import 'dart:ui';

import 'package:flutter/foundation.dart';

import '../models/detected_point.dart';
import '../models/target_config.dart';
import 'bright_spot_detector.dart';
import 'camera_source.dart';
import 'pixel_output.dart';

enum ScanState { idle, running, done, cancelled, error }

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

  ScanController({
    required this.config,
    required this.camera,
    PixelOutput? output,
    BrightSpotDetector? detector,
    this.settleDelayMs = 60,
  })  : output = output ?? createPixelOutput(config.protocol),
        detector = detector ?? const ImageBrightSpotDetector();

  final List<DetectedPoint> points = [];
  ScanState state = ScanState.idle;
  int currentIndex = -1;
  String? error;

  /// Most recent captured frame (for live preview) and the black reference.
  Uint8List? lastFrame;
  Uint8List? referenceFrame;

  bool _cancel = false;

  int get detectedCount => points.where((p) => p.detected).length;
  double get progress =>
      config.pixelCount == 0 ? 0 : (currentIndex + 1) / config.pixelCount;

  /// Runs a full sequential scan over all pixels.
  Future<void> start() async {
    if (state == ScanState.running) return;
    _cancel = false;
    error = null;
    state = ScanState.running;
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

      // Capture a black reference frame to subtract ambient hotspots.
      await output.blackout();
      await _settle();
      referenceFrame = await camera.captureFrame();

      for (var i = 0; i < config.pixelCount; i++) {
        if (_cancel) {
          state = ScanState.cancelled;
          break;
        }
        await _scanInto(points[i]);
        currentIndex = i;
        notifyListeners();
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
