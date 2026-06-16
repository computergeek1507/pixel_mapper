import 'dart:isolate';
import 'dart:ui';

import 'package:flutter/foundation.dart';

import '../models/detected_point.dart';
import '../models/target_config.dart';
import 'base3_codec.dart';
import 'base3_scanner.dart';
import 'bright_spot_detector.dart';
import 'camera_source.dart';
import 'pixel_output.dart';

enum ScanState { idle, running, done, cancelled, error }

/// How pixels are sequenced during a scan.
/// - [sequential]: one pixel at a time (N frames). Simplest, most robust.
/// - [fastBase3]: xLights' base-3 RGB pattern — every pixel lit each frame,
///   ~log3(N)+2 frames total. Much faster for large props.
enum ScanMode { sequential, fastBase3 }

/// Drives the capture -> detect -> store pipeline: lights each pixel in turn,
/// captures a fresh frame, finds the brightest blob, and records its position.
///
/// Dependencies are injected so the engine can be exercised in tests with fake
/// camera/output implementations (see test/scan_engine_test.dart).
class ScanController extends ChangeNotifier {
  final TargetConfig config;
  final CameraSource camera;
  final BrightSpotDetector detector;
  final PixelOutput output;

  /// Settle time after changing pixels before capturing (LED latch + controller
  /// + UDP jitter). Tunable from the UI.
  int settleDelayMs;

  /// Pixel-sequencing strategy.
  ScanMode mode;

  /// LED drive brightness (0.0–1.0). Lower it to avoid the camera clipping
  /// bright pixels to white, which can defeat the base-3 colour read.
  double get ledBrightness => output.brightness;
  set ledBrightness(double value) => output.brightness = value;

  ScanController({
    required this.config,
    required this.camera,
    PixelOutput? output,
    BrightSpotDetector? detector,
    this.settleDelayMs = 60,
    this.mode = ScanMode.sequential,
  })  : output = output ?? createPixelOutput(config.protocol),
        detector = detector ?? const ImageBrightSpotDetector();

  final List<DetectedPoint> points = [];
  ScanState state = ScanState.idle;
  int currentIndex = -1;

  /// Total capture steps for the current run (pixels, or base-3 frames).
  int stepsTotal = 0;
  String? error;

  /// Most recent captured frame (for live preview) and the black reference.
  Uint8List? lastFrame;
  Uint8List? referenceFrame;

  bool _cancel = false;

  int get detectedCount => points.where((p) => p.detected).length;
  double get progress =>
      stepsTotal == 0 ? 0 : (currentIndex + 1) / stepsTotal;

  /// Runs a full scan using the selected [mode].
  Future<void> start() async {
    if (state == ScanState.running) return;
    _cancel = false;
    error = null;
    state = ScanState.running;
    stepsTotal = mode == ScanMode.fastBase3
        ? Base3Codec.bitsFor(config.pixelCount)
        : config.pixelCount;
    points
      ..clear()
      ..addAll(List.generate(
          config.pixelCount, (i) => DetectedPoint(nodeIndex: i)));
    currentIndex = -1;
    notifyListeners();

    try {
      if (!output.isOpen) await output.open(config);
      if (!camera.isInitialized) await camera.initialize();
      await camera.lockCaptureSettings();

      if (mode == ScanMode.fastBase3) {
        await _runBase3();
      } else {
        await _runSequential();
      }

      await output.blackout();
      if (state == ScanState.running) state = ScanState.done;
    } catch (e) {
      error = e.toString();
      state = ScanState.error;
    } finally {
      notifyListeners();
    }
  }

  /// Sequential scan: light each pixel in turn and detect the single bright spot.
  Future<void> _runSequential() async {
    await output.blackout();
    await _settle();
    referenceFrame = await camera.captureFrame();

    for (var i = 0; i < config.pixelCount; i++) {
      if (_cancel) {
        state = ScanState.cancelled;
        return;
      }
      await _scanInto(points[i]);
      currentIndex = i;
      notifyListeners();
    }
  }

  /// Fast scan: xLights' base-3 RGB pattern. Light every pixel each frame in the
  /// colour of one base-3 digit of its index, capture ~log3(N)+2 frames, then
  /// decode every blob's colour sequence back to a pixel number.
  Future<void> _runBase3() async {
    final numPixels = config.pixelCount;
    final bits = Base3Codec.bitsFor(numPixels);
    final codes =
        List.generate(numPixels, (j) => Base3Codec.encode(j + 1, bits));

    await output.blackout();
    await _settle();
    referenceFrame = await camera.captureFrame();

    final frames = <Uint8List>[];
    for (var i = 0; i < bits; i++) {
      if (_cancel) {
        state = ScanState.cancelled;
        return;
      }
      for (var j = 0; j < numPixels; j++) {
        output.setPixel(
            j, Base3Codec.colorForDigit(codes[j].codeUnitAt(i) - 0x30));
      }
      await output.render();
      await _settle();
      frames.add(await camera.captureFrame());
      lastFrame = frames.last;
      currentIndex = i;
      notifyListeners();
    }

    final refBytes = referenceFrame;
    final decoded = await Isolate.run(
        () => const Base3Scanner().decodeBytes(frames, refBytes, numPixels));
    points
      ..clear()
      ..addAll(decoded);
  }

  /// Re-scans a single pixel (e.g. one the user flagged as wrong in review).
  Future<void> rescanOne(int index) async {
    if (index < 0 || index >= points.length) return;
    try {
      if (!output.isOpen) await output.open(config);
      if (!camera.isInitialized) await camera.initialize();
      if (referenceFrame == null) {
        await output.blackout();
        await _settle();
        referenceFrame = await camera.captureFrame();
      }
      await _scanInto(points[index]);
      await output.blackout();
      notifyListeners();
    } catch (e) {
      error = e.toString();
      notifyListeners();
    }
  }

  Future<void> _scanInto(DetectedPoint point) async {
    await output.lightSingle(point.nodeIndex);
    await _settle();
    final frame = await camera.captureFrame();
    lastFrame = frame;
    final spot = await detector.detect(frame, referenceBytes: referenceFrame);
    point.screenXY = spot != null ? Offset(spot.normX, spot.normY) : null;
    point.brightness = spot?.brightness ?? 0;
    point.manualEdited = false;
  }

  void cancel() => _cancel = true;

  Future<void> _settle() =>
      Future<void>.delayed(Duration(milliseconds: settleDelayMs));

  /// Releases hardware. Call when leaving the scan flow.
  Future<void> close() async {
    cancel();
    await output.blackout().catchError((_) {});
    await output.close();
    await camera.dispose();
  }
}
