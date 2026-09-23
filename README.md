# musik mobile

Flutter client for a self-hosted musik server.

## Run

```bash
flutter pub get
flutter run
```

Enter the server URL and `MUSIK_API_TOKEN` on the login screen. Credentials are
stored only in the device preferences.

For a private managed build, values may be injected without changing source:

```bash
flutter build apk --release \
  --dart-define=MUSIK_BASE_URL=https://music.example.com \
  --dart-define=MUSIK_API_TOKEN="$MUSIK_API_TOKEN" \
  --dart-define=MUSIK_PREFER_BAKED_SERVER=true
```

Values supplied through `--dart-define` are recoverable from the resulting
binary. Never publish such an APK or use a privileged long-lived token.

## Checks

```bash
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
```

Build output, signing keys, local SDK paths and environment files are ignored.
The source is available under the [MIT License](LICENSE).

## Public Android release

Public APKs must not contain a server URL, API token, or password. Users enter
their own self-hosted server URL and credentials on first launch.

Create a private signing key once and keep it for every future update:

```bash
cp android/key.properties.example android/key.properties
# Fill in private values and point storeFile at your private .jks file.
flutter build apk --release
```

Never commit `android/key.properties` or the keystore. Losing the keystore means
future APKs cannot update an installed release.
