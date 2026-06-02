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

  int get pixelCount => rgb.length ~/ 3;

  bool get isOpen => socket != null;

  TargetConfig get config => cfg;

  Future<void> open(TargetConfig config) async {
    cfg = config;
    rgb = Uint8List(config.pixelCount * 3);
    socket = await UdpSocket.create();
  }

  Future<void> close() async {
    socket?.close();
    socket = null;
  }

  void setPixel(int index, PixelColor c) {
    if (index < 0 || index >= pixelCount) return;
    final o = index * 3;
    rgb[o] = c.r;
    rgb[o + 1] = c.g;
    rgb[o + 2] = c.b;
  }

  void setAll(PixelColor c) {
    for (var i = 0; i < rgb.length; i += 3) {
      rgb[i] = c.r;
      rgb[i + 1] = c.g;
      rgb[i + 2] = c.b;
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

  /// Encodes the current frame buffer into protocol packets and sends them.
  Future<void> render();
}

PixelOutput createPixelOutput(Protocol protocol) {
  switch (protocol) {
    case Protocol.ddp:
      return DdpSender();
    case Protocol.sacn:
      return SacnSender();
  }
}
