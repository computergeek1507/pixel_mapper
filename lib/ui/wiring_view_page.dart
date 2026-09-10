import 'package:flutter/material.dart';

import '../models/wired_model.dart';
import '../services/wiring_print_service.dart';
import '../widgets/wiring_canvas.dart';

class WiringViewPage extends StatefulWidget {
  final WiredModel model;
  const WiringViewPage({super.key, required this.model});

  @override
  State<WiringViewPage> createState() => _WiringViewPageState();
}

class _WiringViewPageState extends State<WiringViewPage> {
  bool _showLabels = true;
  // Default on: you wire a prop from the back, not the front/display side
  // the model's own coordinates describe, so the mirrored view is what most
  // people opening this screen actually need.
  bool _showBackside = true;
  bool _printing = false;

  Future<void> _print() async {
    setState(() => _printing = true);
    try {
      await printWiringDiagram(
        widget.model,
        showLabels: _showLabels,
        showBackside: _showBackside,
      );
    } catch (e) {
      if (mounted) {
        final scheme = Theme.of(context).colorScheme;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Could not print: $e',
              style: TextStyle(color: scheme.onError),
            ),
            backgroundColor: scheme.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _printing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final model = widget.model;
    return Scaffold(
      appBar: AppBar(
        title: Text(model.name),
        actions: [
          IconButton(
            tooltip: _showBackside
                ? 'Showing backside (wiring) view — tap for front/display view'
                : 'Showing front/display view — tap for backside (wiring) view',
            icon: Icon(
              _showBackside
                  ? Icons.flip_camera_android
                  : Icons.flip_camera_android_outlined,
            ),
            onPressed: () => setState(() => _showBackside = !_showBackside),
          ),
          IconButton(
            tooltip: 'Toggle node number labels',
            icon: Icon(_showLabels ? Icons.label : Icons.label_outline),
            onPressed: () => setState(() => _showLabels = !_showLabels),
          ),
          IconButton(
            tooltip: 'Print wiring diagram',
            icon: _printing
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.print),
            onPressed: _printing ? null : _print,
          ),
        ],
      ),
      body: Column(
        children: [
          // Fixed dark bar to match the wiring canvas below it (the canvas is
          // intentionally dark regardless of app theme, for contrast against
          // the colored wiring dots — see WiringPainter).
          Material(
            color: const Color(0xFF22222A),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Chip(label: Text(model.displayAs)),
                  const SizedBox(width: 12),
                  Text(
                    '${model.nodes.length} nodes',
                    style: const TextStyle(color: Colors.white70),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    _showBackside ? 'Backside view' : 'Front/display view',
                    style: const TextStyle(color: Colors.white54),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: WiringCanvas(
              model: model,
              showLabels: _showLabels,
              showBackside: _showBackside,
            ),
          ),
        ],
      ),
    );
  }
}
