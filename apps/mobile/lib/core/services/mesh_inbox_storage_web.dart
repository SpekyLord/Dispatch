// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:convert';
import 'dart:html' as html;

// Browser-backed mesh inbox persistence for Flutter web.
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
