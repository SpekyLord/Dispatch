// Municipality home — placeholder shell. Verification is web-only in Phase 1.

import 'package:dispatch_mobile/core/state/session_controller.dart';
import 'package:dispatch_mobile/features/shared/presentation/role_shell_scaffold.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class MunicipalityHomeScreen extends ConsumerWidget {
  const MunicipalityHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return RoleShellScaffold(
      kicker: 'Municipality shell',
      title: 'Oversight foundation',
      onSignOut: () => ref.read(sessionControllerProvider.notifier).signOut(),
      body: const _PlaceholderList(
        items: [
          'Department verification remains web-first in Phase 1.',
          'Lightweight municipality placeholders can still live here on mobile.',
          'Analytics and assessments become meaningful in later phases.',
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
