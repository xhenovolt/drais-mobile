import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';

import 'package:drais_server/config/env.dart';
import 'package:drais_server/db/database.dart';
import 'package:drais_server/http/api_response.dart';
import 'package:drais_server/http/middleware.dart';
import 'package:drais_server/routes/auth_routes.dart';

/// DRAIS Server — the Dart implementation of the DRAIS API.
///
/// Phase 1 of the strangler migration: authentication only. Every other route
/// still belongs to the Next.js application, and this service is deliberately
/// deployable beside it rather than in place of it.
///
/// ```bash
/// cd server
/// dart pub get
/// cp .env.example .env      # fill in TIDB_*
/// dart run bin/server.dart
/// ```
///
/// Point the Flutter app at it and sign in. If that works, the migration is
/// viable; if it does not, we have found out for the price of ~1,500 lines
/// rather than 61,000.
Future<void> main(List<String> args) async {
  final ServerEnv env = ServerEnv.load();

  final List<String> problems = env.validate();
  if (problems.isNotEmpty) {
    stderr.writeln('DRAIS Server cannot start:');
    for (final String problem in problems) {
      stderr.writeln('  • $problem');
    }
    stderr.writeln('\nCopy .env.example to .env and fill in the TiDB values.');
    exitCode = 78; // EX_CONFIG
    return;
  }

  stdout.writeln('DRAIS Server starting…');
  stdout.writeln('  config: ${env.safeSummary}');

  final Database db = await Database.connect(env);

  // Prove the database is reachable before accepting traffic. Starting and
  // then failing every request is a worse failure mode than not starting:
  // it looks like an application bug rather than a configuration one.
  final ({bool connected, int? latencyMs, String? error}) health =
      await db.ping();
  if (!health.connected) {
    stderr.writeln('  ✖ Cannot reach TiDB: ${health.error}');
    await db.close();
    exitCode = 69; // EX_UNAVAILABLE
    return;
  }
  stdout.writeln('  ✔ TiDB reachable (${health.latencyMs}ms)');

  final Router api = Router()
    ..get('/api/health', (Request request) => _health(db, env))
    ..mount('/api/auth/', AuthRoutes(db: db, env: env).router.call);

  final Handler handler = const Pipeline()
      .addMiddleware(DraisMiddleware.logging())
      .addMiddleware(DraisMiddleware.errors())
      .addMiddleware(DraisMiddleware.securityHeaders())
      .addHandler(api.call);

  final HttpServer server;
  try {
    server = await shelf_io.serve(handler, env.bindAddress, env.port);
  } on SocketException catch (e) {
    // The common startup failures are "port taken" and "address not
    // assignable", and both have a one-line fix. Dumping a stack trace for
    // either sends the reader looking for a bug that isn't there.
    await db.close();
    stderr.writeln('  ✖ Cannot listen on ${env.bindAddress}:${env.port}');

    if (e.osError?.errorCode == 98) {
      stderr.writeln('');
      stderr.writeln('    Port ${env.port} is already in use — most likely an');
      stderr.writeln('    earlier DRAIS Server that is still running.');
      stderr.writeln('');
      stderr.writeln('    Find it:  ss -lptn \'sport = :${env.port}\'');
      stderr.writeln('    Stop it:  pkill -f "bin/server.dart"');
      stderr.writeln('    Or run on another port:  PORT=8081 dart run bin/server.dart');
    } else {
      stderr.writeln('    ${e.osError?.message ?? e.message}');
    }

    exitCode = 73; // EX_CANTCREAT
    return;
  }

  // Compression is off: response bodies here are small, and enabling it on a
  // cookie-bearing API invites the BREACH class of attack for no real gain.
  server.autoCompress = false;

  stdout.writeln('  ✔ Listening on http://${env.bindAddress}:${env.port}');
  stdout.writeln('');
  stdout.writeln('Point DRAIS Mobile at this address on the connect screen.');
  stdout.writeln('Routes: /api/health, /api/auth/login, /api/auth/me, '
      '/api/auth/logout');

  // Close the pool cleanly so in-flight queries finish and TiDB does not hold
  // half-open connections — they count against the account's connection cap.
  ProcessSignal.sigint.watch().listen((ProcessSignal _) async {
    stdout.writeln('\nShutting down…');
    await server.close(force: false);
    await db.close();
    exit(0);
  });
}

/// `GET /api/health` — the shape the Flutter client's `ServerProbe` expects.
///
/// `server` and `db` together are the fingerprint the client uses to decide
/// that an address is genuinely DRAIS and not a router admin page. Both keys
/// must be present, so the probe is answered honestly by either backend.
Future<Response> _health(Database db, ServerEnv env) async {
  final ({bool connected, int? latencyMs, String? error}) result =
      await db.ping();

  return ApiResponse.ok(
    <String, Object?>{
      'ok': result.connected,
      'server': true,
      'implementation': 'dart',
      'db': <String, Object?>{
        'connected': result.connected,
        if (result.latencyMs != null) 'latency_ms': result.latencyMs,
        if (result.error != null) 'error': result.error,
      },
      // Whether each variable is *set*, never its value — matching the
      // platform's health endpoint, which masks the same way.
      'env': <String, Object?>{
        'tidb_host_set': env.tidbHost != null,
        'tidb_user_set': env.tidbUser != null,
        'tidb_password_set': env.tidbPassword != null,
        'tidb_db': env.tidbDatabase,
        'node_env': env.isProduction ? 'production' : 'development',
      },
      'time': DateTime.now().toIso8601String(),
    },
    status: result.connected ? 200 : 503,
  );
}
