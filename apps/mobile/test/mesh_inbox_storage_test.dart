import 'dart:io';

import 'package:dispatch_mobile/core/services/local_database_service.dart';
import 'package:dispatch_mobile/core/services/mesh_inbox_storage_io.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('persists mesh inbox rows through the shared SQLite service', () async {
    final tempDir = await Directory.systemTemp.createTemp('dispatch_mesh_inbox_');
    final firstService = LocalDatabaseService(
      baseDirectoryPath: tempDir.path,
      databaseName: 'mesh_inbox_test.db',
      forceFfi: true,
    );
    final firstStorage = MeshInboxStorage(databaseService: firstService);

    addTearDown(() async {
      await firstService.close();
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    await firstStorage.save([
      {
        'id': 'row-1',
        'messageId': 'message-1',
        'threadId': 'thread-1',
        'itemType': 'mesh_message',
        'recipientScope': 'broadcast',
        'recipientIdentifier': null,
        'authorDisplayName': 'Responder Aya',
        'authorRole': 'department',
        'title': null,
        'body': 'Supplies are available at the school gym.',
        'category': null,
        'hopCount': 1,
        'maxHops': 7,
        'isRead': false,
        'needsServerSync': true,
        'rawPacket': {
          'messageId': 'message-1',
          'payloadType': 'MESH_MESSAGE',
        },
        'createdAt': '2026-03-31T02:00:00Z',
      },
    ]);
    await firstService.close();

    final secondService = LocalDatabaseService(
      baseDirectoryPath: tempDir.path,
      databaseName: 'mesh_inbox_test.db',
      forceFfi: true,
    );
    final secondStorage = MeshInboxStorage(databaseService: secondService);
    addTearDown(secondService.close);

    final restored = await secondStorage.load();

    expect(restored, hasLength(1));
    expect(restored.first['messageId'], 'message-1');
    expect(restored.first['body'], 'Supplies are available at the school gym.');
    expect(restored.first['isRead'], false);
    expect(restored.first['rawPacket'], {'messageId': 'message-1', 'payloadType': 'MESH_MESSAGE'});
  });
}

