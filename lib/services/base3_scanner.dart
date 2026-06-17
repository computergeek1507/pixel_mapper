import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' show Offset;

import 'package:image/image.dart' as img;

import '../models/detected_point.dart';
import 'base3_codec.dart';

/// One detected bright region (an LED, or a cluster of touching LEDs). Holds the
/// pixel indices that make it up so colour can be read over exactly those
/// pixels — no background, no neighbouring LED.
class _Blob {
  final double cx;
  final double cy;
  final List<int> pixels; // indices into the w*h signal map
  _Blob(this.cx, this.cy, this.pixels);
  int get area => pixels.length;
}

class _Candidate {
  final double normX;
  final double normY;
  final int area;
  const _Candidate(this.normX, this.normY, this.area);
}

/// Result of a base-3 decode: the per-pixel points plus how many distinct bright
/// regions were found (a diagnostic: regions far below the pixel count means the
/// camera can't separate the LEDs, not that decoding failed).
class Base3ScanResult {
  final List<DetectedPoint> points;
  final int blobsFound;
  const Base3ScanResult(this.points, this.blobsFound);
}

/// Decodes a base-3 RGB capture (the xLights "non-linear pixel pattern") into
/// per-pixel positions. Every pixel is lit in every frame; in frame `i` it
/// shows the colour of the i-th base-3 digit of its index.
///
/// We find each bright region (connected component of the ambient-subtracted
/// max-projection), read its colour over its own pixels in every frame, and
/// match the colour sequence to the nearest valid codeword.
class Base3Scanner {
  /// Detection signal (max RGB channel, ambient-subtracted) threshold.
  final int detectThreshold;

  /// Minimum connected-component area (analyzed px) to count as an LED, so
  /// sensor speckle doesn't register as a pixel.
  final int minBlobArea;

  /// Minimum per-pixel chroma (dominant channel minus the channel minimum) for
  /// a sample to vote on the colour. Filters out white/grey bloom and ambient
  /// so they can't be misclassified as a colour.
  final int chromaFloor;

  /// The winning colour vote must beat the runner-up by at least this ratio,
  /// otherwise the frame is read as an *erasure* (unknown). An erasure is
  /// recoverable by the codeword matcher; a confident wrong guess often isn't.
  final double confidenceRatio;

  /// Frames wider than this are downscaled before analysis. Higher values keep
  /// densely-packed LEDs separable at the cost of more work.
  final int analyzeWidth;

  const Base3Scanner({
    this.detectThreshold = 50,
    this.minBlobArea = 3,
    this.chromaFloor = 12,
    this.confidenceRatio = 1.25,
    this.analyzeWidth = 1920,
  });

  /// Decodes encoded image bytes (one per base-3 frame). Suitable for running
  /// inside `Isolate.run`.
  Base3ScanResult decodeBytes(
    List<Uint8List> frameBytes,
    Uint8List? referenceBytes,
    int numPixels,
  ) {
    final frames = <img.Image>[];
    for (final b in frameBytes) {
      final decoded = img.decodeImage(b);
      if (decoded == null) {
        return Base3ScanResult(
            List.generate(numPixels, (i) => DetectedPoint(nodeIndex: i)), 0);
      }
      frames.add(decoded.width > analyzeWidth
          ? img.copyResize(decoded, width: analyzeWidth)
          : decoded);
    }
    img.Image? ref;
    if (referenceBytes != null && frames.isNotEmpty) {
      final r = img.decodeImage(referenceBytes);
      if (r != null) {
        ref = img.copyResize(r, width: frames[0].width, height: frames[0].height);
      }
    }
    return decodeImages(frames, ref, numPixels);
  }

