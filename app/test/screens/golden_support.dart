/// The one harness every screen golden test uses.
///
/// Two things make a golden prove something about the real screen, and both
/// live here so no test copies them and drifts:
///
/// 1. [loadAppFonts] loads every family `AppType` and the app theme name
///    (IBM Plex Sans, Archivo, JetBrainsMono Nerd Font Mono) plus the Material
///    Symbols Rounded icon font. Without this, `flutter test`'s headless
///    renderer draws a placeholder font and every glyph is a tofu box. The
///    Cupertino glyph font is loaded too, so a platform back button, search
///    glyph or chevron renders in a golden instead of a box (2026-09-08,
///    R-20-044).
/// 2. [goldenApp] wraps the screen in a `MaterialApp` under `appThemeFrom`,
///    the app's one real theme. A bare `ThemeData` gives every stock Material
///    widget the `Roboto` family the test bundle never has, and colours this
///    app never ships. Its `builder` mirrors the real root's `ResolvedChrome`,
///    so an iOS `CupertinoPageScaffold` branch inherits the app-wide
///    `DefaultTextStyle` instead of `MaterialApp`'s yellow fallback (R-41-020).
library;

import 'package:flutter/services.dart' show FontLoader, rootBundle;
import 'package:flutter/widgets.dart'
    show
        AssetImage,
        Brightness,
        BuildContext,
        Builder,
        MediaQuery,
        MediaQueryData,
        Size,
        View,
        Widget,
        precacheImage;
import 'package:flutter_test/flutter_test.dart' show Finder, WidgetTester;
import 'package:herdr_mobile/app.dart'
    show ResolvedChrome, appThemeFrom, sdkMaterialLocalizations;
import 'package:herdr_mobile/widgets/theme/chrome_scheme.dart'
    show ChromeScheme;
import 'package:material_ui/material_ui.dart' show MaterialApp, ThemeMode;

/// The iPhone SE (3rd generation) logical screen size. `docs/20-mobile-framework.md` names that
/// device as the reference; no document states the pixel values, so they live here once.
const Size goldenReferenceSize = Size(375, 667);

Future<void> _loadFont(String family, List<String> assetPaths) async {
  final loader = FontLoader(family);
  for (final assetPath in assetPaths) {
    loader.addFont(rootBundle.load(assetPath));
  }
  await loader.load();
}

/// Loads every font family the app renders with. Call once in `setUpAll`.
Future<void> loadAppFonts() async {
  await _loadFont('IBM Plex Sans', [
    'assets/fonts/IBMPlexSans-Regular.ttf',
    'assets/fonts/IBMPlexSans-SemiBold.ttf',
  ]);
  await _loadFont('Archivo', [
    'assets/fonts/Archivo-Bold.ttf',
    'assets/fonts/Archivo-Black.ttf',
  ]);
  await _loadFont('JetBrainsMono Nerd Font Mono', [
    'assets/fonts/JetBrainsMonoNerdFontMono-Regular.ttf',
    'assets/fonts/JetBrainsMonoNerdFontMono-Bold.ttf',
    'assets/fonts/JetBrainsMonoNerdFontMono-Italic.ttf',
    'assets/fonts/JetBrainsMonoNerdFontMono-BoldItalic.ttf',
  ]);
  await _loadFont('packages/material_symbols_icons/MaterialSymbolsRounded', [
    'packages/material_symbols_icons/lib/fonts/MaterialSymbolsRounded.ttf',
  ]);
  await _loadFont('packages/cupertino_icons/CupertinoIcons', [
    'packages/cupertino_icons/assets/CupertinoIcons.ttf',
  ]);
}

/// A `MaterialApp` under the app's real light and dark themes, forced to
/// [brightness], with [child] as home.
///
/// The `MediaQuery` sits above the `MaterialApp`, not under `home`, so a
/// modal route (a sheet, a dialog) that the navigator pushes above `home`
/// sees the same brightness and the same size as the screen. Its data comes
/// from the test view (`tester.view`), so the size is the real
/// [goldenReferenceSize] the test set, never `Size.zero`. [adjust] lets a
/// test add view insets or a text scale; `platformBrightness` is forced
/// after it runs.
Widget goldenApp({
  required Widget child,
  required Brightness brightness,
  MediaQueryData Function(MediaQueryData ambient)? adjust,
}) => Builder(
  builder: (BuildContext context) {
    final MediaQueryData ambient =
        MediaQuery.maybeOf(context) ??
        MediaQueryData.fromView(View.of(context));
    final MediaQueryData adjusted = adjust?.call(ambient) ?? ambient;
    return MediaQuery(
      data: adjusted.copyWith(platformBrightness: brightness),
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        // [sdkMaterialLocalizations] mirrors the real app root: screens that call
        // `package:flutter/material.dart`'s own `showModalBottomSheet` look the SDK
        // `MaterialLocalizations` type up by identity, a different type from
        // `material_ui`'s reimplementation.
        localizationsDelegates: sdkMaterialLocalizations,
        theme: appThemeFrom(ChromeScheme.fixed(Brightness.light)),
        darkTheme: appThemeFrom(ChromeScheme.fixed(Brightness.dark)),
        themeMode: brightness == Brightness.dark
            ? ThemeMode.dark
            : ThemeMode.light,
        builder: (BuildContext context, Widget? child) =>
            ResolvedChrome(child: child!),
        home: child,
      ),
    );
  },
);

/// Decodes `assets/brand/ram.png` into the image cache before the golden
/// frame is taken. `Image.asset` decodes off the test's fake async zone, so
/// without this the first golden in a file paints no brand mark while every
/// later one, served from the cache, does. [scope] is any element under the
/// pumped app.
Future<void> precacheBrandMark(WidgetTester tester, Finder scope) async {
  final BuildContext context = tester.element(scope);
  await tester.runAsync(
    () => precacheImage(const AssetImage('assets/brand/ram.png'), context),
  );
  await tester.pump();
}
