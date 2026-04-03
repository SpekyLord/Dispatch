import 'package:dispatch_mobile/core/state/session.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class MunicipalityEscalatedReportsScreen extends ConsumerStatefulWidget {
  const MunicipalityEscalatedReportsScreen({super.key});

  @override
  ConsumerState<MunicipalityEscalatedReportsScreen> createState() =>
      _MunicipalityEscalatedReportsScreenState();
}

class _MunicipalityEscalatedReportsScreenState
    extends ConsumerState<MunicipalityEscalatedReportsScreen> {
  List<Map<String, dynamic>> _reports = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _fetchReports();
  }

  Future<void> _fetchReports() async {
    setState(() => _loading = true);
    try {
      final reports = await ref
          .read(authServiceProvider)
          .getMunicipalityEscalatedReports();
      if (!mounted) return;
      setState(() {
        _reports = reports;
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
      appBar: AppBar(title: const Text('Escalated Reports')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _reports.isEmpty
          ? const Center(child: Text('No unresolved escalations right now.'))
          : RefreshIndicator(
              onRefresh: _fetchReports,
              child: ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: _reports.length,
                separatorBuilder: (_, _) => const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  final report = _reports[index];
                  final responseSummary =
                      report['response_summary'] as Map<String, dynamic>? ??
                      const {};
                  return Card(
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              const Chip(label: Text('Escalated')),
                              Chip(
                                label: Text(
                                  (report['status'] as String? ?? 'pending')
                                      .toUpperCase(),
                                ),
                              ),
                              Chip(
                                label: Text(
                                  (report['category'] as String? ?? 'other')
                                      .replaceAll('_', ' '),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Text(
                            report['title'] as String? ??
                                report['description'] as String? ??
                                'Escalated report',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          const SizedBox(height: 8),
                          Text(report['description'] as String? ?? ''),
                          if ((report['address'] as String?)?.isNotEmpty ==
                              true) ...[
                            const SizedBox(height: 10),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Icon(
                                  Icons.location_on_outlined,
                                  size: 16,
                                  color: Color(0xFFA14B2F),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(report['address'] as String),
                                ),
                              ],
                            ),
                          ],
                          const SizedBox(height: 14),
                          Row(
                            children: [
                              _SummaryPill(
                                label: 'Accepted',
                                value: '${responseSummary['accepted'] ?? 0}',
                                tone: const Color(0xFF397154),
                              ),
                              const SizedBox(width: 8),
                              _SummaryPill(
                                label: 'Declined',
                                value: '${responseSummary['declined'] ?? 0}',
                                tone: const Color(0xFFD97757),
                              ),
                              const SizedBox(width: 8),
                              _SummaryPill(
                                label: 'Pending',
                                value: '${responseSummary['pending'] ?? 0}',
                                tone: const Color(0xFF1695D3),
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

class _SummaryPill extends StatelessWidget {
  const _SummaryPill({
    required this.label,
    required this.value,
    required this.tone,
  });

  final String label;
  final String value;
  final Color tone;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          color: tone.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          children: [
            Text(
              value,
              style: TextStyle(color: tone, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text(label, style: const TextStyle(fontSize: 11)),
          ],
        ),
      ),
    );
  }
}
