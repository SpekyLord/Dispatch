import 'dart:async';

import 'package:dispatch_mobile/core/config/app_config.dart';
import 'package:dispatch_mobile/core/state/session.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const _authSlides = [
  _LoginSlide('assets/auth_slides/bicol-front.jpg', 'Rescue responders digging through landslide debris.'),
  _LoginSlide('assets/auth_slides/typhoon-rai.jpg', 'Flood response team guiding evacuees through deep water.'),
  _LoginSlide('assets/auth_slides/fire-response.jpg', 'Firefighters coordinating suppression efforts from an elevated platform.'),
  _LoginSlide('assets/auth_slides/medical-response.jpg', 'Medical responders preparing equipment from an emergency vehicle.'),
];

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
  Timer? _slideTimer;
  bool _loading = false;
  bool _showServerConfig = false;
  bool _obscurePassword = true;
  int _activeSlide = 0;
  String? _error;

  @override
  void initState() {
    super.initState();
    final currentUrl = ref.read(sessionControllerProvider.notifier).currentApiBaseUrl;
    _apiUrlController = TextEditingController(text: currentUrl);
    if (_currentApiHelp(currentUrl) != null) _showServerConfig = true;
    if (_authSlides.length > 1) {
      _slideTimer = Timer.periodic(const Duration(seconds: 12), (_) {
        if (!mounted) return;
        setState(() => _activeSlide = (_activeSlide + 1) % _authSlides.length);
      });
    }
  }

  @override
  void dispose() {
    _slideTimer?.cancel();
    _emailController.dispose();
    _passwordController.dispose();
    _apiUrlController.dispose();
    super.dispose();
  }

  String? _currentApiHelp(String url) {
    return buildMobileApiUrlHelp(
      isWeb: kIsWeb,
      isAndroid: defaultTargetPlatform == TargetPlatform.android,
      url: url,
    );
  }

  Future<void> _applyApiUrl() async {
    final url = _apiUrlController.text.trim();
    if (url.isEmpty) return;
    await ref.read(sessionControllerProvider.notifier).setCustomApiBaseUrl(url);
    if (!mounted) return;
    setState(() => _error = null);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Server URL set to $url')));
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
      err = await controller.login(email: email, password: password);
    } catch (e) {
      err = e.toString();
    }

    if (!mounted) return;
    setState(() {
      _loading = false;
      _error = err;
      if (err != null && _currentApiHelp(controller.currentApiBaseUrl) != null) {
        _showServerConfig = true;
      }
    });
  }

  void _showForgotPasswordMessage() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Password recovery is not yet available in the mobile app.')),
    );
  }

  Widget _fieldLabel(String label) {
    return Builder(
      builder: (context) => Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: const Color(0xFF433B36),
          fontWeight: FontWeight.w800,
          letterSpacing: 2,
        ),
      ),
    );
  }

  Widget _inputShell({required Widget child, IconData? icon, Widget? trailing}) {
    return Container(
      padding: EdgeInsets.fromLTRB(icon != null ? 14 : 18, 6, 8, 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [BoxShadow(color: Color(0x12000000), blurRadius: 14, offset: Offset(0, 5))],
      ),
      child: Row(
        children: [
          if (icon != null) ...[Icon(icon, size: 18, color: const Color(0xFFB26848)), const SizedBox(width: 10)],
          Expanded(child: child),
          if (trailing != null) trailing,
        ],
      ),
    );
  }

  Widget _infoPanel({required Color backgroundColor, required Color borderColor, required String title, required String body, required Color titleColor, required Color bodyColor}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.labelSmall?.copyWith(color: titleColor, fontWeight: FontWeight.w800, letterSpacing: 1.6)),
          const SizedBox(height: 8),
          Text(body, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: bodyColor, fontSize: 12.5, height: 1.5)),
        ],
      ),
    );
  }
  Widget _hero() {
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(34)),
      child: AspectRatio(
        aspectRatio: 0.92,
        child: Stack(
          fit: StackFit.expand,
          children: [
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 900),
              child: Semantics(
                image: true,
                label: _authSlides[_activeSlide].semanticLabel,
                child: Image.asset(
                  _authSlides[_activeSlide].assetPath,
                  key: ValueKey(_authSlides[_activeSlide].assetPath),
                  fit: BoxFit.cover,
                ),
              ),
            ),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0x66412518), Color(0x483F281D), Color(0x0F000000)],
                  begin: Alignment.topCenter,
                  end: Alignment.center,
                ),
              ),
            ),
            Positioned(
              top: -20,
              right: -30,
              child: Container(
                width: 160,
                height: 160,
                decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withValues(alpha: 0.10)),
              ),
            ),
            Positioned(
              left: -44,
              bottom: 86,
              child: Container(
                width: 130,
                height: 130,
                decoration: BoxDecoration(shape: BoxShape.circle, color: const Color(0xFFF0D5BA).withValues(alpha: 0.16)),
              ),
            ),
            Align(
              alignment: Alignment.topCenter,
              child: Padding(
                padding: const EdgeInsets.only(top: 36),
                child: Text(
                  'DISPATCH',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: const Color(0xFF9F4E31),
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 5,
                  ),
                ),
              ),
            ),
            const Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0x00F7F2EA), Color(0xCCF7F2EA), Color(0xFFF7F2EA)],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    stops: [0.34, 0.78, 1],
                  ),
                ),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 22,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(_authSlides.length, (index) {
                  final isActive = index == _activeSlide;
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 240),
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    width: isActive ? 28 : 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: isActive ? const Color(0xFFA14B2F) : const Color(0xFFD9CBC0),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  );
                }),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final currentUrl = ref.read(sessionControllerProvider.notifier).currentApiBaseUrl;
    final apiHelp = _currentApiHelp(currentUrl);

    return Scaffold(
      backgroundColor: const Color(0xFFF2EEE7),
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFFF8F5EF), Color(0xFFF2E6D8), Color(0xFFE9D8C8)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 28),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 430),
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(34),
                    border: Border.all(color: const Color(0xFFF7F0E7), width: 1.4),
                    gradient: const LinearGradient(
                      colors: [Color(0xFFF8F4ED), Color(0xFFF5EFE6)],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
                    boxShadow: const [
                      BoxShadow(color: Color(0x2B5F3524), blurRadius: 34, offset: Offset(0, 18)),
                      BoxShadow(color: Color(0x1EFFFFFF), blurRadius: 12, offset: Offset(0, -4)),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _hero(),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(22, 0, 22, 22),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('SECURE ACCESS', style: textTheme.labelSmall?.copyWith(color: const Color(0xFF544A44), fontWeight: FontWeight.w700, letterSpacing: 2.7)),
                            const SizedBox(height: 10),
                            Text(
                              'Welcome back',
                              style: textTheme.headlineMedium?.copyWith(
                                fontFamily: 'Georgia',
                                fontFamilyFallback: const ['Times New Roman', 'serif'],
                                color: const Color(0xFF1E1B1A),
                                fontSize: 33,
                                fontWeight: FontWeight.w400,
                                height: 0.96,
                                letterSpacing: -1.1,
                              ),
                            ),
                            const SizedBox(height: 14),
                            Text(
                              'Enter your credentials to access the crisis management dashboard.',
                              style: textTheme.bodyLarge?.copyWith(color: const Color(0xFF5E5550), fontSize: 15, height: 1.65),
                            ),
                            const SizedBox(height: 18),
                            if (_error != null) ...[
                              _infoPanel(
                                backgroundColor: const Color(0xFFF9E4DE),
                                borderColor: const Color(0xFFE8B4A6),
                                title: 'Unable to sign in',
                                body: _error!,
                                titleColor: const Color(0xFF9E422C),
                                bodyColor: const Color(0xFF7A3622),
                              ),
                              const SizedBox(height: 14),
                            ],
                            if (apiHelp != null) ...[
                              _infoPanel(
                                backgroundColor: const Color(0xFFF7EDE3),
                                borderColor: const Color(0xFFEAD5C2),
                                title: 'Android API target',
                                body: '$apiHelp\n\nCurrent target: $currentUrl',
                                titleColor: const Color(0xFFA14B2F),
                                bodyColor: const Color(0xFF6A5A52),
                              ),
                              const SizedBox(height: 14),
                            ],
                            InkWell(
                              onTap: () => setState(() => _showServerConfig = !_showServerConfig),
                              borderRadius: BorderRadius.circular(999),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(vertical: 6),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(_showServerConfig ? Icons.expand_less_rounded : Icons.dns_outlined, size: 18, color: const Color(0xFF7C706A)),
                                    const SizedBox(width: 8),
                                    Text(
                                      _showServerConfig ? 'Hide server settings' : 'Server settings',
                                      style: textTheme.bodySmall?.copyWith(color: const Color(0xFF7C706A), fontWeight: FontWeight.w600),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            AnimatedCrossFade(
                              crossFadeState: _showServerConfig ? CrossFadeState.showFirst : CrossFadeState.showSecond,
                              duration: const Duration(milliseconds: 240),
                              firstChild: Padding(
                                padding: const EdgeInsets.only(top: 12),
                                child: Column(
                                  children: [
                                    _inputShell(
                                      icon: Icons.dns_outlined,
                                      child: TextField(
                                        controller: _apiUrlController,
                                        keyboardType: TextInputType.url,
                                        textInputAction: TextInputAction.done,
                                        onSubmitted: (_) => _applyApiUrl(),
                                        decoration: InputDecoration(
                                          isDense: true,
                                          filled: false,
                                          fillColor: Colors.transparent,
                                          hintText: 'http://192.168.x.x:5000',
                                          border: InputBorder.none,
                                          hintStyle: TextStyle(color: const Color(0xFFC5B8AF).withValues(alpha: 0.95)),
                                        ),
                                        style: const TextStyle(color: Color(0xFF2F221D), fontSize: 15, height: 1.4),
                                      ),
                                      trailing: IconButton(
                                        onPressed: _applyApiUrl,
                                        icon: const Icon(Icons.check_rounded, color: Color(0xFFA14B2F)),
                                        tooltip: 'Apply',
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      'For a physical phone or installed APK, use your computer\'s LAN IP or a public API URL.',
                                      style: textTheme.bodySmall?.copyWith(color: const Color(0xFF7A6E68), height: 1.45),
                                    ),
                                  ],
                                ),
                              ),
                              secondChild: const SizedBox.shrink(),
                            ),
                            const SizedBox(height: 22),
                            _fieldLabel('EMAIL ADDRESS'),
                            const SizedBox(height: 10),
                            _inputShell(
                              child: TextField(
                                controller: _emailController,
                                keyboardType: TextInputType.emailAddress,
                                textInputAction: TextInputAction.next,
                                decoration: InputDecoration(
                                  isDense: true,
                                  filled: false,
                                  fillColor: Colors.transparent,
                                  hintText: 'name@organization.com',
                                  border: InputBorder.none,
                                  hintStyle: TextStyle(color: const Color(0xFFC6B8AD).withValues(alpha: 0.98)),
                                ),
                                style: const TextStyle(color: Color(0xFF2F221D), fontSize: 15, height: 1.4),
                              ),
                            ),
                            const SizedBox(height: 18),
                            Row(
                              children: [
                                Expanded(child: _fieldLabel('PASSWORD')),
                                TextButton(
                                  onPressed: _showForgotPasswordMessage,
                                  style: TextButton.styleFrom(foregroundColor: const Color(0xFFA14B2F), padding: EdgeInsets.zero, minimumSize: Size.zero, tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                                  child: const Text('FORGOT PASSWORD?', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 0.4)),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            _inputShell(
                              child: TextField(
                                controller: _passwordController,
                                obscureText: _obscurePassword,
                                textInputAction: TextInputAction.done,
                                onSubmitted: (_) => _handleLogin(),
                                decoration: InputDecoration(
                                  isDense: true,
                                  filled: false,
                                  fillColor: Colors.transparent,
                                  hintText: '••••••••',
                                  border: InputBorder.none,
                                  hintStyle: TextStyle(color: const Color(0xFFD1C5BB).withValues(alpha: 0.98), fontSize: 18, letterSpacing: 3),
                                ),
                                style: const TextStyle(color: Color(0xFF2F221D), fontSize: 15, height: 1.4),
                              ),
                              trailing: IconButton(
                                onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                                icon: Icon(_obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined, color: const Color(0xFFB26848)),
                                tooltip: _obscurePassword ? 'Show password' : 'Hide password',
                              ),
                            ),
                            const SizedBox(height: 28),
                            SizedBox(
                              width: double.infinity,
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(12),
                                  gradient: const LinearGradient(colors: [Color(0xFFA14B2F), Color(0xFFB05D33)], begin: Alignment.centerLeft, end: Alignment.centerRight),
                                  boxShadow: const [BoxShadow(color: Color(0x302E1A12), blurRadius: 18, offset: Offset(0, 12))],
                                ),
                                child: FilledButton(
                                  onPressed: _loading ? null : _handleLogin,
                                  style: FilledButton.styleFrom(
                                    backgroundColor: Colors.transparent,
                                    shadowColor: Colors.transparent,
                                    disabledBackgroundColor: Colors.transparent,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(vertical: 18),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                  ),
                                  child: Text(
                                    _loading ? 'Signing in...' : 'Sign in to Dispatch',
                                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, letterSpacing: 0.2),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 24),
                            Row(
                              children: [
                                Expanded(child: Container(height: 1, color: const Color(0xFFE4DAD0))),
                                Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 12),
                                  child: Text('OR', style: textTheme.labelSmall?.copyWith(color: const Color(0xFFAD9F97), letterSpacing: 1.8)),
                                ),
                                Expanded(child: Container(height: 1, color: const Color(0xFFE4DAD0))),
                              ],
                            ),
                            const SizedBox(height: 24),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(18),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF7EFE7),
                                borderRadius: BorderRadius.circular(22),
                                border: Border.all(color: const Color(0xFFE8DCD1)),
                                boxShadow: const [BoxShadow(color: Color(0x12000000), blurRadius: 16, offset: Offset(0, 6))],
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Container(
                                        width: 42,
                                        height: 42,
                                        decoration: BoxDecoration(
                                          color: Colors.white,
                                          borderRadius: BorderRadius.circular(14),
                                          border: Border.all(color: const Color(0xFFE9DCD0)),
                                        ),
                                        child: const Icon(Icons.person_add_alt_1_rounded, color: Color(0xFFA14B2F)),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text('Need an account?', style: textTheme.labelSmall?.copyWith(color: const Color(0xFFA14B2F), fontWeight: FontWeight.w800, letterSpacing: 2.1)),
                                            const SizedBox(height: 6),
                                            Text(
                                              'Register as a citizen or department and step into the same response-ready workspace.',
                                              style: textTheme.bodyMedium?.copyWith(color: const Color(0xFF645A54), height: 1.55),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 16),
                                  SizedBox(
                                    width: double.infinity,
                                    child: OutlinedButton(
                                      onPressed: widget.onSwitchToRegister,
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: const Color(0xFF6E625B),
                                        side: const BorderSide(color: Color(0xFFD6CABD)),
                                        padding: const EdgeInsets.symmetric(vertical: 14),
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
                                      ),
                                      child: const Text('Create account', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 1.6)),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LoginSlide {
  const _LoginSlide(this.assetPath, this.semanticLabel);

  final String assetPath;
  final String semanticLabel;
}

