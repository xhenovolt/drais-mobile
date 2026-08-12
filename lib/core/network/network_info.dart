import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';

import 'package:drais/core/logging/app_logger.dart';

/// Reports whether the device has a usable network path.
///
/// ## What this can and cannot tell you
///
/// `connectivity_plus` reports the **radio state**, not reachability. A device
/// joined to a school Wi-Fi network with no upstream link, or sitting behind a
/// captive portal, reports `wifi` while every request fails. So:
///
/// * `isConnected == false` is **conclusive** — do not attempt the request.
/// * `isConnected == true` is a **hint** — the request may still fail.
///
/// Treating it as anything stronger produces the classic bug where the app
/// insists it is online while nothing loads. Reachability is therefore proven
/// only by a successful call to `/api/health`, which [probeReachability]
/// exposes for the diagnostics screen.
class NetworkInfo {
  /// Creates a network monitor.
  NetworkInfo({required AppLogger logger, Connectivity? connectivity})
    : _connectivity = connectivity ?? Connectivity(),
      _logger = logger.child('Network');

  final Connectivity _connectivity;
  final AppLogger _logger;

  StreamSubscription<List<ConnectivityResult>>? _subscription;
  final StreamController<bool> _controller = StreamController<bool>.broadcast();

  bool _lastKnown = true;

  /// Whether the device currently has a network path.
  Future<bool> get isConnected async {
    try {
      final List<ConnectivityResult> results = await _connectivity
          .checkConnectivity();
      final bool connected = _isConnectedResult(results);
      _lastKnown = connected;
      return connected;
    } on Object catch (e) {
      // If the platform channel fails, assume connected: refusing to make a
      // request that would have worked is worse than attempting one that
      // fails with a clear NetworkFailure.
      _logger.warn(
        'Connectivity check failed; assuming online.',
        context: <String, Object?>{'reason': e.runtimeType},
      );
      return true;
    }
  }

  /// The most recent known state, without awaiting the platform channel.
  /// Suitable for synchronous UI decisions such as an offline banner.
  bool get lastKnownConnected => _lastKnown;

  /// Emits on every connectivity transition.
  Stream<bool> get onConnectivityChanged => _controller.stream;

  /// Begins listening for connectivity changes. Called once during bootstrap.
  void start() {
    _subscription ??= _connectivity.onConnectivityChanged.listen(
      (List<ConnectivityResult> results) {
        final bool connected = _isConnectedResult(results);
        if (connected == _lastKnown) return;
        _lastKnown = connected;
        _logger.info(
          connected ? 'Connectivity restored.' : 'Connectivity lost.',
          context: <String, Object?>{
            'transports': results
                .map((ConnectivityResult r) => r.name)
                .toList(),
          },
        );
        _controller.add(connected);
      },
      onError: (Object e) => _logger.warn(
        'Connectivity stream error.',
        context: <String, Object?>{'reason': e.runtimeType},
      ),
    );
  }

  /// Stops listening and releases resources.
  Future<void> dispose() async {
    await _subscription?.cancel();
    _subscription = null;
    await _controller.close();
  }

  static bool _isConnectedResult(List<ConnectivityResult> results) =>
      results.isNotEmpty &&
      !results.every((ConnectivityResult r) => r == ConnectivityResult.none);
}
