import 'dart:convert';

import 'package:dispatch_mobile/core/services/local_database_service.dart';
import 'package:sqflite/sqlite_api.dart';

class MeshInboxStorage {
  MeshInboxStorage({LocalDatabaseService? databaseService})
    : _databaseService = databaseService ?? LocalDatabaseService();

  final LocalDatabaseService _databaseService;
  List<Map<String, dynamic>> _cachedItems = const [];

  Future<List<Map<String, dynamic>>> load() async {
    try {
      final database = await _databaseService.database();
      final rows = await database.query('mesh_inbox', orderBy: 'created_at DESC');
      _cachedItems = rows.map(_rowToJson).toList(growable: false);
      return List<Map<String, dynamic>>.from(_cachedItems);
    } catch (_) {
      return List<Map<String, dynamic>>.from(_cachedItems);
    }
  }

  Future<void> save(List<Map<String, dynamic>> items) async {
    _cachedItems = items
        .map((item) => Map<String, dynamic>.from(item))
        .toList(growable: false);

    try {
      final database = await _databaseService.database();
      await database.transaction((txn) async {
        await txn.delete('mesh_inbox');
        for (final item in _cachedItems) {
          await txn.insert(
            'mesh_inbox',
            _jsonToRow(item),
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
      });
    } catch (_) {}
  }

  Future<void> clear() async {
    _cachedItems = const [];
    try {
      final database = await _databaseService.database();
      await database.delete('mesh_inbox');
    } catch (_) {}
  }

  // Store the inbox as normalized rows while keeping the full packet for rehydrate.
  Map<String, Object?> _jsonToRow(Map<String, dynamic> item) {
    return {
      'id': item['id'] as String? ?? '',
      'message_id': item['messageId'] as String? ?? '',
      'thread_id': item['threadId'] as String?,
      'item_type': item['itemType'] as String? ?? 'mesh_message',
      'recipient_scope': item['recipientScope'] as String? ?? 'broadcast',
      'recipient_identifier': item['recipientIdentifier'] as String?,
      'author_display_name': item['authorDisplayName'] as String? ?? 'Unknown',
      'author_role': item['authorRole'] as String? ?? 'anonymous',
      'title': item['title'] as String?,
      'body': item['body'] as String? ?? '',
      'category': item['category'] as String?,
      'hop_count': (item['hopCount'] as num?)?.toInt() ?? 0,
      'max_hops': (item['maxHops'] as num?)?.toInt() ?? 7,
      'is_read': item['isRead'] == true ? 1 : 0,
      'needs_server_sync': item['needsServerSync'] == false ? 0 : 1,
      'raw_packet': jsonEncode(item['rawPacket'] as Map<String, dynamic>? ?? const {}),
      'created_at': item['createdAt'] as String? ?? '',
    };
  }

  Map<String, dynamic> _rowToJson(Map<String, Object?> row) {
    return {
      'id': row['id'] as String? ?? '',
      'messageId': row['message_id'] as String? ?? '',
      'threadId': row['thread_id'] as String?,
      'itemType': row['item_type'] as String? ?? 'mesh_message',
      'recipientScope': row['recipient_scope'] as String? ?? 'broadcast',
      'recipientIdentifier': row['recipient_identifier'] as String?,
      'authorDisplayName': row['author_display_name'] as String? ?? 'Unknown',
      'authorRole': row['author_role'] as String? ?? 'anonymous',
      'title': row['title'] as String?,
      'body': row['body'] as String? ?? '',
      'category': row['category'] as String?,
      'hopCount': (row['hop_count'] as num?)?.toInt() ?? 0,
      'maxHops': (row['max_hops'] as num?)?.toInt() ?? 7,
      'isRead': (row['is_read'] as num?)?.toInt() == 1,
      'needsServerSync': (row['needs_server_sync'] as num?)?.toInt() != 0,
      'rawPacket': _decodeRawPacket(row['raw_packet'] as String?),
      'createdAt': row['created_at'] as String? ?? '',
    };
  }

  Map<String, dynamic> _decodeRawPacket(String? rawPacket) {
    if (rawPacket == null || rawPacket.isEmpty) {
      return const {};
    }
    try {
      return Map<String, dynamic>.from(
        jsonDecode(rawPacket) as Map<String, dynamic>,
      );
    } catch (_) {
      return const {};
    }
  }
}
