import 'package:dispatch_mobile/app.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

void main() {
  testWidgets('renders the login screen by default', (WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: DispatchMobileApp()));

    expect(find.textContaining('DISPATCH'), findsOneWidget);
    expect(find.textContaining('Sign in'), findsWidgets);
  });
}
