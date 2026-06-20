import 'dart:isolate';
import 'dart:typed_data';
import 'dart:ui' show Rect;

import 'package:image/image.dart' as img;

/// Result of locating the single brightest blob in a frame.
class BrightSpot {
  /// Centroid normalized to 0..1 of the analyzed frame's width/height.
  final double normX;
  final double normY;

  /// Peak signal at the blob (0..255). With a reference frame this is the peak
  /// of the difference image.
  final int brightness;

  /// Number of pixels that passed the blob threshold.
  final int area;

  const BrightSpot({
    required this.normX,
    required this.normY,
    required this.brightness,
    required this.area,
  });

  @override
  String toString() =>
      'BrightSpot(${normX.toStringAsFixed(3)}, ${normY.toStringAsFixed(3)}, '
      'b=$brightness, area=$area)';
}

abstract class BrightSpotDetector {
  /// Decodes [frameBytes] (PNG/JPEG) and returns the brightest blob, or null if
  /// nothing bright enough was found. When [referenceBytes] is given, a black
  /// reference frame is subtracted first to suppress ambient hotspots.
  /// [roi] (normalized 0..1) restricts the search; [maskAmbient] drops pixels
  /// that are bright in the reference (ambient/noise).
  Future<BrightSpot?> detect(
    Uint8List frameBytes, {
    Uint8List? referenceBytes,
    Rect? roi,
    bool maskAmbient = false,
    int maskThreshold = 60,
  });
}

/// Pure-Dart detector built on the `image` package. No native dependencies, so
/// behavior is identical on Android, iOS, and Windows.
class ImageBrightSpotDetector implements BrightSpotDetector {
  /// Peak signal must exceed this for the frame to count as a detection.
  final int minBrightness;

  /// A pixel joins the blob if its signal >= peak * relativeThreshold.
  final double relativeThreshold;

  /// Reject the detection if the blob covers more than this fraction of the
  /// frame (overexposure / glare rather than a single pixel).
  final double maxAreaFraction;

  /// Frames wider than this are downscaled before analysis for speed.
  final int analyzeWidth;

  const ImageBrightSpotDetector({
    this.minBrightness = 40,
    this.relativeThreshold = 0.85,
    this.maxAreaFraction = 0.25,
    this.analyzeWidth = 640,
  });

  @override
  Future<BrightSpot?> detect(
    Uint8List frameBytes, {
    Uint8List? referenceBytes,
    Rect? roi,
    bool maskAmbient = false,
    int maskThreshold = 60,
  }) async {
    // Copy params to locals so the isolate closure doesn't capture `this`.
    final minB = minBrightness;
    final rel = relativeThreshold;
    final maxA = maxAreaFraction;
    final aw = analyzeWidth;

    return Isolate.run(() {
      final decoded = img.decodeImage(frameBytes);
      if (decoded == null) return null;

      var frame = decoded;
      if (frame.width > aw) {
        frame = img.copyResize(frame, width: aw);
      }

      img.Image? ref;
      if (referenceBytes != null) {
        final r = img.decodeImage(referenceBytes);
        if (r != null) {
          ref = img.copyResize(r, width: frame.width, height: frame.height);
        }
      }

      return detectInImage(
        frame,
        reference: ref,
        minBrightness: minB,
        relativeThreshold: rel,
        maxAreaFraction: maxA,
        roi: roi,
        maskAmbient: maskAmbient,
        maskThreshold: maskThreshold,
      );
    });
  }

  static int _luma(img.Image im, int x, int y) {
    final p = im.getPixel(x, y);
    // Rec. 601 luma; channel values are 0..255 for 8-bit images.
    return (0.299 * p.r + 0.587 * p.g + 0.114 * p.b).round();
  }

  /// Core detection on an already-decoded (and optionally downscaled) image.
  /// Exposed for unit testing without isolates or image encoding.
  static BrightSpot? detectInImage(
    img.Image frame, {
    img.Image? reference,
    int minBrightness = 40,
    double relativeThreshold = 0.85,
    double maxAreaFraction = 0.25,
    Rect? roi,
    bool maskAmbient = false,
    int maskThreshold = 60,
  }) {
    final w = frame.width;
    final h = frame.height;
    if (w == 0 || h == 0) return null;

    // Region of interest (pixel bounds); search only inside it.
    final rx0 = roi == null ? 0 : (roi.left * w).round().clamp(0, w);
    final ry0 = roi == null ? 0 : (roi.top * h).round().clamp(0, h);
    final rx1 = roi == null ? w : (roi.right * w).round().clamp(0, w);
    final ry1 = roi == null ? h : (roi.bottom * h).round().clamp(0, h);

    int signal(int x, int y) {
      final amb = reference != null ? _luma(reference, x, y) : 0;
      // Mask: ignore anything bright when the LEDs were off (ambient/noise).
      if (maskAmbient && amb >= maskThreshold) return 0;
      final s = _luma(frame, x, y) - amb;
      return s < 0 ? 0 : s;
    }

    // Pass 1: find the peak signal.
    var peak = 0;
    for (var y = ry0; y < ry1; y++) {
      for (var x = rx0; x < rx1; x++) {
        final s = signal(x, y);
        if (s > peak) peak = s;
      }
    }
    if (peak < minBrightness) return null;

    // Pass 2: intensity-weighted centroid over the blob. A bright LED close to
    // the camera blooms well past maxAreaFraction, but the bloom fades from a
    // hot core, so tightening the threshold toward the peak isolates that core.
    // Genuine glare/overexposure is uniformly bright and stays large even near
    // the peak, so it's still rejected. Try the base threshold first (unchanged
    // behaviour for normal dots), then progressively tighter ones.
    final maxArea = maxAreaFraction * w * h;
    for (final rel in <double>[relativeThreshold, 0.90, 0.95, 0.98]) {
      if (rel < relativeThreshold) continue; // never loosen below the base
      final threshold = peak * rel;
      double sumX = 0, sumY = 0, sumW = 0;
      var area = 0;
      for (var y = ry0; y < ry1; y++) {
        for (var x = rx0; x < rx1; x++) {
          final s = signal(x, y);
          if (s >= threshold) {
            sumX += x * s;
            sumY += y * s;
            sumW += s;
            area++;
          }
        }
      }
      if (sumW <= 0) continue;
      if (area > maxArea) continue; // still too diffuse — tighten further

      return BrightSpot(
        normX: (sumX / sumW) / w,
        normY: (sumY / sumW) / h,
        brightness: peak,
        area: area,
      );
    }
    return null; // even the hot core is too diffuse -> real glare
  }
}
