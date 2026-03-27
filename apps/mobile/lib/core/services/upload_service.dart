class UploadService {
  static const supportedMimeTypes = {'image/jpeg', 'image/png'};
  static const maxImageSizeBytes = 5 * 1024 * 1024;

  bool isSupportedMimeType(String mimeType) => supportedMimeTypes.contains(mimeType);

  bool isWithinUploadLimit(int sizeInBytes) => sizeInBytes <= maxImageSizeBytes;
}
