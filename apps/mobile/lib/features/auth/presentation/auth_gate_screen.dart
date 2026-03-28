// Auth gate — toggles between login and register screens.

import 'package:dispatch_mobile/features/auth/presentation/login_screen.dart';
import 'package:dispatch_mobile/features/auth/presentation/register_screen.dart';
import 'package:flutter/material.dart';

class AuthGateScreen extends StatefulWidget {
  const AuthGateScreen({super.key});

  @override
  State<AuthGateScreen> createState() => _AuthGateScreenState();
}

class _AuthGateScreenState extends State<AuthGateScreen> {
  bool _showLogin = true;

  @override
  Widget build(BuildContext context) {
    return _showLogin
        ? LoginScreen(onSwitchToRegister: () => setState(() => _showLogin = false))
        : RegisterScreen(onSwitchToLogin: () => setState(() => _showLogin = true));
  }
}
