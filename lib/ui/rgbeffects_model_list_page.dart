import 'package:flutter/material.dart';

import '../services/rgbeffects_importer.dart';
import '../services/xmodel_importer.dart';
import 'wiring_view_page.dart';

/// Lists every model found in a loaded `xlights_rgbeffects.xml` (the user's
/// whole show layout) — an alternative to browsing the online vendor catalog
/// or loading one `.xmodel` at a time, for viewing wiring on models the user
/// has already built into their own show.
class RgbEffectsModelListPage extends StatefulWidget {
  final String fileName;
  final List<RgbEffectsModelEntry> entries;

  const RgbEffectsModelListPage({
    super.key,
    required this.fileName,
    required this.entries,
  });

  @override
  State<RgbEffectsModelListPage> createState() =>
      _RgbEffectsModelListPageState();
}

class _RgbEffectsModelListPageState extends State<RgbEffectsModelListPage> {
  String _query = '';

  void _open(RgbEffectsModelEntry entry) {
    try {
      final model = entry.build();
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => WiringViewPage(model: model)),
      );
    } on XModelImportException catch (e) {
      final scheme = Theme.of(context).colorScheme;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.message, style: TextStyle(color: scheme.onError)),
          backgroundColor: scheme.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final query = _query.trim().toLowerCase();
    final entries = query.isEmpty
        ? widget.entries
        : widget.entries
              .where((e) => e.name.toLowerCase().contains(query))
              .toList();

    return Scaffold(
      appBar: AppBar(title: Text(widget.fileName)),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: TextField(
              decoration: InputDecoration(
                hintText: 'Filter ${widget.entries.length} models…',
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
            child: entries.isEmpty
                ? Center(
                    child: Text(
                      'No models match that filter.',
                      style: TextStyle(color: muted),
                    ),
                  )
                : ListView.separated(
                    itemCount: entries.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, i) {
                      final entry = entries[i];
                      return ListTile(
                        leading: const Icon(Icons.cable),
                        title: Text(entry.name),
                        subtitle: Text(entry.displayAs),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => _open(entry),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
