import 'dart:async';

import 'package:dispatch_mobile/core/services/location_service.dart';
import 'package:dispatch_mobile/core/services/mesh_transport_service.dart';
import 'package:dispatch_mobile/core/services/realtime_service.dart';
import 'package:dispatch_mobile/core/state/mesh_providers.dart';
import 'package:dispatch_mobile/core/state/session.dart';
import 'package:dispatch_mobile/core/theme/dispatch_colors.dart' as dc;
import 'package:dispatch_mobile/features/citizen/presentation/citizen_feed_detail_screen.dart';
import 'package:dispatch_mobile/features/citizen/presentation/citizen_report_detail_screen.dart';
import 'package:dispatch_mobile/features/citizen/presentation/citizen_report_form_screen.dart';
import 'package:dispatch_mobile/features/mesh/presentation/mesh_people_map_screen.dart';
import 'package:dispatch_mobile/features/mesh/presentation/offline_comms_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';

const _fallbackFloodImageUrl =
    'https://lh3.googleusercontent.com/aida-public/AB6AXuBpbdu1Cxzplfb2Wsq2Q0DKA_FgJIXWmv3NzeMic3oPqqwv-DZ4Ob38QfCn8ng1PiyYWp6CN9uzdrZxZYPgJRearFtdgZKLY2lExm9JJBkLNNDZi0voeEs2BulX_Sc8j_V0VL704Eo2E6u-bJhib8viFwzju63sIN9VLV6duttt-sOJLf-egMOwVG-CYpjeSn1wHqLK4HNhlIXBAmQD6ez-ah_TaJdBMmPkP41GDtYyQwX7lbcun5xF3JtYgk7NTn5ny59etC0zzSE';
const _fallbackMapImageUrl =
    'https://lh3.googleusercontent.com/aida-public/AB6AXuBZPIXpRXkI-oBG7Kl5O5x7L9G2ud9R9ErTbYyZE_aShaXbaFIJcx0pzsd-G1mKSQ0JBClUVUrvGlHQBPv7exYpqVszFGIfsfrys4KSjgTxpnnM6CYMbPuM9D7ptV6Hy8JBRMtNQoha5qiBd613DNK2eGEh00NqB4jiACe7yMFmJTojA6XzxS7h-cfgKAazZwt07DTSN1cKRkhuj1JNbWZP_iLzzcvgvPTAtsJoOZhsFBUrJWzXa6uNuTy_2X7oxnDzybXPzxkifO4';

class CitizenFeedScreen extends ConsumerStatefulWidget {
  const CitizenFeedScreen({super.key, this.onOpenMapTab, this.onOpenNodesTab});

  final VoidCallback? onOpenMapTab;
  final VoidCallback? onOpenNodesTab;

  @override
  ConsumerState<CitizenFeedScreen> createState() => _CitizenFeedScreenState();
}

class _CitizenFeedScreenState extends ConsumerState<CitizenFeedScreen> {
  static const _tabLabels = ['All Reports', 'Disaster', 'Messages'];

  final List<RealtimeSubscriptionHandle> _subscriptions = [];
  int _selectedTab = 0;
  bool _loading = true;
  List<Map<String, dynamic>> _posts = const [];
  List<Map<String, dynamic>> _reports = const [];
  List<Map<String, dynamic>> _topologyNodes = const [];
  List<MeshInboxItem> _inboxItems = const [];
  LocationData? _location;

  @override
  void initState() {
    super.initState();
    _fetchFeed();
    _subscribeToRealtime();
  }

  @override
  void dispose() {
    for (final subscription in _subscriptions) {
      unawaited(subscription.dispose());
    }
    super.dispose();
  }

  void _subscribeToRealtime() {
    final realtime = ref.read(realtimeServiceProvider);
    _subscriptions.addAll([
      realtime.subscribeToTable(
        table: 'posts',
        onChange: () {
          if (mounted) {
            unawaited(_fetchFeed(showLoader: false));
          }
        },
      ),
      realtime.subscribeToTable(
        table: 'incident_reports',
        onChange: () {
          if (mounted) {
            unawaited(_fetchFeed(showLoader: false));
          }
        },
      ),
    ]);
  }

