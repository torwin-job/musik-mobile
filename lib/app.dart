import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/theme.dart';
import 'domain/playback/playback_controller.dart';
import 'providers/providers.dart';
import 'routing/app_router.dart';

class MusikApp extends ConsumerStatefulWidget {
  const MusikApp({super.key});

  @override
  ConsumerState<MusikApp> createState() => _MusikAppState();
}

class _MusikAppState extends ConsumerState<MusikApp> {
  var _sessionRestoreAttempted = false;

  @override
  Widget build(BuildContext context) {
    ref.listen(authControllerProvider, (prev, next) {
      if (!next.signedIn || _sessionRestoreAttempted) return;
      _sessionRestoreAttempted = true;
      Future.microtask(() async {
        try {
          final settings = await ref.read(settingsRepositoryProvider.future);
          final sid = settings.sessionId;
          if (sid == null || sid.isEmpty) return;
          await ref.read(playbackControllerProvider.notifier).restore(sid);
        } catch (_) {}
      });
    });

    final router = ref.watch(appRouterProvider);
    return MaterialApp.router(
      title: 'musik',
      debugShowCheckedModeBanner: false,
      theme: buildMusikTheme(),
      routerConfig: router,
    );
  }
}
