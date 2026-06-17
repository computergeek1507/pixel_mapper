import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import 'camera_source.dart';

/// [CameraSource] for an RTSP network/IP camera, backed by media_kit. Intended
/// for the Windows path (e.g. an IP camera or a phone running an RTSP server).
///
/// Requires the native libs from `media_kit_libs_video`. Frames are grabbed via
/// [Player.screenshot] off the live video output.
class RtspCameraSource implements CameraSource {
  final String url;

  Player? _player;
  VideoController? _videoController;

  RtspCameraSource(this.url);

  @override
  bool get isInitialized => _player != null;

  @override
  Future<void> initialize() async {
    MediaKit.ensureInitialized();
    final player = Player();
    // Attaching a VideoController is required for screenshot() to have frames.
    final controller = VideoController(player);
    await player.open(Media(url), play: true);
    _player = player;
    _videoController = controller;
  }

  @override
  Future<void> lockCaptureSettings() async {
    // Not applicable to a network stream; exposure is controlled on the camera.
  }

  @override
  Future<Uint8List> captureFrame() async {
    final player = _player;
    if (player == null) throw StateError('RTSP source not initialized.');
    final bytes = await player.screenshot(format: 'image/png');
    if (bytes == null) {
      throw StateError('Failed to grab a frame from the RTSP stream.');
    }
    return bytes;
  }

  @override
  Future<void> resumePreview() async {
    // RTSP preview is a continuous live stream; nothing to resume.
  }

  @override
  Widget buildPreview() {
    final controller = _videoController;
    if (controller == null) return const ColoredBox(color: Colors.black);
    return Video(controller: controller);
  }

  @override
  Future<void> dispose() async {
    await _player?.dispose();
    _player = null;
    _videoController = null;
  }
}
