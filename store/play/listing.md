# Pixel Mapper — Google Play Store Listing

Copy-and-paste source for the Play Console **Main store listing** page.
Character counts are noted against Google's limits.

---

## App name
> Limit: 30 characters

```
Pixel Mapper
```
(12 chars)

Alternative (more searchable):
```
Pixel Mapper — xLights Mapper
```
(29 chars)

---

## Short description
> Limit: 80 characters. Shown in search results and at the top of the listing.

```
Auto-map WS2811 pixels into an xLights custom model with your phone's camera.
```
(77 chars)

---

## Full description
> Limit: 4000 characters.

```
Pixel Mapper turns your phone into an automatic layout tool for xLights. Point
your camera at your light display, and the app lights each WS2811 / WS2812 pixel,
finds it in the camera image with computer vision, and builds a ready-to-import
xLights Custom model — no manual clicking pixel by pixel.

Perfect for Christmas light displays, props, matrices, megatrees, and any
irregular pixel layout that's painful to map by hand.

HOW IT WORKS
1. Target — enter your controller's IP and pixel count. Output goes over DDP or
   sACN / E1.31, the same protocols xLights and FPP already speak.
2. Scan — choose a mode:
   • Fast (base-3): every pixel lights in every frame, colored by one base-3
     digit of its index, so all pixels are identified in only ~log3(N)+2 frames
     (about 500 pixels in 8 frames). Two checksum digits reject misreads.
   • Sequential: light one pixel at a time and find the single bright blob.
     Slower, but dead simple and rock solid.
   Both modes subtract a black reference frame to ignore ambient hotspots.
3. Review — see the detected layout over your photo, drop bad points, tap to
   place or move a node, and re-scan individual pixels. Zoom and pan to fine-tune.
4. Export — save a standard xLights .xmodel file that imports into both old and
   new versions of xLights.

WHY PIXEL MAPPER
• No more mapping hundreds of pixels by hand.
• Works with the gear you already own — any DDP or sACN/E1.31 pixel controller.
• Fast base-3 scan maps large models in seconds of capture.
• Checksum-protected so misread pixels get rejected, not placed wrong.
• Best results in a dim room; the app locks camera exposure and focus where the
   device supports it.
• Captures a clean 2D layout from a single camera angle.

REQUIREMENTS
• A WS2811 / WS2812 (or compatible) pixel controller reachable on your network.
• The controller set to receive DDP or sACN / E1.31.
• A phone on the same network as the controller.

Pixel Mapper is an independent tool and is not affiliated with or endorsed by the
xLights project. xLights is a trademark of its respective owners.
```

---

## Category & tags
- **App category:** Tools  (alt: House & Home)
- **Tags / search terms to target:** xLights, pixel mapping, WS2811, WS2812, DDP,
  sACN, E1.31, Christmas lights, FPP, custom model, light show, megatree

---

## Contact details (required by Play Console)
- **Email:** scott@scottnation.com
- **Website:** _(add a repo or project URL)_
- **Phone:** _(optional)_

---

## Content rating
Expected: **Everyone**. Complete the IARC questionnaire in Play Console — this app
has no user-generated content, ads, or sensitive material.

---

## Notes on data safety
See `privacy-policy.md`. Summary: the app collects no personal data and sends no
data off-device except pixel-control packets to the controller you configure on
your own LAN.
