class SelectedMedia {
  const SelectedMedia({
    required this.name,
    required this.path,
  });

  final String name;
  final String path;
}

class MediaService {
  Future<SelectedMedia?> pickImageFromGallery() async {
    return null;
  }
}
