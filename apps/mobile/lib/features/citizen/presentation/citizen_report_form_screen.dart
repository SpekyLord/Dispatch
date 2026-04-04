// Report form -- submit a new incident with photos, GPS, and map pin.

import 'dart:async';

import 'package:dispatch_mobile/core/services/location_service.dart';
import 'package:dispatch_mobile/core/services/media_service.dart';
import 'package:dispatch_mobile/core/state/session.dart';
import 'package:dispatch_mobile/core/theme/dispatch_colors.dart' as dc;
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

class CitizenReportFormScreen extends ConsumerStatefulWidget {
  const CitizenReportFormScreen({super.key});

  @override
  ConsumerState<CitizenReportFormScreen> createState() =>
      _CitizenReportFormScreenState();
}

class _CitizenReportFormScreenState
    extends ConsumerState<CitizenReportFormScreen> {
  final _titleController = TextEditingController();
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
  StreamSubscription<LocationData>? _gpsSubscription;

  // Images
  final List<SelectedMedia> _images = [];

  @override
  void initState() {
    super.initState();
    _startGpsWatch();
    _detectGps();
  }

  @override
  void dispose() {
    _gpsSubscription?.cancel();
    _titleController.dispose();
    _descController.dispose();
    _addressController.dispose();
    super.dispose();
  }

  void _startGpsWatch() {
    _gpsSubscription = ref
        .read(locationServiceProvider)
        .watchPosition()
        .listen((location) {
          if (!mounted) {
            return;
          }

          setState(() {
            if (!_hasUserPinnedLocation) {
              _latitude = location.latitude;
              _longitude = location.longitude;
            }
            _gpsStatus = 'GPS acquired';
          });
        });
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
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Add a photo',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 12),
              ResponsiveButton(
                text: 'Take Photo',
                onPressed: () {
                  Navigator.of(context).pop();
                  _pickImage(ImageSource.camera);
                },
                icon: Icons.photo_camera,
              ),
              const SizedBox(height: 8),
              ResponsiveButton(
                text: 'Choose from Gallery',
                onPressed: () {
                  Navigator.of(context).pop();
                  _pickImage(ImageSource.gallery);
                },
                buttonType: ButtonType.outlined,
                icon: Icons.photo_library_outlined,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _submitReport() async {
    if (_loading) {
      return;
    }

    final title = _titleController.text.trim();
    final description = _descController.text.trim();
    final address = _addressController.text.trim();

    if (_category == null) {
      setState(() => _error = 'Please select a category.');
      return;
    }

    if (title.isEmpty && description.isEmpty) {
      setState(() => _error = 'Please add a title or description.');
      return;
    }

    final combinedDescription = title.isEmpty
        ? description
        : description.isEmpty
            ? title
            : '$title\n$description';

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final auth = ref.read(authServiceProvider);
      final result = await auth.createReport(
        description: combinedDescription,
        category: _category!,
        severity: _severity,
        address: address.isEmpty ? null : address,
        latitude: _latitude,
        longitude: _longitude,
      );

      final report = result['report'] as Map<String, dynamic>? ?? result;
      final reportId =
          (report['id'] ?? report['report_id'] ?? report['uuid'])?.toString();

      if (reportId != null) {
        for (final image in _images) {
          await auth.uploadReportImage(reportId, image);
        }
      }

      if (!mounted) {
        return;
      }

      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Report submitted.')),
      );
      Navigator.of(context).pop();
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loading = false;
        _error = 'Unable to submit report. Please try again.';
      });
    }
  }

  Widget _buildChoiceChips({
    required List<(String, String)> options,
    required String? selected,
    required ValueChanged<String> onSelected,
  }) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: options.map((option) {
        final isSelected = option.$1 == selected;
        return ChoiceChip(
          label: Text(option.$2),
          selected: isSelected,
          onSelected: (_) => onSelected(option.$1),
        );
      }).toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Submit a Report')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_error != null)
            Container(
              padding: const EdgeInsets.all(12),
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: dc.statusError.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                _error!,
                style: TextStyle(color: dc.statusError),
              ),
            ),
          TextField(
            controller: _titleController,
            decoration: const InputDecoration(
              labelText: 'Report title',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _descController,
            decoration: const InputDecoration(
              labelText: 'Description',
              border: OutlineInputBorder(),
              alignLabelWithHint: true,
            ),
            maxLines: 4,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _addressController,
            decoration: const InputDecoration(
              labelText: 'Address or landmark',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Category',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          _buildChoiceChips(
            options: _categories,
            selected: _category,
            onSelected: (value) => setState(() => _category = value),
          ),
          const SizedBox(height: 16),
          const Text(
            'Severity',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          _buildChoiceChips(
            options: _severities,
            selected: _severity,
            onSelected: (value) => setState(() => _severity = value),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              const Text(
                'Location',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              const Spacer(),
              if (_gpsLoading)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
            ],
          ),
          if (_gpsStatus != null) ...[
            const SizedBox(height: 6),
            Text(_gpsStatus!, style: const TextStyle(color: Colors.black54)),
          ],
          const SizedBox(height: 10),
          LocationPicker(
            initialLatitude: _latitude ?? 14.5995,
            initialLongitude: _longitude ?? 120.9842,
            onLocationSelected: _onLocationSelected,
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              const Text(
                'Photos',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              const Spacer(),
              Text('${_images.length}/$_maxImages'),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final image in _images)
                Stack(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Image.memory(
                        image.bytes,
                        width: 90,
                        height: 90,
                        fit: BoxFit.cover,
                      ),
                    ),
                    Positioned(
                      right: 4,
                      top: 4,
                      child: InkWell(
                        onTap: () => setState(() => _images.remove(image)),
                        child: Container(
                          decoration: const BoxDecoration(
                            color: Colors.black54,
                            shape: BoxShape.circle,
                          ),
                          child: const Padding(
                            padding: EdgeInsets.all(2),
                            child: Icon(Icons.close, size: 16, color: Colors.white),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              if (_images.length < _maxImages)
                OutlinedButton.icon(
                  onPressed: _showImageSourceSheet,
                  icon: const Icon(Icons.add_a_photo_outlined),
                  label: const Text('Add'),
                ),
            ],
          ),
          const SizedBox(height: 24),
          ResponsiveButton(
            text: _loading ? 'Submitting...' : 'Submit Report',
            onPressed: _loading ? () {} : () => _submitReport(),
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }
}
