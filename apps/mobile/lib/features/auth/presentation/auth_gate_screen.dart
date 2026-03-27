import 'package:dispatch_mobile/core/state/session_controller.dart';
import 'package:dispatch_mobile/core/state/session_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class AuthGateScreen extends ConsumerWidget {
  const AuthGateScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(sessionControllerProvider.notifier);

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'Dispatch mobile foundation',
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: const Color(0xFFE05A2B),
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.3,
                    ),
              ),
              const SizedBox(height: 12),
              Text(
                'Role-aware navigation is wired before the real auth flows arrive.',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 16),
              Text(
                'These buttons simulate Phase 1 authentication so we can verify the citizen, department, and municipality shells now.',
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: Colors.black54,
                    ),
              ),
              const SizedBox(height: 32),
              for (final role in AppRole.values) ...[
                FilledButton(
                  onPressed: () => controller.signInAs(role),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(56),
                    alignment: Alignment.centerLeft,
                  ),
                  child: Text('Continue as ${role.name}'),
                ),
                const SizedBox(height: 12),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
