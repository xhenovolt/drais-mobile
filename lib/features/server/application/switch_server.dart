import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:drais/core/di/providers.dart';

/// Disconnects the device from its current DRAIS server.
///
/// ## Why this is one function and not two calls at the call site
///
/// The order is load-bearing and easy to get wrong:
///
/// 1. **Sign out first**, while the server address is still known. `POST
///    /api/auth/logout` has to reach the server that issued the session in
///    order to invalidate it. Clearing the address first would strand a live
///    session row on the old server for its full seven days.
/// 2. **Then clear the server**, which drops the stored address and sends the
///    router back to the connect screen.
///
/// A session cookie is meaningless to a different server, so carrying one
/// across would produce a confusing run of 401s instead of a clean re-login.
/// `AuthRepositoryImpl.logout` also clears the response cache, so no tenant
/// data survives the switch — which matters, because the next server may be a
/// different school entirely.
///
/// Used when moving between the hosted DRAIS and a school's own server, and
/// when a deployment moves.
Future<void> switchServer(WidgetRef ref) async {
  await ref.read(authControllerProvider.notifier).logout();
  await ref.read(serverControllerProvider.notifier).clearServer();
}
