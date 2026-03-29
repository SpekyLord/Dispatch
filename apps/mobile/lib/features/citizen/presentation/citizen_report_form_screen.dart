// Report form — submit a new incident with photos, GPS, and map pin.

import 'package:dispatch_mobile/core/services/location_service.dart';
import 'package:dispatch_mobile/core/services/media_service.dart';
import 'package:dispatch_mobile/core/state/session_controller.dart';
import 'package:dispatch_mobile/features/shared/presentation/location_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart' show ImageSource;
import 'package:latlong2/latlong.dart';

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

class CitizenReportFormScreen extends ConsumerStatefulWidget {
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
          _latitude = loc.latitude;
          _longitude = loc.longitude;
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
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: const Text('Camera'),
              onTap: () {
                Navigator.pop(context);
                _pickImage(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Gallery'),
              onTap: () {
                Navigator.pop(context);
                _pickImage(ImageSource.gallery);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _submit() async {
    if (_category == null) {
      setState(() => _error = 'Please select a category.');
      return;
    }
    if (_descController.text.trim().isEmpty) {
      setState(() => _error = 'Description is required.');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final authService = ref.read(authServiceProvider);
      final result = await authService.createReport(
        description: _descController.text.trim(),
        category: _category!,
        severity: _severity,
        address: _addressController.text.trim().isNotEmpty
            ? _addressController.text.trim()
            : null,
        latitude: _latitude,
        longitude: _longitude,
      );

      // Upload images
      final reportId =
          (result['report'] as Map<String, dynamic>?)?['id'] as String?;
      if (reportId != null) {
        for (final img in _images) {
          await authService.uploadReportImage(reportId, img);
        }
      }

      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = e.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('New Report')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          if (_error != null)
            Container(
              padding: const EdgeInsets.all(12),
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red.shade200),
              ),
              child: Text(
                _error!,
                style: TextStyle(color: Colors.red.shade700),
              ),
            ),

          // Description
          TextField(
            controller: _descController,
            decoration: const InputDecoration(
              labelText: 'Description *',
              hintText: 'Describe the incident in detail...',
              border: OutlineInputBorder(),
            ),
            maxLines: 4,
          ),
          const SizedBox(height: 16),

          // Category
          DropdownButtonFormField<String>(
            initialValue: _category,
            decoration: const InputDecoration(
              labelText: 'Category *',
              border: OutlineInputBorder(),
            ),
            items: _categories
                .map((c) => DropdownMenuItem(value: c.$1, child: Text(c.$2)))
                .toList(),
            onChanged: (v) => setState(() => _category = v),
          ),
          const SizedBox(height: 16),

          // Severity
          DropdownButtonFormField<String>(
            initialValue: _severity,
            decoration: const InputDecoration(
              labelText: 'Severity',
              border: OutlineInputBorder(),
            ),
            items: _severities
                .map((s) => DropdownMenuItem(value: s.$1, child: Text(s.$2)))
                .toList(),
            onChanged: (v) => setState(() => _severity = v ?? 'medium'),
          ),
          const SizedBox(height: 16),

          // Address
          TextField(
            controller: _addressController,
            decoration: const InputDecoration(
              labelText: 'Address / Location',
              hintText: 'e.g. Corner of Rizal Ave and Mabini St',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),

          // GPS status
          if (_gpsLoading)
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  SizedBox(width: 8),
                  Text(
                    'Detecting location...',
                    style: TextStyle(fontSize: 13, color: Colors.black54),
                  ),
                ],
              ),
            )
          else if (_gpsStatus != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                _latitude != null
                    ? 'GPS: ${_latitude!.toStringAsFixed(4)}, ${_longitude!.toStringAsFixed(4)}'
                    : _gpsStatus!,
                style: TextStyle(
                  fontSize: 13,
                  color: _latitude != null ? Colors.green : Colors.black54,
                ),
              ),
            ),

          // Location picker map
          Text('Pin Location', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          LocationPicker(
            initialLatitude: _latitude ?? 14.5995,
            initialLongitude: _longitude ?? 120.9842,
            height: 200,
            onLocationSelected: _onLocationSelected,
          ),
          const SizedBox(height: 16),

          // Image picker
          Row(
            children: [
              Text(
                'Photos (${_images.length}/$_maxImages)',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const Spacer(),
              if (_images.length < _maxImages)
                TextButton.icon(
                  onPressed: _showImageSourceSheet,
                  icon: const Icon(Icons.add_a_photo, size: 18),
                  label: const Text('Add Photo'),
                ),
            ],
          ),
          if (_images.isNotEmpty) ...[
            const SizedBox(height: 8),
            SizedBox(
              height: 100,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _images.length,
                separatorBuilder: (context, index) => const SizedBox(width: 8),
                itemBuilder: (_, i) => Stack(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.memory(
                        _images[i].bytes,
                        width: 100,
                        height: 100,
                        fit: BoxFit.cover,
                      ),
                    ),
                    Positioned(
                      top: 2,
                      right: 2,
                      child: GestureDetector(
                        onTap: () => setState(() => _images.removeAt(i)),
                        child: Container(
                          padding: const EdgeInsets.all(2),
                          decoration: const BoxDecoration(
                            color: Colors.black54,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.close,
                            size: 16,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 24),

          // Submit
          FilledButton(
            onPressed: _loading ? null : _submit,
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
            ),
            child: Text(_loading ? 'Submitting...' : 'Submit Report'),
          ),
        ],
      ),
    );
  }
}
