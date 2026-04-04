// Profile screen -- edit full name and phone number.

import 'package:dispatch_mobile/core/state/session.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class CitizenProfileScreen extends ConsumerStatefulWidget {
  const CitizenProfileScreen({super.key});

  @override
  ConsumerState<CitizenProfileScreen> createState() =>
      _CitizenProfileScreenState();
}

const _recentReports = <_ReportSummary>[
  _ReportSummary('Flooded intersection', 'Responding'),
  _ReportSummary('Downed power lines', 'Accepted'),
  _ReportSummary('Medical assistance needed', 'Pending'),
  _ReportSummary('Road debris cleared', 'Resolved'),
];

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
      ref
          .read(sessionControllerProvider.notifier)
          .updateFullName(_nameController.text.trim());
      if (mounted) {
        setState(() {
          _loading = false;
          _success = true;
        });
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
    final session = ref.watch(sessionControllerProvider);
    final name = session.fullName ?? 'Citizen Responder';
    final initials = name.isNotEmpty ? name.substring(0, 1).toUpperCase() : 'C';

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 120),
      children: [
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFFA14B2F), Color(0xFF7B3A25)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(20),
            boxShadow: const [
              BoxShadow(
                color: Color(0x26131110),
                blurRadius: 18,
                offset: Offset(0, 10),
              ),
            ],
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 30,
                backgroundColor: Colors.white.withValues(alpha: 0.2),
                child: Text(
                  initials,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      session.email ?? 'Verified citizen account',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.8),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: const [
                        Chip(
                          label: Text('Verified Citizen'),
                          avatar: Icon(Icons.verified, color: Colors.white),
                          backgroundColor: Color(0x33FFFFFF),
                          labelStyle: TextStyle(color: Colors.white),
                        ),
                        Chip(
                          label: Text('Responder Ready'),
                          avatar: Icon(Icons.health_and_safety, color: Colors.white),
                          backgroundColor: Color(0x33FFFFFF),
                          labelStyle: TextStyle(color: Colors.white),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: const [
            _StatTile(label: 'Reports', value: '4'),
            SizedBox(width: 12),
            _StatTile(label: 'Resolved', value: '1'),
            SizedBox(width: 12),
            _StatTile(label: 'Follow-ups', value: '2'),
          ],
        ),
        const SizedBox(height: 20),
        _SectionTitle(title: 'Account details'),
        const SizedBox(height: 8),
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
        if (_success)
          Container(
            padding: const EdgeInsets.all(12),
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: Colors.green.shade50,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              'Profile updated.',
              style: TextStyle(color: Colors.green.shade700),
            ),
          ),
        TextField(
          controller: _nameController,
          decoration: const InputDecoration(
            labelText: 'Full name',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _phoneController,
          decoration: const InputDecoration(
            labelText: 'Phone number',
            border: OutlineInputBorder(),
          ),
          keyboardType: TextInputType.phone,
        ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: _loading ? null : _save,
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(48),
          ),
          child: Text(_loading ? 'Saving...' : 'Save Changes'),
        ),
        const SizedBox(height: 20),
        _SectionTitle(title: 'Recent reports'),
        const SizedBox(height: 8),
        for (final report in _recentReports)
          _ReportRow(title: report.title, status: report.status),
      ],
    );
  }
}

class _ReportSummary {
  const _ReportSummary(this.title, this.status);

  final String title;
  final String status;
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF8F3),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFE7D1C6)),
        ),
        child: Column(
          children: [
            Text(
              value,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text(label, style: const TextStyle(color: Colors.black54)),
          ],
        ),
      ),
    );
  }
}

class _ReportRow extends StatelessWidget {
  const _ReportRow({required this.title, required this.status});

  final String title;
  final String status;

  Color _statusColor(String status) {
    return switch (status.toLowerCase()) {
      'pending' => const Color(0xFFD97757),
      'accepted' => const Color(0xFF1695D3),
      'responding' => const Color(0xFF7B5E57),
      'resolved' => const Color(0xFF397154),
      _ => Colors.grey,
    };
  }

  @override
  Widget build(BuildContext context) {
    final accent = _statusColor(status);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF8F3),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE7D1C6)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              status,
              style: TextStyle(
                color: accent,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
