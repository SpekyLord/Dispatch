// App config — injected via --dart-define at build time.
// Default API URL uses 10.0.2.2 (Android emulator alias for host localhost).
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
  bool get hasRealtimeConfig => supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;

  static const current = AppConfig(
    apiBaseUrl: String.fromEnvironment(
      'MOBILE_API_BASE_URL',
      defaultValue: 'http://10.0.2.2:5000',
    ),
    supabaseAnonKey: String.fromEnvironment('MOBILE_SUPABASE_ANON_KEY'),
    supabaseUrl: String.fromEnvironment('MOBILE_SUPABASE_URL'),
  );
}
