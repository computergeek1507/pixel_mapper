import 'package:flutter/material.dart';

import '../models/custom_grid.dart';
import '../services/coordinate_processor.dart';
import '../services/scan_controller.dart';
import 'export_page.dart';
import 'widgets/preview_painter.dart';

/// Review detected points: see the normalized grid preview, drop bad points,
/// re-scan individual pixels, then continue to export.
class ReviewPage extends StatefulWidget {
  final ScanController scan;

  const ReviewPage({super.key, required this.scan});

  @override
  State<ReviewPage> createState() => _ReviewPageState();
}

class _ReviewPageState extends State<ReviewPage> {
  late CustomGrid _grid;
  int? _busyIndex;

  @override
  void initState() {
    super.initState();
    _recompute();
  }

  void _recompute() =>
      _grid = CoordinateProcessor.normalize(widget.scan.points);

  Future<void> _rescan(int index) async {
    setState(() => _busyIndex = index);
    await widget.scan.rescanOne(index);
    if (mounted) {
      setState(() {
        _busyIndex = null;
        _recompute();
      });
    }
  }

  void _drop(int index) {
    setState(() {
      final p = widget.scan.points[index];
      p.screenXY = null;
      p.manualEdited = true;
      _recompute();
    });
  }

  @override
  Widget build(BuildContext context) {
    final points = widget.scan.points;
    final detected = widget.scan.detectedCount;
    final total = points.length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Review'),
        actions: [
          TextButton.icon(
            onPressed: _grid.cells.isEmpty
                ? null
                : () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => ExportPage(grid: _grid),
                    )),
            icon: const Icon(Icons.arrow_forward),
            label: const Text('Export'),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Column(
        children: [
          AspectRatio(
            aspectRatio: 4 / 3,
            child: Container(
              margin: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(8),
              ),
              clipBehavior: Clip.antiAlias,
              // Pinch / scroll to zoom and drag to pan, to inspect dense nodes.
              child: InteractiveViewer(
                maxScale: 12,
                child: CustomPaint(
                  painter: LayoutPainter(
                    LayoutPainter.fromGrid(_grid),
                    showLabels: true,
                    padding: 18,
                  ),
                  child: const SizedBox.expand(),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('$detected of $total detected · '
                    'grid ${_grid.width}×${_grid.height}'),
                if (detected < total)
                  Text('${total - detected} missing',
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.error)),
              ],
            ),
          ),
          const Divider(height: 16),
          Expanded(
            child: ListView.builder(
              itemCount: points.length,
              itemBuilder: (context, i) {
                final p = points[i];
                return ListTile(
                  dense: true,
                  leading: CircleAvatar(
                    radius: 14,
                    backgroundColor: p.detected
                        ? Colors.green
                        : Theme.of(context).colorScheme.errorContainer,
                    child: Text('${p.nodeIndex + 1}',
                        style: const TextStyle(fontSize: 11)),
                  ),
                  title: Text(p.detected
                      ? '(${p.screenXY!.dx.toStringAsFixed(2)}, '
                          '${p.screenXY!.dy.toStringAsFixed(2)})  '
                          'brightness ${p.brightness}'
                      : 'Not detected'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_busyIndex == i)
                        const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      else
                        IconButton(
                          tooltip: 'Re-scan this pixel',
                          icon: const Icon(Icons.refresh),
                          onPressed: () => _rescan(i),
                        ),
                      if (p.detected)
                        IconButton(
                          tooltip: 'Drop',
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () => _drop(i),
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
        ),
      ),
    );
  }
}
