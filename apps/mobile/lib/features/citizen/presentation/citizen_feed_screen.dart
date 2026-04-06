import 'dart:async';

import 'package:dispatch_mobile/core/services/mesh_transport_service.dart';
import 'package:dispatch_mobile/core/services/realtime_service.dart';
import 'package:dispatch_mobile/core/state/mesh_providers.dart';
import 'package:dispatch_mobile/core/state/notification_inbox_controller.dart';
import 'package:dispatch_mobile/core/state/session.dart';
import 'package:dispatch_mobile/core/theme/dispatch_colors.dart' as dc;
import 'package:dispatch_mobile/features/citizen/presentation/citizen_department_profile_screen.dart';
import 'package:dispatch_mobile/features/citizen/presentation/citizen_feed_detail_screen.dart';
import 'package:dispatch_mobile/features/citizen/presentation/citizen_report_detail_screen.dart';
import 'package:dispatch_mobile/features/citizen/presentation/citizen_report_form_screen.dart';
import 'package:dispatch_mobile/features/mesh/presentation/offline_comms_screen.dart';
import 'package:dispatch_mobile/features/shared/presentation/notifications_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

enum CitizenFeedSegment { news, reports, messages }

const _feedCategories = <String>[
  'all',
  'alert',
  'warning',
  'safety_tip',
  'update',
  'situational_report',
];

class CitizenFeedScreen extends ConsumerStatefulWidget {
  const CitizenFeedScreen({
    super.key,
    this.onOpenMapTab,
    this.onOpenNodesTab,
    this.initialSegment = CitizenFeedSegment.news,
  });

  final VoidCallback? onOpenMapTab;
  final VoidCallback? onOpenNodesTab;
  final CitizenFeedSegment initialSegment;

  @override
  ConsumerState<CitizenFeedScreen> createState() => _CitizenFeedScreenState();
}

class _CitizenFeedScreenState extends ConsumerState<CitizenFeedScreen> {
  final List<RealtimeSubscriptionHandle> _subscriptions =
      <RealtimeSubscriptionHandle>[];
  final Set<String> _bookmarkedPostIds = <String>{};
  final TextEditingController _searchController = TextEditingController();

  late CitizenFeedSegment _segment;
  bool _loading = true;
  String? _loadError;
  String _searchQuery = '';
  String _newsCategory = 'all';
  String _reportStatus = 'all';
  String _reportCategory = 'all';
  List<Map<String, dynamic>> _posts = const <Map<String, dynamic>>[];
  List<Map<String, dynamic>> _reports = const <Map<String, dynamic>>[];

  @override
  void initState() {
    super.initState();
    _segment = widget.initialSegment;
    _fetchFeed();
    _subscribeToRealtime();
  }

  @override
  void dispose() {
    _searchController.dispose();
    for (final subscription in _subscriptions) {
      unawaited(subscription.dispose());
    }
    super.dispose();
  }

  bool get _isCitizen {
    return ref.read(sessionControllerProvider).role == AppRole.citizen;
  }

  void _subscribeToRealtime() {
    final realtime = ref.read(realtimeServiceProvider);
    _subscriptions.addAll([
      realtime.subscribeToTable(
        table: 'department_feed_posts',
        onChange: () {
          if (mounted) {
            unawaited(_fetchFeed(showLoader: false));
          }
        },
      ),
      realtime.subscribeToTable(
        table: 'department_feed_comment',
        onChange: () {
          if (mounted && _segment == CitizenFeedSegment.news) {
            unawaited(_fetchFeed(showLoader: false));
          }
        },
      ),
      realtime.subscribeToTable(
        table: 'department_feed_reactions',
        onChange: () {
          if (mounted && _segment == CitizenFeedSegment.news) {
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
      realtime.subscribeToTable(
        table: 'mesh_messages',
        onChange: () {
          if (mounted && _segment == CitizenFeedSegment.messages) {
            setState(() {});
          }
        },
      ),
    ]);
  }

  Future<void> _fetchFeed({bool showLoader = true}) async {
    if (showLoader && mounted) {
      setState(() {
        _loading = true;
        _loadError = null;
      });
    }

    try {
      final auth = ref.read(authServiceProvider);
      final transport = ref.read(meshTransportProvider);
      final snapshot = _isCitizen
          ? await auth.getCitizenMeshFeedSnapshot()
          : <String, dynamic>{'posts': await auth.getFeedPosts()};

      final posts = (snapshot['posts'] as List<dynamic>? ?? const <dynamic>[])
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList(growable: false);
      final reports =
          (snapshot['reports'] as List<dynamic>? ?? const <dynamic>[])
              .whereType<Map>()
              .map((item) => Map<String, dynamic>.from(item))
              .toList(growable: false);
      final meshMessages =
          (snapshot['mesh_messages'] as List<dynamic>? ?? const <dynamic>[])
              .whereType<Map>()
              .map((item) => Map<String, dynamic>.from(item))
              .toList(growable: false);
      final meshPosts =
          (snapshot['mesh_posts'] as List<dynamic>? ?? const <dynamic>[])
              .whereType<Map>()
              .map((item) => Map<String, dynamic>.from(item))
              .toList(growable: false);

      if (_isCitizen) {
        transport.ingestServerMessages(meshMessages);
        transport.ingestServerMeshPosts(meshPosts);
      }

      if (!mounted) {
        return;
      }

      setState(() {
        _posts = posts;
        _reports = reports;
        _loading = false;
        _loadError = null;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loading = false;
        _loadError = 'Unable to refresh the citizen feed right now.';
      });
    }
  }

  Future<void> _openNotifications() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const NotificationsScreen()));
  }

