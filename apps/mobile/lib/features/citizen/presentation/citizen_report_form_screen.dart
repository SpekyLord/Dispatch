import 'dart:async';

import 'package:dispatch_mobile/core/services/location_service.dart';
import 'package:dispatch_mobile/core/services/media_service.dart';
import 'package:dispatch_mobile/core/state/session.dart';
import 'package:dispatch_mobile/core/theme/dispatch_colors.dart' as dc;
import 'package:dispatch_mobile/features/shared/presentation/location_picker.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart' show ImageSource;
import 'package:latlong2/latlong.dart';

const _maxImages = 3;
const _categories = <({String api, String label, IconData icon})>[
  (api: 'fire', label: 'Fire', icon: Icons.local_fire_department_rounded),
  (api: 'flood', label: 'Flood', icon: Icons.water_drop_rounded),
  (api: 'earthquake', label: 'Earthquake', icon: Icons.vibration_rounded),
  (api: 'road_accident', label: 'Road Accident', icon: Icons.car_crash_rounded),
  (api: 'medical', label: 'Medical', icon: Icons.medical_services_rounded),
  (api: 'structural', label: 'Structural', icon: Icons.foundation_rounded),
  (api: 'other', label: 'Other', icon: Icons.more_horiz_rounded),
];
const _severities = <({String api, String label})>[
  (api: 'low', label: 'Low'),
  (api: 'medium', label: 'Moderate'),
  (api: 'high', label: 'High'),
  (api: 'critical', label: 'Critical'),
];

class CitizenReportFormScreen extends ConsumerStatefulWidget {
  const CitizenReportFormScreen({super.key});

  @override
  ConsumerState<CitizenReportFormScreen> createState() =>
      _CitizenReportFormScreenState();
}

