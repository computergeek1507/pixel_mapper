import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xml/xml.dart';

import '../models/vendor.dart';
import '../models/vendor_model.dart';

const _vendorsUrl =
    'https://raw.githubusercontent.com/xLightsSequencer/xLights/master/download/xlights_vendors.xml';
const _fetchTimeout = Duration(seconds: 10);

/// Result of fetching one vendor's model inventory: either [models] (which
/// may still be a partial list if some `<model>` entries were malformed) or
/// a human-readable [error] — never both, and fetching one vendor never
/// throws in a way that could break the vendor list screen.
class VendorModelsResult {
  final List<VendorModel> models;
  final String? error;
  const VendorModelsResult({this.models = const [], this.error});
  bool get hasError => error != null;
}

/// Fetches and caches xLights' vendor catalog and each vendor's model
/// inventory. Network failures fall back to the last cached copy so the app
/// stays usable offline; a vendor whose own fetch fails does not affect any
/// other vendor.
class VendorCatalogService {
  static const _vendorsCacheKey = 'cache.vendors.xml';

  Future<List<Vendor>> fetchVendors({bool forceRefresh = false}) async {
    final prefs = await SharedPreferences.getInstance();
    String? xml;

    if (!forceRefresh) {
      xml = prefs.getString(_vendorsCacheKey);
    }
    if (xml == null || forceRefresh) {
      try {
        final response = await http
            .get(Uri.parse(_vendorsUrl))
            .timeout(_fetchTimeout);
        if (response.statusCode == 200) {
          xml = response.body;
          await prefs.setString(_vendorsCacheKey, xml);
        }
      } catch (_) {
        // Fall through to the cached copy, if any.
      }
      xml ??= prefs.getString(_vendorsCacheKey);
    }

    if (xml == null) {
      throw Exception(
        'Could not reach the xLights vendor catalog and no offline copy is cached.',
      );
    }

    return _parseVendors(xml);
  }

  List<Vendor> _parseVendors(String xml) {
    try {
      final doc = XmlDocument.parse(xml);
      final vendors = <Vendor>[];
      for (final e in doc.findAllElements('vendor')) {
        final v = Vendor.fromXml(e);
        if (v != null && !isDmxVendor(v.name)) vendors.add(v);
      }
      return vendors;
    } on XmlException {
      return const [];
    }
  }

  Future<VendorModelsResult> fetchVendorModels(
    Vendor vendor, {
    bool forceRefresh = false,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final cacheKey = 'cache.models.${vendor.inventoryUrl}';
    String? xml;

    if (!forceRefresh) {
      xml = prefs.getString(cacheKey);
    }
    if (xml == null || forceRefresh) {
      try {
        final response = await http
            .get(Uri.parse(vendor.inventoryUrl))
            .timeout(_fetchTimeout);
        if (response.statusCode == 200) {
          xml = response.body;
          await prefs.setString(cacheKey, xml);
        } else {
          xml ??= prefs.getString(cacheKey);
          if (xml == null) {
            return VendorModelsResult(
              error: 'Vendor returned HTTP ${response.statusCode}.',
            );
          }
        }
      } catch (e) {
        xml ??= prefs.getString(cacheKey);
        if (xml == null) {
          return VendorModelsResult(error: 'Could not reach this vendor: $e');
        }
      }
    }

    try {
      final doc = XmlDocument.parse(xml);
      final models = <VendorModel>[];
      for (final e in doc.findAllElements('model')) {
        final m = VendorModel.fromXml(e);
        if (m != null) models.add(m);
      }
      return VendorModelsResult(models: models);
    } on XmlException catch (e) {
      return VendorModelsResult(
        error: 'This vendor\'s catalog isn\'t valid XML: ${e.message}',
      );
    }
  }
}
