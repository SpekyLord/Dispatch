// Register screen - citizen or department account creation.
// Department fields remain conditional when role = 'department'.

import 'package:dispatch_mobile/core/state/session.dart';
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
  final _fullNameController = TextEditingController();
  final _orgNameController = TextEditingController();
  final _contactController = TextEditingController();
  final _addressController = TextEditingController();
  final _areaController = TextEditingController();

  String _role = 'citizen';
  String _deptType = 'fire';
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _fullNameController.dispose();
    _orgNameController.dispose();
    _contactController.dispose();
    _addressController.dispose();
    _areaController.dispose();
    super.dispose();
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
      setState(() {
        _loading = false;
        _error = err;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 18, 24, 28),
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [
                    Color(0xFFA14B2F),
                    Color(0xFF7B3A25),
                    Color(0xFF425E72),
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
                    style: TextStyle(color: Color(0xFFF9EEE9), height: 1.45),
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
                          color: const Color(0xFFFFF1EB),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Text(
                          _error!,
                          style: const TextStyle(color: Color(0xFFA14B2F)),
                        ),
                      ),
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
                          color: const Color(0xFFF7EADF),
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
                              initialValue: _deptType,
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
