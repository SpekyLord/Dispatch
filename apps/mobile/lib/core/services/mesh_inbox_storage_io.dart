import 'dart:convert';
import 'dart:io';

class MeshInboxStorage {
  static const _fileName = 'dispatch_mobile_mesh_inbox.json';
  List<Map<String, dynamic>> _cachedItems = const [];

  Future<List<Map<String, dynamic>>> load() async {
    try {
      final file = await _cacheFile();
      if (!await file.exists()) {
        return List<Map<String, dynamic>>.from(_cachedItems);
      }

      final content = await file.readAsString();
      if (content.trim().isEmpty) {
        return List<Map<String, dynamic>>.from(_cachedItems);
      }

      final decoded = jsonDecode(content) as List<dynamic>;
      _cachedItems = decoded
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item.cast<String, dynamic>()))
          .toList();
      return List<Map<String, dynamic>>.from(_cachedItems);
    } catch (_) {
      return List<Map<String, dynamic>>.from(_cachedItems);
    }
  }

  Future<void> save(List<Map<String, dynamic>> items) async {
    _cachedItems = items
        .map((item) => Map<String, dynamic>.from(item))
        .toList(growable: false);
    final file = await _cacheFile();
    await file.writeAsString(jsonEncode(_cachedItems), flush: true);
  }

  Future<void> clear() async {
    _cachedItems = const [];
    final file = await _cacheFile();
    if (await file.exists()) {
      await file.delete();
    }
  }

  Future<File> _cacheFile() async {
    final directory = Directory(
      '${Directory.systemTemp.path}${Platform.pathSeparator}dispatch_mobile',
    );
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    return File('${directory.path}${Platform.pathSeparator}$_fileName');
  }
}
