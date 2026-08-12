import 'package:flutter_test/flutter_test.dart';

import 'package:drais/core/config/app_config.dart';
import 'package:drais/core/config/environment.dart';

/// Configuration validation is a release gate, so the failure cases matter
/// more than the happy path.
///
/// The most important case is the *absence* of a server address: it must be
/// valid, because the app asks the user rather than guessing. A default of
/// `localhost` is what previously pointed builds at a developer's machine.
void main() {
  group('Environment.fromName', () {
    test('recognises canonical names and short forms', () {
      expect(Environment.fromName('production'), Environment.production);
      expect(Environment.fromName('prod'), Environment.production);
      expect(Environment.fromName('staging'), Environment.staging);
      expect(Environment.fromName('qa'), Environment.qa);
      expect(Environment.fromName('DEV'), Environment.development);
    });

    test('falls back to development for anything unrecognised', () {
      expect(Environment.fromName(null), Environment.development);
      expect(Environment.fromName('nonsense'), Environment.development);
    });

    test('only production suppresses diagnostics', () {
      expect(Environment.production.allowsDiagnostics, isFalse);
      expect(Environment.staging.allowsDiagnostics, isTrue);
      expect(Environment.qa.allowsDiagnostics, isTrue);
      expect(Environment.development.allowsDiagnostics, isTrue);
    });
  });

  group('AppConfig.validate', () {
    test('a build with no server address is valid', () {
      // The defining case. Screens are compiled into the binary, so the app
      // opens and renders with no server; it asks when data is first needed.
      const AppConfig config = AppConfig.test(
        environment: Environment.production,
        allowInsecureHttp: false,
      );

      expect(config.defaultApiBaseUrl, isNull);
      expect(config.validate(), isEmpty);
    });

    test('accepts a well-formed production default', () {
      const AppConfig config = AppConfig.test(
        environment: Environment.production,
        defaultApiBaseUrl: 'https://app.drais.pro',
        allowInsecureHttp: false,
      );

      expect(config.validate(), isEmpty);
    });

    test('rejects cleartext http when insecure transport is disallowed', () {
      const AppConfig config = AppConfig.test(
        environment: Environment.production,
        defaultApiBaseUrl: 'http://app.drais.pro',
        allowInsecureHttp: false,
      );

      expect(config.validate(), contains(contains('cleartext http')));
    });

    test('rejects a production build defaulting to a local address', () {
      const AppConfig config = AppConfig.test(
        environment: Environment.production,
        defaultApiBaseUrl: 'https://localhost',
        allowInsecureHttp: false,
      );

      expect(config.validate(), contains(contains('local address')));
    });

    test('rejects a non-absolute default', () {
      const AppConfig config = AppConfig.test(
        defaultApiBaseUrl: 'app.drais.pro',
      );

      expect(config.validate(), contains(contains('not an absolute URL')));
    });

    test('rejects an out-of-range page size', () {
      const AppConfig config = AppConfig.test(defaultPageSize: 0);

      expect(config.validate(), contains(contains('DRAIS_PAGE_SIZE')));
    });
  });
}
