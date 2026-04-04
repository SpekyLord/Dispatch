import 'dart:async';

import 'package:dispatch_mobile/core/services/realtime_service.dart';
import 'package:dispatch_mobile/core/state/session.dart';
import 'package:dispatch_mobile/features/citizen/presentation/citizen_feed_detail_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
const _feedBackground = Color(0xFFFDF7F2);
const _feedCard = Color(0xFFFFF8F3);
const _feedBorder = Color(0xFFE7D1C6);
const _feedText = Color(0xFF4E433D);
const _feedMuted = Color(0xFF7A6B63);

class CitizenFeedScreen extends ConsumerStatefulWidget {
  const CitizenFeedScreen({super.key});

  @override
  ConsumerState<CitizenFeedScreen> createState() => _CitizenFeedScreenState();
}

class _CitizenFeedScreenState extends ConsumerState<CitizenFeedScreen> {
  List<Map<String, dynamic>> _posts = [];
  RealtimeSubscriptionHandle? _subscription;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _fetchPosts();
    _subscription = ref
        .read(realtimeServiceProvider)
        .subscribeToTable(
          table: 'posts',
          onChange: () {
            if (mounted) {
              _fetchPosts(showLoader: false);
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

  Future<void> _fetchPosts({bool showLoader = true}) async {
    if (showLoader && mounted) {
      setState(() => _loading = true);
    }
    try {
      final posts = await ref.read(authServiceProvider).getFeedPosts();
      if (mounted) {
        setState(() {
          _posts = posts;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted && showLoader) {
        setState(() => _loading = false);
      }
    }
  }

  IconData _categoryIcon(String category) {
    return switch (category) {
      'alert' => Icons.warning_amber,
      'warning' => Icons.error_outline,
      'safety_tip' => Icons.health_and_safety,
      'update' => Icons.info_outline,
      'situational_report' => Icons.summarize,
      _ => Icons.article,
    };
  }

  Color _categoryColor(String category) {
    return switch (category) {
      'alert' => Colors.red,
      'warning' => Colors.orange,
      'safety_tip' => Colors.blue,
      'update' => Colors.green,
      'situational_report' => Colors.purple,
      _ => Colors.grey,
    };
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_posts.isEmpty) {
      return const Center(child: Text('No announcements yet.'));
    }

    return RefreshIndicator(
      onRefresh: () => _fetchPosts(),
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
        itemCount: _posts.length,
        itemBuilder: (context, index) {
          final post = _posts[index];
          final category = post['category'] as String? ?? 'update';
          final isPinned = post['is_pinned'] == true;
          final dept = post['department'] as Map<String, dynamic>?;
          final postId = post['id']?.toString();
          final createdAt = post['created_at']?.toString() ?? '';
          final content = post['content'] as String? ?? '';
          final title = post['title'] as String? ?? '';
          final imageUrls =
              (post['image_urls'] as List?)?.whereType<String>().toList() ??
              const <String>[];

          return Container(
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: _feedCard,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: _feedBorder),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x14131110),
                  blurRadius: 18,
                  offset: Offset(0, 10),
                ),
              ],
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(18),
              onTap: () {
                if (postId == null || postId.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Post is unavailable.')),
                  );
                  return;
                }
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => CitizenFeedDetailScreen(postId: postId),
                  ),
                );
              },
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                    child: Row(
                      children: [
                        CircleAvatar(
                          backgroundColor:
                              _categoryColor(category).withAlpha(30),
                          child: Icon(
                            _categoryIcon(category),
                            color: _categoryColor(category),
                            size: 18,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      dept?['name'] as String? ??
                                          'Verified Department',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                        color: _feedText,
                                      ),
                                    ),
                                  ),
                                  const Icon(
                                    Icons.verified,
                                    color: Color(0xFF1695D3),
                                    size: 16,
                                  ),
                                  if (isPinned)
                                    Padding(
                                      padding: const EdgeInsets.only(left: 6),
                                      child: Icon(
                                        Icons.push_pin,
                                        size: 14,
                                        color: Colors.orange.shade700,
                                      ),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 2),
                              Text(
                                _formatTime(createdAt),
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: _feedMuted,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: _categoryColor(category).withAlpha(20),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            category.replaceAll('_', ' '),
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: _categoryColor(category),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (title.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Text(
                        title,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: _feedText,
                        ),
                      ),
                    ),
                  if (content.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                      child: Text(
                        content,
                        style: const TextStyle(color: _feedText, height: 1.4),
                      ),
                    ),
                  if (imageUrls.isNotEmpty)
                    SizedBox(
                      height: 200,
                      child: ListView.separated(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        scrollDirection: Axis.horizontal,
                        itemCount: imageUrls.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 10),
                        itemBuilder: (_, i) => ClipRRect(
                          borderRadius: BorderRadius.circular(14),
                          child: Image.network(
                            imageUrls[i],
                            width: 260,
                            height: 200,
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                    child: Row(
                      children: const [
                        Icon(Icons.thumb_up_alt, size: 14, color: _feedMuted),
                        SizedBox(width: 6),
                        Text('Like', style: TextStyle(color: _feedMuted)),
                        Spacer(),
                        Text('Comments', style: TextStyle(color: _feedMuted)),
                      ],
                    ),
                  ),
                  const Divider(height: 16),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                    child: Row(
                      children: [
                        _FeedAction(
                          icon: Icons.thumb_up_alt_outlined,
                          label: 'Like',
                          onTap: () {},
                        ),
                        _FeedAction(
                          icon: Icons.chat_bubble_outline,
                          label: 'Comment',
                          onTap: () {},
                        ),
                        _FeedAction(
                          icon: Icons.ios_share_outlined,
                          label: 'Share',
                          onTap: () {},
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  String _formatTime(String raw) {
    final parsed = DateTime.tryParse(raw);
    if (parsed == null) {
      return raw.isEmpty ? 'Just now' : raw;
    }
    final local = parsed.toLocal();
    final now = DateTime.now();
    final diff = now.difference(local);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m';
    if (diff.inHours < 24) return '${diff.inHours}h';
    return '${local.month}/${local.day}/${local.year}';
  }
}

class _FeedAction extends StatelessWidget {
  const _FeedAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: TextButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 18, color: _feedMuted),
        label: Text(label, style: const TextStyle(color: _feedMuted)),
      ),
    );
  }
}
