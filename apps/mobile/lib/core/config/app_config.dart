import 'package:flutter/foundation.dart';

// App config can be injected via --dart-define / --dart-define-from-file.
// Android emulator defaults to 10.0.2.2 (the emulator's host alias); other
// native platforms (Windows, macOS, Linux, iOS) default to 127.0.0.1; web
// derives the host from the current browser URI so Chrome always resolves
// correctly without any explicit configuration.
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
      isAndroid: defaultTargetPlatform == TargetPlatform.android,
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
  required bool isAndroid,
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

  // 10.0.2.2 is the Android emulator's loopback alias for the host machine.
  // Physical Android devices, Windows, macOS, Linux, and iOS all use the
  // standard loopback address instead.
  return isAndroid ? 'http://10.0.2.2:5000' : 'http://127.0.0.1:5000';
}

bool _isAndroidEmulatorAlias(String url) {
  final uri = Uri.tryParse(url);
  return uri?.host == '10.0.2.2';
}
