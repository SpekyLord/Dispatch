import 'package:dispatch_mobile/core/state/session.dart';
import 'package:dispatch_mobile/core/theme/dispatch_colors.dart' as dc;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class CitizenDepartmentProfileScreen extends ConsumerStatefulWidget {
  const CitizenDepartmentProfileScreen({required this.uploaderId, super.key});

  final String uploaderId;

  @override
  ConsumerState<CitizenDepartmentProfileScreen> createState() =>
      _CitizenDepartmentProfileScreenState();
}

class _CitizenDepartmentProfileScreenState
    extends ConsumerState<CitizenDepartmentProfileScreen> {
  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _department;
  List<Map<String, dynamic>> _posts = const <Map<String, dynamic>>[];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final auth = ref.read(authServiceProvider);
      final departmentResponse = await auth.getDepartmentPublicProfile(
        widget.uploaderId,
      );
      final posts = await auth.getFeedPosts(uploader: widget.uploaderId);
      if (!mounted) {
        return;
      }
      setState(() {
        _department = departmentResponse['department'] as Map<String, dynamic>?;
        _posts = posts;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loading = false;
        _error = 'Unable to load this department profile right now.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final department = _department;
    final headerPhoto = (department?['header_photo'] as String?)?.trim();
    final profilePicture =
        ((department?['profile_picture'] ?? department?['profile_photo'])
                as String?)
            ?.trim();
    final name = (department?['name'] as String? ?? 'Department').trim();
    final type = (department?['type'] as String? ?? 'department').trim();
    final description = (department?['description'] as String? ?? '').trim();
    final address = (department?['address'] as String? ?? '').trim();
    final area = (department?['area_of_responsibility'] as String? ?? '')
        .trim();
    final contact = (department?['contact_number'] as String? ?? '').trim();
    final initials = name.isEmpty ? 'D' : name.substring(0, 1).toUpperCase();

    return Scaffold(
      backgroundColor: dc.background,
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: dc.primary))
          : _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: dc.mutedInk),
                ),
              ),
            )
          : RefreshIndicator(
              onRefresh: _load,
              color: dc.primary,
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      SizedBox(
                        height: 238,
                        width: double.infinity,
                        child: DecoratedBox(
                          decoration: const BoxDecoration(
                            gradient: LinearGradient(
                              colors: dc.heroGradient,
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                          ),
                          child: headerPhoto == null || headerPhoto.isEmpty
                              ? null
                              : Image.network(
                                  headerPhoto,
                                  fit: BoxFit.cover,
                                  errorBuilder: (context, error, stackTrace) =>
                                      const SizedBox.shrink(),
                                ),
                        ),
                      ),
                      Positioned(
                        top: MediaQuery.of(context).padding.top + 8,
                        left: 8,
                        child: IconButton(
                          onPressed: () => Navigator.of(context).pop(),
                          icon: const Icon(
                            Icons.arrow_back_rounded,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      Positioned(
                        left: 20,
                        right: 20,
                        bottom: -56,
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            CircleAvatar(
                              radius: 54,
                              backgroundColor: dc.surfaceContainerLowest,
                              child: CircleAvatar(
                                radius: 50,
                                backgroundColor: dc.primaryContainer,
                                backgroundImage:
                                    profilePicture == null ||
                                        profilePicture.isEmpty
                                    ? null
                                    : NetworkImage(profilePicture),
                                child:
                                    profilePicture == null ||
                                        profilePicture.isEmpty
                                    ? Text(
                                        initials,
                                        style: const TextStyle(
                                          fontSize: 34,
                                          fontWeight: FontWeight.w800,
                                          color: dc.onPrimaryContainer,
                                        ),
                                      )
                                    : null,
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      name,
                                      style: const TextStyle(
                                        fontSize: 28,
                                        fontWeight: FontWeight.w800,
                                        color: Colors.white,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 6,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.white.withValues(
                                          alpha: 0.16,
                                        ),
                                        borderRadius: BorderRadius.circular(
                                          999,
                                        ),
                                      ),
                                      child: Text(
                                        _titleCase(type.replaceAll('_', ' ')),
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 11,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 72, 20, 32),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (description.isNotEmpty) ...[
                          Text(
                            description,
                            style: const TextStyle(
                              fontSize: 15,
                              height: 1.5,
                              color: dc.ink,
                            ),
                          ),
                          const SizedBox(height: 18),
                        ],
                        Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: [
                            _InfoPill(
                              icon: Icons.campaign_outlined,
                              label: '${_posts.length} published posts',
                            ),
                            if (area.isNotEmpty)
                              _InfoPill(icon: Icons.map_outlined, label: area),
                            if (address.isNotEmpty)
                              _InfoPill(
                                icon: Icons.place_outlined,
                                label: address,
                              ),
                          ],
                        ),
                        const SizedBox(height: 22),
                        if (contact.isNotEmpty ||
                            area.isNotEmpty ||
                            address.isNotEmpty)
                          Container(
                            padding: const EdgeInsets.all(18),
                            decoration: BoxDecoration(
                              color: dc.surfaceContainerLowest,
                              borderRadius: BorderRadius.circular(24),
                              border: Border.all(color: dc.warmBorder),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Public details',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w800,
                                    color: dc.ink,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                if (contact.isNotEmpty)
                                  _DetailRow(
                                    icon: Icons.phone_outlined,
                                    label: contact,
                                  ),
                                if (address.isNotEmpty)
                                  _DetailRow(
                                    icon: Icons.location_on_outlined,
                                    label: address,
                                  ),
                                if (area.isNotEmpty)
                                  _DetailRow(
                                    icon: Icons.map_outlined,
                                    label: area,
                                  ),
                              ],
                            ),
                          ),
                        const SizedBox(height: 22),
                        const Text(
                          'Published posts',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: dc.ink,
                          ),
                        ),
                        const SizedBox(height: 10),
                        if (_posts.isEmpty)
                          Container(
                            padding: const EdgeInsets.all(22),
                            decoration: BoxDecoration(
                              color: dc.surfaceContainerLow,
                              borderRadius: BorderRadius.circular(22),
                            ),
                            child: const Text(
                              'No published posts yet.',
                              style: TextStyle(color: dc.mutedInk),
                            ),
                          )
                        else
                          for (final post in _posts) ...[
                            _DepartmentPostCard(post: post),
                            const SizedBox(height: 12),
                          ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

class _DepartmentPostCard extends StatelessWidget {
  const _DepartmentPostCard({required this.post});

  final Map<String, dynamic> post;

  @override
  Widget build(BuildContext context) {
    final title = (post['title'] as String? ?? '').trim();
    final content = (post['content'] as String? ?? '').trim();
    final category = (post['category'] as String? ?? 'update').trim();
    final location = (post['location'] as String? ?? '').trim();
    final images = (post['image_urls'] as List<dynamic>? ?? const <dynamic>[])
        .whereType<String>()
        .toList(growable: false);

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: dc.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: dc.warmBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _InfoPill(
                icon: Icons.label_outline_rounded,
                label: _titleCase(category.replaceAll('_', ' ')),
              ),
              if (location.isNotEmpty)
                _InfoPill(icon: Icons.place_outlined, label: location),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            title,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: dc.ink,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            content,
            style: const TextStyle(
              fontSize: 14,
              height: 1.5,
              color: dc.mutedInk,
            ),
          ),
          if (images.isNotEmpty) ...[
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Image.network(
                images.first,
                height: 160,
                width: double.infinity,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => Container(
                  height: 160,
                  color: dc.surfaceContainerHigh,
                  alignment: Alignment.center,
                  child: const Icon(Icons.image_not_supported_outlined),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _InfoPill extends StatelessWidget {
  const _InfoPill({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: dc.primaryContainer,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: dc.onPrimaryContainer),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: dc.onPrimaryContainer,
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: dc.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(fontSize: 14, height: 1.45, color: dc.ink),
            ),
          ),
        ],
      ),
    );
  }
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
