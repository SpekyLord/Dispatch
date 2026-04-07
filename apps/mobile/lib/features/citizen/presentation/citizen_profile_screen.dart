import 'dart:async';

import 'package:dispatch_mobile/core/state/mesh_providers.dart';
import 'package:dispatch_mobile/core/state/notification_inbox_controller.dart';
import 'package:dispatch_mobile/core/state/session.dart';
import 'package:dispatch_mobile/core/theme/dispatch_colors.dart' as dc;
import 'package:dispatch_mobile/features/citizen/presentation/citizen_feed_screen.dart';
import 'package:dispatch_mobile/features/citizen/presentation/citizen_my_reports_screen.dart';
import 'package:dispatch_mobile/features/citizen/presentation/citizen_profile_edit_screen.dart';
import 'package:dispatch_mobile/features/shared/presentation/notifications_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class CitizenProfileScreen extends ConsumerStatefulWidget {
  const CitizenProfileScreen({super.key});

  @override
  ConsumerState<CitizenProfileScreen> createState() =>
      _CitizenProfileScreenState();
}

class _CitizenProfileScreenState extends ConsumerState<CitizenProfileScreen> {
  static const _fallbackAvatarUrl =
      'https://lh3.googleusercontent.com/aida-public/AB6AXuC5eskmHMV5gmRHD9IzSqJJ4FlZC3pntpLOrZeLSJBvNckS_AwQgSEpIoL6hQptPPVpTbXR-uYV_Nr7eqp2cy7DXBIBNxmxTR529fI1HKPuHPWtBF_Xkxs1Atjs3ZxtUC8XHqmMr2UQqEjati8vl5ZZ8I6W4ttYVzWAfvYrnn1ujWt_fSWKxxmOdVbAD_SRsRFELitL1DWH2Z1X1t6n1_sZ8M06mL2S7t2wSkSGxXnCQWGVPL7dtbmNTEbZnNWPVghmHpcUNMye-RI';

