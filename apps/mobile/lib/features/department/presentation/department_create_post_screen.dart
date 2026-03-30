// Department post creation Ã¢â‚¬â€ verified departments publish announcements to citizen feed.

import 'package:dispatch_mobile/core/state/session_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class DepartmentCreatePostScreen extends ConsumerStatefulWidget {
  const DepartmentCreatePostScreen({super.key});

  @override
  ConsumerState<DepartmentCreatePostScreen> createState() =>
      _DepartmentCreatePostScreenState();
}

class _DepartmentCreatePostScreenState
    extends ConsumerState<DepartmentCreatePostScreen> {
  final _titleCtrl = TextEditingController();
  final _contentCtrl = TextEditingController();
  String _category = 'update';
  bool _isPinned = false;
  bool _loading = false;
  String? _error;

  static const _categories = [
    ('alert', 'Alert'),
    ('warning', 'Warning'),
    ('safety_tip', 'Safety Tip'),
    ('update', 'Update'),
    ('situational_report', 'Situational Report'),
  ];

  @override
  void dispose() {
    _titleCtrl.dispose();
    _contentCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_titleCtrl.text.trim().isEmpty || _contentCtrl.text.trim().isEmpty) {
      setState(() => _error = 'Title and content are required.');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await ref
          .read(authServiceProvider)
          .createPost(
            title: _titleCtrl.text.trim(),
            content: _contentCtrl.text.trim(),
            category: _category,
            isPinned: _isPinned,
          );
      if (mounted) {
        Navigator.pop(context, true);
      }
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
      appBar: AppBar(title: const Text('Create Post')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          if (_error != null)
            Container(
              padding: const EdgeInsets.all(12),
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                _error!,
                style: TextStyle(color: Colors.red.shade700),
              ),
            ),

          TextField(
            controller: _titleCtrl,
            decoration: const InputDecoration(
              labelText: 'Title',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),

          TextField(
            controller: _contentCtrl,
            decoration: const InputDecoration(
              labelText: 'Content',
              border: OutlineInputBorder(),
              alignLabelWithHint: true,
            ),
            maxLines: 5,
          ),
          const SizedBox(height: 16),

          DropdownButtonFormField<String>(
            initialValue: _category,
            decoration: const InputDecoration(
              labelText: 'Category',
              border: OutlineInputBorder(),
            ),
            items: _categories
                .map((c) => DropdownMenuItem(value: c.$1, child: Text(c.$2)))
                .toList(),
            onChanged: (v) {
              if (v != null) setState(() => _category = v);
            },
          ),
          const SizedBox(height: 12),

          CheckboxListTile(
            title: const Text('Pin this post'),
            value: _isPinned,
            onChanged: (v) => setState(() => _isPinned = v ?? false),
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: EdgeInsets.zero,
          ),
          const SizedBox(height: 16),

          FilledButton(
            onPressed: _loading ? null : _submit,
            child: Text(_loading ? 'Publishing...' : 'Publish'),
          ),
        ],
      ),
    );
  }
}
