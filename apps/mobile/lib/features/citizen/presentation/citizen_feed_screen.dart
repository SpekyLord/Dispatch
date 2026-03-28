// Citizen feed — lists public department announcements with category filter.

import 'package:dispatch_mobile/core/state/session_controller.dart';
import 'package:dispatch_mobile/features/citizen/presentation/citizen_feed_detail_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class CitizenFeedScreen extends ConsumerStatefulWidget {
  const CitizenFeedScreen({super.key});

  @override
  ConsumerState<CitizenFeedScreen> createState() => _CitizenFeedScreenState();
}

class _CitizenFeedScreenState extends ConsumerState<CitizenFeedScreen> {
  List<Map<String, dynamic>> _posts = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _fetchPosts();
  }

  Future<void> _fetchPosts() async {
    setState(() => _loading = true);
    try {
      final posts = await ref.read(authServiceProvider).getFeedPosts();
      if (mounted) setState(() { _posts = posts; _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  // Category icon mapping
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
    return Scaffold(
      appBar: AppBar(title: const Text('Community Feed')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _posts.isEmpty
              ? const Center(child: Text('No announcements yet.'))
              : RefreshIndicator(
                  onRefresh: _fetchPosts,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _posts.length,
                    itemBuilder: (context, index) {
                      final post = _posts[index];
                      final category = post['category'] as String? ?? 'update';
                      final isPinned = post['is_pinned'] == true;
                      final dept = post['department'] as Map<String, dynamic>?;

                      return Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        child: ListTile(
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(builder: (_) => CitizenFeedDetailScreen(postId: post['id'] as String)),
                          ),
                          leading: CircleAvatar(
                            backgroundColor: _categoryColor(category).withAlpha(30),
                            child: Icon(_categoryIcon(category), color: _categoryColor(category), size: 20),
                          ),
                          title: Row(
                            children: [
                              if (isPinned)
                                Padding(
                                  padding: const EdgeInsets.only(right: 4),
                                  child: Icon(Icons.push_pin, size: 14, color: Colors.orange.shade700),
                                ),
                              Expanded(
                                child: Text(
                                  post['title'] as String? ?? '',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontWeight: FontWeight.w600),
                                ),
                              ),
                            ],
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SizedBox(height: 4),
                              Text(
                                post['content'] as String? ?? '',
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 12),
                              ),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  if (dept != null)
                                    Text(dept['name'] as String? ?? '', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600)),
                                  const Spacer(),
                                  Text(
                                    category.replaceAll('_', ' '),
                                    style: TextStyle(fontSize: 10, color: _categoryColor(category), fontWeight: FontWeight.w600),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          trailing: const Icon(Icons.chevron_right, size: 18),
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}
