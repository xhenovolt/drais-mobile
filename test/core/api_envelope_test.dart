import 'package:flutter_test/flutter_test.dart';

import 'package:drais/core/error/api_error_code.dart';
import 'package:drais/core/network/api_response.dart';

/// Pins the parser to the three envelope shapes DRAIS LongTerm actually emits.
///
/// Each case below is taken from a real route, named in its comment. If the
/// backend consolidates on one shape these tests should still pass — they
/// assert what the parser tolerates, not what it requires.
void main() {
  group('ApiEnvelope.parse — success shapes', () {
    test('createSuccessResponse: { success, data }', () {
      final ApiEnvelope<Map<String, Object?>> envelope =
          ApiEnvelope.parse<Map<String, Object?>>(<String, Object?>{
            'success': true,
            'data': <String, Object?>{'id': 7},
          }, fromJson: (Object json) => json as Map<String, Object?>);

      expect(envelope.success, isTrue);
      expect(envelope.data?['id'], 7);
    });

    test('ok() shorthand: { success, message, data }', () {
      final ApiEnvelope<Map<String, Object?>> envelope =
          ApiEnvelope.parse<Map<String, Object?>>(<String, Object?>{
            'success': true,
            'message': 'Saved',
            'data': <String, Object?>{'id': 7},
          }, fromJson: (Object json) => json as Map<String, Object?>);

      expect(envelope.message, 'Saved');
      expect(envelope.data?['id'], 7);
    });

    test('flat shape via dataKey: /api/auth/me', () {
      // { success, user, setupComplete } — the payload is not under `data`.
      final ApiEnvelope<Map<String, Object?>> envelope =
          ApiEnvelope.parse<Map<String, Object?>>(
            <String, Object?>{
              'success': true,
              'user': <String, Object?>{'id': 42, 'email': 'a@b.co'},
              'setupComplete': true,
            },
            dataKey: 'user',
            fromJson: (Object json) => json as Map<String, Object?>,
          );

      expect(envelope.data?['id'], 42);
      // Sibling keys stay reachable through the raw body.
      expect(envelope['setupComplete'], isTrue);
    });

    test('a body with no success flag is treated as success', () {
      final ApiEnvelope<void> envelope = ApiEnvelope.parse<void>(
        <String, Object?>{'ok': true},
      );

      expect(envelope.success, isTrue);
    });
  });

  group('ApiEnvelope.parse — failure shapes', () {
    test('structured error: { success:false, error:{ code, message } }', () {
      final ApiEnvelope<void> envelope = ApiEnvelope.parse<void>(
        <String, Object?>{
          'success': false,
          'error': <String, Object?>{
            'code': 'SESSION_EXPIRED',
            'message': 'Your session has expired.',
          },
        },
      );

      expect(envelope.isFailure, isTrue);
      expect(envelope.errorCode, ApiErrorCode.sessionExpired);
      expect(envelope.errorMessage, 'Your session has expired.');
    });

    test('fail() shorthand puts the message at the top level', () {
      final ApiEnvelope<void> envelope = ApiEnvelope.parse<void>(
        <String, Object?>{'success': false, 'message': 'Nope'},
      );

      expect(envelope.isFailure, isTrue);
      expect(envelope.errorMessage, 'Nope');
    });

    test('unknown codes degrade rather than break', () {
      // The backend may ship a code before the app knows it.
      final ApiEnvelope<void> envelope = ApiEnvelope.parse<void>(
        <String, Object?>{
          'success': false,
          'error': <String, Object?>{'code': 'SOMETHING_NEW'},
        },
      );

      expect(envelope.errorCode, ApiErrorCode.unknown);
    });

    test('error.details is preserved for field-level validation', () {
      final ApiEnvelope<void> envelope = ApiEnvelope.parse<void>(
        <String, Object?>{
          'success': false,
          'error': <String, Object?>{
            'code': 'INVALID_INPUT',
            'message': 'Invalid value for email',
            'details': <String, Object?>{'field': 'email'},
          },
        },
      );

      expect(envelope.errorDetails?['field'], 'email');
    });
  });

  group('ApiErrorCode', () {
    test('reauthentication codes are recognised', () {
      expect(ApiErrorCode.sessionExpired.requiresReauthentication, isTrue);
      expect(ApiErrorCode.unauthorized.requiresReauthentication, isTrue);
      expect(ApiErrorCode.notAuthenticated.requiresReauthentication, isTrue);
    });

    test('a wrong password does NOT invalidate a session', () {
      // Critical distinction: treating a failed login as an expired session
      // would trigger a global sign-out on every mistyped password.
      expect(ApiErrorCode.invalidCredentials.requiresReauthentication, isFalse);
    });

    test('a lapsed subscription is not a session problem', () {
      expect(
        ApiErrorCode.subscriptionExpired.requiresReauthentication,
        isFalse,
      );
      expect(ApiErrorCode.subscriptionExpired.isRetryable, isFalse);
    });

    test('wire values round-trip case-insensitively', () {
      expect(ApiErrorCode.fromWire('forbidden'), ApiErrorCode.forbidden);
      expect(ApiErrorCode.fromWire(null), ApiErrorCode.unknown);
      expect(ApiErrorCode.fromWire(''), ApiErrorCode.unknown);
    });
  });
}
