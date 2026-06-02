import 'dart:ui';

/// One pixel's scan result: where node [nodeIndex] was seen in the camera
/// frame, normalized to 0..1 of the frame's width/height. [screenXY] is null
/// when the pixel was never detected (occluded, off, or too dim).
class DetectedPoint {
  final int nodeIndex;
  Offset? screenXY;
  int brightness;
  bool manualEdited;

  DetectedPoint({
    required this.nodeIndex,
    this.screenXY,
    this.brightness = 0,
    this.manualEdited = false,
  });

  bool get detected => screenXY != null;
}
