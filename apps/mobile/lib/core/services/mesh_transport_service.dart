// Mesh transport - BLE discovery, WiFi Direct handoff, packet relay, and gateway sync.
// The transport now also keeps a restart-safe Offline Comms inbox for mesh messages and posts.

import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:dispatch_mobile/core/services/mesh_inbox_storage.dart';

enum MeshNodeRole { origin, relay, gateway }

enum MeshPayloadType {
  incidentReport,
  announcement,
  distress,
  survivorSignal,
  meshMessage,
  meshPost,
  statusUpdate,
  syncAck,
}

class MeshPacket {
  final String messageId;
  final String originDeviceId;
  final String timestamp;
  int hopCount;
  final int maxHops;
  final MeshPayloadType payloadType;
  final Map<String, dynamic> payload;
  final String signature;

  MeshPacket({
    required this.messageId,
    required this.originDeviceId,
    required this.timestamp,
    this.hopCount = 0,
    this.maxHops = 7,
    required this.payloadType,
    required this.payload,
    this.signature = '',
  });

  String get payloadTypeString {
    return switch (payloadType) {
      MeshPayloadType.incidentReport => 'INCIDENT_REPORT',
      MeshPayloadType.announcement => 'ANNOUNCEMENT',
      MeshPayloadType.distress => 'DISTRESS',
      MeshPayloadType.survivorSignal => 'SURVIVOR_SIGNAL',
      MeshPayloadType.meshMessage => 'MESH_MESSAGE',
      MeshPayloadType.meshPost => 'MESH_POST',
      MeshPayloadType.statusUpdate => 'STATUS_UPDATE',
      MeshPayloadType.syncAck => 'SYNC_ACK',
    };
  }

  Map<String, dynamic> toJson() {
    return {
      'messageId': messageId,
      'originDeviceId': originDeviceId,
      'timestamp': timestamp,
      'hopCount': hopCount,
      'maxHops': maxHops,
      'payloadType': payloadTypeString,
      'payload': payload,
      'signature': signature,
    };
  }

  factory MeshPacket.fromJson(Map<String, dynamic> json) {
    final typeStr = json['payloadType'] as String? ?? '';
    final type = switch (typeStr) {
      'INCIDENT_REPORT' => MeshPayloadType.incidentReport,
      'ANNOUNCEMENT' => MeshPayloadType.announcement,
      'DISTRESS' => MeshPayloadType.distress,
      'SURVIVOR_SIGNAL' => MeshPayloadType.survivorSignal,
      'MESH_MESSAGE' => MeshPayloadType.meshMessage,
      'MESH_POST' => MeshPayloadType.meshPost,
      'STATUS_UPDATE' => MeshPayloadType.statusUpdate,
      'SYNC_ACK' => MeshPayloadType.syncAck,
      _ => MeshPayloadType.statusUpdate,
    };
    return MeshPacket(
      messageId: json['messageId'] as String? ?? '',
      originDeviceId: json['originDeviceId'] as String? ?? '',
      timestamp: json['timestamp'] as String? ?? '',
      hopCount: json['hopCount'] as int? ?? 0,
      maxHops: json['maxHops'] as int? ?? 7,
      payloadType: type,
      payload: json['payload'] as Map<String, dynamic>? ?? {},
      signature: json['signature'] as String? ?? '',
    );
  }

  bool get requiresWifiDirect {
    final encoded = utf8.encode(jsonEncode(payload));
    return encoded.length > 10240;
  }
}

class MeshPeer {
  final String endpointId;
  final String deviceName;
  final bool isGateway;
  DateTime lastSeen;

  MeshPeer({
    required this.endpointId,
    required this.deviceName,
    this.isGateway = false,
    DateTime? lastSeen,
  }) : lastSeen = lastSeen ?? DateTime.now();
}

class MeshInboxItem {
  const MeshInboxItem({
    required this.id,
    required this.messageId,
    required this.itemType,
    required this.recipientScope,
    required this.authorDisplayName,
    required this.authorRole,
    required this.body,
    required this.hopCount,
    required this.maxHops,
    required this.isRead,
    required this.needsServerSync,
    required this.rawPacket,
    required this.createdAt,
    this.threadId,
    this.recipientIdentifier,
    this.title,
    this.category,
  });

