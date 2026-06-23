# Screenshots

Captured on the `pixel` Android emulator. Three sets, each matching a Play
Console upload slot:

| Folder | Size | Play Console slot |
|---|---|---|
| `./` (this folder) | 1080 × 2400 | Phone screenshots |
| `tablet7/` | 1200 × 1920 | 7-inch tablet screenshots |
| `tablet/` | 1600 × 2560 | 10-inch tablet screenshots |

Tablet sets were captured by overriding the emulator display size
(`adb shell wm size … / wm density …`) so the responsive Flutter layout
relaid-out at tablet width, then reset afterward. Same four screens, same
real-UI / seeded-data caveats as the phone set below.

# Phone screenshots (1080 × 2400)

All meet Play's phone spec (≥1080 px short side, 16:9 portrait). Upload 2–8
under **Main store listing → Phone screenshots**.

| File | Screen | Notes |
|---|---|---|
| `01-target.png` | Target setup | Real UI — full config form (IP, pixel count, color order, DDP/sACN, scan mode). |
| `02-scan.png`   | Camera scan  | Real UI. Preview shows the **emulator's built-in test scene**, not a light display — replace with a shot from a real scan in a dim room for the best impression. |
| `03-review.png` | Review       | Real UI, seeded with a sample 46-node tree layout so the detected grid is visible (a bare emulator has no LEDs to detect). |
| `04-export.png` | Export       | Real UI, same sample layout — shows the generated `.xmodel` XML preview. |

## Regenerating / replacing
- `01` and `02` come straight from running the app (`flutter run -d <device>`)
  and `adb exec-out screencap -p > file.png`.
- `03` and `04` were captured via a throwaway entrypoint that seeded sample
  detected points into the real Review/Export widgets (deleted after use). The
  ideal replacement is a screenshot from an actual hardware scan.

## Recommended for the listing
Best 4 to upload, in order: **03-review** (the payoff shot), **01-target**,
**02-scan**, **04-export**. Lead with Review — the mapped layout is the most
compelling "what does this app do" image.
