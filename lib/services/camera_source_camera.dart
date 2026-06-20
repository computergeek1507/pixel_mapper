import 'dart:io';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import 'camera_source.dart';

/// Appends a line to `<appSupport>/camera_debug.log` for diagnosing camera
/// failures on devices we can't observe directly.
Future<void> _logCamera(String msg) async {
  try {
    final dir = await getApplicationSupportDirectory();
    final f = File('${dir.path}/camera_debug.log');
    await f.writeAsString('${DateTime.now().toIso8601String()}  $msg\n',
        mode: FileMode.append, flush: true);
  } catch (_) {}
  debugPrint('CAMERA: $msg');
}

/// [CameraSource] backed by the first-party `camera` package. Works on Android,
/// iOS, and on Windows via the endorsed `camera_windows` implementation (which
/// supports `takePicture` but not image streaming — fine, we capture stills).
class CameraPackageSource implements CameraSource {
  final int cameraIndex;
  final ResolutionPreset resolution;

  CameraController? _controller;

  CameraPackageSource({
    this.cameraIndex = 0,
    // `high` (≈720p) renders reliably; veryHigh/max made some back-camera
    // previews come up black on camera_android_camerax. Still plenty of detail
    // for the scan (we capture stills, not a low-res stream).
    this.resolution = ResolutionPreset.high,
  });

  /// Enumerates available cameras (for a picker in the UI).
  static Future<List<CameraDescription>> listCameras() => availableCameras();

  @override
  bool get isInitialized => _controller?.value.isInitialized ?? false;

  @override
  Future<void> initialize() async {
    final cameras = await availableCameras();
    final list = [
      for (var i = 0; i < cameras.length; i++)
        '[$i] "${cameras[i].name}" ${cameras[i].lensDirection.name}'
    ].join(' | ');
    await _logCamera('available (${cameras.length}): $list');
    if (cameras.isEmpty) {
      throw StateError('No cameras available on this device.');
    }
    final idx = cameraIndex.clamp(0, cameras.length - 1);
    final camera = cameras[idx];
    await _logCamera('requested index=$cameraIndex -> using [$idx] "${camera.name}"');

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
        await _logCamera('SUCCESS "${camera.name}" @ $preset');
        return;
      } catch (e) {
        lastError = e;
        await _logCamera('FAIL "${camera.name}" @ $preset: $e');
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
  double get previewAspectRatio {
    final c = _controller;
    if (c != null && c.value.isInitialized) return c.value.aspectRatio;
    return 16 / 9;
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
