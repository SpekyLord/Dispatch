import 'dart:async';
import 'dart:convert';

import 'package:dispatch_mobile/core/services/mesh_transport_service.dart';
import 'package:dispatch_mobile/core/services/realtime_service.dart';
import 'package:dispatch_mobile/core/state/mesh_providers.dart';
import 'package:dispatch_mobile/core/state/session.dart';
import 'package:dispatch_mobile/core/theme/dispatch_colors.dart' as dc;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class OfflineCommsScreen extends ConsumerStatefulWidget {
  const OfflineCommsScreen({
    super.key,
    this.initialMode,
    this.initialRecipientIdentifier,
    this.initialRecipientLabel,
    this.initialThreadId,
  });

  final String? initialMode;
  final String? initialRecipientIdentifier;
  final String? initialRecipientLabel;
  final String? initialThreadId;

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
  final List<RealtimeSubscriptionHandle> _realtimeHandles = [];

  String? get _activeThreadId => widget.initialThreadId;
  bool get _isDirectThread => (_activeThreadId != null) && _mode == 'direct';
  String get _recipientLabel =>
      widget.initialRecipientLabel ?? 'Selected node';

  @override
  void initState() {
    super.initState();
    _mode = widget.initialMode ??
        (widget.initialRecipientIdentifier != null ? 'direct' : 'broadcast');

    final transport = ref.read(meshTransportProvider);
    if (_activeThreadId != null) {
      transport.markThreadRead(_activeThreadId!);
    } else {
      transport.markAllCommsRead();
    }

    _bindRealtime();
    unawaited(_hydrateServerHistory());
  }

  void _bindRealtime() {
    final realtime = ref.read(realtimeServiceProvider);
    if (!realtime.isConfigured) {
      return;
    }

    _realtimeHandles.addAll([
      realtime.subscribeToTable(
        table: 'mesh_comms_messages',
        onChange: () => unawaited(_hydrateServerHistory()),
      ),
      realtime.subscribeToTable(
        table: 'mesh_comms_posts',
        onChange: () => unawaited(_hydrateServerHistory()),
      ),
    ]);
  }

  @override
  void dispose() {
    for (final handle in _realtimeHandles) {
      unawaited(handle.dispose());
    }
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
          .ingestServerMessages(
            (response['messages'] as List?)?.cast<Map<String, dynamic>>() ??
                const [],
          );
      ref
          .read(meshTransportProvider)
          .ingestServerMeshPosts(
            (response['mesh_posts'] as List?)?.cast<Map<String, dynamic>>() ??
                const [],
          );
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
    setState(() => _syncing = true);
    try {
      final syncResult = await ref
          .read(meshGatewaySyncServiceProvider)
          .sync(
            operatorRole: session.role?.name,
            departmentId: session.department?.id,
            departmentName: session.department?.name,
            displayName:
                session.fullName ?? session.department?.name ?? session.email,
          );
      if (!syncResult.didUpload) {
        return;
      }
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
      final payload =
          jsonDecode(
                utf8.decode(base64Url.decode(base64Url.normalize(segments[1]))),
              )
              as Map<String, dynamic>;
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
    final displayName =
        session.fullName ??
        session.department?.name ??
        session.email ??
        'Mesh user';
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
        if (offlineToken == null ||
            offlineToken.isEmpty ||
            _offlineTokenExpired(offlineToken)) {
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
            (offlineToken == null ||
                offlineToken.isEmpty ||
                _offlineTokenExpired(offlineToken))) {
          throw Exception(
            'Offline account token is missing or expired. Sign in again before sending mesh messages.',
          );
        }
        final threadId = _mode == 'direct'
            ? _activeThreadId
            : _mode == 'department' && session.department != null
                ? MeshTransportService.departmentThreadId(session.department!.id)
                : MeshTransportService.broadcastThreadId();
        final recipientScope = _mode == 'direct'
            ? 'direct'
            : _mode == 'department'
                ? 'department'
                : 'broadcast';
        final recipientIdentifier = _mode == 'direct'
            ? widget.initialRecipientIdentifier
            : _mode == 'department'
                ? session.department?.id
                : null;
        if (threadId == null || threadId.isEmpty) {
          throw Exception('Direct thread target is missing.');
        }
        if (recipientScope == 'direct' &&
            (recipientIdentifier == null || recipientIdentifier.isEmpty)) {
          throw Exception('Recipient node is missing for this direct message.');
        }
        final packet = MeshTransportService.createMeshMessagePacket(
          deviceId: transport.localDeviceId,
          threadId: threadId,
          recipientScope: recipientScope,
          recipientIdentifier: recipientIdentifier,
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
    final items = _activeThreadId != null
        ? transport.threadItems(_activeThreadId!)
        : transport.inboxItems;
    final canDepartmentMessage =
        session.role == AppRole.department && session.department != null;

    return Scaffold(
      backgroundColor: dc.warmBackground,
      appBar: AppBar(
        title: Text(_isDirectThread ? _recipientLabel : 'Offline Comms'),
        backgroundColor: dc.warmBackground,
        surfaceTintColor: Colors.transparent,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Stack(
              alignment: Alignment.center,
              children: [
                IconButton(
                  onPressed: _syncing
                      ? null
                      : () => unawaited(_syncPendingPackets()),
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
                colors: [
                  ...dc.heroGradient,
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(28),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: const Text(
                    'Mesh Comms',
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
                  'Stay connected even when the network is down.',
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
                      ? 'Offline — messages queue locally and sync when a gateway node reconnects.'
                      : 'Online — queued messages will sync to the server automatically.',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.86),
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: dc.warmSurface,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: dc.warmBorder),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Compose',
                  style: TextStyle(
                    color: dc.ink,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (_activeThreadId != null)
                      _ModeChip(
                        label: 'Direct',
                        active: _mode == 'direct',
                        onTap: () => setState(() => _mode = 'direct'),
                      ),
                    if (_activeThreadId == null)
                      _ModeChip(
                        label: 'Broadcast',
                        active: _mode == 'broadcast',
                        onTap: () => setState(() => _mode = 'broadcast'),
                      ),
                    if (_activeThreadId == null && canDepartmentMessage)
                      _ModeChip(
                        label: 'Department',
                        active: _mode == 'department',
                        onTap: () => setState(() => _mode = 'department'),
                      ),
                    if (_activeThreadId == null && canDepartmentMessage)
                      _ModeChip(
                        label: 'Mesh Post',
                        active: _mode == 'post',
                        onTap: () => setState(() => _mode = 'post'),
                      ),
                  ],
                ),
                const SizedBox(height: 14),
                if (_mode == 'post') ...[
                  TextField(
                    controller: _titleCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Title',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: _postCategory,
                    decoration: const InputDecoration(
                      labelText: 'Category',
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'alert', child: Text('Alert')),
                      DropdownMenuItem(
                        value: 'warning',
                        child: Text('Warning'),
                      ),
                      DropdownMenuItem(
                        value: 'safety_tip',
                        child: Text('Safety Tip'),
                      ),
                      DropdownMenuItem(value: 'update', child: Text('Update')),
                      DropdownMenuItem(
                        value: 'situational_report',
                        child: Text('Situational Report'),
                      ),
                    ],
                    onChanged: (value) =>
                        setState(() => _postCategory = value ?? 'update'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _postBodyCtrl,
                    maxLength: 1000,
                    maxLines: 5,
                    decoration: const InputDecoration(
                      labelText: 'Body',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ] else
                  TextField(
                    controller: _messageCtrl,
                    maxLength: 500,
                    maxLines: 4,
                    decoration: InputDecoration(
                      labelText: _mode == 'department'
                          ? 'Department message'
                          : 'Broadcast message',
                      border: const OutlineInputBorder(),
                    ),
                  ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _error!,
                    style: const TextStyle(color: Colors.redAccent),
                  ),
                ],
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: _sending ? null : _submit,
                  style: FilledButton.styleFrom(
                    backgroundColor: dc.warmSeed,
                    foregroundColor: Colors.white,
                  ),
                  icon: Icon(_mode == 'post' ? Icons.campaign : Icons.send),
                  label: Text(
                    _sending
                        ? 'Queueing...'
                        : _mode == 'post'
                        ? 'Publish over mesh'
                        : 'Send over mesh',
                  ),
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
                color: dc.warmSurface,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: dc.warmBorder),
              ),
              child: const Text(
                _isDirectThread
                    ? 'No direct messages in this thread yet. Send one and nearby nodes will relay it across the mesh.'
                    : 'No messages yet. Compose a broadcast above or wait for nearby nodes to relay traffic.',
                style: TextStyle(color: dc.mutedInk, height: 1.45),
              ),
            ),
        ],
      ),
    );
  }
}

class _ModeChip extends StatelessWidget {
  const _ModeChip({
    required this.label,
    required this.active,
    required this.onTap,
  });
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
          color: active ? dc.warmSeed : dc.chipFill,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: active ? Colors.white : dc.ink,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _InboxCard extends StatelessWidget {
  const _InboxCard({required this.item});
  final MeshInboxItem item;

  @override
  Widget build(BuildContext context) {
    final accent = item.itemType == 'mesh_post' ? dc.warmSeed : dc.coolAccent;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: item.isRead ? dc.warmSurface : Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: item.isRead ? dc.warmBorder : accent.withValues(alpha: 0.4),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  item.title ?? item.authorDisplayName,
                  style: const TextStyle(
                    color: dc.ink,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              _Badge(
                label: item.itemType == 'mesh_post'
                    ? 'Post'
                    : item.recipientScope,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            item.body,
            style: const TextStyle(color: dc.ink, height: 1.45),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _MetaChip(label: item.authorRole),
              if (item.category != null)
                _MetaChip(label: item.category!.replaceAll('_', ' ')),
              _MetaChip(label: '${item.hopCount}/${item.maxHops} hops'),
              _MetaChip(
                label: item.needsServerSync
                    ? 'Pending sync'
                    : 'Synced',
              ),
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
        color: dc.chipFill,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: dc.mutedInk,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
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
        color: dc.warmSeed,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}