  final String id;
  final String messageId;
  final String itemType;
  final String recipientScope;
  final String? threadId;
  final String? recipientIdentifier;
  final String authorDisplayName;
  final String authorRole;
  final String? title;
  final String body;
  final String? category;
  final int hopCount;
  final int maxHops;
  final bool isRead;
  final bool needsServerSync;
  final Map<String, dynamic> rawPacket;
  final String createdAt;

  factory MeshInboxItem.fromPacket(
    MeshPacket packet, {
    required bool isRead,
    required bool needsServerSync,
  }) {
    final payload = packet.payload;
    final isPost = packet.payloadType == MeshPayloadType.meshPost;
    return MeshInboxItem(
      id: packet.messageId,
      messageId: packet.messageId,
      itemType: isPost ? 'mesh_post' : 'mesh_message',
      recipientScope: isPost
          ? 'broadcast'
          : (payload['recipientScope'] as String? ?? 'broadcast'),
      threadId: isPost ? null : payload['threadId'] as String?,
      recipientIdentifier: isPost
          ? null
          : payload['recipientIdentifier'] as String?,
      authorDisplayName: isPost
          ? 'Department Broadcast'
          : (payload['authorDisplayName'] as String? ?? 'Unknown'),
      authorRole: isPost
          ? 'department'
          : (payload['authorRole'] as String? ?? 'anonymous'),
      title: isPost ? payload['title'] as String? : null,
      body: isPost
          ? (payload['body'] as String? ?? '')
          : (payload['body'] as String? ?? ''),
      category: isPost ? payload['category'] as String? : null,
      hopCount: packet.hopCount,
      maxHops: packet.maxHops,
      isRead: isRead,
      needsServerSync: needsServerSync,
      rawPacket: packet.toJson(),
      createdAt: packet.timestamp,
    );
  }

  factory MeshInboxItem.fromJson(Map<String, dynamic> json) {
    return MeshInboxItem(
      id: json['id'] as String? ?? '',
      messageId: json['messageId'] as String? ?? '',
      itemType: json['itemType'] as String? ?? 'mesh_message',
      recipientScope: json['recipientScope'] as String? ?? 'broadcast',
      threadId: json['threadId'] as String?,
      recipientIdentifier: json['recipientIdentifier'] as String?,
      authorDisplayName: json['authorDisplayName'] as String? ?? 'Unknown',
      authorRole: json['authorRole'] as String? ?? 'anonymous',
      title: json['title'] as String?,
      body: json['body'] as String? ?? '',
      category: json['category'] as String?,
      hopCount: json['hopCount'] as int? ?? 0,
      maxHops: json['maxHops'] as int? ?? 7,
      isRead: json['isRead'] == true,
      needsServerSync: json['needsServerSync'] != false,
      rawPacket: json['rawPacket'] as Map<String, dynamic>? ?? {},
      createdAt: json['createdAt'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'messageId': messageId,
      'itemType': itemType,
      'recipientScope': recipientScope,
      'threadId': threadId,
      'recipientIdentifier': recipientIdentifier,
      'authorDisplayName': authorDisplayName,
      'authorRole': authorRole,
      'title': title,
      'body': body,
      'category': category,
      'hopCount': hopCount,
      'maxHops': maxHops,
      'isRead': isRead,
      'needsServerSync': needsServerSync,
      'rawPacket': rawPacket,
      'createdAt': createdAt,
    };
  }

  MeshInboxItem copyWith({
    bool? isRead,
    bool? needsServerSync,
    int? hopCount,
    int? maxHops,
    Map<String, dynamic>? rawPacket,
  }) {
    return MeshInboxItem(
      id: id,
      messageId: messageId,
      itemType: itemType,
      recipientScope: recipientScope,
      threadId: threadId,
      recipientIdentifier: recipientIdentifier,
      authorDisplayName: authorDisplayName,
      authorRole: authorRole,
      title: title,
      body: body,
      category: category,
      hopCount: hopCount ?? this.hopCount,
      maxHops: maxHops ?? this.maxHops,
      isRead: isRead ?? this.isRead,
      needsServerSync: needsServerSync ?? this.needsServerSync,
      rawPacket: rawPacket ?? this.rawPacket,
      createdAt: createdAt,
    );
  }
}

class MeshTransportService {
  MeshTransportService({MeshInboxStorage? inboxStorage})
    : _inboxStorage = inboxStorage,
      _localDeviceId = _generateUuid();

