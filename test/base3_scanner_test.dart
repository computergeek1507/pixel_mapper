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
    final points = scanner.decodeImages(frames, null, numPixels).points;

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
    final points = scanner.decodeImages(frames, null, numPixels).points;

    final detected = points.where((p) => p.detected).length;
    // Allow a tiny margin for any blob-merge edge cases.
    expect(detected, greaterThanOrEqualTo(numPixels - 2));
  });

  test('decodes despite a white-balance colour cast on every channel', () {
    // Auto white-balance (exposure is locked but WB isn't) tints the whole
    // frame. A raw max-channel read would skew toward the cast; chroma must not.
    const numPixels = 20;
    final positions = {
      0: const Offset(40, 40),
      5: const Offset(160, 60),
      12: const Offset(250, 180),
    };
    // Warm cast: lift red+green, leaving blue alone, on every pixel — including
    // the black reference frame (same camera, same cast), so the real pipeline's
    // reference subtraction removes the ambient baseline as it would live.
    img.Image warm(img.Image f) =>
        img.colorOffset(f, red: 70, green: 50, blue: 0);
    final cast = _makeFrames(numPixels, positions).map(warm).toList();
    final refRaw = img.Image(width: 320, height: 240);
    img.fill(refRaw, color: img.ColorRgb8(4, 4, 4));
    final ref = warm(refRaw);

    final points = const Base3Scanner().decodeImages(cast, ref, numPixels).points;
    for (final node in positions.keys) {
      expect(points[node].detected, isTrue, reason: 'node $node');
    }
  });

  test('recovers a pixel with one unreadable (erasure) frame', () {
    // Render a normal capture, then wipe one pixel's colour to grey in a single
    // frame so that frame reads as an erasure. The old all-or-nothing decode
    // dropped the pixel; the codeword matcher should still resolve it.
    const numPixels = 20;
    const node = 12;
    const pos = Offset(160, 120);
    final bits = Base3Codec.bitsFor(numPixels);
    final code = Base3Codec.encode(node + 1, bits);
    final frames = <img.Image>[];
    for (var i = 0; i < bits; i++) {
      final im = img.Image(width: 320, height: 240);
      img.fill(im, color: img.ColorRgb8(4, 4, 4));
      // Frame index 1 is colourless grey (an erasure); the rest are the colour.
      final c = i == 1
          ? img.ColorRgb8(120, 120, 120)
          : () {
              final pc = Base3Codec.colorForDigit(code.codeUnitAt(i) - 0x30);
              return img.ColorRgb8(pc.r, pc.g, pc.b);
            }();
      img.fillCircle(im, x: pos.dx.round(), y: pos.dy.round(), radius: 5, color: c);
      frames.add(im);
    }

    final points = const Base3Scanner().decodeImages(frames, null, numPixels).points;
    expect(points[node].detected, isTrue);
  });

  test('decodes a bloomed pixel: white-clipped core with a coloured halo', () {
    // Bright LEDs photographed close up clip to white at the centre; only the
    // halo carries the hue. The colour vote must come from the halo.
    const numPixels = 20;
    const center = Offset(160, 120);
    const node = 5;
    final bits = Base3Codec.bitsFor(numPixels);
    final code = Base3Codec.encode(node + 1, bits);
    final frames = <img.Image>[];
    for (var i = 0; i < bits; i++) {
      final im = img.Image(width: 320, height: 240);
      img.fill(im, color: img.ColorRgb8(3, 3, 3));
      final c = Base3Codec.colorForDigit(code.codeUnitAt(i) - 0x30);
      // Coloured halo (radius 7) then a blown-out white core (radius 3).
      img.fillCircle(im,
          x: center.dx.round(),
          y: center.dy.round(),
          radius: 7,
          color: img.ColorRgb8(c.r, c.g, c.b));
      img.fillCircle(im,
          x: center.dx.round(),
          y: center.dy.round(),
          radius: 3,
          color: img.ColorRgb8(255, 255, 255));
      frames.add(im);
    }

    final points = const Base3Scanner().decodeImages(frames, null, numPixels).points;
    expect(points[node].detected, isTrue);
  });
}
