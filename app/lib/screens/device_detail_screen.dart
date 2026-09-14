/// The Device detail screen (`WP-20-a`, wave 8 of `docs/90-implementation-plan.md`), drawn
/// from `docs/31-mockups/14-devices.md`'s second wireframe. A phone row of
/// `device_list_screen.dart` pushes it as the next level in the hierarchy (R-33-072.1,
/// R-03-105, 2026-09-09; until then a bottom sheet, `device_detail_sheet.dart`, opened from a
/// `Details` control on the row). The push is `Navigator.push`, not a named route: the screen
/// carries the one `device_list` entry the row already holds, which no URL could restate
/// (R-31-14-07 forbids the identity values a URL would need).
///
/// Shows exactly six values, per R-31-14-08: the name in the app bar, then the pair time, the
/// last seen time, the platform and the key fingerprint as the platform's own information
/// rows, and one `Remove` action — nothing else, and no operating system version, because
/// `device_list` carries none (R-11-062). On this phone's own detail the two times sit in the
/// `Health` card of R-03-113 item 6 (2026-09-09) with the App Lock state and the revocation
/// path, each fact still shown once (R-03-058); `platformLabel` and the fingerprint keep their
/// rows below it. The name is never editable here: `docs/31-mockups/14-devices.md`'s own
/// "Retired rules" table retires the older, editable-name draft of R-31-14-05, because no
/// rename message exists in `docs/11-relay-protocol.md` and none is planned, so no phone can
/// rename another (R-31-15-12). The one place a person renames this phone is the row `This
/// phone's name` on `/settings` (`docs/31-mockups/15-appearance.md`), a different package's
/// screen.
library;

import 'package:cupertino_ui/cupertino_ui.dart'
    show CupertinoNavigationBar, CupertinoPageScaffold;
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/widgets.dart'
    show
        Border,
        BorderSide,
        BuildContext,
        Container,
        EdgeInsets,
        ListView,
        Padding,
        PreferredSize,
        SafeArea,
        Semantics,
        Size,
        StatelessWidget,
        Text,
        TextStyle,
        VoidCallback,
        Widget;
import 'package:material_ui/material_ui.dart' show AppBar, Scaffold;

import '../models/messages/device_list_entry.dart';
import '../models/messages/platform.dart' as wire;
import '../services/device_list.dart';
import '../widgets/key_label.dart';
import '../widgets/theme/app_color.dart';
import '../widgets/theme/app_radius.dart';
import '../widgets/theme/app_space.dart';
import '../widgets/theme/app_type.dart';
import '../widgets/theme/chrome_list_row.dart';
import '../widgets/theme/chrome_settings_section.dart';

bool get _isIos => defaultTargetPlatform == TargetPlatform.iOS;

/// The revocation path of the health card (R-03-113 item 6), under the `Health` group of this
/// phone's detail: the `Remove phones` action of the list (R-03-111) and the Host's `r` key,
/// which removes every phone. `{r}` is the inline key of R-32-599.
const String _howToRevoke =
    'How to revoke: Remove phones on the phone list removes one phone or every phone. '
    'The {r} key in the Relay pane on your computer removes every phone.';

/// R-31-14-10: `device_list.platform` renders as exactly one of these two words, never the raw
/// lower case wire value and never a marketing name.
String platformLabel(wire.Platform platform) => switch (platform) {
  wire.Platform.ios => 'iOS',
  wire.Platform.android => 'Android',
};

/// One `label`/`value` row of the four values (R-31-14-08): the platform's own information
/// row, [ChromeListRow.static], with the label as its title and the value at its trailing edge
/// in `type.body` `color.fg.secondary`, the value composition the choice row of
/// `docs/32-design-language.md` section 7.4 already draws, or `type.mono.code` for the
/// fingerprint, the format `docs/13-security-pairing.md` R-13-040 owns. One `label, value`
/// semantics node, per the mockup's own Accessibility section: the row's own node would speak
/// the title alone, so this widget names the pair itself, one level up.
class _ValueRow extends StatelessWidget {
  const _ValueRow({
    required this.label,
    required this.value,
    this.mono = false,
    this.showDivider = true,
  });

  final String label;
  final String value;
  final bool mono;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    final AppColor color = AppColor.of(context);
    final TextStyle style = (mono ? AppType.monoCode : AppType.body).copyWith(
      color: color.fgSecondary,
    );
    return Semantics(
      label: '$label, $value',
      excludeSemantics: true,
      child: ChromeListRow.static(
        title: label,
        trailing: Text(value, style: style),
        showDivider: showDivider,
      ),
    );
  }
}

/// One caption line under a group, on the row text's edge like the group header of
/// R-33-073.1: `space.4`, plus the card margin on iOS, in `type.caption` `color.fg.secondary`.
/// [template] may name a key as `{r}`, drawn as the inline key of R-32-599 and spoken plain.
class _Caption extends StatelessWidget {
  const _Caption(this.template);

  final String template;

  @override
  Widget build(BuildContext context) {
    final AppColor color = AppColor.of(context);
    return Padding(
      padding: EdgeInsets.only(
        left: _isIos ? AppSpace.space4 * 2 : AppSpace.space4,
        right: AppSpace.space4,
        top: AppSpace.space2,
      ),
      child: keyedText(
        template,
        style: AppType.caption.copyWith(color: color.fgSecondary),
        color: color,
      ),
    );
  }
}

