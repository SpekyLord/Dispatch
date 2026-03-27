import 'package:dispatch_mobile/core/services/session_storage.dart';
import 'package:dispatch_mobile/core/state/session_state.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final sessionStorageProvider = Provider<SessionStorage>((ref) => SessionStorage());

final sessionControllerProvider =
    StateNotifierProvider<SessionController, SessionState>((ref) {
      return SessionController(ref.read(sessionStorageProvider));
    });

class SessionController extends StateNotifier<SessionState> {
  SessionController(this._storage) : super(const SessionState()) {
    _restore();
  }

  final SessionStorage _storage;

  Future<void> _restore() async {
    state = await _storage.load();
  }

  Future<void> signInAs(AppRole role) async {
    state = SessionState(
      accessToken: 'phase0-${role.name}-token',
      email: '${role.name}@dispatch.local',
      role: role,
    );
    await _storage.save(state);
  }

  Future<void> signOut() async {
    state = const SessionState();
    await _storage.clear();
  }
}
