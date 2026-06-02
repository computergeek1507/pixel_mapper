/// One pixel placed on the integer Custom-model grid. [node] is the xLights
/// 1-based node number; [col]/[row] are 0-based grid coordinates.
class GridCell {
  final int node;
  final int col;
  final int row;

  const GridCell({required this.node, required this.col, required this.row});
}

/// A normalized xLights Custom model: a [width] x [height] grid holding placed
/// pixels. Undetected pixels are simply absent (xLights tolerates sparse grids).
class CustomGrid {
  final int width;
  final int height;
  final List<GridCell> cells;

  const CustomGrid({
    required this.width,
    required this.height,
    required this.cells,
  });

  static const CustomGrid empty = CustomGrid(width: 1, height: 1, cells: []);

  /// The `CustomModelCompressed` attribute value. Per xLights' source
  /// (CustomModel::ToCompressed), each triple is `node,row,col` — row before
  /// column — separated by `;`. Ordered by row then column to mirror xLights.
  String toCompressed() {
    final ordered = [...cells]
      ..sort((a, b) =>
          a.row != b.row ? a.row.compareTo(b.row) : a.col.compareTo(b.col));
    return ordered.map((c) => '${c.node},${c.row},${c.col}').join(';');
  }

  /// The legacy `CustomModel` grid string xLights still writes alongside the
  /// compressed form (and reads on older versions): a [height] x [width] grid
  /// of node numbers, columns joined by `,`, rows by `;`, empty cells blank.
  /// Single layer (no `|` layer separators) for our 2D models.
  String toLegacyGrid() {
    final grid = List.generate(height, (_) => List.filled(width, ''));
    for (final c in cells) {
      if (c.row >= 0 && c.row < height && c.col >= 0 && c.col < width) {
        grid[c.row][c.col] = '${c.node}';
      }
    }
    return grid.map((row) => row.join(',')).join(';');
  }
}
