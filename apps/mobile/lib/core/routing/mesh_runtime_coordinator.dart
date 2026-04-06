import 'dart:async';

import 'package:dispatch_mobile/core/state/mesh_providers.dart';
import 'package:dispatch_mobile/core/state/session.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class MeshRuntimeCoordinator extends ConsumerStatefulWidget {
  const MeshRuntimeCoordinator({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<MeshRuntimeCoordinator> createState() =>
      _MeshRuntimeCoordinatorState();
}

class _MeshRuntimeCoordinatorState
    extends ConsumerState<MeshRuntimeCoordinator>
    with WidgetsBindingObserver {
  Timer? _heartbeat;
  bool _probingConnectivity = false;
  bool _syncInFlight = false;
  String? _lastSessionSignature;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_bootstrap(forceHydrate: true));
    });
    _heartbeat = Timer.periodic(const Duration(seconds: 10), (_) {
      unawaited(_heartbeatTick());
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _heartbeat?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_bootstrap(forceHydrate: true));
    }
  }

  Future<void> _bootstrap({bool forceHydrate = false}) async {
    final transport = ref.read(meshTransportProvider);
    final session = ref.read(sessionControllerProvider);

    await transport.initialize();
    _updateOperatorProfile(session);

    try {
      if (!transport.isDiscovering) {
        await transport.startDiscovery();
      }
    } catch (_) {
      // Discovery should keep retrying internally; runtime bootstrap is best effort.
    }

    await _refreshConnectivity();
    await _syncWhenOnline(forceHydrate: forceHydrate);
  }

  Future<void> _heartbeatTick() async {
    if (!mounted) {
      return;
    }
    final transport = ref.read(meshTransportProvider);
    transport.pruneStalePeers();
    _updateOperatorProfile(ref.read(sessionControllerProvider));

    // If discovery died but we should be discovering, restart it
    if (!transport.isDiscovering) {
      try {
        await transport.startDiscovery();
      } catch (_) {}
    }

    await _refreshConnectivity();
    await _syncWhenOnline();
  }

  void _updateOperatorProfile(SessionState session) {
    ref
        .read(meshTransportProvider)
        .updateOperatorProfile(
          displayName:
              session.fullName ?? session.department?.name ?? session.email,
          operatorRole: session.role?.name,
          departmentId: session.department?.id,
          departmentName: session.department?.name,
        );
  }

  Future<void> _refreshConnectivity() async {
    if (_probingConnectivity) {
      return;
    }

    _probingConnectivity = true;
    final auth = ref.read(authServiceProvider);
    final transport = ref.read(meshTransportProvider);

    try {
      final isOnline = await auth.checkHealth();
      transport.setConnectivity(isOnline);
    } catch (_) {
      transport.setConnectivity(false);
    } finally {
      _probingConnectivity = false;
    }
  }

  Future<void> _syncWhenOnline({bool forceHydrate = false}) async {
    if (_syncInFlight) {
      return;
    }

    final session = ref.read(sessionControllerProvider);
    final transport = ref.read(meshTransportProvider);
    if (session.accessToken == null || transport.isMeshOnlyState) {
      return;
    }

    _syncInFlight = true;
    try {
      if (transport.hasPendingServerSync || forceHydrate) {
        await ref
            .read(meshGatewaySyncServiceProvider)
            .sync(
              operatorRole: session.role?.name,
              departmentId: session.department?.id,
              departmentName: session.department?.name,
              displayName:
                  session.fullName ?? session.department?.name ?? session.email,
            );
      }

      final auth = ref.read(authServiceProvider);
      final history = await auth.getMeshMessages(includePosts: true);
      transport.ingestServerMessages(
        (history['messages'] as List<dynamic>? ?? const [])
            .whereType<Map>()
            .map((row) => Map<String, dynamic>.from(row))
            .toList(growable: false),
      );
      transport.ingestServerMeshPosts(
        (history['mesh_posts'] as List<dynamic>? ?? const [])
            .whereType<Map>()
            .map((row) => Map<String, dynamic>.from(row))
            .toList(growable: false),
      );

      final lastSeen = await auth.getMeshLastSeen();
      transport.ingestServerLastSeen(
        (lastSeen['devices'] as List<dynamic>? ?? const [])
            .whereType<Map>()
            .map((row) => Map<String, dynamic>.from(row))
            .toList(growable: false),
      );
    } catch (_) {
      // The coordinator retries on the next heartbeat or realtime update.
    } finally {
      _syncInFlight = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionControllerProvider);
    final nextSignature = [
      session.userId,
      session.accessToken,
      session.role?.name,
      session.fullName,
      session.department?.id,
      session.department?.name,
    ].join('|');

    if (_lastSessionSignature != nextSignature) {
      _lastSessionSignature = nextSignature;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        unawaited(_bootstrap(forceHydrate: true));
      });
    }

    return widget.child;
  }
}
