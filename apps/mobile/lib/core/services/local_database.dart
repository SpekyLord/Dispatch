// Local SQLite schema for mesh queue, seen messages, peer cache, and session.

class LocalDatabase {
  static const bootstrapStatements = [
    // offline packet queue — holds mesh packets until gateway sync
    '''
    CREATE TABLE IF NOT EXISTS mesh_queue (
      id TEXT PRIMARY KEY,
      payload_type TEXT NOT NULL,
      payload TEXT NOT NULL,
      hop_count INTEGER NOT NULL DEFAULT 0,
      max_hops INTEGER NOT NULL DEFAULT 7,
      origin_device_id TEXT NOT NULL DEFAULT '',
      signature TEXT NOT NULL DEFAULT '',
      status TEXT NOT NULL DEFAULT 'queued',
      created_at TEXT NOT NULL,
      synced_at TEXT
    )
    ''',
    // dedup log — prevents re-processing relayed packets
    '''
    CREATE TABLE IF NOT EXISTS seen_messages (
      message_id TEXT PRIMARY KEY,
      payload_type TEXT NOT NULL,
      origin_device_id TEXT NOT NULL DEFAULT '',
      received_at TEXT NOT NULL,
      hop_count INTEGER NOT NULL DEFAULT 0
    )
    ''',
    // nearby peer cache — tracks discovered mesh peers
    '''
    CREATE TABLE IF NOT EXISTS mesh_peers (
      endpoint_id TEXT PRIMARY KEY,
      device_name TEXT NOT NULL DEFAULT '',
      is_gateway INTEGER NOT NULL DEFAULT 0,
      last_seen_at TEXT NOT NULL,
      signal_strength INTEGER
    )
    ''',
    // generic key-value session cache
    '''
    CREATE TABLE IF NOT EXISTS session_cache (
      key TEXT PRIMARY KEY,
      value TEXT NOT NULL
    )
    ''',
  ];

  Future<List<String>> schemaStatements() async {
    return bootstrapStatements;
  }
}
