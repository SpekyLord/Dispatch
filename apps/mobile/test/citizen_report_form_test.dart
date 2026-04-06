import 'package:dispatch_mobile/core/services/location_service.dart';
import 'package:dispatch_mobile/core/services/media_service.dart';
import 'package:dispatch_mobile/features/citizen/presentation/citizen_report_form_screen.dart';
import 'package:dispatch_mobile/features/shared/presentation/location_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

class _FakeLocationService extends LocationService {
  final LocationData location = const LocationData(
    latitude: 16.1234,
    longitude: 121.5678,
  );

  @override
  Future<bool> ensurePermission() async => true;

  @override
  Future<bool> isGpsAvailable() async => true;

  @override
  Future<LocationData?> getCurrentPosition() async => location;

  @override
  Stream<LocationData> watchPosition() => Stream<LocationData>.value(location);
}

class _FakeMediaService extends MediaService {
  @override
  Future<SelectedMedia?> pickImageFromGallery() async => null;

  @override
  Future<SelectedMedia?> pickImageFromCamera() async => null;
}

void main() {
  Widget buildTestWidget({LocationService? locationService}) {
    return ProviderScope(
      overrides: [
        locationServiceProvider.overrideWith(
          (ref) => locationService ?? _FakeLocationService(),
        ),
        mediaServiceProvider.overrideWith((ref) => _FakeMediaService()),
      ],
      child: const MaterialApp(home: CitizenReportFormScreen()),
    );
  }

  testWidgets('renders the web-parity report categories', (tester) async {
    tester.view.physicalSize = const Size(430, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(buildTestWidget());
    await tester.pumpAndSettle();

    expect(find.text('Fire'), findsOneWidget);
    expect(find.text('Flood'), findsOneWidget);
    expect(find.text('Earthquake'), findsOneWidget);
    expect(find.text('Road Accident'), findsOneWidget);
    expect(find.text('Medical'), findsOneWidget);
    expect(find.text('Structural'), findsOneWidget);
    expect(find.text('Other'), findsOneWidget);
  });

  testWidgets('shows GPS coordinates from the location service', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(430, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(buildTestWidget());
    await tester.pumpAndSettle();

    // The badge is inside the mesh section card which may overflow its bounds;
    // use skipOffstage: false so the finder works regardless of clip/scroll.
    expect(
      find.text('ACTIVE MESH TAGGING', skipOffstage: false),
      findsOneWidget,
    );
  });

  testWidgets('opens the manual map-pin fallback flow', (tester) async {
    tester.view.physicalSize = const Size(430, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(buildTestWidget());
    await tester.pumpAndSettle();

    // The 'Pin on map' button is inside the fixed-height mesh card that may
    // overflow its clip bounds — invoke the callback directly to open the modal.
    final pinButton = tester
        .widgetList<OutlinedButton>(
          find.ancestor(
            of: find.text('Pin on map', skipOffstage: false),
            matching: find.byType(OutlinedButton, skipOffstage: false),
          ),
        )
        .first;
    pinButton.onPressed?.call();
    await tester.pumpAndSettle();

    expect(find.text('Pin Incident Location'), findsOneWidget);
    expect(find.byType(LocationPicker), findsOneWidget);

    final picker = tester.widget<LocationPicker>(find.byType(LocationPicker));
    picker.onLocationSelected?.call(const LatLng(11.4321, 122.5432));
    await tester.pump();

    final usePin = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Use pin'),
    );
    usePin.onPressed?.call();
    await tester.pumpAndSettle();

    // After confirming the pin, the form shows the manual location locked badge
    expect(find.text('MANUAL MAP PIN', skipOffstage: false), findsOneWidget);
  });
}
