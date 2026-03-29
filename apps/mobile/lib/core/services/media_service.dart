import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

class SelectedMedia {
  const SelectedMedia({
    required this.bytes,
    required this.contentType,
    required this.name,
  });

  final Uint8List bytes;
  final String contentType;
  final String name;
}

const _maxFileBytes = 5 * 1024 * 1024; // 5 MB
const _allowedExtensions = {'.jpg', '.jpeg', '.png'};
const _mimeTypeByExtension = {
  '.jpg': 'image/jpeg',
  '.jpeg': 'image/jpeg',
  '.png': 'image/png',
};

class MediaService {
  final _picker = ImagePicker();

  Future<SelectedMedia?> pickImageFromGallery() => _pick(ImageSource.gallery);

  Future<SelectedMedia?> pickImageFromCamera() => _pick(ImageSource.camera);

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

    final size = await xfile.length();
    if (size > _maxFileBytes) return null;

    return SelectedMedia(
      bytes: await xfile.readAsBytes(),
      contentType: _mimeTypeByExtension[ext] ?? 'application/octet-stream',
      name: xfile.name,
    );
  }
}

final mediaServiceProvider = Provider<MediaService>((ref) => MediaService());
