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

/// A per-frame shift field on a [g]x[g] grid (full-resolution px), used to undo
/// camera drift. Block lookup for the dense pass; bilinear for per-blob reads.
class _ShiftField {
  final int g;
  final int w;
  final int h;
  final List<int> dxs; // g*g
  final List<int> dys; // g*g
  const _ShiftField(this.g, this.w, this.h, this.dxs, this.dys);

  int _bx(int x) => ((x * g) ~/ w).clamp(0, g - 1);
  int _by(int y) => ((y * g) ~/ h).clamp(0, g - 1);

  int blockDx(int x, int y) => dxs[_by(y) * g + _bx(x)];
  int blockDy(int x, int y) => dys[_by(y) * g + _bx(x)];

  /// Bilinear-interpolated [dx, dy] at full-res (x, y).
  List<int> at(int x, int y) {
    final gxf = ((x + 0.5) / w * g - 0.5).clamp(0.0, (g - 1).toDouble());
    final gyf = ((y + 0.5) / h * g - 0.5).clamp(0.0, (g - 1).toDouble());
    final x0 = gxf.floor(), y0 = gyf.floor();
    final x1 = (x0 + 1).clamp(0, g - 1), y1 = (y0 + 1).clamp(0, g - 1);
    final fx = gxf - x0, fy = gyf - y0;
    double bil(List<int> v) {
      final a = v[y0 * g + x0] + (v[y0 * g + x1] - v[y0 * g + x0]) * fx;
      final b = v[y1 * g + x0] + (v[y1 * g + x1] - v[y1 * g + x0]) * fx;
      return a + (b - a) * fy;
    }

    return [bil(dxs).round(), bil(dys).round()];
  }
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

  /// Width the brightness maps are downscaled to for frame registration (camera
  /// drift estimation). Smaller is faster; the shift is scaled back to full res.
  final int alignWidth;

  /// Frame registration uses a [registerGrid] x [registerGrid] grid of regional
  /// shifts (interpolated into a smooth field), so handheld rotation/tilt — not
  /// just translation — is compensated.
  final int registerGrid;

