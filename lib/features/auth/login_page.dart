import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config.dart';
import '../../core/theme.dart';
import '../../providers/providers.dart';

class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  late final TextEditingController _baseUrl;
  late final TextEditingController _token;
  late final TextEditingController _password;
  var _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _baseUrl = TextEditingController(text: AppConfig.defaultBaseUrl);
    _token = TextEditingController(text: AppConfig.defaultApiToken);
    _password = TextEditingController(text: AppConfig.defaultPassword);
  }

  @override
  void dispose() {
    _baseUrl.dispose();
    _token.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(authControllerProvider.notifier)
          .login(
            baseUrl: _baseUrl.text.trim(),
            apiToken: _token.text.trim(),
            password: _password.text.trim().isEmpty ? null : _password.text,
          );
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final authErr = ref.watch(authControllerProvider).error;

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF5A2E18), MusikColors.bg, Color(0xFF16352E)],
            stops: [0.0, 0.45, 1.0],
          ),
        ),
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(24, 48, 24, 24),
            children: [
              Text(
                'musik',
                style: Theme.of(context).textTheme.displayMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  letterSpacing: -1.2,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'изучаем вкус · слушай и скипай',
                style: TextStyle(color: MusikColors.muted),
              ),
              const SizedBox(height: 36),
              TextField(
                controller: _baseUrl,
                decoration: const InputDecoration(
                  labelText: 'Base URL сервера',
                  hintText: 'http://192.168.x.x:8787',
                ),
                keyboardType: TextInputType.url,
                autocorrect: false,
                onSubmitted: (_) => _submit(),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _token,
                decoration: const InputDecoration(labelText: 'API token'),
                obscureText: true,
                autocorrect: false,
                onSubmitted: (_) => _submit(),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _password,
                decoration: const InputDecoration(labelText: 'Пароль UI'),
                obscureText: true,
                onSubmitted: (_) => _submit(),
              ),
              if (_error != null || authErr != null) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0x33FF6B4A),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0x88FF6B4A)),
                  ),
                  child: Text(
                    _error ?? authErr!,
                    style: const TextStyle(
                      color: Color(0xFFFFC9B8),
                      height: 1.35,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _busy ? null : _submit,
                child: _busy
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Войти'),
              ),
              const SizedBox(height: 16),
              Text(
                'По умолчанию: ${AppConfig.defaultBaseUrl}\n'
                'Автологин при старте, если player доступен.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: MusikColors.muted,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
