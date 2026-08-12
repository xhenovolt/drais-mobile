/// Dependency injection for the whole application.
///
/// ## Why Riverpod is the container
///
/// Riverpod is both the state manager and the injector, so there is one
/// object graph rather than two that must agree. Every dependency is declared,
/// overridable in tests, and disposed with its scope. See
/// `docs/adr/M0001-riverpod-as-state-and-di.md`.
///
/// ## Why the two `throw UnimplementedError` providers
///
/// [sharedPreferencesProvider] and [appConfigProvider] are resolved during
/// bootstrap, before `runApp`, and injected as overrides on `ProviderScope`.
/// Throwing when unoverridden is deliberate: it converts "someone forgot to
/// bootstrap" from a subtle empty-storage bug into an immediate, obvious
/// crash at startup. This is the documented Riverpod idiom for values that
/// require async initialisation.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:drais/app/theme/appearance.dart';
import 'package:drais/app/theme/appearance_controller.dart';
import 'package:drais/core/config/app_config.dart';
import 'package:drais/core/config/data_mode.dart';
import 'package:drais/core/database/drais_database.dart';
import 'package:drais/features/attendance/application/attendance_log_controller.dart';
import 'package:drais/features/attendance/data/direct/attendance_direct_repository.dart';
import 'package:drais/features/attendance/domain/repositories/attendance_repository.dart';
import 'package:drais/features/setup/data/setup_direct_repository.dart';
import 'package:drais/features/students/data/students_direct_repository.dart';
import 'package:drais/features/timehealth/data/time_health_direct_repository.dart';
import 'package:drais/core/error/failure.dart';
import 'package:drais/core/error/result.dart';
import 'package:drais/features/auth/data/direct/auth_direct_repository.dart';
import 'package:drais/core/error/api_error_code.dart';
import 'package:drais/core/logging/app_logger.dart';
import 'package:drais/core/network/api_client.dart';
import 'package:drais/core/network/network_info.dart';
import 'package:drais/core/storage/cache_store.dart';
import 'package:drais/core/storage/cookie_store.dart';
import 'package:drais/core/storage/preferences_store.dart';
import 'package:drais/core/storage/secure_store.dart';
import 'package:drais/features/auth/application/auth_controller.dart';
import 'package:drais/features/auth/application/auth_state.dart';
import 'package:drais/features/auth/data/datasources/auth_remote_data_source.dart';
import 'package:drais/features/auth/data/repositories/auth_repository_impl.dart';
import 'package:drais/features/auth/domain/entities/auth_user.dart';
import 'package:drais/features/auth/domain/repositories/auth_repository.dart';
import 'package:drais/features/server/application/server_controller.dart';
import 'package:drais/features/server/data/server_probe.dart';
import 'package:drais/core/config/server_config.dart';

// ─────────────────────────────────────────────────────────────────────────
// Bootstrap-injected
// ─────────────────────────────────────────────────────────────────────────

/// The active build configuration. Overridden in `bootstrap()`.
final Provider<AppConfig> appConfigProvider = Provider<AppConfig>(
  (Ref ref) => throw UnimplementedError(
    'appConfigProvider must be overridden in bootstrap().',
  ),
);

/// TiDB settings for direct mode, or null when this installation uses a
/// DRAIS server. Overridden in `bootstrap()`.
final Provider<DirectDbConfig?> directDbConfigProvider =
    Provider<DirectDbConfig?>((Ref ref) => null);

/// How this installation reaches DRAIS data.
///
/// Derived, never stored: direct mode exists exactly when a `drais.env` was
/// found at startup. There is no setting to get out of step with reality.
final Provider<DataMode> dataModeProvider = Provider<DataMode>(
  (Ref ref) => ref.watch(directDbConfigProvider) == null
      ? DataMode.api
      : DataMode.direct,
);

/// The in-process TiDB connection, in direct mode only.
final Provider<DraisDatabase?> draisDatabaseProvider = Provider<DraisDatabase?>(
  (Ref ref) {
    final DirectDbConfig? config = ref.watch(directDbConfigProvider);
    if (config == null) return null;

    final DraisDatabase db = DraisDatabase.open(
      config,
      ref.watch(loggerProvider),
    );
    ref.onDispose(db.close);
    return db;
  },
);

