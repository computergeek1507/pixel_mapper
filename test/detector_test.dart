import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:pixel_mapper/services/bright_spot_detector.dart';

img.Image _frame({
  int w = 320,
  int h = 240,
  int ambient = 8,
  List<({int x, int y, int r, int v})> dots = const [],
}) {
  final im = img.Image(width: w, height: h);
  img.fill(im, color: img.ColorRgb8(ambient, ambient, ambient));
  for (final d in dots) {
    img.fillCircle(im,
        x: d.x, y: d.y, radius: d.r, color: img.ColorRgb8(d.v, d.v, d.v));
  }
  return im;
}

void main() {
  group('ImageBrightSpotDetector.detectInImage', () {
    test('locates a single bright dot near its center', () {
      final frame = _frame(dots: [(x: 240, y: 60, r: 6, v: 255)]);
      final spot = ImageBrightSpotDetector.detectInImage(frame);

      expect(spot, isNotNull);
      expect(spot!.normX, closeTo(240 / 320, 0.02));
      expect(spot.normY, closeTo(60 / 240, 0.02));
      expect(spot.brightness, greaterThan(200));
    });

    test('returns null when nothing exceeds minBrightness', () {
      final frame = _frame(ambient: 12); // uniform, dim
      final spot = ImageBrightSpotDetector.detectInImage(frame);
      expect(spot, isNull);
    });

    test('rejects overexposed/glare frames via maxAreaFraction', () {
      // A huge bright blob covering most of the frame.
      final frame = _frame(dots: [(x: 160, y: 120, r: 200, v: 255)]);
      final spot = ImageBrightSpotDetector.detectInImage(frame);
      expect(spot, isNull);
    });

    test('reference subtraction ignores a static ambient hotspot', () {
      // Reference: a bright lamp in the corner.
      final reference = _frame(dots: [(x: 40, y: 40, r: 14, v: 230)]);
      // Frame: same lamp PLUS the real lit pixel elsewhere. The pixel is dimmer
      // than the lamp (below the lamp's blob threshold) so the naive pass picks
      // the lamp; only reference subtraction reveals the pixel.
      final frame = _frame(dots: [
        (x: 40, y: 40, r: 14, v: 230), // lamp, same as reference
        (x: 250, y: 180, r: 5, v: 180), // the pixel we care about
      ]);

      // Without reference, the brighter lamp wins.
      final naive = ImageBrightSpotDetector.detectInImage(frame);
      expect(naive!.normX, closeTo(40 / 320, 0.05));

      // With reference subtraction, the lamp cancels and the pixel is found.
      final corrected =
          ImageBrightSpotDetector.detectInImage(frame, reference: reference);
      expect(corrected, isNotNull);
      expect(corrected!.normX, closeTo(250 / 320, 0.03));
      expect(corrected.normY, closeTo(180 / 240, 0.03));
    });
  });

  test('detect() decodes encoded bytes and finds the dot (isolate path)',
      () async {
    final frame = _frame(dots: [(x: 200, y: 100, r: 6, v: 255)]);
    final png = img.encodePng(frame);

    const detector = ImageBrightSpotDetector();
    final spot = await detector.detect(png);

    expect(spot, isNotNull);
    expect(spot!.normX, closeTo(200 / 320, 0.03));
    expect(spot.normY, closeTo(100 / 240, 0.03));
  });
}
