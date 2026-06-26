# Changelog

All notable changes to Pixel Mapper are documented here.

## 1.0.1+11 — 2026-06-26

### Fixed
- **Camera preview aspect ratio on Android.** CameraX reports the preview size in
  the sensor's natural landscape orientation, so on a portrait phone the overlay
  was stretched and detected dots rendered as ovals. The overlay box is now sized
  to the displayed aspect ratio (device orientation plus manual mount rotation),
  keeping circles circular.
- **Exported `.xmodel` files are now reachable.** Export used a silent save to the
  app's private Android folder, which the Files app hides. It now opens the system
  "Save to…" picker so models can be saved to Downloads, Drive, etc.

### Added
- **Landscape layout for the Scan screen** — preview on the left, scrollable
  controls on the right. Portrait layout is unchanged.

## 1.0.0+2 — 2026-06-22

- Initial Google Play release: camera-driven WS2811 pixel mapping into xLights
  custom models.
