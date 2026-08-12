import 'package:flutter_test/flutter_test.dart';

import 'package:drais/features/auth/domain/entities/permission_set.dart';

/// These tests pin the client's permission semantics to the server's.
///
/// `expandPermissionChain()` in `src/lib/rbac/catalog.ts` defines the rules;
/// if these ever disagree, the UI will either hide functionality the user has
/// or offer actions that 403. Both are user-visible bugs, so the cases below
/// mirror the server's behaviour deliberately rather than testing whatever the
/// implementation happens to do.
void main() {
  group('PermissionSet.allows', () {
    test('grants an exact code', () {
      final PermissionSet permissions = PermissionSet(<String>[
        'academics.results.update',
      ]);

      expect(permissions.allows('academics.results.update'), isTrue);
      expect(permissions.allows('academics.results.delete'), isFalse);
    });

    test('grants via an immediate prefix wildcard', () {
      final PermissionSet permissions = PermissionSet(<String>[
        'academics.results.*',
      ]);

      expect(permissions.allows('academics.results.update'), isTrue);
      expect(permissions.allows('academics.results.view'), isTrue);
    });

    test('grants via a distant prefix wildcard', () {
      final PermissionSet permissions = PermissionSet(<String>['academics.*']);

      expect(permissions.allows('academics.results.update'), isTrue);
      expect(permissions.allows('academics.theology.view'), isTrue);
      expect(permissions.allows('finance.payments.create'), isFalse);
    });

    test('grants everything with the universal grant', () {
      // What /api/auth/me returns for a super-admin.
      final PermissionSet permissions = PermissionSet(<String>['*']);

      expect(permissions.hasUniversalGrant, isTrue);
      expect(permissions.allows('anything.at.all'), isTrue);
    });

    test('a wildcard does not grant a sibling branch', () {
      final PermissionSet permissions = PermissionSet(<String>[
        'academics.results.*',
      ]);

      expect(permissions.allows('academics.theology.view'), isFalse);
    });

    test('a wildcard does not grant its own parent segment', () {
      // Holding `academics.results.*` says nothing about `academics` itself.
      final PermissionSet permissions = PermissionSet(<String>[
        'academics.results.*',
      ]);

      expect(permissions.allows('academics'), isFalse);
    });

    test('is case-insensitive on both sides', () {
      final PermissionSet permissions = PermissionSet(<String>[
        'Finance.Payments.Create',
      ]);

      expect(permissions.allows('finance.payments.create'), isTrue);
      expect(permissions.allows('FINANCE.PAYMENTS.CREATE'), isTrue);
    });

    test('an empty set grants nothing', () {
      expect(PermissionSet.empty.allows('anything'), isFalse);
      expect(PermissionSet.empty.isEmpty, isTrue);
    });

    test('an empty code is never granted, even with the universal grant', () {
      final PermissionSet permissions = PermissionSet(<String>['*']);

      expect(permissions.allows(''), isFalse);
      expect(permissions.allows('   '), isFalse);
    });
  });

  group('PermissionSet.expandChain', () {
    test('produces the same chain the server checks', () {
      expect(PermissionSet.expandChain('academics.results.update'), <String>[
        'academics.results.update',
        'academics.results.*',
        'academics.*',
        '*',
      ]);
    });

    test('a single segment expands to itself plus the universal grant', () {
      expect(PermissionSet.expandChain('dashboard'), <String>[
        'dashboard',
        '*',
      ]);
    });

    test('an empty code expands to nothing', () {
      expect(PermissionSet.expandChain(''), isEmpty);
    });
  });
}
