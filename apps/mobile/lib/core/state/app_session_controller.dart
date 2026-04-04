// Session controller - manages auth state, coordinates API + local storage.
// Returns null on success, error string on failure.

import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
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

  static const _offlineTokenRefreshLeadTime = Duration(days: 3);

  final SessionStorage _storage;
  final AuthService _authService;

  Future<void> _restore() async {
    final restored = await _storage.load();
    state = restored;
    if (restored.customApiBaseUrl != null &&
        restored.customApiBaseUrl!.isNotEmpty) {
      _authService.setBaseUrl(restored.customApiBaseUrl!);
    }
    if (restored.accessToken != null) {
      _authService.setToken(restored.accessToken);
    }
    if (restored.refreshToken != null) {
      unawaited(refreshSessionIfNeeded());
    }
  }

  String get currentApiBaseUrl => _authService.baseUrl;

  Future<void> setCustomApiBaseUrl(String url) async {
    _authService.setBaseUrl(url);
    state = state.copyWith(customApiBaseUrl: url);
    await _storage.save(state);
  }

  Future<void> handleAppResumed() async {
    await refreshSessionIfNeeded();
  }

  Future<void> refreshSessionIfNeeded({bool force = false}) async {
    final refreshToken = state.refreshToken;
    if (refreshToken == null || refreshToken.isEmpty) {
      return;
    }
    if (!force && !_shouldRefreshSession(state)) {
      return;
    }

    try {
      final result = await _authService.refreshSession(
        refreshToken: refreshToken,
      );
      _applyAuthPayload(
        result,
        fallbackEmail: state.email ?? '',
        fallbackRole: state.role,
      );
      await _storage.save(state);
    } on Exception {
      // Best effort only - keep the cached session for offline continuity.
    }
  }

  Future<String?> login({
    required String email,
    required String password,
  }) async {
    try {
      final result = await _authService.login(email: email, password: password);
      _applyAuthPayload(result, fallbackEmail: email);
      await _storage.save(state);
      return null;
    } catch (e) {
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
      final roleValue = AppRole.values.where((r) => r.name == role).firstOrNull;
      if (token == null || roleValue == null) {
        // Registration succeeded but no session token was returned.
        // This typically means email confirmation is required.
        return 'CONFIRM_EMAIL';
      }

      _applyAuthPayload(result, fallbackEmail: email, fallbackRole: roleValue);
      await _storage.save(state);
      return null;
    } catch (e) {
      return _extractError(e);
    }
  }

  void updateDepartment(DepartmentInfo dept) {
    state = state.copyWith(department: dept);
    _storage.save(state);
  }

  void updateFullName(String name) {
    state = state.copyWith(fullName: name);
    _storage.save(state);
  }

  Future<void> signOut() async {
    await _authService.logout();
    _authService.setToken(null);
    state = const SessionState();
    await _storage.clear();
  }

  void _applyAuthPayload(
    Map<String, dynamic> result, {
    required String fallbackEmail,
    AppRole? fallbackRole,
  }) {
    final token = result['access_token'] as String?;
    final user = result['user'] as Map<String, dynamic>? ?? const {};
    final roleName = user['role'] as String?;
    final role =
        AppRole.values.where((value) => value.name == roleName).firstOrNull ??
        fallbackRole;

    if (token == null || role == null) {
      throw StateError('Auth payload is missing access_token or role.');
    }

    DepartmentInfo? dept;
    final deptData = result['department'] as Map<String, dynamic>?;
    if (deptData != null) {
      dept = DepartmentInfo.fromJson(deptData);
    }

    _authService.setToken(token);
    state = SessionState(
      accessToken: token,
      refreshToken: result['refresh_token'] as String? ?? state.refreshToken,
      userId: user['id'] as String? ?? state.userId,
      email: user['email'] as String? ?? fallbackEmail,
      role: role,
      fullName: user['full_name'] as String? ?? state.fullName,
      department: dept ?? state.department,
      offlineVerificationToken:
          result['offline_verification_token'] as String? ??
          state.offlineVerificationToken,
    );
  }

  bool _shouldRefreshSession(SessionState session) {
    if (session.role != AppRole.department) {
      return false;
    }
    final expiry = _offlineTokenExpiry(session.offlineVerificationToken);
    if (expiry == null) {
      return true;
    }
    final threshold = expiry.subtract(_offlineTokenRefreshLeadTime);
    return DateTime.now().toUtc().isAfter(threshold);
  }

  DateTime? _offlineTokenExpiry(String? token) {
    if (token == null || token.isEmpty) {
      return null;
    }

    final parts = token.split('.');
    if (parts.length != 3) {
      return null;
    }

    try {
      final normalized = base64Url.normalize(parts[1]);
      final payload =
          jsonDecode(utf8.decode(base64Url.decode(normalized)))
              as Map<String, dynamic>;
      final exp = payload['exp'];
      if (exp is! num) {
        return null;
      }
      return DateTime.fromMillisecondsSinceEpoch(
        exp.toInt() * 1000,
        isUtc: true,
      );
    } on FormatException {
      return null;
    } on ArgumentError {
      return null;
    } catch (_) {
      return null;
    }
  }

  String _extractError(Object error) {
    if (error is DioException) {
      if (error.type == DioExceptionType.connectionTimeout ||
          error.type == DioExceptionType.sendTimeout ||
          error.type == DioExceptionType.receiveTimeout ||
          error.type == DioExceptionType.connectionError) {
        return 'Unable to reach the API. Check MOBILE_API_BASE_URL and ensure the backend is running.';
      }
      final payload = error.response?.data;
      if (payload is Map<String, dynamic>) {
        final data = payload['error'];
        if (data is Map<String, dynamic>) {
          final code = data['code'] as String?;
          final message = data['message'] as String?;
          if (message != null && message.isNotEmpty) {
            return code == null || code.isEmpty ? message : '[$code] $message';
          }
        }
      }
      return error.message ?? 'Request failed.';
    }
    if (error is StateError) {
      return error.message;
    }
    return error.toString();
  }
}
