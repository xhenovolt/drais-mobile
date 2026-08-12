import 'package:flutter_test/flutter_test.dart';

import 'package:drais/core/config/environment.dart';
import 'package:drais/core/config/server_config.dart';

/// The server address is typed by a school administrator under time pressure,
/// often from a note. Normalisation is forgiving on purpose; validation is
/// strict only where being wrong has a cost.
void main() {
  group('ServerConfig.normalise', () {
    test('adds https to a bare public host', () {
      expect(ServerConfig.normalise('drais.pro'), 'https://drais.pro');
    });

    test('adds http to a bare private address', () {
      // A school server on the LAN has no certificate to present, so https
      // would fail. Assuming http for a private address is the useful default.
      expect(
        ServerConfig.normalise('192.168.1.50:3210'),
        'http://192.168.1.50:3210',
      );
    });

    test('strips a trailing slash', () {
      expect(ServerConfig.normalise('https://drais.pro/'), 'https://drais.pro');
    });

    test('strips a trailing /api, since endpoints carry their own', () {
      expect(
        ServerConfig.normalise('https://drais.pro/api'),
        'https://drais.pro',
      );
    });

    test('preserves a port', () {
      expect(
        ServerConfig.normalise('http://10.0.1.7:3210'),
        'http://10.0.1.7:3210',
      );
    });

    test('preserves a sub-path for path-prefixed deployments', () {
      expect(
        ServerConfig.normalise('https://school.ug/drais'),
        'https://school.ug/drais',
      );
    });

    test('trims whitespace', () {
      expect(ServerConfig.normalise('  drais.pro  '), 'https://drais.pro');
    });

    test('rejects empty and unusable input', () {
      expect(ServerConfig.normalise(''), isNull);
      expect(ServerConfig.normalise('   '), isNull);
      expect(ServerConfig.normalise('ftp://drais.pro'), isNull);
    });
  });

  group('ServerConfig.validateCandidate', () {
    test('accepts an https public address', () {
      expect(
        ServerConfig.validateCandidate('drais.pro', Environment.production),
        isNull,
      );
    });

    test('accepts plain http on a private network', () {
      // Cleartext never leaves the building, and the desktop build serves
      // http://0.0.0.0:3210 exactly as `next start` does.
      expect(
        ServerConfig.validateCandidate(
          '192.168.1.50:3210',
          Environment.production,
        ),
        isNull,
      );
      expect(
        ServerConfig.validateCandidate(
          'http://10.0.1.7:3210',
          Environment.production,
        ),
        isNull,
      );
    });

    test('rejects plain http to a public host', () {
      // The session cookie is a seven-day bearer credential; it must not
      // cross the internet unencrypted.
      final String? problem = ServerConfig.validateCandidate(
        'http://drais.pro',
        Environment.production,
      );

      expect(problem, isNotNull);
      expect(problem, contains('https'));
    });

    test('rejects addresses pointing at the device itself', () {
      // Nothing on the handset serves DRAIS — there is no embedded server.
      for (final String host in <String>[
        'http://localhost:3000',
        'http://127.0.0.1:3000',
        'http://10.0.2.2:3000',
      ]) {
        expect(
          ServerConfig.validateCandidate(host, Environment.production),
          isNotNull,
          reason: '$host should be rejected',
        );
      }
    });

    test('rejects nonsense with an actionable message', () {
      final String? problem = ServerConfig.validateCandidate(
        'not a url at all!!',
        Environment.development,
      );

      expect(problem, isNotNull);
      expect(problem, contains('server address'));
    });
  });

  group('ServerConfig properties', () {
    test('identifies LAN and secure addresses', () {
      const ServerConfig lan = ServerConfig(
        baseUrl: 'http://192.168.1.50:3210',
        origin: ServerOrigin.userConfigured,
      );
      const ServerConfig hosted = ServerConfig(
        baseUrl: 'https://app.drais.pro',
        origin: ServerOrigin.buildDefault,
      );

      expect(lan.isLanAddress, isTrue);
      expect(lan.isSecure, isFalse);
      expect(lan.displayHost, '192.168.1.50:3210');

      expect(hosted.isLanAddress, isFalse);
      expect(hosted.isSecure, isTrue);
      expect(hosted.displayHost, 'app.drais.pro');
    });
  });
}
