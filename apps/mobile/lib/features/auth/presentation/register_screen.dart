import 'dart:async';

import 'package:dispatch_mobile/core/config/app_config.dart';
import 'package:dispatch_mobile/core/state/session.dart';
import 'package:dispatch_mobile/features/auth/presentation/widgets/dispatch_brand_mark.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const _registerSlides = [
  _RegisterSlide('assets/auth_slides/bicol-front.jpg', 'Rescue responders digging through landslide debris.'),
  _RegisterSlide('assets/auth_slides/typhoon-rai.jpg', 'Flood response team guiding evacuees through deep water.'),
  _RegisterSlide('assets/auth_slides/fire-response.jpg', 'Firefighters coordinating suppression efforts from an elevated platform.'),
  _RegisterSlide('assets/auth_slides/medical-response.jpg', 'Medical responders preparing equipment from an emergency vehicle.'),
];

const _departmentTypes = {
  'fire': 'Fire (BFP)',
  'police': 'Police (PNP)',
  'medical': 'Medical',
  'disaster': 'MDRRMO',
  'rescue': 'Rescue',
  'other': 'Other',
};

class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({required this.onSwitchToLogin, super.key});

  final VoidCallback onSwitchToLogin;

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  late final TextEditingController _apiUrlController;
  final _fullNameController = TextEditingController();
  final _orgNameController = TextEditingController();
  final _contactController = TextEditingController();
  final _addressController = TextEditingController();
  final _areaController = TextEditingController();
  Timer? _slideTimer;

  String _role = 'citizen';
  String _deptType = 'fire';
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
    if (_registerSlides.length > 1) {
      _slideTimer = Timer.periodic(const Duration(seconds: 12), (_) {
        if (!mounted) return;
        setState(() => _activeSlide = (_activeSlide + 1) % _registerSlides.length);
      });
    }
  }

  @override
  void dispose() {
    _slideTimer?.cancel();
    _apiUrlController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _fullNameController.dispose();
    _orgNameController.dispose();
    _contactController.dispose();
    _addressController.dispose();
    _areaController.dispose();
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

  Future<void> _handleRegister() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    final controller = ref.read(sessionControllerProvider.notifier);
    final err = await controller.register(
      email: _emailController.text.trim(),
      password: _passwordController.text,
      role: _role,
      fullName: _fullNameController.text.trim(),
      organizationName: _role == 'department' ? _orgNameController.text.trim() : null,
      departmentType: _role == 'department' ? _deptType : null,
      contactNumber: _role == 'department' ? _contactController.text.trim() : null,
      address: _role == 'department' ? _addressController.text.trim() : null,
      areaOfResponsibility: _role == 'department' ? _areaController.text.trim() : null,
    );

    if (!mounted) return;
    if (err == 'CONFIRM_EMAIL') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Account created! Check your email to confirm, then sign in.'),
          duration: Duration(seconds: 5),
        ),
      );
      widget.onSwitchToLogin();
      return;
    }

    setState(() {
      _loading = false;
      _error = err;
      if (err != null && _currentApiHelp(controller.currentApiBaseUrl) != null) {
        _showServerConfig = true;
      }
    });
  }

  Widget _fieldLabel(String label) {
    return Text(
      label,
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
        color: const Color(0xFF433B36),
        fontWeight: FontWeight.w800,
        letterSpacing: 2,
      ),
    );
  }

  Widget _inputShell({required Widget child, IconData? icon, Widget? trailing, EdgeInsetsGeometry? padding}) {
    return Container(
      padding: padding ?? EdgeInsets.fromLTRB(icon != null ? 14 : 18, 6, 8, 6),
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
                label: _registerSlides[_activeSlide].semanticLabel,
                child: Image.asset(
                  _registerSlides[_activeSlide].assetPath,
                  key: ValueKey(_registerSlides[_activeSlide].assetPath),
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
              child: Container(width: 160, height: 160, decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withValues(alpha: 0.10))),
            ),
            Positioned(
              left: -44,
              bottom: 86,
              child: Container(width: 130, height: 130, decoration: BoxDecoration(shape: BoxShape.circle, color: const Color(0xFFF0D5BA).withValues(alpha: 0.16))),
            ),
            Align(
              alignment: Alignment.topCenter,
              child: Padding(
                padding: const EdgeInsets.only(top: 24),
                child: const DispatchBrandMark(size: 76),
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
                children: List.generate(_registerSlides.length, (index) {
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

  Widget _rolePill(String value, String label) {
    final isSelected = _role == value;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _role = value),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: isSelected ? const Color(0xFFA14B2F) : Colors.transparent,
            borderRadius: BorderRadius.circular(999),
            boxShadow: isSelected ? const [BoxShadow(color: Color(0x241E120D), blurRadius: 16, offset: Offset(0, 8))] : null,
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(color: isSelected ? Colors.white : const Color(0xFF6A5E58), fontWeight: FontWeight.w700, fontSize: 13, letterSpacing: 0.2),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final currentUrl = ref.read(sessionControllerProvider.notifier).currentApiBaseUrl;
    final apiHelp = _currentApiHelp(currentUrl);
    final roleSummary = _role == 'department'
        ? 'Provide your agency profile so Dispatch can route the account into verification review.'
        : 'Set up a resident account for reports, advisories, and live response visibility.';

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
                    gradient: const LinearGradient(colors: [Color(0xFFF8F4ED), Color(0xFFF5EFE6)], begin: Alignment.topCenter, end: Alignment.bottomCenter),
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
                            Text('SECURE ONBOARDING', style: textTheme.labelSmall?.copyWith(color: const Color(0xFF544A44), fontWeight: FontWeight.w700, letterSpacing: 2.7)),
                            const SizedBox(height: 10),
                            Text(
                              'Create your account',
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
                              'Choose your role and complete the matching profile details to enter Dispatch with the same warm mobile surface.',
                              style: textTheme.bodyLarge?.copyWith(color: const Color(0xFF5E5550), fontSize: 15, height: 1.65),
                            ),
                            const SizedBox(height: 18),
                            if (_error != null) ...[
                              _infoPanel(backgroundColor: const Color(0xFFF9E4DE), borderColor: const Color(0xFFE8B4A6), title: 'Unable to create account', body: _error!, titleColor: const Color(0xFF9E422C), bodyColor: const Color(0xFF7A3622)),
                              const SizedBox(height: 14),
                            ],
                            if (apiHelp != null) ...[
                              _infoPanel(backgroundColor: const Color(0xFFF7EDE3), borderColor: const Color(0xFFEAD5C2), title: 'Android API target', body: '$apiHelp\n\nCurrent target: $currentUrl', titleColor: const Color(0xFFA14B2F), bodyColor: const Color(0xFF6A5A52)),
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
                                    Text(_showServerConfig ? 'Hide server settings' : 'Server settings', style: textTheme.bodySmall?.copyWith(color: const Color(0xFF7C706A), fontWeight: FontWeight.w600)),
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
                                      trailing: IconButton(onPressed: _applyApiUrl, icon: const Icon(Icons.check_rounded, color: Color(0xFFA14B2F)), tooltip: 'Apply'),
                                    ),
                                    const SizedBox(height: 8),
                                    Text('For a physical phone or installed APK, use your computer\'s LAN IP or a public API URL.', style: textTheme.bodySmall?.copyWith(color: const Color(0xFF7A6E68), height: 1.45)),
                                  ],
                                ),
                              ),
                              secondChild: const SizedBox.shrink(),
                            ),
                            const SizedBox(height: 22),
                            Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(color: const Color(0xFFF1E7DD), borderRadius: BorderRadius.circular(999), border: Border.all(color: const Color(0xFFE2D3C6))),
                              child: Row(children: [_rolePill('citizen', 'Citizen'), const SizedBox(width: 8), _rolePill('department', 'Department')]),
                            ),
                            const SizedBox(height: 14),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(color: const Color(0xFFF7EDE3), borderRadius: BorderRadius.circular(18), border: Border.all(color: const Color(0xFFE7D7C8))),
                              child: Text(roleSummary, style: textTheme.bodySmall?.copyWith(color: const Color(0xFF6F615A), fontSize: 12.5, height: 1.55)),
                            ),
                            const SizedBox(height: 22),
                            _fieldLabel('FULL NAME'),
                            const SizedBox(height: 10),
                            _inputShell(
                              child: TextField(
                                controller: _fullNameController,
                                textInputAction: TextInputAction.next,
                                decoration: InputDecoration(
                                  isDense: true,
                                  filled: false,
                                  fillColor: Colors.transparent,
                                  hintText: 'Juan Dela Cruz',
                                  border: InputBorder.none,
                                  hintStyle: TextStyle(color: const Color(0xFFC6B8AD).withValues(alpha: 0.98)),
                                ),
                                style: const TextStyle(color: Color(0xFF2F221D), fontSize: 15, height: 1.4),
                              ),
                            ),
                            const SizedBox(height: 18),
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
                            _fieldLabel('PASSWORD'),
                            const SizedBox(height: 10),
                            _inputShell(
                              child: TextField(
                                controller: _passwordController,
                                obscureText: _obscurePassword,
                                textInputAction: TextInputAction.done,
                                decoration: InputDecoration(
                                  isDense: true,
                                  filled: false,
                                  fillColor: Colors.transparent,
                                  hintText: 'Minimum 6 characters',
                                  border: InputBorder.none,
                                  hintStyle: TextStyle(color: const Color(0xFFC6B8AD).withValues(alpha: 0.98)),
                                ),
                                style: const TextStyle(color: Color(0xFF2F221D), fontSize: 15, height: 1.4),
                              ),
                              trailing: IconButton(
                                onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                                icon: Icon(_obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined, color: const Color(0xFFB26848)),
                                tooltip: _obscurePassword ? 'Show password' : 'Hide password',
                              ),
                            ),
                            if (_role == 'department') ...[
                              const SizedBox(height: 22),
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
                                    Text('Department details', style: textTheme.labelSmall?.copyWith(color: const Color(0xFFA14B2F), fontWeight: FontWeight.w800, letterSpacing: 2.1)),
                                    const SizedBox(height: 6),
                                    Text('These fields help the municipality verify your organization before operational access is approved.', style: textTheme.bodySmall?.copyWith(color: const Color(0xFF6B5E57), height: 1.5)),
                                    const SizedBox(height: 16),
                                    _fieldLabel('ORGANIZATION NAME'),
                                    const SizedBox(height: 10),
                                    _inputShell(
                                      child: TextField(
                                        controller: _orgNameController,
                                        textInputAction: TextInputAction.next,
                                        decoration: InputDecoration(isDense: true, filled: false, fillColor: Colors.transparent, hintText: 'Station or department name', border: InputBorder.none, hintStyle: TextStyle(color: const Color(0xFFC6B8AD).withValues(alpha: 0.98))),
                                        style: const TextStyle(color: Color(0xFF2F221D), fontSize: 15, height: 1.4),
                                      ),
                                    ),
                                    const SizedBox(height: 16),
                                    _fieldLabel('DEPARTMENT TYPE'),
                                    const SizedBox(height: 10),
                                    _inputShell(
                                      padding: const EdgeInsets.fromLTRB(18, 6, 14, 6),
                                      child: DropdownButtonHideUnderline(
                                        child: DropdownButton<String>(
                                          value: _deptType,
                                          isExpanded: true,
                                          dropdownColor: Colors.white,
                                          borderRadius: BorderRadius.circular(16),
                                          icon: const Icon(Icons.expand_more_rounded, color: Color(0xFFB26848)),
                                          style: const TextStyle(color: Color(0xFF2F221D), fontSize: 15),
                                          items: _departmentTypes.entries.map((entry) => DropdownMenuItem(value: entry.key, child: Text(entry.value))).toList(),
                                          onChanged: (value) => setState(() => _deptType = value ?? 'fire'),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 16),
                                    _fieldLabel('CONTACT NUMBER'),
                                    const SizedBox(height: 10),
                                    _inputShell(
                                      child: TextField(
                                        controller: _contactController,
                                        textInputAction: TextInputAction.next,
                                        decoration: InputDecoration(isDense: true, filled: false, fillColor: Colors.transparent, hintText: 'Agency hotline or contact number', border: InputBorder.none, hintStyle: TextStyle(color: const Color(0xFFC6B8AD).withValues(alpha: 0.98))),
                                        style: const TextStyle(color: Color(0xFF2F221D), fontSize: 15, height: 1.4),
                                      ),
                                    ),
                                    const SizedBox(height: 16),
                                    _fieldLabel('ADDRESS'),
                                    const SizedBox(height: 10),
                                    _inputShell(
                                      child: TextField(
                                        controller: _addressController,
                                        textInputAction: TextInputAction.next,
                                        decoration: InputDecoration(isDense: true, filled: false, fillColor: Colors.transparent, hintText: 'Office or station address', border: InputBorder.none, hintStyle: TextStyle(color: const Color(0xFFC6B8AD).withValues(alpha: 0.98))),
                                        style: const TextStyle(color: Color(0xFF2F221D), fontSize: 15, height: 1.4),
                                      ),
                                    ),
                                    const SizedBox(height: 16),
                                    _fieldLabel('AREA OF RESPONSIBILITY'),
                                    const SizedBox(height: 10),
                                    _inputShell(
                                      child: TextField(
                                        controller: _areaController,
                                        decoration: InputDecoration(isDense: true, filled: false, fillColor: Colors.transparent, hintText: 'Municipality, district, or assigned coverage', border: InputBorder.none, hintStyle: TextStyle(color: const Color(0xFFC6B8AD).withValues(alpha: 0.98))),
                                        style: const TextStyle(color: Color(0xFF2F221D), fontSize: 15, height: 1.4),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
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
                                  onPressed: _loading ? null : _handleRegister,
                                  style: FilledButton.styleFrom(
                                    backgroundColor: Colors.transparent,
                                    shadowColor: Colors.transparent,
                                    disabledBackgroundColor: Colors.transparent,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(vertical: 18),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                  ),
                                  child: Text(_loading ? 'Creating account...' : 'Create account', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, letterSpacing: 0.2)),
                                ),
                              ),
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
                                  Text('Already registered?', style: textTheme.labelSmall?.copyWith(color: const Color(0xFFA14B2F), fontWeight: FontWeight.w800, letterSpacing: 2.1)),
                                  const SizedBox(height: 6),
                                  Text('Return to the sign-in screen and continue into Dispatch with your existing credentials.', style: textTheme.bodyMedium?.copyWith(color: const Color(0xFF645A54), height: 1.55)),
                                  const SizedBox(height: 16),
                                  SizedBox(
                                    width: double.infinity,
                                    child: OutlinedButton(
                                      onPressed: widget.onSwitchToLogin,
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: const Color(0xFF6E625B),
                                        side: const BorderSide(color: Color(0xFFD6CABD)),
                                        padding: const EdgeInsets.symmetric(vertical: 14),
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
                                      ),
                                      child: const Text('Sign in', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 1.6)),
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

class _RegisterSlide {
  const _RegisterSlide(this.assetPath, this.semanticLabel);

  final String assetPath;
  final String semanticLabel;
}
