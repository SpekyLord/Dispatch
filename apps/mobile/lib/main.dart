import 'package:dispatch_mobile/app.dart';
import 'package:dispatch_mobile/core/config/app_config.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppConfig.initialize();
  runApp(const ProviderScope(child: DispatchMobileApp()));
}
