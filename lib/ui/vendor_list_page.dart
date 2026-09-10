import 'package:flutter/material.dart';

import '../models/vendor.dart';
import '../services/vendor_catalog_service.dart';
import 'vendor_model_list_page.dart';

class VendorListPage extends StatefulWidget {
  const VendorListPage({super.key});

  @override
  State<VendorListPage> createState() => _VendorListPageState();
}

class _VendorListPageState extends State<VendorListPage> {
  final _service = VendorCatalogService();
  late Future<List<Vendor>> _future;

  @override
  void initState() {
    super.initState();
    _future = _service.fetchVendors();
  }

  Future<void> _refresh() async {
    final future = _service.fetchVendors(forceRefresh: true);
    setState(() => _future = future);
    await future;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Vendor Catalog')),
      body: FutureBuilder<List<Vendor>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return _ErrorRetry(
              message: '${snapshot.error}',
              onRetry: () => setState(() => _future = _service.fetchVendors()),
            );
          }
          final vendors = snapshot.data ?? const [];
          if (vendors.isEmpty) {
            return _ErrorRetry(
              message: 'No vendors found.',
              onRetry: () => setState(() => _future = _service.fetchVendors()),
            );
          }
          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView.separated(
              itemCount: vendors.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, i) {
                final vendor = vendors[i];
                return ListTile(
                  leading: const Icon(Icons.storefront),
                  title: Text(vendor.name),
                  subtitle: vendor.maxModels != null
                      ? Text('${vendor.maxModels} models')
                      : null,
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => VendorModelListPage(vendor: vendor),
                    ),
                  ),
                );
              },
            ),
          );
        },
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