  final MeshInboxStorage? _inboxStorage;
  final String _localDeviceId;
  MeshNodeRole _role = MeshNodeRole.origin;
  final List<MeshPeer> _peers = [];
  final Set<String> _seenMessageIds = {};
  final List<MeshPacket> _outboundQueue = [];
  final List<MeshInboxItem> _inbox = [];
  final StreamController<MeshPacket> _packetController =
      StreamController<MeshPacket>.broadcast();
  DateTime? _lastSyncTime;
  bool _isDiscovering = false;
  bool _hasInternet = false;
  bool _isSosBeaconBroadcasting = false;
  String? _sosBeaconDeviceId;
  bool _hydratedInbox = false;

  MeshNodeRole get role => _role;
  List<MeshPeer> get peers => List.unmodifiable(_peers);
  int get peerCount => _peers.length;
  int get queueSize => _outboundQueue.length;
  DateTime? get lastSyncTime => _lastSyncTime;
  bool get isDiscovering => _isDiscovering;
  int get estimatedReach => _estimateReach();
  bool get isSosBeaconBroadcasting => _isSosBeaconBroadcasting;
  String? get sosBeaconDeviceId => _sosBeaconDeviceId;
  Stream<MeshPacket> get packetStream => _packetController.stream;
  String get localDeviceId => _localDeviceId;
  bool get isMeshOnlyState => !_hasInternet;
  List<MeshInboxItem> get inboxItems => List.unmodifiable(_sortedInbox());
  int get unreadMeshMessageCount =>
      _inbox.where((item) => !item.isRead && item.itemType == 'mesh_message').length;

  List<MeshInboxItem> threadItems(String threadId) {
    return _sortedInbox()
        .where((item) => item.threadId == threadId)
        .toList(growable: false);
  }

  Future<void> initialize() async {
    _role = _hasInternet ? MeshNodeRole.gateway : MeshNodeRole.origin;
    await _hydrateInbox();
  }

  Future<void> _hydrateInbox() async {
    final storage = _inboxStorage;
    if (_hydratedInbox || storage == null) {
      return;
    }
    final stored = await storage.load();
    _inbox
      ..clear()
      ..addAll(stored.map(MeshInboxItem.fromJson));
    for (final item in _inbox) {
      _seenMessageIds.add(item.messageId);
    }
    _hydratedInbox = true;
    if (_role == MeshNodeRole.gateway) {
      _rehydratePendingInboxPackets();
    }
  }

  Future<void> _persistInbox() async {
    final storage = _inboxStorage;
    if (storage == null) {
      return;
    }
    await storage.save(_inbox.map((item) => item.toJson()).toList());
  }

  Future<void> startDiscovery() async {
    _isDiscovering = true;
  }

  Future<void> stopDiscovery() async {
    _isDiscovering = false;
  }

  void setConnectivity(bool hasInternet) {
    _hasInternet = hasInternet;
    if (hasInternet && _role != MeshNodeRole.gateway) {
      _role = MeshNodeRole.gateway;
      _rehydratePendingInboxPackets();
    } else if (!hasInternet && _role == MeshNodeRole.gateway) {
      _role = MeshNodeRole.origin;
    }
  }

  void enqueuePacket(MeshPacket packet) {
    _outboundQueue.add(packet);
    _seenMessageIds.add(packet.messageId);
    _recordPacketInInbox(packet, authoredLocally: true);
  }

  bool receivePacket(MeshPacket packet) {
    if (_seenMessageIds.contains(packet.messageId)) {
      return false;
    }
    if (_isDirectMessage(packet) && !_isPacketForThisDevice(packet)) {
      return false;
    }
    if (packet.hopCount >= packet.maxHops) {
      return false;
    }

    _seenMessageIds.add(packet.messageId);
    packet.hopCount++;

    if (_role == MeshNodeRole.gateway) {
      _outboundQueue.add(packet);
    }

    _recordPacketInInbox(packet, authoredLocally: false);
    _packetController.add(packet);
    return true;
  }

  List<MeshPacket> drainQueue() {
    _rehydratePendingInboxPackets();
    final packets = List<MeshPacket>.from(_outboundQueue)
      ..sort(
        (a, b) =>
            _priorityFor(a.payloadType).compareTo(_priorityFor(b.payloadType)),
      );
    _outboundQueue.clear();
    _lastSyncTime = DateTime.now();
    return packets;
  }

