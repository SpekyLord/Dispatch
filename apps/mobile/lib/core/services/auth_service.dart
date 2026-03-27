import 'package:dispatch_mobile/core/config/app_config.dart';
import 'package:dio/dio.dart';

class AuthService {
  AuthService({Dio? dio}) : _dio = dio ?? Dio(BaseOptions(baseUrl: AppConfig.current.apiBaseUrl));

  final Dio _dio;

  Dio get client => _dio;
}