/// The opened preference store. Overridden in `bootstrap()`.
final Provider<SharedPreferences> sharedPreferencesProvider =
    Provider<SharedPreferences>(
      (Ref ref) => throw UnimplementedError(
        'sharedPreferencesProvider must be overridden in bootstrap().',
      ),
    );

// ─────────────────────────────────────────────────────────────────────────
// Cross-cutting
// ─────────────────────────────────────────────────────────────────────────

/// The root logger. Feature code takes a child of this, never a new instance,
/// so every line carries a source path.
final Provider<AppLogger> loggerProvider = Provider<AppLogger>(
  (Ref ref) =>
      AppLogger('DRAIS', environment: ref.watch(appConfigProvider).environment),
);

/// Connectivity monitor. Started during bootstrap and disposed with the scope.
final Provider<NetworkInfo> networkInfoProvider = Provider<NetworkInfo>((
  Ref ref,
) {
  final NetworkInfo info = NetworkInfo(logger: ref.watch(loggerProvider))
    ..start();
  ref.onDispose(() => info.dispose());
  return info;
});

/// Whether the device currently has a network path. Drives the offline banner.
final StreamProvider<bool> connectivityProvider = StreamProvider<bool>(
  (Ref ref) => ref.watch(networkInfoProvider).onConnectivityChanged,
);

// ─────────────────────────────────────────────────────────────────────────
// Storage
// ─────────────────────────────────────────────────────────────────────────

/// Keystore-backed storage for credential-grade values.
final Provider<SecureStore> secureStoreProvider = Provider<SecureStore>(
  (Ref ref) => SecureStore(logger: ref.watch(loggerProvider)),
);

/// The persistent session cookie jar.
final Provider<CookieStore> cookieStoreProvider = Provider<CookieStore>(
  (Ref ref) => CookieStore(
    secureStore: ref.watch(secureStoreProvider),
    logger: ref.watch(loggerProvider),
  ),
);

/// Non-sensitive device preferences.
final Provider<PreferencesStore> preferencesStoreProvider =
    Provider<PreferencesStore>(
      (Ref ref) => PreferencesStore(
        preferences: ref.watch(sharedPreferencesProvider),
        logger: ref.watch(loggerProvider),
      ),
    );

/// Offline read cache.
final Provider<CacheStore> cacheStoreProvider = Provider<CacheStore>(
  (Ref ref) => CacheStore(
    preferences: ref.watch(sharedPreferencesProvider),
    logger: ref.watch(loggerProvider),
  ),
);

/// How DRAIS looks. Device-level and applied immediately.
final StateNotifierProvider<AppearanceController, AppearanceSettings>
appearanceProvider =
    StateNotifierProvider<AppearanceController, AppearanceSettings>(
      (Ref ref) => AppearanceController(
        preferences: ref.watch(preferencesStoreProvider),
        logger: ref.watch(loggerProvider),
      ),
    );

/// Whether the welcome screen has been accepted on this device.
///
/// Read through a provider rather than the store directly so the router can be
/// invalidated when it changes; the value itself is a plain synchronous read.
final Provider<bool> welcomeSeenProvider = Provider<bool>(
  (Ref ref) => ref.watch(preferencesStoreProvider).welcomeSeen,
);

// ─────────────────────────────────────────────────────────────────────────
// Server selection
// ─────────────────────────────────────────────────────────────────────────

/// Which DRAIS server this installation talks to.
final StateNotifierProvider<ServerController, ServerConfig?>
serverControllerProvider =
    StateNotifierProvider<ServerController, ServerConfig?>(
      (Ref ref) => ServerController(
        preferences: ref.watch(preferencesStoreProvider),
        config: ref.watch(appConfigProvider),
        logger: ref.watch(loggerProvider),
      ),
    );

/// Tests a candidate server address before it is saved.
final Provider<ServerProbe> serverProbeProvider = Provider<ServerProbe>((
  Ref ref,
) {
  final ServerProbe probe = ServerProbe(logger: ref.watch(loggerProvider));
  ref.onDispose(probe.close);
  return probe;
});

