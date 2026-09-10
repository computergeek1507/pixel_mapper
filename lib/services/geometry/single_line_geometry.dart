import 'package:xml/xml.dart';

import '../../models/wired_model.dart';
import 'geometry_attrs.dart';

/// Builds a [WiredModel] for `DisplayAs="Single Line"`: `lightCount` pixels
/// evenly spaced along a straight local X axis (y=0). Mirrors xLights'
/// SingleLineModel — the model's actual on-screen position/rotation comes
/// from its `TwoPointScreenLocation`, which only matters for the layout tab,
/// not for a relative wiring diagram, so it's not applied here.
WiredModel buildSingleLine(XmlElement root) {
  final numStrings = attrInt(
    root,
    'NumStrings',
    parmFallback: 'parm1',
    fallback: 1,
  );
  final nodesPerString = attrInt(
    root,
    'NodesPerString',
    parmFallback: 'parm2',
    fallback: 50,
  );
  final lightsPerNode = attrInt(
    root,
    'LightsPerNode',
    parmFallback: 'parm3',
    fallback: 1,
  );

  final lightCount =
      (numStrings < 1 ? 1 : numStrings) *
      (nodesPerString < 1 ? 1 : nodesPerString) *
      (lightsPerNode < 1 ? 1 : lightsPerNode);

  final nodes = <WiredNode>[];
  if (lightCount == 1) {
    nodes.add(const WiredNode(node: 1, x: 0, y: 0));
  } else {
    final spacing = 1.0 / (lightCount - 1);
    for (var i = 0; i < lightCount; i++) {
      nodes.add(WiredNode(node: i + 1, x: i * spacing, y: 0));
    }
  }

  return WiredModel.fromNodes(
    name: attrString(root, 'name', fallback: 'Single Line'),
    displayAs: 'Single Line',
    nodes: nodes,
  );
}
