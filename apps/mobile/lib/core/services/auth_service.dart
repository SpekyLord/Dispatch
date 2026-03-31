// API service â€” wraps Dio for all backend calls. Token managed by SessionController.

import 'package:dispatch_mobile/core/config/app_config.dart';
import 'package:dispatch_mobile/core/services/media_service.dart';
import 'package:dispatch_mobile/core/state/session_state.dart';
import 'package:dio/dio.dart';

class AuthService {
  AuthService({Dio? dio})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              baseUrl: AppConfig.current.apiBaseUrl,
              headers: {'Content-Type': 'application/json'},
            ),
          );

  final Dio _dio;

  Dio get client => _dio;

  void setToken(String? token) {
    if (token != null) {
      _dio.options.headers['Authorization'] = 'Bearer $token';
    } else {
      _dio.options.headers.remove('Authorization');
    }
  }

  // --- Auth ---

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
    // Build body imperatively to avoid Dart null-aware element lint issues
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
    final response = await _dio.post(
      '/api/auth/login',
      data: {'email': email, 'password': password},
    );
    return response.data as Map<String, dynamic>;
  }

  Future<void> logout() async {
    try {
      await _dio.post('/api/auth/logout');
    } catch (_) {
      // Sign out locally even if API fails
    }
  }

  Future<Map<String, dynamic>> getMe() async {
    final response = await _dio.get('/api/auth/me');
    return response.data as Map<String, dynamic>;
  }

  // --- User profile ---

  Future<Map<String, dynamic>> getProfile() async {
    final response = await _dio.get('/api/users/profile');
    return response.data as Map<String, dynamic>;
  }

  // Only include non-null fields in the request
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

  // --- Reports ---

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
    String reportId,
    SelectedMedia media,
  ) async {
    final formData = FormData.fromMap({
      'file': MultipartFile.fromBytes(media.bytes, filename: media.name),
    });
    final response = await _dio.post(
      '/api/reports/$reportId/upload',
      data: formData,
    );
    return response.data as Map<String, dynamic>;
  }

  // --- Department ---

  Future<DepartmentInfo> getDepartmentProfile() async {
    final response = await _dio.get('/api/departments/profile');
    final data =
        (response.data as Map<String, dynamic>)['department']
            as Map<String, dynamic>;
    return DepartmentInfo.fromJson(data);
  }

  // API auto-moves rejected departments back to pending on update
  Future<DepartmentInfo> updateDepartmentProfile(
    Map<String, dynamic> updates,
  ) async {
    final response = await _dio.put('/api/departments/profile', data: updates);
    final data =
        (response.data as Map<String, dynamic>)['department']
            as Map<String, dynamic>;
    return DepartmentInfo.fromJson(data);
  }

  // --- Department reports (Phase 2) ---

  // Fetch reports routed to this department, with optional status/category filters
  Future<List<Map<String, dynamic>>> getDepartmentReports({
    String? status,
    String? category,
  }) async {
    final params = <String, dynamic>{};
    if (status != null) params['status'] = status;
    if (category != null) params['category'] = category;
    final response = await _dio.get(
      '/api/departments/reports',
      queryParameters: params,
    );
    return (response.data['reports'] as List).cast<Map<String, dynamic>>();
  }

  // Accept a report on behalf of this department
  Future<Map<String, dynamic>> acceptReport(
    String reportId, {
    String? notes,
  }) async {
    final body = <String, dynamic>{};
    if (notes != null) body['notes'] = notes;
    final response = await _dio.post(
      '/api/departments/reports/$reportId/accept',
      data: body,
    );
    return response.data as Map<String, dynamic>;
  }

  // Decline a report â€” decline_reason is required
  Future<Map<String, dynamic>> declineReport(
    String reportId, {
    required String declineReason,
    String? notes,
  }) async {
    final body = <String, dynamic>{'decline_reason': declineReason};
    if (notes != null) body['notes'] = notes;
    final response = await _dio.post(
      '/api/departments/reports/$reportId/decline',
      data: body,
    );
    return response.data as Map<String, dynamic>;
  }

  // Get response roster for a report
  Future<Map<String, dynamic>> getReportResponses(String reportId) async {
    final response = await _dio.get(
      '/api/departments/reports/$reportId/responses',
    );
    return response.data as Map<String, dynamic>;
  }

  // Update report status (responding / resolved)
  Future<Map<String, dynamic>> updateReportStatus(
    String reportId, {
    required String status,
    String? notes,
  }) async {
    final body = <String, dynamic>{'status': status};
    if (notes != null) body['notes'] = notes;
    final response = await _dio.put(
      '/api/departments/reports/$reportId/status',
      data: body,
    );
    return response.data as Map<String, dynamic>;
  }

  // --- Department posts (Phase 2) ---

  // Create a new department announcement
  Future<Map<String, dynamic>> createPost({
    required String title,
    required String content,
    required String category,
    bool isPinned = false,
  }) async {
    final response = await _dio.post(
      '/api/departments/posts',
      data: {
        'title': title,
        'content': content,
        'category': category,
        'is_pinned': isPinned,
      },
    );
    return response.data as Map<String, dynamic>;
  }

  // --- Feed (Phase 2) ---

  // List public feed posts with optional category filter
  Future<List<Map<String, dynamic>>> getFeedPosts({String? category}) async {
    final params = <String, dynamic>{};
    if (category != null) params['category'] = category;
    final response = await _dio.get('/api/feed', queryParameters: params);
    return (response.data['posts'] as List).cast<Map<String, dynamic>>();
  }

  // Get a single feed post by ID
  Future<Map<String, dynamic>> getFeedPost(String postId) async {
    final response = await _dio.get('/api/feed/$postId');
    return (response.data as Map<String, dynamic>)['post']
        as Map<String, dynamic>;
  }

  // --- Notifications (Phase 2) ---

  // List all notifications for current user
  Future<Map<String, dynamic>> getNotifications() async {
    final response = await _dio.get('/api/notifications');
    return response.data as Map<String, dynamic>;
  }

  // Mark a single notification as read
  Future<void> markNotificationRead(String notificationId) async {
    await _dio.put('/api/notifications/$notificationId/read');
  }

  // Mark all notifications as read
  Future<void> markAllNotificationsRead() async {
    await _dio.put('/api/notifications/read-all');
  }

  // --- Mesh survivor signals (Phase 4 extension) ---

  Future<List<Map<String, dynamic>>> getSurvivorSignals({
    String? status,
    String? detectionMethod,
  }) async {
    final params = <String, dynamic>{};
    if (status != null) params['status'] = status;
    if (detectionMethod != null) params['detection_method'] = detectionMethod;
    final response = await _dio.get(
      '/api/mesh/survivor-signals',
      queryParameters: params,
    );
    return (response.data['survivor_signals'] as List)
        .cast<Map<String, dynamic>>();
  }

  Future<Map<String, dynamic>> resolveSurvivorSignal(
    String signalId, {
    String note = '',
  }) async {
    final response = await _dio.put(
      '/api/mesh/survivor-signals/$signalId/resolve',
      data: {'note': note},
    );
    return (response.data as Map<String, dynamic>)['survivor_signal']
        as Map<String, dynamic>;
  }

  // --- Mesh comms (Phase 4 extension) ---

  Future<Map<String, dynamic>> ingestMeshPackets(
    List<Map<String, dynamic>> packets, {
    Map<String, dynamic>? topologySnapshot,
  }) async {
    final body = <String, dynamic>{'packets': packets};
    if (topologySnapshot != null) {
      body['topologySnapshot'] = topologySnapshot;
    }
    final response = await _dio.post('/api/mesh/ingest', data: body);
    return response.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> getMeshMessages({
    String? threadId,
    bool includePosts = false,
  }) async {
    final params = <String, dynamic>{};
    if (threadId != null) params['threadId'] = threadId;
    if (includePosts) params['include_posts'] = '1';
    final response = await _dio.get('/api/mesh/messages', queryParameters: params);
    return response.data as Map<String, dynamic>;
  }
  // --- Damage assessments (Phase 3) ---

  // Submit a new damage assessment for this department
  Future<Map<String, dynamic>> createAssessment({
    required String affectedArea,
    required String damageLevel,
    int estimatedCasualties = 0,
    int displacedPersons = 0,
    String? location,
    String? description,
    String? reportId,
  }) async {
    final body = <String, dynamic>{
      'affected_area': affectedArea,
      'damage_level': damageLevel,
      'estimated_casualties': estimatedCasualties,
      'displaced_persons': displacedPersons,
    };
    if (location != null) body['location'] = location;
    if (description != null) body['description'] = description;
    if (reportId != null) body['report_id'] = reportId;
    final response = await _dio.post(
      '/api/departments/assessments',
      data: body,
    );
    return response.data as Map<String, dynamic>;
  }

  // List this department's submitted assessments
  Future<List<Map<String, dynamic>>> getDepartmentAssessments() async {
    final response = await _dio.get('/api/departments/assessments');
    return (response.data['assessments'] as List).cast<Map<String, dynamic>>();
  }
}
