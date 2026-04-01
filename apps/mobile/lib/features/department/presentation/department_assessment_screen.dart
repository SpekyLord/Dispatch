import 'package:dispatch_mobile/core/i18n/app_strings.dart';
import 'package:dispatch_mobile/core/i18n/locale_action_button.dart';
import 'package:dispatch_mobile/core/state/session.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class DepartmentAssessmentScreen extends ConsumerStatefulWidget {
  const DepartmentAssessmentScreen({super.key});

  @override
  ConsumerState<DepartmentAssessmentScreen> createState() =>
      _DepartmentAssessmentScreenState();
}

class _DepartmentAssessmentScreenState
    extends ConsumerState<DepartmentAssessmentScreen> {
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
      if (mounted) {
        setState(() {
          _assessments = list;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      final authService = ref.read(authServiceProvider);
      final area = _areaCtrl.text.trim();
      final casualties = int.tryParse(_casualtiesCtrl.text.trim()) ?? 0;
      final displaced = int.tryParse(_displacedCtrl.text.trim()) ?? 0;
      final location = _locationCtrl.text.trim();
      final description = _descriptionCtrl.text.trim();

      await authService.createAssessment(
        affectedArea: area,
        damageLevel: _damageLevel,
        estimatedCasualties: casualties,
        displacedPersons: displaced,
        location: location.isNotEmpty ? location : null,
        description: description.isNotEmpty ? description : null,
      );

      _areaCtrl.clear();
      _casualtiesCtrl.text = '0';
      _displacedCtrl.text = '0';
      _locationCtrl.clear();
      _descriptionCtrl.clear();

      setState(() => _damageLevel = 'minor');
      await _fetchAssessments();

      if (mounted) {
        final strings = ref.read(appStringsProvider);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(strings.assessmentSubmitted)),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = e.toString());
      }
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

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
    final strings = ref.watch(appStringsProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(strings.assessmentScreenTitle),
        actions: const [LocaleActionButton()],
      ),
      body: RefreshIndicator(
        onRefresh: _fetchAssessments,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              strings.newAssessment,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
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
                  style: TextStyle(color: Colors.red.shade700, fontSize: 13),
                ),
              ),
            Form(
              key: _formKey,
              child: Column(
                children: [
                  TextFormField(
                    controller: _areaCtrl,
                    decoration: InputDecoration(
                      labelText: strings.affectedArea,
                      border: const OutlineInputBorder(),
                    ),
                    validator: (value) => (value == null || value.trim().isEmpty)
                        ? strings.required
                        : null,
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    decoration: InputDecoration(
                      labelText: strings.damageLevel,
                      border: const OutlineInputBorder(),
                    ),
                    initialValue: _damageLevel,
                    onChanged: (value) {
                      if (value != null) {
                        setState(() => _damageLevel = value);
                      }
                    },
                    items: [
                      DropdownMenuItem(
                        value: 'minor',
                        child: Text(strings.damageLevelLabel('minor')),
                      ),
                      DropdownMenuItem(
                        value: 'moderate',
                        child: Text(strings.damageLevelLabel('moderate')),
                      ),
                      DropdownMenuItem(
                        value: 'severe',
                        child: Text(strings.damageLevelLabel('severe')),
                      ),
                      DropdownMenuItem(
                        value: 'critical',
                        child: Text(strings.damageLevelLabel('critical')),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _casualtiesCtrl,
                    decoration: InputDecoration(
                      labelText: strings.estimatedCasualties,
                      border: const OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.number,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _displacedCtrl,
                    decoration: InputDecoration(
                      labelText: strings.displacedPersons,
                      border: const OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.number,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _locationCtrl,
                    decoration: InputDecoration(
                      labelText: strings.location,
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _descriptionCtrl,
                    decoration: InputDecoration(
                      labelText: strings.description,
                      border: const OutlineInputBorder(),
                    ),
                    maxLines: 3,
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _submitting ? null : _submit,
                      child: Text(
                        _submitting
                            ? strings.submitting
                            : strings.submitAssessment,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),
            Text(
              strings.previousAssessments,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            if (_loading)
              const Center(child: CircularProgressIndicator())
            else if (_assessments.isEmpty)
              Text(
                strings.noAssessmentsSubmittedYet,
                style: const TextStyle(color: Colors.black45),
              )
            else
              for (final assessment in _assessments)
                _buildAssessmentCard(assessment, strings),
          ],
        ),
      ),
    );
  }

  Widget _buildAssessmentCard(
    Map<String, dynamic> assessment,
    AppStrings strings,
  ) {
    final level = assessment['damage_level'] as String? ?? 'minor';
    final area = assessment['affected_area'] as String? ?? '';
    final casualties = assessment['estimated_casualties'] ?? 0;
    final displaced = assessment['displaced_persons'] ?? 0;
    final createdAt = assessment['created_at'] as String? ?? '';

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
                  child: Text(
                    area,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: _damageLevelColor(level).withAlpha(30),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    strings.damageLevelLabel(level).toUpperCase(),
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: _damageLevelColor(level),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              strings.casualtiesAndDisplaced(casualties as int, displaced as int),
              style: const TextStyle(fontSize: 12, color: Colors.black54),
            ),
            if (assessment['location'] != null) ...[
              const SizedBox(height: 4),
              Row(
                children: [
                  const Icon(
                    Icons.location_on,
                    size: 13,
                    color: Colors.black45,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      assessment['location'] as String,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.black54,
                      ),
                    ),
                  ),
                ],
              ),
            ],
            if (assessment['description'] != null) ...[
              const SizedBox(height: 4),
              Text(
                assessment['description'] as String,
                style: const TextStyle(fontSize: 12),
              ),
            ],
            const SizedBox(height: 4),
            Text(
              createdAt,
              style: const TextStyle(fontSize: 10, color: Colors.black38),
            ),
          ],
        ),
      ),
    );
  }
}
