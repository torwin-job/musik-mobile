import '../../core/errors.dart';
import '../api/musik_api.dart';
import 'settings_repository.dart';

class AuthRepository {
  AuthRepository(this._api, this._settings);

  final MusikApi _api;
  final SettingsRepository _settings;

  Future<bool> get hasToken async {
    final t = await _settings.getToken();
    return t != null && t.isNotEmpty;
  }

  /// Store Bearer token, optional cookie login, verify `/api/auth/me`.
  Future<void> login({
    required String baseUrl,
    String? password,
    String? apiToken,
  }) async {
    await _settings.setBaseUrl(baseUrl);
    _api.updateBaseUrl(baseUrl);

    final token = apiToken?.trim();
    if (token != null && token.isNotEmpty) {
      await _settings.setToken(token);
    }

    final pass = password?.trim();
    if (pass != null && pass.isNotEmpty) {
      try {
        await _api.login(pass);
      } on ApiException catch (e) {
        if (e.code == 'bad_password' || e.statusCode == 401) {
          throw ApiException(
            'Неверный пароль UI (поле «Пароль»). '
            'Для приложения достаточно API token — оставь пароль пустым, '
            'или введи ровно MUSIK_PASSWORD из .env.',
            code: e.code,
            statusCode: e.statusCode,
          );
        }
        rethrow;
      }
    }

    await _api.health();

    final me = await _api.authMe();
    if (me['auth_enabled'] == true && me['ok'] != true) {
      throw ApiException(
        'Токен не принят. Проверь MUSIK_API_TOKEN в .env player’а.',
        code: 'bad_token',
        statusCode: 401,
      );
    }
  }

  Future<void> logout() async {
    try {
      await _api.logout();
    } catch (_) {}
    await _settings.setToken(null);
    await _settings.setSessionId(null);
  }

  Future<Map<String, dynamic>> health() => _api.health();

  Future<Map<String, dynamic>> authMe() => _api.authMe();

  Future<Map<String, dynamic>> profile() => _api.profile();
}
