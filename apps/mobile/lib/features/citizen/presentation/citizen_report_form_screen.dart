// Report form â€” submit a new incident with photos, GPS, and map pin.

import 'package:dispatch_mobile/core/services/location_service.dart';
import 'package:dispatch_mobile/core/services/media_service.dart';
import 'package:dispatch_mobile/core/state/session.dart';
import 'package:dispatch_mobile/features/shared/presentation/location_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart' show ImageSource;
import 'package:latlong2/latlong.dart';
import 'package:dispatch_mobile/features/shared/presentation/widgets/button.dart';

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
  ConsumerState<CitizenReportFormScreen> createState() =>
      _CitizenReportFormScreenState();
}

class _CitizenReportFormScreenState
    extends ConsumerState<CitizenReportFormScreen> {
  final _descController = TextEditingController();
  final _addressController = TextEditingController();
  String? _category;
  String _severity = 'medium';
  bool _loading = false;
  String? _error;

  // Location
  double? _latitude;
  double? _longitude;
  bool _gpsLoading = false;
  String? _gpsStatus;
  bool _hasUserPinnedLocation = false;

  // Images
  final List<SelectedMedia> _images = [];

  @override
  void initState() {
    super.initState();
    _detectGps();
  }

  @override
  void dispose() {
    _descController.dispose();
    _addressController.dispose();
    super.dispose();
  }

  Future<void> _detectGps() async {
    setState(() => _gpsLoading = true);
    try {
      final loc = await ref.read(locationServiceProvider).getCurrentPosition();
      if (loc != null && mounted) {
        setState(() {
          if (!_hasUserPinnedLocation) {
            _latitude = loc.latitude;
            _longitude = loc.longitude;
          }
          _gpsStatus = 'GPS acquired';
        });
      } else if (mounted) {
        setState(
          () => _gpsStatus =
              'GPS unavailable. Pick location on map or enter address.',
        );
      }
    } catch (_) {
      if (mounted) {
        setState(() => _gpsStatus = 'GPS unavailable.');
      }
    } finally {
      if (mounted) setState(() => _gpsLoading = false);
    }
  }

  void _onLocationSelected(LatLng point) {
    setState(() {
      _hasUserPinnedLocation = true;
      _latitude = point.latitude;
      _longitude = point.longitude;
    });
  }

  Future<void> _pickImage(ImageSource source) async {
    if (_images.length >= _maxImages) {
      setState(() => _error = 'Maximum $_maxImages images allowed.');
      return;
    }
    final media = source == ImageSource.camera
        ? await ref.read(mediaServiceProvider).pickImageFromCamera()
        : await ref.read(mediaServiceProvider).pickImageFromGallery();
    if (media != null && mounted) {
      setState(() {
        _images.add(media);
        _error = null;
      });
    }
  }

  void _showImageSourceSheet() {
    showModalBottomSheet(
      context: context,
      builder: (_) => SafeArea(
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
