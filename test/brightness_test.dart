import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pixel_mapper/models/pixel_color.dart';
import 'package:pixel_mapper/services/pixel_output.dart';

/// Minimal [PixelOutput] that just holds a buffer (no socket), so the
/// brightness scaling applied by setPixel/setAll can be inspected directly.
class _BufferOutput extends PixelOutput {
  _BufferOutput(int pixels) {
    rgb = Uint8List(pixels * 3);
  }

  Uint8List get buffer => rgb;

  @override
  Future<void> sendFrame() async {}
}

void main() {
  group('PixelOutput.brightness', () {
    test('full brightness writes colours unchanged', () {
      final out = _BufferOutput(1);
      out.setPixel(0, const PixelColor(255, 1, 128));
      expect(out.buffer.sublist(0, 3), [255, 1, 128]);
    });

    test('scales every channel written via setPixel and setAll', () {
      final out = _BufferOutput(2)..brightness = 0.5;
      out.setPixel(0, const PixelColor(255, 100, 0));
      // 255*0.5 = 127.5 -> 128 (round), 100*0.5 = 50, 0 -> 0.
      expect(out.buffer.sublist(0, 3), [128, 50, 0]);

      out.setAll(const PixelColor(200, 200, 200));
      expect(out.buffer.sublist(0, 3), [100, 100, 100]);
      expect(out.buffer.sublist(3, 6), [100, 100, 100]);
    });

    test('clamps to the 0..1 range', () {
      final out = _BufferOutput(1);
      out.brightness = 5.0;
      expect(out.brightness, 1.0);
      out.brightness = -2.0;
      expect(out.brightness, 0.0);
    });
  });
}