  List<Map<String, dynamic>> _reports = const [];
  String? _phone;
  String? _description;
  String? _avatarUrl;
  String? _profilePictureUrl;
  String? _headerPhotoUrl;
  bool _loading = true;
  bool _meshBusy = false;
  bool _signingOut = false;
  bool _darkModePreview = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_hydrate());
    });
  }

  Future<void> _hydrate({bool showLoader = true}) async {
    if (showLoader && mounted) {
      setState(() => _loading = true);
    }

    final auth = ref.read(authServiceProvider);
    final transport = ref.read(meshTransportProvider);
    final session = ref.read(sessionControllerProvider);

    try {
      await transport.initialize();
    } catch (_) {}

    Map<String, dynamic>? profile;
    try {
      final response = await auth.getProfile();
      profile =
          (response['profile'] as Map<String, dynamic>?) ??
          (response.isNotEmpty ? response : null);
    } catch (_) {
      profile = null;
    }

    List<Map<String, dynamic>> reports = const [];
    try {
      reports = (await auth.getReports()).cast<Map<String, dynamic>>();
    } catch (_) {
      reports = const [];
    }

    final updatedName = profile?['full_name'] as String?;
    if (updatedName != null &&
        updatedName.trim().isNotEmpty &&
        updatedName.trim() != (session.fullName ?? '').trim()) {
      ref.read(sessionControllerProvider.notifier).updateFullName(updatedName);
    }

    if (!mounted) {
      return;
    }

    setState(() {
      _reports = reports;
      _phone = _readProfileString(profile, ['phone']);
      _description = _readProfileString(profile, ['description']);
      _avatarUrl = _readProfileString(profile, [
        'avatar_url',
        'profile_picture',
        'profile_photo',
      ]);
      _profilePictureUrl = _readProfileString(profile, [
        'profile_picture',
        'profile_photo',
        'avatar_url',
      ]);
      _headerPhotoUrl = _readProfileString(profile, ['header_photo']);
      _loading = false;
    });
  }

  Future<void> _openEditProfile() async {
    final session = ref.read(sessionControllerProvider);
    final result = await Navigator.of(context).push<CitizenProfileEditResult>(
      MaterialPageRoute(
        builder: (_) => CitizenProfileEditScreen(
          initialFullName: session.fullName ?? '',
          initialPhone: _phone ?? '',
          initialDescription: _description ?? '',
          initialProfilePictureUrl: _profilePictureUrl,
          initialHeaderPhotoUrl: _headerPhotoUrl,
        ),
      ),
    );

    if (!mounted || result == null) {
      return;
    }

    final profile = result.profile;
    final nextName = _readProfileString(profile, ['full_name']);
    if (nextName != null && nextName.isNotEmpty) {
      ref.read(sessionControllerProvider.notifier).updateFullName(nextName);
    }
    setState(() {
      _phone = _readProfileString(profile, ['phone']) ?? _phone;
      _description =
          _readProfileString(profile, ['description']) ?? _description;
      _avatarUrl =
          _readProfileString(profile, [
            'avatar_url',
            'profile_picture',
            'profile_photo',
          ]) ??
          _avatarUrl;
      _profilePictureUrl =
          _readProfileString(profile, [
            'profile_picture',
            'profile_photo',
            'avatar_url',
          ]) ??
          _profilePictureUrl;
      _headerPhotoUrl =
          _readProfileString(profile, ['header_photo']) ?? _headerPhotoUrl;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Profile updated successfully.')),
    );
  }

  Future<void> _toggleMeshMode(bool enabled) async {
    if (_meshBusy) {
      return;
    }

    final transport = ref.read(meshTransportProvider);
    setState(() => _meshBusy = true);
    try {
      await transport.initialize();
      if (enabled) {
        await transport.startDiscovery();
      } else {
        await transport.stopDiscovery();
      }
      if (!mounted) {
        return;
      }
      setState(() {});
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              enabled
                  ? 'Unable to start BLE discovery right now.'
                  : 'Unable to pause BLE discovery right now.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _meshBusy = false);
      }
    }
  }

  Future<void> _signOut() async {
    if (_signingOut) {
      return;
    }
    setState(() => _signingOut = true);
    try {
      await ref.read(sessionControllerProvider.notifier).signOut();
    } finally {
      if (mounted) {
        setState(() => _signingOut = false);
      }
    }
  }

  void _toggleAppearance(bool enabled) {
    setState(() => _darkModePreview = enabled);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Appearance preview updated locally. Persistent theme sync is not configured yet.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionControllerProvider);
    final transport = ref.watch(meshTransportProvider);
    final inbox = ref.watch(notificationInboxControllerProvider);
    final stats = _CitizenProfileStats.fromReports(_reports);
    final fullName = (session.fullName ?? '').trim().isEmpty
        ? 'Citizen Responder'
        : session.fullName!.trim();
    final citizenId = _formatCitizenId(
      session.userId ?? session.email ?? fullName,
    );
    final sectorLabel = _sectorLabel(session.userId ?? transport.localDeviceId);
    final nodeStateLabel = transport.isDiscovering
        ? 'ACTIVE NODE'
        : 'STANDBY NODE';
    final topPadding = MediaQuery.of(context).padding.top + 18;
    const backgroundColor = dc.background;
    const cardColor = dc.surfaceContainerLow;
    const labelColor = dc.onSurfaceVariant;
    const textColor = dc.onSurface;

    return Scaffold(
      backgroundColor: backgroundColor,
      body: Stack(
      children: [
        RefreshIndicator(
          color: dc.primary,
          onRefresh: () => _hydrate(showLoader: false),
          child: ListView(
            padding: EdgeInsets.fromLTRB(12, topPadding, 12, 120),
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: Icon(Icons.arrow_back_ios_new_rounded, color: textColor, size: 20),
                      tooltip: 'Back',
                      padding: EdgeInsets.zero,
                      visualDensity: VisualDensity.compact,
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Citizen profile',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.35,
                              color: textColor,
                            ),
                          ),
                          Text(
                            'Profile, report stats, quick links, and node settings.',
                            style: TextStyle(fontSize: 12, color: labelColor),
                          ),
                        ],
                      ),
                    ),
                    Stack(
                      clipBehavior: Clip.none,
                      children: [
                        IconButton(
                          onPressed: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => const NotificationsScreen(),
                              ),
                            );
                          },
                          icon: Icon(
                            Icons.notifications_none_rounded,
                            color: textColor,
                          ),
                          tooltip: 'Notifications',
                        ),
                        if (inbox.unreadCount > 0)
                          Positioned(
                            right: 6,
                            top: 6,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 5,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: dc.statusError,
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                inbox.unreadCount > 99
                                    ? '99+'
                                    : '${inbox.unreadCount}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                    IconButton(
                      onPressed: _loading
                          ? null
                          : () => unawaited(_hydrate(showLoader: false)),
                      icon: Icon(
                        Icons.sync,
                        color: labelColor.withValues(alpha: 0.8),
                      ),
                      tooltip: 'Refresh settings',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 22),
              Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.bottomCenter,
                children: [
                  // Header banner
                  Container(
                    height: 148,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(26),
                      gradient: const LinearGradient(
                        colors: dc.heroGradient,
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      image: (_headerPhotoUrl ?? '').isNotEmpty
                          ? DecorationImage(
                              image: NetworkImage(_headerPhotoUrl!),
                              fit: BoxFit.cover,
                            )
                          : null,
                    ),
                  ),
                  // Avatar overlapping the bottom of the banner
                  Positioned(
                    bottom: -48,
                    child: _ProfileAvatarBadge(
                      avatarUrl: (_profilePictureUrl ?? _avatarUrl ?? '').isEmpty
                          ? _fallbackAvatarUrl
                          : (_profilePictureUrl ?? _avatarUrl)!,
                      initials: _initialsFor(fullName),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 62),
              Center(
                child: _ProfileIdentityHero(
                  avatarUrl: (_profilePictureUrl ?? _avatarUrl ?? '').isEmpty
                      ? _fallbackAvatarUrl
                      : (_profilePictureUrl ?? _avatarUrl)!,
                  initials: _initialsFor(fullName),
                  fullName: fullName,
                  citizenId: citizenId,
                  sectorLabel: sectorLabel,
                  nodeStateLabel: nodeStateLabel,
                ),
              ),
              if ((_description ?? '').trim().isNotEmpty) ...[
                const SizedBox(height: 16),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Text(
                    _description!,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      height: 1.5,
                      color: labelColor,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _openEditProfile,
                icon: const Icon(Icons.edit_outlined),
                label: const Text('Edit profile'),
                style: FilledButton.styleFrom(
                  backgroundColor: dc.primary,
                  foregroundColor: dc.onPrimary,
                ),
              ),
              const SizedBox(height: 28),
              GridView.count(
                crossAxisCount: 2,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                childAspectRatio: 1.2,
                children: [
                  _StatCard(
                    label: 'Total Reports',
                    value: '${stats.totalReports}',
                    valueColor: textColor,
                    backgroundColor: cardColor,
                    labelColor: labelColor,
                  ),
                  _StatCard(
                    label: 'Resolved',
                    value: '${stats.resolvedReports}',
                    valueColor: dc.primary,
                    backgroundColor: cardColor,
                    labelColor: labelColor,
                  ),
                  _StatCard(
                    label: 'Recent',
                    value: stats.recentReports.toString().padLeft(2, '0'),
                    valueColor: textColor,
                    backgroundColor: cardColor,
                    labelColor: labelColor,
                  ),
                  _StatCard(
                    label: 'Follow-Ups',
                    value: stats.followUps.toString().padLeft(2, '0'),
                    valueColor: textColor,
                    backgroundColor: cardColor,
                    labelColor: labelColor,
                  ),
                ],
              ),
              const SizedBox(height: 24),
              _SectionLabel(title: 'Quick Links', color: labelColor),
              const SizedBox(height: 10),
              _GroupedCard(
                backgroundColor: cardColor,
                children: [
                  _ActionTile(
                    icon: Icons.assignment_outlined,
                    title: 'My Reports',
                    subtitle: '${stats.totalReports} total reports logged',
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const Scaffold(body: CitizenMyReportsScreen()),
                        ),
                      );
                    },
                  ),
                  const _ToneDivider(),
                  _ActionTile(
                    icon: Icons.notifications_none_rounded,
                    title: 'Notifications',
                    subtitle: inbox.unreadCount == 0
                        ? 'All caught up'
                        : '${inbox.unreadCount} unread updates',
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const NotificationsScreen(),
                        ),
                      );
                    },
                  ),
                  const _ToneDivider(),
                  _ActionTile(
                    icon: Icons.newspaper_outlined,
                    title: 'Dispatch News',
                    subtitle: 'Browse advisories and department updates',
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) =>
                              const Scaffold(body: CitizenFeedScreen()),
                        ),
                      );
                    },
                  ),
                ],
              ),
              const SizedBox(height: 24),
              _SectionLabel(title: 'Published Posts', color: labelColor),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: cardColor,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text(
                  'No published posts yet.',
                  style: TextStyle(color: dc.mutedInk),
                ),
              ),
              const SizedBox(height: 24),
              _SectionLabel(title: 'App Configuration', color: labelColor),
              const SizedBox(height: 10),
              _ConfigTile(
                icon: Icons.contrast,
                title: 'Appearance',
                subtitle: _darkModePreview
                    ? 'Dark Mode preview'
                    : 'Light Mode active',
                value: _darkModePreview,
                onChanged: _toggleAppearance,
                backgroundColor: cardColor,
                busy: false,
              ),
              const SizedBox(height: 12),
              _ConfigTile(
                icon: Icons.hub,
                title: 'Join Mesh (Node Mode)',
                subtitle: transport.isDiscovering
                    ? 'BLE Discovery Active'
                    : 'BLE discovery paused',
                value: transport.isDiscovering,
                onChanged: _toggleMeshMode,
                backgroundColor: cardColor,
                highlight: true,
                busy: _meshBusy,
              ),
              const SizedBox(height: 30),
              _SignOutButton(
                busy: _signingOut,
                onTap: _signOut,
              ),
              const SizedBox(height: 12),
              Center(
                child: Text(
                  'App Version 0.1.0-stable - Build 1',
                  style: TextStyle(
                    fontSize: 11,
                    color: labelColor.withValues(alpha: 0.8),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
        if (_loading)
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: backgroundColor.withValues(alpha: 0.4),
                ),
                child: const Center(child: CircularProgressIndicator()),
              ),
            ),
          ),
      ],
    ),
    );
  }

  static String? _readProfileString(
    Map<String, dynamic>? profile,
    List<String> keys,
  ) {
    if (profile == null) {
      return null;
    }
    for (final key in keys) {
      final value = profile[key];
      if (value is String && value.trim().isNotEmpty) {
        return value.trim();
      }
    }
    return null;
  }

  static String _initialsFor(String fullName) {
    final parts = fullName
        .split(RegExp(r'\s+'))
        .where((part) => part.trim().isNotEmpty)
        .toList(growable: false);
    if (parts.isEmpty) {
      return 'CR';
    }
    if (parts.length == 1) {
      return parts.first.substring(0, 1).toUpperCase();
    }
    return '${parts.first.substring(0, 1)}${parts.last.substring(0, 1)}'
        .toUpperCase();
  }

  static String _formatCitizenId(String seed) {
    final cleaned = seed.replaceAll(RegExp(r'[^A-Za-z0-9]'), '').toUpperCase();
    final padded = cleaned.padRight(11, '0');
    return 'MESH-${padded.substring(0, 3)}-${padded.substring(3, 5)}-${padded.substring(5, 10)}';
  }

  static String _sectorLabel(String seed) {
    final cleaned = seed.replaceAll(RegExp(r'[^A-Za-z0-9]'), '').toUpperCase();
    final units = cleaned.codeUnits;
    final total = units.isEmpty ? 0 : units.reduce((sum, value) => sum + value);
    final ring = (total % 9) + 1;
    final block = String.fromCharCode(65 + (total % 26));
    return 'SECTOR $ring-$block';
  }
}

