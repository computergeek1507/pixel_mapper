import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:path_provider/path_provider.dart';

import 'camera_source.dart';

/// Appends a line to `<appSupport>/camera_debug.log` (same file the device
/// camera logs to) for diagnosing media_kit open failures.
Future<void> _log(String msg) async {
  try {
    final dir = await getApplicationSupportDirectory();
    final f = File('${dir.path}/camera_debug.log');
    await f.writeAsString('${DateTime.now().toIso8601String()}  mediakit: $msg\n',
        mode: FileMode.append, flush: true);
  } catch (_) {}
  debugPrint('MEDIAKIT: $msg');
}

/// [CameraSource] backed by media_kit/libmpv. Used on Windows for both RTSP
/// network cameras and local USB/MF webcams via DirectShow
/// (`av://dshow:video=<name>`) — libmpv decodes MJPG-only webcams (e.g. the
/// Logitech C920) that the `camera_windows` preview path can't open.
///
/// Frames are grabbed via [Player.screenshot] off the live video output.
class RtspCameraSource implements CameraSource {
  final String url;

  Player? _player;
  VideoController? _videoController;
  StreamSubscription<String>? _errorSub;

  RtspCameraSource(this.url);

  /// Builds a source for a DirectShow device by friendly name (Windows).
  factory RtspCameraSource.dshow(String deviceName) =>
      RtspCameraSource('av://dshow:video=$deviceName');

  @override
  bool get isInitialized => _player != null;

  @override
  Future<void> initialize() async {
    await _log('opening "$url"');
    MediaKit.ensureInitialized();
    final player = Player();
    // libmpv blocks the av:// (DirectShow device) protocol as "unsafe" by
    // default; allow it so local USB webcams can be opened.
    final platform = player.platform;
    if (platform != null) {
      final p = platform as dynamic;
      Future<void> setProp(String k, String v) async {
        try {
          await p.setProperty(k, v);
        } catch (e) {
          await _log('setProperty $k=$v failed: $e');
        }
      }

      // Allow the av:// (DirectShow device) protocol.
      await setProp('load-unsafe-playlists', 'yes');
      if (url.startsWith('av://')) {
        // Local webcam: minimise buffering so a screenshot reflects the frame
        // on screen *now* (the scan changes the LEDs then grabs a still), and
        // cap the capture format so a heavy 1080p MJPG feed doesn't lag.
        await setProp('cache', 'no');
        await setProp('profile', 'low-latency');
        await setProp('untimed', 'yes');
        await setProp(
            'demuxer-lavf-o', 'fflags=nobuffer,video_size=1280x720,framerate=30');
      }
    }
    // Attaching a VideoController is required for screenshot() to have frames.
    final controller = VideoController(player);
    _errorSub = player.stream.error.listen((e) => _log('error: $e'));
    await player.open(Media(url), play: true);
    _player = player;
    _videoController = controller;
    await _log('opened "$url"');
  }

  @override
  Future<void> lockCaptureSettings() async {
    // Not applicable to a stream/device; exposure is controlled on the camera.
  }

  @override
  Future<Uint8List> captureFrame() async {
    final player = _player;
    if (player == null) throw StateError('Camera source not initialized.');
    // The live feed lags the real scene; after the caller changes the LEDs and
    // settles, wait one feed interval and discard a frame so the screenshot is
    // the *current* scene, not a stale buffered one. Without this, sequential
    // scanning records each pixel from the wrong (lagging) frame.
    await player.screenshot(format: 'image/png');
    await Future<void>.delayed(const Duration(milliseconds: 220));
    final bytes = await player.screenshot(format: 'image/png');
    if (bytes == null) {
      await _log('screenshot returned null for "$url"');
      throw StateError('Failed to grab a frame from "$url".');
    }
    return bytes;
  }

  @override
  Future<void> resumePreview() async {
    // Live stream/device; nothing to resume.
  }

  @override
  Widget buildPreview() {
    final controller = _videoController;
    if (controller == null) return const ColoredBox(color: Colors.black);
    return Video(controller: controller);
  }

  @override
  Future<void> dispose() async {
    await _errorSub?.cancel();
    _errorSub = null;
    await _player?.dispose();
    _player = null;
    _videoController = null;
  }
}
