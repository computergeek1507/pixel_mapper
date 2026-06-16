import 'package:flutter/material.dart';

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

  @override
  void initState() {
    super.initState();
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

  @override
  void dispose() {
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
                  : Stack(
                      fit: StackFit.expand,
                      children: [
                        if (_cameraReady) widget.camera.buildPreview(),
                        CustomPaint(
                          painter: LayoutPainter(
                            LayoutPainter.fromDetected(_scan.points),
                          ),
                        ),
                      ],
                    ),
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
                        value: _scan.settleDelayMs.toDouble(),
                        min: 0,
                        max: 300,
                        divisions: 30,
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
        return _cameraReady
            ? 'Ready. Dim the room and press Start.'
            : 'Initializing camera…';
      case ScanState.done:
        return 'Done — ${_scan.detectedCount} of '
            '${widget.config.pixelCount} pixels detected.';
      case ScanState.cancelled:
        return 'Stopped — ${_scan.detectedCount} detected so far.';
      case ScanState.error:
        return 'Error: ${_scan.error}';
      case ScanState.running:
        return '';
    }
  }
}
