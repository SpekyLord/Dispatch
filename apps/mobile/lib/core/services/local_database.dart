class LocalDatabase {
  static const bootstrapStatements = [
    '''
    CREATE TABLE mesh_queue (
      id TEXT PRIMARY KEY,
      payload_type TEXT NOT NULL,
      payload TEXT NOT NULL,
      created_at TEXT NOT NULL
    )
    ''',
    '''
    CREATE TABLE session_cache (
      key TEXT PRIMARY KEY,
      value TEXT NOT NULL
    )
    ''',
  ];

  Future<List<String>> schemaStatements() async {
    return bootstrapStatements;
  }
}
