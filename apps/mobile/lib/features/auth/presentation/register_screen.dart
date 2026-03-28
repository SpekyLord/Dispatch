import 'package:dispatch_mobile/core/state/session_controller.dart';
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
      organizationName: _role == 'department' ? _orgNameController.text.trim() : null,
      departmentType: _role == 'department' ? _deptType : null,
      contactNumber: _role == 'department' ? _contactController.text.trim() : null,
      address: _role == 'department' ? _addressController.text.trim() : null,
      areaOfResponsibility: _role == 'department' ? _areaController.text.trim() : null,
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
          padding: const EdgeInsets.all(24),
          children: [
            const SizedBox(height: 40),
            Text(
              'DISPATCH',
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: const Color(0xFFE05A2B),
                    fontWeight: FontWeight.w700,
                    letterSpacing: 2.0,
                  ),
            ),
            const SizedBox(height: 12),
            Text(
              'Create an account',
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 24),
            if (_error != null)
              Container(
                padding: const EdgeInsets.all(12),
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red.shade200),
                ),
                child: Text(_error!, style: TextStyle(color: Colors.red.shade700, fontSize: 14)),
              ),
            // Role selector
            Row(
              children: [
                Expanded(
                  child: ChoiceChip(
                    label: const Text('Citizen'),
                    selected: _role == 'citizen',
                    onSelected: (_) => setState(() => _role = 'citizen'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ChoiceChip(
                    label: const Text('Department'),
                    selected: _role == 'department',
                    onSelected: (_) => setState(() => _role = 'department'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _fullNameController,
              decoration: const InputDecoration(
                labelText: 'Full name',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _emailController,
              decoration: const InputDecoration(
                labelText: 'Email',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.emailAddress,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _passwordController,
              decoration: const InputDecoration(
                labelText: 'Password (min 6 characters)',
                border: OutlineInputBorder(),
              ),
              obscureText: true,
            ),
            if (_role == 'department') ...[
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'DEPARTMENT DETAILS',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            letterSpacing: 1.2,
                            fontWeight: FontWeight.w600,
                            color: Colors.black54,
                          ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _orgNameController,
                      decoration: const InputDecoration(
                        labelText: 'Organization name *',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: _deptType,
                      decoration: const InputDecoration(
                        labelText: 'Department type',
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(value: 'fire', child: Text('Fire (BFP)')),
                        DropdownMenuItem(value: 'police', child: Text('Police (PNP)')),
                        DropdownMenuItem(value: 'medical', child: Text('Medical')),
                        DropdownMenuItem(value: 'disaster', child: Text('MDRRMO')),
                        DropdownMenuItem(value: 'rescue', child: Text('Rescue')),
                        DropdownMenuItem(value: 'other', child: Text('Other')),
                      ],
                      onChanged: (v) => setState(() => _deptType = v ?? 'fire'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _contactController,
                      decoration: const InputDecoration(
                        labelText: 'Contact number',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.phone,
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _addressController,
                      decoration: const InputDecoration(
                        labelText: 'Address',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _areaController,
                      decoration: const InputDecoration(
                        labelText: 'Area of responsibility',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _loading ? null : _handleRegister,
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
              child: Text(_loading ? 'Creating account...' : 'Create account'),
            ),
            const SizedBox(height: 16),
            TextButton(
              onPressed: widget.onSwitchToLogin,
              child: const Text('Already have an account? Sign in'),
            ),
          ],
        ),
      ),
    );
  }
}
