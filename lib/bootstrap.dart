import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:drais/app/app.dart';
import 'package:drais/core/config/app_config.dart';
import 'package:drais/core/config/data_mode.dart';
import 'package:drais/core/constants/app_version.dart';
import 'package:drais/core/di/providers.dart';
import 'package:drais/core/logging/app_logger.dart';

/// Starts the application.
///
/// ## Order matters
///
/// 1. Bind the Flutter engine.
/// 2. Resolve configuration and **validate it**.
/// 3. Open storage, which is async and must exist before any provider reads it.
/// 4. Install error handlers, so a crash during startup is still logged.
/// 5. Run the app with the resolved values injected as provider overrides.
///
/// Configuration is validated before anything else can use it. A release build
/// pointed at a developer's laptop, or one that would send the session cookie
/// over cleartext, refuses to start — a loud failure at launch is far cheaper
/// than a quiet one in a school.
Future<void> bootstrap() async {
  WidgetsFlutterBinding.ensureInitialized();

  final AppConfig config = AppConfig.fromEnvironment();
  final AppLogger logger = AppLogger('DRAIS', environment: config.environment);

  final List<String> problems = config.validate();
  if (problems.isNotEmpty) {
    logger.error(
      'Invalid configuration.',
      context: <String, Object?>{'problems': problems},
    );
    if (config.environment.isProduction) {
      // Refuse to run rather than misbehave silently.
      runApp(_ConfigurationErrorApp(problems: problems));
      return;
    }
    // Outside production, warn loudly and continue — a developer pointing at
    // a laptop over http is doing so on purpose.
    logger.warn('Continuing despite configuration problems (non-production).');
  }

  logger.info(
    'Starting DRAIS Mobile.',
    context: <String, Object?>{
      'version': AppVersion.fullVersion,
      'environment': config.environment.id,
      'defaultApi': config.defaultApiBaseUrl ?? '(unset — will ask)',
      'verifiedAgainstLongTerm': AppVersion.verifiedAgainstLongTerm,
    },
  );

  final SharedPreferences preferences = await SharedPreferences.getInstance();

  // Direct mode is opt-in per installation: it exists only when an operator
  // has placed a drais.env alongside the app. Absence is the normal case and
  // means the app talks to a DRAIS server instead.
  final DirectDbConfig? directDb = await DirectDbConfig.load(logger);
  if (directDb != null) {
    logger.info(
      'Direct database mode active — no DRAIS server required.',
      context: <String, Object?>{'database': directDb.database},
    );
  }

  _installErrorHandlers(logger);

  runApp(
    ProviderScope(
      overrides: <Override>[
        appConfigProvider.overrideWithValue(config),
        sharedPreferencesProvider.overrideWithValue(preferences),
        directDbConfigProvider.overrideWithValue(directDb),
      ],
      child: const DraisApp(),
    ),
  );
}

/// Routes framework and isolate errors into the structured logger.
///
/// Without this, a widget-build exception goes to the console and vanishes,
/// and an async error outside the framework is lost entirely. Both are exactly
/// the "silent failure" the platform's error-handling standard forbids.
void _installErrorHandlers(AppLogger logger) {
  final FlutterExceptionHandler? previous = FlutterError.onError;

  FlutterError.onError = (FlutterErrorDetails details) {
    logger.error(
      'Flutter framework error.',
      error: details.exception,
      stackTrace: details.stack,
      context: <String, Object?>{
        'library': details.library,
        'context': details.context?.toDescription(),
      },
    );
    previous?.call(details);
  };

  // Errors raised outside the framework's zone — a failed future in a
  // repository, for instance — surface here.
  PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
    logger.error('Uncaught platform error.', error: error, stackTrace: stack);
    // Returning true marks it handled: the app keeps running. A crash on an
    // unhandled background error would lose the user's work for something
    // they cannot act on.
    return true;
  };
}

/// The only screen a misconfigured production build will show.
class _ConfigurationErrorApp extends StatelessWidget {
  const _ConfigurationErrorApp({required this.problems});

  final List<String> problems;

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    home: Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Icon(Icons.settings_suggest_outlined, size: 48),
              const SizedBox(height: 16),
              const Text(
                'DRAIS cannot start',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              const Text(
                'This build is misconfigured. Please contact your '
                'administrator or reinstall the correct version.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              for (final String problem in problems)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Text(
                    '• $problem',
                    style: const TextStyle(fontSize: 12),
                    textAlign: TextAlign.center,
                  ),
                ),
            ],
          ),
        ),
      ),
    ),
  );
}
