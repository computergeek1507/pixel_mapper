/// A simple RGB color value for a single WS2811 pixel.
///
/// The app targets RGB pixels (3 channels). Values are 0-255.
class PixelColor {
  final int r;
  final int g;
  final int b;

  const PixelColor(this.r, this.g, this.b);

  static const PixelColor off = PixelColor(0, 0, 0);
  static const PixelColor white = PixelColor(255, 255, 255);
  static const PixelColor red = PixelColor(255, 0, 0);
  static const PixelColor green = PixelColor(0, 255, 0);
  static const PixelColor blue = PixelColor(0, 0, 255);

  @override
  bool operator ==(Object other) =>
      other is PixelColor && other.r == r && other.g == g && other.b == b;

  @override
  int get hashCode => Object.hash(r, g, b);

  @override
  String toString() => 'PixelColor($r, $g, $b)';
}