  Future<void> _openPost(_FeedPost post) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CitizenFeedDetailScreen(postId: post.id),
      ),
    );
    await _fetchFeed(showLoader: false);
  }

  Future<void> _openReport(_CitizenReport report) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CitizenReportDetailScreen(reportId: report.id),
      ),
    );
    await _fetchFeed(showLoader: false);
  }

  Future<void> _openReportComposer() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const CitizenReportFormScreen()));
    await _fetchFeed(showLoader: false);
  }

  Future<void> _openDepartmentProfile(_FeedPost post) async {
    final uploaderId = post.uploaderId;
    if (uploaderId == null || uploaderId.isEmpty) {
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CitizenDepartmentProfileScreen(uploaderId: uploaderId),
      ),
    );
  }

  Future<void> _toggleReaction(_FeedPost post) async {
    if (post.id.isEmpty) {
      return;
    }
    final previousPosts = _posts;
    final nextLiked = !post.likedByMe;
    final nextReaction = nextLiked
        ? post.reactionCount + 1
        : (post.reactionCount - 1).clamp(0, post.reactionCount);

    setState(() {
      _posts = [
        for (final item in _posts)
          if ((item['id'] ?? '').toString() == post.id)
            {...item, 'liked_by_me': nextLiked, 'reaction': nextReaction}
          else
            item,
      ];
    });

    try {
      final updated = await ref
          .read(authServiceProvider)
          .toggleFeedReaction(post.id);
      if (!mounted) {
        return;
      }
      setState(() {
        _posts = [
          for (final item in _posts)
            if ((item['id'] ?? '').toString() == post.id) updated else item,
        ];
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() => _posts = previousPosts);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Unable to update your reaction right now.'),
        ),
      );
    }
  }

  Future<void> _openComments(_FeedPost post) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _CommentsSheet(post: post),
    );
    await _fetchFeed(showLoader: false);
  }

  void _toggleBookmark(String postId) {
    setState(() {
      if (_bookmarkedPostIds.contains(postId)) {
        _bookmarkedPostIds.remove(postId);
      } else {
        _bookmarkedPostIds.add(postId);
      }
    });
  }

  List<_FeedPost> get _filteredPosts {
    final query = _searchQuery.trim().toLowerCase();
    return _posts
        .map(_FeedPost.fromJson)
        .where((post) {
          if (_newsCategory != 'all' && post.category != _newsCategory) {
            return false;
          }
          if (query.isEmpty) {
            return true;
          }
          final haystack = [
            post.title,
            post.content,
            post.categoryLabel,
            post.location ?? '',
            post.departmentName ?? '',
            post.departmentDescription ?? '',
          ].join(' ').toLowerCase();
          return haystack.contains(query);
        })
        .toList(growable: false);
  }

  List<_CitizenReport> get _filteredReports {
    final query = _searchQuery.trim().toLowerCase();
    return _reports
        .map(_CitizenReport.fromJson)
        .where((report) {
          if (_reportStatus != 'all' && report.status != _reportStatus) {
            return false;
          }
          if (_reportCategory != 'all' && report.category != _reportCategory) {
            return false;
          }
          if (query.isEmpty) {
            return true;
          }
          final haystack = [
            report.title,
            report.description,
            report.categoryLabel,
            report.statusLabel,
            report.address ?? '',
            report.severityLabel,
          ].join(' ').toLowerCase();
          return haystack.contains(query);
        })
        .toList(growable: false);
  }

  List<MeshInboxItem> get _meshItems {
    final items = ref.watch(meshTransportProvider).inboxItems.toList();
    items.sort((left, right) => right.createdAt.compareTo(left.createdAt));
    final query = _searchQuery.trim().toLowerCase();
    return items
        .where((item) {
          if (query.isEmpty) {
            return true;
          }
          final haystack = [
            item.title ?? '',
            item.body,
            item.authorDisplayName,
            item.category ?? '',
          ].join(' ').toLowerCase();
          return haystack.contains(query);
        })
        .toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionControllerProvider);
    final inbox = ref.watch(notificationInboxControllerProvider);
    final segments = _isCitizen
        ? const <CitizenFeedSegment>[
            CitizenFeedSegment.news,
            CitizenFeedSegment.reports,
            CitizenFeedSegment.messages,
          ]
        : const <CitizenFeedSegment>[CitizenFeedSegment.news];
    final availableSegment = segments.contains(_segment)
        ? _segment
        : CitizenFeedSegment.news;
    final profileSeed = (session.fullName ?? session.email ?? 'Dispatch')
        .trim();
    final profileInitial = profileSeed.isEmpty
        ? 'D'
        : profileSeed.substring(0, 1).toUpperCase();

    return Container(
      color: dc.background,
      child: SafeArea(
        child: RefreshIndicator(
          onRefresh: _fetchFeed,
          color: dc.primary,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 120),
            children: [
              Row(
                children: [
                  if (widget.onOpenNodesTab != null)
                    IconButton(
                      onPressed: widget.onOpenNodesTab,
                      icon: const Icon(Icons.menu_rounded, color: dc.primary),
                      tooltip: 'Open navigation',
                    )
                  else
                    const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _isCitizen ? 'Citizen feed' : 'Community feed',
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w800,
                            color: dc.ink,
                          ),
                        ),
                        Text(
                          _isCitizen
                              ? 'Track official advisories, your reports, and mesh updates from one place.'
                              : 'Browse the public Dispatch news stream.',
                          style: const TextStyle(
                            fontSize: 12,
                            height: 1.45,
                            color: dc.mutedInk,
                          ),
                        ),
                      ],
                    ),
                  ),
                  _NotificationIconButton(
                    unreadCount: inbox.unreadCount,
                    onTap: _openNotifications,
                  ),
                  const SizedBox(width: 10),
                  CircleAvatar(
                    radius: 20,
                    backgroundColor: dc.primaryDim,
                    child: Text(
                      profileInitial,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Container(
                decoration: BoxDecoration(
                  color: dc.surfaceContainerLowest,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x12000000),
                      blurRadius: 16,
                      offset: Offset(0, 8),
                    ),
                  ],
                ),
                child: TextField(
                  controller: _searchController,
                  onChanged: (value) => setState(() => _searchQuery = value),
                  decoration: const InputDecoration(
                    prefixIcon: Icon(
                      Icons.search_rounded,
                      color: dc.onSurfaceVariant,
                    ),
                    hintText: 'Search posts, reports, or mesh updates',
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 16,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              if (segments.length > 1) ...[
                SizedBox(
                  height: 42,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemBuilder: (context, index) {
                      final item = segments[index];
                      return _SegmentChip(
                        label: switch (item) {
                          CitizenFeedSegment.news => 'News',
                          CitizenFeedSegment.reports => 'My Reports',
                          CitizenFeedSegment.messages => 'Messages',
                        },
                        selected: availableSegment == item,
                        onTap: () => setState(() => _segment = item),
                      );
                    },
                    separatorBuilder: (context, index) =>
                        const SizedBox(width: 8),
                    itemCount: segments.length,
                  ),
                ),
                const SizedBox(height: 16),
              ],
              if (_loadError != null)
                Container(
                  margin: const EdgeInsets.only(bottom: 14),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: dc.errorContainer.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: dc.error.withValues(alpha: 0.12)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.wifi_tethering_error, color: dc.error),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _loadError!,
                          style: const TextStyle(color: dc.errorDim),
                        ),
                      ),
                    ],
                  ),
                ),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                child: switch (availableSegment) {
                  CitizenFeedSegment.news => _buildNews(context),
                  CitizenFeedSegment.reports => _buildReports(context),
                  CitizenFeedSegment.messages => _buildMessages(context),
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNews(BuildContext context) {
    final posts = _filteredPosts;
    return Column(
      key: const ValueKey<String>('news'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: dc.heroGradient,
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(28),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: const Text(
                      'DISPATCH NEWS',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '${posts.length} updates',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.84),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              const Text(
                'Official advisories and field notices',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  height: 1.08,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Pinned alerts stay at the top, while comments and reactions keep the response loop active.',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.86),
                  height: 1.45,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        SizedBox(
          height: 38,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemBuilder: (context, index) {
              final category = _feedCategories[index];
              return _FilterChip(
                label: category == 'all'
                    ? 'All'
                    : category.replaceAll('_', ' '),
                selected: _newsCategory == category,
                onTap: () => setState(() => _newsCategory = category),
              );
            },
            separatorBuilder: (context, index) => const SizedBox(width: 8),
            itemCount: _feedCategories.length,
          ),
        ),
        const SizedBox(height: 18),
        if (_loading && _posts.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 40),
            child: Center(child: CircularProgressIndicator(color: dc.primary)),
          )
        else if (posts.isEmpty)
          _EmptyStateCard(
            icon: Icons.newspaper_outlined,
            title: 'No matching posts yet',
            body:
                'Try another search term or category. Official department updates will appear here as they are published.',
          )
        else
          for (final post in posts) ...[
            _FeedPostCard(
              post: post,
              bookmarked: _bookmarkedPostIds.contains(post.id),
              onBookmark: () => _toggleBookmark(post.id),
              onComment: () => _openComments(post),
              onOpen: () => _openPost(post),
              onPublisherTap: () => _openDepartmentProfile(post),
              onReact: () => _toggleReaction(post),
            ),
            const SizedBox(height: 14),
          ],
      ],
    );
  }

  Widget _buildReports(BuildContext context) {
    final reports = _filteredReports;
    final reportCategories = <String>{
      'all',
      ..._reports
          .map(_CitizenReport.fromJson)
          .map((report) => report.category)
          .where((category) => category.isNotEmpty),
    }.toList(growable: false);

    return Column(
      key: const ValueKey<String>('reports'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: dc.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: dc.warmBorder),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'My reports',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        color: dc.ink,
                      ),
                    ),
                  ),
                  FilledButton.icon(
                    onPressed: _openReportComposer,
                    icon: const Icon(Icons.add_alert_rounded, size: 18),
                    label: const Text('New report'),
                    style: FilledButton.styleFrom(
                      backgroundColor: dc.primary,
                      foregroundColor: dc.onPrimary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                '${reports.length} visible in this view',
                style: const TextStyle(color: dc.mutedInk),
              ),
              const SizedBox(height: 14),
              SizedBox(
                height: 38,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    for (final status in const [
                      'all',
                      'pending',
                      'accepted',
                      'responding',
                      'resolved',
                    ]) ...[
                      _FilterChip(
                        label: status == 'all' ? 'All statuses' : status,
                        selected: _reportStatus == status,
                        onTap: () => setState(() => _reportStatus = status),
                      ),
                      const SizedBox(width: 8),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                height: 38,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemBuilder: (context, index) {
                    final category = reportCategories[index];
                    return _FilterChip(
                      label: category == 'all'
                          ? 'All categories'
                          : category.replaceAll('_', ' '),
                      selected: _reportCategory == category,
                      onTap: () => setState(() => _reportCategory = category),
                    );
                  },
                  separatorBuilder: (context, index) =>
                      const SizedBox(width: 8),
                  itemCount: reportCategories.length,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        if (_loading && _reports.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 40),
            child: Center(child: CircularProgressIndicator(color: dc.primary)),
          )
        else if (reports.isEmpty)
          _EmptyStateCard(
            icon: Icons.assignment_outlined,
            title: 'No reports match this view',
            body:
                'Your submitted incidents will show status, severity, and response progress here.',
            actionLabel: 'Create a report',
            onAction: _openReportComposer,
          )
        else
          for (final report in reports) ...[
            _ReportCard(report: report, onTap: () => _openReport(report)),
            const SizedBox(height: 12),
          ],
      ],
    );
  }

  Widget _buildMessages(BuildContext context) {
    final items = _meshItems;
    return Column(
      key: const ValueKey<String>('messages'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: dc.surfaceContainerLow,
            borderRadius: BorderRadius.circular(28),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Mesh inbox',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  color: dc.ink,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Keep the mobile-first local inbox for direct node traffic and broadcasted field updates.',
                style: TextStyle(color: dc.mutedInk, height: 1.45),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: widget.onOpenMapTab,
                      icon: const Icon(Icons.map_outlined),
                      label: const Text('Mesh map'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const OfflineCommsScreen(),
                          ),
                        );
                      },
                      icon: const Icon(Icons.send_rounded),
                      label: const Text('Open comms'),
                      style: FilledButton.styleFrom(
                        backgroundColor: dc.primary,
                        foregroundColor: dc.onPrimary,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        if (items.isEmpty)
          _EmptyStateCard(
            icon: Icons.forum_outlined,
            title: 'No local mesh messages yet',
            body:
                'Broadcasts and direct relay messages will appear here once nearby nodes sync.',
            actionLabel: 'Open Offline Comms',
            onAction: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const OfflineCommsScreen()),
              );
            },
          )
        else
          for (final item in items) ...[
            _MeshMessageCard(item: item),
            const SizedBox(height: 12),
          ],
      ],
    );
  }
}

