import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

class SelectedMedia {
  const SelectedMedia({required this.name, required this.path});

  final String name;
  final String path;
}

const _maxFileBytes = 5 * 1024 * 1024; // 5 MB
const _allowedExtensions = {'.jpg', '.jpeg', '.png'};

class MediaService {
  final _picker = ImagePicker();

  Future<SelectedMedia?> pickImageFromGallery() =>
      _pick(ImageSource.gallery);

  Future<SelectedMedia?> pickImageFromCamera() =>
      _pick(ImageSource.camera);

  Future<SelectedMedia?> _pick(ImageSource source) async {
    final xfile = await _picker.pickImage(
      source: source,
      maxWidth: 2048,
      maxHeight: 2048,
      imageQuality: 85,
    );
    if (xfile == null) return null;

    final ext = xfile.name.contains('.')
        ? '.${xfile.name.split('.').last.toLowerCase()}'
        : '';
    if (!_allowedExtensions.contains(ext)) return null;

    final size = await File(xfile.path).length();
    if (size > _maxFileBytes) return null;

    return SelectedMedia(name: xfile.name, path: xfile.path);
  }
}

final mediaServiceProvider = Provider<MediaService>((ref) => MediaService());