// ─────────────────────────────────────────────────────────────────────────
// Network
// ─────────────────────────────────────────────────────────────────────────

/// The single HTTP client. No feature may construct its own.
///
/// The session-invalidated callback reaches back into [authControllerProvider],
/// which itself depends on this client. That cycle is resolved by `ref.read`
/// *inside* the callback: by the time the server rejects a session, both
/// objects exist. Using `ref.watch` here instead would deadlock the graph at
/// construction.
final Provider<ApiClient> apiClientProvider = Provider<ApiClient>((Ref ref) {
  // Rebuilt whenever the server changes, so repointing the app takes effect
  // immediately and no request can be left addressed to the old server.
  // Empty when no server is configured; the router prevents any data screen
  // being reached in that state, so no request is ever made with it.
  final ServerConfig? server = ref.watch(serverControllerProvider);

  final ApiClient client = ApiClient(
    config: ref.watch(appConfigProvider),
    baseUrl: server?.baseUrl ?? '',
    cookieStore: ref.watch(cookieStoreProvider),
    networkInfo: ref.watch(networkInfoProvider),
    cacheStore: ref.watch(cacheStoreProvider),
    logger: ref.watch(loggerProvider),
    onSessionInvalidated: (ApiErrorCode code) async {
      await ref
          .read(authControllerProvider.notifier)
          .handleSessionInvalidated(code);
    },
  );
  ref.onDispose(client.close);
  return client;
});

// ─────────────────────────────────────────────────────────────────────────
// Auth feature
// ─────────────────────────────────────────────────────────────────────────

/// Typed binding to `/api/auth/*`.
final Provider<AuthRemoteDataSource> authRemoteDataSourceProvider =
    Provider<AuthRemoteDataSource>(
      (Ref ref) => AuthRemoteDataSource(ref.watch(apiClientProvider)),
    );

/// The authentication repository.
///
/// Typed as the domain interface, not the implementation, so a test can
/// override it with a fake without the application layer noticing.
final Provider<AuthRepository> authRepositoryProvider =
    Provider<AuthRepository>((Ref ref) {
      final DraisDatabase? database = ref.watch(draisDatabaseProvider);

      // Direct mode: the app is its own backend, talking to TiDB in-process.
      // Same domain interface, so nothing above data/ changes.
      if (database != null) {
        return AuthDirectRepository(
          database: database,
          secureStore: ref.watch(secureStoreProvider),
          preferences: ref.watch(preferencesStoreProvider),
          cacheStore: ref.watch(cacheStoreProvider),
          logger: ref.watch(loggerProvider),
        );
      }

      return AuthRepositoryImpl(
        remote: ref.watch(authRemoteDataSourceProvider),
        cookieStore: ref.watch(cookieStoreProvider),
        preferences: ref.watch(preferencesStoreProvider),
        cacheStore: ref.watch(cacheStoreProvider),
        logger: ref.watch(loggerProvider),
      );
    });

/// Application-wide authentication state.
final StateNotifierProvider<AuthController, AuthState>
authControllerProvider = StateNotifierProvider<AuthController, AuthState>(
  (Ref ref) => AuthController(
    repository: ref.watch(authRepositoryProvider),
    logger: ref.watch(loggerProvider),
    // Re-arm the transport's dead-session guard so the next expiry is caught.
    onSignedIn: () => ref.read(apiClientProvider).resetSessionGuard(),
  ),
);

// ─────────────────────────────────────────────────────────────────────────
// Attendance
// ─────────────────────────────────────────────────────────────────────────

