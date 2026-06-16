import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' show Offset;

import 'package:image/image.dart' as img;

import '../models/detected_point.dart';
import 'base3_codec.dart';

class _Blob {
  final double cx;
  final double cy;
  final int area;
  const _Blob(this.cx, this.cy, this.area);
}

class _Candidate {
  final double normX;
  final double normY;
  final int area;
  const _Candidate(this.normX, this.normY, this.area);
}

/// Decodes a base-3 RGB capture (the xLights "non-linear pixel pattern") into
/// per-pixel positions. Every pixel is lit in every frame; in frame `i` it
/// shows the colour of the i-th base-3 digit of its index. We find every lit
/// blob, read its colour in each frame, and decode the digit string back to a
/// pixel number (rejecting blobs whose checksum fails).
class Base3Scanner {
  /// Detection signal (max RGB channel, ambient-subtracted) threshold.
  final int detectThreshold;

  /// Minimum connected-component area (in analyzed pixels) to count as a blob.
  final int minBlobArea;

  /// Minimum half-size of the colour-sampling window around a blob centroid.
  /// The actual window grows with the blob so it reaches the coloured halo even
  /// when the centre has bloomed to white.
  final int sampleRadius;

  /// Minimum per-pixel chroma (dominant channel minus the channel minimum) for
  /// a sample to vote on the colour. Filters out white/grey bloom and ambient
  /// so they can't be misclassified as a colour.
  final int chromaFloor;

  /// The winning colour vote must beat the runner-up by at least this ratio,
  /// otherwise the frame is read as an *erasure* (unknown). An erasure is
  /// recoverable by the codeword matcher; a confident wrong guess often isn't.
  final double confidenceRatio;

  /// Radius of the morphological closing (dilate then erode) applied to the
  /// blob mask before labeling. Fills small gaps so a single LED that the
  /// pattern fragments into pieces stays one blob. 0 disables it.
  final int morphRadius;

  /// Frames wider than this are downscaled before analysis.
  final int analyzeWidth;

  const Base3Scanner({
    this.detectThreshold = 50,
    this.minBlobArea = 2,
    this.sampleRadius = 2,
    this.chromaFloor = 12,
    this.confidenceRatio = 1.25,
    this.morphRadius = 1,
    this.analyzeWidth = 640,
  });

