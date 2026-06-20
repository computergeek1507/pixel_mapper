import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:pixel_mapper/services/base3_codec.dart';
import 'package:pixel_mapper/services/base3_scanner.dart';

// Deterministic pseudo-noise so the test is reproducible.
int _noise(int a, int b) => (((a * 73856093) ^ (b * 19349663)) & 0xff) - 128;

/// Builds a realistic synthetic base-3 capture of [n] LEDs and returns the
/// stills (framesPerState per base-3 frame) plus the ambient reference.
({List<img.Image> frames, img.Image ref}) _simulate(
  int n, {
  int w = 1280,
  int h = 720,
  int repeats = 3,
  double sigma = 3.0, // defocus blur
  int coreR = 7,
  double castScale = 0.3, // per-frame white-balance drift
  int noiseAmp = 6,
  Set<int> badFrames = const {2}, // out-of-focus frames
  double breatheAmp = 0.0, // focus-breathing scale (±) per frame
}) {
  // Grid of LEDs filling most of the frame, well separated.
  final positions = <int, List<int>>{};
  const cols = 20, rows = 10;
  final dx = (w - 200) ~/ (cols - 1), dy = (h - 160) ~/ (rows - 1);
  var idx = 0;
  for (var r = 0; r < rows && idx < n; r++) {
    for (var c = 0; c < cols && idx < n; c++) {
      positions[idx] = [100 + c * dx, 80 + r * dy];
      idx++;
    }
  }

  final bits = Base3Codec.bitsFor(n);
  final codes = {
    for (final e in positions.entries) e.key: Base3Codec.encode(e.key + 1, bits)
  };

  img.Image ambient() {
    final im = img.Image(width: w, height: h);
    img.fill(im, color: img.ColorRgb8(10, 8, 6));
    return im;
  }

  final frames = <img.Image>[];
  for (var s = 0; s < bits; s++) {
    final castR = (20 + (s * 7) % 25) * castScale;
    final castG = (10 + (s * 5) % 20) * castScale;
    final bad = badFrames.contains(s);
    final sig = bad ? sigma * 2.2 : sigma;
    final rad = (bad ? coreR + 6 : coreR) + 3;
    // Focus breathing: this frame's image is scaled slightly about centre.
    final scale = 1 + breatheAmp * (((bits == 1 ? 0.0 : s / (bits - 1)) - 0.5) * 2);
    final cx = w / 2, cy = h / 2;
    for (var k = 0; k < repeats; k++) {
      final im = ambient();
      positions.forEach((node, p) {
        final d = codes[node]!.codeUnitAt(s) - 0x30;
        final col = Base3Codec.colorForDigit(d);
        final px = (cx + (p[0] - cx) * scale).round();
        final py = (cy + (p[1] - cy) * scale).round();
        for (var ddy = -rad; ddy <= rad; ddy++) {
          for (var ddx = -rad; ddx <= rad; ddx++) {
            final x = px + ddx, y = py + ddy;
            if (x < 0 || y < 0 || x >= w || y >= h) continue;
            final inten = exp(-(ddx * ddx + ddy * ddy) / (2 * sig * sig));
            if (inten < 0.04) continue;
            final ns = _noise(x * 7 + k, y * 7 + s) * noiseAmp ~/ 128;
            final rr = (col.r * inten + castR + ns).clamp(0, 255).toInt();
            final gg = (col.g * inten + castG + ns).clamp(0, 255).toInt();
            final bb = (col.b * inten + ns).clamp(0, 255).toInt();
            final cur = im.getPixel(x, y); // max-blend (neighbour overlap)
            im.setPixelRgb(x, y, max(cur.r.toInt(), rr), max(cur.g.toInt(), gg),
                max(cur.b.toInt(), bb));
          }
        }
      });
      frames.add(im);
    }
  }
  return (frames: frames, ref: ambient());
}

void main() {
  test('realistic 200-LED fast capture decodes nearly all', () {
    const n = 200;
    const repeats = 3;
    final sim = _simulate(n, repeats: repeats);
    final result =
        const Base3Scanner().decodeImages(sim.frames, sim.ref, n, repeats);
    final detected = result.points.where((p) => p.detected).length;
    // ignore: avoid_print
    print('SIM detected=$detected blobsSeen=${result.blobsFound} of $n');
    expect(detected, greaterThanOrEqualTo(196),
        reason: 'detected $detected / $n (blobs ${result.blobsFound})');
  });

  test('harsh capture: two out-of-focus frames still mostly decodes', () {
    const n = 200;
    const repeats = 3;
    final sim = _simulate(n,
        repeats: repeats, badFrames: {1, 4}, noiseAmp: 10, sigma: 3.5);
    final result =
        const Base3Scanner().decodeImages(sim.frames, sim.ref, n, repeats);
    final detected = result.points.where((p) => p.detected).length;
    // ignore: avoid_print
    print('HARSH detected=$detected blobsSeen=${result.blobsFound} of $n');
    expect(detected, greaterThanOrEqualTo(190),
        reason: 'detected $detected / $n (blobs ${result.blobsFound})');
  });

  test('focus breathing: registration ghosts, stabilize-off recovers', () {
    const n = 200;
    const repeats = 3;
    final sim = _simulate(n, repeats: repeats, breatheAmp: 0.03);

    // Registration on: a mounted, breathing camera ghosts each LED.
    final withReg =
        const Base3Scanner().decodeImages(sim.frames, sim.ref, n, repeats);
    // Registration off (Stabilize toggle off): should be clean.
    final noReg = const Base3Scanner()
        .decodeImages(sim.frames, sim.ref, n, repeats, null, false, 60, false);
    final dReg = withReg.points.where((p) => p.detected).length;
    final dNo = noReg.points.where((p) => p.detected).length;
    // ignore: avoid_print
    print('BREATHE reg: det=$dReg seen=${withReg.blobsFound} | '
        'noReg: det=$dNo seen=${noReg.blobsFound}');
    expect(dNo, greaterThanOrEqualTo(196),
        reason: 'stabilize-off should decode nearly all ($dNo)');
  });
}
