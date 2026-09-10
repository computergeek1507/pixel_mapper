import 'package:xml/xml.dart';

import '../../models/wired_model.dart';
import 'geometry_attrs.dart';
import 'matrix_buffer.dart';

/// Builds a [WiredModel] for `DisplayAs="Matrix"` (and legacy
/// `"Vert Matrix"`/`"Horiz Matrix"`). Mirrors xLights' MatrixModel/VMatrixModel:
/// see [buildMatrixBuffer] for the row/strand/zigzag layout this projects
/// straight through as (x, y) = (col, row).
WiredModel buildMatrix(XmlElement root) {
  final displayAs = attrString(root, 'DisplayAs', fallback: 'Matrix');
  final vertical =
      attrBool(root, 'Vertical') || displayAs.toLowerCase() == 'vert matrix';

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
    fallback: 1,
  );
  final strandsPerString = attrInt(
    root,
    'StrandsPerString',
    parmFallback: 'parm3',
    fallback: 1,
  );
  // "NoZig" in some files, "NoZigZag" in others.
  final zigzag = !(attrBool(root, 'NoZigZag') || attrBool(root, 'NoZig'));
  final alternateNodes = attrBool(root, 'AlternateNodes');
  final startAtTop =
      attrString(root, 'StartSide', fallback: 'B').toUpperCase() == 'T';
  final reverseStrandOrder =
      attrString(root, 'Dir', fallback: 'L').toUpperCase() == 'R';

  final buffer = buildMatrixBuffer(
    numStrings: numStrings,
    nodesPerString: nodesPerString,
    strandsPerString: strandsPerString,
    vertical: vertical,
    zigzag: zigzag,
    alternateNodes: alternateNodes,
    startAtTop: startAtTop,
    reverseStrandOrder: reverseStrandOrder,
  );

  final nodes = <WiredNode>[];
  for (var i = 0; i < buffer.length; i++) {
    final p = buffer[i];
    nodes.add(
      WiredNode(
        node: i + 1,
        x: p.col.toDouble(),
        y: p.row.toDouble(),
        strand: 'Strand ${p.strandIndex + 1}',
        strandIndex: p.strandIndex,
      ),
    );
  }

  return WiredModel.fromNodes(
    name: attrString(root, 'name', fallback: 'Matrix'),
    displayAs: 'Matrix',
    nodes: nodes,
  );
}
