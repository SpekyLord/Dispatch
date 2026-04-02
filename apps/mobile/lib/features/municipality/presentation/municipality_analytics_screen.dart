import 'package:dispatch_mobile/core/state/session.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class MunicipalityAnalyticsScreen extends ConsumerStatefulWidget {
  const MunicipalityAnalyticsScreen({super.key});

  @override
  ConsumerState<MunicipalityAnalyticsScreen> createState() =>
      _MunicipalityAnalyticsScreenState();
}

class _MunicipalityAnalyticsScreenState
    extends ConsumerState<MunicipalityAnalyticsScreen> {
  Map<String, dynamic>? _analytics;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _fetchAnalytics();
  }

  Future<void> _fetchAnalytics() async {
    setState(() => _loading = true);
    try {
      final analytics = await ref
          .read(authServiceProvider)
          .getMunicipalityAnalytics();
      if (!mounted) return;
      setState(() {
        _analytics = analytics;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final analytics = _analytics;
    final byCategory =
        analytics?['by_category'] as Map<String, dynamic>? ?? const {};
    final byStatus =
        analytics?['by_status'] as Map<String, dynamic>? ?? const {};
    final responseTimes =
        analytics?['response_times'] as Map<String, dynamic>? ?? const {};

    return Scaffold(
      appBar: AppBar(title: const Text('Analytics')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : analytics == null
          ? const Center(child: Text('Analytics are unavailable right now.'))
          : RefreshIndicator(
              onRefresh: _fetchAnalytics,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      _AnalyticsTile(
                        label: 'Total reports',
                        value: '${analytics['total_reports'] ?? 0}',
                      ),
                      _AnalyticsTile(
                        label: 'Last 7 days',
                        value: '${analytics['last_7_days'] ?? 0}',
                      ),
                      _AnalyticsTile(
                        label: 'Last 30 days',
                        value: '${analytics['last_30_days'] ?? 0}',
                      ),
                      _AnalyticsTile(
                        label: 'Unattended',
                        value: '${analytics['unattended_reports'] ?? 0}',
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  _AnalyticsSection(
                    title: 'Reports by category',
                    entries: byCategory,
                  ),
                  const SizedBox(height: 12),
                  _AnalyticsSection(
                    title: 'Reports by status',
                    entries: byStatus,
                  ),
                  const SizedBox(height: 12),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Response timing',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          const SizedBox(height: 12),
                          _TimingRow(
                            label: 'Create to accept',
                            value: responseTimes['avg_create_to_accept'],
                          ),
                          _TimingRow(
                            label: 'Accept to responding',
                            value: responseTimes['avg_accept_to_responding'],
                          ),
                          _TimingRow(
                            label: 'Responding to resolved',
                            value: responseTimes['avg_responding_to_resolved'],
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

class _AnalyticsTile extends StatelessWidget {
  const _AnalyticsTile({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: (MediaQuery.of(context).size.width - 44) / 2,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(value, style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 8),
              Text(label),
            ],
          ),
        ),
      ),
    );
  }
}

class _AnalyticsSection extends StatelessWidget {
  const _AnalyticsSection({required this.title, required this.entries});

  final String title;
  final Map<String, dynamic> entries;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            if (entries.isEmpty)
              const Text('No data yet.')
            else
              ...entries.entries.map(
                (entry) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    children: [
                      Expanded(child: Text(entry.key.replaceAll('_', ' '))),
                      Text(
                        '${entry.value}',
                        style: const TextStyle(fontWeight: FontWeight.w700),
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

class _TimingRow extends StatelessWidget {
  const _TimingRow({required this.label, required this.value});

  final String label;
  final dynamic value;

  @override
  Widget build(BuildContext context) {
    final display = value == null ? 'N/A' : '${value.toString()} s';
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          Text(display, style: const TextStyle(fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}
