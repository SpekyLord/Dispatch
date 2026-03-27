import 'package:dispatch_mobile/core/state/session_controller.dart';
import 'package:dispatch_mobile/features/shared/presentation/role_shell_scaffold.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class CitizenHomeScreen extends ConsumerWidget {
  const CitizenHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return RoleShellScaffold(
      kicker: 'Citizen shell',
      title: 'Citizen foundation',
      onSignOut: () => ref.read(sessionControllerProvider.notifier).signOut(),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Phase 1 will add report creation, photo uploads, and personal report history here.',
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          const SizedBox(height: 20),
          Container(
            height: 220,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              gradient: const LinearGradient(
                colors: [Color(0xFFFFE3D5), Color(0xFFE5F6FC)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            padding: const EdgeInsets.all(20),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Text(
                  'Map wrapper placeholder',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
                SizedBox(height: 8),
                Text(
                  'Phase 0 keeps a dedicated location shell here while Windows Developer Mode is unavailable for plugin-backed mobile packages.',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