  Future<void> _fetchFeed({bool showLoader = true}) async {
    if (showLoader && mounted) {
      setState(() => _loading = true);
    }

    try {
      final auth = ref.read(authServiceProvider);
      final transport = ref.read(meshTransportProvider);
      final results = await Future.wait<Object?>([
        auth.getCitizenMeshFeedSnapshot(),
        ref.read(locationServiceProvider).getCurrentPosition(),
      ]);
      final snapshot = results[0] as Map<String, dynamic>;
      final meshMessages =
          (snapshot['mesh_messages'] as List<dynamic>? ?? const <dynamic>[])
              .cast<Map<String, dynamic>>();
      final meshPosts =
          (snapshot['mesh_posts'] as List<dynamic>? ?? const <dynamic>[])
              .cast<Map<String, dynamic>>();
      transport.ingestServerMessages(meshMessages);
      transport.ingestServerMeshPosts(meshPosts);
      if (!mounted) {
        return;
      }
      setState(() {
        _posts = (snapshot['posts'] as List<dynamic>? ?? const <dynamic>[])
            .cast<Map<String, dynamic>>();
        _reports = (snapshot['reports'] as List<dynamic>? ?? const <dynamic>[])
            .cast<Map<String, dynamic>>();
        _topologyNodes =
            (snapshot['topology_nodes'] as List<dynamic>? ?? const <dynamic>[])
                .cast<Map<String, dynamic>>();
        _inboxItems = transport.inboxItems;
        _location = results[1] as LocationData?;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _inboxItems = ref.read(meshTransportProvider).inboxItems;
        _loading = false;
      });
    }
  }

