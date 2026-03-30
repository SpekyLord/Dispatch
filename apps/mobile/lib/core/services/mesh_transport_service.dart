// Mesh transport - BLE discovery, WiFi Direct handoff, packet relay, and gateway sync.
// Uses nearby_connections API abstraction; actual plugin integration requires
// Android/iOS permissions and is tested via manual device-to-device field tests.

import 'dart:async';
import 'dart:convert';
import 'dart:math';

enum MeshNodeRole { origin, relay, gateway }

enum MeshPayloadType {
  incidentReport,
  announcement,
  distress,
  survivorSignal,
  statusUpdate,
  syncAck,
}

// canonical mesh packet envelope
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

  // payload type string for API
  String get payloadTypeString {
    return switch (payloadType) {
      MeshPayloadType.incidentReport => 'INCIDENT_REPORT',
      MeshPayloadType.announcement => 'ANNOUNCEMENT',
      MeshPayloadType.distress => 'DISTRESS',
      MeshPayloadType.survivorSignal => 'SURVIVOR_SIGNAL',
      MeshPayloadType.statusUpdate => 'STATUS_UPDATE',
      MeshPayloadType.syncAck => 'SYNC_ACK',
    };
  }

  // serialize to JSON map for transmission
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

  // deserialize from JSON map
  factory MeshPacket.fromJson(Map<String, dynamic> json) {
    final typeStr = json['payloadType'] as String? ?? '';
    final type = switch (typeStr) {
      'INCIDENT_REPORT' => MeshPayloadType.incidentReport,
      'ANNOUNCEMENT' => MeshPayloadType.announcement,
      'DISTRESS' => MeshPayloadType.distress,
      'SURVIVOR_SIGNAL' => MeshPayloadType.survivorSignal,
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

  // check if payload is above BLE threshold (10 KB)
  bool get requiresWifiDirect {
    final encoded = utf8.encode(jsonEncode(payload));
    return encoded.length > 10240;
  }
}

// peer info from discovery
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

class MeshTransportService {
  MeshNodeRole _role = MeshNodeRole.origin;
  final List<MeshPeer> _peers = [];
  final Set<String> _seenMessageIds = {};
  final List<MeshPacket> _outboundQueue = [];
  final StreamController<MeshPacket> _packetController =
      StreamController<MeshPacket>.broadcast();
  DateTime? _lastSyncTime;
  bool _isDiscovering = false;
  bool _hasInternet = false;
  bool _isSosBeaconBroadcasting = false;
  String? _sosBeaconDeviceId;

  // read-only accessors
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

  Future<void> initialize() async {
    // detect connectivity and set initial role
    _role = _hasInternet ? MeshNodeRole.gateway : MeshNodeRole.origin;
  }

  // start BLE discovery for nearby mesh peers
  Future<void> startDiscovery() async {
    _isDiscovering = true;
    // nearby_connections.startDiscovery() would be called here
    // on peer found: _onPeerDiscovered(endpointId, deviceName)
  }

  // stop discovery
  Future<void> stopDiscovery() async {
    _isDiscovering = false;
  }

  // update internet connectivity status
  void setConnectivity(bool hasInternet) {
    _hasInternet = hasInternet;
    if (hasInternet && _role != MeshNodeRole.gateway) {
      _role = MeshNodeRole.gateway;
    } else if (!hasInternet && _role == MeshNodeRole.gateway) {
      _role = MeshNodeRole.origin;
    }
  }

  // queue a packet for mesh broadcast
  void enqueuePacket(MeshPacket packet) {
    _outboundQueue.add(packet);
    _seenMessageIds.add(packet.messageId);
  }

  // receive an incoming packet from another peer
  bool receivePacket(MeshPacket packet) {
    // dedup: skip if already seen
    if (_seenMessageIds.contains(packet.messageId)) {
      return false;
    }
    _seenMessageIds.add(packet.messageId);

    // drop if hop limit exceeded
    if (packet.hopCount >= packet.maxHops) {
      return false;
    }

    // increment hop count for relay
    packet.hopCount++;

    // if we're a gateway, queue for server upload
    if (_role == MeshNodeRole.gateway) {
      _outboundQueue.add(packet);
    }

    _packetController.add(packet);

    // relay to other peers (would call nearby_connections.sendPayload)
    return true;
  }

  // get all queued packets for gateway upload
  List<MeshPacket> drainQueue() {
    final packets = List<MeshPacket>.from(_outboundQueue)
      ..sort(
        (a, b) =>
            _priorityFor(a.payloadType).compareTo(_priorityFor(b.payloadType)),
      );
    _outboundQueue.clear();
    _lastSyncTime = DateTime.now();
    return packets;
  }

  // process SYNC_ACK packets from server
  void processSyncAcks(List<Map<String, dynamic>> acks) {
    for (final ack in acks) {
      final msgId = ack['messageId'] as String? ?? '';
      if (msgId.isNotEmpty) {
        _seenMessageIds.add(msgId);
      }
    }
  }

  // handle peer discovery callback
  void onPeerDiscovered(String endpointId, String deviceName) {
    final existing = _peers.where((p) => p.endpointId == endpointId);
    if (existing.isNotEmpty) {
      existing.first.lastSeen = DateTime.now();
    } else {
      _peers.add(MeshPeer(endpointId: endpointId, deviceName: deviceName));
    }
  }

  // remove stale peers (not seen in last 5 minutes)
  void pruneStalePeers() {
    final cutoff = DateTime.now().subtract(const Duration(minutes: 5));
    _peers.removeWhere((p) => p.lastSeen.isBefore(cutoff));
  }

  void pruneStaleePeers() => pruneStalePeers();

  // decide transport: BLE for small, WiFi Direct for >10KB
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

  // estimate mesh reach based on peer count and avg hops
  int _estimateReach() {
    if (_peers.isEmpty) return 1;
    // rough estimate: each peer extends reach by ~2 devices
    return min(_peers.length * 2, 50);
  }

  // create a distress packet with maxHops=15, no login required
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
      maxHops: 15, // distress gets wider propagation
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

  // create an offline incident report packet
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

  // create an offline announcement packet (requires dept verification token)
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

  // imperative map builders to avoid use_null_aware_elements lint
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

  // Distress and survivor detection packets drain first so gateway uploads keep
  // life-safety traffic ahead of routine reports and acknowledgements.
  static int _priorityFor(MeshPayloadType payloadType) {
    return switch (payloadType) {
      MeshPayloadType.distress || MeshPayloadType.survivorSignal => 0,
      MeshPayloadType.statusUpdate => 1,
      MeshPayloadType.announcement => 2,
      MeshPayloadType.incidentReport => 3,
      MeshPayloadType.syncAck => 4,
    };
  }

  void dispose() {
    _packetController.close();
  }

  // simple uuid v4 generator
  static String _generateUuid() {
    final rng = Random();
    final bytes = List<int>.generate(16, (_) => rng.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40; // version 4
    bytes[8] = (bytes[8] & 0x3f) | 0x80; // variant 1
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-'
        '${hex.substring(20)}';
  }
}
