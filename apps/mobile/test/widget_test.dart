import 'package:dispatch_mobile/app.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

void main() {
  testWidgets('renders the phase 0 auth shell by default', (WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: DispatchMobileApp()));

    expect(find.textContaining('Dispatch mobile foundation'), findsOneWidget);
    expect(find.textContaining('Continue as citizen'), findsOneWidget);
  });
}
