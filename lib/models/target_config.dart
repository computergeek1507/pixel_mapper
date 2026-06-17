/// Wire protocol used to push pixel data to a controller.
enum Protocol {
  ddp('DDP'),
  sacn('sACN / E1.31');

  const Protocol(this.label);
  final String label;
}

/// Order the three colour bytes are sent in on the wire. WS2811/WS2812 strings
/// vary (GRB is very common), and if it's wrong the app's red shows as green —
/// which silently breaks the base-3 colour scan. [c0]/[c1]/[c2] are the logical
/// channels (0=R, 1=G, 2=B) that go in the first/second/third wire byte.
enum ColorOrder {
  rgb('RGB', 0, 1, 2),
  rbg('RBG', 0, 2, 1),
  grb('GRB', 1, 0, 2),
  gbr('GBR', 1, 2, 0),
  brg('BRG', 2, 0, 1),
  bgr('BGR', 2, 1, 0);

  const ColorOrder(this.label, this.c0, this.c1, this.c2);
  final String label;
  final int c0;
  final int c1;
  final int c2;

  /// Writes logical colour [r],[g],[b] into [buf] at [o] in this wire order.
  void write(List<int> buf, int o, int r, int g, int b) {
    final ch = [r, g, b];
    buf[o] = ch[c0];
    buf[o + 1] = ch[c1];
    buf[o + 2] = ch[c2];
  }
}

/// Describes the controller we are driving: its address, how many RGB pixels
/// it has, and protocol-specific addressing.
///
/// The app assumes 3 channels per pixel (WS2811 RGB).
class TargetConfig {
  final String ip;
  final int pixelCount;
  final Protocol protocol;

  /// First sACN universe (1-based). Ignored for DDP.
  final int startUniverse;

  /// First DMX channel within [startUniverse] (1-based). Ignored for DDP.
  final int startChannel;

  /// When true, pixel channels flow continuously across universe boundaries
  /// (a pixel may straddle two universes). xLights' default is false: each
  /// universe holds whole pixels only (170 RGB pixels = 510 channels).
  final bool crossUniverseWrap;

  /// Byte order the LEDs expect on the wire (WS2811 is often GRB).
  final ColorOrder colorOrder;

  const TargetConfig({
    required this.ip,
    required this.pixelCount,
    this.protocol = Protocol.ddp,
    this.startUniverse = 1,
    this.startChannel = 1,
    this.crossUniverseWrap = false,
    this.colorOrder = ColorOrder.rgb,
  });

  /// Channels per pixel — RGB only in this app.
  static const int channelsPerPixel = 3;

  TargetConfig copyWith({
    String? ip,
    int? pixelCount,
    Protocol? protocol,
    int? startUniverse,
    int? startChannel,
    bool? crossUniverseWrap,
    ColorOrder? colorOrder,
  }) {
    return TargetConfig(
      ip: ip ?? this.ip,
      pixelCount: pixelCount ?? this.pixelCount,
      protocol: protocol ?? this.protocol,
      startUniverse: startUniverse ?? this.startUniverse,
      startChannel: startChannel ?? this.startChannel,
      crossUniverseWrap: crossUniverseWrap ?? this.crossUniverseWrap,
      colorOrder: colorOrder ?? this.colorOrder,
    );
  }

  Map<String, dynamic> toJson() => {
        'ip': ip,
        'pixelCount': pixelCount,
        'protocol': protocol.name,
        'startUniverse': startUniverse,
        'startChannel': startChannel,
        'crossUniverseWrap': crossUniverseWrap,
        'colorOrder': colorOrder.name,
      };

  factory TargetConfig.fromJson(Map<String, dynamic> json) {
    return TargetConfig(
      ip: json['ip'] as String? ?? '',
      pixelCount: json['pixelCount'] as int? ?? 0,
      protocol: Protocol.values.firstWhere(
        (p) => p.name == json['protocol'],
        orElse: () => Protocol.ddp,
      ),
      startUniverse: json['startUniverse'] as int? ?? 1,
      startChannel: json['startChannel'] as int? ?? 1,
      crossUniverseWrap: json['crossUniverseWrap'] as bool? ?? false,
      colorOrder: ColorOrder.values.firstWhere(
        (o) => o.name == json['colorOrder'],
        orElse: () => ColorOrder.rgb,
      ),
    );
  }
}
