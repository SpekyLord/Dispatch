import 'package:dispatch_mobile/core/state/mesh_providers.dart';
import 'package:dispatch_mobile/core/theme/dispatch_colors.dart' as dc;
import 'package:dispatch_mobile/features/citizen/presentation/citizen_feed_screen.dart';
import 'package:dispatch_mobile/features/citizen/presentation/citizen_profile_screen.dart';
import 'package:dispatch_mobile/features/mesh/presentation/mesh_people_map_screen.dart';
import 'package:dispatch_mobile/features/mesh/presentation/mesh_status_screen.dart';
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

  @override
  Widget build(BuildContext context) {
    final pages = [
      CitizenFeedScreen(
        onOpenMapTab: () => _onItemTapped(1),
        onOpenNodesTab: () => _onItemTapped(2),
      ),
      const MeshPeopleMapScreen(
        title: 'Mesh Feed Map',
        subtitle: 'Interactive map',
        allowResolveActions: false,
        allowCompassActions: true,
      ),
      const MeshStatusScreen(),
      const CitizenProfileScreen(),
    ];

    return Scaffold(
      backgroundColor: dc.background,
      extendBody: true,
      body: IndexedStack(index: _selectedIndex, children: pages),
      bottomNavigationBar: AppBottomNavigationBar(
        selectedIndex: _selectedIndex,
        onItemTapped: _onItemTapped,
      ),
    );
  }
}
