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

  /// Frames wider than this are downscaled before analysis.
  final int analyzeWidth;

  const Base3Scanner({
    this.detectThreshold = 50,
    this.minBlobArea = 2,
    this.sampleRadius = 2,
    this.chromaFloor = 12,
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

    // 2. Threshold + connected components -> blob centroids.
    final blobs = _connectedComponents(signal, w, h);

    // 3. Read each blob's colour sequence, decode to a pixel number.
    final best = <int, _Candidate>{};
    for (final b in blobs) {
      final digits = StringBuffer();
      var ok = true;
      for (final f in frames) {
        final d = _dominantDigit(f, b);
        if (d < 0) {
          ok = false;
          break;
        }
        digits.write(d);
      }
      if (!ok) continue;
      final pixel = Base3Codec.decode(digits.toString());
      if (pixel == null || pixel < 1 || pixel > numPixels) continue;
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
    if (top == vr) return 0;
    if (top == vg) return 1;
    return 2;
  }

  /// BFS connected-component labeling over the thresholded signal.
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
            if (visited[nidx] == 1 || signal[nidx] < detectThreshold) continue;
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
