/// The relay origin: parsing, validation, canonical storage form, and the
/// `https://`/`http://` to `wss://`/`ws://` mapping (`docs/22-platform-integration.md`
/// section 7, `docs/03-product-decisions.md` R-03-030 to R-03-033).
///
/// The app ships no compiled default relay origin (R-22-040, R-03-030): first run has no
/// relay, and pairing supplies the first one. Every origin this file accepts or rejects
/// comes from a pairing URI's `r` field or a person's manual entry, never a constant in this
/// codebase.
library;

import 'dart:io';

import '../core/result/result.dart' show Err, Ok, Result;

/// `docs/11-relay-protocol.md` §9.5's two origin-specific failure codes. The remaining rows
/// of that table (`pair_uri_*`, `phrase_*`, `handle_malformed`) belong to the pairing URI
/// parser (`app/lib/services/pairing.dart`, a later work package), not this file.
enum RelayOriginErrorCode {
  /// `r` is not an absolute `http`/`https` origin, or carries a path, query, fragment, or
  /// userinfo.
  relayOriginInvalid('relay_origin_invalid'),

  /// `r` uses `http://` for a host outside the local-development allow list (R-22-039).
  relayOriginInsecure('relay_origin_insecure');

  const RelayOriginErrorCode(this.wireValue);

  /// The exact string this code appears as in `docs/11-relay-protocol.md` §9.5.
  final String wireValue;
}

/// Set as an [Err.cause] when [parseRelayOrigin] rejects its input. [message] is shown raw,
/// per the R-11-092 pattern this codebase already applies to every other wire-adjacent
/// error.
final class RelayOriginException implements Exception {
  const RelayOriginException(this.code, this.message);

  final RelayOriginErrorCode code;
  final String message;

  @override
  String toString() => message;
}

/// A relay origin in the canonical form R-22-037 requires: scheme, host, and an optional
/// port. No path, no query, no fragment, no trailing slash.
final class RelayOrigin {
  const RelayOrigin({required this.scheme, required this.host, this.port});

  /// `https` or `http`. Never `wss`/`ws`: those are the WebSocket-path form
  /// [webSocketUri] produces, not the stored form (R-22-037, R-22-038).
  final String scheme;

  final String host;

  /// `null` when the origin carries no explicit port (the scheme's default port applies).
  final int? port;

  /// `true` for `http://` origins, which R-22-039 permits only for the local-development
  /// allow list and which the app MUST mark with a persistent, non-dismissible
  /// insecure-development warning wherever it is displayed (R-22-039). A screen reads this
  /// flag; this file paints nothing.
  bool get isInsecureDevelopment => scheme == 'http';

  /// The canonical storage string (R-22-037): `scheme://host[:port]`, no trailing slash.
  String get canonical =>
      port == null ? '$scheme://$host' : '$scheme://$host:$port';

  /// Builds the WebSocket URL for one relay-facing path, mapping `https://` to `wss://` and
  /// `http://` to `ws://` (R-22-038, R-11-111). [path] MUST start with `/`, for example
  /// `/device/n6Loxf94CfyIO6hOxlaHvA` (R-11-110).
  Uri webSocketUri(String path) {
    assert(path.startsWith('/'), 'path MUST start with "/": $path');
    return Uri(
      scheme: scheme == 'https' ? 'wss' : 'ws',
      host: host,
      port: port,
      path: path,
    );
  }

  @override
  String toString() => canonical;

  @override
  bool operator ==(Object other) =>
      other is RelayOrigin &&
      other.scheme == scheme &&
      other.host == host &&
      other.port == port;

  @override
  int get hashCode => Object.hash(scheme, host, port);
}

/// Parses and validates a relay origin string — from a pairing URI's `r` field or manual
/// settings entry — into its canonical [RelayOrigin] form.
///
/// Rejects:
/// - Anything that is not an absolute `http`/`https` URI, or that carries a path (other than
///   an empty or single `/`), a query, a fragment, or userinfo:
///   [RelayOriginErrorCode.relayOriginInvalid] (R-22-037).
/// - An `http://` origin whose host is outside the local-development allow list —
///   `localhost`, `127.0.0.0/8`, `::1`, and the RFC 1918 ranges `10.0.0.0/8`,
///   `172.16.0.0/12`, `192.168.0.0/16`: [RelayOriginErrorCode.relayOriginInsecure]
///   (R-03-033, R-22-039).
Result<RelayOrigin> parseRelayOrigin(String text) {
  final Uri uri;
  try {
    uri = Uri.parse(text);
  } on FormatException {
    return Err(
      'parse relay origin "$text"',
      cause: const RelayOriginException(
        RelayOriginErrorCode.relayOriginInvalid,
        'The relay origin is not a valid URI.',
      ),
    );
  }

  final isValidShape =
      uri.hasScheme &&
      (uri.scheme == 'http' || uri.scheme == 'https') &&
      uri.host.isNotEmpty &&
      uri.userInfo.isEmpty &&
      (uri.path.isEmpty || uri.path == '/') &&
      uri.query.isEmpty &&
      uri.fragment.isEmpty;
  if (!isValidShape) {
    return Err(
      'parse relay origin "$text"',
      cause: const RelayOriginException(
        RelayOriginErrorCode.relayOriginInvalid,
        'The relay origin must be an absolute https:// or http:// URL with '
        'no path, query, or fragment.',
      ),
    );
  }

  final origin = RelayOrigin(
    scheme: uri.scheme,
    host: uri.host,
    port: uri.hasPort ? uri.port : null,
  );

  if (origin.scheme == 'http' && !_isLocalDevelopmentHost(origin.host)) {
    return Err(
      'parse relay origin "$text"',
      cause: RelayOriginException(
        RelayOriginErrorCode.relayOriginInsecure,
        'http:// is only permitted for localhost and private-network '
        'addresses. Use https:// for "${origin.host}".',
      ),
    );
  }

  return Ok(origin);
}

/// R-22-039: `localhost`, `127.0.0.0/8`, `::1`, and the RFC 1918 ranges `10.0.0.0/8`,
/// `172.16.0.0/12`, `192.168.0.0/16`.
bool _isLocalDevelopmentHost(String host) {
  if (host == 'localhost') {
    return true;
  }
  final address = InternetAddress.tryParse(host);
  if (address == null) {
    return false;
  }
  if (address.type == InternetAddressType.IPv6) {
    return address.isLoopback;
  }
  final octets = address.rawAddress;
  if (octets.length != 4) {
    return false;
  }
  if (octets[0] == 127) {
    return true; // 127.0.0.0/8
  }
  if (octets[0] == 10) {
    return true; // 10.0.0.0/8
  }
  if (octets[0] == 172 && octets[1] >= 16 && octets[1] <= 31) {
    return true; // 172.16.0.0/12
  }
  if (octets[0] == 192 && octets[1] == 168) {
    return true; // 192.168.0.0/16
  }
  return false;
}
