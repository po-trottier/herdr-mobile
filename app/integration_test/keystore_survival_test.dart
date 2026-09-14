// On-device proof that `KeystoreService` persists through the platform keychain or keystore,
// not through Dart-side process state (R-22-009, R-13-046).
//
// Two things this file cannot prove with the pinned `integration_test` package alone, because
// a single `flutter test integration_test/...` run never kills and relaunches the app
// process:
//   - Survival across a genuine app-process restart (not just a fresh Dart object). The
//     positive-path test below gets as close as the harness allows: a second
//     `KeystoreService` backed by a second `FlutterSecureStorage` instance shares no Dart
//     state with the first, so a matching read forces a real platform-channel round trip to
//     the OS-level store.
//   - Key loss across an uninstall and reinstall (R-22-009, R-13-046). That needs `adb
//     uninstall` and a reinstall between two separate test runs, which is a manual or CI-script
//     step, not something one `testWidgets` body can drive. The second test below documents
//     the expected behaviour and is skipped for that reason, named so a future CI job can
//     replace it with a real two-phase driver script instead of deleting the record of the
//     requirement.

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:herdr_mobile/core/result/result.dart';
import 'package:herdr_mobile/services/keystore.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('the device key pair survives a fresh KeystoreService instance', (
    tester,
  ) async {
    final beforeResult = await KeystoreService(appLockEnabled: true)
        .deviceKeyPair();
    expect(beforeResult, isA<Ok<SimpleKeyPair>>());
    final publicKeyBefore = await (beforeResult as Ok<SimpleKeyPair>).value
        .extractPublicKey();

    // A second instance, with no Dart-side state shared with the first, simulates the app
    // restarting: any key it returns had to come from the platform store, not from memory.
    final afterResult = await KeystoreService(appLockEnabled: true)
        .deviceKeyPair();
    expect(afterResult, isA<Ok<SimpleKeyPair>>());
    final publicKeyAfter = await (afterResult as Ok<SimpleKeyPair>).value
        .extractPublicKey();

    expect(publicKeyAfter.bytes, publicKeyBefore.bytes);
  });

  testWidgets(
    'the device key pair is lost across an uninstall and reinstall, and a '
    're-pair is required (needs adb uninstall + reinstall between two '
    'flutter drive runs; a single flutter test process cannot kill and '
    'relaunch the app, R-22-009, R-13-046; replace with a two-phase driver '
    'script when CI gains device automation)',
    (tester) async {},
    skip: true,
  );
}
