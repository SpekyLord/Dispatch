import 'package:dispatch_mobile/core/config/app_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('resolveApiBaseUrl', () {
    test('defaults Android builds to the emulator loopback alias', () {
      final url = resolveApiBaseUrl(
        isWeb: false,
        isAndroid: true,
        configuredApiBaseUrl: '',
        configuredWebApiBaseUrl: '',
        currentUri: Uri.parse('http://localhost:4321'),
      );

      expect(url, 'http://10.0.2.2:5000');
    });

    test('defaults non-Android native builds to 127.0.0.1', () {
      final url = resolveApiBaseUrl(
        isWeb: false,
        isAndroid: false,
        configuredApiBaseUrl: '',
        configuredWebApiBaseUrl: '',
        currentUri: Uri.parse('http://localhost:4321'),
      );

      expect(url, 'http://127.0.0.1:5000');
    });

    test(
      'uses the browser host for web when the Android alias is configured',
      () {
        final url = resolveApiBaseUrl(
          isWeb: true,
          isAndroid: false,
          configuredApiBaseUrl: 'http://10.0.2.2:5000',
          configuredWebApiBaseUrl: '',
          currentUri: Uri.parse('http://localhost:4321'),
        );

        expect(url, 'http://localhost:5000');
      },
    );

    test('prefers the dedicated web override when it is provided', () {
      final url = resolveApiBaseUrl(
        isWeb: true,
        isAndroid: false,
        configuredApiBaseUrl: 'http://10.0.2.2:5000',
        configuredWebApiBaseUrl: 'http://127.0.0.1:5000',
        currentUri: Uri.parse('http://localhost:4321'),
      );

      expect(url, 'http://127.0.0.1:5000');
    });

    test('keeps an explicit shared override that is safe for web', () {
      final url = resolveApiBaseUrl(
        isWeb: true,
        isAndroid: false,
        configuredApiBaseUrl: 'http://192.168.1.50:5000',
        configuredWebApiBaseUrl: '',
        currentUri: Uri.parse('http://localhost:4321'),
      );

      expect(url, 'http://192.168.1.50:5000');
    });
  });
}
