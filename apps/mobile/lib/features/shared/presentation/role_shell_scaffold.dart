import 'package:dispatch_mobile/core/i18n/app_strings.dart';
import 'package:dispatch_mobile/core/i18n/locale_action_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class RoleShellScaffold extends ConsumerWidget {
  const RoleShellScaffold({
    required this.body,
    required this.kicker,
    required this.title,
    required this.onSignOut,
    super.key,
  });

  final Widget body;
  final String kicker;
  final String title;
  final VoidCallback onSignOut;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = ref.watch(appStringsProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          const LocaleActionButton(),
          TextButton(onPressed: onSignOut, child: Text(strings.signOut)),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text(
              kicker,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: const Color(0xFFE05A2B),
                fontWeight: FontWeight.w700,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 12),
            body,
          ],
        ),
      ),
    );
  }
}
