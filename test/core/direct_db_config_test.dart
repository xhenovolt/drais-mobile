import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:drais/core/config/data_mode.dart';

/// Direct mode is switched on by the presence of a `drais.env`, so a malformed
/// file is a silent fallback to server mode — the app boots and then asks for
/// an address nobody expected to be asked for.
///
/// The last group validates the file actually on this machine, so a bad edit
/// fails a test rather than a launch.
void main() {
  group('DirectDbConfig.parse', () {
    test('reads a complete configuration', () {
      final DirectDbConfig? config = DirectDbConfig.parse('''
TIDB_HOST=gateway01.eu-central-1.prod.aws.tidbcloud.com
TIDB_PORT=4000
TIDB_USER=abc.root
TIDB_PASSWORD=secret
TIDB_DB=drais
''');

      expect(config, isNotNull);
      expect(config!.host, 'gateway01.eu-central-1.prod.aws.tidbcloud.com');
      expect(config.port, 4000);
      expect(config.user, 'abc.root');
      expect(config.password, 'secret');
      expect(config.database, 'drais');
    });

    test('ignores comments and blank lines', () {
      final DirectDbConfig? config = DirectDbConfig.parse('''
# a comment

TIDB_HOST=h
   # indented comment
TIDB_USER=u
TIDB_PASSWORD=p
''');

      expect(config, isNotNull);
      expect(config!.host, 'h');
    });

    test('strips surrounding quotes', () {
      final DirectDbConfig? config = DirectDbConfig.parse(
        'TIDB_HOST="h"\nTIDB_USER=\'u\'\nTIDB_PASSWORD="p@ss=word"',
      );

      expect(config!.host, 'h');
      expect(config.user, 'u');
      // Only the outer quotes go; a '=' inside the value survives.
      expect(config.password, 'p@ss=word');
    });

    test('defaults the port and database', () {
      final DirectDbConfig? config = DirectDbConfig.parse(
        'TIDB_HOST=h\nTIDB_USER=u\nTIDB_PASSWORD=p',
      );

      expect(config!.port, 4000); // TiDB, not MySQL's 3306
      expect(config.database, 'drais');
    });

    test('returns null when a required value is missing', () {
      // Absence must mean "use a server", never a half-configured connection.
      expect(DirectDbConfig.parse('TIDB_HOST=h\nTIDB_USER=u'), isNull);
      expect(DirectDbConfig.parse('TIDB_HOST=h\nTIDB_PASSWORD=p'), isNull);
      expect(DirectDbConfig.parse(''), isNull);
      expect(DirectDbConfig.parse('# nothing but a comment'), isNull);
    });

    test('never exposes the password in toString', () {
      final DirectDbConfig config = DirectDbConfig.parse(
        'TIDB_HOST=h\nTIDB_USER=u\nTIDB_PASSWORD=hunter2',
      )!;

      expect(config.toString(), isNot(contains('hunter2')));
    });
  });

  group('the drais.env on this machine', () {
    final File file = File('drais.env');

    test(
      'is well-formed and would switch the app into direct mode',
      () {
        final DirectDbConfig? config = DirectDbConfig.parse(
          file.readAsStringSync(),
        );

        expect(
          config,
          isNotNull,
          reason:
              'drais.env exists but is missing TIDB_HOST/USER/PASSWORD, '
              'so the app would silently fall back to server mode.',
        );
        expect(config!.host, isNotEmpty);
        expect(config.port, greaterThan(0));
      },
      // Skipped where no file is present — that is the normal case for a
      // checkout that uses a DRAIS server.
      skip: file.existsSync() ? false : 'no drais.env on this machine',
    );
  });
}
