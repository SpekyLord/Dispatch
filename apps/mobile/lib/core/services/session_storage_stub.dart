import 'package:dispatch_mobile/core/state/session_state.dart';

// Fallback in-memory session storage for unsupported platforms.
class SessionStorage {
  SessionState _cachedState = const SessionState();

  Future<SessionState> load() async => _cachedState;

  Future<void> save(SessionState state) async {
    _cachedState = state;
  }

  Future<void> clear() async {
    _cachedState = const SessionState();
  }
}