class _CitizenProfileStats {
  const _CitizenProfileStats({
    required this.totalReports,
    required this.resolvedReports,
    required this.recentReports,
    required this.followUps,
  });

  final int totalReports;
  final int resolvedReports;
  final int recentReports;
  final int followUps;

  factory _CitizenProfileStats.fromReports(List<Map<String, dynamic>> reports) {
    var resolved = 0;
    var recent = 0;
    var followUps = 0;
    final now = DateTime.now();

    for (final report in reports) {
      final status = (report['status'] as String? ?? '').toLowerCase();
      if (status == 'resolved') {
        resolved += 1;
      }
      if (status == 'accepted' || status == 'responding') {
        followUps += 1;
      }
      final createdAt = DateTime.tryParse(
        report['created_at'] as String? ?? '',
      );
      if (createdAt != null &&
          now.difference(createdAt.toLocal()).inDays <= 7) {
        recent += 1;
      }
    }

    return _CitizenProfileStats(
      totalReports: reports.length,
      resolvedReports: resolved,
      recentReports: recent,
      followUps: followUps,
    );
  }
}

// Standalone avatar + verified badge — used in the banner overlap
class _ProfileAvatarBadge extends StatelessWidget {
  const _ProfileAvatarBadge({required this.avatarUrl, required this.initials});