class _CitizenReportFormScreenState
    extends ConsumerState<CitizenReportFormScreen> {
  final _titleController = TextEditingController();
  final _detailsController = TextEditingController();
  final _addressController = TextEditingController();
  final List<SelectedMedia> _images = <SelectedMedia>[];

  String _category = 'medical';
  String _severity = 'high';
  bool _loading = false;
  bool _gpsLoading = false;
  bool _manualLocationLocked = false;
  String? _error;
  String _meshStatus = 'Waiting for Mesh Broadcast...';
  double? _latitude;
  double? _longitude;
  double? _accuracyMeters;
  StreamSubscription<LocationData>? _gpsSubscription;

  @override
  void initState() {
    super.initState();
    _gpsSubscription = ref.read(locationServiceProvider).watchPosition().listen(
      (location) {
        if (!mounted) {
          return;
        }
        if (_manualLocationLocked) {
          return;
        }
        setState(() {
          _latitude = location.latitude;
          _longitude = location.longitude;
          _accuracyMeters = location.accuracyMeters;
          _meshStatus = 'Mesh location locked.';
        });
      },
    );
    unawaited(_refreshGps());
  }

  @override
  void dispose() {
    _gpsSubscription?.cancel();
    _titleController.dispose();
    _detailsController.dispose();
    _addressController.dispose();
    super.dispose();
  }

  Future<void> _refreshGps() async {
    if (_gpsLoading) {
      return;
    }
    setState(() {
      _gpsLoading = true;
      _meshStatus = 'Refreshing mesh coordinates...';
    });
    try {
      final location = await ref
          .read(locationServiceProvider)
          .getCurrentPosition();
      if (!mounted) {
        return;
      }
      setState(() {
        _manualLocationLocked = false;
        _latitude = location?.latitude;
        _longitude = location?.longitude;
        _accuracyMeters = location?.accuracyMeters;
        _meshStatus = location == null
            ? 'GPS unavailable. Add a landmark so responders can locate you.'
            : 'Mesh location locked.';
      });
    } catch (_) {
      if (mounted) {
        setState(() => _meshStatus = 'Unable to refresh GPS right now.');
      }
    } finally {
      if (mounted) {
        setState(() => _gpsLoading = false);
      }
    }
  }

  Future<void> _pickLocationManually() async {
    final selected = await showModalBottomSheet<LatLng>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        final initialLatitude = _latitude ?? 14.5995;
        final initialLongitude = _longitude ?? 120.9842;
        LatLng? pendingSelection;

        return StatefulBuilder(
          builder: (context, setModalState) {
            return SafeArea(
              child: Container(
                margin: const EdgeInsets.fromLTRB(12, 24, 12, 12),
                decoration: BoxDecoration(
                  color: dc.surfaceContainerLowest,
                  borderRadius: BorderRadius.circular(28),
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          const Expanded(
                            child: Text(
                              'Pin Incident Location',
                              style: TextStyle(
                                fontFamily: 'Inter',
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                                color: dc.onSurface,
                              ),
                            ),
                          ),
                          IconButton(
                            onPressed: () => Navigator.of(context).pop(),
                            icon: const Icon(Icons.close_rounded),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      const Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Tap the map to drop a manual pin when GPS is weak or drifting.',
                          style: TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 13,
                            height: 1.45,
                            color: dc.onSurfaceVariant,
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      LocationPicker(
                        initialLatitude: initialLatitude,
                        initialLongitude: initialLongitude,
                        height: 320,
                        onLocationSelected: (point) {
                          setModalState(() => pendingSelection = point);
                        },
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () => Navigator.of(context).pop(),
                              child: const Text('Cancel'),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: FilledButton(
                              onPressed: () {
                                Navigator.of(context).pop(
                                  pendingSelection ??
                                      LatLng(initialLatitude, initialLongitude),
                                );
                              },
                              style: FilledButton.styleFrom(
                                backgroundColor: dc.primary,
                                foregroundColor: dc.onPrimary,
                              ),
                              child: const Text('Use pin'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );

    if (!mounted || selected == null) {
      return;
    }

    setState(() {
      _manualLocationLocked = true;
      _latitude = selected.latitude;
      _longitude = selected.longitude;
      _meshStatus = 'Manual map pin locked.';
    });
  }

  Future<void> _pickImage(ImageSource source) async {
    if (_images.length >= _maxImages) {
      setState(
        () => _error = 'You can attach up to $_maxImages photos per report.',
      );
      return;
    }
    final media = source == ImageSource.camera
        ? await ref.read(mediaServiceProvider).pickImageFromCamera()
        : await ref.read(mediaServiceProvider).pickImageFromGallery();
    if (!mounted || media == null) {
      return;
    }
    setState(() {
      _images.add(media);
      _error = null;
      _meshStatus = 'Evidence attached and queued for mesh transfer.';
    });
  }

  void _showImageSourceSheet() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: dc.surfaceContainerLowest,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Attach Photo',
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: dc.onSurface,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Choose a camera capture or an existing image for responders.',
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 13,
                  height: 1.45,
                  color: dc.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 18),
              _sheetAction(Icons.photo_camera_outlined, 'Take Photo', () {
                Navigator.of(context).pop();
                _pickImage(ImageSource.camera);
              }),
              const SizedBox(height: 10),
              _sheetAction(
                Icons.photo_library_outlined,
                'Choose from Gallery',
                () {
                  Navigator.of(context).pop();
                  _pickImage(ImageSource.gallery);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _reportSubmissionError(Object error) {
    if (error is DioException) {
      if (error.type == DioExceptionType.connectionTimeout ||
          error.type == DioExceptionType.sendTimeout ||
          error.type == DioExceptionType.receiveTimeout ||
          error.type == DioExceptionType.connectionError) {
        return 'Unable to reach the server right now. Check the mobile API URL and your connection, then try again.';
      }
      final payload = error.response?.data;
      if (payload is Map<String, dynamic>) {
        final apiError = payload['error'];
        if (apiError is Map<String, dynamic>) {
          final message = apiError['message'] as String?;
          if (message != null && message.isNotEmpty) {
            return message;
          }
        }
      }
      if (error.message != null && error.message!.isNotEmpty) {
        return error.message!;
      }
    }
    return 'Unable to submit the report right now. Please try again.';
  }

  Future<void> _submitReport() async {
    if (_loading) {
      return;
    }
    final title = _titleController.text.trim();
    final details = _detailsController.text.trim();
    final address = _addressController.text.trim();
    if (title.isEmpty && details.isEmpty) {
      setState(
        () =>
            _error = 'Add a title or describe the situation before submitting.',
      );
      return;
    }
    final description = title.isEmpty
        ? details
        : details.isEmpty
        ? title
        : '$title\n$details';
    setState(() {
      _loading = true;
      _error = null;
      _meshStatus = 'Submitting report to Dispatch...';
    });
    try {
      final auth = ref.read(authServiceProvider);
      final result = await auth.createReport(
        title: title.isEmpty ? null : title,
        description: description,
        category: _category,
        severity: _severity,
        address: address.isEmpty ? null : address,
        latitude: _latitude,
        longitude: _longitude,
      );
      final report = result['report'] as Map<String, dynamic>? ?? result;
      final reportId = (report['id'] ?? report['report_id'] ?? report['uuid'])
          ?.toString();
      if (reportId != null) {
        for (final image in _images) {
          await auth.uploadReportImage(reportId, image);
        }
      }
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Report submitted successfully.')),
      );
      Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = _reportSubmissionError(e);
          _meshStatus = 'Report submission failed. Retrying is safe.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasDraft =
        _titleController.text.trim().isNotEmpty ||
        _detailsController.text.trim().isNotEmpty;
    final progress = _loading
        ? 0.82
        : _images.isNotEmpty
        ? 0.56
        : hasDraft
        ? 0.38
        : 0.24;
    final connectionLabel = _accuracyMeters == null
        ? 'Node connection: Awaiting GPS lock'
        : _accuracyMeters! <= 15
        ? 'Node connection: Strong mesh tag'
        : _accuracyMeters! <= 40
        ? 'Node connection: Stable mesh tag'
        : 'Node connection: Approximate mesh tag';

    return Scaffold(
      backgroundColor: dc.background,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 0),
              child: Row(
                children: [
                  const Icon(
                    Icons.warning_amber_rounded,
                    color: dc.primary,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Disaster Report',
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: dc.onSurface,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Refresh location',
                    onPressed: _gpsLoading ? null : _refreshGps,
                    splashRadius: 20,
                    icon: _gpsLoading
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.2,
                              color: dc.primary,
                            ),
                          )
                        : const Icon(
                            Icons.sync_rounded,
                            color: dc.onSurfaceVariant,
                            size: 20,
                          ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 32),
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 10, 8, 22),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'EMERGENCY PROTOCOL',
                          style: TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.1,
                            color: dc.primary.withValues(alpha: 0.75),
                          ),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'Submit Incident',
                          style: TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 35,
                            height: 1.05,
                            fontWeight: FontWeight.w900,
                            color: dc.onSurface,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Document critical incidents for immediate broadcast to the surrounding mesh nodes. Accuracy saves lives.',
                          style: TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 13,
                            height: 1.45,
                            color: dc.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (_error != null)
                    Container(
                      margin: const EdgeInsets.only(bottom: 14),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: dc.errorContainer.withValues(alpha: 0.22),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: dc.error.withValues(alpha: 0.18),
                        ),
                      ),
                      child: Text(
                        _error!,
                        style: const TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 12,
                          height: 1.45,
                          color: dc.onErrorContainer,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  _sectionCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _sectionLabel('REPORT TITLE (OPTIONAL)'),
                        const SizedBox(height: 10),
                        _input(
                          controller: _titleController,
                          hintText: 'e.g. Flooded intersection at Main St',
                          textInputAction: TextInputAction.next,
                          onChanged: (_) => setState(() {}),
                        ),
                        const SizedBox(height: 18),
                        _sectionLabel('1. INCIDENT CATEGORY'),
                        const SizedBox(height: 12),
                        GridView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: _categories.length,
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 2,
                                crossAxisSpacing: 10,
                                mainAxisSpacing: 10,
                                childAspectRatio: 1.3,
                              ),
                          itemBuilder: (context, index) {
                            final item = _categories[index];
                            final selected = item.api == _category;
                            return Material(
                              color: Colors.transparent,
                              child: InkWell(
                                onTap: () =>
                                    setState(() => _category = item.api),
                                borderRadius: BorderRadius.circular(12),
                                child: Ink(
                                  decoration: BoxDecoration(
                                    color: selected
                                        ? dc.primaryContainer.withValues(
                                            alpha: 0.78,
                                          )
                                        : dc.surfaceContainerLowest,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: selected
                                          ? dc.primary
                                          : dc.outlineVariant,
                                      width: selected ? 1.4 : 1,
                                    ),
                                  ),
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        item.icon,
                                        size: 18,
                                        color: selected
                                            ? dc.onPrimaryContainer
                                            : dc.onSurfaceVariant,
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        item.label,
                                        style: TextStyle(
                                          fontFamily: 'Inter',
                                          fontSize: 11,
                                          fontWeight: selected
                                              ? FontWeight.w800
                                              : FontWeight.w600,
                                          color: selected
                                              ? dc.onPrimaryContainer
                                              : dc.onSurfaceVariant,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  _sectionCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _sectionLabel('2. SEVERITY LEVEL'),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: _severities.map((item) {
                            final selected = item.api == _severity;
                            return Material(
                              color: Colors.transparent,
                              child: InkWell(
                                onTap: () =>
                                    setState(() => _severity = item.api),
                                borderRadius: BorderRadius.circular(999),
                                child: Ink(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 8,
                                  ),
                                  decoration: BoxDecoration(
                                    color: selected
                                        ? dc.primaryContainer
                                        : dc.surfaceContainerLowest,
                                    borderRadius: BorderRadius.circular(999),
                                    border: Border.all(
                                      color: selected
                                          ? dc.primary
                                          : dc.outline.withValues(alpha: 0.6),
                                      width: selected ? 1.4 : 1,
                                    ),
                                  ),
                                  child: Text(
                                    item.label,
                                    style: TextStyle(
                                      fontFamily: 'Inter',
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      color: selected
                                          ? dc.primary
                                          : dc.onSurfaceVariant,
                                    ),
                                  ),
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  _sectionCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _sectionLabel('3. SITUATION DETAILS'),
                        const SizedBox(height: 12),
                        _input(
                          controller: _detailsController,
                          hintText: 'Describe the situation clearly...',
                          minLines: 5,
                          maxLines: 5,
                          textInputAction: TextInputAction.newline,
                          onChanged: (_) => setState(() {}),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  _sectionCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _sectionLabel('4. EVIDENCE'),
                        const SizedBox(height: 10),
                        const Text(
                          'Attach a photo for responders. Compressed for mesh transfer.',
                          style: TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 11,
                            height: 1.4,
                            color: dc.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 14),
                        Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: _loading ? null : _showImageSourceSheet,
                            borderRadius: BorderRadius.circular(12),
                            child: Ink(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 14,
                              ),
                              decoration: BoxDecoration(
                                color: dc.secondaryContainer,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.add_a_photo_outlined,
                                    color: dc.onSecondaryContainer,
                                    size: 18,
                                  ),
                                  SizedBox(width: 8),
                                  Text(
                                    'Attach Photo',
                                    style: TextStyle(
                                      fontFamily: 'Inter',
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                      color: dc.onSecondaryContainer,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        if (_images.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          SizedBox(
                            height: 86,
                            child: ListView.separated(
                              scrollDirection: Axis.horizontal,
                              itemCount: _images.length,
                              separatorBuilder: (_, _) =>
                                  const SizedBox(width: 10),
                              itemBuilder: (context, index) {
                                final image = _images[index];
                                return SizedBox(
                                  width: 86,
                                  child: Stack(
                                    children: [
                                      ClipRRect(
                                        borderRadius: BorderRadius.circular(12),
                                        child: Image.memory(
                                          image.bytes,
                                          width: 86,
                                          height: 86,
                                          fit: BoxFit.cover,
                                        ),
                                      ),
                                      Positioned(
                                        top: 6,
                                        right: 6,
                                        child: Material(
                                          color: Colors.black.withValues(
                                            alpha: 0.5,
                                          ),
                                          shape: const CircleBorder(),
                                          child: InkWell(
                                            onTap: () => setState(
                                              () => _images.remove(image),
                                            ),
                                            customBorder: const CircleBorder(),
                                            child: const Padding(
                                              padding: EdgeInsets.all(4),
                                              child: Icon(
                                                Icons.close,
                                                color: Colors.white,
                                                size: 14,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  _sectionCard(
                    child: SizedBox(
                      height: 184,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          DecoratedBox(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(14),
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [
                                  dc.surfaceContainerHighest.withValues(
                                    alpha: 0.95,
                                  ),
                                  dc.surfaceContainerLow.withValues(
                                    alpha: 0.88,
                                  ),
                                ],
                              ),
                            ),
                            child: Stack(
                              children: [
                                Positioned(
                                  left: -30,
                                  top: -22,
                                  child: Container(
                                    width: 112,
                                    height: 112,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: dc.primary.withValues(alpha: 0.08),
                                    ),
                                  ),
                                ),
                                Positioned(
                                  right: -18,
                                  bottom: -18,
                                  child: Container(
                                    width: 120,
                                    height: 120,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: dc.onSurface.withValues(
                                        alpha: 0.03,
                                      ),
                                    ),
                                  ),
                                ),
                                Positioned.fill(
                                  child: CustomPaint(
                                    painter: _MeshGridPainter(),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.all(14),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '5. MESH LOCATION',
                                  style: TextStyle(
                                    fontFamily: 'Inter',
                                    fontSize: 9,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 1.1,
                                    color: dc.primary.withValues(alpha: 0.85),
                                  ),
                                ),
                                const Spacer(),
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Padding(
                                      padding: EdgeInsets.only(top: 2),
                                      child: Icon(
                                        Icons.location_on_rounded,
                                        color: dc.primary,
                                        size: 20,
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Text(
                                        _coordinatesLabel,
                                        style: const TextStyle(
                                          fontFamily: 'Inter',
                                          fontSize: 18,
                                          height: 1.2,
                                          fontWeight: FontWeight.w800,
                                          color: dc.onSurface,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 5,
                                  ),
                                  decoration: BoxDecoration(
                                    color: dc.primary,
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                  child: Text(
                                    _latitude == null || _longitude == null
                                        ? 'SEARCHING FOR MESH TAG'
                                        : _manualLocationLocked
                                        ? 'MANUAL MAP PIN'
                                        : 'ACTIVE MESH TAGGING',
                                    style: const TextStyle(
                                      fontFamily: 'Inter',
                                      fontSize: 9,
                                      fontWeight: FontWeight.w800,
                                      color: dc.onPrimary,
                                      letterSpacing: 0.8,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  _meshStatus,
                                  style: TextStyle(
                                    fontFamily: 'Inter',
                                    fontSize: 11,
                                    color: dc.onSurface.withValues(alpha: 0.72),
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Row(
                                  children: [
                                    Expanded(
                                      child: OutlinedButton.icon(
                                        onPressed: _pickLocationManually,
                                        icon: const Icon(
                                          Icons.push_pin_outlined,
                                        ),
                                        label: const Text('Pin on map'),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: OutlinedButton.icon(
                                        onPressed: _gpsLoading
                                            ? null
                                            : _refreshGps,
                                        icon: const Icon(
                                          Icons.gps_fixed_rounded,
                                        ),
                                        label: const Text('Use GPS'),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  _sectionCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _sectionLabel('ADDRESS OR LANDMARK (OPTIONAL)'),
                        const SizedBox(height: 10),
                        _input(
                          controller: _addressController,
                          hintText: 'e.g. Near the Central Park entrance',
                          textInputAction: TextInputAction.done,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 22),
                  _broadcastButton(),
                  const SizedBox(height: 18),
                  _syncStatus(progress, connectionLabel),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionCard({required Widget child}) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: dc.surfaceContainerLow,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: dc.outlineVariant.withValues(alpha: 0.7)),
    ),
    child: child,
  );

  Widget _sectionLabel(String text) => Text(
    text,
    style: const TextStyle(
      fontFamily: 'Inter',
      fontSize: 9,
      fontWeight: FontWeight.w800,
      letterSpacing: 1.0,
      color: dc.onSurfaceVariant,
    ),
  );

  Widget _input({
    required TextEditingController controller,
    required String hintText,
    int minLines = 1,
    int maxLines = 1,
    TextInputAction? textInputAction,
    ValueChanged<String>? onChanged,
  }) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: dc.surfaceContainerHighest.withValues(alpha: 0.58),
        borderRadius: BorderRadius.circular(12),
      ),
      child: TextField(
        controller: controller,
        minLines: minLines,
        maxLines: maxLines,
        onChanged: onChanged,
        textInputAction: textInputAction,
        style: const TextStyle(
          fontFamily: 'Inter',
          fontSize: 13,
          height: 1.4,
          color: dc.onSurface,
        ),
        decoration: InputDecoration(
          hintText: hintText,
          hintStyle: TextStyle(
            fontFamily: 'Inter',
            fontSize: 13,
            color: dc.onSurfaceVariant.withValues(alpha: 0.48),
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 14,
          ),
          border: InputBorder.none,
        ),
      ),
    );
  }

  Widget _sheetAction(IconData icon, String label, VoidCallback onTap) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(
            color: dc.surfaceContainerLow,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              Icon(icon, color: dc.primary, size: 20),
              const SizedBox(width: 10),
              Text(
                label,
                style: const TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: dc.onSurface,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _broadcastButton() {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _loading ? null : _submitReport,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [dc.primary, dc.primaryDim],
            ),
            boxShadow: [
              BoxShadow(
                color: dc.primary.withValues(alpha: 0.24),
                blurRadius: 18,
                offset: const Offset(0, 7),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (_loading) ...[
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.2,
                    color: dc.onPrimary,
                  ),
                ),
                const SizedBox(width: 12),
              ] else ...[
                const Icon(Icons.cell_tower_rounded, color: dc.onPrimary),
                const SizedBox(width: 10),
              ],
              Text(
                _loading ? 'Broadcasting...' : 'Broadcast to Mesh',
                style: const TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: dc.onPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _syncStatus(double progress, String connectionLabel) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: dc.primary,
                borderRadius: BorderRadius.circular(999),
                boxShadow: [
                  BoxShadow(
                    color: dc.primary.withValues(alpha: 0.25),
                    blurRadius: 10,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                _meshStatus,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: dc.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: Container(
            height: 5,
            color: dc.surfaceContainerHighest,
            child: FractionallySizedBox(
              widthFactor: progress.clamp(0.12, 1.0).toDouble(),
              alignment: Alignment.centerLeft,
              child: Container(color: dc.primary),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          connectionLabel,
          style: TextStyle(
            fontFamily: 'Inter',
            fontSize: 10,
            color: dc.onSurfaceVariant.withValues(alpha: 0.7),
          ),
        ),
      ],
    );
  }

  String get _coordinatesLabel {
    if (_latitude == null || _longitude == null) {
      return 'Acquiring mesh coordinates...';
    }
    return '${_formatAxis(_latitude!, 'N', 'S')}, ${_formatAxis(_longitude!, 'E', 'W')}';
  }

  String _formatAxis(double value, String positive, String negative) {
    final direction = value >= 0 ? positive : negative;
    return '${value.abs().toStringAsFixed(4)}° $direction';
  }
}

class _MeshGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final linePaint = Paint()
      ..color = dc.onSurface.withValues(alpha: 0.06)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (var x = -size.height; x < size.width + size.height; x += 26) {
      canvas.drawLine(
        Offset(x.toDouble(), 0),
        Offset(x + size.height, size.height),
        linePaint,
      );
    }
    for (var y = 18.0; y < size.height; y += 24) {
      canvas.drawLine(
        Offset(0, y),
        Offset(size.width, y),
        linePaint..color = dc.primary.withValues(alpha: 0.04),
      );
      linePaint.color = dc.onSurface.withValues(alpha: 0.06);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
