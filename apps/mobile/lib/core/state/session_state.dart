enum AppRole { citizen, department, municipality }

/// Mirrors the `departments` table. verificationStatus drives UI routing.
class DepartmentInfo {
  const DepartmentInfo({
    required this.id,
    required this.name,
    required this.type,
    required this.verificationStatus,
    this.rejectionReason,
    this.contactNumber,
    this.address,
    this.areaOfResponsibility,
  });

  final String id;
  final String name;
  final String type;
  final String verificationStatus;
  final String? rejectionReason;
  final String? contactNumber;
  final String? address;
  final String? areaOfResponsibility;

  factory DepartmentInfo.fromJson(Map<String, dynamic> json) {
    return DepartmentInfo(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      type: json['type'] as String? ?? '',
      verificationStatus: json['verification_status'] as String? ?? 'pending',
      rejectionReason: json['rejection_reason'] as String?,
      contactNumber: json['contact_number'] as String?,
      address: json['address'] as String?,
      areaOfResponsibility: json['area_of_responsibility'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'type': type,
        'verification_status': verificationStatus,
        'rejection_reason': rejectionReason,
        'contact_number': contactNumber,
        'address': address,
        'area_of_responsibility': areaOfResponsibility,
      };
}

/// Auth session state — serializable to JSON for file-based persistence.
class SessionState {
  const SessionState({
    this.accessToken,
    this.refreshToken,
    this.userId,
    this.email,
    this.role,
    this.fullName,
    this.department,
  });

  final String? accessToken;
  final String? refreshToken;
  final String? userId;
  final String? email;
  final AppRole? role;
  final String? fullName;
  final DepartmentInfo? department;

  // Need both role and token to be considered logged in
  bool get isAuthenticated => role != null && accessToken != null;

  SessionState copyWith({
    String? accessToken,
    String? refreshToken,
    String? userId,
    String? email,
    AppRole? role,
    String? fullName,
    DepartmentInfo? department,
  }) {
    return SessionState(
      accessToken: accessToken ?? this.accessToken,
      refreshToken: refreshToken ?? this.refreshToken,
      userId: userId ?? this.userId,
      email: email ?? this.email,
      role: role ?? this.role,
      fullName: fullName ?? this.fullName,
      department: department ?? this.department,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'accessToken': accessToken,
      'refreshToken': refreshToken,
      'userId': userId,
      'email': email,
      'role': role?.name,
      'fullName': fullName,
      'department': department?.toJson(),
    };
  }

  static SessionState fromJson(Map<String, dynamic> json) {
    final roleName = json['role'] as String?;
    final deptJson = json['department'] as Map<String, dynamic>?;
    return SessionState(
      accessToken: json['accessToken'] as String?,
      refreshToken: json['refreshToken'] as String?,
      userId: json['userId'] as String?,
      email: json['email'] as String?,
      role: AppRole.values.where((value) => value.name == roleName).firstOrNull,
      fullName: json['fullName'] as String?,
      department: deptJson != null ? DepartmentInfo.fromJson(deptJson) : null,
    );
  }
}
