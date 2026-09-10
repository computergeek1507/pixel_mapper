import 'dart:math' as math;

import 'package:xml/xml.dart';

import '../../models/wired_model.dart';
import 'geometry_attrs.dart';

/// Builds a [WiredModel] for `DisplayAs="Spinner"`. Mirrors xLights'
/// SpinnerModel's simple case (no zigzag/alternate-node variants within an
/// arm, which are lower priority): `armCount` spokes radiate from a hub, each
/// carrying `NodesPerArm` pixels outward.
WiredModel buildSpinner(XmlElement root) {
  final numStrings = math.max(
    1,
    attrInt(root, 'NumStrings', parmFallback: 'parm1', fallback: 1),
  );
  final nodesPerArm = math.max(
    1,
    attrInt(root, 'NodesPerArm', parmFallback: 'parm2', fallback: 1),
  );
  final armsPerString = math.max(
    1,
    attrInt(root, 'ArmsPerString', parmFallback: 'parm3', fallback: 1),
  );
  final hollowPct = attrDouble(root, 'Hollow', fallback: 20);
  final arcDegrees = attrDouble(root, 'Arc', fallback: 360);
  final startAngleDeg = attrDouble(root, 'StartAngle', fallback: 0);
  final isCCW = attrString(root, 'Dir', fallback: 'L').toUpperCase() != 'R';

  final armCount = numStrings * armsPerString;
  final arcRad = arcDegrees * math.pi / 180;
  final angleStep = (armCount > 1 && arcDegrees < 360)
      ? arcRad / (armCount - 1)
      : arcRad / armCount;
  final baseAngle = (270 + startAngleDeg) * math.pi / 180;
  final hollowOffset = hollowPct * 2 * nodesPerArm / 100;

  final nodes = <WiredNode>[];
  var nodeCounter = 1;
  for (var a = 0; a < armCount; a++) {
    final angle = baseAngle + (isCCW ? 1 : -1) * a * angleStep;
    for (var n = 0; n < nodesPerArm; n++) {
      final r = 0.5 + n + hollowOffset;
      nodes.add(
        WiredNode(
          node: nodeCounter++,
          x: r * math.cos(angle),
          y: r * math.sin(angle),
          strand: 'Arm ${a + 1}',
          strandIndex: a,
        ),
      );
    }
  }

  return WiredModel.fromNodes(
    name: attrString(root, 'name', fallback: 'Spinner'),
    displayAs: 'Spinner',
    nodes: nodes,
  );
}
