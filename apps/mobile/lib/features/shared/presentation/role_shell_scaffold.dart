import 'package:flutter/material.dart';

class RoleShellScaffold extends StatelessWidget {
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
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          TextButton(
            onPressed: onSignOut,
            child: const Text('Sign out'),
          ),
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
