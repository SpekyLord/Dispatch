import 'package:dispatch_mobile/core/services/auth_service.dart';
import 'package:dispatch_mobile/core/state/session.dart';
import 'package:dispatch_mobile/features/department/presentation/department_assessment_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeAssessmentAuthService extends AuthService {
  FakeAssessmentAuthService() : super();

  final List<Map<String, dynamic>> _assessments = [
    {
      'id': 'assess-1',
      'affected_area': 'Barangay Centro',
      'damage_level': 'moderate',
      'estimated_casualties': 1,
      'displaced_persons': 5,
      'location': 'Main Road',
      'description': 'Initial assessment complete.',
      'created_at': '2026-03-29T08:00:00Z',
    },
  ];

  @override
  Future<List<Map<String, dynamic>>> getDepartmentAssessments() async {
    return List<Map<String, dynamic>>.from(_assessments);
  }

  @override
  Future<Map<String, dynamic>> createAssessment({
    required String affectedArea,
    required String damageLevel,
    int estimatedCasualties = 0,
    int displacedPersons = 0,
    String? location,
    String? description,
    String? reportId,
  }) async {
    _assessments.insert(0, {
      'id': 'assess-${_assessments.length + 1}',
      'affected_area': affectedArea,
      'damage_level': damageLevel,
      'estimated_casualties': estimatedCasualties,
      'displaced_persons': displacedPersons,
      'location': location,
      'description': description,
      'created_at': '2026-03-29T09:00:00Z',
    });
    return {'ok': true};
  }
}

void main() {
  testWidgets(
    'department assessments support locale switching and refresh after submit',
    (tester) async {
      final auth = FakeAssessmentAuthService();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [authServiceProvider.overrideWithValue(auth)],
          child: const MaterialApp(home: DepartmentAssessmentScreen()),
        ),
      );

      await tester.pump();
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Language'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Filipino'));
      await tester.pumpAndSettle();

      expect(find.text('Bagong Pagtatasa'), findsOneWidget);

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Apektadong Lugar *'),
        'Barangay Riverside',
      );
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Kritikal').last);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Tinatayang Nasawi'),
        '3',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Mga Lumikas'),
        '14',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Lokasyon'),
        'Floodplain',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Paglalarawan'),
        'Flood damage has cut road access.',
      );

      await tester.tap(find.widgetWithText(FilledButton, 'Isumite ang Pagtatasa'));
      await tester.pump();
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.text('Mga Naunang Pagtatasa'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();

      expect(find.text('Mga Naunang Pagtatasa'), findsOneWidget);
      expect(find.text('Naipasa ang pagtatasa'), findsOneWidget);
      expect(find.text('Barangay Riverside'), findsOneWidget);
      expect(find.text('KRITIKAL'), findsOneWidget);
    },
  );
}
