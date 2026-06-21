import 'package:flutter/material.dart';

import '../../models/custom_grid.dart';
import '../../models/detected_point.dart';

/// A single dot to draw, positioned in normalized 0..1 space.
class LayoutDot {
  final Offset pos;
  final int node;
  const LayoutDot(this.pos, this.node);
}

/// Paints detected/placed pixels as numbered dots, scaled to fill the canvas.
/// Used both as a live overlay on the camera preview and for the grid preview.
class LayoutPainter extends CustomPainter {
  final List<LayoutDot> dots;
  final bool showLabels;
  final Color color;

  /// Inset (px) so edge nodes and their labels aren't clipped at the border.
  /// Keep 0 for the camera overlay so dots align with the image edge-to-edge.
  final double padding;

  LayoutPainter(
    this.dots, {
    this.showLabels = false,
    this.color = const Color(0xFF00E676),
    this.padding = 0,
  });

  /// Dots from raw detected points (normalized screen positions).
  static List<LayoutDot> fromDetected(List<DetectedPoint> points) => points
      .where((p) => p.detected)
      .map((p) => LayoutDot(p.screenXY!, p.nodeIndex + 1))
      .toList();

  /// Dots from a normalized grid (cell col/row mapped to 0..1).
  static List<LayoutDot> fromGrid(CustomGrid grid) {
    final w = grid.width > 1 ? grid.width - 1 : 1;
    final h = grid.height > 1 ? grid.height - 1 : 1;
    return grid.cells
        .map((c) => LayoutDot(Offset(c.col / w, c.row / h), c.node))
        .toList();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final fill = Paint()..color = color;
    final stroke = Paint()
      ..color = Colors.black.withValues(alpha: 0.6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    final iw = (size.width - 2 * padding).clamp(1.0, size.width);
    final ih = (size.height - 2 * padding).clamp(1.0, size.height);
    for (final dot in dots) {
      final c =
          Offset(padding + dot.pos.dx * iw, padding + dot.pos.dy * ih);
      canvas.drawCircle(c, 5, fill);
      canvas.drawCircle(c, 5, stroke);
      if (showLabels) {
        final tp = TextPainter(
          text: TextSpan(
            text: '${dot.node}',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 9,
              fontWeight: FontWeight.bold,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, c + const Offset(6, -4));
      }
    }
  }

  @override
  bool shouldRepaint(covariant LayoutPainter old) =>
      old.dots != dots ||
      old.showLabels != showLabels ||
      old.padding != padding;
}
