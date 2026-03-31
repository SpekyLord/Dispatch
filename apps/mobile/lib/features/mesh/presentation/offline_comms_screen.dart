import 'dart:async';
import 'dart:convert';

import 'package:dispatch_mobile/core/services/mesh_transport_service.dart';
import 'package:dispatch_mobile/core/state/mesh_providers.dart';
import 'package:dispatch_mobile/core/state/session.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const _warmBackground = Color(0xFFFDF7F2);
const _warmPanel = Color(0xFFFFF8F3);
const _warmBorder = Color(0xFFE7D1C6);
const _warmAccent = Color(0xFFA14B2F);
const _coolAccent = Color(0xFF1695D3);
const _deepText = Color(0xFF4E433D);
const _mutedText = Color(0xFF7A6B63);

class OfflineCommsScreen extends ConsumerStatefulWidget {
  const OfflineCommsScreen({super.key});

  @override
  ConsumerState<OfflineCommsScreen> createState() => _OfflineCommsScreenState();
}

class _OfflineCommsScreenState extends ConsumerState<OfflineCommsScreen> {
  final _messageCtrl = TextEditingController();
  final _titleCtrl = TextEditingController();
  final _postBodyCtrl = TextEditingController();
  String _mode = 'broadcast';
  String _postCategory = 'update';
  bool _sending = false;
  bool _syncing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final transport = ref.read(meshTransportProvider);
    transport.markAllCommsRead();
    unawaited(_hydrateServerHistory());
  }

  @override
  void dispose() {
    _messageCtrl.dispose();
    _titleCtrl.dispose();
    _postBodyCtrl.dispose();
    super.dispose();
  }

  Future<void> _hydrateServerHistory() async {
    final session = ref.read(sessionControllerProvider);
    if (session.accessToken == null) {
      return;
    }
    try {
      final response = await ref
          .read(authServiceProvider)
          .getMeshMessages(includePosts: true);
      ref
          .read(meshTransportProvider)
          .ingestServerMessages((response['messages'] as List?)?.cast<Map<String, dynamic>>() ?? const []);
      ref
          .read(meshTransportProvider)
          .ingestServerMeshPosts((response['mesh_posts'] as List?)?.cast<Map<String, dynamic>>() ?? const []);
      if (mounted) {
        setState(() {});
      }
    } catch (_) {}
  }

  Future<void> _syncPendingPackets() async {
    final session = ref.read(sessionControllerProvider);
    if (session.accessToken == null) {
      return;
    }
    final transport = ref.read(meshTransportProvider);
    final queued = transport.drainQueue();
    if (queued.isEmpty) {
      return;
    }
    setState(() => _syncing = true);
    try {
      final response = await ref.read(authServiceProvider).ingestMeshPackets(
        queued.map((packet) => packet.toJson()).toList(),
      );
      transport.processSyncAcks(
        (response['acks'] as List?)?.cast<Map<String, dynamic>>() ?? const [],
      );
      await _hydrateServerHistory();
    } catch (e) {
      if (mounted) {
        setState(() => _error = e.toString());
      }
    } finally {
      if (mounted) {
        setState(() => _syncing = false);
      }
    }
  }

  bool _offlineTokenExpired(String token) {
    try {
      final segments = token.split('.');
      if (segments.length != 3) {
        return true;
      }
      final payload = jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(segments[1]))),
      ) as Map<String, dynamic>;
      final exp = payload['exp'];
      if (exp is! int) {
        return true;
      }
      return DateTime.now().toUtc().millisecondsSinceEpoch >= exp * 1000;
    } catch (_) {
      return true;
    }
  }

  Future<void> _submit() async {
    final session = ref.read(sessionControllerProvider);
    final transport = ref.read(meshTransportProvider);
    final displayName = session.fullName ?? session.department?.name ?? session.email ?? 'Mesh user';
    final offlineToken = session.offlineVerificationToken;
    final authenticatedRole = session.role?.name;
    setState(() {
      _sending = true;
      _error = null;
    });

    try {
      if (_mode == 'post') {
        if (session.role != AppRole.department || session.department == null) {
          throw Exception('Only verified departments can publish mesh posts.');
        }
        if (offlineToken == null || offlineToken.isEmpty || _offlineTokenExpired(offlineToken)) {
          throw Exception('Offline department token is missing or expired.');
        }
        final packet = MeshTransportService.createMeshPostPacket(
          deviceId: transport.localDeviceId,
          postId: MeshTransportService.generateUuid(),
          category: _postCategory,
          title: _titleCtrl.text.trim(),
          body: _postBodyCtrl.text.trim(),
          authorDepartmentId: session.department!.id,
          authorOfflineToken: offlineToken,
        );
        transport.enqueuePacket(packet);
        _titleCtrl.clear();
        _postBodyCtrl.clear();
      } else {
        final body = _messageCtrl.text.trim();
        if (body.isEmpty) {
          throw Exception('Message body is required.');
        }
        if (authenticatedRole != null &&
            (offlineToken == null || offlineToken.isEmpty || _offlineTokenExpired(offlineToken))) {
          throw Exception('Offline account token is missing or expired. Sign in again before sending mesh messages.');
        }
        final packet = MeshTransportService.createMeshMessagePacket(
          deviceId: transport.localDeviceId,
          threadId: _mode == 'department' && session.department != null
              ? MeshTransportService.departmentThreadId(session.department!.id)
              : MeshTransportService.broadcastThreadId(),
          recipientScope: _mode == 'department' ? 'department' : 'broadcast',
          recipientIdentifier: _mode == 'department' ? session.department?.id : null,
          body: body,
          authorDisplayName: displayName,
          authorRole: authenticatedRole ?? 'anonymous',
          authorOfflineToken: offlineToken,
        );
        transport.enqueuePacket(packet);
        _messageCtrl.clear();
      }
      if (mounted) {
        setState(() {});
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = e.toString());
      }
    } finally {
      if (mounted) {
        setState(() => _sending = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionControllerProvider);
    final transport = ref.watch(meshTransportProvider);
    final items = transport.inboxItems;
    final canDepartmentMessage =
        session.role == AppRole.department && session.department != null;

    return Scaffold(
      backgroundColor: _warmBackground,
      appBar: AppBar(
        title: const Text('Offline Comms'),
        backgroundColor: _warmBackground,
        surfaceTintColor: Colors.transparent,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Stack(
              alignment: Alignment.center,
              children: [
                IconButton(
                  onPressed: _syncing ? null : () => unawaited(_syncPendingPackets()),
                  icon: const Icon(Icons.sync),
                  tooltip: 'Sync queued packets',
                ),
                if (transport.unreadMeshMessageCount > 0)
                  Positioned(
                    top: 10,
                    right: 8,
                    child: _Badge(count: transport.unreadMeshMessageCount),
                  ),
              ],
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFA14B2F), Color(0xFF7B3A25), Color(0xFF425E72)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(28),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: const Text(
                    'Mesh-Routed Communications',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.1,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Broadcast updates, department chatter, and mesh-authored advisories keep moving even when the network does not.',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.w700,
                    height: 1.15,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  transport.isMeshOnlyState
                      ? 'Mesh-only mode is active, so new messages stay queued for gateway sync while still appearing in the local inbox.'
                      : 'Internet is available, so queued mesh packets can be flushed to the backend while the local inbox keeps the same offline-first view.',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.86), height: 1.45),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: _warmPanel,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: _warmBorder),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Compose',
                  style: TextStyle(color: _deepText, fontSize: 20, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _ModeChip(label: 'Broadcast', active: _mode == 'broadcast', onTap: () => setState(() => _mode = 'broadcast')),
                    if (canDepartmentMessage)
                      _ModeChip(label: 'Department', active: _mode == 'department', onTap: () => setState(() => _mode = 'department')),
                    if (canDepartmentMessage)
                      _ModeChip(label: 'Mesh Post', active: _mode == 'post', onTap: () => setState(() => _mode = 'post')),
                  ],
                ),
                const SizedBox(height: 14),
                if (_mode == 'post') ...[
                  TextField(controller: _titleCtrl, decoration: const InputDecoration(labelText: 'Title', border: OutlineInputBorder())),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: _postCategory,
                    decoration: const InputDecoration(labelText: 'Category', border: OutlineInputBorder()),
                    items: const [
                      DropdownMenuItem(value: 'alert', child: Text('Alert')),
                      DropdownMenuItem(value: 'warning', child: Text('Warning')),
                      DropdownMenuItem(value: 'safety_tip', child: Text('Safety Tip')),
                      DropdownMenuItem(value: 'update', child: Text('Update')),
                      DropdownMenuItem(value: 'situational_report', child: Text('Situational Report')),
                    ],
                    onChanged: (value) => setState(() => _postCategory = value ?? 'update'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _postBodyCtrl,
                    maxLength: 1000,
                    maxLines: 5,
                    decoration: const InputDecoration(labelText: 'Body', border: OutlineInputBorder()),
                  ),
                ] else
                  TextField(
                    controller: _messageCtrl,
                    maxLength: 500,
                    maxLines: 4,
                    decoration: InputDecoration(
                      labelText: _mode == 'department' ? 'Department message' : 'Broadcast message',
                      border: const OutlineInputBorder(),
                    ),
                  ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!, style: const TextStyle(color: Colors.redAccent)),
                ],
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: _sending ? null : _submit,
                  style: FilledButton.styleFrom(backgroundColor: _warmAccent, foregroundColor: Colors.white),
                  icon: Icon(_mode == 'post' ? Icons.campaign : Icons.send),
                  label: Text(_sending ? 'Queueing...' : _mode == 'post' ? 'Publish over mesh' : 'Send over mesh'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          ...items.map((item) => _InboxCard(item: item)),
          if (items.isEmpty)
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: _warmPanel,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: _warmBorder),
              ),
              child: const Text(
                'No mesh-routed messages or posts yet. Compose a broadcast above or wait for nearby mesh traffic to arrive.',
                style: TextStyle(color: _mutedText, height: 1.45),
              ),
            ),
        ],
      ),
    );
  }
}

