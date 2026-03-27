import 'package:dispatch_mobile/core/routing/app_root.dart';
import 'package:flutter/material.dart';

class DispatchMobileApp extends StatelessWidget {
  const DispatchMobileApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Dispatch',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFE05A2B),
          secondary: const Color(0xFF1695D3),
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: const Color(0xFFFDF7F2),
        useMaterial3: true,
      ),
      home: const AppRoot(),
    );
  }
}
