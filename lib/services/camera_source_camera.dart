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
    final controller = CameraController(
      camera,
      resolution,
      enableAudio: false,
    );
    await controller.initialize();
    _controller = controller;
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
