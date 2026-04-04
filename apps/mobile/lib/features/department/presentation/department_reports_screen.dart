import 'package:dispatch_mobile/features/department/presentation/department_report_board_screen.dart';
import 'package:flutter/material.dart';

/// Thin wrapper that delegates to [DepartmentReportBoardScreen], which is the
/// full implementation with real-time subscriptions, filtering, and navigation.
class DepartmentReportsScreen extends StatelessWidget {
  const DepartmentReportsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const DepartmentReportBoardScreen();
  }
}
