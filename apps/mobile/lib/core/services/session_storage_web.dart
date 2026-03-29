// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:convert';
import 'dart:html' as html;

import 'package:dispatch_mobile/core/state/session_state.dart';

// Browser-backed session persistence for Flutter web.
class SessionStorage {
  static const _storageKey = 'dispatch_mobile_session';
  SessionState _cachedState = const SessionState();

  Future<SessionState> load() async {
    try {
      final content = html.window.localStorage[_storageKey];
      if (content == null || content.trim().isEmpty) {
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
    html.window.localStorage[_storageKey] = jsonEncode(state.toJson());
  }

  Future<void> clear() async {
    _cachedState = const SessionState();
    html.window.localStorage.remove(_storageKey);
  }
}
