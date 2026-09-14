/// The inline key of `docs/32-design-language.md` section 7.33 (R-32-599),
/// per `docs/03-product-decisions.md` R-03-103: a key or a chord named in
/// interface text is drawn as a key cap in the sentence, never printed as
/// a plain word. [InlineKey] is one cap; [keyedText] turns a template such
/// as `the {r} key in the Relay pane` into a `Text.rich` whose `{...}`
/// spans are caps on the sentence's own baseline.
library;

import 'package:flutter/widgets.dart';

import 'theme/app_color.dart';
import 'theme/app_radius.dart';
import 'theme/app_space.dart';
import 'theme/app_type.dart';

/// The spoken form of a key name, the words `key_row.dart` already gives its
/// caps: a modifier by its full name, a letter in a chord upper case, a
/// single key as written.
const Map<String, String> _spokenNames = <String, String>{
  'ctrl': 'Control',
  'alt': 'Alt',
  'shift': 'Shift',
  'cmd': 'Command',
  'super': 'Super',
  'esc': 'Escape',
  'tab': 'Tab',
  'enter': 'Enter',
};

final RegExp _keyToken = RegExp(r'\{([^{}]+)\}');

/// One key cap drawn inline: `type.mono.key` in `color.fg.primary` on a
/// `color.bg.high` box with a `border.hairline` in `color.border.strong`
/// and `radius.sm`, padded `space.1` sideways and `space.0` vertically,
/// per R-32-599. Its semantics label is the spoken key name, so a cap on
/// its own reads as the key and not as a box.
class InlineKey extends StatelessWidget {
  const InlineKey({super.key, required this.label, this.color});

  /// The key as written on a cap: `r`, `d`, `Enter`, `ctrl+c`.
  final String label;

  /// The palette the cap draws with; resolved from the context when null.
  final AppColor? color;

  /// How a screen reader says [label]: `r` stays `r`, `ctrl+c` reads
  /// `Control C`, `esc` reads `Escape`.
  static String spoken(String label) {
    final List<String> parts = label.split('+');
    if (parts.length == 1) return _spokenNames[label] ?? label;
    return parts
        .map((String part) => _spokenNames[part] ?? part.toUpperCase())
        .join(' ');
  }

  @override
  Widget build(BuildContext context) {
    final AppColor color = this.color ?? AppColor.of(context);
    return Semantics(
      label: spoken(label),
      excludeSemantics: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: color.bgHigh,
          borderRadius: BorderRadius.circular(AppRadius.sm),
          border: Border.all(
            color: color.borderStrong,
            width: AppBorder.hairline,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpace.space1,
            vertical: AppSpace.space0,
          ),
          child: Text(
            label,
            style: AppType.monoKey.copyWith(color: color.fgPrimary),
          ),
        ),
      ),
    );
  }
}

/// [template] with every `{key}` replaced by its spoken name: the sentence
/// a screen reader gets from [keyedText], and the sentence to announce.
String keyedPlain(String template) => template.replaceAllMapped(
  _keyToken,
  (Match match) => InlineKey.spoken(match[1]!),
);

/// [template] as one `Text.rich`: the prose in [style], every `{key}` an
/// [InlineKey] on the alphabetic baseline, and the whole sentence read as
/// [keyedPlain] of the template. [color] is the palette the caps draw with.
Text keyedText(
  String template, {
  required TextStyle style,
  required AppColor color,
  TextAlign? textAlign,
}) {
  final List<InlineSpan> spans = <InlineSpan>[];
  int last = 0;
  for (final Match match in _keyToken.allMatches(template)) {
    if (match.start > last) {
      spans.add(TextSpan(text: template.substring(last, match.start)));
    }
    spans.add(
      WidgetSpan(
        alignment: PlaceholderAlignment.baseline,
        baseline: TextBaseline.alphabetic,
        child: InlineKey(label: match[1]!, color: color),
      ),
    );
    last = match.end;
  }
  if (last < template.length) {
    spans.add(TextSpan(text: template.substring(last)));
  }
  return Text.rich(
    TextSpan(style: style, children: spans),
    textAlign: textAlign,
    semanticsLabel: keyedPlain(template),
  );
}
