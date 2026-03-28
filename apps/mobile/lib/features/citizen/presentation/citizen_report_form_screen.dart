import 'package:dispatch_mobile/core/state/session_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const _categories = [
  ('fire', 'Fire'),
  ('flood', 'Flood'),
  ('earthquake', 'Earthquake'),
  ('road_accident', 'Road Accident'),
  ('medical', 'Medical Emergency'),
  ('structural', 'Structural Damage'),
  ('other', 'Other'),
];

const _severities = [
  ('low', 'Low'),
  ('medium', 'Medium'),
  ('high', 'High'),
  ('critical', 'Critical'),
];

class CitizenReportFormScreen extends ConsumerStatefulWidget {
  const CitizenReportFormScreen({super.key});

  @override
  ConsumerState<CitizenReportFormScreen> createState() => _CitizenReportFormScreenState();
}

class _CitizenReportFormScreenState extends ConsumerState<CitizenReportFormScreen> {
  final _descController = TextEditingController();
  final _addressController = TextEditingController();
  String? _category;
  String _severity = 'medium';
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _descController.dispose();
    _addressController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_category == null) {
      setState(() => _error = 'Please select a category.');
      return;
    }
    if (_descController.text.trim().isEmpty) {
      setState(() => _error = 'Description is required.');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final authService = ref.read(authServiceProvider);
      await authService.createReport(
        description: _descController.text.trim(),
        category: _category!,
        severity: _severity,
        address: _addressController.text.trim().isNotEmpty ? _addressController.text.trim() : null,
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = e.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('New Report')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          if (_error != null)
            Container(
              padding: const EdgeInsets.all(12),
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red.shade200),
              ),
              child: Text(_error!, style: TextStyle(color: Colors.red.shade700)),
            ),
          TextField(
            controller: _descController,
            decoration: const InputDecoration(
              labelText: 'Description *',
              hintText: 'Describe the incident in detail...',
              border: OutlineInputBorder(),
            ),
            maxLines: 4,
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            value: _category,
            decoration: const InputDecoration(
              labelText: 'Category *',
              border: OutlineInputBorder(),
            ),
            items: _categories
                .map((c) => DropdownMenuItem(value: c.$1, child: Text(c.$2)))
                .toList(),
            onChanged: (v) => setState(() => _category = v),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            value: _severity,
            decoration: const InputDecoration(
              labelText: 'Severity',
              border: OutlineInputBorder(),
            ),
            items: _severities
                .map((s) => DropdownMenuItem(value: s.$1, child: Text(s.$2)))
                .toList(),
            onChanged: (v) => setState(() => _severity = v ?? 'medium'),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _addressController,
            decoration: const InputDecoration(
              labelText: 'Address / Location',
              hintText: 'e.g. Corner of Rizal Ave and Mabini St',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _loading ? null : _submit,
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
            child: Text(_loading ? 'Submitting...' : 'Submit Report'),
          ),
        ],
      ),
    );
  }
}
