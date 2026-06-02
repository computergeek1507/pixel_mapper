import '../models/pixel_color.dart';

/// Base-3 positional encoding used to identify many pixels in few frames —
/// the "non-linear pixel pattern" from xLights' Generate Custom Model wizard
/// (GenerateCustomModelDialog.cpp: GetBits / convertToBase3).
///
/// Every pixel is lit in every frame; in frame `i` a pixel shows the colour of
/// the i-th base-3 digit of its (1-based) index: 0=Red, 1=Green, 2=Blue. After
/// `bitsFor(n)` frames each pixel's colour sequence spells its base-3 number.
/// The last two digits are a checksum derived from the digit sum, so misreads
/// are rejected on decode.
class Base3Codec {
  /// Digit -> colour. Matches xLights SetBulbsUsingBase3 (channel 0/1/2 = R/G/B).
  static const PixelColor red = PixelColor(255, 0, 0);
  static const PixelColor green = PixelColor(0, 255, 0);
  static const PixelColor blue = PixelColor(0, 0, 255);

  /// Number of base-3 digits (frames) needed for [numPixels]. Equals the digit
  /// count of numPixels plus two checksum digits — xLights' GetBits.
  static int bitsFor(int numPixels) {
    var count = 0;
    var p = numPixels;
    while (p != 0) {
      p ~/= 3;
      count++;
    }
    return count + 2;
  }

  /// Encodes a 1-based [pixel] number to a [bits]-long base-3 digit string with
  /// the two trailing checksum digits and leading-zero padding. Char by char
  /// this is the colour the pixel shows in frames 0..bits-1.
  static String encode(int pixel, int bits) {
    var number = pixel;
    var res = '';
    var total = 0;
    while (number > 0) {
      final r = number % 3;
      res = '$r$res';
      total += r;
      number ~/= 3;
    }
    var check = 2 - (total % 3);
    res = '$res$check';
    check = (check + 1) % 3;
    res = '$res$check';
    while (res.length < bits) {
      res = '0$res';
    }
    return res;
  }

  /// Decodes a base-3 digit string back to its 1-based pixel number, or null if
  /// the checksum doesn't validate (a misread). Inverse of [encode].
  static int? decode(String digits) {
    if (digits.length < 3) return null;
    final body = digits.substring(0, digits.length - 2);
    final check1 = digits.codeUnitAt(digits.length - 2) - 0x30;
    final check2 = digits.codeUnitAt(digits.length - 1) - 0x30;

    var total = 0;
    var value = 0;
    for (final unit in body.codeUnits) {
      final d = unit - 0x30;
      if (d < 0 || d > 2) return null;
      total += d;
      value = value * 3 + d;
    }
    final expected1 = 2 - (total % 3);
    final expected2 = (expected1 + 1) % 3;
    if (check1 != expected1 || check2 != expected2) return null;
    return value;
  }

  /// Colour for a single base-3 digit character ('0'/'1'/'2').
  static PixelColor colorForDigit(int digit) {
    switch (digit) {
      case 0:
        return red;
      case 1:
        return green;
      default:
        return blue;
    }
  }
}
