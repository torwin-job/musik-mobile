import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/config.dart';
import '../core/errors.dart';
import '../data/api/musik_api.dart';
import '../data/repositories/auth_repository.dart';
import '../data/repositories/settings_repository.dart';

final sharedPrefsProvider = FutureProvider<SharedPreferences>((ref) {
  return SharedPreferences.getInstance();
});

final settingsRepositoryProvider = FutureProvider<SettingsRepository>((
  ref,
) async {
  final prefs = await ref.watch(sharedPrefsProvider.future);
  return SettingsRepository(prefs);
});

final musikApiProvider = Provider<MusikApi?>((ref) {
  final settingsAsync = ref.watch(settingsRepositoryProvider);
  return settingsAsync.when(
    data: (settings) {
      late MusikApi api;
      api = MusikApi(
        baseUrl: settings.baseUrl,
        tokenProvider: settings.getToken,
        onUnauthorized: () {
          // Real 401 only (interceptor). Clear session → login once.
          settings.setToken(null);
          ref.read(authControllerProvider.notifier).markSignedOut();
        },
      );
      return api;
    },
    loading: () => null,
    error: (_, _) => null,
  );
});

final authRepositoryProvider = Provider<AuthRepository?>((ref) {
  final api = ref.watch(musikApiProvider);
  final settingsAsync = ref.watch(settingsRepositoryProvider);
  if (api == null) return null;
  return settingsAsync.when(
    data: (settings) => AuthRepository(api, settings),
    loading: () => null,
    error: (_, _) => null,
  );
});

/// Stable Bearer token for artwork / stream headers (avoids per-widget futures).
final bearerTokenProvider = FutureProvider<String?>((ref) async {
  final settings = await ref.watch(settingsRepositoryProvider.future);
  return settings.getToken();
});

class AuthState {
  const AuthState({
    required this.ready,
    required this.signedIn,
    this.baseUrl,
    this.error,
  });

  final bool ready;
  final bool signedIn;
  final String? baseUrl;
  final String? error;

  AuthState copyWith({
    bool? ready,
    bool? signedIn,
    String? baseUrl,
    String? error,
    bool clearError = false,
  }) {
    return AuthState(
      ready: ready ?? this.ready,
      signedIn: signedIn ?? this.signedIn,
      baseUrl: baseUrl ?? this.baseUrl,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

class AuthController extends Notifier<AuthState> {
  @override
  AuthState build() {
    Future.microtask(_bootstrap);
    return const AuthState(ready: false, signedIn: false);
  }

  Future<void> _bootstrap() async {
    try {
      final settings = await ref.read(settingsRepositoryProvider.future);
      await settings.ensureDefaults();

      ref.invalidate(settingsRepositoryProvider);
      final fresh = await ref.read(settingsRepositoryProvider.future);

      final token = await fresh.getToken();
      final baseUrl = AppConfig.preferBakedServer
          ? AppConfig.defaultBaseUrl
          : fresh.baseUrl;

      if (token == null || token.isEmpty) {
        state = AuthState(ready: true, signedIn: false, baseUrl: baseUrl);
        return;
      }

      // Enter immediately — no login flash. Verify token in background.
      await fresh.setBaseUrl(baseUrl);
      await fresh.setToken(token);
      ref.invalidate(settingsRepositoryProvider);
      await ref.read(settingsRepositoryProvider.future);

      state = AuthState(ready: true, signedIn: true, baseUrl: baseUrl);
      // ignore: unawaited_futures
      _verifySessionInBackground(baseUrl: baseUrl, token: token);
    } catch (e) {
      // Still allow entry if we have a baked token — network may be down.
      final hasBaked = AppConfig.defaultApiToken.isNotEmpty;
      state = AuthState(
        ready: true,
        signedIn: hasBaked,
        baseUrl: AppConfig.defaultBaseUrl,
        error: hasBaked ? null : e.toString(),
      );
    }
  }

  Future<void> _verifySessionInBackground({
    required String baseUrl,
    required String token,
  }) async {
    try {
      final auth = ref.read(authRepositoryProvider);
      if (auth == null) return;
      await auth.login(
        baseUrl: baseUrl,
        apiToken: token,
        // Flutter uses Bearer only — no UI password on silent resume.
        password: null,
      );
    } on ApiException catch (e) {
      if (e.statusCode == 401 || e.code == 'bad_token') {
        final settings = await ref.read(settingsRepositoryProvider.future);
        await settings.setToken(null);
        markSignedOut();
      }
      // Network / timeouts: keep signed in.
    } catch (_) {
      // Keep signed in offline.
    }
  }

  void markSignedOut() {
    state = AuthState(ready: true, signedIn: false, baseUrl: state.baseUrl);
  }

  Future<void> login({
    required String baseUrl,
    String? password,
    String? apiToken,
  }) async {
    state = state.copyWith(clearError: true);
    final token = (apiToken?.trim().isNotEmpty ?? false)
        ? apiToken!.trim()
        : (await ref
                  .read(settingsRepositoryProvider.future)
                  .then((s) => s.getToken()) ??
              AppConfig.defaultApiToken);
    if (token.isEmpty) {
      throw Exception(
        'Укажи MUSIK_API_TOKEN (Bearer). Без него стриминг не заработает.',
      );
    }

    final settings = await ref.read(settingsRepositoryProvider.future);
    await settings.setBaseUrl(baseUrl);
    await settings.setToken(token);
    if (password != null && password.trim().isNotEmpty) {
      await settings.setPassword(password.trim());
    }
    ref.invalidate(settingsRepositoryProvider);
    await ref.read(settingsRepositoryProvider.future);

    final auth = ref.read(authRepositoryProvider);
    if (auth == null) {
      throw Exception('Клиент API ещё не готов, попробуй ещё раз');
    }

    try {
      await auth.login(baseUrl: baseUrl, password: password, apiToken: token);
      state = AuthState(ready: true, signedIn: true, baseUrl: baseUrl);
    } on ApiException catch (e) {
      if (e.statusCode == 401 ||
          e.code == 'bad_token' ||
          e.code == 'bad_password') {
        await settings.setToken(null);
      }
      state = AuthState(
        ready: true,
        signedIn: false,
        baseUrl: baseUrl,
        error: e.toString(),
      );
      rethrow;
    } catch (e) {
      // Do not wipe token on unknown / network errors.
      state = AuthState(
        ready: true,
        signedIn: false,
        baseUrl: baseUrl,
        error: e.toString(),
      );
      rethrow;
    }
  }

  Future<void> logout() async {
    final auth = ref.read(authRepositoryProvider);
    if (auth != null) {
      await auth.logout();
    }
    state = AuthState(ready: true, signedIn: false, baseUrl: state.baseUrl);
  }
}

final authControllerProvider = NotifierProvider<AuthController, AuthState>(
  AuthController.new,
);
