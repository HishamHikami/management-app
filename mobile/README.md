# KSA Riyadh Unit — Android & iPhone app

Flutter app for the unit's server (`ksa-riyadh.halacreative.com`). Structured like
`task-manager/mobile`: `api.dart` (HTTP client), `state.dart` (login, roles, counts, push),
`ui.dart` + `picker.dart` (shared widgets and themed sheets), `screens/`.

## Tabs
Home · Tasks · News (announcements) · Meetings · Committees — plus Inbox (bell) and Profile
(avatar) in every tab's top bar. Leaders get a **Create** button for tasks, announcements and
meetings.

## Build
Requires Flutter (stable) and the Android SDK.

```bash
cd mobile
flutter pub get
flutter build apk --release      # build/app/outputs/flutter-apk/app-release.apk
```

Another server: `--dart-define=SERVER=https://other.example.com`, or long-press the logo on the
sign-in screen.

### Signing
Release builds use `android/key.properties` if present (never commit it or the key):

```
storePassword=…
keyPassword=…
keyAlias=unit
storeFile=/path/to/your-release-key.jks
```

Without it the build is signed with the debug key. Android only installs an update over an
existing install when it's signed with the **same** key, so create your key before handing the
app to members:

```bash
keytool -genkey -v -keystore ~/ksa-riyadh-release.jks -keyalg RSA -keysize 2048 -validity 10000 -alias unit
```

## Push
Nothing to configure in the app — see `../docs/PUSH.md`.

## Release builds
GitHub Actions builds the signed Play bundle and the TestFlight upload — see `../docs/RELEASE.md`.

## Rebranding
Colours: `brand` and `gold` in `lib/ui.dart` (+ `res/values/colors.xml`). Logo: `assets/seal.png`, `assets/emblem.png`; icons in `branding/` and the platform icon folders.
Name: `ORG_NAME` / `ORG_SHORT_NAME` on the server; launcher label in `AndroidManifest.xml`.
