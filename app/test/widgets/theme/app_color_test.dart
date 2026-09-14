/// Unit tests for `app/lib/widgets/theme/app_color.dart` against the two
/// documented source tables in `docs/32-design-language.md`: the Herdr
/// brand source for chrome and semantic state (`R-32-110`, `R-32-120`,
/// `R-32-130` per `R-32-584`: a `color.status.*` token keeps drawing from
/// the Herdr brand, per section 3.1b) and Selenized for the terminal
/// palette (`R-32-100`, `R-32-140`), plus the `R-32-101` exception and the
/// ANSI slot 7 remap in `R-32-141`.
///
/// `contrast_test.dart` in this directory recomputes every documented
/// contrast ratio; this file instead proves each getter is drawn only from
/// the source permitted for its class, and that the named exception and
/// slot remap land on exactly the getters the prose says they do.
library;

import 'dart:io';

import 'package:flutter/widgets.dart' show Color;
import 'package:flutter_test/flutter_test.dart';
import 'package:herdr_mobile/widgets/theme/app_color.dart';

/// The 22 Selenized dark values named in `docs/32-design-language.md`'s
/// section 3.1 table (lines 95-118), keyed by their Selenized name.
const Map<String, int> _selenizedDark = <String, int>{
  'bg_0': 0xFF103c48,
  'bg_1': 0xFF184956,
  'bg_2': 0xFF2d5b69,
  'dim_0': 0xFF72898f,
  'fg_0': 0xFFadbcbc,
  'fg_1': 0xFFcad8d9,
  'red': 0xFFfa5750,
  'green': 0xFF75b938,
  'yellow': 0xFFdbb32d,
  'blue': 0xFF4695f7,
  'magenta': 0xFFf275be,
  'cyan': 0xFF41c7b9,
  'orange': 0xFFed8649,
  'violet': 0xFFaf88eb,
  'br_red': 0xFFff665c,
  'br_green': 0xFF84c747,
  'br_yellow': 0xFFebc13d,
  'br_blue': 0xFF58a3ff,
  'br_magenta': 0xFFff84cd,
  'br_cyan': 0xFF53d6c7,
  'br_orange': 0xFFfd9456,
  'br_violet': 0xFFbd96fa,
};

/// The same 22 rows, Selenized light column.
const Map<String, int> _selenizedLight = <String, int>{
  'bg_0': 0xFFfbf3db,
  'bg_1': 0xFFece3cc,
  'bg_2': 0xFFd5cdb6,
  'dim_0': 0xFF909995,
  'fg_0': 0xFF53676d,
  'fg_1': 0xFF3a4d53,
  'red': 0xFFd2212d,
  'green': 0xFF489100,
  'yellow': 0xFFad8900,
  'blue': 0xFF0072d4,
  'magenta': 0xFFca4898,
  'cyan': 0xFF009c8f,
  'orange': 0xFFc25d1e,
  'violet': 0xFF8762c6,
  'br_red': 0xFFcc1729,
  'br_green': 0xFF428b00,
  'br_yellow': 0xFFa78300,
  'br_blue': 0xFF006dce,
  'br_magenta': 0xFFc44392,
  'br_cyan': 0xFF00978a,
  'br_orange': 0xFFbc5819,
  'br_violet': 0xFF825dc0,
};

/// Herdr brand chrome values for dark (Ink).
const Set<int> _herdrDark = <int>{
  0xFF17171A, // bgBase, and fgOnAccent (both brand `--bg`/`--spot-ink`)
  0xFF1E1E22, // bgRaised
  0xFF26262B, // bgHigh
  0xFF202024, // bgGrid
  0xFF908F96, // borderStrong, fgDisabled, and statusUnknown
  0xFF35353D, // borderSubtle
  0xFFEAE8EE, // fgPrimary
  0xFFB0AFB6, // fgSecondary
  // `shadow` (#181818, Selenized black bg_0) is the one R-32-101 exception,
  0xFFCBA6F7, // accentText, and accentPrimary
  0xFF52C97A, // statusIdle, and statusOk
  0xFFE6B84A, // statusWorking, and statusWarning
  0xFFE05A5A, // statusBlocked, and statusError
  0xFF94E2D5, // statusDone
};

