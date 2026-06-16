import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' show Offset;

import 'package:image/image.dart' as img;

import '../models/detected_point.dart';
import 'base3_codec.dart';

/// A detected LED candidate: a brightness peak in the max-projection signal.
/// [reach] is how far to sample colour around it (capped at half the distance
/// to the nearest other peak, so neighbouring LEDs don't bleed into the read).
class _Peak {
  final int x;
  final int y;
  final int signal;
  int reach;
  _Peak(this.x, this.y, this.signal, this.reach);
}

class _Candidate {
  final double normX;
  final double normY;
  final int signal;
  const _Candidate(this.normX, this.normY, this.signal);
}

/// Result of a base-3 decode: the per-pixel points plus how many distinct LED
/// peaks were found (a diagnostic: peaks far below the pixel count means the
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
/// Because every LED is lit in every frame, a single bright "blob" mask would
/// merge adjacent LEDs, so we instead find every brightness *peak* (each LED is
/// a local maximum), read its colour per frame, and match the colour sequence
/// to the nearest valid codeword.
class Base3Scanner {
  /// Detection signal (max RGB channel, ambient-subtracted) threshold.
  final int detectThreshold;

  /// A pixel is a peak candidate if no neighbour within this radius is brighter.
  final int peakWindow;

  /// Minimum half-size of the colour-sampling window around a peak.
  final int sampleRadius;

  /// Hard cap on the colour-sampling window, so an isolated bloomed LED reads
  /// its coloured halo without an unbounded scan.
  final int maxColorReach;

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
    this.peakWindow = 1,
    this.sampleRadius = 2,
    this.maxColorReach = 8,
    this.chromaFloor = 12,
    this.confidenceRatio = 1.25,
    this.analyzeWidth = 1280,
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

    // 2. Find LED peaks (local maxima) and cap each one's colour-sampling reach
    //    at half the gap to its nearest neighbour.
    final peaks = _findPeaks(signal, w, h);

    // The valid codewords, regenerated exactly as the scan side drove them, as
    // digit lists. Decoding by nearest codeword (with erasures) lets a peak
    // with one bad or unreadable frame still resolve, instead of being dropped.
    final bits = Base3Codec.bitsFor(numPixels);
    final codes = List<List<int>>.generate(numPixels, (j) {
      final s = Base3Codec.encode(j + 1, bits);
      return List<int>.generate(s.length, (i) => s.codeUnitAt(i) - 0x30);
    });

    // 3. Read each peak's colour sequence and match it to a pixel.
    final best = <int, _Candidate>{};
    for (final p in peaks) {
      final read = [for (final f in frames) _dominantDigit(f, p, signal, w)];
      final pixel = _matchCodeword(read, codes);
      if (pixel < 1 || pixel > numPixels) continue;
      // On duplicate decode, keep the brighter peak.
      final cand = _Candidate(p.x / w, p.y / h, p.signal);
      final prev = best[pixel];
      if (prev == null || cand.signal > prev.signal) best[pixel] = cand;
    }

    best.forEach((pixel, cand) {
      final point = points[pixel - 1];
      point.screenXY = Offset(cand.normX, cand.normY);
      point.brightness = 255;
    });
    return Base3ScanResult(points, peaks.length);
  }

  static int _maxChannel(img.Pixel p) {
    final r = p.r.toInt();
    final g = p.g.toInt();
    final b = p.b.toInt();
    return max(r, max(g, b));
  }

  /// Finds one LED peak per local-maximum region. Every pixel that no neighbour
  /// outshines is flagged; connected flagged pixels (a flat bright core) collapse
  /// to a single peak at their centroid. Each peak's colour-sampling reach is
  /// then capped at half the distance to its nearest neighbour, so adjacent LEDs
  /// never bleed into one another's colour read.
  List<_Peak> _findPeaks(Uint8List signal, int w, int h) {
    final isMax = Uint8List(w * h);
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final s = signal[y * w + x];
        if (s < detectThreshold) continue;
        var peak = true;
        for (var dy = -peakWindow; dy <= peakWindow && peak; dy++) {
          for (var dx = -peakWindow; dx <= peakWindow; dx++) {
            final nx = x + dx, ny = y + dy;
            if (nx < 0 || ny < 0 || nx >= w || ny >= h) continue;
            if (signal[ny * w + nx] > s) {
              peak = false;
              break;
            }
          }
        }
        if (peak) isMax[y * w + x] = 1;
      }
    }

    // Connected components over the local-max mask -> one peak per region.
    final visited = Uint8List(w * h);
    final peaks = <_Peak>[];
    final queue = <int>[];
    for (var start = 0; start < isMax.length; start++) {
      if (visited[start] == 1 || isMax[start] == 0) continue;
      visited[start] = 1;
      queue
        ..clear()
        ..add(start);
      var sumX = 0, sumY = 0, count = 0, peakSig = 0;
      while (queue.isNotEmpty) {
        final idx = queue.removeLast();
        final x = idx % w, y = idx ~/ w;
        sumX += x;
        sumY += y;
        count++;
        if (signal[idx] > peakSig) peakSig = signal[idx];
        for (var dy = -1; dy <= 1; dy++) {
          for (var dx = -1; dx <= 1; dx++) {
            if (dx == 0 && dy == 0) continue;
            final nx = x + dx, ny = y + dy;
            if (nx < 0 || ny < 0 || nx >= w || ny >= h) continue;
            final nidx = ny * w + nx;
            if (visited[nidx] == 1 || isMax[nidx] == 0) continue;
            visited[nidx] = 1;
            queue.add(nidx);
          }
        }
      }
      peaks.add(_Peak(
          (sumX / count).round(), (sumY / count).round(), peakSig, sampleRadius));
    }

    // Reach = half the distance to the nearest other peak (clamped), so the
    // colour sample stays on this LED even when neighbours are close.
    for (final p in peaks) {
      var nearest = 1 << 30;
      for (final o in peaks) {
        if (identical(o, p)) continue;
        final ddx = o.x - p.x, ddy = o.y - p.y;
        final d2 = ddx * ddx + ddy * ddy;
        if (d2 < nearest) nearest = d2;
      }
      final half = (sqrt(nearest) / 2).floor();
      p.reach = half.clamp(sampleRadius, maxColorReach);
    }
    return peaks;
  }

  /// Classifies a peak's colour in frame [f] as a base-3 digit (0=R,1=G,2=B),
  /// or -1 (erasure) if no sample is colourful enough or the vote is too close.
  ///
  /// Each sample votes by *chroma* — its channel value minus the per-pixel
  /// minimum — which discards the white/grey component, so a centre blown out
  /// to white (the coloured halo still votes) and an auto white-balance tint
  /// don't fool it.
  int _dominantDigit(img.Image f, _Peak p, Uint8List signal, int w) {
    final reach = p.reach;
    var vr = 0, vg = 0, vb = 0;
    for (var dy = -reach; dy <= reach; dy++) {
      for (var dx = -reach; dx <= reach; dx++) {
        final x = p.x + dx;
        final y = p.y + dy;
        if (x < 0 || y < 0 || x >= f.width || y >= f.height) continue;
        // Only sample LED pixels (bright in the max-projection); skip the
        // background, whose colour may be tinted by the camera white-balance.
        if (signal[y * w + x] < detectThreshold) continue;
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
}
