import 'dart:convert';
import 'dart:io';

import 'package:dispatch_mobile/core/state/session_state.dart';

// File-based session persistence. Saves JSON to system temp dir.
class SessionStorage {
  static const _fileName = 'dispatch_mobile_session.json';
  SessionState _cachedState = const SessionState();

  Future<SessionState> load() async {
    try {
      final file = await _cacheFile();
      if (!await file.exists()) {
        return _cachedState;
      }

      final content = await file.readAsString();
      if (content.trim().isEmpty) {
        return _cachedState;
      }

      final decoded = jsonDecode(content) as Map<String, dynamic>;
      _cachedState = SessionState.fromJson(decoded);
      return _cachedState;
    } catch (_) {
      return _cachedState;
    }
  }

  Future<void> save(SessionState state) async {
    _cachedState = state;
    final file = await _cacheFile();
    await file.writeAsString(jsonEncode(state.toJson()), flush: true);
  }

  Future<void> clear() async {
    _cachedState = const SessionState();
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
