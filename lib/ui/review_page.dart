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
  int? _placingIndex; // node awaiting a tap to place/move it
  final TransformationController _transform = TransformationController();
  static const double _previewPad = 18;
  double _previewHeight = 300; // resizable via the drag handle

  @override
  void initState() {
    super.initState();
    _recompute();
  }

  @override
  void dispose() {
    _transform.dispose();
    super.dispose();
  }

  /// Places [index] at the tapped point. [local] is in the preview's content
  /// coordinates (a child of the InteractiveViewer, so already untransformed);
  /// [box] is the content size. Inverts the painter's padding inset.
  void _placeAt(int index, Offset local, Size box) {
    final nx = ((local.dx - _previewPad) / (box.width - 2 * _previewPad))
        .clamp(0.0, 1.0);
    final ny = ((local.dy - _previewPad) / (box.height - 2 * _previewPad))
        .clamp(0.0, 1.0);
    setState(() {
      final p = widget.scan.points[index];
      p.screenXY = Offset(nx, ny);
      p.brightness = p.brightness == 0 ? 1 : p.brightness;
      p.manualEdited = true;
      _placingIndex = null;
      _recompute();
    });
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
          SizedBox(
            height: _previewHeight,
            child: Center(
              child: AspectRatio(
                // Match the camera so nodes keep their true proportions instead
                // of being stretched into a fixed box.
                aspectRatio: widget.scan.camera.previewAspectRatio,
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.black,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  clipBehavior: Clip.antiAlias,
                  // Pinch / scroll to zoom, drag to pan; tap to place when
                  // placing a node.
                  child: InteractiveViewer(
                    transformationController: _transform,
                    maxScale: 12,
                    child: LayoutBuilder(builder: (context, c) {
                      final box = Size(c.maxWidth, c.maxHeight);
                      return GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTapUp: _placingIndex == null
                            ? null
                            : (d) =>
                                _placeAt(_placingIndex!, d.localPosition, box),
                        child: CustomPaint(
                          // Raw detected positions = what the camera saw.
                          painter: LayoutPainter(
                            LayoutPainter.fromDetected(points),
                            showLabels: true,
                            padding: _previewPad,
                          ),
                          child: const SizedBox.expand(),
                        ),
                      );
                    }),
                  ),
                ),
              ),
            ),
          ),
          // Drag handle to resize the preview vs the node list.
          GestureDetector(
            onVerticalDragUpdate: (d) => setState(() {
              final maxH = MediaQuery.of(context).size.height * 0.7;
              _previewHeight = (_previewHeight + d.delta.dy).clamp(120.0, maxH);
            }),
            child: Container(
              height: 20,
              color: Colors.transparent,
              alignment: Alignment.center,
              child: Container(
                width: 44,
                height: 4,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.outline,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          ),
          if (_placingIndex != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              color: Theme.of(context).colorScheme.secondaryContainer,
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Tap the preview to place node ${_placingIndex! + 1}',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                  TextButton(
                    onPressed: () => setState(() => _placingIndex = null),
                    child: const Text('Cancel'),
                  ),
                ],
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
                  selected: _placingIndex == i,
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: p.detected
                            ? 'Move: tap the preview'
                            : 'Place: tap the preview',
                        icon: Icon(p.detected
                            ? Icons.edit_location_alt_outlined
                            : Icons.add_location_alt_outlined),
                        onPressed: () => setState(() => _placingIndex = i),
                      ),
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
