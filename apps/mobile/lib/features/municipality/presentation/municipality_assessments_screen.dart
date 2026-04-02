import 'package:dispatch_mobile/core/state/session.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class MunicipalityAssessmentsScreen extends ConsumerStatefulWidget {
  const MunicipalityAssessmentsScreen({super.key});

  @override
  ConsumerState<MunicipalityAssessmentsScreen> createState() =>
      _MunicipalityAssessmentsScreenState();
}

class _MunicipalityAssessmentsScreenState
    extends ConsumerState<MunicipalityAssessmentsScreen> {
  List<Map<String, dynamic>> _assessments = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _fetchAssessments();
  }

  Future<void> _fetchAssessments() async {
    setState(() => _loading = true);
    try {
      final assessments = await ref
          .read(authServiceProvider)
          .getMunicipalityAssessments();
      if (!mounted) return;
      setState(() {
        _assessments = assessments;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Assessments')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _assessments.isEmpty
          ? const Center(child: Text('No assessments submitted yet.'))
          : RefreshIndicator(
              onRefresh: _fetchAssessments,
              child: ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: _assessments.length,
                separatorBuilder: (_, _) => const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  final assessment = _assessments[index];
                  return Card(
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  assessment['affected_area'] as String? ??
                                      'Affected area',
                                  style: Theme.of(context).textTheme.titleLarge,
                                ),
                              ),
                              Chip(
                                label: Text(
                                  (assessment['damage_level'] as String? ??
                                          'unknown')
                                      .toUpperCase(),
                                ),
                              ),
                            ],
                          ),
                          if ((assessment['location'] as String?)?.isNotEmpty ==
                              true) ...[
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                const Icon(
                                  Icons.location_on_outlined,
                                  size: 16,
                                  color: Color(0xFFA14B2F),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(assessment['location'] as String),
                                ),
                              ],
                            ),
                          ],
                          const SizedBox(height: 10),
                          Text(
                            assessment['description'] as String? ??
                                'No assessment notes were provided.',
                          ),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              Chip(
                                label: Text(
                                  'Casualties ${assessment['estimated_casualties'] ?? 0}',
                                ),
                              ),
                              Chip(
                                label: Text(
                                  'Displaced ${assessment['displaced_persons'] ?? 0}',
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
    );
  }
}
