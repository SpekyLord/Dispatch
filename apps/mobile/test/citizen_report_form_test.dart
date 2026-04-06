import 'package:dispatch_mobile/core/services/location_service.dart';
import 'package:dispatch_mobile/core/services/media_service.dart';
import 'package:dispatch_mobile/features/citizen/presentation/citizen_report_form_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

/// Fake LocationService — returns a fixed position without Geolocator.
class FakeLocationService extends LocationService {
  FakeLocationService({
    this.location = const LocationData(latitude: 16.1234, longitude: 121.5678),
  });

  final LocationData? location;

  @override
  Future<bool> isGpsAvailable() async => true;

  @override
  Future<LocationData?> getCurrentPosition() async => location;
}

/// Fake MediaService — no real image_picker calls.
class FakeMediaService extends MediaService {
  @override
  Future<SelectedMedia?> pickImageFromGallery() async => null;

  @override
  Future<SelectedMedia?> pickImageFromCamera() async => null;
}

void main() {
  Widget buildTestWidget({LocationService? locationService}) {
    // Use a very tall surface so the ListView renders ALL items (including
    // the submit button which sits below the 200px map).
    return ProviderScope(
      overrides: [
        locationServiceProvider.overrideWith(
          (ref) => locationService ?? FakeLocationService(),
        ),
        mediaServiceProvider.overrideWith((ref) => FakeMediaService()),
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

  testWidgets('GPS detection updates status and map selected coordinate', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(buildTestWidget());
    await tester.pumpAndSettle();

    expect(find.text('GPS: 16.1234, 121.5678'), findsOneWidget);
    expect(find.text('16.1234, 121.5678'), findsOneWidget);
  });

  testWidgets('manual pin selection updates map coordinate text', (tester) async {
    tester.view.physicalSize = const Size(400, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(buildTestWidget());
    await tester.pumpAndSettle();

    final map = tester.widget<FlutterMap>(find.byType(FlutterMap));
    map.options.onTap?.call(
      const TapPosition(Offset.zero, Offset.zero),
      const LatLng(11.4321, 122.5432),
    );
    await tester.pump();

    expect(find.text('11.4321, 122.5432'), findsOneWidget);
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

  testWidgets('shows error when submitting without description', (
    tester,
  ) async {
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
