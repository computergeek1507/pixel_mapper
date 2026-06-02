/// Wire protocol used to push pixel data to a controller.
enum Protocol {
  ddp('DDP'),
  sacn('sACN / E1.31');

  const Protocol(this.label);
  final String label;
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

  const TargetConfig({
    required this.ip,
    required this.pixelCount,
    this.protocol = Protocol.ddp,
    this.startUniverse = 1,
    this.startChannel = 1,
    this.crossUniverseWrap = false,
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
  }) {
    return TargetConfig(
      ip: ip ?? this.ip,
      pixelCount: pixelCount ?? this.pixelCount,
      protocol: protocol ?? this.protocol,
      startUniverse: startUniverse ?? this.startUniverse,
      startChannel: startChannel ?? this.startChannel,
      crossUniverseWrap: crossUniverseWrap ?? this.crossUniverseWrap,
    );
  }

  Map<String, dynamic> toJson() => {
        'ip': ip,
        'pixelCount': pixelCount,
        'protocol': protocol.name,
        'startUniverse': startUniverse,
        'startChannel': startChannel,
        'crossUniverseWrap': crossUniverseWrap,
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
    );
  }
}
