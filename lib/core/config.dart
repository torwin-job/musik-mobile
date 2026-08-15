/// Public-safe build defaults.
///
/// Private builds can inject values without committing them:
/// `flutter build apk --release
///   --dart-define=MUSIK_BASE_URL=https://music.example.com
///   --dart-define=MUSIK_API_TOKEN=...`
class AppConfig {
  static const defaultBaseUrl = String.fromEnvironment(
    'MUSIK_BASE_URL',
    defaultValue: 'http://127.0.0.1:8787',
  );

  /// Android emulator → host loopback (local-dev fallback).
  static const androidEmulatorBaseUrl = 'http://10.0.2.2:8787';

  static const defaultApiToken = String.fromEnvironment('MUSIK_API_TOKEN');
  static const defaultPassword = String.fromEnvironment('MUSIK_PASSWORD');

  /// Opt-in for managed/private builds. Public builds preserve user settings.
  static const preferBakedServer = bool.fromEnvironment(
    'MUSIK_PREFER_BAKED_SERVER',
    defaultValue: false,
  );
}
