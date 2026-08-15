import 'package:shared_preferences/shared_preferences.dart';

import '../../core/config.dart';

class SettingsRepository {
  SettingsRepository(this._prefs);

  final SharedPreferences _prefs;

  static const _kBaseUrl = 'base_url';
  static const _kToken = 'api_token';
  static const _kSessionId = 'session_id';
  static const _kPassword = 'ui_password';

  String get baseUrl {
    if (AppConfig.preferBakedServer) return AppConfig.defaultBaseUrl;
    final saved = _prefs.getString(_kBaseUrl)?.trim();
    if (saved != null && saved.isNotEmpty) return saved;
    return AppConfig.defaultBaseUrl;
  }

  Future<void> setBaseUrl(String url) async {
    await _prefs.setString(_kBaseUrl, url.trim());
  }

  Future<String?> getToken() async {
    final t = _prefs.getString(_kToken);
    if (t != null && t.trim().isNotEmpty) return t.trim();
    if (AppConfig.defaultApiToken.isNotEmpty) return AppConfig.defaultApiToken;
    return null;
  }

  Future<void> setToken(String? token) async {
    if (token == null || token.isEmpty) {
      await _prefs.remove(_kToken);
    } else {
      await _prefs.setString(_kToken, token.trim());
    }
  }

  Future<String?> getPassword() async {
    final p = _prefs.getString(_kPassword);
    if (p != null && p.isNotEmpty) return p;
    if (AppConfig.defaultPassword.isNotEmpty) return AppConfig.defaultPassword;
    return null;
  }

  Future<void> setPassword(String? password) async {
    if (password == null || password.isEmpty) {
      await _prefs.remove(_kPassword);
    } else {
      await _prefs.setString(_kPassword, password);
    }
  }

  String? get sessionId => _prefs.getString(_kSessionId);

  Future<void> setSessionId(String? id) async {
    if (id == null || id.isEmpty) {
      await _prefs.remove(_kSessionId);
    } else {
      await _prefs.setString(_kSessionId, id);
    }
  }

  /// Seed optional private-build defaults without overwriting user settings.
  Future<void> ensureDefaults() async {
    final savedBase = _prefs.getString(_kBaseUrl)?.trim();
    if (AppConfig.preferBakedServer || savedBase == null || savedBase.isEmpty) {
      await setBaseUrl(AppConfig.defaultBaseUrl);
    }

    final savedToken = _prefs.getString(_kToken)?.trim();
    if (AppConfig.defaultApiToken.isNotEmpty &&
        (AppConfig.preferBakedServer ||
            savedToken == null ||
            savedToken.isEmpty)) {
      await setToken(AppConfig.defaultApiToken);
    }

    final savedPassword = _prefs.getString(_kPassword);
    if (AppConfig.defaultPassword.isNotEmpty &&
        (AppConfig.preferBakedServer ||
            savedPassword == null ||
            savedPassword.isEmpty)) {
      await setPassword(AppConfig.defaultPassword);
    }
  }
}
