import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pixel_mapper/models/target_config.dart';
import 'package:pixel_mapper/services/ddp_sender.dart';
import 'package:pixel_mapper/services/sacn_sender.dart';

int be16(Uint8List p, int o) => (p[o] << 8) | p[o + 1];
int be32(Uint8List p, int o) =>
    (p[o] << 24) | (p[o + 1] << 16) | (p[o + 2] << 8) | p[o + 3];

void main() {
  group('DDP', () {
    test('single packet header + data for 2 pixels', () {
      final rgb = Uint8List.fromList([10, 20, 30, 40, 50, 60]);
      final packets = DdpSender.buildPackets(rgb, 5);

      expect(packets.length, 1);
      final p = packets.first;
      expect(p.length, 10 + 6);
      expect(p[0], 0x41); // VER1 | PUSH (final packet)
      expect(p[1], 5); // sequence
      expect(p[2], 0x00); // data type
      expect(p[3], 0x01); // dest id
      expect(be32(p, 4), 0); // data offset bytes
      expect(be16(p, 8), 6); // data length bytes
      expect(p.sublist(10), rgb);
    });

    test('chunks at 480 pixels; only final packet pushes', () {
      final rgb = Uint8List(500 * 3); // 500 pixels
      for (var i = 0; i < rgb.length; i++) {
        rgb[i] = i & 0xFF;
      }
      final packets = DdpSender.buildPackets(rgb, 3);

      expect(packets.length, 2);
      // First packet: 480 px, no push.
      expect(packets[0][0], 0x40);
      expect(be32(packets[0], 4), 0);
      expect(be16(packets[0], 8), 480 * 3);
      // Second packet: remaining 20 px, push, offset after first chunk.
      expect(packets[1][0], 0x41);
      expect(be32(packets[1], 4), 480 * 3);
      expect(be16(packets[1], 8), 20 * 3);
    });

    test('empty buffer yields no packets', () {
      expect(DdpSender.buildPackets(Uint8List(0), 1), isEmpty);
    });
  });

  group('sACN / E1.31', () {
    test('full-universe packet layout', () {
      final cid = Uint8List(16);
      for (var i = 0; i < 16; i++) {
        cid[i] = i + 1;
      }
      final dmx = Uint8List(512);
      dmx[0] = 111;
      dmx[511] = 222;

      final p = SacnSender.buildPacket(
        universe: 1,
        sequence: 7,
        cid: cid,
        dmxData: dmx,
      );

      expect(p.length, 638);

      // Root layer.
      expect(be16(p, 0), 0x0010); // preamble
      expect(be16(p, 2), 0x0000); // postamble
      expect(String.fromCharCodes(p.sublist(4, 13)), 'ASC-E1.17');
      expect(be16(p, 16), 0x7000 | (638 - 16)); // 0x726E
      expect(be32(p, 18), 0x00000004); // root vector
      expect(p.sublist(22, 38), cid);

      // Framing layer.
      expect(be16(p, 38), 0x7000 | (638 - 38)); // 0x7258
      expect(be32(p, 40), 0x00000002); // framing vector
      expect(String.fromCharCodes(p.sublist(44, 55)), 'PixelMapper');
      expect(p[108], 100); // priority
      expect(p[111], 7); // sequence
      expect(p[112], 0x00); // options
      expect(be16(p, 113), 1); // universe

      // DMP layer.
      expect(be16(p, 115), 0x7000 | (638 - 115)); // 0x720B
      expect(p[117], 0x02); // DMP vector
      expect(p[118], 0xA1); // address & data type
      expect(be16(p, 119), 0x0000); // first prop addr
      expect(be16(p, 121), 0x0001); // increment
      expect(be16(p, 123), 513); // property count (1 + 512)
      expect(p[125], 0x00); // start code
      expect(p[126], 111); // first DMX slot
      expect(p[637], 222); // last DMX slot
    });

    test('universe rollover: 171 RGB pixels span 2 universes (no wrap)', () {
      const cfg = TargetConfig(
        ip: '10.0.0.5',
        pixelCount: 171,
        protocol: Protocol.sacn,
        startUniverse: 1,
      );
      final rgb = Uint8List(171 * 3);
      // Pixel 0 -> universe 1, slot 0..2.
      rgb[0] = 1;
      rgb[1] = 2;
      rgb[2] = 3;
      // Pixel 170 -> universe 2, slot 0..2 (170 pixels fill universe 1).
      rgb[170 * 3] = 7;
      rgb[170 * 3 + 1] = 8;
      rgb[170 * 3 + 2] = 9;

      final universes = SacnSender.mapUniverses(rgb, cfg);

      expect(universes.keys.toSet(), {1, 2});
      expect(universes[1]!.length, 512);
      expect(universes[1]!.sublist(0, 3), [1, 2, 3]);
      // Universe 1 carries 170 whole pixels = 510 channels; ch 510-511 unused.
      expect(universes[1]![510], 0);
      expect(universes[1]![511], 0);
      // Pixel 170 lands at start of universe 2.
      expect(universes[2]!.sublist(0, 3), [7, 8, 9]);
    });

    test('startChannel offsets within first universe', () {
      const cfg = TargetConfig(
        ip: '10.0.0.5',
        pixelCount: 1,
        protocol: Protocol.sacn,
        startUniverse: 1,
        startChannel: 10,
      );
      final rgb = Uint8List.fromList([5, 6, 7]);
      final universes = SacnSender.mapUniverses(rgb, cfg);
      // startChannel 10 (1-based) -> slot index 9.
      expect(universes[1]!.sublist(9, 12), [5, 6, 7]);
    });
  });
}
