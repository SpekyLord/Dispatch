import 'package:dispatch_mobile/features/shared/presentation/widgets/bottom_nav_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('renders the citizen shell nav with a dedicated reports tab', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          bottomNavigationBar: AppBottomNavigationBar(
            selectedIndex: 2,
            onItemTapped: (_) {},
            onCenterActionTap: () {},
            showCitizenReportsTab: true,
            showCitizenNotificationsTab: true,
          ),
        ),
      ),
    );

    expect(find.text('MESH'), findsOneWidget);
    expect(find.text('MAP'), findsOneWidget);
    expect(find.text('REPORTS'), findsOneWidget);
    expect(find.text('FEED'), findsOneWidget);
    expect(find.text('NOTIFS'), findsOneWidget);
    expect(find.text('SETTINGS'), findsNothing);
    expect(find.text('Submit\nReport'), findsOneWidget);
  });

  testWidgets('routes feed and notifications indexes correctly when reports tab is enabled', (tester) async {
    final tapped = <int>[];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          bottomNavigationBar: AppBottomNavigationBar(
            selectedIndex: 0,
            onItemTapped: tapped.add,
            onCenterActionTap: () {},
            showCitizenReportsTab: true,
            showCitizenNotificationsTab: true,
          ),
        ),
      ),
    );

    await tester.tap(find.text('FEED'));
    await tester.pump();
    await tester.tap(find.text('NOTIFS'));
    await tester.pump();

    expect(tapped, <int>[3, 4]);
  });
}
