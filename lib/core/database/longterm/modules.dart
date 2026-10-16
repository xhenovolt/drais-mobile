/// The per-school module switch — `checkModule()` / `isModuleEnabled()` in
/// `src/lib/auth/requireModule.ts` and `src/lib/school-modules.ts` (DRAIS
/// LongTerm).
///
/// Opt-out, as on the platform: a module is on unless a `school_modules`
/// row explicitly disables it. Super-admins are not exempt — a module gate
/// models what the school bought, not who is asking.
library;

import 'package:drais/core/database/drais_database.dart';
import 'package:drais/core/error/api_error_code.dart';
import 'package:drais/core/error/failure.dart';

/// The refusal `checkModule()` returns, or null when [code] is enabled.
///
/// The platform answers 403 with code `MODULE_DISABLED`; the app has no such
/// code, so it is reported as `FORBIDDEN` with the platform's message.
Future<Failure?> checkModule(DraisDatabase db, int schoolId, String code) async {
  final Row? row = await db.queryOne(
    'SELECT 1 AS x FROM school_modules '
    'WHERE school_id = ? AND module_code = ? AND is_enabled = 0 LIMIT 1',
    <Object?>[schoolId, code],
  );
  return row == null
      ? null
      : AuthorizationFailure(
          code: ApiErrorCode.forbidden,
          message: "Module '$code' is not enabled for this school",
        );
}
