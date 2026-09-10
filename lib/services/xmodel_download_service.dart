import 'package:http/http.dart' as http;

/// Downloads a vendor's `.xmodel` file. Transient — the view flow doesn't
/// need to persist it to disk, it's parsed straight into a `WiredModel`.
class XmodelDownloadService {
  static const _timeout = Duration(seconds: 15);

  Future<String> downloadXmodel(String url) async {
    final http.Response response;
    try {
      response = await http.get(Uri.parse(url)).timeout(_timeout);
    } catch (e) {
      throw Exception('Could not download this model: $e');
    }
    if (response.statusCode != 200) {
      throw Exception(
        'Server returned HTTP ${response.statusCode} for this model.',
      );
    }
    return response.body;
  }
}
