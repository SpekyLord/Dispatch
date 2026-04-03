import 'package:dispatch_mobile/features/mesh/presentation/mesh_people_map_screen.dart';
import 'package:flutter/material.dart';

class MunicipalityMeshMapScreen extends StatelessWidget {
  const MunicipalityMeshMapScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const MeshPeopleMapScreen(
      title: 'Mesh & SAR Map',
      subtitle: 'Municipality live topology snapshot',
      allowResolveActions: true,
      allowCompassActions: true,
    );
  }
}
