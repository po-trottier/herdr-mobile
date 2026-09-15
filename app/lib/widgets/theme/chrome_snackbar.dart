/// Platform feedback with the opaque section 7.22 surface.
library;

import 'dart:async' show Timer;
import 'dart:math' show max;

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/widgets.dart';
import 'package:material_ui/material_ui.dart'
    show
        RoundedRectangleBorder,
        ScaffoldMessenger,
        SnackBar,
        SnackBarBehavior,
        SnackBarThemeData;

import 'app_color.dart';
import 'app_elev.dart';
import 'app_radius.dart';
import 'app_space.dart';
import 'app_type.dart';
import 'chrome_transient_timeout.dart';

// The native SnackBar duration and section 7.22 elevation.
const Duration _duration = Duration(seconds: 4);
const double _elevation = 2;
const EdgeInsets _padding = EdgeInsets.symmetric(
  vertical: AppSpace.space3,
  horizontal: AppSpace.space4,
);

/// The Material surface uses the same tokens as the iOS overlay.
SnackBarThemeData chromeSnackbarTheme(AppColor color) => SnackBarThemeData(
  backgroundColor: color.bgRaised,
  contentTextStyle: AppType.body.copyWith(color: color.fgPrimary),
  elevation: _elevation,
  shape: const RoundedRectangleBorder(
    borderRadius: BorderRadius.all(Radius.circular(AppRadius.md)),
  ),
  behavior: SnackBarBehavior.floating,
  insetPadding: const EdgeInsets.all(AppSpace.space4),
);

/// Shows feedback without a timeout while a screen reader is active.
void showChromeSnackbar(BuildContext context, String text) {
  if (defaultTargetPlatform != TargetPlatform.iOS) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text),
        padding: _padding,
        duration: _duration,
        persist: ChromeTransientTimeout.of(context, _duration) == null,
      ),
    );
    return;
  }

  final OverlayState overlay = Overlay.of(context, rootOverlay: true);
  late final OverlayEntry entry;
  bool dismissed = false;
  void dismiss() {
    if (dismissed) return;
    dismissed = true;
    entry.remove();
    entry.dispose();
  }

  entry = OverlayEntry(
    builder: (BuildContext context) =>
        _IosSnackbar(text: text, onDismiss: dismiss),
  );
  overlay.insert(entry);
}

class _IosSnackbar extends StatefulWidget {
  const _IosSnackbar({required this.text, required this.onDismiss});

  final String text;
  final VoidCallback onDismiss;

  @override
  State<_IosSnackbar> createState() => _IosSnackbarState();
}

class _IosSnackbarState extends State<_IosSnackbar> {
  Timer? _timer;
  Duration? _timeout;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final Duration? timeout = ChromeTransientTimeout.of(context, _duration);
    if (_timeout == timeout) return;
    _timeout = timeout;
    _timer?.cancel();
    if (timeout != null) _timer = Timer(timeout, widget.onDismiss);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppColor color = AppColor.of(context);
    final MediaQueryData media = MediaQuery.of(context);
    return Positioned(
      left: media.padding.left + AppSpace.space4,
      right: media.padding.right + AppSpace.space4,
      bottom:
          max(media.viewInsets.bottom, media.padding.bottom) + AppSpace.space4,
      child: Semantics(
        liveRegion: true,
        onDismiss: widget.onDismiss,
        child: DecoratedBox(
          decoration: AppElev.elev2(color).copyWith(
            color: color.bgRaised,
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          child: Padding(
            padding: _padding,
            child: Text(
              widget.text,
              style: AppType.body.copyWith(
                color: color.fgPrimary,
                inherit: false,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
