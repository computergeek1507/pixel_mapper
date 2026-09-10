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

  /// Parses the modern `CustomModelCompressed` attribute: `;`-separated triples
  /// `node,row,col` (an optional 4th `layer` field is ignored — we are 2D).
  /// [width]/[height] come from the model's `CustomWidth`/`CustomHeight`; if
  /// absent (<= 0) they are inferred from the maximum row/col seen.
  factory CustomGrid.fromCompressed(
    String value, {
    int width = 0,
    int height = 0,
  }) {
    final cells = <GridCell>[];
    var maxCol = -1;
    var maxRow = -1;
    for (final triple in value.split(';')) {
      final t = triple.trim();
      if (t.isEmpty) continue;
      final parts = t.split(',');
      if (parts.length < 3) continue;
      final node = int.tryParse(parts[0].trim());
      final row = int.tryParse(parts[1].trim());
      final col = int.tryParse(parts[2].trim());
      if (node == null || row == null || col == null) continue;
      cells.add(GridCell(node: node, col: col, row: row));
      if (col > maxCol) maxCol = col;
      if (row > maxRow) maxRow = row;
    }
    return CustomGrid(
      width: width > 0 ? width : maxCol + 1,
      height: height > 0 ? height : maxRow + 1,
      cells: cells,
    );
  }

  /// Parses the legacy `CustomModel` grid string: rows separated by `;`,
  /// columns by `,`, empty cells blank. Multi-layer strings (separated by `|`)
  /// are flattened to their first layer. Width/height are inferred from the
  /// grid shape.
  factory CustomGrid.fromLegacyGrid(String value) {
    // Take the first layer only for 2D rendering.
    final layer = value.split('|').first;
    final rows = layer.split(';');
    final cells = <GridCell>[];
    var width = 0;
    for (var r = 0; r < rows.length; r++) {
      final colsText = rows[r].split(',');
      if (colsText.length > width) width = colsText.length;
      for (var c = 0; c < colsText.length; c++) {
        final cell = colsText[c].trim();
        if (cell.isEmpty) continue;
        final node = int.tryParse(cell);
        if (node == null) continue;
        cells.add(GridCell(node: node, col: c, row: r));
      }
    }
    return CustomGrid(width: width, height: rows.length, cells: cells);
  }

  /// The `CustomModelCompressed` attribute value. Per xLights' source
  /// (CustomModel::ToCompressed), each triple is `node,row,col` — row before
  /// column — separated by `;`. Ordered by row then column to mirror xLights.
  String toCompressed() {
    final ordered = [...cells]
      ..sort(
        (a, b) =>
            a.row != b.row ? a.row.compareTo(b.row) : a.col.compareTo(b.col),
      );
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
