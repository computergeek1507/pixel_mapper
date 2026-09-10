import 'dart:math' as math;

import 'package:xml/xml.dart';

import '../../models/wired_model.dart';
import 'geometry_attrs.dart';
import 'matrix_buffer.dart';

/// Builds a [WiredModel] for `DisplayAs="Tree"` (and legacy compound values
/// like `"Tree 360"`, `"Tree 120"`, `"Tree Flat"`, `"Tree Ribbon"` — older
/// xLights files encode the degree span or Flat/Ribbon style directly in
/// `DisplayAs` instead of a separate `TreeType`/`TreeDegrees` attribute).
/// Also accepts a `<treemodel>` root, which some vendor exports use in place
/// of a generic `<model DisplayAs="Tree ...">`. Tree reuses Matrix's buffer
/// layout (see [buildMatrixBuffer]) — strand index becomes the buffer's x
/// axis, position along the strand becomes its y axis — then projects that
/// buffer onto a shape selected by `TreeType` (0=Round/spiral cone [default],
/// 1=Flat, 2=Ribbon). Round mode is inherently 3D; z is dropped for a 2D
/// front elevation, which is enough to show wiring order.
WiredModel buildTree(XmlElement root) {
  final displayAsRaw = attrString(
    root,
    'DisplayAs',
    fallback: 'Tree',
  ).toLowerCase();
  final treeType = _treeType(root, displayAsRaw);
  final numStrings = math.max(
    1,
    attrInt(root, 'NumStrings', parmFallback: 'parm1', fallback: 1),
  );
  final nodesPerString = math.max(
    1,
    attrInt(root, 'NodesPerString', parmFallback: 'parm2', fallback: 1),
  );
  final strandsPerString = math.max(
    1,
    attrInt(root, 'StrandsPerString', parmFallback: 'parm3', fallback: 1),
  );
  final vertical =
      attrString(root, 'StrandDir', fallback: 'Vertical').toLowerCase() !=
      'horizontal';
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

  final bufferWi = buffer.fold(0, (m, p) => math.max(m, p.col)) + 1;
  final bufferHt = buffer.fold(0, (m, p) => math.max(m, p.row)) + 1;

  final nodes = <WiredNode>[];
  if (treeType == 0) {
    final treeDegrees = _treeDegrees(root, displayAsRaw);
    final treeRotationDeg = attrDouble(root, 'TreeRotation', fallback: 3.0);
    final bottomTopRatio = attrDouble(
      root,
      'TreeBottomTopRatio',
      fallback: 6.0,
    );
    final spiralRotations = attrDouble(
      root,
      'TreeSpiralRotations',
      fallback: 0,
    );

    final renderHt = bufferHt * 3.0;
    final renderWi = renderHt / 1.8;
    final radius = renderWi / 2;
    final ratio = bottomTopRatio.abs() < 0.0001 ? 1.0 : bottomTopRatio.abs();
    final topRadius = radius / ratio;

    final radians = treeDegrees * math.pi / 180.0;
    final startAngle = -radians / 2 + treeRotationDeg * math.pi / 180.0;
    final angleIncr = (bufferWi > 1 && treeDegrees < 350)
        ? radians / (bufferWi - 1)
        : radians / bufferWi;

    for (final p in buffer) {
      final t = bufferHt > 1 ? p.row / (bufferHt - 1) : 0.0;
      final angle =
          startAngle + p.col * angleIncr + spiralRotations * 2 * math.pi * t;
      final xBottom = radius * math.sin(angle);
      final xTop = topRadius * math.sin(angle);
      final x = xBottom + (xTop - xBottom) * t;
      // t=0 is the (wide) physical bottom, t=1 the (narrow) top — xLights'
      // own coordinate space is y-up, but our canvas draws y-down, so this
      // must be negated or the wide base renders at the top of the screen.
      final y = renderHt / 2 - renderHt * t;
      nodes.add(
        WiredNode(
          node: nodes.length + 1,
          x: x,
          y: y,
          strand: 'Strand ${p.strandIndex + 1}',
          strandIndex: p.strandIndex,
        ),
      );
    }
  } else {
    // Flat (1) / Ribbon (2) — Ribbon treated as Flat with a wider base scale.
    final treeScale = treeType == 2 ? 5.0 : 4.0;
    final renderHt = bufferHt * 2.0;
    for (final p in buffer) {
      final t = bufferHt > 1 ? p.row / (bufferHt - 1) : 0.0;
      final xTop = (p.col + 0.5 - bufferWi / 2) * 0.9;
      final xBottom = (p.col + 0.5 - bufferWi / 2) * treeScale;
      final x = xBottom + (xTop - xBottom) * t;
      // Same y-up-to-y-down flip as the round-mode branch above.
      final y = renderHt / 2 - renderHt * t;
      nodes.add(
        WiredNode(
          node: nodes.length + 1,
          x: x,
          y: y,
          strand: 'Strand ${p.strandIndex + 1}',
          strandIndex: p.strandIndex,
        ),
      );
    }
  }

  return WiredModel.fromNodes(
    name: attrString(root, 'name', fallback: 'Tree'),
    displayAs: 'Tree',
    nodes: nodes,
  );
}

/// 0=Round, 1=Flat, 2=Ribbon. Prefers the modern `TreeType` attribute;
/// legacy files instead spell the style into `DisplayAs` ("Tree Flat",
/// "Tree Ribbon") with no `TreeType` attribute at all.
int _treeType(XmlElement root, String displayAsLower) {
  final explicit = root.getAttribute('TreeType');
  if (explicit != null && explicit.trim().isNotEmpty) {
    return int.tryParse(explicit) ?? 0;
  }
  if (displayAsLower.contains('flat')) return 1;
  if (displayAsLower.contains('ribbon')) return 2;
  return 0;
}

/// Prefers the modern `TreeDegrees` attribute; legacy files instead encode
/// the angular span as a trailing number in `DisplayAs` (e.g. "Tree 120" for
/// a 120° spread), with no `TreeDegrees` attribute at all.
double _treeDegrees(XmlElement root, String displayAsLower) {
  final explicit = root.getAttribute('TreeDegrees');
  if (explicit != null && explicit.trim().isNotEmpty) {
    return double.tryParse(explicit) ?? 360;
  }
  final match = RegExp(r'(\d+(?:\.\d+)?)').firstMatch(displayAsLower);
  return match != null ? double.parse(match.group(1)!) : 360;
}
