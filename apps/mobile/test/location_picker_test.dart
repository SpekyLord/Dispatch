import 'package:dispatch_mobile/features/shared/presentation/location_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

class _LocationPickerHarness extends StatefulWidget {
  const _LocationPickerHarness({required GlobalKey<_LocationPickerHarnessState> harnessKey})
    : super(key: harnessKey);

  @override
  State<_LocationPickerHarness> createState() => _LocationPickerHarnessState();
}

class _LocationPickerHarnessState extends State<_LocationPickerHarness> {
  double latitude = 14.5995;
  double longitude = 120.9842;

  void updateCenter({required double latitude, required double longitude}) {
    setState(() {
      this.latitude = latitude;
      this.longitude = longitude;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: LocationPicker(
          initialLatitude: latitude,
          initialLongitude: longitude,
          height: 220,
        ),
      ),
    );
  }
}

void main() {
  testWidgets('updates selected coordinate when external center changes', (
    tester,
  ) async {
    final key = GlobalKey<_LocationPickerHarnessState>();

    await tester.pumpWidget(_LocationPickerHarness(harnessKey: key));
    await tester.pumpAndSettle();

    expect(find.text('14.5995, 120.9842'), findsOneWidget);

    key.currentState!.updateCenter(latitude: 16.1234, longitude: 121.5678);
    await tester.pump();
    await tester.pump();

    expect(find.text('16.1234, 121.5678'), findsOneWidget);
  });

  testWidgets('does not auto-recenter after user tap interaction', (
    tester,
  ) async {
    final key = GlobalKey<_LocationPickerHarnessState>();

    await tester.pumpWidget(_LocationPickerHarness(harnessKey: key));
    await tester.pumpAndSettle();

    final map = tester.widget<FlutterMap>(find.byType(FlutterMap));
    map.options.onTap?.call(
      const TapPosition(Offset.zero, Offset.zero),
      const LatLng(11.1111, 122.2222),
    );
    await tester.pump();

    expect(find.text('11.1111, 122.2222'), findsOneWidget);

    key.currentState!.updateCenter(latitude: 18.8888, longitude: 123.7777);
    await tester.pump();
    await tester.pump();

    expect(find.text('11.1111, 122.2222'), findsOneWidget);
    expect(find.text('18.8888, 123.7777'), findsNothing);
  });
}