  /// Core decode on already-decoded frames. Exposed for unit testing.
  Base3ScanResult decodeImages(
    List<img.Image> frames,
    img.Image? reference,
    int numPixels,
  ) {
    final points =
        List.generate(numPixels, (i) => DetectedPoint(nodeIndex: i));
    if (frames.isEmpty) return Base3ScanResult(points, 0);

    final w = frames.first.width;
    final h = frames.first.height;

    // 1. Max-projection of the max-channel signal across all frames (every
    //    pixel is lit in every frame, so this surfaces them all), minus ambient.
    final signal = Uint8List(w * h);
    for (final f in frames) {
      for (var y = 0; y < h; y++) {
        for (var x = 0; x < w; x++) {
          final p = f.getPixel(x, y);
          final m = _maxChannel(p);
          final idx = y * w + x;
          if (m > signal[idx]) signal[idx] = m;
        }
      }
    }
    if (reference != null) {
      for (var y = 0; y < h; y++) {
        for (var x = 0; x < w; x++) {
          final idx = y * w + x;
          final s = signal[idx] - _maxChannel(reference.getPixel(x, y));
          signal[idx] = s < 0 ? 0 : s;
        }
      }
    }

    // 2. Connected components of the bright mask -> one blob per LED (or per
    //    touching cluster). Robust to in-LED sensor noise, which would shatter
    //    a peak-based detector.
    final blobs = _connectedComponents(signal, w, h);

    // The valid codewords, regenerated exactly as the scan side drove them, as
    // digit lists. Decoding by nearest codeword (with erasures) lets a blob
    // with one bad or unreadable frame still resolve, instead of being dropped.
    final bits = Base3Codec.bitsFor(numPixels);
    final codes = List<List<int>>.generate(numPixels, (j) {
      final s = Base3Codec.encode(j + 1, bits);
      return List<int>.generate(s.length, (i) => s.codeUnitAt(i) - 0x30);
    });

    // 3. Read every blob's colour sequence (digits, -1 = erasure).
    final reads = [
      for (final b in blobs) [for (final f in frames) _dominantDigit(f, b, w)]
    ];

    // Auto-detect colour order: the camera sees R/G/B permuted if the LEDs use a
    // non-RGB byte order (WS2811 is often GRB). Try all six permutations of the
    // observed digits and keep whichever decodes the most blobs — no need for
    // the user to get the colour-order setting right for the scan to work.
    const perms = [
      [0, 1, 2],
      [0, 2, 1],
      [1, 0, 2],
      [1, 2, 0],
      [2, 0, 1],
      [2, 1, 0],
    ];
    var bestPixels = const <int>[];
    var bestCount = -1;
    for (final perm in perms) {
      final pixels = List<int>.filled(reads.length, -1);
      var count = 0;
      for (var bi = 0; bi < reads.length; bi++) {
        final permuted = [for (final d in reads[bi]) d < 0 ? -1 : perm[d]];
        final px = _matchCodeword(permuted, codes);
        pixels[bi] = px;
        if (px >= 1 && px <= numPixels) count++;
      }
      if (count > bestCount) {
        bestCount = count;
        bestPixels = pixels;
      }
    }

    // Keep the largest blob per decoded pixel.
    final best = <int, _Candidate>{};
    for (var bi = 0; bi < blobs.length; bi++) {
      final pixel = bestPixels[bi];
      if (pixel < 1 || pixel > numPixels) continue;
      final b = blobs[bi];
      final cand = _Candidate(b.cx / w, b.cy / h, b.area);
      final prev = best[pixel];
      if (prev == null || cand.area > prev.area) best[pixel] = cand;
    }

    best.forEach((pixel, cand) {
      final point = points[pixel - 1];
      point.screenXY = Offset(cand.normX, cand.normY);
      point.brightness = 255;
    });
    return Base3ScanResult(points, blobs.length);
  }

  static int _maxChannel(img.Pixel p) {
    final r = p.r.toInt();
    final g = p.g.toInt();
    final b = p.b.toInt();
    return max(r, max(g, b));
  }

