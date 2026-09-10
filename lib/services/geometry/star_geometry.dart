import 'dart:math' as math;

import 'package:xml/xml.dart';

import '../../models/wired_model.dart';
import 'geometry_attrs.dart';

/// Builds a [WiredModel] for `DisplayAs="Star"`. Traces the `2*StarPoints`-gon
/// outline (alternating outer/inner radius vertices) and places pixels at
/// constant arc-length spacing along that closed path. When `LayerSizes` is
/// present the star is nested/concentric: each layer gets its own outline at
/// a scaled-down radius (from `StarCenterPercent`, the innermost layer's
/// size as a percent of full size) and its own sequential block of node
/// numbers, all layers sharing the same start angle/direction.
///
/// `LayerSizes` is listed innermost-first but wired outermost-first —
/// verified against a real two-layer vendor model ("Med Tree Star",
/// `LayerSizes="20,30"`, `StarCenterPercent="67"`) against a reference from
/// xLights itself: the 30-pixel layer wires as the full-size outer star
/// first (nodes 1-30, starting at an inner "knee" vertex, not a point),
/// then the 20-pixel layer as the smaller inner star at 67% size (nodes
/// 31-50) — so the list is reversed before assigning node-number blocks.
WiredModel buildStar(XmlElement root) {
  final numStrings = math.max(
    1,
    attrInt(root, 'NumStrings', parmFallback: 'parm1', fallback: 1),
  );
  final nodesPerString = math.max(
    1,
    attrInt(root, 'NodesPerString', parmFallback: 'parm2', fallback: 1),
  );
  final starPoints = math.max(
    3,
    attrInt(root, 'StarPoints', parmFallback: 'parm3', fallback: 5),
  );
  final starRatioRaw = attrDouble(root, 'StarRatio', fallback: 2.618034);
  final starRatio = starRatioRaw.abs() < 0.0001 ? 1.0 : starRatioRaw.abs();
  final startLocation = attrString(
    root,
    'StarStartLocation',
    fallback: 'Top-CW',
  ).toLowerCase();
  final centerPercent = attrDouble(root, 'StarCenterPercent', fallback: -1);

  final pixelCount = numStrings * nodesPerString;
  final baseOuterRadius = pixelCount / 2;
  final pointAngleGap = 2 * math.pi / starPoints;

  double startAngle;
  if (startLocation.contains('bottom')) {
    startAngle = math.pi;
  } else if (startLocation.contains('left')) {
    startAngle = -math.pi / 2;
  } else if (startLocation.contains('right')) {
    startAngle = math.pi / 2;
  } else {
    startAngle = 0; // Top
  }
  final directionUnit = startLocation.contains('ccw') ? -1.0 : 1.0;

  final rawLayerSizes = attrString(root, 'LayerSizes', fallback: '')
      .split(',')
      .map((s) => int.tryParse(s.trim()))
      .whereType<int>()
      .where((n) => n > 0)
      .toList();

  // Wired outermost-first; the file lists innermost-first (see doc comment).
  final layerCounts = rawLayerSizes.length > 1
      ? rawLayerSizes.reversed.toList()
      : [pixelCount];
  final numLayers = layerCounts.length;
  final innerScale =
      (centerPercent > 0 ? centerPercent : (100 / numLayers)) / 100;

  final nodes = <WiredNode>[];
  var nodeCounter = 1;
  for (var layerIdx = 0; layerIdx < numLayers; layerIdx++) {
    final count = layerCounts[layerIdx];
    // layer 0 = outer (scale 1.0) ... last layer = inner (scale innerScale).
    final scale = numLayers > 1
        ? 1.0 - (1.0 - innerScale) * (layerIdx / (numLayers - 1))
        : 1.0;
    final outerRadius = baseOuterRadius * scale;
    final innerRadius = outerRadius / starRatio;

    for (final p in _walkStarOutline(
      starPoints: starPoints,
      outerRadius: outerRadius,
      innerRadius: innerRadius,
      startAngle: startAngle,
      directionUnit: directionUnit,
      pointAngleGap: pointAngleGap,
      pixelCount: count,
    )) {
      nodes.add(
        WiredNode(
          node: nodeCounter++,
          x: p.x,
          y: p.y,
          strand: numLayers > 1 ? 'Layer ${layerIdx + 1}' : null,
          strandIndex: numLayers > 1 ? layerIdx : null,
        ),
      );
    }
  }

  return WiredModel.fromNodes(
    name: attrString(root, 'name', fallback: 'Star'),
    displayAs: 'Star',
    nodes: nodes,
  );
}

/// Traces the `2*starPoints`-gon outline (alternating outer/inner vertices,
/// starting at [startAngle] and winding by [directionUnit]) and places
/// [pixelCount] points at constant arc-length spacing along that closed path.
List<({double x, double y})> _walkStarOutline({
  required int starPoints,
  required double outerRadius,
  required double innerRadius,
  required double startAngle,
  required double directionUnit,
  required double pointAngleGap,
  required int pixelCount,
}) {
  final segments = starPoints * 2;
  final vertices = <({double x, double y})>[];
  var curAngle = startAngle;
  for (var i = 0; i < segments; i++) {
    // Index 0 is an inner "knee" vertex, not an outer point — the walk (and
    // so node 1 of each layer) starts at a knee, matching xLights' own
    // wiring order.
    final r = i.isEven ? innerRadius : outerRadius;
    // y negated: xLights' angle convention is y-up (angle 0 = "top" sits at
    // +y), but this canvas draws y-down — same class of bug fixed in Tree
    // and Circle.
    vertices.add((x: r * math.sin(curAngle), y: -r * math.cos(curAngle)));
    curAngle += directionUnit * pointAngleGap / 2;
  }

  final segLengths = <double>[];
  final prefix = <double>[0];
  for (var i = 0; i < segments; i++) {
    final a = vertices[i];
    final b = vertices[(i + 1) % segments];
    final len = math.sqrt(math.pow(b.x - a.x, 2) + math.pow(b.y - a.y, 2));
    segLengths.add(len);
    prefix.add(prefix.last + len);
  }
  final totalPerimeter = prefix.last;
  if (totalPerimeter <= 0 || pixelCount <= 0) return const [];

  final points = <({double x, double y})>[];
  final step = totalPerimeter / pixelCount;
  for (var n = 0; n < pixelCount; n++) {
    final targetDist = n * step;
    var segIdx = segments - 1;
    for (var i = 0; i < segments; i++) {
      if (targetDist < prefix[i + 1] || i == segments - 1) {
        segIdx = i;
        break;
      }
    }
    final segLen = segLengths[segIdx];
    final t = segLen <= 0 ? 0.0 : (targetDist - prefix[segIdx]) / segLen;
    final a = vertices[segIdx];
    final b = vertices[(segIdx + 1) % segments];
    points.add((x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t));
  }
  return points;
}