  Future<void> _openReportComposer() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const CitizenReportFormScreen()));
    await _fetchFeed(showLoader: false);
  }

  Future<void> _openBroadcastComposer() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const OfflineCommsScreen()));
    await _fetchFeed(showLoader: false);
  }

  Future<void> _openStory(_FeedStory story) async {
    switch (story.type) {
      case _FeedStoryType.report:
        if (story.routeId == null || story.routeId!.isEmpty) {
          return;
        }
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => CitizenReportDetailScreen(reportId: story.routeId!),
          ),
        );
      case _FeedStoryType.post:
        if (story.routeId == null || story.routeId!.isEmpty) {
          return;
        }
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => CitizenFeedDetailScreen(postId: story.routeId!),
          ),
        );
      case _FeedStoryType.meshPost:
        await _openBroadcastComposer();
    }
    await _fetchFeed(showLoader: false);
  }

  Future<void> _handleHeroAction(_FeedStory story) async {
    await _openStory(story);
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Critical alert opened for full details.'),
        duration: Duration(seconds: 1),
      ),
    );
  }

  Future<void> _openMap() async {
    if (widget.onOpenMapTab != null) {
      widget.onOpenMapTab!.call();
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const MeshPeopleMapScreen(
          title: 'Mesh Feed Map',
          subtitle: 'Interactive map',
          allowResolveActions: false,
          allowCompassActions: true,
        ),
      ),
    );
  }

  List<MeshInboxItem> get _meshMessages {
    final items = _inboxItems
        .where((item) => item.itemType == 'mesh_message')
        .toList(growable: false);
    items.sort(
      (a, b) => _parseDate(b.createdAt).compareTo(_parseDate(a.createdAt)),
    );
    return items;
  }

  List<_FeedStory> _buildStories() {
    final stories = <_FeedStory>[];
    final seenKeys = <String>{};
    for (final post in _posts) {
      final story = _FeedStory.fromPost(post);
      final dedupeKey = '${story.title}|${story.body}';
      if (seenKeys.add(dedupeKey)) {
        stories.add(story);
      }
    }
    for (final report in _reports) {
      final story = _FeedStory.fromReport(report);
      final dedupeKey = '${story.title}|${story.body}|${story.createdAt}';
      if (seenKeys.add(dedupeKey)) {
        stories.add(story);
      }
    }
    for (final item in _inboxItems.where(
      (entry) => entry.itemType == 'mesh_post',
    )) {
      final story = _FeedStory.fromMeshPost(item);
      final dedupeKey = '${story.title}|${story.body}';
      if (seenKeys.add(dedupeKey)) {
        stories.add(story);
      }
    }
    stories.sort((a, b) {
      final priority = _storyPriority(b).compareTo(_storyPriority(a));
      if (priority != 0) {
        return priority;
      }
      return _parseDate(b.createdAt).compareTo(_parseDate(a.createdAt));
    });
    return stories;
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionControllerProvider);
    final transport = ref.read(meshTransportProvider);
    final stories = _buildStories();
    final heroStory =
        _firstWhereOrNull(stories, _isCriticalStory) ?? _fallbackHeroStory;
    final secondaryStory =
        _firstOrNull(stories.where((story) => story.id != heroStory.id)) ??
        _fallbackIncidentStory;
    final disasterStories = stories
        .where(_isDisasterStory)
        .toList(growable: false);
    final remoteMessageItem = _firstWhereOrNull(
      _meshMessages,
      (item) => !_isLocalMessage(
        item,
        fullName: session.fullName,
        email: session.email,
      ),
    );
    final localMessageItem = _firstWhereOrNull(
      _meshMessages,
      (item) => _isLocalMessage(
        item,
        fullName: session.fullName,
        email: session.email,
      ),
    );
    final remoteMessage = _messagePreviewFromItem(
      remoteMessageItem,
      fallback: _fallbackRemoteMessage,
      isLocal: false,
    );
    final localMessage = _messagePreviewFromItem(
      localMessageItem,
      fallback: _fallbackLocalMessage,
      isLocal: true,
    );
    final nodeCount = _topologyNodes.isNotEmpty
        ? _topologyNodes.length
        : transport.peerCount > 0
        ? transport.peerCount
        : 42;
    final updateCount = _meshMessages.isNotEmpty ? _meshMessages.length : 3;

    if (_loading && _posts.isEmpty && _reports.isEmpty && _inboxItems.isEmpty) {
      return Container(
        color: dc.background,
        alignment: Alignment.center,
        child: const CircularProgressIndicator(color: dc.primary),
      );
    }

    final content = switch (_selectedTab) {
      0 => _buildAllReportsContent(
        heroStory: heroStory,
        secondaryStory: secondaryStory,
        remoteMessage: remoteMessage,
        localMessage: localMessage,
        nodeCount: nodeCount,
        updateCount: updateCount,
      ),
      1 => _buildDisasterContent(
        disasterStories: disasterStories,
        fallbackHero: heroStory,
        updateCount: updateCount,
        nodeCount: nodeCount,
      ),
      _ => _buildMessagesContent(
        sessionName: session.fullName,
        sessionEmail: session.email,
        updateCount: updateCount,
        nodeCount: nodeCount,
      ),
    };

    return Stack(
      children: [
        Container(color: dc.background),
        Column(
          children: [
            SafeArea(
              bottom: false,
              child: _FeedTopBar(
                onMenuTap: widget.onOpenNodesTab,
                onStatusTap: () => _fetchFeed(showLoader: false),
              ),
            ),
            _FeedTabBar(
              labels: _tabLabels,
              selectedIndex: _selectedTab,
              onSelected: (index) => setState(() => _selectedTab = index),
            ),
            Expanded(
              child: RefreshIndicator(
                color: dc.primary,
                onRefresh: () => _fetchFeed(),
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 144),
                  children: content,
                ),
              ),
            ),
          ],
        ),
        Positioned(
          right: 24,
          bottom: 104,
          child: _BroadcastReportButton(onTap: _openReportComposer),
        ),
      ],
    );
  }

  List<Widget> _buildAllReportsContent({
    required _FeedStory heroStory,
    required _FeedStory secondaryStory,
    required _FeedMessageData remoteMessage,
    required _FeedMessageData localMessage,
    required int nodeCount,
    required int updateCount,
  }) {
    return [
      _CriticalAlertCard(
        story: heroStory,
        timeLabel: _timeAgo(heroStory.createdAt),
        distanceLabel: _distanceLabel(heroStory),
        onTap: () => _openStory(heroStory),
        onAction: () => _handleHeroAction(heroStory),
      ),
      const SizedBox(height: 18),
      _MeshMessageBubble(message: remoteMessage),
      const SizedBox(height: 18),
      _IncidentStoryCard(
        story: secondaryStory,
        updateCount: updateCount,
        severityLabel: _storySeverityLabel(secondaryStory),
        onTap: () => _openStory(secondaryStory),
        onBroadcast: _openBroadcastComposer,
        onUpdates: () => setState(() => _selectedTab = 2),
      ),
      const SizedBox(height: 18),
      _MeshMessageBubble(message: localMessage),
      const SizedBox(height: 18),
      _MapSnapshotCard(nodeCount: nodeCount, onOpenMap: _openMap),
    ];
  }

  List<Widget> _buildDisasterContent({
    required List<_FeedStory> disasterStories,
    required _FeedStory fallbackHero,
    required int updateCount,
    required int nodeCount,
  }) {
    final stories = disasterStories.isNotEmpty
        ? disasterStories.take(5).toList(growable: false)
        : <_FeedStory>[fallbackHero, _fallbackIncidentStory];
    return [
      _CriticalAlertCard(
        story: stories.first,
        timeLabel: _timeAgo(stories.first.createdAt),
        distanceLabel: _distanceLabel(stories.first),
        onTap: () => _openStory(stories.first),
        onAction: () => _handleHeroAction(stories.first),
      ),
      for (final story in stories.skip(1)) ...[
        const SizedBox(height: 18),
        _IncidentStoryCard(
          story: story,
          updateCount: updateCount,
          severityLabel: _storySeverityLabel(story),
          onTap: () => _openStory(story),
          onBroadcast: _openBroadcastComposer,
          onUpdates: () => setState(() => _selectedTab = 2),
        ),
      ],
      const SizedBox(height: 18),
      _MapSnapshotCard(nodeCount: nodeCount, onOpenMap: _openMap),
    ];
  }

  List<Widget> _buildMessagesContent({
    required String? sessionName,
    required String? sessionEmail,
    required int updateCount,
    required int nodeCount,
  }) {
    final items = _inboxItems
        .where(
          (item) =>
              item.itemType == 'mesh_message' || item.itemType == 'mesh_post',
        )
        .take(8)
        .toList(growable: false);
    final widgets = <Widget>[];
    if (items.isEmpty) {
      widgets
        ..add(_MeshMessageBubble(message: _fallbackRemoteMessage))
        ..add(const SizedBox(height: 18))
        ..add(_MeshMessageBubble(message: _fallbackLocalMessage));
    } else {
      for (final item in items) {
        if (item.itemType == 'mesh_post') {
          final story = _FeedStory.fromMeshPost(item);
          widgets.add(
            _IncidentStoryCard(
              story: story,
              updateCount: updateCount,
              severityLabel: _storySeverityLabel(story),
              onTap: _openBroadcastComposer,
              onBroadcast: _openBroadcastComposer,
              onUpdates: () => setState(() => _selectedTab = 2),
            ),
          );
        } else {
          final isLocal = _isLocalMessage(
            item,
            fullName: sessionName,
            email: sessionEmail,
          );
          widgets.add(
            _MeshMessageBubble(
              message: _messagePreviewFromItem(
                item,
                fallback: isLocal
                    ? _fallbackLocalMessage
                    : _fallbackRemoteMessage,
                isLocal: isLocal,
              ),
            ),
          );
        }
        widgets.add(const SizedBox(height: 18));
      }
      if (widgets.isNotEmpty) {
        widgets.removeLast();
      }
    }
    widgets
      ..add(const SizedBox(height: 18))
      ..add(_MapSnapshotCard(nodeCount: nodeCount, onOpenMap: _openMap));
    return widgets;
  }

  bool _isLocalMessage(
    MeshInboxItem item, {
    required String? fullName,
    required String? email,
  }) {
    final author = item.authorDisplayName.trim().toLowerCase();
    final name = fullName?.trim().toLowerCase();
    final userEmail = email?.trim().toLowerCase();
    return item.needsServerSync ||
        author == 'you' ||
        author == 'local node' ||
        (name != null && name.isNotEmpty && author == name) ||
        (userEmail != null && userEmail.isNotEmpty && author == userEmail);
  }

  _FeedMessageData _messagePreviewFromItem(
    MeshInboxItem? item, {
    required _FeedMessageData fallback,
    required bool isLocal,
  }) {
    if (item == null) {
      return fallback;
    }
    final sender = isLocal
        ? 'YOU (LOCAL NODE)'
        : _senderLabel(item.authorDisplayName, item.authorRole);
    return _FeedMessageData(
      senderLabel: sender,
      timeLabel: _clockTime(item.createdAt),
      body: item.body.isEmpty ? fallback.body : item.body,
      isLocal: isLocal,
    );
  }

  String _senderLabel(String displayName, String role) {
    final normalizedName = displayName.trim().isEmpty
        ? 'Mesh Node'
        : displayName.trim();
    final normalizedRole = role.trim().isEmpty || role.trim() == 'anonymous'
        ? ''
        : ' (${role.trim().toUpperCase()})';
    return '${normalizedName.toUpperCase()}$normalizedRole';
  }

  bool _isCriticalStory(_FeedStory story) {
    final severity = (story.severity ?? '').toLowerCase();
    final category = story.category.toLowerCase();
    return story.isPinned ||
        severity == 'critical' ||
        severity == 'high' ||
        category == 'alert' ||
        category == 'warning' ||
        category == 'flood' ||
        category == 'fire' ||
        category == 'earthquake' ||
        category == 'medical' ||
        category == 'structural';
  }

  bool _isDisasterStory(_FeedStory story) {
    final category = story.category.toLowerCase();
    return _isCriticalStory(story) ||
        story.type == _FeedStoryType.report ||
        category == 'situational_report' ||
        category == 'road_accident';
  }

  int _storyPriority(_FeedStory story) {
    var score = 0;
    if (story.isPinned) score += 4;
    switch ((story.severity ?? '').toLowerCase()) {
      case 'critical':
        score += 4;
      case 'high':
        score += 3;
      case 'medium':
        score += 2;
      case 'low':
        score += 1;
    }
    switch (story.category.toLowerCase()) {
      case 'alert':
      case 'warning':
      case 'flood':
      case 'fire':
      case 'earthquake':
      case 'medical':
      case 'structural':
        score += 3;
      case 'situational_report':
      case 'road_accident':
        score += 2;
      case 'update':
      case 'safety_tip':
        score += 1;
    }
    if (story.type == _FeedStoryType.report) score += 1;
    return score;
  }

  String _storySeverityLabel(_FeedStory story) {
    final severity = (story.severity ?? '').trim();
    if (severity.isNotEmpty) {
      return _titleCase(severity);
    }
    return switch (story.category.toLowerCase()) {
      'alert' => 'Critical',
      'warning' => 'Moderate',
      'situational_report' => 'Update',
      _ => 'Moderate',
    };
  }

  String _distanceLabel(_FeedStory story) {
    if (story.latitude != null &&
        story.longitude != null &&
        _location != null) {
      const calculator = Distance();
      final meters = calculator.as(
        LengthUnit.Meter,
        LatLng(_location!.latitude, _location!.longitude),
        LatLng(story.latitude!, story.longitude!),
      );
      if (meters >= 1000) {
        return '${(meters / 1000).toStringAsFixed(1)}km from your current node';
      }
      return '${meters.round()}m from your current node';
    }
    if ((story.address ?? '').trim().isNotEmpty) {
      return story.address!.trim();
    }
    return 'Near your current node';
  }

  String _timeAgo(String raw) {
    final parsed = _tryParseDate(raw);
    if (parsed == null) return raw.isEmpty ? 'Now' : raw;
    final diff = DateTime.now().difference(parsed);
    if (diff.inMinutes < 1) return 'Now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  String _clockTime(String raw) {
    final parsed = _tryParseDate(raw);
    if (parsed == null) return raw.isEmpty ? '12:45 PM' : raw;
    return DateFormat('h:mm a').format(parsed);
  }

  String _titleCase(String value) {
    if (value.trim().isEmpty) return value;
    return value
        .split(' ')
        .where((part) => part.isNotEmpty)
        .map(
          (part) =>
              '${part[0].toUpperCase()}${part.substring(1).toLowerCase()}',
        )
        .join(' ');
  }

  DateTime _parseDate(String raw) {
    return _tryParseDate(raw) ?? DateTime.fromMillisecondsSinceEpoch(0);
  }

  DateTime? _tryParseDate(String raw) {
    final parsed = DateTime.tryParse(raw);
    return parsed?.toLocal();
  }
}

