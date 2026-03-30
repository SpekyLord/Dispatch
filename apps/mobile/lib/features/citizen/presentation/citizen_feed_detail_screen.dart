import 'dart:async';

import 'package:dispatch_mobile/core/services/realtime_service.dart';
import 'package:dispatch_mobile/core/state/session_controller.dart';
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
      final post = await ref
          .read(authServiceProvider)
          .getFeedPost(widget.postId);
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Announcement')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _post == null
          ? const Center(child: Text('Post not found.'))
          : ListView(
              padding: const EdgeInsets.all(24),
              children: [
                Wrap(
                  spacing: 8,
                  children: [
                    Chip(
                      label: Text(
                        (_post!['category'] as String? ?? 'update').replaceAll(
                          '_',
                          ' ',
                        ),
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      visualDensity: VisualDensity.compact,
                    ),
                    if (_post!['is_pinned'] == true)
                      Chip(
                        avatar: Icon(
                          Icons.push_pin,
                          size: 14,
                          color: Colors.orange.shade700,
                        ),
                        label: const Text(
                          'Pinned',
                          style: TextStyle(fontSize: 10),
                        ),
                        visualDensity: VisualDensity.compact,
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  _post!['title'] as String? ?? '',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                if (_post!['department'] != null) ...[
                  Text(
                    'By ${(_post!['department'] as Map<String, dynamic>)['name'] ?? 'Unknown'}',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.black54,
                    ),
                  ),
                  const SizedBox(height: 4),
                ],
                Text(
                  _post!['created_at'] as String? ?? '',
                  style: const TextStyle(fontSize: 11, color: Colors.grey),
                ),
                const Divider(height: 32),
                Text(
                  _post!['content'] as String? ?? '',
                  style: const TextStyle(fontSize: 14, height: 1.6),
                ),
                if (_post!['image_urls'] != null &&
                    (_post!['image_urls'] as List).isNotEmpty) ...[
                  const SizedBox(height: 16),
                  SizedBox(
                    height: 180,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: (_post!['image_urls'] as List).length,
                      separatorBuilder: (context, index) =>
                          const SizedBox(width: 8),
                      itemBuilder: (_, i) => ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.network(
                          (_post!['image_urls'] as List)[i] as String,
                          height: 180,
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
