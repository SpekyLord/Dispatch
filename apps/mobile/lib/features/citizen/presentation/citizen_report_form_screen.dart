// Report form â€” submit a new incident with photos, GPS, and map pin.

import 'package:dispatch_mobile/core/services/location_service.dart';
import 'package:dispatch_mobile/core/services/media_service.dart';
import 'package:dispatch_mobile/core/state/session.dart';
import 'package:dispatch_mobile/features/shared/presentation/location_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart' show ImageSource;
import 'package:latlong2/latlong.dart';
import 'package:dispatch/apps/mobile/lib/features/shared/presentation/widgets/button.dart';

const _categories = [
  ('fire', 'Fire'),
  ('flood', 'Flood'),
  ('earthquake', 'Earthquake'),
  ('road_accident', 'Road Accident'),
  ('medical', 'Medical Emergency'),
  ('structural', 'Structural Damage'),
  ('other', 'Other'),
];

const _severities = [
  ('low', 'Low'),
  ('medium', 'Medium'),
  ('high', 'High'),
  ('critical', 'Critical'),
];

const _maxImages = 3;

class CitizenReportFormScreen extends StatelessWidget {
  const CitizenReportFormScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Submit a Report')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextFormField(
              decoration: const InputDecoration(
                labelText: 'Report Title',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              decoration: const InputDecoration(
                labelText: 'Description',
                border: OutlineInputBorder(),
                alignLabelWithHint: true,
              ),
              maxLines: 5,
            ),
            const SizedBox(height: 16),
            // Placeholder for location picker
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey),
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Row(
                children: [
                  Icon(Icons.location_on),
                  SizedBox(width: 8),
                  Text('Select Location'),
                ],
              ),
            ),
            const SizedBox(height: 16),
            // Placeholder for file attachment
            ResponsiveButton(
              text: 'Attach Photo/Video',
              onPressed: () {},
              buttonType: ButtonType.outlined,
              icon: Icons.attach_file,
            ),
            const SizedBox(height: 24),
            ResponsiveButton(
              text: 'Submit Report',
              onPressed: () {
                // Handle report submission
              },
            ),
          ],
        ),
      ),
    );
  }
}
