// Profile screen — edit full name and phone number.

import 'package:dispatch_mobile/core/state/session_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class CitizenProfileScreen extends ConsumerStatefulWidget {
  const CitizenProfileScreen({super.key});

  @override
  ConsumerState<CitizenProfileScreen> createState() => _CitizenProfileScreenState();
}

class _CitizenProfileScreenState extends ConsumerState<CitizenProfileScreen> {
  late TextEditingController _nameController;
  late TextEditingController _phoneController;
  bool _loading = false;
  String? _error;
  bool _success = false;

  @override
  void initState() {
    super.initState();
    final session = ref.read(sessionControllerProvider);
    _nameController = TextEditingController(text: session.fullName ?? '');
    _phoneController = TextEditingController();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _loading = true;
      _error = null;
      _success = false;
    });

    try {
      final authService = ref.read(authServiceProvider);
      await authService.updateProfile(
        fullName: _nameController.text.trim(),
        phone: _phoneController.text.trim(),
      );
      ref.read(sessionControllerProvider.notifier).updateFullName(_nameController.text.trim());
      if (mounted) setState(() { _loading = false; _success = true; });
    } catch (e) {
      if (mounted) setState(() { _loading = false; _error = e.toString(); });
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionControllerProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(session.email ?? '', style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.black54)),
          const SizedBox(height: 4),
          Chip(label: Text(session.role?.name ?? '')),
          const SizedBox(height: 24),
          if (_error != null)
            Container(
              padding: const EdgeInsets.all(12),
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(8)),
              child: Text(_error!, style: TextStyle(color: Colors.red.shade700)),
            ),
          if (_success)
            Container(
              padding: const EdgeInsets.all(12),
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(color: Colors.green.shade50, borderRadius: BorderRadius.circular(8)),
              child: Text('Profile updated.', style: TextStyle(color: Colors.green.shade700)),
            ),
          TextField(
            controller: _nameController,
            decoration: const InputDecoration(labelText: 'Full name', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _phoneController,
            decoration: const InputDecoration(labelText: 'Phone number', border: OutlineInputBorder()),
            keyboardType: TextInputType.phone,
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _loading ? null : _save,
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            child: Text(_loading ? 'Saving...' : 'Save Changes'),
          ),
        ],
      ),
    );
  }
}
