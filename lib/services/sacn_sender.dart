import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:uuid/uuid.dart';

import '../models/target_config.dart';
import 'pixel_output.dart';

/// Streaming ACN (sACN / E1.31) sender.
///
/// One 638-byte packet per universe (full 512-slot universe). Three layers:
/// Root / Framing / DMP. All multi-byte fields are big-endian.
/// References: https://wiki.openlighting.org/index.php/E1.31 ,
/// libe131 (github.com/hhromic/libe131), ANSI E1.31-2016.
class SacnSender extends PixelOutput {
  static const int port = 5568;
  static const int slotsPerUniverse = 512;
  static const String sourceName = 'PixelMapper';
  static const int priority = 100;

  static const int channels = TargetConfig.channelsPerPixel; // 3 (RGB)

  /// Component Identifier — a stable 16-byte UUID identifying this source.
  final Uint8List _cid;

  /// Per-universe rolling sequence number (0..255).
  final Map<int, int> _seq = {};

  SacnSender({List<int>? cid})
      : _cid = cid != null
            ? Uint8List.fromList(cid)
            : _cidFromUuid(const Uuid().v4());

  @override
  Future<void> render() async {
    final s = socket;
    if (s == null) return;
    final dest = InternetAddress(cfg.ip);
    final universes = mapUniverses(rgb, cfg);
    universes.forEach((universe, dmx) {
      final packet = buildPacket(
        universe: universe,
        sequence: _nextSequence(universe),
        cid: _cid,
        dmxData: dmx,
      );
      s.send(packet, dest, port);
    });
  }

  int _nextSequence(int universe) {
    final next = ((_seq[universe] ?? 0) + 1) & 0xFF;
    _seq[universe] = next;
    return next;
  }

  /// Groups an RGB frame buffer into per-universe 512-byte DMX blocks.
  ///
  /// Pure function (no socket) so it can be unit-tested directly.
  static Map<int, Uint8List> mapUniverses(Uint8List rgb, TargetConfig cfg) {
    final pixelCount = rgb.length ~/ channels;
    final map = <int, Uint8List>{};

    if (cfg.crossUniverseWrap) {
      // Channels flow continuously; a pixel may straddle two universes.
      for (var n = 0; n < pixelCount; n++) {
        for (var c = 0; c < channels; c++) {
          final abs = (cfg.startChannel - 1) + n * channels + c;
          final universe = cfg.startUniverse + abs ~/ slotsPerUniverse;
          final slot = abs % slotsPerUniverse;
          (map[universe] ??= Uint8List(slotsPerUniverse))[slot] =
              rgb[n * channels + c];
        }
      }
    } else {
      // xLights default: whole pixels per universe (170 RGB pixels = 510 ch).
      final pixelsPerUniverse = slotsPerUniverse ~/ channels; // 170
      for (var n = 0; n < pixelCount; n++) {
        final universe = cfg.startUniverse + n ~/ pixelsPerUniverse;
        final base = (cfg.startChannel - 1) + (n % pixelsPerUniverse) * channels;
        final buf = map[universe] ??= Uint8List(slotsPerUniverse);
        for (var c = 0; c < channels; c++) {
          buf[base + c] = rgb[n * channels + c];
        }
      }
    }
    return map;
  }

  /// Builds a single E1.31 data packet for one [universe]. [dmxData] is the
  /// channel data (without the start code); it is sent as a full universe.
  static Uint8List buildPacket({
    required int universe,
    required int sequence,
    required Uint8List cid,
    required Uint8List dmxData,
    String name = sourceName,
    int priorityValue = priority,
  }) {
    final slotCount = dmxData.length;
    final total = 126 + slotCount; // header through last DMX slot
    final p = Uint8List(total);
    final bd = ByteData.sublistView(p);

    // ---- Root layer ----
    bd.setUint16(0, 0x0010); // preamble size
    bd.setUint16(2, 0x0000); // postamble size
    // ACN packet identifier @4 (12 bytes): "ASC-E1.17\0\0\0"
    const acnId = [
      0x41, 0x53, 0x43, 0x2d, 0x45, 0x31, 0x2e, 0x31, 0x37, 0x00, 0x00, 0x00,
    ];
    p.setRange(4, 16, acnId);
    bd.setUint16(16, 0x7000 | (total - 16)); // root flags & length
    bd.setUint32(18, 0x00000004); // root vector = VECTOR_ROOT_E131_DATA
    p.setRange(22, 38, cid); // CID (16 bytes)

    // ---- Framing layer ----
    bd.setUint16(38, 0x7000 | (total - 38)); // framing flags & length
    bd.setUint32(40, 0x00000002); // framing vector = VECTOR_E131_DATA_PACKET
    final nameBytes = utf8.encode(name);
    for (var i = 0; i < nameBytes.length && i < 63; i++) {
      p[44 + i] = nameBytes[i]; // source name (64 bytes, null-padded)
    }
    p[108] = priorityValue & 0xFF; // priority
    bd.setUint16(109, 0x0000); // synchronization address (none)
    p[111] = sequence & 0xFF; // sequence number
    p[112] = 0x00; // options
    bd.setUint16(113, universe); // universe

    // ---- DMP layer ----
    bd.setUint16(115, 0x7000 | (total - 115)); // DMP flags & length
    p[117] = 0x02; // DMP vector = VECTOR_DMP_SET_PROPERTY
    p[118] = 0xA1; // address type & data type
    bd.setUint16(119, 0x0000); // first property address
    bd.setUint16(121, 0x0001); // address increment
    bd.setUint16(123, slotCount + 1); // property value count (incl. start code)
    p[125] = 0x00; // DMX start code
    p.setRange(126, 126 + slotCount, dmxData);

    return p;
  }

  static Uint8List _cidFromUuid(String uuidStr) {
    final hex = uuidStr.replaceAll('-', '');
    final out = Uint8List(16);
    for (var i = 0; i < 16; i++) {
      out[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return out;
  }
}