  /// Decodes encoded image bytes (one per base-3 frame). Suitable for running
  /// inside `Isolate.run`.
  List<DetectedPoint> decodeBytes(
    List<Uint8List> frameBytes,
    Uint8List? referenceBytes,
    int numPixels,
  ) {
    final frames = <img.Image>[];
    for (final b in frameBytes) {
      final decoded = img.decodeImage(b);
      if (decoded == null) {
        return List.generate(numPixels, (i) => DetectedPoint(nodeIndex: i));
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
  List<DetectedPoint> decodeImages(
    List<img.Image> frames,
    img.Image? reference,
    int numPixels,
  ) {
    final points =
        List.generate(numPixels, (i) => DetectedPoint(nodeIndex: i));
    if (frames.isEmpty) return points;

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

    // 2. Threshold -> binary mask -> optional morphological closing -> labels.
    final mask = _maskFromSignal(signal, w, h);
    final blobs = _connectedComponents(mask, w, h);

    // The valid codewords, regenerated exactly as the scan side drove them, as
    // digit lists. Decoding by nearest codeword (with erasures) lets a blob
    // with one bad or unreadable frame still resolve, instead of being dropped.
    final bits = Base3Codec.bitsFor(numPixels);
    final codes = List<List<int>>.generate(numPixels, (j) {
      final s = Base3Codec.encode(j + 1, bits);
      return List<int>.generate(s.length, (i) => s.codeUnitAt(i) - 0x30);
    });

    // 3. Read each blob's colour sequence and match it to a pixel.
    final best = <int, _Candidate>{};
    for (final b in blobs) {
      final read = [for (final f in frames) _dominantDigit(f, b)];
      final pixel = _matchCodeword(read, codes);
      if (pixel < 1 || pixel > numPixels) continue;
      // On duplicate decode, keep the larger blob.
      final cand = _Candidate(b.cx / w, b.cy / h, b.area);
      final prev = best[pixel];
      if (prev == null || cand.area > prev.area) best[pixel] = cand;
    }

    best.forEach((pixel, cand) {
      final point = points[pixel - 1];
      point.screenXY = Offset(cand.normX, cand.normY);
      point.brightness = 255;
    });
    return points;
  }

  static int _maxChannel(img.Pixel p) {
    final r = p.r.toInt();
    final g = p.g.toInt();
    final b = p.b.toInt();
    return max(r, max(g, b));
  }

  /// Classifies blob [b]'s colour in frame [f] as a base-3 digit (0=R,1=G,2=B),
  /// or -1 if no sample is colourful enough to decide.
  ///
  /// Each sample votes by *chroma* — its channel value minus the per-pixel
  /// minimum — which discards the white/grey component. That makes the read
  /// robust to a centre blown out to white (the coloured halo still votes) and
  /// to the camera's auto white-balance tinting the whole frame. The sampling
  /// window grows with the blob so it always reaches that halo.
  int _dominantDigit(img.Image f, _Blob b) {
    final cx = b.cx.round();
    final cy = b.cy.round();
    // Reach roughly to the blob edge (area ~= pi r^2), but at least sampleRadius.
    final reach = max(sampleRadius, (sqrt(b.area / pi)).round());
    var vr = 0, vg = 0, vb = 0;
    for (var dy = -reach; dy <= reach; dy++) {
      for (var dx = -reach; dx <= reach; dx++) {
        final x = cx + dx;
        final y = cy + dy;
        if (x < 0 || y < 0 || x >= f.width || y >= f.height) continue;
        final p = f.getPixel(x, y);
        final r = p.r.toInt();
        final g = p.g.toInt();
        final b0 = p.b.toInt();
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

  /// Thresholds [signal] into a binary mask, then optionally closes it
  /// (dilate then erode) to fill small gaps and consolidate fragmented blobs.
  Uint8List _maskFromSignal(Uint8List signal, int w, int h) {
    final mask = Uint8List(signal.length);
    for (var i = 0; i < signal.length; i++) {
      mask[i] = signal[i] >= detectThreshold ? 1 : 0;
    }
    if (morphRadius <= 0) return mask;
    return _erode(_dilate(mask, w, h, morphRadius), w, h, morphRadius);
  }

  /// Morphological dilation with a square structuring element of [r].
  static Uint8List _dilate(Uint8List m, int w, int h, int r) {
    final out = Uint8List(w * h);
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        var on = 0;
        for (var dy = -r; dy <= r && on == 0; dy++) {
          for (var dx = -r; dx <= r; dx++) {
            final nx = x + dx, ny = y + dy;
            if (nx < 0 || ny < 0 || nx >= w || ny >= h) continue;
            if (m[ny * w + nx] == 1) {
              on = 1;
              break;
            }
          }
        }
        out[y * w + x] = on;
      }
    }
    return out;
  }

  /// Morphological erosion with a square structuring element of [r].
  static Uint8List _erode(Uint8List m, int w, int h, int r) {
    final out = Uint8List(w * h);
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        var keep = 1;
        for (var dy = -r; dy <= r && keep == 1; dy++) {
          for (var dx = -r; dx <= r; dx++) {
            final nx = x + dx, ny = y + dy;
            // Border pixels can't be fully covered -> treat as eroded away.
            if (nx < 0 || ny < 0 || nx >= w || ny >= h || m[ny * w + nx] == 0) {
              keep = 0;
              break;
            }
          }
        }
        out[y * w + x] = keep;
      }
    }
    return out;
  }

  /// BFS connected-component labeling over a binary [mask].
  List<_Blob> _connectedComponents(Uint8List mask, int w, int h) {
    final visited = Uint8List(w * h);
    final blobs = <_Blob>[];
    final queue = <int>[];
    for (var start = 0; start < mask.length; start++) {
      if (visited[start] == 1 || mask[start] == 0) continue;
      visited[start] = 1;
      queue
        ..clear()
        ..add(start);
      var sumX = 0, sumY = 0, count = 0;
      while (queue.isNotEmpty) {
        final idx = queue.removeLast();
        final x = idx % w;
        final y = idx ~/ w;
        sumX += x;
        sumY += y;
        count++;
        for (var dy = -1; dy <= 1; dy++) {
          for (var dx = -1; dx <= 1; dx++) {
            if (dx == 0 && dy == 0) continue;
            final nx = x + dx;
            final ny = y + dy;
            if (nx < 0 || ny < 0 || nx >= w || ny >= h) continue;
            final nidx = ny * w + nx;
            if (visited[nidx] == 1 || mask[nidx] == 0) continue;
            visited[nidx] = 1;
            queue.add(nidx);
          }
        }
      }
      if (count >= minBlobArea) {
        blobs.add(_Blob(sumX / count, sumY / count, count));
      }
    }
    return blobs;
  }
}