class _FeedTopBar extends StatelessWidget {
  const _FeedTopBar({this.onMenuTap, this.onStatusTap});

  final VoidCallback? onMenuTap;
  final VoidCallback? onStatusTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 4),
      child: Row(
        children: [
          _HeaderIconButton(icon: Icons.menu, onTap: onMenuTap),
          const Expanded(
            child: Text(
              'Mesh Feed',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: dc.onSurface,
              ),
            ),
          ),
          _StatusHaloButton(onTap: onStatusTap),
        ],
      ),
    );
  }
}

class _HeaderIconButton extends StatelessWidget {
  const _HeaderIconButton({required this.icon, this.onTap});

  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: SizedBox(
          width: 40,
          height: 40,
          child: Icon(icon, color: dc.onSurface, size: 22),
        ),
      ),
    );
  }
}

class _StatusHaloButton extends StatefulWidget {
  const _StatusHaloButton({this.onTap});

  final VoidCallback? onTap;

  @override
  State<_StatusHaloButton> createState() => _StatusHaloButtonState();
}

class _StatusHaloButtonState extends State<_StatusHaloButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1700),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final scale = 0.92 + (_controller.value * 0.16);
        final opacity = 0.08 + (_controller.value * 0.16);
        return Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: widget.onTap,
            borderRadius: BorderRadius.circular(999),
            child: SizedBox(
              width: 40,
              height: 40,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Transform.scale(
                    scale: scale,
                    child: Container(
                      width: 26,
                      height: 26,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: dc.primary.withValues(alpha: opacity),
                      ),
                    ),
                  ),
                  const Icon(Icons.wifi_tethering, color: dc.primary, size: 20),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _FeedTabBar extends StatelessWidget {
  const _FeedTabBar({
    required this.labels,
    required this.selectedIndex,
    required this.onSelected,
  });

  final List<String> labels;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: dc.background.withValues(alpha: 0.95),
        border: Border(
          bottom: BorderSide(color: dc.outlineVariant.withValues(alpha: 0.3)),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          for (var index = 0; index < labels.length; index++)
            Padding(
              padding: EdgeInsets.only(
                right: index == labels.length - 1 ? 0 : 24,
              ),
              child: InkWell(
                onTap: () => onSelected(index),
                child: Container(
                  padding: const EdgeInsets.only(top: 14, bottom: 12),
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(
                        color: selectedIndex == index
                            ? dc.primary
                            : Colors.transparent,
                        width: 3,
                      ),
                    ),
                  ),
                  child: Text(
                    labels[index],
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: selectedIndex == index
                          ? dc.onSurface
                          : dc.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _CriticalAlertCard extends StatelessWidget {
  const _CriticalAlertCard({
    required this.story,
    required this.timeLabel,
    required this.distanceLabel,
    required this.onTap,
    required this.onAction,
  });

  final _FeedStory story;
  final String timeLabel;
  final String distanceLabel;
  final VoidCallback onTap;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: dc.errorContainer.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(18),
            border: Border(left: BorderSide(color: dc.error, width: 4)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: dc.error,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: const Text(
                      'CRITICAL ALERT',
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.2,
                        color: dc.onError,
                      ),
                    ),
                  ),
                  const Spacer(),
                  Text(
                    timeLabel,
                    style: const TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 12,
                      color: dc.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: AspectRatio(
                  aspectRatio: 16 / 9,
                  child: Image.network(
                    story.imageUrl ?? _fallbackFloodImageUrl,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) => Container(
                      color: dc.primaryContainer,
                      alignment: Alignment.center,
                      child: const Icon(
                        Icons.flood,
                        color: dc.primary,
                        size: 36,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                story.title,
                style: const TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 24,
                  height: 1.15,
                  fontWeight: FontWeight.w800,
                  color: dc.onSurface,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                story.body.isEmpty
                    ? 'Immediate evacuation advised for nearby residents. Stay alert for route updates from responders.'
                    : story.body,
                style: const TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 14,
                  height: 1.45,
                  color: dc.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  const Icon(Icons.location_on, color: dc.error, size: 16),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      distanceLabel,
                      style: const TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: dc.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: onAction,
                  style: FilledButton.styleFrom(
                    backgroundColor: dc.error,
                    foregroundColor: dc.onError,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: const Text(
                    'MARK AS SAFE / ACKNOWLEDGE',
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.6,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MeshMessageBubble extends StatelessWidget {
  const _MeshMessageBubble({required this.message});

  final _FeedMessageData message;

  @override
  Widget build(BuildContext context) {
    final alignment = message.isLocal
        ? CrossAxisAlignment.end
        : CrossAxisAlignment.start;
    final rowAlignment = message.isLocal
        ? MainAxisAlignment.end
        : MainAxisAlignment.start;
    final bubbleColor = message.isLocal ? dc.primary : dc.surfaceContainerLow;
    final textColor = message.isLocal ? dc.onPrimary : dc.onSurface;
    final metaColor = message.isLocal ? dc.primary : dc.onSurfaceVariant;
    final borderRadius = message.isLocal
        ? const BorderRadius.only(
            topLeft: Radius.circular(18),
            topRight: Radius.circular(6),
            bottomLeft: Radius.circular(18),
            bottomRight: Radius.circular(18),
          )
        : const BorderRadius.only(
            topLeft: Radius.circular(6),
            topRight: Radius.circular(18),
            bottomLeft: Radius.circular(18),
            bottomRight: Radius.circular(18),
          );
    return Column(
      crossAxisAlignment: alignment,
      children: [
        Row(
          mainAxisAlignment: rowAlignment,
          children: [
            if (!message.isLocal)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: dc.surfaceContainerHigh,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.account_circle,
                    color: dc.primary,
                    size: 18,
                  ),
                ),
              ),
            Flexible(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: message.isLocal
                    ? [
                        Text(
                          message.timeLabel,
                          style: const TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 10,
                            color: dc.outline,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          message.senderLabel,
                          style: TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.4,
                            color: metaColor,
                          ),
                        ),
                      ]
                    : [
                        Text(
                          message.senderLabel,
                          style: TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.4,
                            color: metaColor,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          message.timeLabel,
                          style: const TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 10,
                            color: dc.outline,
                          ),
                        ),
                      ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Container(
          constraints: const BoxConstraints(maxWidth: 290),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: bubbleColor,
            borderRadius: borderRadius,
            boxShadow: message.isLocal
                ? [
                    BoxShadow(
                      color: dc.primary.withValues(alpha: 0.18),
                      blurRadius: 14,
                      offset: const Offset(0, 6),
                    ),
                  ]
                : null,
          ),
          child: Text(
            message.body,
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 14,
              height: 1.45,
              color: textColor,
            ),
          ),
        ),
      ],
    );
  }
}

class _IncidentStoryCard extends StatelessWidget {
  const _IncidentStoryCard({
    required this.story,
    required this.updateCount,
    required this.severityLabel,
    required this.onTap,
    required this.onBroadcast,
    required this.onUpdates,
  });

  final _FeedStory story;
  final int updateCount;
  final String severityLabel;
  final VoidCallback onTap;
  final VoidCallback onBroadcast;
  final VoidCallback onUpdates;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: dc.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(
                color: dc.onSurface.withValues(alpha: 0.04),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: dc.primaryContainer,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  _storyCategoryIcon(story.category),
                  color: dc.primary,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            story.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontFamily: 'Inter',
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: dc.onSurface,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: dc.surfaceContainerHigh,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            severityLabel,
                            style: const TextStyle(
                              fontFamily: 'Inter',
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: dc.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      story.body.isEmpty
                          ? 'Waiting for field updates.'
                          : story.body,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 12,
                        height: 1.45,
                        color: dc.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        TextButton.icon(
                          onPressed: onBroadcast,
                          style: TextButton.styleFrom(
                            foregroundColor: dc.primary,
                            padding: EdgeInsets.zero,
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          icon: const Icon(Icons.share, size: 16),
                          label: const Text(
                            'BROADCAST',
                            style: TextStyle(
                              fontFamily: 'Inter',
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        TextButton.icon(
                          onPressed: onUpdates,
                          style: TextButton.styleFrom(
                            foregroundColor: dc.onSurfaceVariant,
                            padding: EdgeInsets.zero,
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          icon: const Icon(Icons.chat_bubble_outline, size: 16),
                          label: Text(
                            '$updateCount UPDATES',
                            style: const TextStyle(
                              fontFamily: 'Inter',
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  IconData _storyCategoryIcon(String category) {
    return switch (category) {
      'flood' => Icons.flood,
      'fire' => Icons.local_fire_department,
      'earthquake' => Icons.vibration,
      'medical' => Icons.medical_services,
      'structural' => Icons.home_repair_service,
      'warning' => Icons.warning_amber,
      'alert' => Icons.campaign,
      _ => Icons.electrical_services,
    };
  }
}

class _MapSnapshotCard extends StatelessWidget {
  const _MapSnapshotCard({required this.nodeCount, required this.onOpenMap});

  final int nodeCount;
  final VoidCallback onOpenMap;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: dc.surfaceContainerLow,
        borderRadius: BorderRadius.circular(18),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Column(
          children: [
            Stack(
              children: [
                SizedBox(
                  height: 168,
                  width: double.infinity,
                  child: Image.network(
                    _fallbackMapImageUrl,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) => Container(
                      color: dc.surfaceContainerHigh,
                      alignment: Alignment.center,
                      child: const Icon(Icons.map, color: dc.primary, size: 36),
                    ),
                  ),
                ),
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: [
                          dc.onSurface.withValues(alpha: 0.1),
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Interactive Mesh Topology',
                          style: TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: dc.onSurface,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '$nodeCount Active Nodes in this sector',
                          style: const TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 10,
                            color: dc.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  TextButton(
                    onPressed: onOpenMap,
                    style: TextButton.styleFrom(
                      foregroundColor: dc.primary,
                      padding: EdgeInsets.zero,
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: const Text(
                      'OPEN MAP',
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BroadcastReportButton extends StatelessWidget {
  const _BroadcastReportButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Ink(
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [dc.primary, dc.primaryDim],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
            borderRadius: BorderRadius.circular(999),
            boxShadow: [
              BoxShadow(
                color: dc.onSurface.withValues(alpha: 0.08),
                blurRadius: 26,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.campaign, color: dc.onPrimary, size: 18),
                SizedBox(width: 8),
                Text(
                  'BROADCAST REPORT',
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: dc.onPrimary,
                    letterSpacing: 0.4,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

enum _FeedStoryType { post, report, meshPost }

class _FeedStory {
  const _FeedStory({
    required this.id,
    required this.type,
    required this.title,
    required this.body,
    required this.category,
    required this.createdAt,
    this.routeId,
    this.imageUrl,
    this.latitude,
    this.longitude,
    this.address,
    this.severity,
    this.isPinned = false,
  });

  factory _FeedStory.fromPost(Map<String, dynamic> post) {
    final title = (post['title'] as String? ?? '').trim();
    final body = (post['content'] as String? ?? '').trim();
    final category = (post['category'] as String? ?? 'update').trim();
    final images =
        (post['image_urls'] as List?)?.whereType<String>().toList() ??
        const <String>[];
    return _FeedStory(
      id: 'post-${post['id'] ?? title.hashCode}',
      type: _FeedStoryType.post,
      title: title.isEmpty ? _defaultPostTitle(category) : title,
      body: body,
      category: category,
      createdAt: post['created_at'] as String? ?? '',
      routeId: post['id']?.toString(),
      imageUrl: images.isEmpty ? null : images.first,
      isPinned: post['is_pinned'] == true,
    );
  }

  factory _FeedStory.fromReport(Map<String, dynamic> report) {
    final description = (report['description'] as String? ?? '').trim();
    final lines = description
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList(growable: false);
    final category = (report['category'] as String? ?? 'report').trim();
    final images =
        (report['image_urls'] as List?)?.whereType<String>().toList() ??
        const <String>[];
    return _FeedStory(
      id: 'report-${report['id'] ?? description.hashCode}',
      type: _FeedStoryType.report,
      title: lines.isNotEmpty ? lines.first : _defaultReportTitle(category),
      body: lines.length > 1 ? lines.skip(1).join(' ') : description,
      category: category,
      createdAt: report['created_at'] as String? ?? '',
      routeId: report['id']?.toString(),
      imageUrl: images.isEmpty ? null : images.first,
      latitude: (report['latitude'] as num?)?.toDouble(),
      longitude: (report['longitude'] as num?)?.toDouble(),
      address: report['address'] as String?,
      severity: report['severity'] as String?,
      isPinned:
          ((report['severity'] as String?) ?? '').toLowerCase() == 'critical',
    );
  }

  factory _FeedStory.fromMeshPost(MeshInboxItem item) {
    final category = (item.category ?? 'update').trim();
    return _FeedStory(
      id: 'mesh-post-${item.messageId}',
      type: _FeedStoryType.meshPost,
      title: (item.title ?? '').trim().isEmpty
          ? _defaultPostTitle(category)
          : item.title!.trim(),
      body: item.body.trim(),
      category: category,
      createdAt: item.createdAt,
      routeId: item.id,
      isPinned: category == 'alert' || category == 'warning',
    );
  }

  final String id;
  final _FeedStoryType type;
  final String title;
  final String body;
  final String category;
  final String createdAt;
  final String? routeId;
  final String? imageUrl;
  final double? latitude;
  final double? longitude;
  final String? address;
  final String? severity;
  final bool isPinned;

  static String _defaultPostTitle(String category) {
    return switch (category) {
      'alert' => 'Critical Alert',
      'warning' => 'Emergency Warning',
      'safety_tip' => 'Safety Guidance',
      'situational_report' => 'Field Situation Report',
      _ => 'Department Update',
    };
  }

  static String _defaultReportTitle(String category) {
    return switch (category) {
      'flood' => 'Flash Flood Advisory',
      'fire' => 'Fire Response Needed',
      'earthquake' => 'Earthquake Damage Check',
      'medical' => 'Medical Assistance Needed',
      'road_accident' => 'Road Hazard Report',
      'structural' => 'Structural Damage Report',
      _ => 'Citizen Incident Report',
    };
  }
}

class _FeedMessageData {
  const _FeedMessageData({
    required this.senderLabel,
    required this.timeLabel,
    required this.body,
    required this.isLocal,
  });

  final String senderLabel;
  final String timeLabel;
  final String body;
  final bool isLocal;
}

const _fallbackHeroStory = _FeedStory(
  id: 'fallback-hero',
  type: _FeedStoryType.post,
  title: 'Flash Flood - Zone B (North Riverside)',
  body:
      'Immediate evacuation advised for all residents within 500m of the river bank. Water levels rising 15cm/hr.',
  category: 'alert',
  createdAt: '',
  imageUrl: _fallbackFloodImageUrl,
  isPinned: true,
);

const _fallbackIncidentStory = _FeedStory(
  id: 'fallback-incident',
  type: _FeedStoryType.report,
  title: 'Downed Power Lines',
  body: 'Oakwood Ave & 12th St intersection. Avoid area.',
  category: 'structural',
  createdAt: '',
  severity: 'moderate',
);

const _fallbackRemoteMessage = _FeedMessageData(
  senderLabel: 'NODE_742 (SUPPORT)',
  timeLabel: '12:45 PM',
  body:
      'Has anyone checked the bridge on 5th Street? We have a transport waiting to cross with medical supplies.',
  isLocal: false,
);

const _fallbackLocalMessage = _FeedMessageData(
  senderLabel: 'YOU (LOCAL NODE)',
  timeLabel: '12:48 PM',
  body: 'Checking 5th St bridge now. Will report back in 5 mins.',
  isLocal: true,
);

T? _firstOrNull<T>(Iterable<T> items) {
  for (final item in items) {
    return item;
  }
  return null;
}

T? _firstWhereOrNull<T>(Iterable<T> items, bool Function(T item) test) {
  for (final item in items) {
    if (test(item)) {
      return item;
    }
  }
  return null;
}
