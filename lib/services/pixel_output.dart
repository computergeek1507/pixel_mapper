import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/pixel_color.dart';
import '../models/target_config.dart';
import 'ddp_sender.dart';
import 'sacn_sender.dart';
import 'udp_socket.dart';

/// Abstract pixel-data output. Holds an RGB frame buffer and a UDP socket;
/// concrete subclasses ([DdpSender], [SacnSender]) encode and send the frame.
///
/// Typical use:
/// ```
/// final out = createPixelOutput(cfg.protocol);
/// await out.open(cfg);
/// await out.lightSingle(0);   // light pixel 0 white, all others off
/// await out.blackout();
/// await out.close();
/// ```
abstract class PixelOutput {
  @protected
  late TargetConfig cfg;

  @protected
  UdpSocket? socket;

  /// RGB frame buffer, 3 bytes per pixel.
  @protected
  Uint8List rgb = Uint8List(0);

  /// Global brightness scale (0.0–1.0) applied to every colour written to the
  /// buffer. Lowering it dims the driven LEDs, which reduces the white-clipping
  /// / bloom that can defeat the base-3 colour read. Defaults to full.
  double _brightness = 1.0;

  double get brightness => _brightness;

  set brightness(double value) => _brightness = value.clamp(0.0, 1.0);

  int _scale(int channel) => (channel * _brightness).round().clamp(0, 255);

  /// Re-sends the current frame on a fixed cadence while the output is open.
  /// Pixel controllers in a receive mode (WLED realtime, Falcon "receive
  /// timeout", etc.) revert to their normal output if data stops arriving, so
  /// holding a static frame requires periodic re-transmission. The interval
  /// must be comfortably shorter than the shortest such timeout (WLED's
  /// realtime default is ~2.5 s).
  Timer? _keepAlive;

  /// How often to re-send the current frame as a keep-alive.
  @visibleForTesting
  static const Duration keepAliveInterval = Duration(milliseconds: 800);

  int get pixelCount => rgb.length ~/ 3;

  bool get isOpen => socket != null;

  TargetConfig get config => cfg;

  Future<void> open(TargetConfig config) async {
    cfg = config;
    rgb = Uint8List(config.pixelCount * 3);
    socket = await UdpSocket.create();
  }

  Future<void> close() async {
    _keepAlive?.cancel();
    _keepAlive = null;
    socket?.close();
    socket = null;
  }

  void setPixel(int index, PixelColor c) {
    if (index < 0 || index >= pixelCount) return;
    cfg.colorOrder.write(rgb, index * 3, _scale(c.r), _scale(c.g), _scale(c.b));
  }

  void setAll(PixelColor c) {
    final r = _scale(c.r);
    final g = _scale(c.g);
    final b = _scale(c.b);
    for (var i = 0; i < rgb.length; i += 3) {
      cfg.colorOrder.write(rgb, i, r, g, b);
    }
  }

  /// Blacks out every pixel, lights [index] with [color], and renders.
  Future<void> lightSingle(int index,
      {PixelColor color = PixelColor.white}) async {
    setAll(PixelColor.off);
    setPixel(index, color);
    await render();
  }

  Future<void> blackout() async {
    setAll(PixelColor.off);
    await render();
  }

  /// Sends the current frame now and restarts the keep-alive countdown, so the
  /// next automatic re-send is a full interval away (no redundant back-to-back
  /// packets right after an explicit update).
  Future<void> render() async {
    _restartKeepAlive();
    await sendFrame();
  }

  /// Encodes the current frame buffer into protocol packets and sends them.
  /// Implemented per protocol; call [render] (not this) to also keep the
  /// output alive.
  @protected
  Future<void> sendFrame();

  void _restartKeepAlive() {
    _keepAlive?.cancel();
    if (socket == null) return;
    _keepAlive = Timer.periodic(keepAliveInterval, (_) {
      if (socket == null) return;
      // Fire-and-forget; a transient send error must not kill the timer.
      sendFrame().catchError((_) {});
    });
  }
}

PixelOutput createPixelOutput(Protocol protocol) {
  switch (protocol) {
    case Protocol.ddp:
      return DdpSender();
    case Protocol.sacn:
      return SacnSender();
  }
}
