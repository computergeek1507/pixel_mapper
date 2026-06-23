# Releasing Pixel Mapper to Google Play

## Signing

Release builds are signed with an **upload keystore** at
`android/app/upload-keystore.jks`, with credentials in `android/key.properties`.

**Both files are gitignored — never commit them.** Back them up somewhere safe
(password manager + offline copy). If `key.properties` is absent, the release
build falls back to debug signing so `flutter run --release` still works locally,
but such a build **cannot** be uploaded to Play.

`android/key.properties` (current values — change the passwords and keep them safe):

```
storePassword=pixelmapper2026
keyPassword=pixelmapper2026
keyAlias=upload
storeFile=upload-keystore.jks
```

To regenerate the keystore from scratch:
```sh
cd android/app
keytool -genkeypair -v -keystore upload-keystore.jks -keyalg RSA -keysize 2048 \
  -validity 10000 -alias upload
```

> Enroll in **Play App Signing** (default for new apps). This keystore is only the
> *upload* key — Google holds the real app-signing key, so a lost/compromised
> upload key is recoverable through Play support.

## Build the App Bundle

```sh
flutter build appbundle --release
```

Output: `build/app/outputs/bundle/release/app-release.aab` — this is what you
upload to Play Console.

To bump the version, edit `version:` in `pubspec.yaml` (e.g. `1.0.0+1` →
`1.0.1+2`); the part before `+` is the versionName, the part after is the
versionCode (must increase every upload).

## Build a test APK (sideload / direct install)

```sh
flutter build apk --release
# build/app/outputs/flutter-apk/app-release.apk
```

## Store listing materials

See `store/play/` — `listing.md` (copy), `assets-checklist.md` (graphics + Console
field map), and `privacy-policy.md`.
