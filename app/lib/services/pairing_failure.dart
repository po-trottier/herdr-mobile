import 'dart:async' show TimeoutException;
import 'dart:io' show HandshakeException, SocketException, WebSocketException;

import 'relay.dart'
    show RelayConnectException, RelayConnectFailure, RelayRegistrationException;

/// Names the transport failure without the pairing credentials or connection URI.
String pairingFailureSentence(
  Object? error,
  String host, {
  Iterable<String> secrets = const [],
}) {
  String redact(String value) {
    var text = value.replaceAll(
      RegExp(r'[a-zA-Z][a-zA-Z0-9+.-]*://[^\s]+'),
      '[redacted]',
    );
    for (final secret in secrets) {
      if (secret.isEmpty) continue;
      for (final form in {
        secret,
        Uri.encodeComponent(secret),
        secret.replaceAll('-', ' '),
      }) {
        text = text.replaceAll(form, '[redacted]');
      }
    }
    return text.replaceAll(RegExp(r'[\r\n]+'), ' ').trim();
  }

  if (error is RelayRegistrationException) return redact(error.message);

  if (error is RelayConnectException &&
      error.failure != RelayConnectFailure.webSocketFailed) {
    return redact(error.message);
  }

  final String reason;
  if (error is RelayConnectException) {
    // The wrapper hides the transport text (R-13-066); classify what it wrapped.
    if (error.inner != null) {
      return pairingFailureSentence(error.inner, host, secrets: secrets);
    }
    reason = error.message.contains('closed')
        ? 'the relay closed the connection'
        : error.message;
  } else if (error is SocketException) {
    reason = switch (error.osError?.errorCode) {
      61 || 111 || 1225 || 10061 => 'connection refused',
      60 || 110 || 10060 => 'connection timed out',
      51 || 65 || 101 || 113 || 10051 || 10065 => 'no route to the network',
      _ => error.osError?.message ?? error.message,
    };
  } else if (error is WebSocketException) {
    reason = 'the relay closed the connection';
  } else if (error is TimeoutException) {
    final duration = error.duration;
    reason = duration == null
        ? 'connection timed out'
        : 'timed out after ${duration.inMilliseconds % 1000 == 0 ? duration.inSeconds : duration.inMilliseconds / 1000} s';
  } else if (error is HandshakeException) {
    reason = 'TLS failed';
  } else {
    reason =
        error?.toString().replaceFirst(RegExp(r'^Exception: '), '') ??
        'connection failed';
  }
  final safeReason = redact(reason).replaceFirst(RegExp(r'[.]+$'), '');
  return 'Could not reach ${redact(host)}: ${safeReason.isEmpty ? 'connection failed' : safeReason}.';
}
