class AppConfig {
  const AppConfig({
    required this.apiBaseUrl,
    required this.supabaseAnonKey,
    required this.supabaseUrl,
  });

  final String apiBaseUrl;
  final String supabaseAnonKey;
  final String supabaseUrl;

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