  /// Classifies blob [b]'s colour in frame [f] as a base-3 digit (0=R,1=G,2=B),
  /// or -1 (erasure) if no sample is colourful enough or the vote is too close.
  ///
  /// Votes over the blob's own pixels by *chroma* — each channel minus the
  /// per-pixel minimum — which discards the white/grey component, so a centre
  /// blown out to white still reads (its coloured edge votes) and the camera's
  /// auto white-balance tinting the frame doesn't fool it.
  int _dominantDigit(img.Image f, _Blob b, int w) {
    var vr = 0, vg = 0, vb = 0;
    for (final idx in b.pixels) {
      final x = idx % w, y = idx ~/ w;
      final px = f.getPixel(x, y);
      final r = px.r.toInt();
      final g = px.g.toInt();
      final b0 = px.b.toInt();
      final m = min(r, min(g, b0)); // white/grey/ambient component
      final cr = r - m, cg = g - m, cb = b0 - m; // chroma per channel
      final topc = max(cr, max(cg, cb));
      if (topc < chromaFloor) continue; // colourless -> no vote
      if (topc == cr) {
        vr += cr;
      } else if (topc == cg) {
        vg += cg;
      } else {
        vb += cb;
      }
    }
    final top = max(vr, max(vg, vb));
    if (top <= 0) return -1; // nothing colourful enough to classify
    // Read as an erasure unless the winner clearly beats the runner-up.
    final second = (top == vr)
        ? max(vg, vb)
        : (top == vg ? max(vr, vb) : max(vr, vg));
    if (top < second * confidenceRatio) return -1;
    if (top == vr) return 0;
    if (top == vg) return 1;
    return 2;
  }

  /// Matches a per-frame digit read (with -1 for erasures) to the nearest valid
  /// codeword and returns its 1-based pixel number, or -1 if no match is
  /// confident and unambiguous. An erasure costs less than a substitution, so a
  /// single unreadable frame is recoverable; a single wrong frame is only
  /// corrected when one codeword is clearly closest.
  int _matchCodeword(List<int> read, List<List<int>> codes) {
    const erasureCost = 1;
    const substitutionCost = 2;
    const maxAcceptCost = 2; // up to 2 erasures, or 1 substitution
    const minMargin = 2; // runner-up must be clearly worse

    var bestCost = 1 << 30, secondCost = 1 << 30, bestPixel = -1;
    final n = read.length;
    for (var j = 0; j < codes.length; j++) {
      final code = codes[j];
      final len = n < code.length ? n : code.length;
      var cost = 0;
      for (var i = 0; i < len; i++) {
        final r = read[i];
        if (r < 0) {
          cost += erasureCost;
        } else if (r != code[i]) {
          cost += substitutionCost;
        }
        if (cost >= secondCost) break; // can't make the top two
      }
      if (cost < bestCost) {
        secondCost = bestCost;
        bestCost = cost;
        bestPixel = j + 1;
      } else if (cost < secondCost) {
        secondCost = cost;
      }
    }
    if (bestCost > maxAcceptCost) return -1;
    if (secondCost - bestCost < minMargin) return -1; // ambiguous
    return bestPixel;
  }

  /// BFS connected-component labeling over the thresholded signal, collecting
  /// each component's pixels and intensity-weighted centroid.
  List<_Blob> _connectedComponents(Uint8List signal, int w, int h) {
    final visited = Uint8List(w * h);
    final blobs = <_Blob>[];
    final queue = <int>[];
    for (var start = 0; start < signal.length; start++) {
      if (visited[start] == 1 || signal[start] < detectThreshold) continue;
      visited[start] = 1;
      queue
        ..clear()
        ..add(start);
      final pixels = <int>[];
      double sumX = 0, sumY = 0, sumW = 0;
      while (queue.isNotEmpty) {
        final idx = queue.removeLast();
        final x = idx % w, y = idx ~/ w;
        final s = signal[idx];
        pixels.add(idx);
        sumX += x * s;
        sumY += y * s;
        sumW += s;
        for (var dy = -1; dy <= 1; dy++) {
          for (var dx = -1; dx <= 1; dx++) {
            if (dx == 0 && dy == 0) continue;
            final nx = x + dx, ny = y + dy;
            if (nx < 0 || ny < 0 || nx >= w || ny >= h) continue;
            final nidx = ny * w + nx;
            if (visited[nidx] == 1 || signal[nidx] < detectThreshold) continue;
            visited[nidx] = 1;
            queue.add(nidx);
          }
        }
      }
      if (pixels.length >= minBlobArea && sumW > 0) {
        blobs.add(_Blob(sumX / sumW, sumY / sumW, pixels));
      }
    }
    return blobs;
  }
}
