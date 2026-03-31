class MeshInboxStorage {
  final List<Map<String, dynamic>> _cache = [];

  Future<List<Map<String, dynamic>>> load() async {
    return List<Map<String, dynamic>>.from(_cache);
  }

  Future<void> save(List<Map<String, dynamic>> items) async {
    _cache
      ..clear()
      ..addAll(items.map((item) => Map<String, dynamic>.from(item)));
  }

  Future<void> clear() async {
    _cache.clear();
  }
}