  final String avatarUrl;
  final String initials;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: 96,
          height: 96,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: dc.primaryContainer,
            border: Border.all(color: dc.background, width: 4),
            boxShadow: const [
              BoxShadow(color: Color(0x22000000), blurRadius: 18, offset: Offset(0, 8)),
            ],
          ),
          child: ClipOval(
            child: Image.network(
              avatarUrl,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Center(
                child: Text(
                  initials,
                  style: const TextStyle(
                    color: dc.onPrimaryContainer,
                    fontSize: 30,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ),
        ),
        Positioned(
          right: 2,
          bottom: 2,
          child: Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              color: dc.primary,
              shape: BoxShape.circle,
              border: Border.all(color: dc.background, width: 2),
            ),
            child: const Icon(Icons.verified, size: 14, color: dc.onPrimary),
          ),
        ),
      ],
    );
  }
}

class _ProfileIdentityHero extends StatelessWidget {
  const _ProfileIdentityHero({
    required this.avatarUrl,
    required this.initials,
    required this.fullName,
    required this.citizenId,
    required this.sectorLabel,
    required this.nodeStateLabel,
  });

  final String avatarUrl;
  final String initials;
  final String fullName;
  final String citizenId;
  final String sectorLabel;
  final String nodeStateLabel;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          fullName,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.6,
            color: dc.onSurface,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          decoration: BoxDecoration(
            color: dc.primaryContainer,
            borderRadius: BorderRadius.circular(999),
          ),
          child: const Text(
            'VERIFIED CITIZEN',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 1,
              color: dc.onPrimaryContainer,
            ),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          'ID: $citizenId',
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: dc.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.location_on, size: 14, color: dc.primary),
            const SizedBox(width: 4),
            Text(
              '$sectorLabel - $nodeStateLabel',
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.7,
                color: dc.primary,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.label,
    required this.value,
    required this.valueColor,
    required this.backgroundColor,
    required this.labelColor,
  });

  final String label;
  final String value;
  final Color valueColor;
  final Color backgroundColor;
  final Color labelColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label.toUpperCase(),
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.1,
              color: labelColor,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.7,
              color: valueColor,
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.title, required this.color});

  final String title;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.3,
          color: color,
        ),
      ),
    );
  }
}