  const Base3Scanner({
    this.detectThreshold = 50,
    this.minBlobArea = 3,
    this.chromaFloor = 6,
    // 1.0 = trust the dominant chroma channel (only erase a truly colourless
    // frame). Real R/G/B LEDs often read with a strong secondary channel
    // (e.g. orange-ish red), so a higher ratio erased correct reads.
    this.confidenceRatio = 1.0,
    this.analyzeWidth = 1920,
    this.alignWidth = 480,
    this.registerGrid = 4,
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

    // 0. Register frames: the camera drifts between the sequential photos
    //    (handheld), so estimate each frame's pixel shift relative to frame 0.
    //    Without this, a fixed read position lands on a neighbouring LED in
    //    later frames and the colour sequence is garbage.
    final fields = _estimateShiftFields(frames, w, h);

    // 1. Aligned max-projection of the max-channel signal across all frames
    //    (every pixel is lit in every frame, so this surfaces them all), minus
    //    ambient. Each frame is sampled at its registered offset.
    final signal = Uint8List(w * h);
    for (var fi = 0; fi < frames.length; fi++) {
      final f = frames[fi];
      final field = fields[fi];
      for (var y = 0; y < h; y++) {
        for (var x = 0; x < w; x++) {
          final xi = x + field.blockDx(x, y);
          final yi = y + field.blockDy(x, y);
          if (xi < 0 || yi < 0 || xi >= w || yi >= h) continue;
          final m = _maxChannel(f.getPixel(xi, yi));
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

    // 3. Read every blob's colour sequence (digits, -1 = erasure), sampling
    //    each frame at the blob's registered position for that frame.
    final reads = [
      for (final b in blobs)
        [
          for (var fi = 0; fi < frames.length; fi++)
            () {
              final s = fields[fi].at(b.cx.round(), b.cy.round());
              return _dominantDigit(frames[fi], b, w, s[0], s[1]);
            }()
        ]
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

  /// Estimates a per-frame shift field (camera drift during the handheld
  /// capture). Frame 0 is the reference (zero field). For every other frame a
  /// global shift is found first, then a regional shift per grid block, falling
  /// back to the global one where a block has too little signal or aligns
  /// poorly. Interpolating the grid yields a smooth field that follows
  /// translation and rotation/tilt.
  List<_ShiftField> _estimateShiftFields(List<img.Image> frames, int w, int h) {
    final g = registerGrid;
    final n = frames.length;
    final fields = <_ShiftField>[
      _ShiftField(g, w, h, List.filled(g * g, 0), List.filled(g * g, 0))
    ];
    if (n <= 1) return fields;

    final dw = w > alignWidth ? alignWidth : w;
    final factor = w / dw;
    final dh = (h / factor).round().clamp(1, h);
    final maps = <Uint8List>[];
    for (final f in frames) {
      final small =
          (f.width > dw) ? img.copyResize(f, width: dw, height: dh) : f;
      final m = Uint8List(dw * dh);
      for (var y = 0; y < dh; y++) {
        final sy = y < small.height ? y : small.height - 1;
        for (var x = 0; x < dw; x++) {
          final sx = x < small.width ? x : small.width - 1;
          m[y * dw + x] = _maxChannel(small.getPixel(sx, sy));
        }
      }
      maps.add(m);
    }

    final ref = maps[0];
    for (var i = 1; i < n; i++) {
      final gl = _stepSearchWin(maps[i], ref, dw, dh, 0, 0, dw, dh, 0, 0);
      final globalRes =
          _meanAbsDiffWin(maps[i], ref, dw, dh, 0, 0, dw, dh, gl[0], gl[1]);
      final dxs = List.filled(g * g, 0), dys = List.filled(g * g, 0);
      for (var by = 0; by < g; by++) {
        for (var bx = 0; bx < g; bx++) {
          final x0 = bx * dw ~/ g, x1 = (bx + 1) * dw ~/ g;
          final y0 = by * dh ~/ g, y1 = (by + 1) * dh ~/ g;
          var s = gl;
          if (_blockEnergy(ref, dw, x0, y0, x1, y1) >= detectThreshold) {
            final cand = _stepSearchWin(
                maps[i], ref, dw, dh, x0, y0, x1, y1, gl[0], gl[1]);
            final res =
                _meanAbsDiffWin(maps[i], ref, dw, dh, x0, y0, x1, y1, cand[0], cand[1]);
            if (res <= globalRes * 1.5 + 4) s = cand;
          }
          dxs[by * g + bx] = (s[0] * factor).round();
          dys[by * g + bx] = (s[1] * factor).round();
        }
      }
      fields.add(_ShiftField(g, w, h, dxs, dys));
    }
    return fields;
  }

  /// Logarithmic (diamond) search over a window for the [dx, dy] minimizing
  /// mean abs difference between [m] shifted and [ref]. Starts from a seed.
  List<int> _stepSearchWin(Uint8List m, Uint8List ref, int dw, int dh, int x0,
      int y0, int x1, int y1, int seedX, int seedY) {
    var bx = seedX, by = seedY;
    var best = _meanAbsDiffWin(m, ref, dw, dh, x0, y0, x1, y1, bx, by);
    const dirs = [
      [1, 0], [-1, 0], [0, 1], [0, -1],
      [1, 1], [1, -1], [-1, 1], [-1, -1], //
    ];
    for (var step = 16; step >= 1; step ~/= 2) {
      var improved = true;
      while (improved) {
        improved = false;
        for (final d in dirs) {
          final nx = bx + d[0] * step, ny = by + d[1] * step;
          final c = _meanAbsDiffWin(m, ref, dw, dh, x0, y0, x1, y1, nx, ny);
          if (c < best) {
            best = c;
            bx = nx;
            by = ny;
            improved = true;
          }
        }
      }
    }
    return [bx, by];
  }

  /// Mean absolute difference over window [x0,x1)x[y0,y1) of [m] shifted by
  /// ([dx],[dy]) against [ref], normalized over the overlap.
  double _meanAbsDiffWin(Uint8List m, Uint8List ref, int dw, int dh, int x0,
      int y0, int x1, int y1, int dx, int dy) {
    var sum = 0, cnt = 0;
    for (var y = y0; y < y1; y++) {
      final yi = y + dy;
      if (yi < 0 || yi >= dh) continue;
      for (var x = x0; x < x1; x++) {
        final xi = x + dx;
        if (xi < 0 || xi >= dw) continue;
        sum += (m[yi * dw + xi] - ref[y * dw + x]).abs();
        cnt++;
      }
    }
    final area = (x1 - x0) * (y1 - y0);
    if (cnt < area ~/ 4) return 1e9; // too little overlap to trust
    return sum / cnt;
  }

  /// Mean brightness of [ref] over a block — used to skip near-dark blocks.
  double _blockEnergy(Uint8List ref, int dw, int x0, int y0, int x1, int y1) {
    var sum = 0, cnt = 0;
    for (var y = y0; y < y1; y++) {
      for (var x = x0; x < x1; x++) {
        sum += ref[y * dw + x];
        cnt++;
      }
    }
    return cnt > 0 ? sum / cnt : 0;
  }

  /// Classifies blob [b]'s colour in frame [f] as a base-3 digit (0=R,1=G,2=B),
  /// or -1 (erasure) if no sample is colourful enough or the vote is too close.
  ///
  /// Votes over the blob's own pixels by *chroma* — each channel minus the
  /// per-pixel minimum — which discards the white/grey component, so a centre
  /// blown out to white still reads (its coloured edge votes) and the camera's
  /// auto white-balance tinting the frame doesn't fool it.
  int _dominantDigit(img.Image f, _Blob b, int w, int sx, int sy) {
    var vr = 0, vg = 0, vb = 0;
    for (final idx in b.pixels) {
      final x = idx % w + sx, y = idx ~/ w + sy;
      if (x < 0 || y < 0 || x >= f.width || y >= f.height) continue;
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
    const maxAcceptCost = 3; // e.g. 1 substitution + 1 erasure, or 3 erasures
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
