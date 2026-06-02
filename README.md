# Pixel Mapper

A cross-platform Flutter app (Android / iOS / Windows) that **automatically builds an
xLights Custom model** by lighting WS2811 pixels one at a time, recording them with a
camera, locating each lit pixel with computer vision, and exporting an xLights `.xmodel`.

## How it works

1. **Target** — point the app at your controller (IP + pixel count) over **DDP** or
   **sACN / E1.31**.
2. **Scan** — the app lights each pixel in turn, captures a camera frame, and finds the
   brightest blob (with a black reference frame subtracted to ignore ambient hotspots).
3. **Review** — see the detected layout, drop bad points, and re-scan individual pixels.
4. **Export** — save an xLights `.xmodel` (a `<custommodel>` with both `CustomModel` and
   `CustomModelCompressed`, so it imports into old and new xLights alike).

## Cameras

- **Android / iOS** and **Windows webcam / Windows 11 Connected Camera** via the `camera` package.
- **RTSP** network/IP cameras on Windows via `media_kit`.

## Project layout

```
lib/
  models/          pixel color, target config, detected point, custom grid
  services/        DDP + sACN senders, camera sources, bright-spot detector,
                   scan engine, coordinate normalizer, .xmodel exporter
  ui/              target setup, scan, review, export pages + preview painter
test/              protocol, detector, scan-engine, and export unit tests
```

## Running

```sh
flutter pub get
flutter run -d windows      # or an attached phone
flutter test                # unit tests (no hardware required)
```

## Notes

- Scanning works best in a dim room; the app locks camera exposure/focus where supported.
- The model is captured in 2D (single camera angle). A 3D depth pass (multiple angles ->
  `WorldPosZ`) is a planned enhancement.
- The xLights compressed format is `node,row,col` triples (1-based node numbers), matching
  xLights' own `CustomModel::ToCompressed`.

🤖 Built with [Claude Code](https://claude.com/claude-code)
