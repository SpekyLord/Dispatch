// Session controller - manages auth state, coordinates API + local storage.
// Returns null on success, error string on failure.

import 'package:dispatch_mobile/core/services/auth_service.dart';
import 'package:dispatch_mobile/core/services/session_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_session_state.dart';

final authServiceProvider = Provider<AuthService>((ref) => AuthService());
final sessionStorageProvider = Provider<SessionStorage>(
  (ref) => SessionStorage(),
);

final sessionControllerProvider =
    StateNotifierProvider<SessionController, SessionState>((ref) {
      return SessionController(
        ref.read(sessionStorageProvider),
        ref.read(authServiceProvider),
      );
    });

class SessionController extends StateNotifier<SessionState> {
  SessionController(this._storage, this._authService)
    : super(const SessionState()) {
    _restore();
  }

  final SessionStorage _storage;
  final AuthService _authService;

  Future<void> _restore() async {
    final restored = await _storage.load();
    state = restored;
    if (restored.accessToken != null) {
      _authService.setToken(restored.accessToken);
    }
  }

  Future<String?> login({
    required String email,
    required String password,
  }) async {
    try {
      final result = await _authService.login(email: email, password: password);
      final token = result['access_token'] as String?;
      final user = result['user'] as Map<String, dynamic>? ?? {};
      final roleName = user['role'] as String? ?? '';
      final role = AppRole.values.where((r) => r.name == roleName).firstOrNull;

      if (token == null || role == null) return 'Login failed.';

      _authService.setToken(token);

      DepartmentInfo? dept;
      final deptData = result['department'] as Map<String, dynamic>?;
      if (deptData != null) {
        dept = DepartmentInfo.fromJson(deptData);
      }

      state = SessionState(
        accessToken: token,
        refreshToken: result['refresh_token'] as String?,
        userId: user['id'] as String?,
        email: user['email'] as String? ?? email,
        role: role,
        fullName: user['full_name'] as String?,
        department: dept,
        offlineVerificationToken:
            result['offline_verification_token'] as String?,
      );
      await _storage.save(state);
      return null;
    } on Exception catch (e) {
      return _extractError(e);
    }
  }

  Future<String?> register({
    required String email,
    required String password,
    required String role,
    String? fullName,
    String? organizationName,
    String? departmentType,
    String? contactNumber,
    String? address,
    String? areaOfResponsibility,
  }) async {
    try {
      final result = await _authService.register(
        email: email,
        password: password,
        role: role,
        fullName: fullName,
        organizationName: organizationName,
        departmentType: departmentType,
        contactNumber: contactNumber,
        address: address,
        areaOfResponsibility: areaOfResponsibility,
      );

      final token = result['access_token'] as String?;
      final user = result['user'] as Map<String, dynamic>? ?? {};
      final roleValue = AppRole.values.where((r) => r.name == role).firstOrNull;

      if (token == null || roleValue == null) {
        return null;
      }

      _authService.setToken(token);

      DepartmentInfo? dept;
      final deptData = result['department'] as Map<String, dynamic>?;
      if (deptData != null) {
        dept = DepartmentInfo.fromJson(deptData);
      }

      state = SessionState(
        accessToken: token,
        userId: user['id'] as String?,
        email: user['email'] as String? ?? email,
        role: roleValue,
        fullName: user['full_name'] as String?,
        department: dept,
        offlineVerificationToken:
            result['offline_verification_token'] as String?,
      );
      await _storage.save(state);
      return null;
    } on Exception catch (e) {
      return _extractError(e);
    }
  }

  void updateDepartment(DepartmentInfo dept) {
    state = state.copyWith(department: dept);
    _storage.save(state);
  }

  void updateFullName(String name) {
    state = SessionState(
      accessToken: state.accessToken,
      refreshToken: state.refreshToken,
      userId: state.userId,
      email: state.email,
      role: state.role,
      fullName: name,
      department: state.department,
      offlineVerificationToken: state.offlineVerificationToken,
    );
    _storage.save(state);
  }

  Future<void> signOut() async {
    await _authService.logout();
    _authService.setToken(null);
    state = const SessionState();
    await _storage.clear();
  }

  String _extractError(Exception e) {
    if (e.toString().contains('DioException')) {
      final str = e.toString();
      if (str.contains('message')) {
        final match = RegExp(r'"message"\s*:\s*"([^"]*)"').firstMatch(str);
        if (match != null) return match.group(1)!;
      }
    }
    return e.toString();
  }
}
