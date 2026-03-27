enum AppRole { citizen, department, municipality }

class SessionState {
  const SessionState({
    this.accessToken,
    this.email,
    this.role,
  });

  final String? accessToken;
  final String? email;
  final AppRole? role;

  bool get isAuthenticated => role != null && accessToken != null;

  Map<String, String?> toJson() {
    return {
      'accessToken': accessToken,
      'email': email,
      'role': role?.name,
    };
  }

  static SessionState fromJson(Map<String, dynamic> json) {
    final roleName = json['role'] as String?;
    return SessionState(
      accessToken: json['accessToken'] as String?,
      email: json['email'] as String?,
      role: AppRole.values.where((value) => value.name == roleName).firstOrNull,
    );
  }
}
