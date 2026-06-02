import 'package:flutter_test/flutter_test.dart';
import 'package:pixel_mapper/services/base3_codec.dart';

void main() {
  group('Base3Codec.bitsFor', () {
    test('matches xLights GetBits (digits + 2 checksum)', () {
      expect(Base3Codec.bitsFor(3), 4); // 3->1->0 = 2 digits + 2
      expect(Base3Codec.bitsFor(50), 6); // 50 needs 4 base-3 digits + 2
      expect(Base3Codec.bitsFor(500), 8); // 500 needs 6 digits + 2
    });
  });

  group('Base3Codec.encode', () {
    test('encodes known values matching xLights convertToBase3', () {
      // pixel 1, 8 digits: base3(1)="1", checks 1,2 -> "112", pad -> "00000112".
      expect(Base3Codec.encode(1, 8), '00000112');
      // pixel 3: base3="10" (sum1) check1=1 check2=2 -> "1012", pad8.
      expect(Base3Codec.encode(3, 8), '00001012');
    });

    test('length always equals bits', () {
      for (final n in [1, 7, 42, 170, 499]) {
        expect(Base3Codec.encode(n, 8).length, 8);
      }
    });
  });

  group('Base3Codec round-trip', () {
    test('encode then decode recovers every pixel index', () {
      const numPixels = 500;
      final bits = Base3Codec.bitsFor(numPixels);
      for (var n = 1; n <= numPixels; n++) {
        expect(Base3Codec.decode(Base3Codec.encode(n, bits)), n,
            reason: 'pixel $n');
      }
    });
  });

  group('Base3Codec checksum', () {
    test('rejects a single-digit misread', () {
      const bits = 8;
      final good = Base3Codec.encode(123, bits); // body digits, valid checksum
      // Flip the first body digit to an adjacent value -> checksum should fail.
      final firstDigit = good.codeUnitAt(0) - 0x30;
      final bad = '${(firstDigit + 1) % 3}${good.substring(1)}';
      expect(Base3Codec.decode(bad), isNull);
    });

    test('rejects out-of-range digits', () {
      expect(Base3Codec.decode('00000142'), isNull); // contains a 4
    });
  });
}
