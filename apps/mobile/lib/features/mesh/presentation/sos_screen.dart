// SOS distress screen - one-tap emergency signal, no login required.
// Broadcasts DISTRESS packets with maxHops=15 via mesh relay.

import 'package:dispatch_mobile/core/services/mesh_transport_service.dart';
import 'package:dispatch_mobile/core/state/mesh_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class SosScreen extends ConsumerStatefulWidget {
  const SosScreen({super.key});

  @override
  ConsumerState<SosScreen> createState() => _SosScreenState();
}

class _SosScreenState extends ConsumerState<SosScreen> {
  final _nameCtrl = TextEditingController();
  final _contactCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  bool _sent = false;
  bool _sending = false;
  bool _beaconBroadcastActive = false;
  String? _beaconStatusNote;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _contactCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _sendDistress() async {
    setState(() => _sending = true);
    final transport = ref.read(meshTransportProvider);
    final sarPlatform = ref.read(sarPlatformServiceProvider);

    final packet = MeshTransportService.createDistressPacket(
      deviceId: transport.localDeviceId,
      description: _descCtrl.text.trim(),
      reporterName: _nameCtrl.text.trim(),
      contactInfo: _contactCtrl.text.trim(),
    );

    transport.enqueuePacket(packet);

    final capabilities = await sarPlatform.getCapabilities();
    var beaconActive = false;
    var beaconStatusNote = capabilities.sosBeaconNote;
    if (capabilities.sosBeaconSupported) {
      beaconActive = await sarPlatform.startSosBeaconBroadcast(
        deviceId: transport.localDeviceId,
      );
    }

    if (beaconActive) {
      transport.startSosBeaconBroadcast(deviceId: 'local-device');
    } else {
      transport.stopSosBeaconBroadcast();
    }

    await ref.read(sarModeControllerProvider.notifier).refreshSubsystemStatus();

    if (!mounted) {
      return;
    }

    setState(() {
      _sent = true;
      _sending = false;
      _beaconBroadcastActive = beaconActive;
      _beaconStatusNote = beaconActive
          ? 'Nearby SAR devices can now pick up this phone through the standardized SOS BLE beacon.'
          : beaconStatusNote ??
                'SOS beacon broadcasting is unavailable on this device right now, but your distress packet is still relayed across the mesh.';
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Emergency SOS'),
        backgroundColor: Colors.red.shade700,
        foregroundColor: Colors.white,
      ),
      body: _sent ? _buildConfirmation(theme) : _buildForm(theme),
    );
  }

  Widget _buildConfirmation(ThemeData theme) {
    final chipText = _beaconBroadcastActive
        ? 'Max relay: 15 hops | SOS beacon active'
        : 'Max relay: 15 hops | SOS beacon unavailable';
    final chipColor = _beaconBroadcastActive
        ? Colors.cyan.shade50
        : Colors.orange.shade50;
    final chipTextColor = _beaconBroadcastActive
        ? Colors.cyan.shade800
        : Colors.orange.shade900;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: Colors.green.shade100,
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.check, size: 48, color: Colors.green.shade700),
            ),
            const SizedBox(height: 24),
            Text(
              'Distress Signal Sent',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Your SOS signal is being relayed through nearby devices. Help is on the way.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: chipColor,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                chipText,
                style: TextStyle(
                  color: chipTextColor,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if ((_beaconStatusNote ?? '').isNotEmpty) ...[
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(
                  _beaconStatusNote!,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.grey.shade700,
                    fontSize: 13,
                    height: 1.45,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 32),
            OutlinedButton(
              onPressed: () => setState(() => _sent = false),
              child: const Text('Send Another'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildForm(ThemeData theme) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.red.shade50,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.red.shade200),
          ),
          child: Column(
            children: [
              Icon(Icons.sos, size: 48, color: Colors.red.shade700),
              const SizedBox(height: 12),
              Text(
                'Send Emergency SOS',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: Colors.red.shade800,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'No login required. Your distress signal will be relayed through nearby devices via mesh networking.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.red.shade700, fontSize: 13),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        TextField(
          controller: _nameCtrl,
          decoration: const InputDecoration(
            labelText: 'Your name (optional)',
            prefixIcon: Icon(Icons.person_outline),
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _contactCtrl,
          decoration: const InputDecoration(
            labelText: 'Contact number (optional)',
            prefixIcon: Icon(Icons.phone_outlined),
            border: OutlineInputBorder(),
          ),
          keyboardType: TextInputType.phone,
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _descCtrl,
          decoration: const InputDecoration(
            labelText: 'Describe your emergency',
            prefixIcon: Icon(Icons.description_outlined),
            border: OutlineInputBorder(),
            alignLabelWithHint: true,
          ),
          maxLines: 3,
        ),
        const SizedBox(height: 32),
        SizedBox(
          height: 56,
          child: FilledButton(
            onPressed: _sending ? null : _sendDistress,
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red.shade700,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            child: _sending
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2,
                    ),
                  )
                : const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.sos, size: 24),
                      SizedBox(width: 8),
                      Text(
                        'SEND SOS SIGNAL',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.5,
                        ),
                      ),
                    ],
                  ),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'Signal will be broadcast with 15-hop relay range',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
        ),
      ],
    );
  }
}