/// Herdr brand chrome values for light (Paper).
const Set<int> _herdrLight = <int>{
  0xFFEFECE5, // bgBase
  0xFFE7E3DA, // bgRaised
  0xFFDDD8CC, // bgHigh
  0xFFE4E0D6, // bgGrid
  0xFF6F6B5C, // borderStrong, and statusUnknown
  0xFFCBC5B6, // borderSubtle
  0xFF15140F, // fgPrimary
  0xFF55534A, // fgSecondary
  0xFF928E79, // fgDisabled
  0xFF7028D8, // accentText
  0xFF8839EF, // accentPrimary, and statusInfo
  0xFFFFFFFF, // fgOnAccent
  0xFF268A46, // statusIdle, and statusOk
  0xFF9A6F08, // statusWorking, and statusWarning
  0xFFC73E3E, // statusBlocked, and statusError
  0xFF1F8078, // statusDone
};

/// Chrome getters. `shadow` is the one explicit `R-32-101` exception to
/// Herdr brand membership (it uses Selenized black); dark `fgOnAccent` is
/// the brand `--spot-ink`, which happens to equal `bgBase`.
const Set<String> _chromeGetterNames = <String>{
  'bgBase',
  'bgRaised',
  'bgHigh',
  'bgGrid',
  'borderStrong',
  'borderSubtle',
  'shadow',
  'fgPrimary',
  'fgSecondary',
  'fgDisabled',
  'accentText',
  'accentPrimary',
  'fgOnAccent',
};

/// Semantic state getters: `R-32-584` binds a `color.status.*` token to the
/// Herdr brand source of section 3.1b, per section 3.4's own table ("These
/// nine hexes are the Herdr brand state colours"), so they are checked
/// against the brand membership sets, not the Selenized ones.
const Set<String> _statusGetterNames = <String>{
  'statusIdle',
  'statusWorking',
  'statusBlocked',
  'statusDone',
  'statusUnknown',
  'statusError',
  'statusWarning',
  'statusOk',
  'statusInfo',
};

/// `R-32-101`'s single near-neutral exception value: Selenized black's
/// `bg_0`, permitted only as `color.shadow` in both themes. Dark
/// `color.fg.on_accent` is the brand `--spot-ink` `#17171a`, which equals
/// `bgBase`, not this value.
const int _selenizedBlackBg0 = 0xFF181818;

/// Every named getter on one [AppColor] instance, so the class-source
/// membership and `R-32-101` exception placement can be checked without
/// `dart:mirrors`, which Flutter does not ship.
Map<String, Color> _getters(AppColor c) => <String, Color>{
  'bgBase': c.bgBase,
  'bgRaised': c.bgRaised,
  'bgHigh': c.bgHigh,
  'bgGrid': c.bgGrid,
  'borderStrong': c.borderStrong,
  'borderSubtle': c.borderSubtle,
  'shadow': c.shadow,
  'fgPrimary': c.fgPrimary,
  'fgSecondary': c.fgSecondary,
  'fgDisabled': c.fgDisabled,
  'accentText': c.accentText,
  'accentPrimary': c.accentPrimary,
  'fgOnAccent': c.fgOnAccent,
  'statusIdle': c.statusIdle,
  'statusWorking': c.statusWorking,
  'statusBlocked': c.statusBlocked,
  'statusDone': c.statusDone,
  'statusUnknown': c.statusUnknown,
  'statusError': c.statusError,
  'statusWarning': c.statusWarning,
  'statusOk': c.statusOk,
  'statusInfo': c.statusInfo,
  'termBg': c.termBg,
  'termFg': c.termFg,
  'termFgBold': c.termFgBold,
  'termFgDim': c.termFgDim,
  'termCursor': c.termCursor,
  'termSelection': c.termSelection,
  'termAnsi0': c.termAnsi0,
  'termAnsi1': c.termAnsi1,
  'termAnsi2': c.termAnsi2,
  'termAnsi3': c.termAnsi3,
  'termAnsi4': c.termAnsi4,
  'termAnsi5': c.termAnsi5,
  'termAnsi6': c.termAnsi6,
  'termAnsi7': c.termAnsi7,
  'termAnsi8': c.termAnsi8,
  'termAnsi9': c.termAnsi9,
  'termAnsi10': c.termAnsi10,
  'termAnsi11': c.termAnsi11,
  'termAnsi12': c.termAnsi12,
  'termAnsi13': c.termAnsi13,
  'termAnsi14': c.termAnsi14,
  'termAnsi15': c.termAnsi15,
};

