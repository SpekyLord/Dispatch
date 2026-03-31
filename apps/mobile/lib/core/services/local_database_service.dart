import 'dart:io';

import 'package:dispatch_mobile/core/services/local_database.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart' as sqflite;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

// Shared local database bootstrap for native mobile and desktop-hosted tests.
class LocalDatabaseService {
  LocalDatabaseService({
    LocalDatabase? schema,
    this.databaseName = 'dispatch_mobile.db',
    this.baseDirectoryPath,
    this.forceFfi,
  }) : _schema = schema ?? LocalDatabase();

  final LocalDatabase _schema;
  final String databaseName;
  final String? baseDirectoryPath;
  final bool? forceFfi;
  Database? _database;

  Future<Database> database() async {
    final existing = _database;
    if (existing != null) {
      return existing;
    }

    final dbPath = await _resolveDatabasePath();
    final opened = await _openDatabase(dbPath);
    final statements = await _schema.schemaStatements();
    for (final statement in statements) {
      await opened.execute(statement);
    }
    _database = opened;
    return opened;
  }

  Future<void> close() async {
    final existing = _database;
    _database = null;
    await existing?.close();
  }

  Future<Database> _openDatabase(String dbPath) async {
    if (_usesFfi) {
      sqfliteFfiInit();
      return databaseFactoryFfi.openDatabase(dbPath);
    }
    return sqflite.openDatabase(dbPath, version: 1);
  }

  Future<String> _resolveDatabasePath() async {
    final directory = await _resolveDatabaseDirectory();
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    return path.join(directory.path, databaseName);
  }

  Future<Directory> _resolveDatabaseDirectory() async {
    if (baseDirectoryPath != null && baseDirectoryPath!.isNotEmpty) {
      return Directory(baseDirectoryPath!);
    }
    if (_usesFfi) {
      return Directory(path.join(Directory.systemTemp.path, 'dispatch_mobile'));
    }
    final supportDirectory = await getApplicationSupportDirectory();
    return Directory(path.join(supportDirectory.path, 'dispatch_mobile'));
  }

  bool get _usesFfi =>
      forceFfi ?? Platform.isWindows || Platform.isLinux || Platform.isMacOS;
}
