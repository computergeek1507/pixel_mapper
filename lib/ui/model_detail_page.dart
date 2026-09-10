import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/vendor_model.dart';
import '../services/xmodel_download_service.dart';
import '../services/xmodel_importer.dart';
import 'wiring_view_page.dart';

class ModelDetailPage extends StatefulWidget {
  final VendorModel model;
  const ModelDetailPage({super.key, required this.model});

  @override
  State<ModelDetailPage> createState() => _ModelDetailPageState();
}

class _ModelDetailPageState extends State<ModelDetailPage> {
  final _downloadService = XmodelDownloadService();
  // Which wiring option (index into model.wirings) is currently downloading,
  // if any — lets each option show its own spinner without a single global
  // loading flag disabling every other option too.
  int? _loadingIndex;

  Future<void> _viewWiring(int index, ModelWiring wiring) async {
    setState(() => _loadingIndex = index);
    try {
      final xml = await _downloadService.downloadXmodel(wiring.url);
      final wired = importXModel(xml);
      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => WiringViewPage(model: wired)),
      );
    } on XModelImportException catch (e) {
      _showError(e.message);
    } catch (e) {
      _showError('$e');
    } finally {
      if (mounted) setState(() => _loadingIndex = null);
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    final scheme = Theme.of(context).colorScheme;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: TextStyle(color: scheme.onError)),
        backgroundColor: scheme.error,
      ),
    );
  }

  Future<void> _openWeblink(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null ||
        !await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      _showError('Could not open $url');
    }
  }

  @override
  Widget build(BuildContext context) {
    final model = widget.model;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Scaffold(
      appBar: AppBar(title: Text(model.name)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (model.imageFile != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: CachedNetworkImage(
                imageUrl: model.imageFile!,
                fit: BoxFit.contain,
                height: 220,
                errorWidget: (_, _, _) => const SizedBox.shrink(),
              ),
            ),
          const SizedBox(height: 16),
          _detailRow(context, 'Type', model.type),
          _detailRow(context, 'Material', model.material),
          _detailRow(context, 'Width', model.width),
          _detailRow(context, 'Height', model.height),
          _detailRow(context, 'Thickness', model.thickness),
          _detailRow(context, 'Pixel count', model.pixelCount?.toString()),
          _detailRow(context, 'Pixel description', model.pixelDescription),
          _detailRow(context, 'Pixel spacing', model.pixelSpacing),
          if (model.notes != null && model.notes!.isNotEmpty)
            _detailRow(context, 'Notes', model.notes),
          if (model.weblink != null) _weblinkRow(context, model.weblink!),
          const SizedBox(height: 24),
          if (model.wirings.isEmpty)
            Text(
              'This model has no downloadable .xmodel file.',
              style: TextStyle(color: muted),
            )
          else ...[
            if (model.wirings.length > 1)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text('Wiring options', style: TextStyle(color: muted)),
              ),
            for (var i = 0; i < model.wirings.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: FilledButton.icon(
                  onPressed: _loadingIndex == null
                      ? () => _viewWiring(i, model.wirings[i])
                      : null,
                  icon: _loadingIndex == i
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.cable),
                  label: Text(
                    _loadingIndex == i
                        ? 'Loading…'
                        : model.wirings.length > 1
                        ? (model.wirings[i].name ?? 'Wiring ${i + 1}')
                        : 'View Wiring',
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _weblinkRow(BuildContext context, String url) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final link = Theme.of(context).colorScheme.primary;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text('Vendor page', style: TextStyle(color: muted)),
          ),
          Expanded(
            child: InkWell(
              onTap: () => _openWeblink(url),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Flexible(
                    child: Text(
                      url,
                      style: TextStyle(
                        color: link,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(Icons.open_in_new, size: 16, color: link),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _detailRow(BuildContext context, String label, String? value) {
    if (value == null || value.isEmpty) return const SizedBox.shrink();
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(label, style: TextStyle(color: muted)),
          ),
          Expanded(child: SelectableText(value)),
        ],
      ),
    );
  }
}
