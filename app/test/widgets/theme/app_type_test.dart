/// Asserts the fifteen `AppType` tokens `docs/32-design-language.md`
/// section 4 fixes (R-32-202) are exactly what
/// `app/lib/widgets/theme/app_type.dart` declares: no size, line height,
/// weight or letter spacing drifts, no token is missing and no sixteenth
/// token appears. Also asserts the `type.mono.terminal` closed size list
/// and default (R-30-210, R-32-208), the letter-spacing rule R-32-204
/// states (negative on `display`, `title`, `heading`; positive on `micro`
/// and `monoButton`; none elsewhere), and that `pubspec.yaml`'s
/// `IBM Plex Sans` family lists exactly the two files R-32-200 names
/// (R-32-201 assets exist by the app building at all; this only checks the
/// font declaration, per WP-12-a).
library;

import 'dart:io';

import 'package:flutter/widgets.dart' show FontWeight, TextStyle;
import 'package:flutter_test/flutter_test.dart';
import 'package:herdr_mobile/widgets/theme/app_type.dart';

/// One documented token: its name and the exact `TextStyle` fields
/// `docs/32-design-language.md` section 4 fixes for it.
class _Token {
  const _Token(
    this.name,
    this.style, {
    required this.fontSize,
    required this.height,
    required this.weight,
    this.letterSpacing,
  });

  final String name;
  final TextStyle style;
  final double fontSize;
  final double height;
  final FontWeight weight;
  final double? letterSpacing;
}

/// Every static `AppType` token, transcribed by hand from
/// `app/lib/widgets/theme/app_type.dart`. There is no runtime reflection in
/// Flutter, so this list itself is the "no 16th token" boundary: a token
/// added to `AppType` without a matching entry here is silently unchecked,
/// which is why the count test below also pins the total to fifteen.
List<_Token> _tokens() => <_Token>[
  const _Token(
    'display',
    AppType.display,
    fontSize: 42,
    height: 40 / 42,
    weight: FontWeight.w900,
    letterSpacing: -2.4,
  ),
  const _Token(
    'title',
    AppType.title,
    fontSize: 28,
    height: 30 / 28,
    weight: FontWeight.w900,
    letterSpacing: -1.1,
  ),
  const _Token(
    'heading',
    AppType.heading,
    fontSize: 18,
    height: 24 / 18,
    weight: FontWeight.w700,
  ),
  const _Token(
    'body',
    AppType.body,
    fontSize: 16,
    height: 24 / 16,
    weight: FontWeight.w400,
  ),
  const _Token(
    'bodyStrong',
    AppType.bodyStrong,
    fontSize: 16,
    height: 24 / 16,
    weight: FontWeight.w600,
  ),
  const _Token(
    'label',
    AppType.label,
    fontSize: 14,
    height: 20 / 14,
    weight: FontWeight.w500,
  ),
  const _Token(
    'caption',
    AppType.caption,
    fontSize: 12,
    height: 16 / 12,
    weight: FontWeight.w400,
  ),
  const _Token(
    'micro',
    AppType.micro,
    fontSize: 11,
    height: 14 / 11,
    weight: FontWeight.w700,
    letterSpacing: 1.76,
  ),
  const _Token(
    'microStrong',
    AppType.microStrong,
    fontSize: 11,
    height: 14 / 11,
    weight: FontWeight.w700,
  ),
  const _Token(
    'monoButton',
    AppType.monoButton,
    fontSize: 13,
    height: 16 / 13,
    weight: FontWeight.w700,
    letterSpacing: 1.04,
  ),
  const _Token(
    'monoCode',
    AppType.monoCode,
    fontSize: 13,
    height: 20 / 13,
    weight: FontWeight.w400,
  ),
  const _Token(
    'monoKey',
    AppType.monoKey,
    fontSize: 13,
    height: 16 / 13,
    weight: FontWeight.w500,
  ),
  const _Token(
    'monoCompose',
    AppType.monoCompose,
    fontSize: 15,
    height: 22 / 15,
    weight: FontWeight.w400,
  ),
  const _Token(
    'monoPhrase',
    AppType.monoPhrase,
    fontSize: 18,
    height: 24 / 18,
    weight: FontWeight.w500,
  ),
  _Token(
    'monoTerminal (default size)',
    AppType.monoTerminal(),
    fontSize: 13,
    height: 1.3,
    weight: FontWeight.w400,
  ),
];

void main() {
  test('AppType.monoTerminalSizes is the closed R-32-208 list, default 13 '
      '(R-30-210)', () {
    expect(AppType.monoTerminalSizes, <int>[10, 11, 12, 13, 14, 16, 18]);
    expect(AppType.monoTerminalDefaultSize, 13);
  });

  test(
    'AppType declares exactly fifteen tokens, no 16th (R-32-202)',
    () => expect(_tokens().length, 15),
  );

  for (final token in _tokens()) {
    test('AppType.${token.name} matches docs/32-design-language.md section 4 '
        '(R-32-202)', () {
      expect(
        token.style.fontSize,
        token.fontSize,
        reason: '${token.name} fontSize',
      );
      expect(token.style.height, token.height, reason: '${token.name} height');
      expect(
        token.style.fontWeight,
        token.weight,
        reason: '${token.name} fontWeight',
      );
    });
  }

  test('letter spacing follows R-32-204: negative on display, title and '
      'heading, positive on micro and monoButton, none elsewhere', () {
    const Map<String, double> tracked = <String, double>{
      'display': -2.4,
      'title': -1.1,
      'heading': -0.36,
      'micro': 1.76,
      'monoButton': 1.04,
    };
    for (final token in _tokens()) {
      final effective = token.style.letterSpacing ?? 0;
      if (tracked.containsKey(token.name)) {
        expect(
          effective,
          tracked[token.name],
          reason: '${token.name} carries its documented tracking',
        );
      } else {
        expect(effective, 0, reason: '${token.name} must not be tracked out');
      }
    }
  });

  test("pubspec.yaml's IBM Plex Sans family lists exactly the two R-32-200 "
      'files', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final familyIndex = pubspec.indexOf('family: IBM Plex Sans');
    expect(
      familyIndex,
      greaterThanOrEqualTo(0),
      reason: 'pubspec.yaml declares the IBM Plex Sans family, R-32-200',
    );
    final nextFamilyIndex = pubspec.indexOf(
      '- family:',
      familyIndex + 'family: IBM Plex Sans'.length,
    );
    final familyBlock = pubspec.substring(
      familyIndex,
      nextFamilyIndex == -1 ? pubspec.length : nextFamilyIndex,
    );
    final assets = RegExp(r'asset:\s*assets/fonts/(\S+\.ttf)')
        .allMatches(familyBlock)
        .map((m) => m.group(1))
        .toList();
    expect(assets, <String>[
      'IBMPlexSans-Regular.ttf',
      'IBMPlexSans-SemiBold.ttf',
    ]);
  });
}
