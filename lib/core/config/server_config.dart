import 'package:drais/core/config/environment.dart';

/// The DRAIS server this installation talks to, resolved at **runtime**.
///
/// ## Why this is not a build-time constant
///
/// DRAIS is deployed two ways, and both are legitimate:
///
/// * **Hosted** — the school uses Xhenvolt's deployment over HTTPS.
/// * **Local** — the school runs its own DRAIS server. The Electron desktop
///   build binds `0.0.0.0:3210` precisely so other devices on the school LAN
///   can reach it, and that server may itself be in either TiDB or local-MySQL
///   mode (ADR-0010). From the phone's point of view the difference is
///   invisible: it is just a different address.
///
/// A build-time-only address cannot serve both, and shipping a different APK
/// per school does not scale. So the address is configuration, not code.
///
/// ## What this is not
///
/// It is **not** a database setting. The app never chooses, sees or reaches a
/// database — the server does that. This selects which *server* answers, and
/// nothing else.
///
/// ## The UI does not depend on it
///
/// Unlike the Next.js client, whose HTML is produced by the server, every
/// screen here is compiled into the binary. The app opens, renders and
/// navigates with no server configured at all. This value is consulted the
/// first time data is needed — nothing earlier.
class ServerConfig {
  /// Creates a resolved server configuration.
  const ServerConfig({required this.baseUrl, required this.origin});

  /// The server's origin, normalised: no trailing slash, no `/api` suffix.
  final String baseUrl;

  /// Where this value came from, for diagnostics and for deciding whether the
  /// user may change it.
  final ServerOrigin origin;

  /// Whether the address is a plain-HTTP LAN address.
  ///
  /// True for a school's own server on the local network, which legitimately
  /// runs HTTP — the desktop build serves `http://0.0.0.0:3210`, exactly as
  /// `next start` does on a browser's localhost.
  bool get isLanAddress => _isPrivateHost(Uri.tryParse(baseUrl));

  /// Whether traffic to this server is encrypted.
  bool get isSecure => Uri.tryParse(baseUrl)?.scheme == 'https';

  /// Short label for the diagnostics screen and the connection banner.
  String get displayHost {
    final Uri? uri = Uri.tryParse(baseUrl);
    if (uri == null) return baseUrl;
    return uri.hasPort ? '${uri.host}:${uri.port}' : uri.host;
  }

  @override
  String toString() => 'ServerConfig($baseUrl, ${origin.name})';

  // ───────────────────────────────────────────────────────────────────────
  // Normalisation and validation
  // ───────────────────────────────────────────────────────────────────────

  /// Normalises user input into an origin.
  ///
  /// Deliberately forgiving about what a school administrator will type:
  /// `drais.pro`, `https://drais.pro/`, `192.168.1.50:3210`, and
  /// `https://drais.pro/api` all resolve to the same origin. Being strict here
  /// produces support calls, not correctness.
  ///
  /// Returns null when nothing sensible can be made of the input.
  static String? normalise(String raw) {
    String value = raw.trim();
    if (value.isEmpty) return null;

    // Bare host or host:port — assume a scheme rather than rejecting.
    // Private addresses get http (a LAN server has no certificate);
    // anything else gets https.
    if (!value.contains('://')) {
      final bool privateLooking = _looksPrivate(value.split('/').first);
      value = '${privateLooking ? 'http' : 'https'}://$value';
    }

    final Uri? uri = Uri.tryParse(value);
    if (uri == null || uri.host.isEmpty) return null;
    if (uri.scheme != 'http' && uri.scheme != 'https') return null;

    // `Uri.tryParse` is permissive — it will happily accept a "host" full of
    // spaces or punctuation rather than returning null. Free text typed into
    // the address field would otherwise be stored as a server, and every
    // request would then fail for reasons the user could not act on.
    if (!_hostPattern.hasMatch(uri.host)) return null;

    final StringBuffer out = StringBuffer('${uri.scheme}://${uri.host}');
    if (uri.hasPort) out.write(':${uri.port}');

    // Preserve a sub-path (some deployments sit behind a path prefix) but
    // strip a trailing /api — endpoint constants carry their own.
    String path = uri.path;
    while (path.endsWith('/')) {
      path = path.substring(0, path.length - 1);
    }
    if (path.endsWith('/api')) path = path.substring(0, path.length - 4);
    if (path.isNotEmpty) out.write(path);

    return out.toString();
  }

