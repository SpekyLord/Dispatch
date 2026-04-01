// Municipality home â€” placeholder shell. Verification is web-only in Phase 1.

import 'package:dispatch_mobile/core/i18n/app_strings.dart';
import 'package:dispatch_mobile/core/state/session.dart';
import 'package:dispatch_mobile/features/shared/presentation/role_shell_scaffold.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class MunicipalityHomeScreen extends ConsumerWidget {
  const MunicipalityHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = ref.watch(appStringsProvider);

    return RoleShellScaffold(
      kicker: strings.municipalityKicker,
      title: strings.municipalityTitle,
      onSignOut: () => ref.read(sessionControllerProvider.notifier).signOut(),
      body: _PlaceholderList(
        items: [
          strings.municipalityPlaceholderVerification,
          strings.municipalityPlaceholderMobile,
          strings.municipalityPlaceholderPhase3,
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