  void processSyncAcks(List<Map<String, dynamic>> acks) {
    var changed = false;
    for (final ack in acks) {
      final msgId = ack['messageId'] as String? ?? '';
      if (msgId.isEmpty) {
        continue;
      }
      _seenMessageIds.add(msgId);
      final index = _inbox.indexWhere((item) => item.messageId == msgId);
      if (index >= 0) {
        _inbox[index] = _inbox[index].copyWith(needsServerSync: false);
        changed = true;
      }
    }
    if (changed) {
      unawaited(_persistInbox());
    }
  }

  void ingestServerMessages(List<Map<String, dynamic>> rows) {
    for (final row in rows) {
      final messageId = row['message_id'] as String? ?? '';
      if (messageId.isEmpty || _inbox.any((item) => item.messageId == messageId)) {
        continue;
      }
      _inbox.add(
        MeshInboxItem(
          id: row['id'] as String? ?? messageId,
          messageId: messageId,
          itemType: 'mesh_message',
          recipientScope: row['recipient_scope'] as String? ?? 'broadcast',
          threadId: row['thread_id'] as String?,
          recipientIdentifier: row['recipient_identifier'] as String?,
          authorDisplayName: row['author_display_name'] as String? ?? 'Unknown',
          authorRole: row['author_role'] as String? ?? 'anonymous',
          body: row['body'] as String? ?? '',
          hopCount: 0,
          maxHops: 7,
          isRead: false,
          needsServerSync: false,
          rawPacket: const {},
          createdAt: row['created_at'] as String? ?? '',
        ),
      );
    }
    unawaited(_persistInbox());
  }

  void ingestServerMeshPosts(List<Map<String, dynamic>> rows) {
    for (final row in rows) {
      final messageId = row['mesh_message_id'] as String?;
      final fallbackId = row['id'] as String? ?? '';
      final uniqueId = messageId ?? 'mesh-post-$fallbackId';
      if (_inbox.any((item) => item.messageId == uniqueId)) {
        continue;
      }
      _inbox.add(
        MeshInboxItem(
          id: fallbackId,
          messageId: uniqueId,
          itemType: 'mesh_post',
          recipientScope: 'broadcast',
          authorDisplayName: 'Department Broadcast',
          authorRole: 'department',
          title: row['title'] as String?,
          body: row['content'] as String? ?? '',
          category: row['category'] as String?,
          hopCount: 0,
          maxHops: 7,
          isRead: false,
          needsServerSync: false,
          rawPacket: const {},
          createdAt: row['created_at'] as String? ?? '',
        ),
      );
    }
    unawaited(_persistInbox());
  }

  void markAllCommsRead() {
    var changed = false;
    for (var index = 0; index < _inbox.length; index++) {
      if (_inbox[index].isRead) {
        continue;
      }
      _inbox[index] = _inbox[index].copyWith(isRead: true);
      changed = true;
    }
    if (changed) {
      unawaited(_persistInbox());
    }
  }

  void markThreadRead(String threadId) {
    var changed = false;
    for (var index = 0; index < _inbox.length; index++) {
      if (_inbox[index].threadId != threadId || _inbox[index].isRead) {
        continue;
      }
      _inbox[index] = _inbox[index].copyWith(isRead: true);
      changed = true;
    }
    if (changed) {
      unawaited(_persistInbox());
    }
  }

  void onPeerDiscovered(String endpointId, String deviceName) {
    final existing = _peers.where((p) => p.endpointId == endpointId);
    if (existing.isNotEmpty) {
      existing.first.lastSeen = DateTime.now();
    } else {
      _peers.add(MeshPeer(endpointId: endpointId, deviceName: deviceName));
    }
  }

  void pruneStalePeers() {
    final cutoff = DateTime.now().subtract(const Duration(minutes: 5));
    _peers.removeWhere((p) => p.lastSeen.isBefore(cutoff));
  }

  void pruneStaleePeers() => pruneStalePeers();

  String transportForPacket(MeshPacket packet) {
    return packet.requiresWifiDirect ? 'wifi_direct' : 'ble';
  }

  void startSosBeaconBroadcast({required String deviceId}) {
    _isSosBeaconBroadcasting = true;
    _sosBeaconDeviceId = deviceId;
  }

  void stopSosBeaconBroadcast() {
    _isSosBeaconBroadcasting = false;
    _sosBeaconDeviceId = null;
  }

