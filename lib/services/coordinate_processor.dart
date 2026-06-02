import 'dart:math';

import '../models/custom_grid.dart';
import '../models/detected_point.dart';

/// Turns raw detected (x, y) positions into an integer Custom-model grid.
///
/// Strategy: pick a grid pitch from the median nearest-neighbor spacing of the
/// detected points, snap each point to a cell, then resolve collisions by
/// spiraling to the nearest free cell. Image-y maps directly to grid row, so
/// the top of the frame is row 0 (flip in xLights if your prop reads inverted).
class CoordinateProcessor {
  /// Normalizes [points]; undetected points are skipped. Returns
  /// [CustomGrid.empty] if nothing was detected.
  static CustomGrid normalize(List<DetectedPoint> points) {
    final detected = points.where((p) => p.detected).toList()
      ..sort((a, b) => a.nodeIndex.compareTo(b.nodeIndex));
    if (detected.isEmpty) return CustomGrid.empty;

    final xs = detected.map((p) => p.screenXY!.dx).toList();
    final ys = detected.map((p) => p.screenXY!.dy).toList();
    final minX = xs.reduce(min);
    final maxX = xs.reduce(max);
    final minY = ys.reduce(min);
    final maxY = ys.reduce(max);

    final spacing = _chooseSpacing(detected, minX, maxX, minY, maxY);

    final occupied = <String, bool>{};
    final cells = <GridCell>[];
    for (final p in detected) {
      var col = ((p.screenXY!.dx - minX) / spacing).round();
      var row = ((p.screenXY!.dy - minY) / spacing).round();
      final free = _findFreeCell(occupied, col, row);
      col = free.$1;
      row = free.$2;
      occupied['$col,$row'] = true;
      cells.add(GridCell(node: p.nodeIndex + 1, col: col, row: row));
    }

    final width = cells.map((c) => c.col).reduce(max) + 1;
    final height = cells.map((c) => c.row).reduce(max) + 1;
    return CustomGrid(width: width, height: height, cells: cells);
  }

  static double _chooseSpacing(
    List<DetectedPoint> pts,
    double minX,
    double maxX,
    double minY,
    double maxY,
  ) {
    if (pts.length < 2) {
      return 1.0; // single point -> trivial 1x1 grid
    }
    final nn = <double>[];
    for (var i = 0; i < pts.length; i++) {
      var best = double.infinity;
      final a = pts[i].screenXY!;
      for (var j = 0; j < pts.length; j++) {
        if (i == j) continue;
        final b = pts[j].screenXY!;
        final d = (a.dx - b.dx) * (a.dx - b.dx) + (a.dy - b.dy) * (a.dy - b.dy);
        if (d < best) best = d;
      }
      if (best.isFinite) nn.add(sqrt(best));
    }
    if (nn.isEmpty) return 1.0;
    nn.sort();
    final median = nn[nn.length ~/ 2];
    if (median > 0) return median;
    // Degenerate (coincident points): fall back to extent / sqrt(count).
    final extent = max(maxX - minX, maxY - minY);
    return extent > 0 ? extent / sqrt(pts.length) : 1.0;
  }

  /// Spiral outward from (col,row) to the first unoccupied cell.
  static (int, int) _findFreeCell(
      Map<String, bool> occupied, int col, int row) {
    if (occupied['$col,$row'] != true) return (col, row);
    for (var radius = 1; radius < 1000; radius++) {
      for (var dr = -radius; dr <= radius; dr++) {
        for (var dc = -radius; dc <= radius; dc++) {
          // Only the ring at this radius (Chebyshev distance == radius).
          if (dr.abs() != radius && dc.abs() != radius) continue;
          final c = col + dc;
          final r = row + dr;
          if (c < 0 || r < 0) continue;
          if (occupied['$c,$r'] != true) return (c, r);
        }
      }
    }
    return (col, row); // unreachable in practice
  }
}
