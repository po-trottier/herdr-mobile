/// The four named status treatments from `docs/32-design-language.md`
/// section 7.2 (R-32-506) and `docs/41-code-standards.md` R-41-112. Each
/// places its hue in an icon, and `treat.error` in a strip and
/// `treat.destructive` always add a leading `border.attention` bar; the
/// label stays on `AppColor.fgPrimary`, never the status hue, per
/// R-30-140 and R-30-141.
library;

import 'package:flutter/widgets.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'key_label.dart';
import 'theme/app_color.dart';
import 'theme/app_radius.dart' show AppBorder;
import 'theme/app_size.dart';
import 'theme/app_space.dart';
import 'theme/app_type.dart';

enum _TreatmentKind { ok, warning, error, destructive }

/// One of the four treatments. Use the named constructors
/// [Treatment.ok], [Treatment.warning], [Treatment.error] or
/// [Treatment.destructive]; a message, a state word or a destructive
/// label MUST use one of them and MUST NOT use a bare status colour, per
/// R-32-506.
class Treatment extends StatelessWidget {
  /// A success word, a healthy leg, a connected state.
  const Treatment.ok({super.key, required this.label, this.textAlign})
    : _kind = _TreatmentKind.ok,
      _attentionBar = false;

  /// A warning line, a strip, the `host_in_use` banner, an expiring
  /// countdown.
  const Treatment.warning({super.key, required this.label, this.textAlign})
    : _kind = _TreatmentKind.warning,
      _attentionBar = false;

  /// A failure message and a failure strip. [inStrip] adds the leading
  /// `border.attention` bar that R-32-506 requires only "when the message
  /// sits in a strip".
  const Treatment.error({
    super.key,
    required this.label,
    bool inStrip = false,
    this.textAlign,
  }) : _kind = _TreatmentKind.error,
       _attentionBar = inStrip;

  /// A destructive action label. The hue lives in the glyph alone: a leading
  /// bar is the state bar of R-03-100, and a bar beside a red glyph is two
  /// marks for one fact, which R-03-058 forbids (R-32-527).
  const Treatment.destructive({super.key, required this.label, this.textAlign})
    : _kind = _TreatmentKind.destructive,
      _attentionBar = false;

  /// The treatment's label. Always rendered in `AppColor.fgPrimary`,
  /// never the status hue, per R-30-402.
  final String label;

  /// How the label's lines align when it wraps. `null` is the start edge,
  /// which `docs/30-ux-spec.md` R-30-293 fixes for every screen but
  /// `/lock`, the one place a centred prompt passes `TextAlign.center`.
  final TextAlign? textAlign;

  final _TreatmentKind _kind;
  final bool _attentionBar;

  @override
  Widget build(BuildContext context) {
    final AppColor color = AppColor.of(context);
    final _Glyph glyph = _glyphFor(_kind, color);
    // R-32-402: the icon aligns to the first line of the label, so a label
    // that wraps keeps the icon at the block's start instead of floating
    // between its lines. The offset is the first `type.body` line's centre
    // less half the icon: a composition of the type and size tokens, which
    // for one line equals plain vertical centring.
    final double firstLineOffset =
        (AppType.body.fontSize! * AppType.body.height! - glyph.size) / 2;
    final Widget content = Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: EdgeInsets.only(top: firstLineOffset),
          child: Icon(
            glyph.icon,
            size: glyph.size,
            color: glyph.color,
            fill: 0,
            weight: 400,
            grade: 0,
          ),
        ),
        SizedBox(width: glyph.gap),
        Flexible(
          child: keyedText(
            label,
            textAlign: textAlign,
            style: AppType.body.copyWith(color: color.fgPrimary),
            color: color,
          ),
        ),
      ],
    );
    if (!_attentionBar) {
      return content;
    }
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(
          left: BorderSide(
            color: color.statusError,
            width: AppBorder.attention,
          ),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.only(left: AppSpace.space2),
        child: content,
      ),
    );
  }

  static _Glyph _glyphFor(_TreatmentKind kind, AppColor color) =>
      switch (kind) {
        _TreatmentKind.ok => _Glyph(
          Symbols.check_circle_rounded,
          color.statusOk,
          AppSize.iconSm,
          AppSpace.space2,
        ),
        _TreatmentKind.warning => _Glyph(
          Symbols.warning_rounded,
          color.statusWarning,
          AppSize.iconSm,
          AppSpace.space2,
        ),
        _TreatmentKind.error => _Glyph(
          Symbols.error_rounded,
          color.statusError,
          AppSize.iconSm,
          AppSpace.space2,
        ),
        _TreatmentKind.destructive => _Glyph(
          Symbols.delete_outline_rounded,
          color.statusError,
          AppSize.iconMd,
          AppSpace.space3,
        ),
      };
}

/// The icon, its colour, its size and the gap before the label, for one
/// treatment kind. Private: an implementation detail of [Treatment].
class _Glyph {
  const _Glyph(this.icon, this.color, this.size, this.gap);

  final IconData icon;
  final Color color;
  final double size;
  final double gap;
}
