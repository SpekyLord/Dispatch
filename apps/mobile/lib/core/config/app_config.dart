import 'package:flutter/foundation.dart';

// App config can be injected via --dart-define / --dart-define-from-file.
// Android defaults to the emulator loopback alias; web defaults to the
// current browser host on port 5000 so Chrome can reach the local API.
class AppConfig {
  const AppConfig({
    required this.apiBaseUrl,
    required this.supabaseAnonKey,
    required this.supabaseUrl,
  });

  final String apiBaseUrl;
  final String supabaseAnonKey;
  final String supabaseUrl;

  // Both URL and key needed for realtime features
  bool get hasRealtimeConfig =>
      supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;

  static const _configuredApiBaseUrl = String.fromEnvironment(
    'MOBILE_API_BASE_URL',
  );
  static const _configuredWebApiBaseUrl = String.fromEnvironment(
    'MOBILE_WEB_API_BASE_URL',
  );
  static const _configuredSupabaseAnonKey = String.fromEnvironment(
    'MOBILE_SUPABASE_ANON_KEY',
  );
  static const _configuredSupabaseUrl = String.fromEnvironment(
    'MOBILE_SUPABASE_URL',
  );

  static final current = AppConfig(
    apiBaseUrl: resolveApiBaseUrl(
      isWeb: kIsWeb,
      configuredApiBaseUrl: _configuredApiBaseUrl,
      configuredWebApiBaseUrl: _configuredWebApiBaseUrl,
      currentUri: Uri.base,
    ),
    supabaseAnonKey: _configuredSupabaseAnonKey,
    supabaseUrl: _configuredSupabaseUrl,
  );
}

String resolveApiBaseUrl({
  required bool isWeb,
  required String configuredApiBaseUrl,
  required String configuredWebApiBaseUrl,
  required Uri currentUri,
}) {
  final apiOverride = configuredApiBaseUrl.trim();
  final webOverride = configuredWebApiBaseUrl.trim();

  if (isWeb) {
    if (webOverride.isNotEmpty) {
      return webOverride;
    }

    if (apiOverride.isNotEmpty && !_isAndroidEmulatorAlias(apiOverride)) {
      return apiOverride;
    }

    final host = currentUri.host.isNotEmpty ? currentUri.host : '127.0.0.1';
    final scheme = currentUri.scheme == 'https' ? 'https' : 'http';
    return '$scheme://$host:5000';
  }

  if (apiOverride.isNotEmpty) {
    return apiOverride;
  }

  return 'http://10.0.2.2:5000';
}

bool _isAndroidEmulatorAlias(String url) {
  final uri = Uri.tryParse(url);
  return uri?.host == '10.0.2.2';
}
