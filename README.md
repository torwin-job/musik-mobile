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
# musik_app

A new Flutter project.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.
