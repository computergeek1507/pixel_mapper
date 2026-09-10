import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../services/rgbeffects_importer.dart';
import '../services/xmodel_importer.dart';
import 'rgbeffects_model_list_page.dart';
import 'vendor_list_page.dart';
import 'wiring_view_page.dart';

/// Entry point for the "Wiring Viewer" tab: browse the xLights vendor
/// catalog, or load a `.xmodel`/`xlights_rgbeffects.xml` straight from
/// device storage, then view the physical wiring order as a pan/zoom
/// diagram. Content-only (no own Scaffold/AppBar) since it lives inside
/// [HomeShell]'s shared TabBarView.
class WiringHomeTab extends StatelessWidget {
  const WiringHomeTab({super.key});

  Future<void> _loadLocalFile(BuildContext context) async {
    final result = await FilePicker.pickFiles(
      dialogTitle: 'Open an xLights .xmodel file',
      type: FileType.custom,
      allowedExtensions: const ['xmodel'],
      withData: true,
    );
    final bytes = result?.files.single.bytes;
    if (bytes == null) return;
    if (!context.mounted) return;

    try {
      final xml = utf8.decode(bytes);
      final model = importXModel(xml);
      if (!context.mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => WiringViewPage(model: model)),
      );
    } on XModelImportException catch (e) {
      if (context.mounted) _showError(context, e.message);
    } catch (e) {
      if (context.mounted) _showError(context, 'Could not read file: $e');
    }
  }

  Future<void> _loadRgbEffects(BuildContext context) async {
    final result = await FilePicker.pickFiles(
      dialogTitle: 'Open xlights_rgbeffects.xml',
      type: FileType.custom,
      allowedExtensions: const ['xml'],
      withData: true,
    );
    final file = result?.files.single;
    if (file?.bytes == null) return;
    if (!context.mounted) return;

    try {
      final xml = utf8.decode(file!.bytes!);
      final entries = parseRgbEffectsModelList(xml);
      if (entries.isEmpty) {
        _showError(context, 'No models found in this file.');
        return;
      }
      if (!context.mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) =>
              RgbEffectsModelListPage(fileName: file.name, entries: entries),
        ),
      );
    } on XModelImportException catch (e) {
      if (context.mounted) _showError(context, e.message);
    } catch (e) {
      if (context.mounted) _showError(context, 'Could not read file: $e');
    }
  }

  void _showError(BuildContext context, String message) {
    final scheme = Theme.of(context).colorScheme;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: TextStyle(color: scheme.onError)),
        backgroundColor: scheme.error,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.cable, size: 64, color: muted),
              const SizedBox(height: 16),
              Text(
                'View the physical pixel wiring order of an xLights model.',
                textAlign: TextAlign.center,
                style: TextStyle(color: muted),
              ),
              const SizedBox(height: 32),
              FilledButton.icon(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const VendorListPage()),
                ),
                icon: const Icon(Icons.store),
                label: const Text('Browse Vendor Catalog'),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () => _loadLocalFile(context),
                icon: const Icon(Icons.folder_open),
                label: const Text('Load .xmodel from device'),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () => _loadRgbEffects(context),
                icon: const Icon(Icons.view_list),
                label: const Text('Load xlights_rgbeffects.xml'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
