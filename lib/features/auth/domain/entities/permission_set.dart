/// The set of permission codes granted to the signed-in user.
///
/// ## The wildcard rules are the server's, reproduced exactly
///
/// LongTerm's `expandPermissionChain()` (`src/lib/rbac/catalog.ts`, used by
/// `userCan()`) grants a request for `academics.results.update` if the user
/// holds **any** of:
///
/// * the exact code — `academics.results.update`
/// * any prefix wildcard — `academics.results.*`, `academics.*`
/// * the universal grant — `*`
///
/// [allows] implements the same chain. Getting it wrong in either direction
/// causes a distinct, unpleasant bug: too strict and the UI hides a button the
/// server would have honoured; too lenient and the user taps a button that
/// fails with 403. The second is worse, and both are avoidable by matching the
/// server exactly.
///
/// ## This is presentation logic, never enforcement
///
/// Permissions are checked here to decide what to *draw*. Authorization is the
/// server's job — `requirePermission()` runs on every protected route, and a
/// tampered client changes nothing. Nothing in the app may treat a local
/// permission check as a security boundary.
class PermissionSet {
  /// Creates a permission set from raw codes.
  PermissionSet(Iterable<String> codes)
    : _codes = Set<String>.unmodifiable(
        codes
            .map((String c) => c.trim().toLowerCase())
            .where((String c) => c.isNotEmpty),
      );

  /// An empty set — grants nothing.
  static final PermissionSet empty = PermissionSet(const <String>[]);

  /// The universal grant the backend returns for super-admins.
  static const String universal = '*';

  final Set<String> _codes;

  /// Every granted code, lowercased.
  Set<String> get codes => _codes;

  /// Whether the universal grant is held.
  bool get hasUniversalGrant => _codes.contains(universal);

  /// Whether nothing is granted.
  bool get isEmpty => _codes.isEmpty;

  /// Whether [code] is granted, honouring exact matches, prefix wildcards and
  /// the universal grant.
  bool allows(String code) {
    final String needle = code.trim().toLowerCase();
    if (needle.isEmpty) return false;
    if (hasUniversalGrant) return true;
    if (_codes.contains(needle)) return true;

    // Walk the dotted chain outward: a.b.c → a.b.* → a.*
    final List<String> segments = needle.split('.');
    for (int i = segments.length - 1; i > 0; i--) {
      if (_codes.contains('${segments.take(i).join('.')}.*')) return true;
    }
    return false;
  }

  /// The full chain of codes that would satisfy a request for [code].
  ///
  /// The client-side twin of `expandPermissionChain()`. Exposed for
  /// diagnostics — showing which grant an engineer is missing is far more
  /// useful than "permission denied".
  static List<String> expandChain(String code) {
    final String needle = code.trim().toLowerCase();
    if (needle.isEmpty) return const <String>[];

    final List<String> chain = <String>[needle];
    final List<String> segments = needle.split('.');
    for (int i = segments.length - 1; i > 0; i--) {
      chain.add('${segments.take(i).join('.')}.*');
    }
    chain.add(universal);
    return chain;
  }

  @override
  String toString() => hasUniversalGrant
      ? 'PermissionSet(*)'
      : 'PermissionSet(${_codes.length} codes)';
}
