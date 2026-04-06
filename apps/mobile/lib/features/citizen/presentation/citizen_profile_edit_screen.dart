import 'dart:typed_data';

import 'package:dispatch_mobile/core/services/media_service.dart';
import 'package:dispatch_mobile/core/state/session.dart';
import 'package:dispatch_mobile/core/theme/dispatch_colors.dart' as dc;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class CitizenProfileEditResult {
  const CitizenProfileEditResult(this.profile);

  final Map<String, dynamic> profile;
}

class CitizenProfileEditScreen extends ConsumerStatefulWidget {
  const CitizenProfileEditScreen({
    required this.initialFullName,
    required this.initialPhone,
    required this.initialDescription,
    required this.initialProfilePictureUrl,
    required this.initialHeaderPhotoUrl,
    super.key,
  });

  final String initialFullName;
  final String initialPhone;
  final String initialDescription;
  final String? initialProfilePictureUrl;
  final String? initialHeaderPhotoUrl;

  @override
  ConsumerState<CitizenProfileEditScreen> createState() =>
      _CitizenProfileEditScreenState();
}

class _CitizenProfileEditScreenState
    extends ConsumerState<CitizenProfileEditScreen> {
  late final TextEditingController _fullNameController;
  late final TextEditingController _phoneController;
  late final TextEditingController _descriptionController;

  SelectedMedia? _profilePicture;
  SelectedMedia? _headerPhoto;
  bool _removeProfilePicture = false;
  bool _removeHeaderPhoto = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _fullNameController = TextEditingController(text: widget.initialFullName);
    _phoneController = TextEditingController(text: widget.initialPhone);
    _descriptionController = TextEditingController(
      text: widget.initialDescription,
    );
  }

  @override
  void dispose() {
    _fullNameController.dispose();
    _phoneController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _pickProfilePicture() async {
    final image = await ref.read(mediaServiceProvider).pickImageFromGallery();
    if (!mounted || image == null) {
      return;
    }
    setState(() {
      _profilePicture = image;
      _removeProfilePicture = false;
    });
  }

  Future<void> _pickHeaderPhoto() async {
    final image = await ref.read(mediaServiceProvider).pickImageFromGallery();
    if (!mounted || image == null) {
      return;
    }
    setState(() {
      _headerPhoto = image;
      _removeHeaderPhoto = false;
    });
  }

  Future<void> _save() async {
    if (_saving) {
      return;
    }
    setState(() => _saving = true);

    try {
      final response = await ref
          .read(authServiceProvider)
          .updateProfileMultipart(
            fullName: _fullNameController.text.trim(),
            phone: _phoneController.text.trim(),
            description: _descriptionController.text.trim(),
            profilePicture: _profilePicture,
            headerPhoto: _headerPhoto,
            removeProfilePicture: _removeProfilePicture,
            removeHeaderPhoto: _removeHeaderPhoto,
          );
      final profile =
          (response['profile'] as Map<String, dynamic>?) ?? response;
      if (!mounted) {
        return;
      }
      Navigator.of(context).pop(CitizenProfileEditResult(profile));
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to save your profile right now.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final profilePicturePreview =
        _profilePicture ?? (_removeProfilePicture ? null : null);
    final headerPhotoPreview =
        _headerPhoto ?? (_removeHeaderPhoto ? null : null);

    return Scaffold(
      backgroundColor: dc.background,
      appBar: AppBar(
        title: const Text('Edit Profile'),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: Text(_saving ? 'Saving...' : 'Save'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          _MediaCard(
            title: 'Header photo',
            subtitle:
                'Show your location context or a recognizable community view.',
            onPick: _pickHeaderPhoto,
            onRemove: () => setState(() {
              _headerPhoto = null;
              _removeHeaderPhoto = true;
            }),
            previewBytes: headerPhotoPreview?.bytes,
            previewUrl: _removeHeaderPhoto
                ? null
                : widget.initialHeaderPhotoUrl,
          ),
          const SizedBox(height: 14),
          _MediaCard(
            title: 'Profile picture',
            subtitle:
                'This image appears beside your citizen profile and activity.',
            onPick: _pickProfilePicture,
            onRemove: () => setState(() {
              _profilePicture = null;
              _removeProfilePicture = true;
            }),
            previewBytes: profilePicturePreview?.bytes,
            previewUrl: _removeProfilePicture
                ? null
                : widget.initialProfilePictureUrl,
            circular: true,
          ),
          const SizedBox(height: 14),
          _FormCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Display name',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _fullNameController,
                  decoration: const InputDecoration(
                    hintText: 'Full name',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 14),
                const Text(
                  'Phone number',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _phoneController,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    hintText: '+63 900 000 0000',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 14),
                const Text(
                  'Bio',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _descriptionController,
                  minLines: 4,
                  maxLines: 6,
                  decoration: const InputDecoration(
                    hintText:
                        'Tell responders or neighbors what area you usually monitor.',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MediaCard extends StatelessWidget {
  const _MediaCard({
    required this.title,
    required this.subtitle,
    required this.onPick,
    required this.onRemove,
    required this.previewBytes,
    required this.previewUrl,
    this.circular = false,
  });

  final String title;
  final String subtitle;
  final VoidCallback onPick;
  final VoidCallback onRemove;
  final Uint8List? previewBytes;
  final String? previewUrl;
  final bool circular;

  @override
  Widget build(BuildContext context) {
    final preview = previewBytes != null
        ? Image.memory(previewBytes!, fit: BoxFit.cover)
        : previewUrl != null && previewUrl!.trim().isNotEmpty
        ? Image.network(
            previewUrl!,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) =>
                const SizedBox.shrink(),
          )
        : null;

    return _FormCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          Text(subtitle, style: const TextStyle(color: dc.mutedInk)),
          const SizedBox(height: 12),
          Align(
            alignment: circular ? Alignment.centerLeft : Alignment.center,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(circular ? 999 : 18),
              child: Container(
                width: circular ? 110 : double.infinity,
                height: circular ? 110 : 170,
                color: dc.surfaceContainerHigh,
                child:
                    preview ??
                    Icon(
                      circular
                          ? Icons.person_outline_rounded
                          : Icons.image_outlined,
                      size: circular ? 42 : 48,
                      color: dc.mutedInk,
                    ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              FilledButton(
                onPressed: onPick,
                style: FilledButton.styleFrom(
                  backgroundColor: dc.primary,
                  foregroundColor: dc.onPrimary,
                ),
                child: const Text('Choose image'),
              ),
              const SizedBox(width: 10),
              OutlinedButton(onPressed: onRemove, child: const Text('Remove')),
            ],
          ),
        ],
      ),
    );
  }
}

class _FormCard extends StatelessWidget {
  const _FormCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: dc.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: dc.warmBorder),
      ),
      child: child,
    );
  }
}
