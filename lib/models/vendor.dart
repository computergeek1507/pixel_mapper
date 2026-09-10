import 'package:xml/xml.dart';

/// DMX fixtures/models aren't pixel models this app can render — there's
/// nothing useful to browse into for these vendors.
bool isDmxVendor(String vendorName) => vendorName.toLowerCase().contains('dmx');

/// One entry from xLights' `xlights_vendors.xml` (the `<vendor>` elements —
/// `<musicvendor>` entries are unrelated to pixel props and are not modeled).
///
/// [inventoryUrl] is NOT a webpage or a direct model — it points to that
/// vendor's own model-inventory XML (a `<modelinventory>` document), fetched
/// separately per vendor.
class Vendor {
  final String name;
  final String inventoryUrl;
  final int? maxModels;

  const Vendor({
    required this.name,
    required this.inventoryUrl,
    this.maxModels,
  });

  /// Returns null if the entry is missing a name/link or the link isn't a
  /// usable http(s) URL (xlights_vendors.xml has at least one known-malformed
  /// entry) — callers should skip null results rather than crash the list.
  static Vendor? fromXml(XmlElement e) {
    final name = e.getElement('name')?.innerText.trim();
    final link = e.getElement('link')?.innerText.trim();
    if (name == null || name.isEmpty || link == null || link.isEmpty) {
      return null;
    }
    final uri = Uri.tryParse(link);
    if (uri == null || (!uri.isScheme('HTTP') && !uri.isScheme('HTTPS'))) {
      return null;
    }
    final maxModelsText = e.getElement('maxmodels')?.innerText.trim();
    return Vendor(
      name: name,
      inventoryUrl: link,
      maxModels: maxModelsText == null ? null : int.tryParse(maxModelsText),
    );
  }
}
