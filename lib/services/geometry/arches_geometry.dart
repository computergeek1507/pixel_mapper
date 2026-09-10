import 'dart:math' as math;

import 'package:xml/xml.dart';

import '../../models/wired_model.dart';
import 'geometry_attrs.dart';

/// Builds a [WiredModel] for `DisplayAs="Arches"`. Two modes, mirroring
/// xLights' ArchesModel:
///
/// - Dominant mode (no `LayerSizes`): `NumArches` separate arches placed
///   side by side, each spanning the same `Arc` degrees.
/// - Layered/concentric mode (`LayerSizes` present): nested arches sharing
///   the same center and angular span, differing only in radius — `Hollow`
///   is the innermost layer's radius as a percent of the outermost, and the
///   list is wired innermost-first (unverified against a real multi-count
///   sample — this codebase's Star LayerSizes support needed that exact
///   assumption corrected once already, so treat this as best-effort until
///   confirmed against a real file where layer sizes actually differ).
///
/// Note `LightsPerNode` (legacy `parm3`) is NOT the arc's angular span; that's
/// the separate `Arc` attribute (default 180°).
WiredModel buildArches(XmlElement root) {
  final numArches = attrInt(
    root,
    'NumArches',
    parmFallback: 'parm1',
    fallback: 1,
  );
  final nodesPerArch = attrInt(
    root,
    'NodesPerArch',
    parmFallback: 'parm2',
    fallback: 1,
  );
  final lightsPerNode = attrInt(
    root,
    'LightsPerNode',
    parmFallback: 'parm3',
    fallback: 1,
  );
  final arcDegrees = attrDouble(root, 'Arc', fallback: 180);
  final gap = attrDouble(root, 'Gap', fallback: 0);
  final reversed = attrString(root, 'Dir', fallback: 'L').toUpperCase() == 'R';
  final archRad = arcDegrees * math.pi / 180.0;

  final layerSizes = attrString(root, 'LayerSizes', fallback: '')
      .split(',')
      .map((s) => int.tryParse(s.trim()))
      .whereType<int>()
      .where((n) => n > 0)
      .toList();

  final nodes = <WiredNode>[];
  var nodeCounter = 1;

  if (layerSizes.length > 1) {
    // Layered/concentric: same center and Arc span, nested by radius.
    final hollowPct = attrDouble(root, 'Hollow', fallback: 70);
    final hollow = (hollowPct / 100).clamp(0.0, 1.0);
    final layerCount = layerSizes.length;
    final baseN = layerSizes.last; // outermost layer's own count = full radius
    final archGap = layerCount > 1 ? (1 - hollow) / (layerCount - 1) : 0.0;

    // Raw (unshifted) points per layer first — layers must share ONE common
    // shift (below), not each independently re-zero its own peak, or the
    // nesting collapses (every layer's peak would land at the same y).
    final perLayerPoints = <List<({double x, double y})>>[];
    for (var layerIdx = 0; layerIdx < layerCount; layerIdx++) {
      final count = layerSizes[layerIdx];
      final scale = 1 - archGap * (layerCount - 1 - layerIdx);
      var points = _archPointsRaw(
        count,
        archRad,
        radiusX: (baseN - 1) * scale,
        radiusY: baseN * scale,
      );
      if (reversed) points = points.reversed.toList();
      perLayerPoints.add(points);
    }
    final globalMinY = perLayerPoints
        .expand((l) => l)
        .map((p) => p.y)
        .reduce(math.min);
    for (var layerIdx = 0; layerIdx < layerCount; layerIdx++) {
      for (final p in perLayerPoints[layerIdx]) {
        nodes.add(
          WiredNode(
            node: nodeCounter++,
            x: p.x,
            y: p.y - globalMinY,
            strand: 'Layer ${layerIdx + 1}',
            strandIndex: layerIdx,
          ),
        );
      }
    }
  } else {
    // Dominant mode: NumArches placed side by side.
    final perArch = math.max(1, nodesPerArch);
    final perNode = math.max(1, lightsPerNode);
    final n = perArch * perNode;
    final archesCount = math.max(1, numArches);

    var xOffset = 0.0;
    final archOrder = List.generate(archesCount, (i) => i);
    for (final archIdx
        in (reversed ? archOrder.reversed.toList() : archOrder)) {
      var points = _archPoints(n, archRad);
      if (reversed) points = points.reversed.toList();
      final xs = points.map((p) => p.x);
      final localMinX = xs.reduce(math.min);
      final archWidth = xs.reduce(math.max) - localMinX;

      for (final p in points) {
        nodes.add(
          WiredNode(
            node: nodeCounter++,
            x: xOffset + (p.x - localMinX),
            y: p.y,
            strand: 'Arch ${archIdx + 1}',
            strandIndex: archIdx,
          ),
        );
      }
      xOffset += archWidth + gap;
    }
  }

  return WiredModel.fromNodes(
    name: attrString(root, 'name', fallback: 'Arches'),
    displayAs: 'Arches',
    nodes: nodes,
  );
}

/// One arch's raw (unshifted) points. `angle(p) = -Arc/2 + Arc*p/(n-1)`,
/// `x=radiusX*sin(angle)`, `y=-radiusY*cos(angle)` (negated because xLights'
/// convention is y-up but this canvas draws y-down — unflipped, the peak
/// ended up at the bottom of the screen and the legs at the top). Defaults
/// to xLights' own `radiusX=n-1, radiusY=n` (a slightly peaked arch, not a
/// true semicircle) when not overridden, which layered/concentric mode does
/// to nest several different-count arches at explicit shared radii instead.
List<({double x, double y})> _archPointsRaw(
  int n,
  double archRad, {
  double? radiusX,
  double? radiusY,
}) {
  if (n <= 1) return const [(x: 0.0, y: 0.0)];
  final rx = radiusX ?? (n - 1).toDouble();
  final ry = radiusY ?? n.toDouble();
  final points = <({double x, double y})>[];
  for (var p = 0; p < n; p++) {
    final angle = -archRad / 2 + archRad * p / (n - 1);
    points.add((x: rx * math.sin(angle), y: -ry * math.cos(angle)));
  }
  return points;
}

/// [_archPointsRaw], shifted so this arch's own minimum y is 0 — correct for
/// a single independent arch (dominant/side-by-side mode), but NOT for
/// concentric layers, which must share one common shift across all layers
/// (see the `globalMinY` step in [buildArches]) or the nesting collapses.
List<({double x, double y})> _archPoints(
  int n,
  double archRad, {
  double? radiusX,
  double? radiusY,
}) {
  final points = _archPointsRaw(n, archRad, radiusX: radiusX, radiusY: radiusY);
  if (points.isEmpty) return points;
  final minY = points.map((e) => e.y).reduce(math.min);
  return [for (final p in points) (x: p.x, y: p.y - minY)];
}
