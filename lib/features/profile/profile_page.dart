import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../domain/playback/playback_controller.dart';
import '../../providers/providers.dart';

class ProfilePage extends ConsumerStatefulWidget {
  const ProfilePage({super.key});

  @override
  ConsumerState<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends ConsumerState<ProfilePage> {
  Map<String, dynamic>? _health;
  Map<String, dynamic>? _profile;
  Map<String, dynamic>? _metrics;
  List<dynamic> _shares = const [];
  String? _error;
  var _loading = true;

  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final auth = ref.read(authRepositoryProvider);
      final api = ref.read(musikApiProvider);
      if (auth == null || api == null) throw Exception('API ещё не готов');
      final h = await auth.health();
      Map<String, dynamic>? p;
      Map<String, dynamic>? m;
      List<dynamic> shares = const [];
      try {
        p = await auth.profile();
      } catch (_) {}
      try {
        m = await api.metricsWeekly();
      } catch (_) {}
      try {
        final s = await api.shareList();
        shares = (s['shares'] as List?) ?? (s['items'] as List?) ?? const [];
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _health = h;
        _profile = p;
        _metrics = m;
        _shares = shares;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authControllerProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Профиль'),
        actions: [
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                if (_error != null)
                  Text(
                    _error!,
                    style: const TextStyle(color: Colors.redAccent),
                  ),
                Text('Сервер', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 6),
                Text(
                  auth.baseUrl ?? '—',
                  style: const TextStyle(color: MusikColors.muted),
                ),
                const SizedBox(height: 16),
                _kv(
                  'health',
                  '${_health?['ok']} · v${_health?['version'] ?? '?'}',
                ),
                _kv('tracks', '${_health?['tracks'] ?? '—'}'),
                _kv('dim', '${_health?['dim'] ?? '—'}'),
                if (_profile != null) ...[
                  const SizedBox(height: 20),
                  Text('Вкус', style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 8),
                  _kv('maturity', '${_profile?['maturity'] ?? '—'}'),
                  _kv('signals+', '${_profile?['n_positive'] ?? '—'}'),
                  _kv('signals−', '${_profile?['n_negative'] ?? '—'}'),
                  _kv('explore', '${_profile?['explore_ratio'] ?? '—'}'),
                ],
                if (_metrics != null) ...[
                  const SizedBox(height: 20),
                  Text('Неделя', style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 8),
                  ..._metrics!.entries
                      .take(8)
                      .map((e) => _kv(e.key, '${e.value}')),
                ],
                const SizedBox(height: 20),
                Text(
                  'Share radio',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                FilledButton.tonal(
                  onPressed: () async {
                    try {
                      final share = await ref
                          .read(playbackControllerProvider.notifier)
                          .createShare();
                      final url = share['url']?.toString() ?? '';
                      await Clipboard.setData(ClipboardData(text: url));
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Скопировано: $url')),
                      );
                      await _load();
                    } catch (e) {
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(
                        context,
                      ).showSnackBar(SnackBar(content: Text('$e')));
                    }
                  },
                  child: const Text('Создать ссылку'),
                ),
                ..._shares.map((s) {
                  if (s is! Map) return const SizedBox.shrink();
                  final url =
                      s['url']?.toString() ?? s['token']?.toString() ?? '';
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      url,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: IconButton(
                      icon: const Icon(Icons.copy),
                      onPressed: () async {
                        await Clipboard.setData(ClipboardData(text: url));
                      },
                    ),
                  );
                }),
                const SizedBox(height: 28),
                OutlinedButton(
                  onPressed: () => context.push('/settings'),
                  child: const Text('Настройки'),
                ),
                const SizedBox(height: 10),
                FilledButton(
                  onPressed: () async {
                    await ref.read(authControllerProvider.notifier).logout();
                    if (context.mounted) context.go('/login');
                  },
                  child: const Text('Выйти'),
                ),
              ],
            ),
    );
  }

  Widget _kv(String k, String v) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 100,
            child: Text(k, style: const TextStyle(color: MusikColors.muted)),
          ),
          Expanded(child: Text(v)),
        ],
      ),
    );
  }
}
