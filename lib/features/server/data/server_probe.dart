import 'package:dio/dio.dart';

import 'package:drais/core/config/api_endpoints.dart';
import 'package:drais/core/constants/app_version.dart';
import 'package:drais/core/logging/app_logger.dart';

/// The outcome of testing a candidate server address.
class ProbeResult {
  /// Creates a probe result.
  const ProbeResult({
    required this.reachable,
    required this.isDrais,
    this.databaseConnected,
    this.serverTime,
    this.problem,
    this.technicalDetail,
  });

  /// Whether anything answered at that address.
  final bool reachable;

  /// Whether what answered is recognisably a DRAIS server.
  ///
  /// Distinguished from [reachable] because a wrong address usually *does*
  /// answer — a router admin page, a captive portal, someone else's website.
  /// "Connection successful" against a home router would be worse than useless.
  final bool isDrais;

  /// Whether that DRAIS server can reach its own database.
  ///
  /// `/api/health` reports this. A server that is up but cannot reach TiDB
  /// will accept the connection and then fail every sign-in, so it is worth
  /// saying so now rather than letting the user conclude their password is
  /// wrong.
  final bool? databaseConnected;

  /// The server's clock, if reported.
  ///
  /// Useful in the field: attendance is time-sensitive and several backend
  /// ADRs concern device clock drift, so a visible disagreement between phone
  /// and server is worth surfacing early.
  final DateTime? serverTime;

  /// User-facing explanation when this address cannot be used.
  final String? problem;

  /// Engineer-facing detail for the diagnostics view.
  final String? technicalDetail;

  /// Whether this address is usable.
  bool get isUsable => reachable && isDrais;
}

/// Tests whether a candidate address is a working DRAIS server.
///
/// Uses its own short-lived `Dio` rather than the application's [ApiClient],
/// because the app client is bound to the *configured* server and this runs
/// before there is one. It also carries no cookies deliberately — probing an
/// address the user has not yet trusted must never send them a session.
class ServerProbe {
  /// Creates a probe.
  ServerProbe({required AppLogger logger, Dio? dio})
    : _logger = logger.child('Probe'),
      _dio = dio ?? Dio();

  final Dio _dio;
  final AppLogger _logger;

  /// Kept short. Someone standing in a school office typing an address wants
  /// an answer, not a spinner — and a server that takes 10s to say hello is
  /// not one to connect to.
  static const Duration _timeout = Duration(seconds: 10);

  /// Probes [baseUrl], which must already be normalised.
  Future<ProbeResult> probe(String baseUrl) async {
    _logger.info(
      'Probing candidate server.',
      context: <String, Object?>{'host': Uri.tryParse(baseUrl)?.host},
    );

    try {
      final Response<Object?> response = await _dio.get<Object?>(
        '$baseUrl${ApiEndpoints.health}',
        options: Options(
          sendTimeout: _timeout,
          receiveTimeout: _timeout,
          headers: <String, Object?>{
            'Accept': 'application/json',
            'User-Agent': AppVersion.userAgent,
          },
          // /api/health answers 503 when the database is unreachable, and that
          // body is exactly what we want to read — so no status is an error here.
          validateStatus: (int? _) => true,
        ),
      );

      return _interpret(response);
    } on DioException catch (e) {
      return ProbeResult(
        reachable: false,
        isDrais: false,
        problem: _describeTransportFailure(e),
        technicalDetail: '${e.type.name}: ${e.message}',
      );
    } on Object catch (e) {
      return ProbeResult(
        reachable: false,
        isDrais: false,
        problem: 'Could not reach that address.',
        technicalDetail: e.toString(),
      );
    }
  }

  ProbeResult _interpret(Response<Object?> response) {
    final Object? body = response.data;
    final int status = response.statusCode ?? 0;

    // Something answered, but not JSON — a router page, a captive portal, a
    // static site. Reachable, but not DRAIS.
    if (body is! Map) {
      return ProbeResult(
        reachable: true,
        isDrais: false,
        problem:
            'Something answered at that address, but it is not a DRAIS '
            'server. Check the address with your administrator.',
        technicalDetail: 'HTTP $status, body ${body.runtimeType}',
      );
    }

    final Map<String, Object?> json = body.map(
      (Object? k, Object? v) => MapEntry<String, Object?>('$k', v),
    );

    // /api/health returns { ok, server, db: {connected,...}, env, time }.
    // `server` and `db` together are the fingerprint — a generic health
    // endpoint from some other service will not have both.
    final bool looksLikeDrais =
        json.containsKey('server') && json.containsKey('db');

    if (!looksLikeDrais) {
      return ProbeResult(
        reachable: true,
        isDrais: false,
        problem: 'That address answered, but it does not look like DRAIS.',
        technicalDetail: 'HTTP $status, keys: ${json.keys.join(', ')}',
      );
    }

    final Object? db = json['db'];
    final bool dbConnected = db is Map && (db['connected'] as bool? ?? false);

    final Object? rawTime = json['time'];
    final DateTime? serverTime = rawTime is String
        ? DateTime.tryParse(rawTime)
        : null;

    _logger.info(
      'DRAIS server confirmed.',
      context: <String, Object?>{'status': status, 'db': dbConnected},
    );

    return ProbeResult(
      reachable: true,
      isDrais: true,
      databaseConnected: dbConnected,
      serverTime: serverTime,
      // Usable, but worth warning about — sign-in will fail until the server's
      // database is back.
      problem: dbConnected
          ? null
          : 'This DRAIS server is running but cannot reach its database. '
                'Signing in will not work until that is fixed.',
      technicalDetail: db is Map ? db['error'] as String? : null,
    );
  }

  /// Turns a transport failure into something a school administrator can act on.
  static String _describeTransportFailure(DioException e) => switch (e.type) {
    DioExceptionType.connectionTimeout ||
    DioExceptionType.receiveTimeout ||
    DioExceptionType.sendTimeout ||
    DioExceptionType.transformTimeout =>
      'That address did not respond in time. Check that the server is '
          'running and that this device is on the same network.',
    DioExceptionType.connectionError =>
      'Could not reach that address. Check the spelling, and that this '
          'device has a connection.',
    DioExceptionType.badCertificate =>
      'The security certificate could not be verified. If this is a '
          'school server on your own network, use its address without '
          'https.',
    DioExceptionType.badResponse ||
    DioExceptionType.unknown ||
    DioExceptionType.cancel => 'Could not reach that address.',
  };

  /// Releases the probe's HTTP resources.
  void close() => _dio.close(force: true);
}
