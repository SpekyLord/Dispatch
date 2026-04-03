import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

class MeshPermissionGate extends StatefulWidget {
  const MeshPermissionGate({required this.child, super.key});

  final Widget child;

  @override
  State<MeshPermissionGate> createState() => _MeshPermissionGateState();
}

class _MeshPermissionGateState extends State<MeshPermissionGate>
    with WidgetsBindingObserver {
  bool _allGranted = false;
  bool _checking = true;
  bool _requesting = false;
  bool _requiresSettings = false;
  bool _pluginUnavailable = false;
  List<_PermissionRequirement> _missing = const [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refreshPermissions(promptIfMissing: true);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshPermissions(promptIfMissing: true);
    }
  }

  Future<void> _refreshPermissions({required bool promptIfMissing}) async {
    if (_requesting) {
      return;
    }
    if (!_supportsRuntimePermissionFlow || _pluginUnavailable) {
      if (!mounted) {
        return;
      }
      setState(() {
        _allGranted = true;
        _checking = false;
      });
      return;
    }

    _requesting = true;
    try {
      var snapshot = await _collectSnapshot();
      if (snapshot.pluginUnavailable) {
        if (!mounted) {
          return;
        }
        setState(() {
          _pluginUnavailable = true;
          _allGranted = true;
          _checking = false;
        });
        return;
      }
      if (promptIfMissing && snapshot.missing.isNotEmpty) {
        await _requestMissingPermissions(snapshot.missing);
        snapshot = await _collectSnapshot();
        if (snapshot.pluginUnavailable) {
          if (!mounted) {
            return;
          }
          setState(() {
            _pluginUnavailable = true;
            _allGranted = true;
            _checking = false;
          });
          return;
        }
      }

      if (!mounted) {
        return;
      }
      setState(() {
        _allGranted = snapshot.missing.isEmpty;
        _missing = snapshot.missing;
        _requiresSettings = snapshot.requiresSettings;
        _checking = false;
      });
    } finally {
      _requesting = false;
    }
  }

  Future<_PermissionSnapshot> _collectSnapshot() async {
    final missing = <_PermissionRequirement>[];
    var requiresSettings = false;
    try {
      for (final requirement in _requiredPermissions) {
        final status = await requirement.permission.status;
        final isGranted = status.isGranted || status.isLimited;
        if (isGranted) {
          continue;
        }
        missing.add(requirement);
        if (status.isPermanentlyDenied || status.isRestricted) {
          requiresSettings = true;
        }
      }
    } on MissingPluginException {
      return const _PermissionSnapshot(
        missing: [],
        requiresSettings: false,
        pluginUnavailable: true,
      );
    }
    return _PermissionSnapshot(
      missing: missing,
      requiresSettings: requiresSettings,
      pluginUnavailable: false,
    );
  }

  Future<void> _requestMissingPermissions(
    List<_PermissionRequirement> missing,
  ) async {
    if (missing.isEmpty) {
      return;
    }
    final uniquePermissions = missing
        .map((requirement) => requirement.permission)
        .toSet()
        .toList(growable: false);
    try {
      await uniquePermissions.request();
    } on MissingPluginException {
      // Handled by subsequent _collectSnapshot fallback.
    }
  }

  Future<void> _openSettings() async {
    try {
      await openAppSettings();
    } on MissingPluginException {
      // No-op when plugin wiring is unavailable.
    }
  }

  List<_PermissionRequirement> get _requiredPermissions {
    if (kIsWeb) {
      return const [];
    }
    if (Platform.isAndroid) {
      return const [
        _PermissionRequirement(
          permission: Permission.locationWhenInUse,
          label: 'Location (GPS)',
        ),
        _PermissionRequirement(
          permission: Permission.microphone,
          label: 'Microphone',
        ),
        _PermissionRequirement(
          permission: Permission.bluetoothScan,
          label: 'Bluetooth Scan',
        ),
        _PermissionRequirement(
          permission: Permission.bluetoothConnect,
          label: 'Bluetooth Connect',
        ),
        _PermissionRequirement(
          permission: Permission.bluetoothAdvertise,
          label: 'Bluetooth Advertise',
        ),
        _PermissionRequirement(
          permission: Permission.nearbyWifiDevices,
          label: 'Nearby Wi-Fi Devices',
        ),
      ];
    }
    if (Platform.isIOS) {
      return const [
        _PermissionRequirement(
          permission: Permission.locationWhenInUse,
          label: 'Location (GPS)',
        ),
        _PermissionRequirement(
          permission: Permission.microphone,
          label: 'Microphone',
        ),
      ];
    }
    return const [];
  }

  bool get _supportsRuntimePermissionFlow {
    if (kIsWeb) {
      return false;
    }
    return Platform.isAndroid || Platform.isIOS;
  }

  @override
  Widget build(BuildContext context) {
    if (_allGranted) {
      return widget.child;
    }

    if (_checking) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Permissions Required',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 12),
              const Text(
                'Dispatch needs these permissions to keep mesh topology, GPS map centering, BLE relay, and SAR sensing working on your phone.',
              ),
              const SizedBox(height: 12),
              const Text(
                'Wi-Fi probe scanning remains unavailable on standard mobile app sandboxing, even with all permissions granted.',
              ),
              const SizedBox(height: 16),
              Expanded(
                child: ListView(
                  children: [
                    for (final requirement in _missing)
                      ListTile(
                        leading: const Icon(Icons.lock_outline),
                        title: Text(requirement.label),
                      ),
                  ],
                ),
              ),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _requesting
                      ? null
                      : () => _refreshPermissions(promptIfMissing: true),
                  child: Text(
                    _requesting
                        ? 'Requesting permissions...'
                        : 'Grant Required Permissions',
                  ),
                ),
              ),
              const SizedBox(height: 10),
              if (_requiresSettings)
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: _openSettings,
                    child: const Text('Open App Settings'),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PermissionRequirement {
  const _PermissionRequirement({required this.permission, required this.label});

  final Permission permission;
  final String label;
}

class _PermissionSnapshot {
  const _PermissionSnapshot({
    required this.missing,
    required this.requiresSettings,
    required this.pluginUnavailable,
  });

  final List<_PermissionRequirement> missing;
  final bool requiresSettings;
  final bool pluginUnavailable;
}
