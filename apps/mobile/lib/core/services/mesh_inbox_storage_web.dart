import 'dart:convert';
import 'dart:html' as html;

class MeshInboxStorage {
  static const _storageKey = 'dispatch_mobile_mesh_inbox';

  Future<List<Map<String, dynamic>>> load() async {
    final raw = html.window.localStorage[_storageKey];
    if (raw == null || raw.trim().isEmpty) {
      return const [];
    }
    final decoded = jsonDecode(raw) as List<dynamic>;
    return decoded
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item.cast<String, dynamic>()))
        .toList();
  }

  Future<void> save(List<Map<String, dynamic>> items) async {
    html.window.localStorage[_storageKey] = jsonEncode(items);
  }

  Future<void> clear() async {
    html.window.localStorage.remove(_storageKey);
  }
}