  /// Checks a candidate address, returning a user-facing problem or null.
  ///
  /// This runs before any network call, so the user learns about a typo
  /// immediately rather than after a timeout.
  static String? validateCandidate(String raw, Environment environment) {
    final String? normalised = normalise(raw);
    if (normalised == null) {
      return 'That does not look like a server address. '
          'Example: drais.pro, or 192.168.1.50:3210 for a school server.';
    }

    final Uri uri = Uri.parse(normalised);

    // Cleartext is acceptable on a LAN, where there is no certificate to have
    // and the traffic never leaves the building. Over the public internet it
    // would expose the session cookie, so it is refused.
    if (uri.scheme == 'http' && !_isPrivateHost(uri)) {
      return 'Use https:// for an internet address. '
          'Plain http is only allowed for a school server on your local '
          'network.';
    }

    if (environment.isProduction && _isLoopback(uri)) {
      return 'That address points at this device itself, which cannot host '
          'DRAIS. Enter your school server or the DRAIS web address.';
    }

    return null;
  }

  /// A hostname, IPv4 address, or bracketed IPv6 literal — and nothing else.
  ///
  /// Deliberately does not verify the host *exists*; that is the probe's job.
  /// This only rejects input that could not be a host at all.
  static final RegExp _hostPattern = RegExp(
    r'^(\[[0-9a-fA-F:]+\]|[a-zA-Z0-9]([a-zA-Z0-9\-]*[a-zA-Z0-9])?'
    r'(\.[a-zA-Z0-9]([a-zA-Z0-9\-]*[a-zA-Z0-9])?)*)$',
  );

  /// Whether a URI names this device — never a valid DRAIS server for a phone,
  /// since nothing on the handset serves the API.
  static bool _isLoopback(Uri uri) {
    const Set<String> loopback = <String>{
      'localhost',
      '127.0.0.1',
      '0.0.0.0',
      '::1',
      '10.0.2.2', // Android emulator's alias for the host machine
    };
    return loopback.contains(uri.host.toLowerCase());
  }

  /// Whether a host is on a private network, where plain HTTP is acceptable.
  static bool _isPrivateHost(Uri? uri) {
    if (uri == null) return false;
    return _looksPrivate(uri.host);
  }

  static bool _looksPrivate(String hostWithOptionalPort) {
    final String host = hostWithOptionalPort.split(':').first.toLowerCase();

    if (host == 'localhost' || host.endsWith('.local')) return true;

    final List<String> octets = host.split('.');
    if (octets.length != 4) return false;
    final List<int?> parts = octets
        .map((String o) => int.tryParse(o))
        .toList(growable: false);
    if (parts.any((int? p) => p == null || p < 0 || p > 255)) return false;

    final int a = parts[0]!;
    final int b = parts[1]!;

    // RFC 1918 private ranges, plus loopback and link-local.
    if (a == 10) return true;
    if (a == 127) return true;
    if (a == 192 && b == 168) return true;
    if (a == 172 && b >= 16 && b <= 31) return true;
    if (a == 169 && b == 254) return true;
    return false;
  }
}

/// Where a [ServerConfig] came from.
enum ServerOrigin {
  /// Chosen by the user on the connect screen and stored on the device.
  userConfigured,

  /// Supplied at build time via `DRAIS_API_BASE_URL` — the normal path for a
  /// production release, so most users never see the connect screen.
  buildDefault,
}
