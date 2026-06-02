import 'package:flutter_test/flutter_test.dart';
import 'package:pixel_mapper/models/detected_point.dart';
import 'package:pixel_mapper/services/coordinate_processor.dart';
import 'package:pixel_mapper/services/xmodel_exporter.dart';
import 'package:xml/xml.dart';

DetectedPoint _pt(int node, double x, double y) =>
    DetectedPoint(nodeIndex: node, screenXY: Offset(x, y), brightness: 200);

void main() {
  group('CoordinateProcessor.normalize', () {
    test('snaps a clean 3x2 grid to integer cells', () {
      // Spacing 0.1 grid, 3 columns x 2 rows.
      final points = [
        _pt(0, 0.1, 0.1),
        _pt(1, 0.2, 0.1),
        _pt(2, 0.3, 0.1),
        _pt(3, 0.1, 0.2),
        _pt(4, 0.2, 0.2),
        _pt(5, 0.3, 0.2),
      ];
      final grid = CoordinateProcessor.normalize(points);

      expect(grid.width, 3);
      expect(grid.height, 2);
      // xLights compressed order is node,row,col (1-based nodes), row-major.
      expect(grid.toCompressed(),
          '1,0,0;2,0,1;3,0,2;4,1,0;5,1,1;6,1,2');
      // Legacy grid: rows joined by ';', cols by ','.
      expect(grid.toLegacyGrid(), '1,2,3;4,5,6');
    });

    test('skips undetected points', () {
      final points = [
        _pt(0, 0.1, 0.1),
        DetectedPoint(nodeIndex: 1), // undetected
        _pt(2, 0.2, 0.1),
      ];
      final grid = CoordinateProcessor.normalize(points);
      // Only nodes 1 and 3 present (node 2 absent).
      expect(grid.cells.map((c) => c.node).toList(), [1, 3]);
    });

    test('resolves collisions to distinct cells', () {
      // Two points at essentially the same spot must not overlap.
      final points = [
        _pt(0, 0.10, 0.10),
        _pt(1, 0.101, 0.101),
        _pt(2, 0.30, 0.10),
      ];
      final grid = CoordinateProcessor.normalize(points);
      final cellKeys =
          grid.cells.map((c) => '${c.col},${c.row}').toSet();
      expect(cellKeys.length, grid.cells.length); // all unique
    });

    test('empty input yields the empty grid', () {
      final grid = CoordinateProcessor.normalize(
          [DetectedPoint(nodeIndex: 0)]);
      expect(grid.cells, isEmpty);
    });
  });

  group('XModelExporter.build', () {
    test('produces valid custommodel XML with expected attributes', () {
      final points = [
        _pt(0, 0.1, 0.1),
        _pt(1, 0.2, 0.1),
        _pt(2, 0.1, 0.2),
      ];
      final grid = CoordinateProcessor.normalize(points);
      final xml = XModelExporter.build(grid, name: 'MappedProp', port: 8);

      final doc = XmlDocument.parse(xml); // throws if malformed
      final root = doc.rootElement;
      expect(root.name.local, 'custommodel');
      expect(root.getAttribute('name'), 'MappedProp');
      expect(root.getAttribute('DisplayAs'), 'Custom');
      expect(root.getAttribute('CustomWidth'), '2');
      expect(root.getAttribute('CustomHeight'), '2');
      expect(root.getAttribute('CustomModelCompressed'),
          grid.toCompressed());
      // Both forms written for cross-version import compatibility.
      expect(root.getAttribute('CustomModel'), grid.toLegacyGrid());

      final conn = root.findElements('ControllerConnection').single;
      expect(conn.getAttribute('Protocol'), 'ws2811');
      expect(conn.getAttribute('Port'), '8');
    });
  });
}
