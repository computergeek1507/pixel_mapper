import 'dart:convert';
import 'dart:typed_data';

import 'package:file_saver/file_saver.dart';
import 'package:flutter/material.dart';

import '../models/custom_grid.dart';
import '../services/xmodel_exporter.dart';

/// Final step: name the model and save it as an xLights `.xmodel` file.
class ExportPage extends StatefulWidget {
  final CustomGrid grid;
  final String defaultName;
  final int port;

  const ExportPage({
    super.key,
    required this.grid,
    this.defaultName = 'MappedModel',
    this.port = 1,
  });

  @override
  State<ExportPage> createState() => _ExportPageState();
}

class _ExportPageState extends State<ExportPage> {
  late final TextEditingController _nameCtrl =
      TextEditingController(text: widget.defaultName);
  late final TextEditingController _portCtrl =
      TextEditingController(text: '${widget.port}');
  String? _message;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _portCtrl.dispose();
    super.dispose();
  }

  String _buildXml() => XModelExporter.build(
        widget.grid,
        name: _nameCtrl.text.trim().isEmpty
            ? 'MappedModel'
            : _nameCtrl.text.trim(),
        port: int.tryParse(_portCtrl.text.trim()) ?? 1,
      );

  Future<void> _save() async {
    final name = _nameCtrl.text.trim().isEmpty
        ? 'MappedModel'
        : _nameCtrl.text.trim();
    try {
      final bytes = Uint8List.fromList(utf8.encode(_buildXml()));
      final path = await FileSaver.instance.saveFile(
        name: name,
        bytes: bytes,
        ext: 'xmodel',
        mimeType: MimeType.other,
      );
      setState(() => _message = 'Saved to $path');
    } catch (e) {
      setState(() => _message = 'Save failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final xml = _buildXml();
    return Scaffold(
      appBar: AppBar(title: const Text('Export .xmodel')),
      body: SafeArea(
        top: false,
        child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _nameCtrl,
            decoration: const InputDecoration(
              labelText: 'Model name',
              border: OutlineInputBorder(),
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _portCtrl,
            decoration: const InputDecoration(
              labelText: 'Controller port',
              border: OutlineInputBorder(),
            ),
            keyboardType: TextInputType.number,
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 16),
          Text(
            'Grid ${widget.grid.width} x ${widget.grid.height}, '
            '${widget.grid.cells.length} pixels placed.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _save,
            icon: const Icon(Icons.save),
            label: const Text('Save .xmodel'),
          ),
          if (_message != null) ...[
            const SizedBox(height: 12),
            Text(_message!, style: Theme.of(context).textTheme.bodySmall),
          ],
          const Divider(height: 32),
          Text('Preview', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),
            child: SelectableText(
              xml,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
            ),
          ),
        ],
        ),
      ),
    );
  }
}
