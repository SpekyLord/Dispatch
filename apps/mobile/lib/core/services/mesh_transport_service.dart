// Mesh transport - BLE discovery, WiFi Direct handoff, packet relay, and gateway sync.
// The transport now also keeps a restart-safe Offline Comms inbox for mesh messages and posts.

import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:dispatch_mobile/core/services/location_service.dart';
import 'package:dispatch_mobile/core/services/mesh_inbox_storage.dart';
import 'package:dispatch_mobile/core/services/mesh_platform_service.dart';

enum MeshNodeRole { origin, relay, gateway }

enum MeshPayloadType {
  incidentReport,
  announcement,
  distress,
  survivorSignal,
  meshMessage,
  meshPost,
  locationBeacon,
  statusUpdate,
  syncAck,
}

const _topologyNodeWindow = Duration(minutes: 30);
const _topologyNodeCap = 150;

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
      MeshPayloadType.locationBeacon => 'LOCATION_BEACON',
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
      'LOCATION_BEACON' => MeshPayloadType.locationBeacon,
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
  String deviceName;
  bool isGateway;
  bool supportsWifiDirect;
  bool isConnected;
  String? transport;
  DateTime lastSeen;

  MeshPeer({
    required this.endpointId,
    required this.deviceName,
    this.isGateway = false,
    this.supportsWifiDirect = false,
    this.isConnected = false,
    this.transport,
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

class DeviceLocationTrailPoint {
  const DeviceLocationTrailPoint({
    required this.messageId,
    required this.deviceFingerprint,
    required this.lat,
    required this.lng,
    required this.recordedAt,
    this.displayName,
    this.accuracyMeters,
    this.batteryPct,
    this.appState = 'foreground',
  });

  final String messageId;
  final String deviceFingerprint;
  final String? displayName;
  final double lat;
  final double lng;
  final double? accuracyMeters;
  final int? batteryPct;
  final String appState;
  final DateTime recordedAt;

  factory DeviceLocationTrailPoint.fromPacket(MeshPacket packet) {
    final payload = packet.payload;
    return DeviceLocationTrailPoint(
      messageId: packet.messageId,
      deviceFingerprint: payload['deviceFingerprint'] as String? ?? '',
      displayName: payload['displayName'] as String?,
      lat: (payload['lat'] as num?)?.toDouble() ?? 0,
      lng: (payload['lng'] as num?)?.toDouble() ?? 0,
      accuracyMeters: (payload['accuracyMeters'] as num?)?.toDouble(),
      batteryPct: (payload['batteryPct'] as num?)?.toInt(),
      appState: payload['appState'] as String? ?? 'foreground',
      recordedAt:
          DateTime.tryParse(packet.timestamp)?.toUtc() ??
          DateTime.now().toUtc(),
    );
  }

  factory DeviceLocationTrailPoint.fromJson(Map<String, dynamic> json) {
    final location = json['location'] as Map<String, dynamic>? ?? const {};
    final lat =
        (json['lat'] as num?)?.toDouble() ??
        (location['lat'] as num?)?.toDouble() ??
        0;
    final lng =
        (json['lng'] as num?)?.toDouble() ??
        (location['lng'] as num?)?.toDouble() ??
        0;
    return DeviceLocationTrailPoint(
      messageId:
          json['message_id'] as String? ?? json['messageId'] as String? ?? '',
      deviceFingerprint:
          json['device_fingerprint'] as String? ??
          json['deviceFingerprint'] as String? ??
          '',
      displayName:
          json['display_name'] as String? ?? json['displayName'] as String?,
      lat: lat,
      lng: lng,
      accuracyMeters:
          (json['accuracy_meters'] as num?)?.toDouble() ??
          (json['accuracyMeters'] as num?)?.toDouble() ??
          (location['accuracyMeters'] as num?)?.toDouble(),
      batteryPct:
          (json['battery_pct'] as num?)?.toInt() ??
          (json['batteryPct'] as num?)?.toInt(),
      appState:
          json['app_state'] as String? ??
          json['appState'] as String? ??
          'foreground',
      recordedAt:
          DateTime.tryParse(
            json['recorded_at'] as String? ??
                json['recordedAt'] as String? ??
                json['created_at'] as String? ??
                DateTime.now().toUtc().toIso8601String(),
          )?.toUtc() ??
          DateTime.now().toUtc(),
    );
  }
}

class MeshTransportService {
  MeshTransportService({
    MeshInboxStorage? inboxStorage,
    LocationService? locationService,
    MeshPlatformService? platform,
    bool automaticLocationBeaconing = true,
  }) : _inboxStorage = inboxStorage,
       _locationService = locationService ?? LocationService(),
       _platform = platform,
       _automaticLocationBeaconing = automaticLocationBeaconing,
       _localDeviceId = _generateUuid();

  final MeshInboxStorage? _inboxStorage;
  final LocationService _locationService;
  final MeshPlatformService? _platform;
  final bool _automaticLocationBeaconing;
  final String _localDeviceId;
  MeshNodeRole _role = MeshNodeRole.origin;
  final List<MeshPeer> _peers = [];
  final Set<String> _seenMessageIds = {};
  final List<MeshPacket> _outboundQueue = [];
  final List<MeshInboxItem> _inbox = [];
  final Map<String, List<DeviceLocationTrailPoint>> _locationTrailByDevice = {};
  final Map<String, DeviceLocationTrailPoint> _lastSeenByDevice = {};
  final StreamController<MeshPacket> _packetController =
      StreamController<MeshPacket>.broadcast();
  final Map<String, MeshPacket> _relayBacklog = {};
  final Map<String, Set<String>> _relayRecipientsByMessage = {};
  DateTime? _lastSyncTime;
  bool _isDiscovering = false;
  bool _hasInternet = false;
  bool _initialized = false;
  bool _relayFlushInFlight = false;
  int _connectedRelayPeerCount = 0;
  String? _transportStatusNote;
  String? _activeRelayTransport;
  bool _isSosBeaconBroadcasting = false;
  bool _sarModeEnabled = false;
  String? _sosBeaconDeviceId;
  Timer? _locationBeaconTimer;
  Duration? _activeLocationBeaconInterval;
  bool _hydratedInbox = false;
  StreamSubscription<MeshPlatformEvent>? _platformSubscription;
  MeshPlatformCapabilities _platformCapabilities =
      MeshPlatformCapabilities.unsupported(
        'Native mesh discovery bridge is unavailable on this build.',
      );

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
  Duration? get activeLocationBeaconInterval => _activeLocationBeaconInterval;
  MeshPlatformCapabilities get platformCapabilities => _platformCapabilities;
  bool get hasNativeDiscovery => _platformCapabilities.bleDiscoverySupported;
  int get connectedRelayPeerCount => _connectedRelayPeerCount;
  String? get transportStatusNote => _transportStatusNote;
  String? get activeRelayTransport => _activeRelayTransport;
  List<MeshInboxItem> get inboxItems => List.unmodifiable(_sortedInbox());
  int get unreadMeshMessageCount => _inbox
      .where((item) => !item.isRead && item.itemType == 'mesh_message')
      .length;

  List<MeshInboxItem> threadItems(String threadId) {
    return _sortedInbox()
        .where((item) => item.threadId == threadId)
        .toList(growable: false);
  }

  DeviceLocationTrailPoint? lastSeenForDevice(String deviceFingerprint) {
    return _lastSeenByDevice[deviceFingerprint];
  }

  List<DeviceLocationTrailPoint> trailForDevice(String deviceFingerprint) {
    final points = List<DeviceLocationTrailPoint>.from(
      _locationTrailByDevice[deviceFingerprint] ?? const [],
    );
    points.sort((a, b) => a.recordedAt.compareTo(b.recordedAt));
    return points;
  }

  void ingestServerLastSeen(Iterable<Map<String, dynamic>> rows) {
    for (final row in rows) {
      _upsertTrailPoint(DeviceLocationTrailPoint.fromJson(row));
    }
  }

  void ingestServerTrail(
    String deviceFingerprint,
    Iterable<Map<String, dynamic>> rows,
  ) {
    for (final row in rows) {
      final point = DeviceLocationTrailPoint.fromJson(row);
      if (point.deviceFingerprint.isEmpty && deviceFingerprint.isNotEmpty) {
        _upsertTrailPoint(
          DeviceLocationTrailPoint(
            messageId: point.messageId,
            deviceFingerprint: deviceFingerprint,
            displayName: point.displayName,
            lat: point.lat,
            lng: point.lng,
            accuracyMeters: point.accuracyMeters,
            batteryPct: point.batteryPct,
            appState: point.appState,
            recordedAt: point.recordedAt,
          ),
        );
        continue;
      }
      _upsertTrailPoint(point);
    }
  }

  Future<void> initialize() async {
    if (_initialized) {
      return;
    }
    _initialized = true;
    _updateNodeRole();
    _bindPlatformEvents();
    await _refreshPlatformCapabilities();
    await _hydrateInbox();
    _syncLocationBeaconSchedule();
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

  void _bindPlatformEvents() {
    if (_platform == null || _platformSubscription != null) {
      return;
    }
    _platformSubscription = _platform.events.listen((event) {
      switch (event.type) {
        case MeshPlatformEventType.peerSeen:
          final peer = event.peer;
          if (peer == null) {
            return;
          }
          onPeerDiscovered(
            peer.endpointId,
            peer.deviceName,
            isGateway: peer.isGateway,
            supportsWifiDirect: peer.supportsWifiDirect,
            isConnected: peer.isConnected,
            transport: peer.transport,
          );
        case MeshPlatformEventType.transportState:
          final snapshot = event.transportState;
          if (snapshot == null) {
            return;
          }
          _connectedRelayPeerCount = snapshot.connectedPeerCount;
          _transportStatusNote = snapshot.note;
          _activeRelayTransport = snapshot.activeTransport;
          _updateNodeRole();
          if (snapshot.connectedPeerCount > 0) {
            _scheduleRelayFlush();
          }
        case MeshPlatformEventType.packetReceived:
          final inbound = event.packet;
          if (inbound == null) {
            return;
          }
          receivePacket(
            MeshPacket.fromJson(inbound.packet),
            sourceEndpointId: inbound.sourceEndpointId,
            transport: inbound.transport,
          );
      }
    });
  }

  Future<void> _refreshPlatformCapabilities() async {
    if (_platform == null) {
      return;
    }
    _platformCapabilities = await _platform.getCapabilities();
  }

  Future<void> startDiscovery() async {
    await initialize();
    _isDiscovering = true;
    await _refreshPlatformCapabilities();
    await _platform?.startDiscovery(
      localDeviceId: _localDeviceId,
      isGateway: _role == MeshNodeRole.gateway,
    );
    _scheduleRelayFlush();
  }

  Future<void> stopDiscovery() async {
    _isDiscovering = false;
    await _platform?.stopDiscovery();
  }

  void setConnectivity(bool hasInternet) {
    _hasInternet = hasInternet;
    if (hasInternet) {
      _rehydratePendingInboxPackets();
    }
    _updateNodeRole();
    if (_isDiscovering && _platform != null) {
      unawaited(
        _platform.startDiscovery(
          localDeviceId: _localDeviceId,
          isGateway: _role == MeshNodeRole.gateway,
        ),
      );
    }
    _syncLocationBeaconSchedule();
    _scheduleRelayFlush();
  }

  void enqueuePacket(MeshPacket packet) {
    _outboundQueue.add(packet);
    _seenMessageIds.add(packet.messageId);
    _rememberForRelay(packet);
    _recordLocationTrail(packet);
    _recordPacketInInbox(packet, authoredLocally: true);
    _scheduleRelayFlush(messageId: packet.messageId);
  }

  bool receivePacket(
    MeshPacket packet, {
    String? sourceEndpointId,
    String? transport,
  }) {
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

    _rememberForRelay(packet);
    _recordLocationTrail(packet);
    _recordPacketInInbox(packet, authoredLocally: false);
    _packetController.add(packet);
    if (transport != null && transport.isNotEmpty) {
      _activeRelayTransport = transport;
    }
    _scheduleRelayFlush(
      messageId: packet.messageId,
      excludeEndpointId: sourceEndpointId,
    );
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

  void restoreQueue(List<MeshPacket> packets) {
    if (packets.isEmpty) {
      return;
    }
    final queuedMessageIds = _outboundQueue
        .map((packet) => packet.messageId)
        .toSet();
    for (final packet in packets) {
      if (queuedMessageIds.contains(packet.messageId)) {
        continue;
      }
      _outboundQueue.add(packet);
      queuedMessageIds.add(packet.messageId);
    }
  }

  Future<Map<String, dynamic>?> buildTopologySnapshot({
    String? operatorRole,
    String? departmentId,
    String? departmentName,
    String? displayName,
    int maxNodes = _topologyNodeCap,
  }) async {
    final capturedAt = DateTime.now().toUtc();
    final effectiveMaxNodes = max(1, maxNodes);
    final localFingerprint = anonymizeDeviceFingerprint(
      _sosBeaconDeviceId ?? _localDeviceId,
    );
    final freshnessCutoff = capturedAt.subtract(_topologyNodeWindow);

    var gatewayPoint = _lastSeenByDevice[localFingerprint];
    var gatewaySource = 'location_beacon';
    if (gatewayPoint == null ||
        gatewayPoint.recordedAt.isBefore(freshnessCutoff)) {
      final location = await _locationService.getCurrentPosition();
      if (location != null) {
        gatewayPoint = DeviceLocationTrailPoint(
          messageId: '',
          deviceFingerprint: localFingerprint,
          displayName: displayName,
          lat: location.latitude,
          lng: location.longitude,
          accuracyMeters: location.accuracyMeters,
          appState: _isSosBeaconBroadcasting ? 'sos_active' : 'foreground',
          recordedAt: capturedAt,
        );
        gatewaySource = 'live_gps';
      }
    }
    if (gatewayPoint == null) {
      return null;
    }

    final normalizedRole = _normalizeTopologyRole(operatorRole);
    final hasDepartmentId =
        departmentId != null && departmentId.trim().isNotEmpty;
    final normalizedDepartmentId = hasDepartmentId
        ? departmentId!.trim()
        : null;
    final normalizedDepartmentName = (departmentName ?? '').trim();
    final gatewayDisplayName = (displayName ?? gatewayPoint.displayName ?? '')
        .trim();

    final gatewayNode = <String, dynamic>{
      'nodeDeviceId': _localDeviceId,
      'gatewayDeviceId': _localDeviceId,
      'role': 'gateway',
      'lat': gatewayPoint.lat,
      'lng': gatewayPoint.lng,
      'peerCount': peerCount,
      'queueDepth': queueSize,
      'displayName': gatewayDisplayName.isEmpty
          ? localFingerprint
          : gatewayDisplayName,
      'operatorRole': normalizedRole,
      'departmentId': normalizedDepartmentId,
      'departmentName': normalizedDepartmentName,
      'isResponder': normalizedRole == 'department' || hasDepartmentId,
      'lastSeenTimestamp': gatewayPoint.recordedAt.toIso8601String(),
      'metadata': {
        'batteryPct': gatewayPoint.batteryPct,
        'appState': gatewayPoint.appState,
        'accuracyMeters': gatewayPoint.accuracyMeters,
        'source': gatewaySource,
      },
    };

    final recentPeerBeacons =
        _lastSeenByDevice.values
            .where(
              (point) =>
                  point.deviceFingerprint != localFingerprint &&
                  point.recordedAt.isAfter(freshnessCutoff),
            )
            .toList(growable: false)
          ..sort((a, b) => b.recordedAt.compareTo(a.recordedAt));

    final nodes = recentPeerBeacons
        .take(effectiveMaxNodes)
        .map(
          (point) => <String, dynamic>{
            'nodeDeviceId': point.deviceFingerprint,
            'gatewayDeviceId': _localDeviceId,
            'role': 'relay',
            'lat': point.lat,
            'lng': point.lng,
            'peerCount': 0,
            'queueDepth': 0,
            'displayName': point.displayName ?? point.deviceFingerprint,
            'isResponder': false,
            'lastSeenTimestamp': point.recordedAt.toIso8601String(),
            'metadata': {
              'batteryPct': point.batteryPct,
              'appState': point.appState,
              'accuracyMeters': point.accuracyMeters,
              'source': 'location_beacon',
            },
          },
        )
        .toList(growable: false);

    return <String, dynamic>{
      'gatewayDeviceId': _localDeviceId,
      'capturedAt': capturedAt.toIso8601String(),
      'gateway': gatewayNode,
      'nodes': nodes,
    };
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
      if (messageId.isEmpty ||
          _inbox.any((item) => item.messageId == messageId)) {
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

  void onPeerDiscovered(
    String endpointId,
    String deviceName, {
    bool isGateway = false,
    bool supportsWifiDirect = false,
    bool isConnected = false,
    String? transport,
  }) {
    final existing = _peers.where((p) => p.endpointId == endpointId);
    if (existing.isNotEmpty) {
      final peer = existing.first;
      peer
        ..deviceName = deviceName
        ..isGateway = isGateway
        ..supportsWifiDirect = supportsWifiDirect
        ..isConnected = isConnected
        ..transport = transport
        ..lastSeen = DateTime.now();
    } else {
      _peers.add(
        MeshPeer(
          endpointId: endpointId,
          deviceName: deviceName,
          isGateway: isGateway,
          supportsWifiDirect: supportsWifiDirect,
          isConnected: isConnected,
          transport: transport,
        ),
      );
    }
    _connectedRelayPeerCount = _peers.where((peer) => peer.isConnected).length;
    if (transport != null && transport.isNotEmpty) {
      _activeRelayTransport = transport;
    }
    _updateNodeRole();
    if (isConnected) {
      _scheduleRelayFlush();
    }
  }

  void pruneStalePeers() {
    final cutoff = DateTime.now().subtract(const Duration(minutes: 5));
    _peers.removeWhere((p) => p.lastSeen.isBefore(cutoff));
    _connectedRelayPeerCount = _peers.where((peer) => peer.isConnected).length;
    _updateNodeRole();
  }

  void pruneStaleePeers() => pruneStalePeers();

  String transportForPacket(MeshPacket packet) {
    if (_platformCapabilities.wifiDirectSupported ||
        _connectedRelayPeerCount > 0) {
      return 'wifi_direct';
    }
    if (packet.requiresWifiDirect) {
      return 'wifi_direct';
    }
    return hasNativeDiscovery ? 'ble_discovery' : 'queued';
  }

  void startSosBeaconBroadcast({required String deviceId}) {
    _isSosBeaconBroadcasting = true;
    _sosBeaconDeviceId = deviceId;
    _syncLocationBeaconSchedule();
  }

  void stopSosBeaconBroadcast() {
    _isSosBeaconBroadcasting = false;
    _sosBeaconDeviceId = null;
    _syncLocationBeaconSchedule();
  }

  void setSarModeEnabled(bool enabled) {
    _sarModeEnabled = enabled;
    _syncLocationBeaconSchedule();
  }

  void _rememberForRelay(MeshPacket packet) {
    _relayBacklog[packet.messageId] = MeshPacket.fromJson(packet.toJson());
    if (_relayBacklog.length > 180) {
      final oldestMessageId = _relayBacklog.values.toList(growable: false)
        ..sort((left, right) => left.timestamp.compareTo(right.timestamp));
      if (oldestMessageId.isNotEmpty) {
        final evicted = oldestMessageId.first.messageId;
        _relayBacklog.remove(evicted);
        _relayRecipientsByMessage.remove(evicted);
      }
    }
  }

  void _scheduleRelayFlush({String? messageId, String? excludeEndpointId}) {
    if (_platform == null || !_isDiscovering) {
      return;
    }
    unawaited(
      _flushRelayBacklog(
        messageId: messageId,
        excludeEndpointId: excludeEndpointId,
      ),
    );
  }

  // Relay backlog keeps accepted packets available for newly connected peers without reprocessing them locally.
  Future<void> _flushRelayBacklog({
    String? messageId,
    String? excludeEndpointId,
  }) async {
    if (_platform == null || _relayFlushInFlight || !_isDiscovering) {
      return;
    }
    _relayFlushInFlight = true;
    try {
      final backlog = messageId == null
          ? _relayBacklog.values.toList(growable: false)
          : <MeshPacket>[
              if (_relayBacklog[messageId] != null) _relayBacklog[messageId]!,
            ];
      backlog.sort(
        (left, right) => _priorityFor(
          left.payloadType,
        ).compareTo(_priorityFor(right.payloadType)),
      );

      for (final packet in backlog) {
        final excluded = {
          ...(_relayRecipientsByMessage[packet.messageId] ?? const <String>{}),
          if (excludeEndpointId != null && excludeEndpointId.isNotEmpty)
            excludeEndpointId,
        };
        final result = await _platform.sendPacket(
          packet: packet.toJson(),
          preferredTransport: transportForPacket(packet),
          excludeEndpointIds: excluded.toList(growable: false),
        );
        if (result.sentEndpointIds.isNotEmpty) {
          _relayRecipientsByMessage
              .putIfAbsent(packet.messageId, () => <String>{})
              .addAll(result.sentEndpointIds);
        }
        if ((result.transport ?? '').isNotEmpty) {
          _activeRelayTransport = result.transport;
        }
      }
    } finally {
      _relayFlushInFlight = false;
      _updateNodeRole();
    }
  }

  void _updateNodeRole() {
    if (_hasInternet) {
      _role = MeshNodeRole.gateway;
      return;
    }
    final hasRelayLink =
        _connectedRelayPeerCount > 0 || _peers.any((peer) => peer.isConnected);
    _role = hasRelayLink ? MeshNodeRole.relay : MeshNodeRole.origin;
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
    final index = _inbox.indexWhere(
      (item) => item.messageId == packet.messageId,
    );
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

  // Location beacons stay in memory because they are refreshed often and only
  // drive the live compass and map overlays.
  void _recordLocationTrail(MeshPacket packet) {
    if (packet.payloadType != MeshPayloadType.locationBeacon) {
      return;
    }
    final point = DeviceLocationTrailPoint.fromPacket(packet);
    if (point.deviceFingerprint.isEmpty) {
      return;
    }
    _upsertTrailPoint(point);
  }

  void _upsertTrailPoint(DeviceLocationTrailPoint point) {
    if (point.deviceFingerprint.isEmpty) {
      return;
    }
    final trail = _locationTrailByDevice.putIfAbsent(
      point.deviceFingerprint,
      () => <DeviceLocationTrailPoint>[],
    );
    final existingIndex = trail.indexWhere(
      (entry) =>
          entry.messageId == point.messageId && entry.messageId.isNotEmpty,
    );
    if (existingIndex >= 0) {
      trail[existingIndex] = point;
    } else {
      trail.add(point);
    }
    trail.sort((a, b) => a.recordedAt.compareTo(b.recordedAt));
    if (trail.length > 240) {
      trail.removeRange(0, trail.length - 240);
    }

    final currentLastSeen = _lastSeenByDevice[point.deviceFingerprint];
    if (currentLastSeen == null ||
        point.recordedAt.isAfter(currentLastSeen.recordedAt)) {
      _lastSeenByDevice[point.deviceFingerprint] = point;
    }
  }

  void _syncLocationBeaconSchedule() {
    if (!_automaticLocationBeaconing) {
      _locationBeaconTimer?.cancel();
      _locationBeaconTimer = null;
      _activeLocationBeaconInterval = null;
      return;
    }

    final shouldBroadcast =
        _sarModeEnabled || isMeshOnlyState || _isSosBeaconBroadcasting;
    final nextInterval = shouldBroadcast
        ? (_isSosBeaconBroadcasting
              ? const Duration(seconds: 10)
              : const Duration(seconds: 30))
        : null;

    if (nextInterval == null) {
      _locationBeaconTimer?.cancel();
      _locationBeaconTimer = null;
      _activeLocationBeaconInterval = null;
      return;
    }

    if (_locationBeaconTimer != null &&
        _activeLocationBeaconInterval == nextInterval) {
      return;
    }

    _locationBeaconTimer?.cancel();
    _activeLocationBeaconInterval = nextInterval;
    _locationBeaconTimer = Timer.periodic(nextInterval, (_) {
      unawaited(_emitLocationBeacon());
    });
    unawaited(_emitLocationBeacon());
  }

  Future<void> _emitLocationBeacon() async {
    final location = await _locationService.getCurrentPosition();
    if (location == null) {
      return;
    }

    enqueuePacket(
      MeshTransportService.createLocationBeaconPacket(
        deviceId: _sosBeaconDeviceId ?? _localDeviceId,
        latitude: location.latitude,
        longitude: location.longitude,
        accuracyMeters: location.accuracyMeters,
        displayName: null,
        appState: _isSosBeaconBroadcasting ? 'sos_active' : 'foreground',
      ),
    );
  }

  bool _isDirectMessage(MeshPacket packet) {
    return packet.payloadType == MeshPayloadType.meshMessage &&
        (packet.payload['recipientScope'] as String? ?? '').toLowerCase() ==
            'direct';
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

  static MeshPacket createLocationBeaconPacket({
    required String deviceId,
    required double latitude,
    required double longitude,
    double? accuracyMeters,
    int? batteryPct,
    String? displayName,
    String appState = 'foreground',
  }) {
    return MeshPacket(
      messageId: _generateUuid(),
      originDeviceId: deviceId,
      timestamp: DateTime.now().toUtc().toIso8601String(),
      maxHops: 7,
      payloadType: MeshPayloadType.locationBeacon,
      payload: {
        'deviceFingerprint': anonymizeDeviceFingerprint(deviceId),
        'displayName': displayName,
        'lat': latitude,
        'lng': longitude,
        'accuracyMeters': accuracyMeters,
        'batteryPct': batteryPct,
        'appState': appState,
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

  static String anonymizeDeviceFingerprint(String rawIdentifier) {
    final segments = rawIdentifier
        .toUpperCase()
        .replaceAll('-', ':')
        .split(':');
    if (segments.length < 6) {
      final cleaned = rawIdentifier.replaceAll(RegExp(r'[^A-Za-z0-9]'), '');
      if (cleaned.length <= 4) {
        return cleaned.padRight(4, 'X');
      }
      return '${cleaned.substring(0, cleaned.length - 4)}XXXX';
    }
    final normalized = [...segments.take(4), '00', '00'];
    return normalized.join(':');
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
      MeshPayloadType.incidentReport || MeshPayloadType.locationBeacon => 3,
      MeshPayloadType.syncAck => 4,
    };
  }

  void dispose() {
    _locationBeaconTimer?.cancel();
    unawaited(_platformSubscription?.cancel());
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

  static String? _normalizeTopologyRole(String? role) {
    if (role == null) {
      return null;
    }
    return switch (role.trim().toLowerCase()) {
      'citizen' => 'citizen',
      'department' => 'department',
      'municipality' => 'municipality',
      _ => null,
    };
  }
}
