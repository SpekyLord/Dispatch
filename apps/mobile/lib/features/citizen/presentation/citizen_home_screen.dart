import 'package:dispatch_mobile/core/state/mesh_providers.dart';
import 'package:dispatch_mobile/core/theme/dispatch_colors.dart' as dc;
import 'package:dispatch_mobile/features/citizen/presentation/citizen_feed_screen.dart';
import 'package:dispatch_mobile/features/citizen/presentation/citizen_report_form_screen.dart';
import 'package:dispatch_mobile/features/citizen/presentation/citizen_profile_screen.dart';
import 'package:dispatch_mobile/features/mesh/presentation/citizen_mesh_dashboard_screen.dart';
import 'package:dispatch_mobile/features/mesh/presentation/mesh_people_map_screen.dart';
import 'package:dispatch_mobile/features/shared/presentation/widgets/bottom_nav_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class CitizenHomeScreen extends ConsumerStatefulWidget {
  const CitizenHomeScreen({super.key});

  @override
  ConsumerState<CitizenHomeScreen> createState() => _CitizenHomeScreenState();
}

class _CitizenHomeScreenState extends ConsumerState<CitizenHomeScreen> {
  int _selectedIndex = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _autoStartMesh();
    });
  }

  Future<void> _autoStartMesh() async {
    try {
      final transport = ref.read(meshTransportProvider);
      await transport.initialize();
      if (!transport.isDiscovering) {
        await transport.startDiscovery();
      }
    } catch (_) {
      // Mesh support is best-effort on citizen devices.
    }
  }

  void _onItemTapped(int index) {
    if (_selectedIndex == index) {
      return;
    }
    setState(() => _selectedIndex = index);
  }

  Future<void> _openReportComposer() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const CitizenReportFormScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hideBottomNav =
        ref.watch(mapNodeOverlayActiveProvider) && _selectedIndex == 1;
    final pages = [
      CitizenMeshDashboardScreen(onOpenMapTab: () => _onItemTapped(2)),
      const MeshPeopleMapScreen(
        title: 'Mesh Feed Map',
        subtitle: 'Interactive map',
        allowResolveActions: false,
        allowCompassActions: true,
      ),
      CitizenFeedScreen(
        onOpenMapTab: () => _onItemTapped(1),
        onOpenNodesTab: () => _onItemTapped(0),
      ),
      const CitizenProfileScreen(),
    ];

    return Scaffold(
      backgroundColor: dc.background,
      extendBody: true,
      body: IndexedStack(index: _selectedIndex, children: pages),
      bottomNavigationBar: IgnorePointer(
        ignoring: hideBottomNav,
        child: AnimatedSlide(
          offset: hideBottomNav ? const Offset(0, 1.15) : Offset.zero,
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
          child: AnimatedOpacity(
            opacity: hideBottomNav ? 0 : 1,
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            child: AppBottomNavigationBar(
              selectedIndex: _selectedIndex,
              onItemTapped: _onItemTapped,
              onCenterActionTap: _openReportComposer,
            ),
          ),
        ),
      ),
    );
  }
}
