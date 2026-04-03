import 'package:flutter/material.dart';
import 'package:dispatch_mobile/features/shared/presentation/widgets/card.dart';

class DepartmentReportsScreen extends StatelessWidget {
  const DepartmentReportsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Reports'),
      ),
      body: ListView.builder(
        itemCount: 10, // Placeholder
        itemBuilder: (context, index) {
          return ResponsiveCard(
            onTap: () {
              // Navigate to report detail
            },
            child: ListTile(
              title: Text('Report Title $index'),
              subtitle: const Text('Submitted by John Doe'),
              trailing: const Icon(Icons.chevron_right),
            ),
          );
        },
      ),
    );
  }
}