class _GroupedCard extends StatelessWidget {
  const _GroupedCard({required this.backgroundColor, required this.children});

  final Color backgroundColor;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(children: children),
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
          child: Row(
            children: [
              Icon(icon, size: 20, color: dc.onSurfaceVariant),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: dc.onSurface,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 12,
                        color: dc.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: dc.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}

class _ToneDivider extends StatelessWidget {
  const _ToneDivider();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Container(
        height: 1,
        color: dc.outlineVariant.withValues(alpha: 0.12),
      ),
    );
  }
}

class _ConfigTile extends StatelessWidget {
  const _ConfigTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
    required this.backgroundColor,
    required this.busy,
    this.highlight = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  final Color backgroundColor;
  final bool busy;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(20),
        border: highlight
            ? Border.all(color: dc.primary.withValues(alpha: 0.18))
            : null,
      ),
      child: Row(
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              Icon(icon, size: 22, color: dc.primary),
              if (highlight && value)
                Positioned(
                  right: -2,
                  top: -2,
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: dc.primary,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: dc.onSurface,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 12,
                    color: highlight && value ? dc.primary : dc.onSurfaceVariant,
                    fontWeight: highlight && value
                        ? FontWeight.w600
                        : FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          if (busy)
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else
            _PillSwitch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}

class _PillSwitch extends StatelessWidget {
  const _PillSwitch({required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => onChanged(!value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: 44,
        height: 24,
        padding: const EdgeInsets.symmetric(horizontal: 3),
        decoration: BoxDecoration(
          color: value ? dc.primary : dc.secondaryContainer,
          borderRadius: BorderRadius.circular(999),
        ),
        child: AnimatedAlign(
          duration: const Duration(milliseconds: 180),
          alignment: value ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            width: 18,
            height: 18,
            decoration: BoxDecoration(
              color: value ? dc.onPrimary : dc.surfaceContainerLowest,
              shape: BoxShape.circle,
            ),
          ),
        ),
      ),
    );
  }
}

class _SignOutButton extends StatelessWidget {
  const _SignOutButton({
    required this.busy,
    required this.onTap,
  });

  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: busy ? null : onTap,
        borderRadius: BorderRadius.circular(18),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          decoration: BoxDecoration(
            color: dc.surfaceContainerHigh.withValues(alpha: 0.42),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (busy)
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                Icon(
                  Icons.logout,
                  size: 18,
                  color: dc.onSurfaceVariant,
                ),
              const SizedBox(width: 8),
              Text(
                busy ? 'Signing out...' : 'Sign out of Mesh',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: dc.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
