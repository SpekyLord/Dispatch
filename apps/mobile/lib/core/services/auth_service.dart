// API service Ã¢â‚¬â€ wraps Dio for all backend calls. Token managed by SessionController.

import 'package:dispatch_mobile/core/config/app_config.dart';
import 'package:dispatch_mobile/core/services/media_service.dart';
import 'package:dispatch_mobile/core/state/session.dart';
import 'package:dio/dio.dart';

class AuthService {
  AuthService({Dio? dio})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              baseUrl: AppConfig.current.apiBaseUrl,
              headers: {'Content-Type': 'application/json'},
              connectTimeout: const Duration(seconds: 12),
              sendTimeout: const Duration(seconds: 12),
              receiveTimeout: const Duration(seconds: 20),
            ),
          );

  final Dio _dio;

  Dio get client => _dio;

  String get baseUrl => _dio.options.baseUrl;

  void setBaseUrl(String url) {
    _dio.options.baseUrl = url;
  }

  void setToken(String? token) {
    if (token != null && token.isNotEmpty) {
      _dio.options.headers['Authorization'] = 'Bearer $token';
    } else {
      _dio.options.headers.remove('Authorization');
    }
  }

  Future<bool> checkHealth() async {
    final response = await _dio.get(
      '/api/health',
      options: Options(
        sendTimeout: const Duration(seconds: 4),
        receiveTimeout: const Duration(seconds: 4),
      ),
    );
    return response.statusCode == 200;
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

  Future<Map<String, dynamic>> refreshSession({
    required String refreshToken,
  }) async {
    final response = await _dio.post(
      '/api/auth/refresh',
      data: {'refresh_token': refreshToken},
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

  Future<Map<String, dynamic>> updateProfileMultipart({
    String? fullName,
    String? phone,
    String? description,
    SelectedMedia? profilePicture,
    SelectedMedia? headerPhoto,
    bool removeProfilePicture = false,
    bool removeHeaderPhoto = false,
  }) async {
    final formData = FormData();
    if (fullName != null) formData.fields.add(MapEntry('full_name', fullName));
    if (phone != null) formData.fields.add(MapEntry('phone', phone));
    if (description != null) {
      formData.fields.add(MapEntry('description', description));
    }
    if (removeProfilePicture) {
      formData.fields.add(const MapEntry('remove_profile_picture', 'true'));
    }
    if (removeHeaderPhoto) {
      formData.fields.add(const MapEntry('remove_header_photo', 'true'));
    }
    if (profilePicture != null) {
      formData.files.add(
        MapEntry(
          'profile_picture_file',
          MultipartFile.fromBytes(
            profilePicture.bytes,
            filename: profilePicture.name,
          ),
        ),
      );
    }
    if (headerPhoto != null) {
      formData.files.add(
        MapEntry(
          'header_photo_file',
          MultipartFile.fromBytes(
            headerPhoto.bytes,
            filename: headerPhoto.name,
          ),
        ),
      );
    }

    final response = await _dio.put('/api/users/profile', data: formData);
    return response.data as Map<String, dynamic>;
  }

  // --- Reports ---

  Future<Map<String, dynamic>> createReport({
    String? title,
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
    if (title != null && title.trim().isNotEmpty) {
      body['title'] = title.trim();
    }
    if (address != null) body['address'] = address;
    if (latitude != null) body['latitude'] = latitude;
    if (longitude != null) body['longitude'] = longitude;
    final response = await _dio.post('/api/reports', data: body);
    return response.data as Map<String, dynamic>;
  }

  Future<List<dynamic>> getReports({String? status, String? category}) async {
    final params = <String, dynamic>{};
    if (status != null && status.isNotEmpty) params['status'] = status;
    if (category != null && category.isNotEmpty) params['category'] = category;
    final response = await _dio.get('/api/reports', queryParameters: params);
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

  // Decline a report Ã¢â‚¬â€ decline_reason is required
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
  Future<List<Map<String, dynamic>>> getFeedPosts({
    String? category,
    String? uploader,
  }) async {
    final params = <String, dynamic>{};
    if (category != null) params['category'] = category;
    if (uploader != null) params['uploader'] = uploader;
    final response = await _dio.get('/api/feed', queryParameters: params);
    return (response.data['posts'] as List).cast<Map<String, dynamic>>();
  }

  // Get a single feed post by ID
  Future<Map<String, dynamic>> getFeedPost(String postId) async {
    final response = await _dio.get('/api/feed/$postId');
    return (response.data as Map<String, dynamic>)['post']
        as Map<String, dynamic>;
  }

  Future<List<Map<String, dynamic>>> getFeedComments(String postId) async {
    final response = await _dio.get('/api/feed/$postId/comments');
    return (response.data['comments'] as List).cast<Map<String, dynamic>>();
  }

  Future<Map<String, dynamic>> createFeedComment(
    String postId, {
    required String comment,
  }) async {
    final response = await _dio.post(
      '/api/feed/$postId/comments',
      data: {'comment': comment},
    );
    return (response.data as Map<String, dynamic>)['comment']
        as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> toggleFeedReaction(String postId) async {
    final response = await _dio.post('/api/feed/$postId/reaction');
    return (response.data as Map<String, dynamic>)['post']
        as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> getDepartmentPublicProfile(
    String uploaderId,
  ) async {
    final response = await _dio.get('/api/departments/view/$uploaderId');
    return response.data as Map<String, dynamic>;
  }

  /// Aggregates the citizen-facing mesh feed into a single payload so the
  /// frontend can render the redesigned feed without manually orchestrating
  /// several unrelated backend requests.
  Future<Map<String, dynamic>> getCitizenMeshFeedSnapshot() async {
    Future<List<Map<String, dynamic>>> safeList(
      Future<List<Map<String, dynamic>>> Function() loader,
    ) async {
      try {
        return await loader();
      } catch (_) {
        return const <Map<String, dynamic>>[];
      }
    }

    Future<Map<String, dynamic>> safeMap(
      Future<Map<String, dynamic>> Function() loader,
    ) async {
      try {
        return await loader();
      } catch (_) {
        return const <String, dynamic>{};
      }
    }

    final results = await Future.wait<Object>([
      safeList(() => getFeedPosts()),
      safeList(() async => (await getReports()).cast<Map<String, dynamic>>()),
      safeMap(() => getMeshMessages(includePosts: true)),
      safeMap(() => getMeshTopology()),
    ]);

    final feedPosts = results[0] as List<Map<String, dynamic>>;
    final reports = results[1] as List<Map<String, dynamic>>;
    final meshResponse = results[2] as Map<String, dynamic>;
    final topology = results[3] as Map<String, dynamic>;

    return {
      'posts': feedPosts,
      'reports': reports,
      'mesh_messages': (meshResponse['messages'] as List<dynamic>? ?? const [])
          .cast<Map<String, dynamic>>(),
      'mesh_posts': (meshResponse['mesh_posts'] as List<dynamic>? ?? const [])
          .cast<Map<String, dynamic>>(),
      'topology_nodes': (topology['nodes'] as List<dynamic>? ?? const [])
          .cast<Map<String, dynamic>>(),
    };
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

  Future<void> deleteNotification(String notificationId) async {
    await _dio.delete('/api/notifications/$notificationId');
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
    final response = await _dio.get(
      '/api/mesh/messages',
      queryParameters: params,
    );
    return response.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> getMeshLastSeen() async {
    final response = await _dio.get('/api/mesh/last-seen');
    return response.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> getMeshTopology() async {
    final response = await _dio.get('/api/mesh/topology');
    return response.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> upsertCitizenNearbyPresence({
    required String displayName,
    required double latitude,
    required double longitude,
    double? accuracyMeters,
    String? meshDeviceId,
    String? meshIdentityHash,
    DateTime? lastSeenAt,
  }) async {
    final response = await _dio.put(
      '/api/mesh/citizen-presence',
      data: {
        'display_name': displayName,
        'lat': latitude,
        'lng': longitude,
        'accuracy_meters': accuracyMeters,
        'mesh_device_id': meshDeviceId,
        'mesh_identity_hash': meshIdentityHash,
        'last_seen_at': lastSeenAt?.toUtc().toIso8601String(),
      },
    );
    return response.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> getNearbyCitizenPresence({
    required double latitude,
    required double longitude,
    int radiusMeters = 15,
    int freshnessSeconds = 15,
    int limit = 100,
  }) async {
    final response = await _dio.get(
      '/api/mesh/citizen-presence/nearby',
      queryParameters: {
        'lat': latitude,
        'lng': longitude,
        'radius_meters': radiusMeters,
        'freshness_seconds': freshnessSeconds,
        'limit': limit,
      },
    );
    return response.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> requestCitizenBleChat({
    required String recipientUserId,
    required String requesterMeshDeviceId,
    required String recipientMeshDeviceId,
    required String requesterDisplayName,
    required String recipientDisplayName,
  }) async {
    final response = await _dio.post(
      '/api/mesh/citizen-ble-chat-sessions/request',
      data: {
        'recipient_user_id': recipientUserId,
        'requester_mesh_device_id': requesterMeshDeviceId,
        'recipient_mesh_device_id': recipientMeshDeviceId,
        'requester_display_name': requesterDisplayName,
        'recipient_display_name': recipientDisplayName,
      },
    );
    return response.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> respondToCitizenBleChat({
    required String sessionId,
    required bool accept,
  }) async {
    final response = await _dio.post(
      '/api/mesh/citizen-ble-chat-sessions/${Uri.encodeComponent(sessionId)}/respond',
      data: {'action': accept ? 'accept' : 'reject'},
    );
    return response.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> closeCitizenBleChat({
    required String sessionId,
  }) async {
    final response = await _dio.post(
      '/api/mesh/citizen-ble-chat-sessions/${Uri.encodeComponent(sessionId)}/close',
    );
    return response.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> listCitizenBleChatSessions({
    int limit = 50,
  }) async {
    final response = await _dio.get(
      '/api/mesh/citizen-ble-chat-sessions',
      queryParameters: {'limit': limit},
    );
    return response.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> getMeshTrail(
    String deviceFingerprint, {
    int limit = 120,
    String? timeStart,
    String? timeEnd,
  }) async {
    final params = <String, dynamic>{'limit': limit};
    if (timeStart != null) params['time_start'] = timeStart;
    if (timeEnd != null) params['time_end'] = timeEnd;
    final response = await _dio.get(
      '/api/mesh/trail/${Uri.encodeComponent(deviceFingerprint)}',
      queryParameters: params,
    );
    return response.data as Map<String, dynamic>;
  }

  // --- Municipality (Phase 3) ---

  Future<List<Map<String, dynamic>>> getMunicipalityDepartments({
    String? status,
  }) async {
    final params = <String, dynamic>{};
    if (status != null && status.isNotEmpty) params['status'] = status;
    final response = await _dio.get(
      '/api/municipality/departments',
      queryParameters: params,
    );
    return (response.data['departments'] as List).cast<Map<String, dynamic>>();
  }

  Future<List<Map<String, dynamic>>> getMunicipalityPendingDepartments() async {
    final response = await _dio.get('/api/municipality/departments/pending');
    return (response.data['departments'] as List).cast<Map<String, dynamic>>();
  }

  Future<Map<String, dynamic>> verifyDepartment(
    String departmentId, {
    required String action,
    String rejectionReason = '',
  }) async {
    final body = <String, dynamic>{'action': action};
    if (rejectionReason.trim().isNotEmpty) {
      body['rejection_reason'] = rejectionReason.trim();
    }
    final response = await _dio.put(
      '/api/municipality/departments/$departmentId/verify',
      data: body,
    );
    return (response.data as Map<String, dynamic>)['department']
        as Map<String, dynamic>;
  }

  Future<List<Map<String, dynamic>>> getMunicipalityEscalatedReports() async {
    final response = await _dio.get('/api/municipality/reports/escalated');
    return (response.data['reports'] as List).cast<Map<String, dynamic>>();
  }

  Future<Map<String, dynamic>> getMunicipalityAnalytics() async {
    final response = await _dio.get('/api/municipality/analytics');
    return response.data as Map<String, dynamic>;
  }

  Future<List<Map<String, dynamic>>> getMunicipalityAssessments() async {
    final response = await _dio.get('/api/municipality/assessments');
    return (response.data['assessments'] as List).cast<Map<String, dynamic>>();
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