/// The screen body. [device] and [isThisPhone] fix which values and which caption lines show
/// (R-31-14-08); [onRemove] is this widget's whole contract with the screen that pushed it —
/// the confirmation dialog and the actual `revoke_device` send both live one level down the
/// stack, in `device_list_screen.dart` (R-90-024), which pops this screen first, so the
/// dialog of R-33-074 opens over the list.
///
/// Every row is the platform row of R-33-073 (R-03-105, 2026-09-09): each value is a
/// [ChromeListRow.static] row in a [ChromeSettingsSection], and `Remove` is the destructive
/// row of `docs/32-design-language.md` section 7.9 ([ChromeListRow.destructive]) alone in its
/// own section. On this phone's detail the first group is the `Health` card of R-03-113 item
/// 6: `Last connected`, `App Lock` and `Pairing`, then the revocation path as its caption; the
/// pair time and the last seen time live there and nowhere else on the screen (R-03-058), so
/// the values group below keeps the platform and the fingerprint. Another phone's detail has
/// no card and keeps all four values in one group. Nothing here is drawn from a box and a
/// gesture; the back control is the platform's own, per R-33-070, so neither app bar sets a
/// `leading`. The screen paints plain `color.bg.base` (R-03-107, amended 2026-09-09).
class DeviceDetailScreen extends StatelessWidget {
  const DeviceDetailScreen({
    super.key,
    required this.device,
    required this.isThisPhone,
    required this.appLockEnabled,
    required this.canRemove,
    required this.onRemove,
  });

  final DeviceListEntry device;

  /// R-31-14-05 and R-03-113 item 6: only the current Device's screen carries the health card
  /// and the rename-hint caption, because a phone cannot rename another and knows only its
  /// own lock state.
  final bool isThisPhone;

  /// This phone's App Lock setting (`docs/03-product-decisions.md` R-03-090), the `App Lock`
  /// row of the health card. Read only when [isThisPhone] is true.
  final bool appLockEnabled;

  /// `false` while offline, while another phone holds the computer, or while a revoke is
  /// already in flight (R-31-14-04, R-31-14-12.1).
  final bool canRemove;

  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final AppColor color = AppColor.of(context);
    final DateTime paired = parseWireTimestamp(device.pairedAt);
    final DateTime lastSeen = parseWireTimestamp(device.lastSeen);
    // A connected phone reads `now` regardless of `last_seen`, as its row does (decided
    // 2026-09-03): the Host stamps `last_seen` on every frame it serves, so a relative time on
    // a connected phone is a stale-read artifact. A phone that is not connected reads the age
    // in the values group, and the age with the time in the health card.
    final String lastSeenLabel = device.connected
        ? 'now'
        : formatLastSeen(lastSeen);
    final String lastConnectedLabel = device.connected
        ? 'now'
        : '${formatLastSeen(lastSeen)} \u00b7 ${formatPairedShort(lastSeen)}';
    // `type.heading`, not `type.title`, because this screen carries a back chevron, matching
    // `device_list_screen.dart`'s own app bar.
    final Widget title = Text(
      device.name,
      style: AppType.heading.copyWith(color: color.fgPrimary),
    );
    final Widget body = SafeArea(
      child: ListView(
        padding: const EdgeInsets.only(bottom: AppSpace.space4),
        children: <Widget>[
          if (isThisPhone) ...<Widget>[
            ChromeSettingsSection(
              header: 'HEALTH',
              rows: <Widget>[
                _ValueRow(label: 'Last connected', value: lastConnectedLabel),
                _ValueRow(
                  label: 'App Lock',
                  value: appLockEnabled ? 'On' : 'Off',
                ),
                _ValueRow(
                  label: 'Pairing',
                  value: 'Paired ${formatPairedFull(paired)}',
                  showDivider: false,
                ),
              ],
            ),
            const _Caption(_howToRevoke),
          ],
          ChromeSettingsSection(
            rows: <Widget>[
              if (!isThisPhone) ...<Widget>[
                _ValueRow(label: 'Paired', value: formatPairedFull(paired)),
                _ValueRow(label: 'Last seen', value: lastSeenLabel),
              ],
              _ValueRow(
                label: 'Platform',
                value: platformLabel(device.platform),
              ),
              _ValueRow(
                label: 'Key fingerprint',
                value: device.fingerprint,
                mono: true,
                showDivider: false,
              ),
            ],
          ),
          if (isThisPhone) const _Caption('Rename this phone in Settings.'),
          ChromeSettingsSection(
            rows: <Widget>[
              ChromeListRow.destructive(
                title: 'Remove',
                onTap: canRemove ? onRemove : null,
                showDivider: false,
              ),
            ],
          ),
        ],
      ),
    );
    // R-32-115, R-32-510: `color.bg.base` with a `border.hairline` `color.border.strong`
    // bottom edge on both platforms, like every other app bar.
    if (_isIos) {
      return CupertinoPageScaffold(
        navigationBar: CupertinoNavigationBar(
          backgroundColor: color.bgBase,
          border: Border(
            bottom: BorderSide(
              color: color.borderStrong,
              width: AppBorder.hairline,
            ),
          ),
          middle: title,
        ),
        child: body,
      );
    }
    return Scaffold(
      backgroundColor: color.bgBase,
      appBar: AppBar(
        backgroundColor: color.bgBase,
        elevation: 0,
        title: title,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(AppBorder.hairline),
          child: Container(
            color: color.borderStrong,
            height: AppBorder.hairline,
          ),
        ),
      ),
      body: body,
    );
  }
}
