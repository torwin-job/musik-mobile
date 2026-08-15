import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/auth/login_page.dart';
import '../features/auth/splash_page.dart';
import '../features/catalog/album_page.dart';
import '../features/catalog/artist_page.dart';
import '../features/home/home_page.dart';
import '../features/library/library_page.dart';
import '../features/player/player_page.dart';
import '../features/profile/profile_page.dart';
import '../features/settings/settings_page.dart';
import '../features/shell/main_shell.dart';
import '../providers/providers.dart';

Page<void> _fadePage(GoRouterState state, Widget child) {
  return CustomTransitionPage<void>(
    key: state.pageKey,
    child: child,
    transitionDuration: const Duration(milliseconds: 220),
    reverseTransitionDuration: const Duration(milliseconds: 160),
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          scale: Tween(begin: 0.985, end: 1.0).animate(curved),
          child: child,
        ),
      );
    },
  );
}

Page<void> _stillPage(GoRouterState state, Widget child) =>
    NoTransitionPage<void>(key: state.pageKey, child: child);

final appRouterProvider = Provider<GoRouter>((ref) {
  final refresh = _AuthListenable(ref);

  return GoRouter(
    initialLocation: '/splash',
    refreshListenable: refresh,
    redirect: (context, state) {
      final auth = ref.read(authControllerProvider);
      final loc = state.matchedLocation;
      final onSplash = loc == '/splash';
      final loggingIn = loc == '/login';

      if (!auth.ready) {
        return onSplash ? null : '/splash';
      }
      if (!auth.signedIn) {
        return loggingIn ? null : '/login';
      }
      // Signed in — never stay on splash/login.
      if (onSplash || loggingIn) return '/home';
      return null;
    },
    routes: [
      GoRoute(
        path: '/splash',
        pageBuilder: (context, state) => _stillPage(state, const SplashPage()),
      ),
      GoRoute(
        path: '/login',
        pageBuilder: (context, state) => _stillPage(state, const LoginPage()),
      ),
      GoRoute(
        path: '/settings',
        pageBuilder: (context, state) => _fadePage(state, const SettingsPage()),
      ),
      GoRoute(
        path: '/artist',
        pageBuilder: (context, state) {
          final name = state.uri.queryParameters['name'] ?? '';
          return _fadePage(state, ArtistPage(artist: name));
        },
      ),
      GoRoute(
        path: '/album',
        pageBuilder: (context, state) {
          final artist = state.uri.queryParameters['artist'] ?? '';
          final album = state.uri.queryParameters['album'] ?? '';
          return _fadePage(state, AlbumPage(artist: artist, album: album));
        },
      ),
      StatefulShellRoute(
        builder: (context, state, navigationShell) {
          return MainShell(navigationShell: navigationShell);
        },
        // Only mount the active tab — IndexedStack kept Home+Library+Player
        // (and all their covers) alive and janked scrolling on Pixel.
        navigatorContainerBuilder: (context, navigationShell, children) {
          return children[navigationShell.currentIndex];
        },
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/home',
                pageBuilder: (context, state) =>
                    _stillPage(state, const HomePage()),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/player',
                pageBuilder: (context, state) =>
                    _stillPage(state, const PlayerPage()),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/library',
                pageBuilder: (context, state) =>
                    _stillPage(state, const LibraryPage()),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/profile',
                pageBuilder: (context, state) =>
                    _stillPage(state, const ProfilePage()),
              ),
            ],
          ),
        ],
      ),
    ],
  );
});

class _AuthListenable extends ChangeNotifier {
  _AuthListenable(this._ref) {
    _ref.listen(authControllerProvider, (_, _) => notifyListeners());
  }

  final Ref _ref;
}
