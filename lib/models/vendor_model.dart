import 'package:xml/xml.dart';

/// One `<wiring>` entry under a `<model>` — a model can offer several
/// downloadable `.xmodel` variants (e.g. different accessory/pixel-count
/// options), each with its own [url] and an optional human [name] label.
class ModelWiring {
  final String? name;
  final String url;

  const ModelWiring({this.name, required this.url});
}

/// One `<model>` entry from a vendor's model-inventory XML (e.g. boscoyo.xml).
/// Third-party vendor files are inconsistent, so every field beyond [id]/[name]
/// is optional and defensively parsed — a missing/malformed field must never
/// prevent the rest of the model (or the rest of the vendor's list) from
/// loading.
class VendorModel {
  final int id;
  final String name;
  final String? type;
  final String? weblink;
  final String? material;
  final String? width;
  final String? height;
  final String? thickness;
  final int? pixelCount;
  final String? pixelDescription;
  final String? pixelSpacing;
  final String? notes;
  final String? imageFile;
  final List<ModelWiring> wirings;

  const VendorModel({
    required this.id,
    required this.name,
    this.type,
    this.weblink,
    this.material,
    this.width,
    this.height,
    this.thickness,
    this.pixelCount,
    this.pixelDescription,
    this.pixelSpacing,
    this.notes,
    this.imageFile,
    this.wirings = const [],
  });

  static String? _text(XmlElement e, String tag) {
    final t = e.getElement(tag)?.innerText.trim();
    return (t == null || t.isEmpty) ? null : t;
  }

  /// Returns null if the entry has no usable id/name.
  static VendorModel? fromXml(XmlElement e) {
    final idText = _text(e, 'id');
    final name = _text(e, 'name');
    final id = idText == null ? null : int.tryParse(idText);
    if (id == null || name == null) return null;

    final pixelCountText = _text(e, 'pixelcount');
    return VendorModel(
      id: id,
      name: name,
      type: _text(e, 'type'),
      weblink: _text(e, 'weblink'),
      material: _text(e, 'material'),
      width: _text(e, 'width'),
      height: _text(e, 'height'),
      thickness: _text(e, 'thickness'),
      pixelCount: pixelCountText == null ? null : int.tryParse(pixelCountText),
      pixelDescription: _text(e, 'pixeldescription'),
      pixelSpacing: _text(e, 'pixelspacing'),
      notes: _text(e, 'notes'),
      imageFile: _text(e, 'imagefile'),
      wirings: [
        for (final w in e.findElements('wiring'))
          if (_text(w, 'xmodellink') case final url?)
            ModelWiring(name: _text(w, 'name'), url: url),
      ],
    );
  }
}
