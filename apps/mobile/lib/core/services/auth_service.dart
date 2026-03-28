import 'package:dispatch_mobile/core/config/app_config.dart';
import 'package:dispatch_mobile/core/state/session_state.dart';
import 'package:dio/dio.dart';

class AuthService {
  AuthService({Dio? dio})
      : _dio = dio ??
            Dio(BaseOptions(
              baseUrl: AppConfig.current.apiBaseUrl,
              headers: {'Content-Type': 'application/json'},
            ));

  final Dio _dio;

  Dio get client => _dio;

  void setToken(String? token) {
    if (token != null) {
      _dio.options.headers['Authorization'] = 'Bearer $token';
    } else {
      _dio.options.headers.remove('Authorization');
    }
  }

  Future<Map<String, dynamic>> register({
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
    final body = <String, dynamic>{
      'email': email,
      'password': password,
      'role': role,
      'full_name': fullName ?? '',
    };

    if (role == 'department') {
      body['organization_name'] = organizationName ?? '';
      body['department_type'] = departmentType ?? 'other';
      body['contact_number'] = contactNumber ?? '';
      body['address'] = address ?? '';
      body['area_of_responsibility'] = areaOfResponsibility ?? '';
    }

    final response = await _dio.post('/api/auth/register', data: body);
    return response.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> login({
    required String email,
    required String password,
  }) async {
    final response = await _dio.post('/api/auth/login', data: {
      'email': email,
      'password': password,
    });
    return response.data as Map<String, dynamic>;
  }

  Future<void> logout() async {
    try {
      await _dio.post('/api/auth/logout');
    } catch (_) {
      // sign out locally even if API fails
    }
  }

  Future<Map<String, dynamic>> getMe() async {
    final response = await _dio.get('/api/auth/me');
    return response.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> getProfile() async {
    final response = await _dio.get('/api/users/profile');
    return response.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> updateProfile({
    String? fullName,
    String? phone,
  }) async {
    final body = <String, dynamic>{};
    if (fullName != null) body['full_name'] = fullName;
    if (phone != null) body['phone'] = phone;
    final response = await _dio.put('/api/users/profile', data: body);
    return response.data as Map<String, dynamic>;
  }

  // Reports
  Future<Map<String, dynamic>> createReport({
    required String description,
    required String category,
    String severity = 'medium',
    String? address,
    double? latitude,
    double? longitude,
  }) async {
    final body = <String, dynamic>{
      'description': description,
      'category': category,
      'severity': severity,
    };
    if (address != null) body['address'] = address;
    if (latitude != null) body['latitude'] = latitude;
    if (longitude != null) body['longitude'] = longitude;
    final response = await _dio.post('/api/reports', data: body);
    return response.data as Map<String, dynamic>;
  }

  Future<List<dynamic>> getReports() async {
    final response = await _dio.get('/api/reports');
    return (response.data as Map<String, dynamic>)['reports'] as List<dynamic>;
  }

  Future<Map<String, dynamic>> getReport(String reportId) async {
    final response = await _dio.get('/api/reports/$reportId');
    return response.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> uploadReportImage(
      String reportId, String filePath, String contentType) async {
    final formData = FormData.fromMap({
      'file': await MultipartFile.fromFile(filePath),
    });
    final response = await _dio.post('/api/reports/$reportId/upload', data: formData);
    return response.data as Map<String, dynamic>;
  }

  // Department
  Future<DepartmentInfo> getDepartmentProfile() async {
    final response = await _dio.get('/api/departments/profile');
    final data = (response.data as Map<String, dynamic>)['department'] as Map<String, dynamic>;
    return DepartmentInfo.fromJson(data);
  }

  Future<DepartmentInfo> updateDepartmentProfile(Map<String, dynamic> updates) async {
    final response = await _dio.put('/api/departments/profile', data: updates);
    final data = (response.data as Map<String, dynamic>)['department'] as Map<String, dynamic>;
    return DepartmentInfo.fromJson(data);
  }
}