class _NotificationIconButton extends StatelessWidget {
  const _NotificationIconButton({
    required this.unreadCount,
    required this.onTap,
  });

  final int unreadCount;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        IconButton(
          onPressed: onTap,
          icon: const Icon(Icons.notifications_none_rounded, color: dc.ink),
          tooltip: 'Notifications',
        ),
        if (unreadCount > 0)
          Positioned(
            right: 5,
            top: 5,
            child: Container(
              constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
              decoration: BoxDecoration(
                color: dc.statusError,
                borderRadius: BorderRadius.circular(999),
              ),
              alignment: Alignment.center,
              child: Text(
                unreadCount > 99 ? '99+' : '$unreadCount',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _SegmentChip extends StatelessWidget {
  const _SegmentChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Ink(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? dc.primary : dc.surfaceContainerLow,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : dc.onSurface,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Ink(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? dc.primaryContainer : dc.surfaceContainerLow,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: selected ? dc.primary : dc.outlineVariant),
        ),
        child: Text(
          _titleCase(label),
          style: TextStyle(
            color: selected ? dc.onPrimaryContainer : dc.onSurfaceVariant,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _FeedPostCard extends StatelessWidget {
  const _FeedPostCard({
    required this.post,
    required this.bookmarked,
    required this.onBookmark,
    required this.onComment,
    required this.onOpen,
    required this.onPublisherTap,
    required this.onReact,
  });

  final _FeedPost post;
  final bool bookmarked;
  final VoidCallback onBookmark;
  final VoidCallback onComment;
  final VoidCallback onOpen;
  final VoidCallback onPublisherTap;
  final VoidCallback onReact;

  @override
  Widget build(BuildContext context) {
    final categoryColor = dc.categoryColor(post.category);
    final publisherInitial = (post.departmentName ?? 'D').substring(0, 1);

    return InkWell(
      onTap: onOpen,
      borderRadius: BorderRadius.circular(26),
      child: Ink(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: dc.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(26),
          border: Border.all(color: dc.warmBorder),
          boxShadow: const [
            BoxShadow(
              color: Color(0x10000000),
              blurRadius: 18,
              offset: Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                GestureDetector(
                  onTap: onPublisherTap,
                  child: CircleAvatar(
                    radius: 22,
                    backgroundColor: dc.primaryContainer,
                    backgroundImage: post.profilePictureUrl == null
                        ? null
                        : NetworkImage(post.profilePictureUrl!),
                    child: post.profilePictureUrl == null
                        ? Text(
                            publisherInitial.toUpperCase(),
                            style: const TextStyle(
                              color: dc.onPrimaryContainer,
                              fontWeight: FontWeight.w700,
                            ),
                          )
                        : null,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: GestureDetector(
                    onTap: onPublisherTap,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          post.departmentName ?? 'Dispatch department',
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: dc.ink,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          post.publishedAtLabel,
                          style: const TextStyle(
                            fontSize: 12,
                            color: dc.mutedInk,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (post.isPinned)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: dc.errorContainer.withValues(alpha: 0.24),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: const Text(
                      'Pinned',
                      style: TextStyle(
                        color: dc.errorDim,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _MetaPill(
                  label: post.categoryLabel,
                  icon: _feedCategoryIcon(post.category),
                  color: categoryColor,
                ),
                if ((post.location ?? '').isNotEmpty)
                  _MetaPill(
                    label: post.location!,
                    icon: Icons.location_on_outlined,
                    color: dc.coolAccent,
                  ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              post.title,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: dc.ink,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              post.content,
              style: const TextStyle(
                fontSize: 14,
                height: 1.5,
                color: dc.mutedInk,
              ),
            ),
            if (post.imageUrls.isNotEmpty) ...[
              const SizedBox(height: 14),
              ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: Image.network(
                  post.imageUrls.first,
                  height: 180,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) => Container(
                    height: 180,
                    color: dc.surfaceContainerHigh,
                    alignment: Alignment.center,
                    child: const Icon(
                      Icons.image_not_supported_outlined,
                      color: dc.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
            ],
            if (post.attachments.isNotEmpty) ...[
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final attachment in post.attachments)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: dc.surfaceContainerLow,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        _attachmentLabel(attachment),
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                ],
              ),
            ],
            const SizedBox(height: 14),
            Row(
              children: [
                _ActionCountButton(
                  icon: post.likedByMe
                      ? Icons.favorite_rounded
                      : Icons.favorite_border_rounded,
                  label: '${post.reactionCount}',
                  color: post.likedByMe ? dc.statusError : dc.onSurfaceVariant,
                  onTap: onReact,
                ),
                const SizedBox(width: 12),
                _ActionCountButton(
                  icon: Icons.mode_comment_outlined,
                  label: '${post.commentCount}',
                  color: dc.onSurfaceVariant,
                  onTap: onComment,
                ),
                const Spacer(),
                IconButton(
                  onPressed: onBookmark,
                  icon: Icon(
                    bookmarked
                        ? Icons.bookmark_rounded
                        : Icons.bookmark_outline_rounded,
                    color: bookmarked ? dc.primary : dc.onSurfaceVariant,
                  ),
                  tooltip: 'Bookmark',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ReportCard extends StatelessWidget {
  const _ReportCard({required this.report, required this.onTap});

  final _CitizenReport report;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(24),
      child: Ink(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: dc.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: dc.warmBorder),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    report.title,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: dc.ink,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: dc
                        .statusColor(report.status)
                        .withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    report.statusLabel,
                    style: TextStyle(
                      color: dc.statusColor(report.status),
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              report.description,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 14,
                height: 1.45,
                color: dc.mutedInk,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _MetaPill(
                  label: report.categoryLabel,
                  icon: _reportCategoryIcon(report.category),
                  color: dc.categoryColor(report.category),
                ),
                _MetaPill(
                  label: report.severityLabel,
                  icon: Icons.priority_high_rounded,
                  color: _severityColor(report.severity),
                ),
                if ((report.address ?? '').isNotEmpty)
                  _MetaPill(
                    label: report.address!,
                    icon: Icons.place_outlined,
                    color: dc.coolAccent,
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              report.createdAtLabel,
              style: const TextStyle(fontSize: 12, color: dc.mutedInk),
            ),
          ],
        ),
      ),
    );
  }
}

class _MeshMessageCard extends StatelessWidget {
  const _MeshMessageCard({required this.item});

  final MeshInboxItem item;

  @override
  Widget build(BuildContext context) {
    final isBroadcast = item.itemType == 'mesh_post';
    final accent = isBroadcast ? dc.primary : dc.coolAccent;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: dc.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: dc.warmBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  isBroadcast ? Icons.campaign_outlined : Icons.forum_outlined,
                  color: accent,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title?.trim().isNotEmpty == true
                          ? item.title!
                          : item.authorDisplayName,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: dc.ink,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _formatDateTime(item.createdAt),
                      style: const TextStyle(fontSize: 12, color: dc.mutedInk),
                    ),
                  ],
                ),
              ),
              if (item.isRead == false)
                Container(
                  width: 10,
                  height: 10,
                  decoration: const BoxDecoration(
                    color: dc.statusPending,
                    shape: BoxShape.circle,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            item.body,
            style: const TextStyle(
              fontSize: 14,
              height: 1.45,
              color: dc.mutedInk,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _MetaPill(
                label: isBroadcast ? 'Broadcast' : 'Direct message',
                icon: isBroadcast ? Icons.campaign : Icons.mail_outline,
                color: accent,
              ),
              _MetaPill(
                label: '${item.hopCount}/${item.maxHops} hops',
                icon: Icons.hub_outlined,
                color: dc.statusResponding,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MetaPill extends StatelessWidget {
  const _MetaPill({
    required this.label,
    required this.icon,
    required this.color,
  });

  final String label;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(
            _titleCase(label),
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionCountButton extends StatelessWidget {
  const _ActionCountButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Ink(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: dc.surfaceContainerLow,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyStateCard extends StatelessWidget {
  const _EmptyStateCard({
    required this.icon,
    required this.title,
    required this.body,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String body;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: dc.surfaceContainerLow,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        children: [
          Icon(icon, size: 34, color: dc.primary),
          const SizedBox(height: 12),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.w800,
              color: dc.ink,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            body,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 14,
              height: 1.5,
              color: dc.mutedInk,
            ),
          ),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: 16),
            FilledButton(
              onPressed: onAction,
              style: FilledButton.styleFrom(
                backgroundColor: dc.primary,
                foregroundColor: dc.onPrimary,
              ),
              child: Text(actionLabel!),
            ),
          ],
        ],
      ),
    );
  }
}

class _CommentsSheet extends ConsumerStatefulWidget {
  const _CommentsSheet({required this.post});

  final _FeedPost post;

  @override
  ConsumerState<_CommentsSheet> createState() => _CommentsSheetState();
}

class _CommentsSheetState extends ConsumerState<_CommentsSheet> {
  final TextEditingController _commentController = TextEditingController();
  bool _loading = true;
  bool _submitting = false;
  List<Map<String, dynamic>> _comments = const <Map<String, dynamic>>[];

  @override
  void initState() {
    super.initState();
    _loadComments();
  }

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  Future<void> _loadComments() async {
    try {
      final comments = await ref
          .read(authServiceProvider)
          .getFeedComments(widget.post.id);
      if (!mounted) {
        return;
      }
      setState(() {
        _comments = comments;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() => _loading = false);
    }
  }

  Future<void> _submitComment() async {
    final value = _commentController.text.trim();
    if (value.isEmpty || _submitting) {
      return;
    }

    setState(() => _submitting = true);
    try {
      final comment = await ref
          .read(authServiceProvider)
          .createFeedComment(widget.post.id, comment: value);
      if (!mounted) {
        return;
      }
      setState(() {
        _comments = [..._comments, comment];
        _submitting = false;
      });
      _commentController.clear();
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to post your comment right now.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Container(
        decoration: const BoxDecoration(
          color: dc.surfaceContainerLowest,
          borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
        ),
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: MediaQuery.of(context).size.height * 0.75,
            child: Column(
              children: [
                const SizedBox(height: 12),
                Container(
                  width: 44,
                  height: 4,
                  decoration: BoxDecoration(
                    color: dc.outlineVariant,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Comments',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              widget.post.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 12,
                                color: dc.mutedInk,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: _loading
                      ? const Center(
                          child: CircularProgressIndicator(color: dc.primary),
                        )
                      : _comments.isEmpty
                      ? const Center(
                          child: Text(
                            'No comments yet. Start the thread.',
                            style: TextStyle(color: dc.mutedInk),
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.all(20),
                          itemBuilder: (context, index) {
                            final comment = _comments[index];
                            final userName =
                                (comment['user_name'] as String? ?? 'Citizen')
                                    .trim();
                            return Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: dc.surfaceContainerLow,
                                borderRadius: BorderRadius.circular(18),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          userName,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ),
                                      Text(
                                        _formatDateTime(
                                          comment['created_at'] as String? ??
                                              '',
                                        ),
                                        style: const TextStyle(
                                          fontSize: 11,
                                          color: dc.mutedInk,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    comment['comment'] as String? ?? '',
                                    style: const TextStyle(
                                      height: 1.45,
                                      color: dc.ink,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                          separatorBuilder: (context, index) =>
                              const SizedBox(height: 12),
                          itemCount: _comments.length,
                        ),
                ),
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _commentController,
                          minLines: 1,
                          maxLines: 4,
                          decoration: InputDecoration(
                            hintText: 'Add a comment',
                            filled: true,
                            fillColor: dc.surfaceContainerLow,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(18),
                              borderSide: BorderSide.none,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      FilledButton(
                        onPressed: _submitting ? null : _submitComment,
                        style: FilledButton.styleFrom(
                          backgroundColor: dc.primary,
                          foregroundColor: dc.onPrimary,
                          minimumSize: const Size(52, 52),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(18),
                          ),
                        ),
                        child: _submitting
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.send_rounded),
                      ),
                    ],
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

class _FeedPost {
  const _FeedPost({
    required this.id,
    required this.title,
    required this.content,
    required this.category,
    required this.createdAt,
    required this.reactionCount,
    required this.commentCount,
    required this.likedByMe,
    required this.isPinned,
    required this.imageUrls,
    required this.attachments,
    this.location,
    this.uploaderId,
    this.departmentName,
    this.departmentDescription,
    this.profilePictureUrl,
  });

  factory _FeedPost.fromJson(Map<String, dynamic> json) {
    final department = json['department'] as Map<String, dynamic>? ?? const {};
    return _FeedPost(
      id: (json['id'] ?? '').toString(),
      title: (json['title'] as String? ?? '').trim(),
      content: (json['content'] as String? ?? '').trim(),
      category: (json['category'] as String? ?? 'update').trim(),
      createdAt: (json['created_at'] as String? ?? '').trim(),
      location: (json['location'] as String?)?.trim(),
      uploaderId: (json['uploader'] ?? '').toString(),
      reactionCount: (json['reaction'] as num?)?.toInt() ?? 0,
      commentCount: (json['comment_count'] as num?)?.toInt() ?? 0,
      likedByMe: json['liked_by_me'] == true,
      isPinned: json['is_pinned'] == true,
      imageUrls: (json['image_urls'] as List<dynamic>? ?? const <dynamic>[])
          .whereType<String>()
          .toList(growable: false),
      attachments: (json['attachments'] as List<dynamic>? ?? const <dynamic>[])
          .whereType<String>()
          .toList(growable: false),
      departmentName: (department['name'] as String?)?.trim(),
      departmentDescription: (department['description'] as String?)?.trim(),
      profilePictureUrl: (department['profile_picture'] as String?)?.trim(),
    );
  }

  final String id;
  final String title;
  final String content;
  final String category;
  final String createdAt;
  final String? location;
  final String? uploaderId;
  final int reactionCount;
  final int commentCount;
  final bool likedByMe;
  final bool isPinned;
  final List<String> imageUrls;
  final List<String> attachments;
  final String? departmentName;
  final String? departmentDescription;
  final String? profilePictureUrl;

  String get categoryLabel => _titleCase(category.replaceAll('_', ' '));

  String get publishedAtLabel => _formatDateTime(createdAt);
}

class _CitizenReport {
  const _CitizenReport({
    required this.id,
    required this.title,
    required this.description,
    required this.category,
    required this.status,
    required this.severity,
    required this.createdAt,
    this.address,
  });

  factory _CitizenReport.fromJson(Map<String, dynamic> json) {
    final title = (json['title'] as String?)?.trim();
    final description = (json['description'] as String? ?? '').trim();
    return _CitizenReport(
      id: (json['id'] ?? '').toString(),
      title: (title == null || title.isEmpty)
          ? _deriveReportTitle(description, json['category'] as String?)
          : title,
      description: description,
      category: (json['category'] as String? ?? 'other').trim(),
      status: (json['status'] as String? ?? 'pending').trim(),
      severity: (json['severity'] as String? ?? 'medium').trim(),
      createdAt: (json['created_at'] as String? ?? '').trim(),
      address: (json['address'] as String?)?.trim(),
    );
  }

  final String id;
  final String title;
  final String description;
  final String category;
  final String status;
  final String severity;
  final String createdAt;
  final String? address;

  String get categoryLabel => _titleCase(category.replaceAll('_', ' '));
  String get statusLabel => _titleCase(status);
  String get severityLabel => _titleCase(severity);
  String get createdAtLabel => _formatDateTime(createdAt);
}

String _deriveReportTitle(String description, String? category) {
  final lines = description
      .split('\n')
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)
      .toList(growable: false);
  if (lines.isNotEmpty) {
    return lines.first;
  }
  final fallback = category?.trim().isNotEmpty == true ? category! : 'report';
  return _titleCase(fallback.replaceAll('_', ' '));
}

String _attachmentLabel(String url) {
  final parsed = Uri.tryParse(url);
  final segment = parsed?.pathSegments.isNotEmpty == true
      ? parsed!.pathSegments.last
      : url.split('/').last;
  return segment.isEmpty ? 'Attachment' : segment;
}

String _titleCase(String value) {
  if (value.trim().isEmpty) {
    return value;
  }
  return value
      .split(RegExp(r'\s+'))
      .map((part) {
        final word = part.trim();
        if (word.isEmpty) {
          return word;
        }
        return '${word.substring(0, 1).toUpperCase()}${word.substring(1).toLowerCase()}';
      })
      .join(' ');
}

String _formatDateTime(String value) {
  final timestamp = DateTime.tryParse(value)?.toLocal();
  if (timestamp == null) {
    return value;
  }
  return DateFormat('MMM d, y • h:mm a').format(timestamp);
}

IconData _feedCategoryIcon(String category) {
  return switch (category) {
    'alert' => Icons.campaign_outlined,
    'warning' => Icons.warning_amber_rounded,
    'safety_tip' => Icons.health_and_safety_outlined,
    'situational_report' => Icons.assignment_outlined,
    _ => Icons.newspaper_outlined,
  };
}

IconData _reportCategoryIcon(String category) {
  return switch (category) {
    'fire' => Icons.local_fire_department_rounded,
    'flood' => Icons.water_drop_outlined,
    'earthquake' => Icons.vibration_rounded,
    'road_accident' => Icons.car_crash_outlined,
    'medical' => Icons.medical_services_outlined,
    'structural' => Icons.foundation_outlined,
    _ => Icons.report_problem_outlined,
  };
}

Color _severityColor(String severity) {
  return switch (severity) {
    'low' => dc.statusResolved,
    'medium' => dc.coolAccent,
    'high' => dc.statusPending,
    'critical' => dc.statusError,
    _ => dc.onSurfaceVariant,
  };
}
