import 'dart:async' show StreamController;

import 'package:firebase_messaging/firebase_messaging.dart'
    show FirebaseMessaging;
import 'package:flutter/foundation.dart'
    show TargetPlatform, debugDefaultTargetPlatformOverride;
import 'package:flutter/services.dart'
    show MethodCall, MethodChannel, PlatformException, StandardMethodCodec;
import 'package:flutter_test/flutter_test.dart'
    show TestWidgetsFlutterBinding, addTearDown, expect, test, tearDown;
import 'package:herdr_mobile/services/push_token.dart' show PushTokenService;
import 'package:logging/logging.dart' show Logger;
import 'package:mocktail/mocktail.dart' show Mock, when;

class _Messaging extends Mock implements FirebaseMessaging {}

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('dev.herdr.herdr_mobile/push');
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
  });

  test(
    'APNs token and failure arrive without Firebase initialization',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      var firebaseCalls = 0;
      final service = PushTokenService(
        initializeFirebase: () async {
          firebaseCalls++;
        },
      );
      addTearDown(service.dispose);
      final tokens = <String?>[];
      final subscription = service.token.listen(tokens.add);
      addTearDown(subscription.cancel);
      binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        expect(call.method, 'register');
        return null;
      });
      await service.register();
      for (final call in [
        const MethodCall('token', '0123abcd'),
        const MethodCall('failed', 'private platform error'),
      ]) {
        await binding.defaultBinaryMessenger.handlePlatformMessage(
          channel.name,
          const StandardMethodCodec().encodeMethodCall(call),
          (_) {},
        );
      }
      await Future<void>.delayed(Duration.zero);
      expect(tokens, ['0123abcd', null]);
      expect(firebaseCalls, 0);
    },
  );

  test('Android publishes initial and refreshed FCM tokens', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final refresh = StreamController<String>();
    final messaging = _Messaging();
    when(() => messaging.onTokenRefresh).thenAnswer((_) => refresh.stream);
    when(() => messaging.getToken()).thenAnswer((_) async => 'initial');
    final service = PushTokenService(
      messaging: messaging,
      initializeFirebase: () async {},
    );
    addTearDown(refresh.close);
    addTearDown(service.dispose);
    final tokens = <String?>[];
    final subscription = service.token.listen(tokens.add);
    addTearDown(subscription.cancel);
    await service.register();
    refresh.add('rotated');
    await Future<void>.delayed(Duration.zero);
    expect(tokens, ['initial', 'rotated']);
  });

  test(
    'missing Firebase configuration completes and logs no error details',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final messages = <String>[];
      final logs = Logger.root.onRecord.listen(
        (record) => messages.add(record.message),
      );
      addTearDown(logs.cancel);
      final service = PushTokenService(
        initializeFirebase: () async {
          throw PlatformException(code: 'private configuration');
        },
      );
      addTearDown(service.dispose);
      final next = service.token.first;
      await service.register();
      expect(await next, null);
      expect(messages, ['Push registration unavailable.']);
    },
  );
}
