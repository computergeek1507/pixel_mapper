# Building & shipping the iOS app without owning a Mac

Building, signing, and uploading an iOS app **requires macOS + Xcode** — it
cannot be done from Windows. You don't have to *buy* a Mac, but you do need
access to one (cloud CI or rented). You also need:

- An **Apple Developer Program** membership — **$99/year** (required to ship to
  the App Store or even to TestFlight).
- App registered in **App Store Connect** with bundle id
  `com.sandbdesigns.pixelMapper` (already set in the Xcode project).

Pick one of the routes below.

---

## Option A — Codemagic (easiest, Flutter-native)
A CI service with hosted Macs and first-class Flutter support; free tier covers
low volume.

1. Connect this GitHub repo at <https://codemagic.io>.
2. Add **App Store Connect API key** (App Store Connect → Users and Access →
   Integrations → App Store Connect API → generate key; upload the `.p8` + IDs to
   Codemagic). Codemagic uses it to manage signing certs/profiles automatically.
3. Workflow steps: `flutter pub get` → `flutter build ipa --release` →
   publish to **App Store Connect / TestFlight**.
4. Codemagic handles code signing (automatic) and the upload.

A starter `codemagic.yaml` (commit at repo root when ready):
```yaml
workflows:
  ios-release:
    name: iOS Release
    instance_type: mac_mini_m2
    integrations:
      app_store_connect: CodemagicASCKey   # name of the key you added
    environment:
      flutter: stable
      ios_signing:
        distribution_type: app_store
        bundle_identifier: com.sandbdesigns.pixelMapper
    scripts:
      - flutter pub get
      - flutter build ipa --release --export-options-plist=/Users/builder/export_options.plist
    artifacts:
      - build/ios/ipa/*.ipa
    publishing:
      app_store_connect:
        auth: integration
        submit_to_testflight: true
```

---

## Option B — GitHub Actions (macOS runner)
Free macOS minutes on public repos. More manual signing setup than Codemagic.

Sketch (`.github/workflows/ios.yml`):
```yaml
on: workflow_dispatch
jobs:
  build:
    runs-on: macos-14
    steps:
      - uses: actions/checkout@v4
      - uses: subosito/flutter-action@v2
        with: { channel: stable }
      - run: flutter pub get
      # Import your distribution cert + provisioning profile from secrets here
      # (e.g. apple-actions/import-codesign-certs), then:
      - run: flutter build ipa --release
      - uses: apple-actions/upload-testflight-build@v1
        with:
          app-path: build/ios/ipa/*.ipa
          # plus issuer-id / api-key-id / api-private-key secrets
```
You manage the signing certificate + provisioning profile yourself (stored as
encrypted GitHub secrets).

---

## Option C — Rented / borrowed Mac
- **MacStadium**, **MacinCloud**, or a friend's Mac.
- One-time setup: install Xcode + Flutter, open `ios/Runner.xcworkspace`, set
  your Team under **Signing & Capabilities**, then:
  ```sh
  flutter build ipa --release
  ```
  Upload `build/ios/ipa/*.ipa` with **Transporter** (free, Mac App Store) or
  Xcode Organizer.

---

## Before any build — checklist
- [x] `NSCameraUsageDescription` + `NSLocalNetworkUsageDescription` in
      `ios/Runner/Info.plist` (done).
- [x] Bundle id `com.sandbdesigns.pixelMapper` (done).
- [ ] Apple Developer Program membership active.
- [ ] App created in App Store Connect with that bundle id.
- [ ] App icon present (run `dart run flutter_launcher_icons` on the Mac).
- [ ] Version/build: `pubspec.yaml` `version:` drives both
      `CFBundleShortVersionString` and `CFBundleVersion`. Bump the build number
      every upload (same as Android).
- [ ] Screenshots captured from the Simulator (see `assets-checklist.md`).
- [ ] Privacy policy URL hosted and entered.

> Note: `media_kit` (RTSP) ships native libs on Windows only and is runtime-gated
> to Windows, so it does not affect the iOS build — the iOS app uses the device
> camera via the `camera` plugin.
