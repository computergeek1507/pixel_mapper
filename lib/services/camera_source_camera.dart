import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import 'camera_source.dart';

/// [CameraSource] backed by the first-party `camera` package. Works on Android,
/// iOS, and on Windows via the endorsed `camera_windows` implementation (which
/// supports `takePicture` but not image streaming — fine, we capture stills).
class CameraPackageSource implements CameraSource {
  final int cameraIndex;
  final ResolutionPreset resolution;

  CameraController? _controller;

  CameraPackageSource({
    this.cameraIndex = 0,
    // Higher resolution so densely-packed LEDs stay separable in the capture.
    this.resolution = ResolutionPreset.veryHigh,
  });

  /// Enumerates available cameras (for a picker in the UI).
  static Future<List<CameraDescription>> listCameras() => availableCameras();

  @override
  bool get isInitialized => _controller?.value.isInitialized ?? false;

  @override
  Future<void> initialize() async {
    final cameras = await availableCameras();
    if (cameras.isEmpty) {
      throw StateError('No cameras available on this device.');
    }
    final camera = cameras[cameraIndex.clamp(0, cameras.length - 1)];

    // Try the preferred resolution, then fall back to lower presets. Many
    // Windows webcams (and the virtual "AV stream" devices Windows enumerates)
    // don't support the higher presets and throw on initialize.
    final presets = <ResolutionPreset>[
      resolution,
      ResolutionPreset.high,
      ResolutionPreset.medium,
      ResolutionPreset.low,
    ];
    Object? lastError;
    for (final preset in presets) {
      final controller = CameraController(camera, preset, enableAudio: false);
      try {
        await controller.initialize();
        _controller = controller;
        return;
      } catch (e) {
        lastError = e;
        await controller.dispose().catchError((_) {});
      }
    }
    throw StateError(
        'Could not open "${camera.name}" at any resolution: $lastError');
  }

  @override
  Future<void> lockCaptureSettings() async {
    final c = _controller;
    if (c == null) return;
    // Best-effort; some platforms (notably Windows) don't support these.
    try {
      await c.setExposureMode(ExposureMode.locked);
    } catch (_) {}
    try {
      await c.setFocusMode(FocusMode.locked);
    } catch (_) {}
  }

  @override
  Future<Uint8List> captureFrame() async {
    final c = _controller;
    if (c == null) throw StateError('Camera not initialized.');
    final file = await c.takePicture();
    return file.readAsBytes();
  }

  @override
  Future<void> resumePreview() async {
    try {
      await _controller?.resumePreview();
    } catch (_) {}
  }

  @override
  Widget buildPreview() {
    final c = _controller;
    if (c == null || !c.value.isInitialized) {
      return const ColoredBox(color: Colors.black);
    }
    return CameraPreview(c);
  }

  @override
  Future<void> dispose() async {
    await _controller?.dispose();
    _controller = null;
  }
}