  void _recordPacketInInbox(
    MeshPacket packet, {
    required bool authoredLocally,
  }) {
    if (packet.payloadType != MeshPayloadType.meshMessage &&
        packet.payloadType != MeshPayloadType.meshPost) {
      return;
    }

    final nextItem = MeshInboxItem.fromPacket(
      packet,
      isRead: authoredLocally,
      needsServerSync: true,
    );
    final index = _inbox.indexWhere((item) => item.messageId == packet.messageId);
    if (index >= 0) {
      _inbox[index] = nextItem.copyWith(
        isRead: authoredLocally ? true : _inbox[index].isRead,
      );
    } else {
      _inbox.add(nextItem);
    }
    unawaited(_persistInbox());
  }

  void _rehydratePendingInboxPackets() {
    for (final item in _inbox.where((entry) => entry.needsServerSync)) {
      if (_outboundQueue.any((packet) => packet.messageId == item.messageId)) {
        continue;
      }
      if (item.rawPacket.isEmpty) {
        continue;
      }
      _outboundQueue.add(MeshPacket.fromJson(item.rawPacket));
    }
  }

  bool _isDirectMessage(MeshPacket packet) {
    return packet.payloadType == MeshPayloadType.meshMessage &&
        (packet.payload['recipientScope'] as String? ?? '').toLowerCase() == 'direct';
  }

  bool _isPacketForThisDevice(MeshPacket packet) {
    final recipient = packet.payload['recipientIdentifier'] as String?;
    return recipient == _localDeviceId || recipient == packet.originDeviceId;
  }

  int _estimateReach() {
    if (_peers.isEmpty) return 1;
    return min(_peers.length * 2, 50);
  }

  List<MeshInboxItem> _sortedInbox() {
    final items = List<MeshInboxItem>.from(_inbox);
    items.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return items;
  }

  static MeshPacket createDistressPacket({
    required String deviceId,
    double? latitude,
    double? longitude,
    String description = '',
    String reporterName = '',
    String contactInfo = '',
  }) {
    return MeshPacket(
      messageId: _generateUuid(),
      originDeviceId: deviceId,
      timestamp: DateTime.now().toUtc().toIso8601String(),
      maxHops: 15,
      payloadType: MeshPayloadType.distress,
      payload: {
        'latitude': latitude,
        'longitude': longitude,
        'description': description,
        'reporter_name': reporterName,
        'contact_info': contactInfo,
      },
    );
  }

  static MeshPacket createIncidentPacket({
    required String deviceId,
    required String description,
    String category = 'other',
    String severity = 'medium',
    String? address,
    double? latitude,
    double? longitude,
    String? reporterId,
  }) {
    return MeshPacket(
      messageId: _generateUuid(),
      originDeviceId: deviceId,
      timestamp: DateTime.now().toUtc().toIso8601String(),
      payloadType: MeshPayloadType.incidentReport,
      payload: _buildIncidentPayload(
        description,
        category,
        severity,
        address,
        latitude,
        longitude,
        reporterId,
      ),
    );
  }

  static MeshPacket createAnnouncementPacket({
    required String deviceId,
    required String departmentId,
    required String offlineToken,
    required String title,
    required String content,
    String category = 'update',
    String? authorId,
  }) {
    return MeshPacket(
      messageId: _generateUuid(),
      originDeviceId: deviceId,
      timestamp: DateTime.now().toUtc().toIso8601String(),
      payloadType: MeshPayloadType.announcement,
      payload: _buildAnnouncementPayload(
        departmentId,
        offlineToken,
        title,
        content,
        category,
        authorId,
      ),
    );
  }

  static MeshPacket createMeshMessagePacket({
    required String deviceId,
    required String threadId,
    required String recipientScope,
    String? recipientIdentifier,
    required String body,
    required String authorDisplayName,
    required String authorRole,
    String? authorOfflineToken,
  }) {
    return MeshPacket(
      messageId: _generateUuid(),
      originDeviceId: deviceId,
      timestamp: DateTime.now().toUtc().toIso8601String(),
      payloadType: MeshPayloadType.meshMessage,
      payload: {
        'threadId': threadId,
        'recipientScope': recipientScope,
        'recipientIdentifier': recipientIdentifier,
        'body': body,
        'authorDisplayName': authorDisplayName,
        'authorRole': authorRole,
        'authorOfflineToken': authorOfflineToken,
      },
    );
  }

