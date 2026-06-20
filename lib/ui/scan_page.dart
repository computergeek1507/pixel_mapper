import 'dart:math';

import 'package:flutter/material.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../models/target_config.dart';
import '../services/camera_source.dart';
import '../services/scan_controller.dart';
import 'review_page.dart';
import 'widgets/preview_painter.dart';

/// Runs a sequential scan: live camera preview with detected dots overlaid,
/// progress, settle-delay control, and a hand-off to the review screen.
class ScanPage extends StatefulWidget {
  final TargetConfig config;
  final CameraSource camera;
  final ScanMode mode;

  const ScanPage({
    super.key,
    required this.config,
    required this.camera,
    this.mode = ScanMode.sequential,
  });

  @override
  State<ScanPage> createState() => _ScanPageState();
}

class _ScanPageState extends State<ScanPage> {
  late final ScanController _scan;
  bool _cameraReady = false;
  String? _cameraError;
  Rect? _roi; // normalized 0..1, null = full frame
  Offset? _dragStart;

  @override
  void initState() {
    super.initState();
    // A long sequential scan has no touch input, so keep the screen awake —
    // otherwise it sleeps and the camera/scan pauses.
    WakelockPlus.enable();
    _scan = ScanController(
        config: widget.config, camera: widget.camera, mode: widget.mode);
    _scan.addListener(_onChange);
    _initCamera();
  }

  Future<void> _initCamera() async {
    try {
      await widget.camera.initialize();
      await widget.camera.lockCaptureSettings();
      if (mounted) setState(() => _cameraReady = true);
    } catch (e) {
      if (mounted) setState(() => _cameraError = e.toString());
    }
  }

  void _onChange() => setState(() {});

  /// Normalized 0..1 rect from two drag points within a [box]-sized preview.
  Rect _normRect(Offset a, Offset b, Size box) {
    double nx(double v) => (v / box.width).clamp(0.0, 1.0);
    double ny(double v) => (v / box.height).clamp(0.0, 1.0);
    return Rect.fromLTRB(
      min(nx(a.dx), nx(b.dx)),
      min(ny(a.dy), ny(b.dy)),
      max(nx(a.dx), nx(b.dx)),
      max(ny(a.dy), ny(b.dy)),
    );
  }

  @override
  void dispose() {
    WakelockPlus.disable();
    _scan.removeListener(_onChange);
    _scan.close();
    super.dispose();
  }

