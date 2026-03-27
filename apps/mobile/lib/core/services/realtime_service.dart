import 'package:dispatch_mobile/core/config/app_config.dart';

class RealtimeService {
  bool get isConfigured => AppConfig.current.hasRealtimeConfig;

  List<String> subscribedTopics() {
    if (!isConfigured) {
      return const [];
    }
    return const [
      'dispatch:reports',
      'dispatch:department-responses',
      'dispatch:notifications',
      'dispatch:feed',
    ];
  }
}
