import 'dart:math' as math;

import 'custom_grid.dart';

/// One physical pixel, positioned in the model's local 2D layout space
/// (arbitrary float units, not screen space — the painter fits/centers this).
class WiredNode {
  /// 1-based xLights wiring/node order. This is what the app visualizes:
  /// "node 1" is the first pixel in the physical wiring chain.
  final int node;
  final double x;
  final double y;

  /// Human label for grouping (e.g. "Strand 1", "Arm 3", "Arch 2") — display
  /// only, not used for rendering logic.
  final String? strand;

  /// 0-based grouping key used to pick a color from the wiring palette.
  final int? strandIndex;

  const WiredNode({
    required this.node,
    required this.x,
    required this.y,
    this.strand,
    this.strandIndex,
  });
}

/// The shape-agnostic result every parser (Custom Model or a native shape)
/// produces. [nodes] is kept in wiring order — list index order IS node
/// order — so the wiring diagram can draw the connecting path by simply
/// iterating the list, with no separate ordering field to keep in sync.
class WiredModel {
  final String name;

  /// The xLights `DisplayAs` value ("Custom", "Matrix", "Arches", ...), used
  /// for the UI badge and in error messages.
  final String displayAs;
  final List<WiredNode> nodes;

  final double minX;
  final double minY;
  final double width;
  final double height;

  const WiredModel({
    required this.name,
    required this.displayAs,
    required this.nodes,
    required this.minX,
    required this.minY,
    required this.width,
    required this.height,
  });

  /// Builds a [WiredModel] from a list of nodes by computing the bounding
  /// box, so every native-shape geometry function can just hand back a flat
  /// node list without repeating this math.
  factory WiredModel.fromNodes({
    required String name,
    required String displayAs,
    required List<WiredNode> nodes,
  }) {
    if (nodes.isEmpty) {
      return WiredModel(
        name: name,
        displayAs: displayAs,
        nodes: nodes,
        minX: 0,
        minY: 0,
        width: 1,
        height: 1,
      );
    }
    var minX = double.infinity, minY = double.infinity;
    var maxX = -double.infinity, maxY = -double.infinity;
    for (final n in nodes) {
      minX = math.min(minX, n.x);
      minY = math.min(minY, n.y);
      maxX = math.max(maxX, n.x);
      maxY = math.max(maxY, n.y);
    }
    return WiredModel(
      name: name,
      displayAs: displayAs,
      nodes: nodes,
      minX: minX,
      minY: minY,
      width: math.max(maxX - minX, 0.0001),
      height: math.max(maxY - minY, 0.0001),
    );
  }

  /// Adapts a parsed Custom-model [CustomGrid] into the unified shape. A
  /// trivial mapping (grid col/row are already local layout coordinates) —
  /// no strand grouping is known for Custom models, so [WiredNode.strand] is
  /// left null.
  factory WiredModel.fromCustomGrid(CustomGrid grid, {required String name}) {
    final sorted = [...grid.cells]..sort((a, b) => a.node.compareTo(b.node));
    return WiredModel.fromNodes(
      name: name,
      displayAs: 'Custom',
      nodes: [
        for (final c in sorted)
          WiredNode(node: c.node, x: c.col.toDouble(), y: c.row.toDouble()),
      ],
    );
  }
}
