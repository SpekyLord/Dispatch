import 'package:dispatch_mobile/core/permissions/mesh_permission_gate.dart';
import 'package:dispatch_mobile/core/routing/mesh_runtime_coordinator.dart';
import 'package:dispatch_mobile/core/state/session.dart';
import 'package:dispatch_mobile/features/auth/presentation/auth_gate_screen.dart';
import 'package:dispatch_mobile/features/citizen/presentation/citizen_home_screen.dart';
import 'package:dispatch_mobile/features/department/presentation/department_home_screen.dart';
import 'package:dispatch_mobile/features/municipality/presentation/municipality_home_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class AppRoot extends ConsumerWidget {
  const AppRoot({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionControllerProvider);

    if (!session.isAuthenticated || session.role == null) {
      return const AuthGateScreen();
    }

    final home = switch (session.role!) {
      AppRole.citizen => const CitizenHomeScreen(),
      AppRole.department => const DepartmentHomeScreen(),
      AppRole.municipality => const MunicipalityHomeScreen(),
    };

    return MeshPermissionGate(
      child: MeshRuntimeCoordinator(child: home),
    );
  }
}