  Future<void> _goToReview() async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ReviewPage(scan: _scan),
    ));
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final running = _scan.state == ScanState.running;
    return Scaffold(
      appBar: AppBar(title: const Text('Scan')),
      body: SafeArea(
        top: false,
        child: Column(
        children: [
          Expanded(
            child: Container(
              color: Colors.black,
              width: double.infinity,
              child: _cameraError != null
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text('Camera error: $_cameraError',
                            style: const TextStyle(color: Colors.white)),
                      ),
                    )
                  : LayoutBuilder(builder: (context, constraints) {
                      final box = constraints.biggest;
                      return GestureDetector(
                        onPanStart: running
                            ? null
                            : (d) => _dragStart = d.localPosition,
                        onPanUpdate: running
                            ? null
                            : (d) {
                                if (_dragStart == null) return;
                                setState(() => _roi = _normRect(
                                    _dragStart!, d.localPosition, box));
                              },
                        onPanEnd: running
                            ? null
                            : (_) {
                                _dragStart = null;
                                // Ignore tiny accidental drags.
                                if (_roi != null &&
                                    (_roi!.width < 0.05 ||
                                        _roi!.height < 0.05)) {
                                  setState(() => _roi = null);
                                }
                                _scan.roi = _roi;
                              },
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            if (_cameraReady) widget.camera.buildPreview(),
                            CustomPaint(
                              painter: LayoutPainter(
                                LayoutPainter.fromDetected(_scan.points),
                              ),
                            ),
                            CustomPaint(painter: _RoiPainter(_roi)),
                          ],
                        ),
                      );
                    }),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                LinearProgressIndicator(value: running ? _scan.progress : null),
                const SizedBox(height: 8),
                Text(
                  running
                      ? (widget.mode == ScanMode.fastBase3
                          ? 'Capturing frame ${_scan.currentIndex + 1} of '
                              '${_scan.stepsTotal}'
                          : 'Scanning pixel ${_scan.currentIndex + 1} of '
                              '${widget.config.pixelCount} — '
                              '${_scan.detectedCount} found')
                      : _statusText(),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Text('Settle'),
                    Expanded(
                      child: Slider(
                        value: _scan.settleDelayMs.toDouble().clamp(0, 2000),
                        min: 0,
                        max: 2000,
                        divisions: 40,
                        label: '${_scan.settleDelayMs} ms',
                        onChanged: running
                            ? null
                            : (v) => setState(
                                () => _scan.settleDelayMs = v.round()),
                      ),
                    ),
                    Text('${_scan.settleDelayMs} ms'),
                  ],
                ),
                Row(
                  children: [
                    const Text('Brightness'),
                    Expanded(
                      child: Slider(
                        value: _scan.ledBrightness,
                        min: 0.05,
                        max: 1.0,
                        divisions: 19,
                        label: '${(_scan.ledBrightness * 100).round()}%',
                        onChanged: running
                            ? null
                            : (v) => setState(() => _scan.ledBrightness = v),
                      ),
                    ),
                    Text('${(_scan.ledBrightness * 100).round()}%'),
                  ],
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  secondary: const Icon(Icons.lightbulb_outline),
                  title: const Text('Preview lights (all on)'),
                  subtitle: const Text('Light every pixel to frame the camera'),
                  value: _scan.framing,
                  onChanged: (running || !_cameraReady)
                      ? null
                      : (v) => _scan.setFraming(v),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  secondary: const Icon(Icons.filter_alt_outlined),
                  title: const Text('Mask ambient light'),
                  subtitle:
                      const Text('Ignore anything lit in the off frame'),
                  value: _scan.maskAmbient,
                  onChanged: running
                      ? null
                      : (v) => setState(() => _scan.maskAmbient = v),
                ),
                if (widget.mode == ScanMode.fastBase3)
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    secondary: const Icon(Icons.center_focus_strong_outlined),
                    title: const Text('Stabilize (handheld)'),
                    subtitle: const Text(
                        'Turn off for a mounted/tripod camera'),
                    value: _scan.stabilize,
                    onChanged: running
                        ? null
                        : (v) => setState(() => _scan.stabilize = v),
                  ),
                Row(
                  children: [
                    const Icon(Icons.crop_free, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _roi == null
                            ? 'ROI: full frame — drag on the preview to set'
                            : 'ROI set — only this region is scanned',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                    if (_roi != null)
                      TextButton(
                        onPressed: running
                            ? null
                            : () => setState(() {
                                  _roi = null;
                                  _scan.roi = null;
                                }),
                        child: const Text('Clear'),
                      ),
                  ],
                ),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: (!_cameraReady || running)
                            ? null
                            : () => _scan.start(),
                        icon: const Icon(Icons.play_arrow),
                        label: const Text('Start scan'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    if (running)
                      OutlinedButton.icon(
                        onPressed: _scan.cancel,
                        icon: const Icon(Icons.stop),
                        label: const Text('Stop'),
                      )
                    else
                      FilledButton.tonalIcon(
                        onPressed: _scan.detectedCount > 0 ? _goToReview : null,
                        icon: const Icon(Icons.arrow_forward),
                        label: const Text('Review'),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
        ),
      ),
    );
  }

  String _statusText() {
    switch (_scan.state) {
      case ScanState.idle:
        if (!_cameraReady) return 'Initializing camera…';
        return _scan.framing
            ? 'Preview lights on — aim the camera, then press Start.'
            : 'Ready. Dim the room and press Start.';
      case ScanState.done:
        final blobs = _scan.lastBlobsFound;
        final blobInfo = blobs != null ? ' · $blobs LEDs seen by camera' : '';
        return 'Done — ${_scan.detectedCount} of '
            '${widget.config.pixelCount} pixels detected$blobInfo.';
      case ScanState.cancelled:
        return 'Stopped — ${_scan.detectedCount} detected so far.';
      case ScanState.error:
        return 'Error: ${_scan.error}';
      case ScanState.running:
        return '';
    }
  }
}

/// Draws the region-of-interest rectangle over the preview and dims outside it.
class _RoiPainter extends CustomPainter {
  final Rect? roi; // normalized 0..1
  _RoiPainter(this.roi);

  @override
  void paint(Canvas canvas, Size size) {
    final r = roi;
    if (r == null) return;
    final rect = Rect.fromLTRB(r.left * size.width, r.top * size.height,
        r.right * size.width, r.bottom * size.height);
    final dim = Path()
      ..addRect(Offset.zero & size)
      ..addRect(rect)
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(dim, Paint()..color = Colors.black.withValues(alpha: 0.45));
    canvas.drawRect(
      rect,
      Paint()
        ..style = PaintingStyle.stroke
        ..color = Colors.orangeAccent
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(covariant _RoiPainter old) => old.roi != roi;
}
