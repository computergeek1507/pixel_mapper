@Tags(['real'])
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pixel_mapper/services/base3_scanner.dart';

// Loads the real captured frames saved by the app's "Save frames (debug)"
// option and tunes the decoder against them. Run with:
//   flutter test test/real_decode_test.dart --tags real
const _dir =
    r'C:\Users\scoot\AppData\Roaming\com.scooterseh\pixel_mapper\captures';
const _n = 200;
const _repeats = 3;

(List<Uint8List>, Uint8List) _load() {
  final ref = File('$_dir\\ref.png').readAsBytesSync();
  final frames = <Uint8List>[];
  final bits = (() {
    var c = 0, p = _n;
    while (p != 0) {
      p ~/= 3;
      c++;
    }
    return c + 2;
  })();
  for (var s = 0; s < bits; s++) {
    for (var k = 0; k < _repeats; k++) {
      frames.add(File('$_dir\\f_${s}_$k.png').readAsBytesSync());
    }
  }
  return (frames, ref);
}

void main() {
  test('tune peak detection on real capture', () {
    final (frames, ref) = _load();
    final r = const Base3Scanner()
        .decodeBytes(frames, ref, _n, _repeats, null, false, 60, false);
    final det = r.points.where((p) => p.detected).length;
    // ignore: avoid_print
    print('DEFAULTS -> detected=$det seen=${r.blobsFound} of $_n');
  });
}