void main() {
  group('AppColor source membership (R-32-100, R-32-110, R-32-120, R-32-130, R-32-140, R-32-584)', () {
    for (final AppColor theme in AppColor.values) {
      test(
        '${theme.name}: chrome and semantic state are Herdr brand, terminal is Selenized',
        () {
          final Set<int> herdr = theme == AppColor.dark
              ? _herdrDark
              : _herdrLight;
          final Set<int> selenized = <int>{
            ...(theme == AppColor.dark
                ? _selenizedDark.values
                : _selenizedLight.values),
            _selenizedBlackBg0,
          };
          final Set<int> chromeAllowed = <int>{...herdr, _selenizedBlackBg0};

          _getters(theme).forEach((String name, Color value) {
            final bool isChrome =
                _chromeGetterNames.contains(name) ||
                _statusGetterNames.contains(name);
            final Set<int> allowed = isChrome ? chromeAllowed : selenized;
            expect(
              allowed.contains(value.toARGB32()),
              isTrue,
              reason:
                  'AppColor.${theme.name}.$name '
                  '(0x${value.toARGB32().toRadixString(16)}) is not a '
                  '${isChrome ? 'Herdr brand chrome/semantic or R-32-101 exception' : 'Selenized terminal'} '
                  'value',
            );
          });
        },
      );
    }
  });

  group('R-32-101 exception placement', () {
    test('exactly shadow (both themes) equals the near-neutral exception; '
        'dark.fgOnAccent is the brand spot-ink, equal to bgBase', () {
      final Map<String, Color> dark = _getters(AppColor.dark);
      final Map<String, Color> light = _getters(AppColor.light);

      final Set<String> darkMatches = dark.entries
          .where(
            (MapEntry<String, Color> e) =>
                e.value.toARGB32() == _selenizedBlackBg0,
          )
          .map((MapEntry<String, Color> e) => e.key)
          .toSet();
      final Set<String> lightMatches = light.entries
          .where(
            (MapEntry<String, Color> e) =>
                e.value.toARGB32() == _selenizedBlackBg0,
          )
          .map((MapEntry<String, Color> e) => e.key)
          .toSet();

      expect(darkMatches, <String>{'shadow'});
      expect(lightMatches, <String>{'shadow'});

      expect(
        dark['fgOnAccent']!.toARGB32(),
        dark['bgBase']!.toARGB32(),
        reason:
            'dark.fgOnAccent is the brand `--spot-ink` #17171a, which '
            'equals `bgBase`, per section 3.1b',
      );
    });
  });

  group('R-32-141 ANSI slot 7 deviation', () {
    test('termAnsi7 equals termFg (fg_0), not termFgDim (dim_0), in both themes', () {
      for (final AppColor c in AppColor.values) {
        expect(
          c.termAnsi7.toARGB32(),
          c.termFg.toARGB32(),
          reason: '${c.name}.termAnsi7 MUST match termFg (fg_0), per R-32-141',
        );
        expect(
          c.termAnsi7.toARGB32(),
          isNot(c.termFgDim.toARGB32()),
          reason:
              '${c.name}.termAnsi7 MUST NOT match termFgDim (dim_0), per R-32-141',
        );
      }
    });
  });

  group('R-32-125 accentPrimary is a fill, never a text-style colour', () {
    test('no widget under lib/screens or lib/widgets styles text with accentPrimary', () {
      // A static scan, matching this directory's `no_literals_test.dart`
      // convention: `docs/41-code-standards.md` R-41-042 forbids a new
      // dependency before the reuse ladder is climbed, and text colour in
      // this codebase is always assigned through `TextStyle(...)` or
      // `AppType.<token>.copyWith(color: ...)` (verified: no other
      // `TextStyle(` construction exists under `lib/screens` or
      // `lib/widgets` outside `lib/widgets/theme`), so a scan for either
      // wrapping `accentPrimary` is a complete, not a sampled, check.
      const List<String> roots = <String>['lib/screens', 'lib/widgets'];
      const String tokenDirectory = 'lib/widgets/theme';
      final RegExp textStyleWithAccentPrimary = RegExp(
        r'(?:TextStyle\(|AppType\.\w+\.copyWith\()[^)]{0,300}\baccentPrimary\b',
      );

      final List<String> offenders = <String>[];
      for (final String rootPath in roots) {
        final Directory root = Directory(rootPath);
        if (!root.existsSync()) continue;
        for (final FileSystemEntity entity in root.listSync(recursive: true)) {
          if (entity is! File || !entity.path.endsWith('.dart')) continue;
          final String normalizedPath = entity.path.replaceAll(r'\', '/');
          if (normalizedPath.contains('$tokenDirectory/')) continue;
          final String contents = entity.readAsStringSync();
          if (textStyleWithAccentPrimary.hasMatch(contents)) {
            offenders.add(normalizedPath);
          }
        }
      }

      expect(
        offenders,
        isEmpty,
        reason:
            'accentPrimary MUST NOT carry text, per R-32-125; offending files: $offenders',
      );
    });
  });
}
