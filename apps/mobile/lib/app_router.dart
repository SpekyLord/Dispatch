import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:dispatch_mobile/features/auth/bloc/auth_bloc.dart';
import 'package:dispatch_mobile/features/auth/presentation/login_screen.dart';
import 'package:dispatch_mobile/features/citizen/presentation/citizen_home_screen.dart';
import 'package:go_router/go_router.dart';

class AppRouter {
  final AuthBloc authBloc;

  AppRouter({required this.authBloc});

  late final GoRouter router = GoRouter(
    routes: <GoRoute>[
      GoRoute(
        path: '/',
        builder: (BuildContext context, GoRouterState state) {
          return const CitizenHomeScreen(); // Or a landing/splash screen
        },
      ),
      GoRoute(
        path: '/auth/login',
        builder: (BuildContext context, GoRouterState state) {
          return const LoginScreen();
        },
      ),
      // ... other routes
    ],
    redirect: (BuildContext context, GoRouterState state) {
      final bool loggedIn = authBloc.state is AuthAuthenticated;
      final bool loggingIn = state.matchedLocation == '/auth/login';

      if (!loggedIn) {
        return '/auth/login';
      }

      if (loggingIn) {
        return '/';
      }

      return null;
    },
    refreshListenable: GoRouterRefreshStream(authBloc.stream),
  );
}

class GoRouterRefreshStream extends ChangeNotifier {
  GoRouterRefreshStream(Stream<dynamic> stream) {
    notifyListeners();
    _subscription = stream.asBroadcastStream().listen((_) => notifyListeners());
  }

  late final _subscription;

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }
}
