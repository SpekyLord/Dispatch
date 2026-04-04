// Login screen - email/password form, delegates auth to SessionController.

import 'package:dispatch_mobile/core/state/session.dart';
import 'package:dispatch_mobile/core/theme/dispatch_colors.dart' as dc;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key, this.onSwitchToRegister});

  final VoidCallback? onSwitchToRegister;

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  late final TextEditingController _apiUrlController;
  bool _loading = false;
  bool _showServerConfig = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final currentUrl =
        ref.read(sessionControllerProvider.notifier).currentApiBaseUrl;
    _apiUrlController = TextEditingController(text: currentUrl);
    // Auto-expand server settings on physical Android devices (10.0.2.2 won't
    // work there — the user must enter their computer's LAN IP).
    if (!kIsWeb &&
        defaultTargetPlatform == TargetPlatform.android &&
        Uri.tryParse(currentUrl)?.host == '10.0.2.2') {
      _showServerConfig = true;
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _apiUrlController.dispose();
    super.dispose();
  }

  Future<void> _applyApiUrl() async {
    final url = _apiUrlController.text.trim();
    if (url.isEmpty) return;
    await ref.read(sessionControllerProvider.notifier).setCustomApiBaseUrl(url);
    if (mounted) {
      setState(() => _error = null);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Server URL set to $url')),
      );
    }
  }

  Future<void> _handleLogin() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text;

    if (email.isEmpty || password.isEmpty) {
      setState(() => _error = 'Please enter both email and password.');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    final controller = ref.read(sessionControllerProvider.notifier);
    String? err;
    try {
      err = await controller.login(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );
    } catch (e) {
      err = e.toString();
    }

    if (mounted) {
      final currentUrl = controller.currentApiBaseUrl;
      final isEmulatorAlias =
          Uri.tryParse(currentUrl)?.host == '10.0.2.2';
      if (err != null && isEmulatorAlias) {
        err =
            'Cannot reach 10.0.2.2 — this address only works on '
            'Android emulators.\n\n'
            'On a physical device, open Server Settings below and '
            'enter your computer\'s local network IP '
            '(e.g. http://192.168.x.x:5000).\n\n'
            'Also make sure API_HOST=0.0.0.0 in your backend .env file.';
      }
      setState(() {
        _loading = false;
        _error = err;
        if (err != null && isEmulatorAlias) {
          _showServerConfig = true;
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Login'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 18, 24, 28),
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [
                    ...dc.heroGradient,
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(24),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'DISPATCH',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 2,
                    ),
                  ),
                  SizedBox(height: 14),
                  Text(
                    'Sign in to your account.',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 28,
                      fontWeight: FontWeight.w700,
                      height: 1.05,
                    ),
                  ),
                  SizedBox(height: 10),
                  Text(
                    'Access your reports, mesh status, and community feed from any device.',
                    style: TextStyle(color: dc.chipFill, height: 1.45),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Login',
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    const SizedBox(height: 18),
                    if (_error != null)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        margin: const EdgeInsets.only(bottom: 16),
                        decoration: BoxDecoration(
                          color: dc.warmSeed.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Text(
                          _error!,
                          style: const TextStyle(color: dc.warmSeed),
                        ),
                      ),
                    InkWell(
                      onTap: () =>
                          setState(() => _showServerConfig = !_showServerConfig),
                      borderRadius: BorderRadius.circular(12),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Row(
                          children: [
                            Icon(
                              _showServerConfig
                                  ? Icons.expand_less
                                  : Icons.dns_outlined,
                              size: 18,
                              color: dc.mutedInk,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              _showServerConfig
                                  ? 'Hide server settings'
                                  : 'Server settings',
                              style: const TextStyle(
                                color: dc.mutedInk,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (_showServerConfig) ...[
                      const SizedBox(height: 8),
                      TextField(
                        controller: _apiUrlController,
                        decoration: InputDecoration(
                          labelText: 'API server URL',
                          hintText: 'http://192.168.x.x:5000',
                          border: const OutlineInputBorder(),
                          suffixIcon: IconButton(
                            onPressed: _applyApiUrl,
                            icon: const Icon(Icons.check),
                            tooltip: 'Apply',
                          ),
                        ),
                        keyboardType: TextInputType.url,
                        onSubmitted: (_) => _applyApiUrl(),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'For physical devices, use your computer\'s local network IP (e.g. 192.168.x.x:5000).',
                        style: TextStyle(
                          color: dc.mutedInk,
                          fontSize: 11,
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    TextField(
                      controller: _emailController,
                      decoration: const InputDecoration(
                        labelText: 'Email',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: _passwordController,
                      decoration: const InputDecoration(
                        labelText: 'Password',
                        border: OutlineInputBorder(),
                      ),
                      obscureText: true,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _handleLogin(),
                    ),
                    const SizedBox(height: 20),
                    FilledButton(
                      onPressed: _loading ? null : _handleLogin,
                      child: Text(_loading ? 'Signing in...' : 'Login'),
                    ),
                    const SizedBox(height: 10),
                    TextButton(
                      onPressed: widget.onSwitchToRegister,
                      child: const Text('Don\'t have an account? Register'),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
