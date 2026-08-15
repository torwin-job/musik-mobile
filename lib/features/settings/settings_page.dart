import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../providers/providers.dart';

class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  late final TextEditingController _baseUrl;
  late final TextEditingController _token;
  var _loaded = false;

  @override
  void initState() {
    super.initState();
    _baseUrl = TextEditingController();
    _token = TextEditingController();
    Future.microtask(() async {
      final s = await ref.read(settingsRepositoryProvider.future);
      _baseUrl.text = s.baseUrl;
      _token.text = (await s.getToken()) ?? '';
      if (mounted) setState(() => _loaded = true);
    });
  }

  @override
  void dispose() {
    _baseUrl.dispose();
    _token.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final s = await ref.read(settingsRepositoryProvider.future);
    await s.setBaseUrl(_baseUrl.text.trim());
    await s.setToken(_token.text.trim());
    ref.invalidate(settingsRepositoryProvider);
    await ref.read(settingsRepositoryProvider.future);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Сохранено. Перелогинься при смене token.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Настройки')),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                TextField(
                  controller: _baseUrl,
                  decoration: const InputDecoration(labelText: 'Base URL'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _token,
                  decoration: const InputDecoration(labelText: 'API token'),
                  obscureText: true,
                ),
                const SizedBox(height: 20),
                FilledButton(onPressed: _save, child: const Text('Сохранить')),
                const SizedBox(height: 24),
                const Text(
                  'Phase 0 skeleton · см. docs/MOBILE.md',
                  style: TextStyle(color: MusikColors.muted),
                ),
              ],
            ),
    );
  }
}
