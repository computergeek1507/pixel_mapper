import 'dart:isolate';
import 'dart:ui';

import 'package:flutter/foundation.dart';

import '../models/detected_point.dart';
import '../models/pixel_color.dart';
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
  set ledBrightness(double value) {
    output.brightness = value;
    // Reflect the new brightness immediately on the framing preview lights.
    if (_framing && state != ScanState.running) {
      output.setAll(PixelColor.blue);
      output.render();
    }
  }

  /// Whether the framing preview ("light every pixel so you can aim the camera
  /// before scanning") is currently on.
  bool _framing = false;
  bool get framing => _framing;

  /// Lights every pixel blue (at the current [ledBrightness]) so the prop is
  /// visible in the live preview for framing, or blacks them out again. Blue is
  /// the dimmest channel for most cameras, so it frames without blooming to
  /// white. No-op while a scan is running.
  Future<void> setFraming(bool on) async {
    if (state == ScanState.running) return;
    _framing = on;
    notifyListeners();
    try {
      if (!output.isOpen) await output.open(config);
      if (on) {
        output.setAll(PixelColor.blue);
        await output.render();
      } else {
        await output.blackout();
      }
    } catch (e) {
      error = e.toString();
      _framing = false;
      notifyListeners();
    }
  }

  ScanController({
    required this.config,
    required this.camera,
    PixelOutput? output,
    BrightSpotDetector? detector,
    this.settleDelayMs = 60,
    this.mode = ScanMode.sequential,
    this.warmupMs = 1500,
    this.framesPerState = 3,
  })  : output = output ?? createPixelOutput(config.protocol),
        detector = detector ?? const ImageBrightSpotDetector();

  /// Time to light the whole prop before capturing, so a camera we can't lock
  /// (e.g. the C920 via media_kit) settles its auto focus/exposure on the lit
  /// scene first. The base-3 frames keep every pixel lit, so it stays stable.
  int warmupMs;

  /// Stills captured per base-3 frame in fast mode. The decoder majority-votes
  /// each LED's colour across them, so a single bad still (motion, glare,
  /// autofocus blip) doesn't corrupt the read — like xLights' video approach.
  int framesPerState;

  final List<DetectedPoint> points = [];
  ScanState state = ScanState.idle;
  int currentIndex = -1;

  /// Total capture steps for the current run (pixels, or base-3 frames).
  int stepsTotal = 0;
  String? error;

  /// Distinct LED peaks found by the last fast (base-3) decode. If this is far
  /// below the pixel count, the camera couldn't separate the LEDs (move back /
  /// raise resolution) rather than the decode failing.
  int? lastBlobsFound;

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
    _framing = false; // the scan drives the lights from here
    error = null;
    lastBlobsFound = null;
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
      // The still-capture burst can leave the live preview paused; resume it so
      // framing (and the preview lights) work again after a scan.
      await camera.resumePreview().catchError((_) {});
      notifyListeners();
    }
  }

  /// Lights the whole prop and holds, letting the live preview drive the
  /// camera's auto focus/exposure to settle on the lit scene before capture.
  Future<void> _warmUp() async {
    if (warmupMs <= 0) return;
    output.setAll(PixelColor.white);
    await output.render();
    await Future<void>.delayed(Duration(milliseconds: warmupMs));
  }

  /// Sequential scan: light each pixel in turn and detect the single bright spot.
  Future<void> _runSequential() async {
    await _warmUp();
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

    await _warmUp();
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
      // Capture several stills of this frame; the decoder majority-votes each
      // LED's colour across them to reject any single bad still.
      final repeats = framesPerState < 1 ? 1 : framesPerState;
      for (var k = 0; k < repeats; k++) {
        frames.add(await camera.captureFrame());
      }
      lastFrame = frames.last;
      currentIndex = i;
      notifyListeners();
    }

    final refBytes = referenceFrame;
    final repeats = framesPerState < 1 ? 1 : framesPerState;
    final result = await Isolate.run(() =>
        const Base3Scanner().decodeBytes(frames, refBytes, numPixels, repeats));
    lastBlobsFound = result.blobsFound;
    points
      ..clear()
      ..addAll(result.points);
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
