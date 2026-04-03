import 'package:flutter/material.dart';
import 'package:dispatch_mobile/features/shared/presentation/widgets/card.dart';

class DepartmentNewsFeedScreen extends StatelessWidget {
  const DepartmentNewsFeedScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Department Feed'),
      ),
      body: ListView.builder(
        itemCount: 5, // Placeholder
        itemBuilder: (context, index) {
          return ResponsiveCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Our Post Title $index',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                const Text('A description of the post content.'),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    '3 days ago',
                    style: TextStyle(color: Colors.grey[500]),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
