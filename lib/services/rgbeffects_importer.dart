import 'package:xml/xml.dart';

import '../models/wired_model.dart';
import 'xmodel_importer.dart';

// Not real wireable pixel models — a saved group of other models, and a
// reference-grid overlay respectively. Filtered out of the list entirely
// rather than left to fail with "unsupported model type" when tapped.
const _nonWireableDisplayAs = {'modelgroup', 'gridlines'};

/// One `<model>` found inside an xLights `xlights_rgbeffects.xml` (the
/// user's full show layout, not a single downloaded `.xmodel`). Keeps the
/// raw [XmlElement] so building its [WiredModel] is deferred until the user
/// actually taps it — the file can list hundreds of models, most of which
/// nobody will look at in a given session.
class RgbEffectsModelEntry {
  final String name;
  final String displayAs;
  final XmlElement _element;

  const RgbEffectsModelEntry._(this.name, this.displayAs, this._element);

  WiredModel build() => importXModel(_element.toXmlString());
}

/// Parses every `<model>` in an xLights show layout file
/// (`xlights_rgbeffects.xml`), regardless of how deeply it's nested under
/// `<xrgb><models type="rgb_effects">...</models></xrgb>` — searching the
/// whole document for `<model>` tags is robust to that wrapper's exact shape
/// and naturally ignores the file's many other sections (palettes, effects,
/// house/controller settings, ...), which use different tag names.
List<RgbEffectsModelEntry> parseRgbEffectsModelList(String xml) {
  final XmlDocument doc;
  try {
    doc = XmlDocument.parse(xml);
  } on XmlException catch (e) {
    throw XModelImportException('Not a valid XML file: ${e.message}');
  }

  final entries = <RgbEffectsModelEntry>[];
  for (final e in doc.findAllElements('model')) {
    final name = e.getAttribute('name');
    if (name == null || name.isEmpty) continue;
    final displayAs = e.getAttribute('DisplayAs') ?? '';
    if (_nonWireableDisplayAs.contains(displayAs.toLowerCase())) continue;
    entries.add(RgbEffectsModelEntry._(name, displayAs, e));
  }
  return entries;
}
