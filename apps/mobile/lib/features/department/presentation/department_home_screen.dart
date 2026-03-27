import 'package:dispatch_mobile/core/state/session_controller.dart';
import 'package:dispatch_mobile/features/shared/presentation/role_shell_scaffold.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class DepartmentHomeScreen extends ConsumerWidget {
  const DepartmentHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return RoleShellScaffold(
      kicker: 'Department shell',
      title: 'Responder foundation',
      onSignOut: () => ref.read(sessionControllerProvider.notifier).signOut(),
      body: const _PlaceholderList(
        items: [
          'Incident board and live response actions arrive in Phase 2.',
          'Operational profile management and announcements attach here later.',
          'This route is intentionally mobile-ready because Phase 4 depends on it.',
        ],
      ),
    );
  }
}

class _PlaceholderList extends StatelessWidget {
  const _PlaceholderList({required this.items});

  final List<String> items;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: items
          .map(
            (item) => Card(
              margin: const EdgeInsets.only(bottom: 12),
              child: ListTile(title: Text(item)),
            ),
          )
          .toList(),
    );
  }
}
