import 'package:xml/xml.dart';

import '../models/custom_grid.dart';
import '../models/wired_model.dart';
import 'geometry/arches_geometry.dart';
import 'geometry/circle_geometry.dart';
import 'geometry/matrix_geometry.dart';
import 'geometry/single_line_geometry.dart';
import 'geometry/spinner_geometry.dart';
import 'geometry/star_geometry.dart';
import 'geometry/tree_geometry.dart';

/// Thrown when a `.xmodel` file can't be turned into a [WiredModel] —
/// invalid XML, a DMX fixture (no pixel grid), or a model shape not yet
/// supported.
class XModelImportException implements Exception {
  final String message;
  XModelImportException(this.message);
  @override
  String toString() => message;
}

const List<String> supportedShapeNames = [
  'Custom',
  'Matrix',
  'Single Line',
  'Arches',
  'Tree',
  'Circle',
  'Star',
  'Spinner',
];

typedef _Builder = WiredModel Function(XmlElement);

final Map<String, _Builder> _nativeGeometries = {
  'matrix': buildMatrix,
  'vert matrix': buildMatrix,
  'horiz matrix': buildMatrix,
  'single line': buildSingleLine,
  'arches': buildArches,
  'circle': buildCircle,
  'star': buildStar,
  'spinner': buildSpinner,
};

/// Parses an xLights model file (`.xmodel`) into a [WiredModel].
///
/// Two on-disk shapes exist in the wild: a vendor-distributed single-model
/// file has the model straight at the document root (root tag
/// `<custommodel>` for grid models, or a shape-named root with `DisplayAs`
/// for native shapes); xLights' own File > Export Models feature instead
/// wraps one or more `<model DisplayAs="...">` elements in a
/// `<models type="exported">` root. Both are unwrapped to the same model
/// element before dispatch, so either file works identically.
///
/// A `<custommodel>` tag OR a `DisplayAs="Custom"` attribute (the wrapped
/// export format uses a generic `<model>` tag with `DisplayAs` doing the
/// work) goes through the [CustomGrid] parser (inverse of pixel_mapper's own
/// `XModelExporter`, preferring the modern `CustomModelCompressed` attribute
/// with a legacy `CustomModel` fallback). Everything else is dispatched by
/// its `DisplayAs` attribute to a native shape geometry builder. DMX
/// fixtures and unrecognized shapes are rejected with a clear message rather
/// than crashing.
WiredModel importXModel(String xml) {
  final XmlDocument doc;
  try {
    doc = XmlDocument.parse(xml);
  } on XmlException catch (e) {
    throw XModelImportException('Not a valid XML file: ${e.message}');
  }

  var root = doc.rootElement;
  var tag = root.name.local.toLowerCase();

  if (tag == 'models') {
    final modelChildren = root.childElements.where(
      (e) => e.name.local.toLowerCase() == 'model',
    );
    if (modelChildren.isEmpty) {
      throw XModelImportException('No <model> found inside this file.');
    }
    root = modelChildren.first;
    tag = root.name.local.toLowerCase();
  }

  final name = root.getAttribute('name') ?? 'Model';
  final displayAs = (root.getAttribute('DisplayAs') ?? '').toLowerCase();

  if (tag == 'custommodel' || displayAs == 'custom') {
    return WiredModel.fromCustomGrid(_importCustomGrid(root), name: name);
  }
  if (tag == 'dmxmodel') {
    throw XModelImportException(
      'This is a DMX fixture model, not a pixel grid — nothing to render.',
    );
  }

  // Some vendor exports use a shape-named root tag (`<treemodel>`,
  // `<matrixmodel>`, ...) instead of a generic `<model DisplayAs="...">`;
  // fall back to that when DisplayAs is missing entirely.
  final shapeKey = displayAs.isNotEmpty
      ? displayAs
      : (tag.endsWith('model')
            ? tag.substring(0, tag.length - 'model'.length)
            : tag);

  // Legacy files spell Tree's degree span or Flat/Ribbon style directly into
  // DisplayAs ("Tree 120", "Tree Flat", ...) instead of separate TreeType/
  // TreeDegrees attributes, so match on prefix rather than an exact string.
  final builder = shapeKey.startsWith('tree')
      ? buildTree
      : _nativeGeometries[shapeKey];
  if (builder == null) {
    throw XModelImportException(
      "Unsupported model type '${root.getAttribute('DisplayAs') ?? tag}'. "
      'Supported: ${supportedShapeNames.join(', ')}.',
    );
  }
  final model = builder(root);
  if (model.nodes.isEmpty) {
    throw XModelImportException('No pixel data found in this model.');
  }
  return model;
}

CustomGrid _importCustomGrid(XmlElement root) {
  final width = int.tryParse(root.getAttribute('CustomWidth') ?? '') ?? 0;
  final height = int.tryParse(root.getAttribute('CustomHeight') ?? '') ?? 0;

  final compressed = root.getAttribute('CustomModelCompressed');
  if (compressed != null && compressed.trim().isNotEmpty) {
    final grid = CustomGrid.fromCompressed(
      compressed,
      width: width,
      height: height,
    );
    if (grid.cells.isNotEmpty) return grid;
  }

  final legacy = root.getAttribute('CustomModel');
  if (legacy != null && legacy.trim().isNotEmpty) {
    final grid = CustomGrid.fromLegacyGrid(legacy);
    if (grid.cells.isNotEmpty) return grid;
  }

  throw XModelImportException(
    'No pixel data found (empty CustomModel / CustomModelCompressed).',
  );
}
