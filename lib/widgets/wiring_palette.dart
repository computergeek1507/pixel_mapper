import 'package:flutter/material.dart';

/// Fixed, visually distinct colors cycled by `node.strandIndex % length` to
/// group nodes by physical strand/arm/row in the wiring diagram. Used
/// on-screen, against the dark canvas background.
const List<Color> wiringPalette = [
  Color(0xFFE53935), // red
  Color(0xFFFB8C00), // orange
  Color(0xFFFDD835), // yellow
  Color(0xFF43A047), // green
  Color(0xFF00ACC1), // cyan
  Color(0xFF1E88E5), // blue
  Color(0xFF5E35B1), // indigo
  Color(0xFF8E24AA), // purple
  Color(0xFFD81B60), // pink
  Color(0xFF6D4C41), // brown
  Color(0xFF546E7A), // blue-grey
  Color(0xFF00897B), // teal
];

/// Same hues, darker (Material 800-ish) shades — needed for contrast when
/// printing on a white page instead of the app's dark canvas background.
const List<Color> wiringPalettePrint = [
  Color(0xFFC62828), // red
  Color(0xFFEF6C00), // orange
  Color(0xFFF9A825), // yellow/gold
  Color(0xFF2E7D32), // green
  Color(0xFF00838F), // cyan
  Color(0xFF1565C0), // blue
  Color(0xFF283593), // indigo
  Color(0xFF6A1B9A), // purple
  Color(0xFFAD1457), // pink
  Color(0xFF4E342E), // brown
  Color(0xFF37474F), // blue-grey
  Color(0xFF00695C), // teal
];

Color colorForStrand(int? strandIndex, {bool forPrint = false}) {
  final palette = forPrint ? wiringPalettePrint : wiringPalette;
  if (strandIndex == null) return palette[0];
  return palette[strandIndex % palette.length];
}
