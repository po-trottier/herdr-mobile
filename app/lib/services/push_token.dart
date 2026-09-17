import 'dart:async' show StreamController, StreamSubscription;

import 'package:firebase_core/firebase_core.dart' show Firebase;
import 'package:firebase_messaging/firebase_messaging.dart'
    show FirebaseMessaging;
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/services.dart' show MethodChannel;
import 'package:logging/logging.dart' show Logger;

/// Acquires opaque push tokens. Notification permission belongs to the caller.
class PushTokenService {
  PushTokenService({
    FirebaseMessaging? messaging,
    Future<void> Function()? initializeFirebase,
    Logger? logger,
    // Keep the injection parameter public and the field private.
    // ignore: prefer_initializing_formals
  }) : _messaging = messaging,
       _initializeFirebase = initializeFirebase ?? _initialize,
       _log = logger ?? Logger('PushTokenService');

  static const MethodChannel _channel = MethodChannel(
    'dev.herdr.herdr_mobile/push',
  );
  static Future<void> _initialize() async {
    await Firebase.initializeApp();
  }

  final FirebaseMessaging? _messaging;
  final Future<void> Function() _initializeFirebase;
  final Logger _log;
  final StreamController<String?> _tokens =
      StreamController<String?>.broadcast();
  StreamSubscription<String>? _refresh;
  bool _disposed = false;

  Stream<String?> get token => _tokens.stream;

  void _publish(String? value) {
    if (!_disposed) _tokens.add(value);
  }

  Future<void> register() async {
    if (_disposed) return;
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      _channel.setMethodCallHandler((call) async {
        if (call.method == 'token') {
          _publish(call.arguments as String?);
        } else if (call.method == 'failed') {
          _publish(null);
          _log.info('Push registration unavailable.');
        }
      });
      try {
        await _channel.invokeMethod<void>('register');
      } on Exception {
        _publish(null);
        _log.info('Push registration unavailable.');
      }
    } else if (defaultTargetPlatform == TargetPlatform.android) {
      try {
        await _initializeFirebase();
        if (_disposed) return;
        final messaging = _messaging ?? FirebaseMessaging.instance;
        _refresh ??= messaging.onTokenRefresh.listen(
          _publish,
          onError: (Object error) {
            _publish(null);
            _log.info('Push registration unavailable.');
          },
        );
        _publish(await messaging.getToken());
      } on Exception {
        _publish(null);
        _log.info('Push registration unavailable.');
      }
    }
  }

  Future<void> dispose() async {
    _disposed = true;
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      _channel.setMethodCallHandler(null);
    }
    await _refresh?.cancel();
    await _tokens.close();
  }
}
