import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;
import 'package:flutter/widgets.dart' show runApp;
import 'package:logging/logging.dart' show Level, Logger;

import 'app.dart';

void main() {
  if (kDebugMode) {
    // Every service logs connection metadata and counts only (AGENTS.md, "Never log");
    // a debug build surfaces them in logcat / the Xcode console. Release prints nothing.
    Logger.root.level = Level.ALL;
    Logger.root.onRecord.listen(
      (record) => debugPrint(
        '${record.loggerName}: ${record.message}'
        '${record.error == null ? '' : ' (${record.error})'}',
      ),
    );
  }
  runApp(const HerdrRemoteApp());
}