/// Reads the attendance log.
///
/// Direct mode only for now: the API-mode implementation needs `/api/attendance`
/// DTOs, which is the next piece of work. Throwing rather than returning a
/// silently empty repository means the gap is impossible to miss.
final Provider<AttendanceRepository>
attendanceRepositoryProvider = Provider<AttendanceRepository>((Ref ref) {
  final DraisDatabase? database = ref.watch(draisDatabaseProvider);
  final AuthUser? user = ref.watch(currentUserProvider);

  if (database == null) {
    throw UnimplementedError(
      'Attendance over the API is not implemented yet — run in direct mode, '
      'or implement AttendanceApiRepository.',
    );
  }
  if (user?.schoolId == null) {
    throw StateError('Attendance requires a signed-in user with a school.');
  }

  return AttendanceDirectRepository(
    database: database,
    // The trusted school id, from the validated session — never from a screen.
    schoolId: user!.schoolId!,
    logger: ref.watch(loggerProvider),
  );
});

/// State of the attendance log screen.
final StateNotifierProvider<AttendanceLogController, AttendanceLogState>
attendanceLogControllerProvider =
    StateNotifierProvider<AttendanceLogController, AttendanceLogState>(
      (Ref ref) =>
          AttendanceLogController(ref.watch(attendanceRepositoryProvider)),
    );

/// Reads the learner roster. Direct mode only, like attendance.
final Provider<StudentsDirectRepository> studentsRepositoryProvider =
    Provider<StudentsDirectRepository>((Ref ref) {
      final DraisDatabase? database = ref.watch(draisDatabaseProvider);
      final AuthUser? user = ref.watch(currentUserProvider);

      if (database == null) {
        throw UnimplementedError(
          'Students over the API is not implemented yet — run in direct mode.',
        );
      }
      if (user?.schoolId == null) {
        throw StateError('The roster requires a signed-in user with a school.');
      }

      return StudentsDirectRepository(
        database: database,
        schoolId: user!.schoolId!,
      );
    });

/// Writes the minimum school configuration. Direct mode only.
final Provider<SetupDirectRepository> setupRepositoryProvider =
    Provider<SetupDirectRepository>((Ref ref) {
      final DraisDatabase? database = ref.watch(draisDatabaseProvider);
      final AuthUser? user = ref.watch(currentUserProvider);

      if (database == null) {
        throw UnimplementedError(
          'School setup over the API is not implemented yet — use the web app.',
        );
      }
      if (user?.schoolId == null) {
        throw StateError('Setup requires a signed-in user with a school.');
      }

      return SetupDirectRepository(
        database: database,
        schoolId: user!.schoolId!,
        logger: ref.watch(loggerProvider),
      );
    });

/// What the school has configured so far.
///
/// Judged on rows that exist rather than on `setup_complete`, so a school set
/// up on the web stops being nagged even though the flag was never flipped
/// from here.
final AutoDisposeFutureProvider<SetupStatus> setupStatusProvider =
    FutureProvider.autoDispose<SetupStatus>((Ref ref) async {
      final Result<SetupStatus> result = await ref
          .watch(setupRepositoryProvider)
          .status();
      return result.fold(
        onOk: (SetupStatus status) => status,
        onErr: (Failure failure) => throw failure,
      );
    });

/// Reads device and clock health. Direct mode only.
final Provider<TimeHealthDirectRepository>
timeHealthRepositoryProvider = Provider<TimeHealthDirectRepository>((Ref ref) {
  final DraisDatabase? database = ref.watch(draisDatabaseProvider);
  final AuthUser? user = ref.watch(currentUserProvider);

  if (database == null) {
    throw UnimplementedError(
      'Time health over the API is not implemented yet — run in direct mode.',
    );
  }
  if (user?.schoolId == null) {
    throw StateError('Time health requires a signed-in user with a school.');
  }

  return TimeHealthDirectRepository(
    database: database,
    schoolId: user!.schoolId!,
  );
});

/// The signed-in user, or null.
final Provider<AuthUser?> currentUserProvider = Provider<AuthUser?>(
  (Ref ref) => ref.watch(authControllerProvider).user,
);

/// Whether the signed-in user holds a permission code.
///
/// ```dart
/// if (ref.watch(canProvider('finance.payments.create'))) ...
/// ```
///
/// **Presentation only.** This decides what to draw; the server decides what
/// is allowed. Never treat it as a security boundary.
final ProviderFamily<bool, String> canProvider = Provider.family<bool, String>(
  (Ref ref, String code) => ref.watch(authControllerProvider).can(code),
);
