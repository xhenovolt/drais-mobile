import 'package:drais/bootstrap.dart';

/// DRAIS Mobile — the Flutter presentation layer of the DRAIS platform.
///
/// The entry point is intentionally empty. Everything that happens at startup
/// lives in `bootstrap()`, which is an ordinary async function and therefore
/// testable; `main` exists only to satisfy the Dart runtime.
///
/// Build with an environment selected:
///
/// ```bash
/// flutter run  --dart-define-from-file=env/development.json
/// flutter build apk --release --dart-define-from-file=env/production.json
/// ```
///
/// See `docs/ENVIRONMENTS.md` for the full variable list and
/// `docs/ARCHITECTURE.md` for how the layers fit together.
Future<void> main() => bootstrap();
