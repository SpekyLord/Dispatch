import 'dart:async';

import 'package:dispatch_mobile/core/services/realtime_service.dart';
import 'package:dispatch_mobile/core/state/session.dart';
import 'package:dispatch_mobile/core/theme/dispatch_colors.dart' as dc;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class CitizenFeedDetailScreen extends ConsumerStatefulWidget {
  const CitizenFeedDetailScreen({required this.postId, super.key});

  final String postId;

  @override
  ConsumerState<CitizenFeedDetailScreen> createState() =>
      _CitizenFeedDetailScreenState();
}

class _CitizenFeedDetailScreenState
    extends ConsumerState<CitizenFeedDetailScreen> {
  Map<String, dynamic>? _post;
  RealtimeSubscriptionHandle? _subscription;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _fetchPost();
    _subscription = ref
        .read(realtimeServiceProvider)
        .subscribeToTable(
          table: 'posts',
          eqColumn: 'id',
          eqValue: widget.postId,
          onChange: () {
            if (mounted) {
              _fetchPost(showLoader: false);
            }
          },
        );
  }

  @override
  void dispose() {
    final subscription = _subscription;
    if (subscription != null) {
      unawaited(subscription.dispose());
    }
    super.dispose();
  }

  Future<void> _fetchPost({bool showLoader = true}) async {
    if (showLoader && mounted) {
      setState(() => _loading = true);
    }
    try {
      final post = await ref.read(authServiceProvider).getFeedPost(widget.postId);
      if (mounted) {
        setState(() {
          _post = post;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted && showLoader) {
        setState(() => _loading = false);
      }
    }
  }

  String _formatDate(String? raw) {
    if (raw == null || raw.isEmpty) return '';
    try {
      final dt = DateTime.parse(raw).toLocal();
      final months = [
        'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
      ];
      final h = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
      final m = dt.minute.toString().padLeft(2, '0');
      final ampm = dt.hour < 12 ? 'AM' : 'PM';
      return '${months[dt.month - 1]} ${dt.day}, ${dt.year} · $h:$m $ampm';
    } catch (_) {
      return raw;
    }
  }

  @override
  Widget build(BuildContext context) {
    final post = _post;
    final category = (post?['category'] as String? ?? 'update');
    final categoryLabel = category.replaceAll('_', ' ');
    final isPinned = post?['is_pinned'] == true;
    final deptName =
        post?['department'] != null
            ? (post!['department'] as Map<String, dynamic>)['name'] as String? ?? 'Unknown'
            : null;

    return Scaffold(
      backgroundColor: dc.background,
      appBar: AppBar(
        backgroundColor: dc.background,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          color: dc.onSurface,
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(
          'Announcement',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: dc.onSurface,
          ),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: dc.primary))
          : post == null
          ? const Center(
              child: Text('Post not found.', style: TextStyle(color: dc.onSurfaceVariant)),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 48),
              children: [
                // Category + pinned badges
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: dc.categoryColor(category).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: dc.categoryColor(category).withValues(alpha: 0.25),
                          width: 0.8,
                        ),
                      ),
                      child: Text(
                        categoryLabel,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.3,
                          color: dc.categoryColor(category),
                        ),
                      ),
                    ),
                    if (isPinned)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: dc.statusPending.withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                            color: dc.statusPending.withValues(alpha: 0.22),
                            width: 0.8,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.push_pin_rounded, size: 12, color: dc.statusPending),
                            const SizedBox(width: 4),
                            Text(
                              'Pinned',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: dc.statusPending,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 20),

                // Title
                Text(
                  post['title'] as String? ?? '',
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.4,
                    height: 1.25,
                    color: dc.onSurface,
                  ),
                ),
                const SizedBox(height: 14),

                // Author + date row
                Row(
                  children: [
                    Container(
                      width: 28,
                      height: 28,
                      decoration: const BoxDecoration(
                        color: dc.primaryContainer,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.business_rounded, size: 14, color: dc.primary),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (deptName != null)
                            Text(
                              deptName,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: dc.onSurface,
                              ),
                            ),
                          Text(
                            _formatDate(post['created_at'] as String?),
                            style: const TextStyle(
                              fontSize: 11,
                              color: dc.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                // Divider
                Container(
                  height: 1,
                  color: dc.outlineVariant.withValues(alpha: 0.35),
                ),
                const SizedBox(height: 20),

                // Body content
                Text(
                  post['content'] as String? ?? '',
                  style: const TextStyle(
                    fontSize: 15,
                    height: 1.7,
                    color: dc.onSurface,
                  ),
                ),

                // Images
                if (post['image_urls'] != null &&
                    (post['image_urls'] as List).isNotEmpty) ...[
                  const SizedBox(height: 24),
                  SizedBox(
                    height: 200,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: (post['image_urls'] as List).length,
                      separatorBuilder: (_, __) => const SizedBox(width: 10),
                      itemBuilder: (_, i) => ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: Image.network(
                          (post['image_urls'] as List)[i] as String,
                          height: 200,
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
    );
  }
}
