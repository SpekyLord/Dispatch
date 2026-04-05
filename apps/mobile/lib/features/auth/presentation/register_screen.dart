// Register screen - citizen or department account creation.
// Department fields remain conditional when role = 'department'.

import 'package:dispatch_mobile/core/config/app_config.dart';
import 'package:dispatch_mobile/core/state/session.dart';
import 'package:dispatch_mobile/core/theme/dispatch_colors.dart' as dc;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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

  String _role = 'citizen';
  String _deptType = 'fire';
  bool _loading = false;
  bool _showServerConfig = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final currentUrl =
        ref.read(sessionControllerProvider.notifier).currentApiBaseUrl;
    _apiUrlController = TextEditingController(text: currentUrl);
    if (_currentApiHelp(currentUrl) != null) {
      _showServerConfig = true;
    }
  }

  @override
  void dispose() {
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
    if (mounted) {
      setState(() => _error = null);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Server URL set to $url')),
      );
    }
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
      organizationName: _role == 'department'
          ? _orgNameController.text.trim()
          : null,
      departmentType: _role == 'department' ? _deptType : null,
      contactNumber: _role == 'department'
          ? _contactController.text.trim()
          : null,
      address: _role == 'department' ? _addressController.text.trim() : null,
      areaOfResponsibility: _role == 'department'
          ? _areaController.text.trim()
          : null,
    );

    if (mounted) {
      if (err == 'CONFIRM_EMAIL') {
        // Registration succeeded but email verification is required.
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Account created! Check your email to confirm, then sign in.',
            ),
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
  }

  @override
  Widget build(BuildContext context) {
    final currentUrl = ref
        .read(sessionControllerProvider.notifier)
        .currentApiBaseUrl;
    final apiHelp = _currentApiHelp(currentUrl);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Register'),
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
                    'Create a field-ready account.',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 28,
                      fontWeight: FontWeight.w700,
                      height: 1.05,
                    ),
                  ),
                  SizedBox(height: 10),
                  Text(
                    'Citizens can report emergencies immediately, while departments can submit their verification profile from the same mobile flow.',
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
                      'Register',
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Choose your role and complete the matching profile fields.',
                      style: Theme.of(context).textTheme.bodyMedium,
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
                    if (apiHelp != null)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        margin: const EdgeInsets.only(bottom: 16),
                        decoration: BoxDecoration(
                          color: dc.alertFill,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: dc.warmSeed.withValues(alpha: 0.18),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Android API target',
                              style: TextStyle(
                                color: dc.warmSeed,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              apiHelp,
                              style: const TextStyle(color: dc.warmSeed),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Current target: $currentUrl',
                              style: const TextStyle(
                                color: dc.mutedInk,
                                fontSize: 12,
                              ),
                            ),
                          ],
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
                        'For a physical phone or installed APK, use your computer\'s LAN IP or a public API URL.',
                        style: TextStyle(
                          color: dc.mutedInk,
                          fontSize: 11,
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    Row(
                      children: [
                        Expanded(
                          child: ChoiceChip(
                            label: const Text('Citizen'),
                            selected: _role == 'citizen',
                            onSelected: (_) =>
                                setState(() => _role = 'citizen'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: ChoiceChip(
                            label: const Text('Department'),
                            selected: _role == 'department',
                            onSelected: (_) =>
                                setState(() => _role = 'department'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _fullNameController,
                      decoration: const InputDecoration(labelText: 'Full name'),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: _emailController,
                      decoration: const InputDecoration(labelText: 'Email'),
                      keyboardType: TextInputType.emailAddress,
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: _passwordController,
                      decoration: const InputDecoration(
                        labelText: 'Password (min 6 characters)',
                      ),
                      obscureText: true,
                    ),
                    if (_role == 'department') ...[
                      const SizedBox(height: 18),
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: dc.chipFill,
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Department details',
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.3,
                              ),
                            ),
                            const SizedBox(height: 12),
                            TextField(
                              controller: _orgNameController,
                              decoration: const InputDecoration(
                                labelText: 'Organization name *',
                              ),
                            ),
                            const SizedBox(height: 12),
                            DropdownButtonFormField<String>(
                              value: _deptType,
                              decoration: const InputDecoration(
                                labelText: 'Department type',
                              ),
                              items: const [
                                DropdownMenuItem(
                                  value: 'fire',
                                  child: Text('Fire (BFP)'),
                                ),
                                DropdownMenuItem(
                                  value: 'police',
                                  child: Text('Police (PNP)'),
                                ),
                                DropdownMenuItem(
                                  value: 'medical',
                                  child: Text('Medical'),
                                ),
                                DropdownMenuItem(
                                  value: 'disaster',
                                  child: Text('MDRRMO'),
                                ),
                                DropdownMenuItem(
                                  value: 'rescue',
                                  child: Text('Rescue'),
                                ),
                                DropdownMenuItem(
                                  value: 'other',
                                  child: Text('Other'),
                                ),
                              ],
                              onChanged: (value) =>
                                  setState(() => _deptType = value ?? 'fire'),
                            ),
                            const SizedBox(height: 12),
                            TextField(
                              controller: _contactController,
                              decoration: const InputDecoration(
                                labelText: 'Contact number',
                              ),
                            ),
                            const SizedBox(height: 12),
                            TextField(
                              controller: _addressController,
                              decoration: const InputDecoration(
                                labelText: 'Address',
                              ),
                            ),
                            const SizedBox(height: 12),
                            TextField(
                              controller: _areaController,
                              decoration: const InputDecoration(
                                labelText: 'Area of responsibility',
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 20),
                    FilledButton(
                      onPressed: _loading ? null : _handleRegister,
                      child: Text(
                        _loading ? 'Creating account...' : 'Create account',
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextButton(
                      onPressed: widget.onSwitchToLogin,
                      child: const Text('Already have an account? Sign in'),
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
