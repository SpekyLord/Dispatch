import 'package:dispatch_mobile/core/config/app_config.dart';
import 'package:dispatch_mobile/core/state/session_controller.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase/supabase.dart';

final realtimeServiceProvider = Provider<RealtimeService>((ref) {
  final service = RealtimeService();
  ref.listen<String?>(
    sessionControllerProvider.select((state) => state.accessToken),
    (_, next) {
      service.setAccessToken(next);
    },
    fireImmediately: true,
  );
  ref.onDispose(() {
    service.dispose();
  });
  return service;
});

class RealtimeSubscriptionHandle {
  const RealtimeSubscriptionHandle(this._dispose);

  final Future<void> Function() _dispose;

  Future<void> dispose() => _dispose();

  factory RealtimeSubscriptionHandle.noop() {
    return RealtimeSubscriptionHandle(() async {});
  }
}

class RealtimeService {
  RealtimeService({AppConfig? config, SupabaseClient? client})
    : _config = config ?? AppConfig.current,
      _client = client;

  final AppConfig _config;
  SupabaseClient? _client;
  String? _accessToken;

  bool get isConfigured => _config.hasRealtimeConfig;

  void setAccessToken(String? accessToken) {
    _accessToken = accessToken;
    final client = _client;
    if (client == null) {
      return;
    }
    client.realtime.setAuth(accessToken ?? _config.supabaseAnonKey);
  }

  RealtimeSubscriptionHandle subscribeToTable({
    required String table,
    String? eqColumn,
    Object? eqValue,
    required VoidCallback onChange,
  }) {
    final client = _ensureClient();
    if (client == null) {
      return RealtimeSubscriptionHandle.noop();
    }

    final filter = eqColumn != null && eqValue != null
        ? PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: eqColumn,
            value: eqValue,
          )
        : null;

    final channel = client.channel(
      'phase2:$table:${filter?.toString() ?? 'all'}:${DateTime.now().microsecondsSinceEpoch}',
    );
    channel
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: table,
          filter: filter,
          callback: (_) => onChange(),
        )
        .subscribe();

    return RealtimeSubscriptionHandle(() async {
      await client.removeChannel(channel);
    });
  }

  Future<void> dispose() async {
    final client = _client;
    if (client == null) {
      return;
    }
    await client.removeAllChannels();
    await client.dispose();
    _client = null;
  }

  SupabaseClient? _ensureClient() {
    if (!isConfigured) {
      return null;
    }

    _client ??= SupabaseClient(
      _config.supabaseUrl,
      _config.supabaseAnonKey,
      accessToken: () async => _accessToken,
    );
    _client!.realtime.setAuth(_accessToken ?? _config.supabaseAnonKey);
    return _client;
  }
}
