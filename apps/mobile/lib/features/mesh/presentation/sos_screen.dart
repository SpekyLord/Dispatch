// SOS distress screen — one-tap emergency signal, no login required.
// Broadcasts DISTRESS packets with maxHops=15 via mesh relay.

import 'package:dispatch_mobile/core/services/mesh_transport_service.dart';
import 'package:flutter/material.dart';

class SosScreen extends StatefulWidget {
  const SosScreen({super.key});

  @override
  State<SosScreen> createState() => _SosScreenState();
}

class _SosScreenState extends State<SosScreen> {
  final _nameCtrl = TextEditingController();
  final _contactCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  bool _sent = false;
  bool _sending = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _contactCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  void _sendDistress() {
    setState(() => _sending = true);

    // create distress packet via mesh transport
    final packet = MeshTransportService.createDistressPacket(
      deviceId: 'local-device', // would use real device ID
      description: _descCtrl.text.trim(),
      reporterName: _nameCtrl.text.trim(),
      contactInfo: _contactCtrl.text.trim(),
    );

    // enqueue for mesh broadcast
    final transport = MeshTransportService();
    transport.enqueuePacket(packet);

    setState(() {
      _sent = true;
      _sending = false;
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
              'Your SOS signal is being relayed through nearby devices. '
              'Help is on the way.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.cyan.shade50,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                'Max relay: 15 hops',
                style: TextStyle(
                  color: Colors.cyan.shade800,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
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
        // emergency header
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
                'No login required. Your distress signal will be relayed '
                'through nearby devices via mesh networking.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.red.shade700, fontSize: 13),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),

        // optional info fields
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

        // big SOS button
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
