import 'package:xml/xml.dart';

import '../models/custom_grid.dart';

/// Writes an xLights single-model file (`.xmodel`) for a Custom model. This is
/// the inverse of xlights_layout's parser: it produces the
/// `CustomModelCompressed` representation xLights reads on import.
class XModelExporter {
  /// Builds the `.xmodel` XML string for [grid].
  ///
  /// Mirrors the attribute set xLights itself writes for a custom model export
  /// (Model.cpp: root tag `custommodel`, with both `CustomModel` and
  /// `CustomModelCompressed`). Writing both keeps the file importable by old and
  /// new xLights versions alike.
  ///
  /// [name] is the model name. [port]/[protocol] populate the controller
  /// connection. [stringType] defaults to RGB nodes (WS2811).
  static String build(
    CustomGrid grid, {
    required String name,
    int port = 1,
    String protocol = 'ws2811',
    String stringType = 'RGB Nodes',
    String sourceVersion = 'PixelMapper',
  }) {
    final builder = XmlBuilder();
    builder.processing('xml', 'version="1.0" encoding="UTF-8"');
    builder.element('custommodel', nest: () {
      builder.attribute('name', name);
      builder.attribute('CustomWidth', '${grid.width}');
      builder.attribute('CustomHeight', '${grid.height}');
      builder.attribute('Depth', '1');
      builder.attribute('StringType', stringType);
      builder.attribute('Transparency', '0');
      builder.attribute('PixelSize', '2');
      builder.attribute('Antialias', '1');
      builder.attribute('StrandNames', '');
      builder.attribute('NodeNames', '');
      builder.attribute('LayoutGroup', 'Default');
      builder.attribute('DisplayAs', 'Custom');
      builder.attribute('CustomModel', grid.toLegacyGrid());
      builder.attribute('CustomModelCompressed', grid.toCompressed());
      builder.attribute('SourceVersion', sourceVersion);
      builder.element('ControllerConnection', nest: () {
        builder.attribute('Protocol', protocol);
        builder.attribute('Port', '$port');
      });
    });
    return builder.buildDocument().toXmlString(pretty: true, indent: '  ');
  }
}
