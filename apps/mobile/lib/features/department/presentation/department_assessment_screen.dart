// Damage assessment screen — form to submit + list of past assessments.

import 'package:dispatch_mobile/core/state/session_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class DepartmentAssessmentScreen extends ConsumerStatefulWidget {
  const DepartmentAssessmentScreen({super.key});

  @override
  ConsumerState<DepartmentAssessmentScreen> createState() => _DepartmentAssessmentScreenState();
}

class _DepartmentAssessmentScreenState extends ConsumerState<DepartmentAssessmentScreen> {
  final _formKey = GlobalKey<FormState>();
  final _areaCtrl = TextEditingController();
  final _casualtiesCtrl = TextEditingController(text: '0');
  final _displacedCtrl = TextEditingController(text: '0');
  final _locationCtrl = TextEditingController();
  final _descriptionCtrl = TextEditingController();

  String _damageLevel = 'minor';
  bool _submitting = false;
  String? _error;

  List<Map<String, dynamic>> _assessments = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _fetchAssessments();
  }

  @override
  void dispose() {
    _areaCtrl.dispose();
    _casualtiesCtrl.dispose();
    _displacedCtrl.dispose();
    _locationCtrl.dispose();
    _descriptionCtrl.dispose();
    super.dispose();
  }

  Future<void> _fetchAssessments() async {
    try {
      final authService = ref.read(authServiceProvider);
      final list = await authService.getDepartmentAssessments();
      if (mounted) setState(() { _assessments = list; _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() { _submitting = true; _error = null; });
    try {
      final authService = ref.read(authServiceProvider);
      // Build body imperatively — no conditional map entries
      final area = _areaCtrl.text.trim();
      final casualties = int.tryParse(_casualtiesCtrl.text.trim()) ?? 0;
      final displaced = int.tryParse(_displacedCtrl.text.trim()) ?? 0;
      final loc = _locationCtrl.text.trim();
      final desc = _descriptionCtrl.text.trim();

      await authService.createAssessment(
        affectedArea: area,
        damageLevel: _damageLevel,
        estimatedCasualties: casualties,
        displacedPersons: displaced,
        location: loc.isNotEmpty ? loc : null,
        description: desc.isNotEmpty ? desc : null,
      );

      // Reset form and refresh list
      _areaCtrl.clear();
      _casualtiesCtrl.text = '0';
      _displacedCtrl.text = '0';
      _locationCtrl.clear();
      _descriptionCtrl.clear();
      setState(() => _damageLevel = 'minor');
      await _fetchAssessments();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Assessment submitted')),
        );
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  // Map damage level to badge color
  Color _damageLevelColor(String level) {
    return switch (level) {
      'minor' => Colors.green,
      'moderate' => Colors.amber.shade700,
      'severe' => Colors.orange,
      'critical' => Colors.red,
      _ => Colors.grey,
    };
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Damage Assessment')),
      body: RefreshIndicator(
        onRefresh: () => _fetchAssessments(),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // --- Submit form ---
            Text('New Assessment', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            if (_error != null)
              Container(
                padding: const EdgeInsets.all(12),
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(8)),
                child: Text(_error!, style: TextStyle(color: Colors.red.shade700, fontSize: 13)),
              ),
            Form(
              key: _formKey,
              child: Column(
                children: [
                  TextFormField(
                    controller: _areaCtrl,
                    decoration: const InputDecoration(labelText: 'Affected Area *', border: OutlineInputBorder()),
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    decoration: const InputDecoration(labelText: 'Damage Level', border: OutlineInputBorder()),
                    initialValue: _damageLevel,
                    onChanged: (v) {
                      if (v != null) setState(() => _damageLevel = v);
                    },
                    items: const [
                      DropdownMenuItem(value: 'minor', child: Text('Minor')),
                      DropdownMenuItem(value: 'moderate', child: Text('Moderate')),
                      DropdownMenuItem(value: 'severe', child: Text('Severe')),
                      DropdownMenuItem(value: 'critical', child: Text('Critical')),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _casualtiesCtrl,
                    decoration: const InputDecoration(labelText: 'Estimated Casualties', border: OutlineInputBorder()),
                    keyboardType: TextInputType.number,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _displacedCtrl,
                    decoration: const InputDecoration(labelText: 'Displaced Persons', border: OutlineInputBorder()),
                    keyboardType: TextInputType.number,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _locationCtrl,
                    decoration: const InputDecoration(labelText: 'Location', border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _descriptionCtrl,
                    decoration: const InputDecoration(labelText: 'Description', border: OutlineInputBorder()),
                    maxLines: 3,
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _submitting ? null : _submit,
                      child: Text(_submitting ? 'Submitting...' : 'Submit Assessment'),
                    ),
                  ),
                ],
              ),
            ),

            // --- Past assessments ---
            const SizedBox(height: 32),
            Text('Previous Assessments', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            if (_loading)
              const Center(child: CircularProgressIndicator())
            else if (_assessments.isEmpty)
              const Text('No assessments submitted yet.', style: TextStyle(color: Colors.black45))
            else
              for (int i = 0; i < _assessments.length; i++)
                _buildAssessmentCard(_assessments[i]),
          ],
        ),
      ),
    );
  }

  Widget _buildAssessmentCard(Map<String, dynamic> a) {
    final level = a['damage_level'] as String? ?? 'minor';
    final area = a['affected_area'] as String? ?? '';
    final casualties = a['estimated_casualties'] ?? 0;
    final displaced = a['displaced_persons'] ?? 0;
    final createdAt = a['created_at'] as String? ?? '';

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(area, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: _damageLevelColor(level).withAlpha(30),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    level.toUpperCase(),
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: _damageLevelColor(level)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text('Casualties: $casualties  |  Displaced: $displaced', style: const TextStyle(fontSize: 12, color: Colors.black54)),
            if (a['location'] != null) ...[
              const SizedBox(height: 4),
              Row(
                children: [
                  const Icon(Icons.location_on, size: 13, color: Colors.black45),
                  const SizedBox(width: 4),
                  Expanded(child: Text(a['location'] as String, style: const TextStyle(fontSize: 12, color: Colors.black54))),
                ],
              ),
            ],
            if (a['description'] != null) ...[
              const SizedBox(height: 4),
              Text(a['description'] as String, style: const TextStyle(fontSize: 12)),
            ],
            const SizedBox(height: 4),
            Text(createdAt, style: const TextStyle(fontSize: 10, color: Colors.black38)),
          ],
        ),
      ),
    );
  }
}
