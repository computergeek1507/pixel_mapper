import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:pixel_mapper/services/base3_codec.dart';
import 'package:pixel_mapper/services/base3_scanner.dart';

/// Renders the base-3 capture for [positions] (nodeIndex -> centre), one frame
/// per base-3 digit, colouring each pixel by its digit (0=R,1=G,2=B).
List<img.Image> _makeFrames(
  int numPixels,
  Map<int, Offset> positions, {
  int w = 320,
  int h = 240,
  int ambient = 4,
  int radius = 4,
}) {
  final bits = Base3Codec.bitsFor(numPixels);
  final codes = {
    for (final e in positions.entries) e.key: Base3Codec.encode(e.key + 1, bits)
  };
  final frames = <img.Image>[];
  for (var i = 0; i < bits; i++) {
    final im = img.Image(width: w, height: h);
    img.fill(im, color: img.ColorRgb8(ambient, ambient, ambient));
    positions.forEach((node, pos) {
      final d = codes[node]!.codeUnitAt(i) - 0x30;
      final c = Base3Codec.colorForDigit(d);
      img.fillCircle(im,
          x: pos.dx.round(),
          y: pos.dy.round(),
          radius: radius,
          color: img.ColorRgb8(c.r, c.g, c.b));
    });
    frames.add(im);
  }
  return frames;
}

void main() {
  test('decodes pixel positions from a base-3 RGB capture', () {
    const numPixels = 20;
    final positions = {
      0: const Offset(40, 40),
      5: const Offset(160, 60),
      12: const Offset(250, 180),
      19: const Offset(80, 200), // pixel 20 == numPixels (boundary)
    };
    final frames = _makeFrames(numPixels, positions);
    // ceil(log3(20)) + 2 = 3 + 2 = 5 frames for 20 pixels.
    expect(frames.length, 5);

    const scanner = Base3Scanner();
    final points = scanner.decodeImages(frames, null, numPixels);

    for (final e in positions.entries) {
      final p = points[e.key];
      expect(p.detected, isTrue, reason: 'node ${e.key}');
      expect(p.screenXY!.dx, closeTo(e.value.dx / 320, 0.03));
      expect(p.screenXY!.dy, closeTo(e.value.dy / 240, 0.03));
    }
    // A pixel that was never placed stays undetected.
    expect(points[1].detected, isFalse);
    expect(points[7].detected, isFalse);
  });

  test('scales: 200 pixels identified in 7 frames', () {
    const numPixels = 200;
    // Lay pixels on a coarse grid so blobs don't overlap.
    final positions = <int, Offset>{};
    var n = 0;
    for (var row = 0; row < 10 && n < numPixels; row++) {
      for (var col = 0; col < 20 && n < numPixels; col++) {
        positions[n] = Offset(20 + col * 30.0, 20 + row * 56.0);
        n++;
      }
    }
    final frames =
        _makeFrames(numPixels, positions, w: 640, h: 600, radius: 4);
    // ceil(log3(200)) + 2 = 5 + 2 = 7 frames for 200 pixels.
    expect(frames.length, 7);

    const scanner = Base3Scanner();
    final points = scanner.decodeImages(frames, null, numPixels);

    final detected = points.where((p) => p.detected).length;
    // Allow a tiny margin for any blob-merge edge cases.
    expect(detected, greaterThanOrEqualTo(numPixels - 2));
  });
}
