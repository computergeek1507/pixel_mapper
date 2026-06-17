import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:pixel_mapper/models/target_config.dart';
import 'package:pixel_mapper/services/camera_source.dart';
import 'package:pixel_mapper/services/pixel_output.dart';
import 'package:pixel_mapper/services/scan_controller.dart';

/// Shared virtual scene: the fake output records which pixel is currently lit,
/// and the fake camera renders a frame with a bright dot at that pixel's known
/// position. Together they simulate the full light -> capture -> detect loop.
class _Scene {
  int lit = -1;
  final Map<int, Offset> positions;
  _Scene(this.positions);
}

class _FakeOutput extends PixelOutput {
  final _Scene scene;
  _FakeOutput(this.scene);

  @override
  Future<void> open(TargetConfig config) async {
    cfg = config;
    rgb = Uint8List(config.pixelCount * 3);
    // No real socket in tests; isOpen stays false so the engine re-opens
    // freely, which just re-sizes the buffer — harmless here.
  }

  @override
  Future<void> sendFrame() async {
    // Find the brightest pixel in the buffer; that's what the "camera" sees.
    var best = -1;
    var bestVal = 0;
    for (var i = 0; i < pixelCount; i++) {
      final v = rgb[i * 3] + rgb[i * 3 + 1] + rgb[i * 3 + 2];
      if (v > bestVal) {
        bestVal = v;
        best = i;
      }
    }
    scene.lit = bestVal > 0 ? best : -1;
  }

  @override
  Future<void> close() async {}
}

class _FakeCamera implements CameraSource {
  final _Scene scene;
  bool _init = false;
  _FakeCamera(this.scene);

  @override
  bool get isInitialized => _init;

  @override
  Future<void> initialize() async => _init = true;

  @override
  Future<void> lockCaptureSettings() async {}

  @override
  Future<void> resumePreview() async {}

  @override
  Future<Uint8List> captureFrame() async {
    final im = img.Image(width: 320, height: 240);
    img.fill(im, color: img.ColorRgb8(6, 6, 6)); // ambient
    final pos = scene.positions[scene.lit];
    if (scene.lit >= 0 && pos != null) {
      img.fillCircle(im,
          x: pos.dx.round(),
          y: pos.dy.round(),
          radius: 5,
          color: img.ColorRgb8(255, 255, 255));
    }
    return img.encodePng(im);
  }

  @override
  Widget buildPreview() => const SizedBox.shrink();

  @override
  Future<void> dispose() async => _init = false;
}

void main() {
  test('scan engine detects each lit pixel and stores its position', () async {
    final positions = {
      0: const Offset(50, 40),
      1: const Offset(160, 120),
      2: const Offset(270, 200),
    };
    final scene = _Scene(positions);
    const cfg = TargetConfig(
      ip: '127.0.0.1',
      pixelCount: 3,
      protocol: Protocol.ddp,
    );

    final ctrl = ScanController(
      config: cfg,
      camera: _FakeCamera(scene),
      output: _FakeOutput(scene),
      settleDelayMs: 0,
      warmupMs: 0,
    );

    await ctrl.start();

    expect(ctrl.state, ScanState.done);
    expect(ctrl.detectedCount, 3);

    expect(ctrl.points[0].screenXY!.dx, closeTo(50 / 320, 0.03));
    expect(ctrl.points[0].screenXY!.dy, closeTo(40 / 240, 0.03));
    expect(ctrl.points[1].screenXY!.dx, closeTo(160 / 320, 0.03));
    expect(ctrl.points[2].screenXY!.dy, closeTo(200 / 240, 0.03));

    await ctrl.close();
  });

  test('undetected pixel (no dot) is recorded as null', () async {
    // Pixel 1 has no position, so the camera shows only ambient -> no detection.
    final scene = _Scene({0: const Offset(80, 80), 2: const Offset(240, 160)});
    const cfg = TargetConfig(ip: '127.0.0.1', pixelCount: 3);

    final ctrl = ScanController(
      config: cfg,
      camera: _FakeCamera(scene),
      output: _FakeOutput(scene),
      settleDelayMs: 0,
      warmupMs: 0,
    );

    await ctrl.start();

    expect(ctrl.state, ScanState.done);
    expect(ctrl.points[0].detected, isTrue);
    expect(ctrl.points[1].detected, isFalse);
    expect(ctrl.points[2].detected, isTrue);
    expect(ctrl.detectedCount, 2);

    await ctrl.close();
  });
}
