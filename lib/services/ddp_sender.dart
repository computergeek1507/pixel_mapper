import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'pixel_output.dart';

/// Distributed Display Protocol (DDP) sender.
///
/// Packet = 10-byte header + RGB data. Big-endian offset/length fields.
/// Reference: http://www.3waylabs.com/ddp/ , https://kno.wled.ge/interfaces/ddp/
class DdpSender extends PixelOutput {
  static const int port = 4048;

  /// Max pixels per packet to stay under a typical 1500-byte Ethernet MTU
  /// (480 * 3 = 1440 bytes data + 10 header).
  static const int maxPixelsPerPacket = 480;

  int _sequence = 0;

  @override
  Future<void> sendFrame() async {
    final s = socket;
    if (s == null) return;
    final dest = InternetAddress(cfg.ip);
    final packets = buildPackets(rgb, _nextSequence());
    for (final pkt in packets) {
      s.send(pkt, dest, port);
    }
  }

  int _nextSequence() {
    // DDP sequence is 1..15; 0 means "not used".
    _sequence = _sequence >= 15 ? 1 : _sequence + 1;
    return _sequence;
  }

  /// Builds one or more DDP packets covering [rgb] (3 bytes/pixel). All packets
  /// in a frame share the same [sequence]; only the final packet sets PUSH.
  static List<Uint8List> buildPackets(Uint8List rgb, int sequence) {
    const int destId = 0x01; // default output device
    final pixelCount = rgb.length ~/ 3;
    final packets = <Uint8List>[];

    if (pixelCount == 0) return packets;

    var pixel = 0;
    while (pixel < pixelCount) {
      final chunkPixels = min(maxPixelsPerPacket, pixelCount - pixel);
      final chunkStartByte = pixel * 3;
      final chunkLen = chunkPixels * 3;
      final isLast = (pixel + chunkPixels) >= pixelCount;

      final packet = Uint8List(10 + chunkLen);
      // Byte 0: flags. 0x40 = version 1. PUSH (0x01) on the final packet.
      packet[0] = isLast ? 0x41 : 0x40;
      packet[1] = sequence & 0x0F;
      packet[2] = 0x00; // data type (0 = undefined RGB; ignored by xLights/WLED)
      packet[3] = destId;
      // Bytes 4-7: data offset in bytes, 32-bit big-endian.
      packet[4] = (chunkStartByte >> 24) & 0xFF;
      packet[5] = (chunkStartByte >> 16) & 0xFF;
      packet[6] = (chunkStartByte >> 8) & 0xFF;
      packet[7] = chunkStartByte & 0xFF;
      // Bytes 8-9: data length, 16-bit big-endian.
      packet[8] = (chunkLen >> 8) & 0xFF;
      packet[9] = chunkLen & 0xFF;

      packet.setRange(10, 10 + chunkLen, rgb, chunkStartByte);
      packets.add(packet);
      pixel += chunkPixels;
    }
    return packets;
  }
}
