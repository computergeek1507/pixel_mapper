import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/wired_model.dart';
import 'wiring_palette.dart';

// Every 50th node after the first (51, 101, 151, ...) marks the start of a
// new physical run — most pixel controllers/ports cap out around 50 pixels,
// so this is a useful "new port starts here" landmark while wiring by hand.
const _portRunLength = 50;
const _portMarkerColorDark = Color(0xFFFFC107);
const _portMarkerColorPrint = Color(0xFFF57F17);
const _canvasBackgroundDark = Color(0xFF101014);
const _canvasBackgroundPrint = Colors.white;

bool _isPortBoundary(int node) => node > 1 && (node - 1) % _portRunLength == 0;

/// Pan/zoomable wiring diagram: a polyline connecting nodes in wiring order
/// underneath color-by-strand dots, so the physical wiring sequence (node 1,
/// 2, 3, ...) is directly traceable. [showLabels]/[showBackside] are owned by
/// the caller (the AppBar toggles on the wiring view page), not this widget,
/// so there is one source of truth for that state.
class WiringCanvas extends StatelessWidget {
  final WiredModel model;
  final bool showLabels;
  final bool showBackside;

  const WiringCanvas({
    super.key,
    required this.model,
    required this.showLabels,
    required this.showBackside,
  });

  @override
  Widget build(BuildContext context) {
    return InteractiveViewer(
      minScale: 0.2,
      maxScale: 8.0,
      boundaryMargin: const EdgeInsets.all(200),
      child: SizedBox(
        width: 2000,
        height: 2000,
        child: CustomPaint(
          painter: WiringPainter(
            model: model,
            showLabels: showLabels,
            showBackside: showBackside,
          ),
        ),
      ),
    );
  }
}

class WiringPainter extends CustomPainter {
  final WiredModel model;
  final bool showLabels;
  final bool showBackside;

  /// White background + darker palette/line/label colors for a printed
  /// page, instead of the app's normal dark canvas. Only
  /// [wiring_print_service.dart] sets this true — the on-screen view always
  /// uses the dark theme.
  final bool forPrint;

  WiringPainter({
    required this.model,
    required this.showLabels,
    required this.showBackside,
    this.forPrint = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final background = forPrint
        ? _canvasBackgroundPrint
        : _canvasBackgroundDark;
    final lineColor = forPrint ? Colors.black : Colors.white;
    final portMarkerColor = forPrint
        ? _portMarkerColorPrint
        : _portMarkerColorDark;

    canvas.drawRect(Offset.zero & size, Paint()..color = background);

    final nodes = model.nodes;
    if (nodes.isEmpty) return;

    const margin = 32.0;
    final availW = size.width - margin * 2;
    final availH = size.height - margin * 2;
    final scaleW = availW / model.width;
    final scaleH = availH / model.height;
    final scale = scaleW < scaleH ? scaleW : scaleH;
    if (scale.isNaN || scale.isInfinite || scale <= 0) return;

    final drawnW = model.width * scale;
    final drawnH = model.height * scale;
    final originX = (size.width - drawnW) / 2;
    final originY = (size.height - drawnH) / 2;

    // xLights' layout view (and the front/display-facing DisplayAs="Custom"
    // grid, and most native-shape formulas) describes the model as seen from
    // the front. Wiring by hand is done from the back, which mirrors left
    // and right — so the backside view flips x around the model's center.
    Offset screen(WiredNode n) {
      final localX = n.x - model.minX;
      final x = showBackside ? model.width - localX : localX;
      return Offset(originX + x * scale, originY + (n.y - model.minY) * scale);
    }

    // Wiring path first, underneath the dots.
    final path = Path();
    for (var i = 0; i < nodes.length; i++) {
      final p = screen(nodes[i]);
      if (i == 0) {
        path.moveTo(p.dx, p.dy);
      } else {
        path.lineTo(p.dx, p.dy);
      }
    }
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = lineColor.withAlpha(forPrint ? 110 : 90),
    );

    const dotRadius = 4.0;
    final dotPaint = Paint()..style = PaintingStyle.fill;
    for (final n in nodes) {
      dotPaint.color = _isPortBoundary(n.node)
          ? portMarkerColor
          : colorForStrand(n.strandIndex, forPrint: forPrint);
      canvas.drawCircle(screen(n), dotRadius, dotPaint);
    }

    // Mark node 1 distinctly so the wiring start/direction is visible even
    // with labels off.
    const startRingRadius = dotRadius + 2;
    canvas.drawCircle(
      screen(nodes.first),
      startRingRadius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = lineColor,
    );

    // Mark the last node (end of the wiring chain) with an octagon.
    const endMarkerRadius = dotRadius + 7;
    final endOctagon = _octagonPath(screen(nodes.last), endMarkerRadius);
    canvas.drawPath(
      endOctagon,
      Paint()
        ..style = PaintingStyle.fill
        ..color = portMarkerColor,
    );
    canvas.drawPath(
      endOctagon,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = Colors.black54,
    );

    if (showLabels) {
      for (final n in nodes) {
        final p = screen(n);
        final tp = TextPainter(
          text: TextSpan(
            text: '${n.node}',
            style: TextStyle(color: lineColor, fontSize: 10),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        final clearance = switch (n) {
          _ when n == nodes.first => startRingRadius + 1.5,
          _ when n == nodes.last => endMarkerRadius + 1.5,
          _ => dotRadius + 2,
        };
        tp.paint(canvas, p + Offset(clearance, -tp.height / 2));
      }
    }
  }

  /// A regular octagon (flat edge on top, like a stop sign) centered at
  /// [center] with the given [radius].
  Path _octagonPath(Offset center, double radius) {
    final path = Path();
    for (var i = 0; i < 8; i++) {
      final angle = -math.pi / 2 + math.pi / 8 + i * (math.pi / 4);
      final x = center.dx + radius * math.cos(angle);
      final y = center.dy + radius * math.sin(angle);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    path.close();
    return path;
  }

  @override
  bool shouldRepaint(covariant WiringPainter old) =>
      old.model != model ||
      old.showLabels != showLabels ||
      old.showBackside != showBackside ||
      old.forPrint != forPrint;
}
