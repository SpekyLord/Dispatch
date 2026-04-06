import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

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

  static AppConfig? _current;

  static AppConfig get current => _current ??= _build();

  static Future<void> initialize() async {
    final bundledConfig = await _loadBundledConfig();
    _current = _build(bundledConfig);
  }

  static AppConfig _build([Map<String, String>? bundledConfig]) {
    final resolvedApiBaseUrl = _firstNonEmpty(
      _configuredApiBaseUrl,
      bundledConfig?['MOBILE_API_BASE_URL'],
    );
    final resolvedWebApiBaseUrl = _firstNonEmpty(
      _configuredWebApiBaseUrl,
      bundledConfig?['MOBILE_WEB_API_BASE_URL'],
    );
    final resolvedSupabaseUrl = _firstNonEmpty(
      _configuredSupabaseUrl,
      bundledConfig?['MOBILE_SUPABASE_URL'],
    );
    final resolvedSupabaseAnonKey = _firstNonEmpty(
      _configuredSupabaseAnonKey,
      bundledConfig?['MOBILE_SUPABASE_ANON_KEY'],
    );

    return AppConfig(
      apiBaseUrl: resolveApiBaseUrl(
        isWeb: kIsWeb,
        isAndroid: defaultTargetPlatform == TargetPlatform.android,
        configuredApiBaseUrl: resolvedApiBaseUrl,
        configuredWebApiBaseUrl: resolvedWebApiBaseUrl,
        currentUri: Uri.base,
      ),
      supabaseAnonKey: resolvedSupabaseAnonKey,
      supabaseUrl: resolvedSupabaseUrl,
    );
  }

  static Future<Map<String, String>?> _loadBundledConfig() async {
    try {
      final rawConfig = await rootBundle.loadString(
        'assets/config/app_config.json',
      );
      final decoded = jsonDecode(rawConfig);
      if (decoded is! Map<String, dynamic>) {
        return null;
      }

      return decoded.map(
        (key, value) => MapEntry(key, value?.toString() ?? ''),
      );
    } catch (_) {
      return null;
    }
  }
}

String _firstNonEmpty(String primary, String? secondary) {
  final trimmedPrimary = primary.trim();
  if (trimmedPrimary.isNotEmpty) {
    return trimmedPrimary;
  }

  final trimmedSecondary = secondary?.trim() ?? '';
  if (trimmedSecondary.isNotEmpty) {
    return trimmedSecondary;
  }

  return '';
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

    if (apiOverride.isNotEmpty && !isAndroidEmulatorAlias(apiOverride)) {
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

bool isAndroidEmulatorAlias(String url) {
  final uri = Uri.tryParse(url);
  return uri?.host == '10.0.2.2';
}

bool isLoopbackApiUrl(String url) {
  final uri = Uri.tryParse(url);
  final host = uri?.host.toLowerCase();
  return host == '10.0.2.2' || host == '127.0.0.1' || host == 'localhost';
}

String? buildMobileApiUrlHelp({
  required bool isWeb,
  required bool isAndroid,
  required String url,
}) {
  if (isWeb || !isAndroid) {
    return null;
  }

  if (isAndroidEmulatorAlias(url)) {
    return 'This Android build is still using 10.0.2.2, which only works in '
        'the Android emulator. On a physical phone or installed APK, use your '
        'computer\'s LAN IP or a public API URL instead.';
  }

  final uri = Uri.tryParse(url);
  final host = uri?.host.toLowerCase();
  if (host == '127.0.0.1' || host == 'localhost') {
    return 'This Android build is pointing at localhost. A physical phone '
        'cannot reach your computer through localhost, so use your computer\'s '
        'LAN IP or a public API URL instead.';
  }

  return null;
}
