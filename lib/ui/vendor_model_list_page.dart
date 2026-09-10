import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../models/vendor.dart';
import '../models/vendor_model.dart';
import '../services/vendor_catalog_service.dart';
import 'model_detail_page.dart';

class VendorModelListPage extends StatefulWidget {
  final Vendor vendor;
  const VendorModelListPage({super.key, required this.vendor});

  @override
  State<VendorModelListPage> createState() => _VendorModelListPageState();
}

class _VendorModelListPageState extends State<VendorModelListPage> {
  final _service = VendorCatalogService();
  late Future<VendorModelsResult> _future;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _future = _service.fetchVendorModels(widget.vendor);
  }

  void _retry({bool forceRefresh = false}) {
    setState(
      () => _future = _service.fetchVendorModels(
        widget.vendor,
        forceRefresh: forceRefresh,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.vendor.name)),
      body: FutureBuilder<VendorModelsResult>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final result = snapshot.data;
          if (result == null || result.hasError) {
            return _ErrorRetry(
              message: result?.error ?? '${snapshot.error}',
              onRetry: () => _retry(forceRefresh: true),
            );
          }
          if (result.models.isEmpty) {
            return _ErrorRetry(
              message: 'This vendor has no models listed.',
              onRetry: () => _retry(forceRefresh: true),
            );
          }

          final query = _query.trim().toLowerCase();
          final models = query.isEmpty
              ? result.models
              : result.models
                    .where((m) => m.name.toLowerCase().contains(query))
                    .toList();

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: TextField(
                  decoration: InputDecoration(
                    hintText: 'Filter ${result.models.length} models…',
                    prefixIcon: const Icon(Icons.search),
                    isDense: true,
                    border: const OutlineInputBorder(
                      borderRadius: BorderRadius.all(Radius.circular(8)),
                    ),
                  ),
                  onChanged: (v) => setState(() => _query = v),
                ),
              ),
              Expanded(
                child: models.isEmpty
                    ? Center(
                        child: Text(
                          'No models match that filter.',
                          style: TextStyle(
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: () async => _retry(forceRefresh: true),
                        child: ListView.separated(
                          itemCount: models.length,
                          separatorBuilder: (_, _) => const Divider(height: 1),
                          itemBuilder: (context, i) =>
                              _ModelTile(model: models[i]),
                        ),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ModelTile extends StatelessWidget {
  final VendorModel model;
  const _ModelTile({required this.model});

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final subtitleParts = <String>[
      if (model.width != null && model.height != null)
        '${model.width} x ${model.height}',
      if (model.pixelCount != null) '${model.pixelCount} px',
    ];
    return ListTile(
      leading: SizedBox(
        width: 48,
        height: 48,
        child: model.imageFile == null
            ? Icon(Icons.image_not_supported, color: muted)
            : ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: CachedNetworkImage(
                  imageUrl: model.imageFile!,
                  fit: BoxFit.cover,
                  placeholder: (_, _) => const Center(
                    child: SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                  errorWidget: (_, _, _) =>
                      Icon(Icons.image_not_supported, color: muted),
                ),
              ),
      ),
      title: Text(model.name),
      subtitle: subtitleParts.isEmpty ? null : Text(subtitleParts.join(' · ')),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => ModelDetailPage(model: model)),
      ),
    );
  }
}

class _ErrorRetry extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorRetry({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline,
              color: Theme.of(context).colorScheme.error,
              size: 40,
            ),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}