class _ModeChip extends StatelessWidget {
  const _ModeChip({required this.label, required this.active, required this.onTap});
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: active ? _warmAccent : const Color(0xFFF7EADF),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(label, style: TextStyle(color: active ? Colors.white : _deepText, fontWeight: FontWeight.w700)),
      ),
    );
  }
}

class _InboxCard extends StatelessWidget {
  const _InboxCard({required this.item});
  final MeshInboxItem item;

  @override
  Widget build(BuildContext context) {
    final accent = item.itemType == 'mesh_post' ? _warmAccent : _coolAccent;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: item.isRead ? _warmPanel : Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: item.isRead ? _warmBorder : accent.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  item.title ?? item.authorDisplayName,
                  style: const TextStyle(color: _deepText, fontSize: 18, fontWeight: FontWeight.w700),
                ),
              ),
              _Badge(label: item.itemType == 'mesh_post' ? 'Post' : item.recipientScope),
            ],
          ),
          const SizedBox(height: 8),
          Text(item.body, style: const TextStyle(color: _deepText, height: 1.45)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _MetaChip(label: item.authorRole),
              if (item.category != null) _MetaChip(label: item.category!.replaceAll('_', ' ')),
              _MetaChip(label: '${item.hopCount}/${item.maxHops} hops'),
              _MetaChip(label: item.needsServerSync ? 'Queued for sync' : 'Server synced'),
            ],
          ),
        ],
      ),
    );
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFF7EADF),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(label, style: const TextStyle(color: _mutedText, fontSize: 12, fontWeight: FontWeight.w600)),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({this.count, this.label});
  final int? count;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final text = label ?? '${count ?? 0}';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: _warmAccent,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(text, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
    );
  }
}


