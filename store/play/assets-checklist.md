# Pixel Mapper — Play Store Graphic Assets Checklist

Everything Google Play requires before you can publish, with exact specs and where
each item goes in **Play Console → Main store listing** (and a couple of
**Release**/**App content** pages).

## Required graphics

| Asset | Spec | Format | Notes |
|---|---|---|---|
| **App icon** | 512 × 512 px | 32-bit PNG (with alpha) | High-res icon. You already have `assets/icon/app_icon.png` — export/scale it to 512². |
| **Feature graphic** | 1024 × 500 px | PNG or JPG (no alpha) | Banner shown at the top of the listing. Required even if you have no promo video. |
| **Phone screenshots** | min 1080 px on the short side; 16:9 or 9:16; 320–3840 px range | PNG or JPG | **2–8 required.** Capture the Target, Scan, Review, and Export pages. |
| **7" tablet screenshots** | up to 3840 px | PNG/JPG | Optional, but recommended if you mark the app as tablet-friendly. |
| **10" tablet screenshots** | up to 3840 px | PNG/JPG | Optional. |

### Capturing screenshots
On a connected device/emulator:
```sh
flutter run --release
# then, from another terminal:
adb exec-out screencap -p > store/play/screenshots/01-target.png
```
Suggested set: `01-target`, `02-scan`, `03-review`, `04-export`.

### Feature graphic quick recipe
1024×500, dark background (matches the app's adaptive-icon background `#1565C0`),
app name "Pixel Mapper", tagline "Auto-map pixels into xLights", and a few
colored dots suggesting a mapped grid.

## Play Console field map

| Console location | Fill with |
|---|---|
| Main store listing → App name | `Pixel Mapper` (see `listing.md`) |
| Main store listing → Short description | from `listing.md` |
| Main store listing → Full description | from `listing.md` |
| Main store listing → App icon | 512×512 PNG |
| Main store listing → Feature graphic | 1024×500 |
| Main store listing → Phone screenshots | 2–8 images |
| Store settings → App category | Tools |
| Store settings → Tags | see `listing.md` |
| Store settings → Contact details | email / website |
| App content → Privacy policy | URL hosting `privacy-policy.md` |
| App content → Data safety | "No data collected/shared" (see privacy doc) |
| App content → Content rating | IARC questionnaire → Everyone |
| App content → Target audience | 13+ (no kids-specific content) |
| App content → Ads | No ads |

## Pre-launch gotchas
- **Privacy policy URL is mandatory** even for a no-data app. Host `privacy-policy.md`
  somewhere public (GitHub Pages, a Gist, your site) and paste the URL.
- **Data safety form is mandatory** and separate from the privacy policy.
- First upload must be an **AAB** (`.aab`), not an APK — see `../../RELEASE.md`.
- Enroll in **Play App Signing** (default). Your `upload-keystore.jks` is the
  *upload* key; Google holds the real app-signing key, so a lost upload key is
  recoverable via support.
