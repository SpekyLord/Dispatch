import 'package:dispatch_mobile/core/state/session.dart';
import 'package:dispatch_mobile/core/theme/dispatch_theme.dart';
import 'package:dispatch_mobile/core/routing/app_root.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class DispatchMobileApp extends ConsumerStatefulWidget {
  const DispatchMobileApp({super.key});

  @override
  ConsumerState<DispatchMobileApp> createState() => _DispatchMobileAppState();
}

class _DispatchMobileAppState extends ConsumerState<DispatchMobileApp>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.read(sessionControllerProvider.notifier).handleAppResumed();
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Dispatch',
      theme: buildDispatchLightTheme(),
      darkTheme: buildDispatchDarkTheme(),
      home: const AppRoot(),
    );
  }
}
