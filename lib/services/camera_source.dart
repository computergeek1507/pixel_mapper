import 'dart:typed_data';

import 'package:flutter/widgets.dart';

/// Abstraction over a camera that can deliver a still frame on demand.
///
/// Implementations:
/// - [CameraPackageSource] (camera package) — Android, iOS, and Windows
///   webcam / Windows 11 Connected Camera.
/// - [RtspCameraSource] (media_kit) — Windows network/IP cameras.
///
/// The scan engine drives capture by calling [captureFrame] once per lit pixel.
/// A still capture is inherently post-settle, which sidesteps the stale-buffered
/// -frame problem of streaming APIs.
abstract class CameraSource {
  bool get isInitialized;

  Future<void> initialize();

  /// Best-effort lock of exposure/focus/white-balance so the detected blob
  /// doesn't drift between frames. No-op where unsupported.
  Future<void> lockCaptureSettings();

  /// Captures the current frame as encoded image bytes (PNG or JPEG).
  Future<Uint8List> captureFrame();

  /// Live preview widget. Returns a black box if not yet initialized.
  Widget buildPreview();

  Future<void> dispose();
}
