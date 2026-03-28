import 'package:dispatch_mobile/core/services/location_service.dart';
import 'package:dispatch_mobile/core/services/media_service.dart';
import 'package:dispatch_mobile/features/citizen/presentation/citizen_report_form_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Fake LocationService — returns a fixed position without Geolocator.
class FakeLocationService extends LocationService {
  @override
  Future<bool> isGpsAvailable() async => true;

  @override
  Future<LocationData?> getCurrentPosition() async {
    return const LocationData(latitude: 14.5995, longitude: 120.9842);
  }
}

/// Fake MediaService — no real image_picker calls.
class FakeMediaService extends MediaService {
  @override
  Future<SelectedMedia?> pickImageFromGallery() async => null;

  @override
  Future<SelectedMedia?> pickImageFromCamera() async => null;
}

void main() {
  Widget buildTestWidget() {
    // Use a very tall surface so the ListView renders ALL items (including
    // the submit button which sits below the 200px map).
    return ProviderScope(
      overrides: [
        locationServiceProvider.overrideWithValue(FakeLocationService()),
        mediaServiceProvider.overrideWithValue(FakeMediaService()),
      ],
      child: MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(size: Size(400, 2000)),
          child: const CitizenReportFormScreen(),
        ),
      ),
    );
  }

  testWidgets('renders description and category fields', (tester) async {
    // Set a large surface so the full form renders
    tester.view.physicalSize = const Size(400, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(buildTestWidget());
    await tester.pump();

    expect(find.text('Description *'), findsOneWidget);
    expect(find.text('Category *'), findsOneWidget);
    expect(find.text('Severity'), findsOneWidget);
    expect(find.text('Address / Location'), findsOneWidget);
    expect(find.text('Submit Report'), findsOneWidget);
  });

  testWidgets('shows error when submitting without category', (tester) async {
    tester.view.physicalSize = const Size(400, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(buildTestWidget());
    await tester.pump();

    // Enter description
    await tester.enterText(find.byType(TextField).first, 'Test description');

    // Tap submit without selecting category
    await tester.tap(find.byType(FilledButton));
    await tester.pump();

    expect(find.text('Please select a category.'), findsOneWidget);
  });

  testWidgets('shows error when submitting without description', (tester) async {
    tester.view.physicalSize = const Size(400, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(buildTestWidget());
    await tester.pump();

    // Select a category via dropdown
    await tester.tap(find.byType(DropdownButtonFormField<String>).first);
    await tester.pump();
    await tester.tap(find.text('Fire').last);
    await tester.pump();

    // Tap submit without entering description
    await tester.tap(find.byType(FilledButton));
    await tester.pump();

    expect(find.text('Description is required.'), findsOneWidget);
  });
}
