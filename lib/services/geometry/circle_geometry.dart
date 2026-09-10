import 'dart:math' as math;

import 'package:xml/xml.dart';

import '../../models/wired_model.dart';
import 'geometry_attrs.dart';

/// Builds a [WiredModel] for `DisplayAs="Circle"`. Mirrors xLights'
/// CircleModel: a single ring by default, or several concentric rings when
/// `LayerSizes` is present (`CenterPercent`/legacy `parm3` sets the
/// innermost ring's radius as a percent of the outermost) — wired
/// innermost-first, same convention confirmed for Star's `LayerSizes`.
WiredModel buildCircle(XmlElement root) {
  final numStrings = math.max(
    1,
    attrInt(root, 'NumStrings', parmFallback: 'parm1', fallback: 1),
  );
  final nodesPerString = math.max(
    1,
    attrInt(root, 'NodesPerString', parmFallback: 'parm2', fallback: 1),
  );
  final numLights = numStrings * nodesPerString;

  final isBotToTop =
      attrString(root, 'StartSide', fallback: 'B').toUpperCase() != 'T';
  final isLtoR = attrString(root, 'Dir', fallback: 'L').toUpperCase() != 'R';
  final centerPercent = attrDouble(
    root,
    'CenterPercent',
    parmFallback: 'parm3',
    fallback: -1,
  );

  Offset2 pointAt(double radius, double frac) {
    var angle = (isBotToTop ? -math.pi : 0) + 2 * math.pi * frac;
    if (!isLtoR) angle = -angle;
    return (
      x: radius * math.sin(angle),
      // Negated: xLights' angle convention is y-up (angle 0 = "top" sits at
      // +y), but this canvas draws y-down, so left unflipped "Bottom" would
      // render at the top of the screen — same class of bug fixed in Tree
      // and Star.
      y: -radius * math.cos(angle),
    );
  }

  final layerSizes = attrString(root, 'LayerSizes', fallback: '')
      .split(',')
      .map((s) => int.tryParse(s.trim()))
      .whereType<int>()
      .where((n) => n > 0)
      .toList();

  final nodes = <WiredNode>[];

  if (layerSizes.length > 1) {
    final layerCount = layerSizes.length;
    final maxRadius = layerSizes.last / 2; // outermost layer's own count
    final minRadius =
        (centerPercent > 0 ? centerPercent / 100 : 0.5) * maxRadius;
    var nodeCounter = 1;
    for (var layerIdx = 0; layerIdx < layerCount; layerIdx++) {
      final count = layerSizes[layerIdx];
      final radius = layerCount > 1
          ? minRadius + (maxRadius - minRadius) * (layerIdx / (layerCount - 1))
          : maxRadius;
      for (var n = 0; n < count; n++) {
        final p = pointAt(radius, n / count);
        nodes.add(
          WiredNode(
            node: nodeCounter++,
            x: p.x,
            y: p.y,
            strand: 'Ring ${layerIdx + 1}',
            strandIndex: layerIdx,
          ),
        );
      }
    }
  } else {
    final radius = numLights / 2;
    for (var n = 0; n < numLights; n++) {
      final p = pointAt(radius, n / numLights);
      nodes.add(WiredNode(node: n + 1, x: p.x, y: p.y));
    }
  }

  return WiredModel.fromNodes(
    name: attrString(root, 'name', fallback: 'Circle'),
    displayAs: 'Circle',
    nodes: nodes,
  );
}

typedef Offset2 = ({double x, double y});
