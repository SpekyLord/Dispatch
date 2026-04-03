import 'package:dispatch_mobile/core/state/session.dart';
import 'package:dispatch_mobile/core/theme/dispatch_theme.dart';
import 'package:dispatch_mobile/core/routing/app_root.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:dispatch/apps/mobile/lib/app_router.dart';
import 'package:dispatch/apps/mobile/lib/features/auth/bloc/auth_bloc.dart';

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
    return MaterialApp.router(
      title: 'Dispatch',
      theme: buildDispatchLightTheme(),
      darkTheme: buildDispatchDarkTheme(),
      routerConfig: AppRouter(authBloc: ref.read(authBlocProvider)),
    );
  }
}

class App extends StatefulWidget {
  const App({super.key});

  @override
  _AppState createState() => _AppState();
}

class _AppState extends State<App> {
  late final AuthBloc _authBloc;
  late final AppRouter _appRouter;

  @override
  void initState() {
    super.initState();
    _authBloc = AuthBloc();
    _appRouter = AppRouter(authBloc: _authBloc);
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider.value(
      value: _authBloc,
      child: MaterialApp.router(
        title: 'Dispatch',
        theme: ThemeData(
          primarySwatch: Colors.blue,
          visualDensity: VisualDensity.adaptivePlatformDensity,
        ),
        routerConfig: _appRouter.router,
      ),
    );
  }

  @override
  void dispose() {
    _authBloc.close();
    super.dispose();
  }
}