  static MeshPacket createMeshPostPacket({
    required String deviceId,
    required String postId,
    required String category,
    required String title,
    required String body,
    required String authorDepartmentId,
    required String authorOfflineToken,
    List<String> attachmentRefs = const [],
  }) {
    return MeshPacket(
      messageId: _generateUuid(),
      originDeviceId: deviceId,
      timestamp: DateTime.now().toUtc().toIso8601String(),
      payloadType: MeshPayloadType.meshPost,
      payload: {
        'postId': postId,
        'category': category,
        'title': title,
        'body': body,
        'authorDepartmentId': authorDepartmentId,
        'authorOfflineToken': authorOfflineToken,
        'attachmentRefs': attachmentRefs,
      },
    );
  }

  static MeshPacket createSurvivorResolvePacket({
    required String deviceId,
    required String survivorMessageId,
    String? signalId,
    String note = '',
    String? resolvedByUserId,
  }) {
    return MeshPacket(
      messageId: _generateUuid(),
      originDeviceId: deviceId,
      timestamp: DateTime.now().toUtc().toIso8601String(),
      maxHops: 15,
      payloadType: MeshPayloadType.statusUpdate,
      payload: _buildSurvivorResolvePayload(
        survivorMessageId,
        signalId,
        note,
        resolvedByUserId,
      ),
    );
  }

  static String generateUuid() => _generateUuid();

  static String broadcastThreadId() => '00000000-0000-4000-8000-000000000001';

  static String departmentThreadId(String departmentId) {
    final digest = md5Hash('department:$departmentId');
    return '${digest.substring(0, 8)}-${digest.substring(8, 12)}-'
        '4${digest.substring(13, 16)}-8${digest.substring(17, 20)}-'
        '${digest.substring(20, 32)}';
  }

  static String md5Hash(String input) {
    final bytes = utf8.encode(input);
    var hash = 0;
    for (final byte in bytes) {
      hash = ((hash * 31) + byte) & 0x7fffffff;
    }
    final seed = hash.toRadixString(16).padLeft(8, '0');
    return (seed * 4).substring(0, 32);
  }

  static Map<String, dynamic> _buildSurvivorResolvePayload(
    String survivorMessageId,
    String? signalId,
    String note,
    String? resolvedByUserId,
  ) {
    final m = <String, dynamic>{
      'targetType': 'SURVIVOR_SIGNAL',
      'survivorMessageId': survivorMessageId,
      'resolved': true,
      'resolutionNote': note,
      'timestamp': DateTime.now().toUtc().toIso8601String(),
    };
    if (signalId != null && signalId.isNotEmpty) m['signalId'] = signalId;
    if (resolvedByUserId != null && resolvedByUserId.isNotEmpty) {
      m['resolvedByUserId'] = resolvedByUserId;
    }
    return m;
  }

  static Map<String, dynamic> _buildIncidentPayload(
    String description,
    String category,
    String severity,
    String? address,
    double? latitude,
    double? longitude,
    String? reporterId,
  ) {
    final m = <String, dynamic>{
      'description': description,
      'category': category,
      'severity': severity,
    };
    if (address != null) m['address'] = address;
    if (latitude != null) m['latitude'] = latitude;
    if (longitude != null) m['longitude'] = longitude;
    if (reporterId != null) m['reporter_id'] = reporterId;
    return m;
  }

  static Map<String, dynamic> _buildAnnouncementPayload(
    String departmentId,
    String offlineToken,
    String title,
    String content,
    String category,
    String? authorId,
  ) {
    final m = <String, dynamic>{
      'department_id': departmentId,
      'offline_verification_token': offlineToken,
      'title': title,
      'content': content,
      'category': category,
    };
    if (authorId != null) m['author_id'] = authorId;
    return m;
  }

  static int _priorityFor(MeshPayloadType payloadType) {
    return switch (payloadType) {
      MeshPayloadType.distress || MeshPayloadType.survivorSignal => 0,
      MeshPayloadType.statusUpdate || MeshPayloadType.meshMessage => 1,
      MeshPayloadType.announcement || MeshPayloadType.meshPost => 2,
      MeshPayloadType.incidentReport => 3,
      MeshPayloadType.syncAck => 4,
    };
  }

  void dispose() {
    _packetController.close();
  }

  static String _generateUuid() {
    final rng = Random();
    final bytes = List<int>.generate(16, (_) => rng.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-'
        '${hex.substring(20)}';
  }
}
