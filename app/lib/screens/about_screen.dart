/// The About screen and its two licence pages, `docs/90-implementation-plan.md` `WP-21-b`
/// (Phase 21), drawn from `docs/31-mockups/19-about.md` (R-90-010, R-90-011): the app name and
/// version, the targeted Herdr protocol, and the licence index/detail pair R-31-19-15 requires
/// — a package index and a per-package detail page, never one concatenated document, and never
/// `showLicensePage`/`LicensePage` (R-31-19-06).
///
/// Three widgets, three routes, per the mockup's own Navigation section: [AboutScreen] at
/// `/settings/about`, [LicenceIndexScreen] at `/settings/about/licences`, and
/// [LicenceDetailScreen] at `/settings/about/licences/:package`. This file owns none of those
/// routes (R-90-024): `app/lib/routing.dart` (`WP-12-b`, on request) wires them, mirroring
/// `welcome_screen.dart`'s and `notification_settings_screen.dart`'s own established pattern of
/// building a routable screen with no `GoRouter` import.
///
/// The licence list itself is never hand-maintained (R-31-19-04): it comes from
/// `LicenseRegistry.licenses`, the Flutter tool's own build-time collector of every package's
/// `LICENSE` file, including this app's own — `app/LICENSE` (a sibling checkbox this same work
/// package fills, copying the root `LICENSE`) is what makes the Apache-2.0 entry arrive here at
/// all.
library;

import 'dart:async' show unawaited;

import 'package:cupertino_ui/cupertino_ui.dart'
    show
        BorderSide,
        BuildContext,
        Column,
        CrossAxisAlignment,
        CupertinoNavigationBar,
        CupertinoPageScaffold;
import 'package:flutter/foundation.dart'
    show LicenseEntry, LicenseRegistry, TargetPlatform, defaultTargetPlatform;
import 'package:flutter/material.dart' show Icon, SelectableText;
import 'package:flutter/widgets.dart'
    show
        Border,
        Center,
        CustomScrollView,
        EdgeInsets,
        ListView,
        Padding,
        Positioned,
        SafeArea,
        Semantics,
        SizedBox,
        SliverList,
        SliverPadding,
        Stack,
        State,
        StatefulWidget,
        StatelessWidget,
        Text,
        VoidCallback,
        Widget;
import 'package:material_symbols_icons/symbols.dart' show Symbols;
import 'package:material_ui/material_ui.dart'
    show
        AppBar,
        Container,
        Divider,
        PreferredSize,
        Scaffold,
        SelectionArea,
        Size;
import 'package:package_info_plus/package_info_plus.dart' show PackageInfo;

import '../widgets/app_list_row.dart';
import '../widgets/brand_mark.dart';
import '../widgets/eyebrow.dart';
import '../widgets/ground_grid.dart';
import '../widgets/theme/app_color.dart';
import '../widgets/theme/app_size.dart';
import '../widgets/theme/app_space.dart';
import '../widgets/theme/app_type.dart';
import '../widgets/treatments.dart';

bool get _isIos => defaultTargetPlatform == TargetPlatform.iOS;

/// `border.hairline`, per `docs/32-design-language.md` R-32-330.
const double _hairlineWidth = 1;

/// R-10-012: the Herdr socket protocol this build targets, shown as a build constant
/// (R-31-19-03: the label says `targeted` because the number is not a reading).
/// Re-measured 2026-09-02 against Herdr `0.8.2-preview.2026-08-31-b1ff4582e968`
/// (`docs/02-herdr-probe-results.md` R-02-028).
const int targetedHerdrProtocol = 22;

/// `R-03-010`: the exact display name.
const String _displayName = 'Herdr Remote';

/// The app's own pub package name (`app/pubspec.yaml`'s `name:`), the identifier
/// `LicenseRegistry` groups this project's own `LICENSE` entry under. Every other package's
/// row shows its own raw pub name (`Skia`, `go_router`, …) unmodified; only this one row is
/// mapped to the public display name [_displayName], per R-03-010 and R-31-19-05.
const String _ownPackageName = 'herdr_mobile';

/// R-31-19-14's fourth wireframe, verbatim.
const String _bundleFailedTitle = 'The licence list did not load.';
const String _bundleFailedDetail = 'Unable to load asset: NOTICES';
const String _bundleFailedBody =
    'This build shipped without its attributions. No action here can '
    'repair it.';

/// One package's licence entries, grouped from [LicenseRegistry.licenses] (R-31-19-04).
class LicensedPackage {
  const LicensedPackage({required this.name, required this.entries});

  /// The raw package identifier `LicenseRegistry` reports — the app's own pub name for the
  /// app's own row, per [_ownPackageName]; a third-party pub name for every other row.
  final String name;

  final List<LicenseEntry> entries;

  /// [name], mapped to [_displayName] for the app's own row only (R-03-010, R-31-19-05).
  String get displayName => name == _ownPackageName ? _displayName : name;
}

/// Drains [LicenseRegistry.licenses] once and groups every entry by package name, per
/// R-31-19-15: the app's own package first (R-31-19-05), then every other package in
/// case-insensitive alphabetical order. Each entry's own paragraph order is preserved
/// (R-31-19-15.4).
Future<List<LicensedPackage>> loadLicensedPackages() async {
  final Map<String, List<LicenseEntry>> byPackage =
      <String, List<LicenseEntry>>{};
  await for (final entry in LicenseRegistry.licenses) {
    for (final package in entry.packages) {
      byPackage.putIfAbsent(package, () => <LicenseEntry>[]).add(entry);
    }
  }
  final packages = byPackage.entries
      .map((e) => LicensedPackage(name: e.key, entries: e.value))
      .toList();
  packages.sort((a, b) {
    if (a.name == _ownPackageName) {
      return -1;
    }
    if (b.name == _ownPackageName) {
      return 1;
    }
    return a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase());
  });
  return packages;
}

/// The failure state of R-31-19-14: a missing or unparseable `NOTICES` bundle, or a bundle
/// that parsed to no entry at all — one state, no retry.
class BundleFailedBlock extends StatelessWidget {
  const BundleFailedBlock({super.key});

  @override
  Widget build(BuildContext context) {
    final AppColor color = AppColor.of(context);
    return Padding(
      padding: const EdgeInsets.all(AppSpace.space4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Treatment.error(label: _bundleFailedTitle, inStrip: false),
          const SizedBox(height: AppSpace.space2),
          Text(
            _bundleFailedDetail,
            style: AppType.monoCode.copyWith(color: color.fgSecondary),
          ),
          const SizedBox(height: AppSpace.space2),
          Text(
            _bundleFailedBody,
            style: AppType.body.copyWith(color: color.fgPrimary),
          ),
        ],
      ),
    );
  }
}

/// `/settings/about`: the three rows of R-31-19-01, and nothing else.
class AboutScreen extends StatefulWidget {
  const AboutScreen({super.key, this.onOpenLicences});

  /// Callout 4: routes to `/settings/about/licences`. `null` is a deliberate no-op
  /// (R-90-016).
  final VoidCallback? onOpenLicences;

  @override
  State<AboutScreen> createState() => _AboutScreenState();
}

class _AboutScreenState extends State<AboutScreen> {
  String? _version;
  String? _buildNumber;

  @override
  void initState() {
    super.initState();
    unawaited(_loadVersion());
  }

  Future<void> _loadVersion() async {
    final info = await PackageInfo.fromPlatform();
    if (!mounted) {
      return;
    }
    // R-31-19-02: the semantic version, then the platform build number in brackets — the
    // same value `device_info.app_version` sends, read from the same build, never restated.
    setState(() {
      _version = info.version;
      _buildNumber = info.buildNumber;
    });
  }

  @override
  Widget build(BuildContext context) {
    final AppColor color = AppColor.of(context);
    final String? version = _version;
    final String? buildNumber = _buildNumber;
    final String versionLine = version == null
        ? '\u2026'
        : '$version ($buildNumber)';
    // The mockup's accessibility section: `Herdr Remote, version 1.0.0, build 412`, so a
    // screen reader speaks the build number and never a bracket.
    final String heroLabel = version == null
        ? _displayName
        : '$_displayName, version $version, build $buildNumber';

    // The hero block keeps the screen inset of `space.4`; the two rows below it run full
    // width and carry their own `space.4` text inset, so every left edge on the screen is one
    // edge (amended 2026-09-08 by the product owner: the rows sat inside the hero's inset, so
    // their text started 16 px right of the product name and their dividers stopped short).
    final body = GroundGrid(
      child: SafeArea(
        child: Stack(
          children: <Widget>[
            // BrandMark anchored top-right
            Positioned(
              top: 0,
              right: 0,
              child: BrandMark(height: 96, color: color.fgDisabled),
            ),
            // Content
            ListView(
              padding: const EdgeInsets.symmetric(vertical: AppSpace.space4),
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpace.space4,
                  ),
                  child: Semantics(
                    label: heroLabel,
                    excludeSemantics: true,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        const Eyebrow(text: 'ABOUT'),
                        const SizedBox(height: AppSpace.space3),
                        Text(
                          _displayName,
                          style: AppType.title.copyWith(color: color.fgPrimary),
                        ),
                        const SizedBox(height: AppSpace.space1),
                        Text(
                          versionLine,
                          style: AppType.monoCode.copyWith(
                            color: color.fgSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: AppSpace.space6),
                // Herdr protocol row (callout 3): the one-line row of R-32-515 with the
                // value as the trailing word in `type.label` `color.fg.primary`; build-constant
                // information, not a control (R-31-19-03, R-31-19-07), so `isStatic` keeps it
                // `22`.
                AppListRow(
                  primary: 'Herdr protocol targeted',
                  semanticsValue: targetedHerdrProtocol.toString(),
                  trailing: Text(
                    targetedHerdrProtocol.toString(),
                    style: AppType.label.copyWith(color: color.fgPrimary),
                  ),
                  onTap: null,
                  isStatic: true,
                ),
                // Licences row (callout 4): the next level, so the chevron is honest
                // (R-33-072). No gap between two rows of one group (R-30-231).
                AppListRow(
                  primary: 'Licences',
                  secondary: 'This app: Apache-2.0',
                  trailing: Icon(
                    Symbols.chevron_right_rounded,
                    size: AppSize.iconMd,
                    color: color.fgSecondary,
                  ),
                  onTap: widget.onOpenLicences,
                ),
              ],
            ),
          ],
        ),
      ),
    );

    final title = Text(
      'About',
      style: AppType.heading.copyWith(color: color.fgPrimary),
    );

    return _scaffold(color: color, title: title, body: body);
  }
}

/// The app bar of R-32-510 on both platforms: `color.bg.base` with a `border.hairline`
/// `color.border.strong` bottom edge (R-32-115), `type.heading` title, the platform's own back
/// control (R-33-070). The three pages of this file share it; [trailing] is the detail page's
/// licence count.
Widget _scaffold({
  required AppColor color,
  required Widget title,
  required Widget body,
  Widget? trailing,
}) {
  if (_isIos) {
    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        backgroundColor: color.bgBase,
        border: Border(
          bottom: BorderSide(color: color.borderStrong, width: _hairlineWidth),
        ),
        middle: title,
        trailing: trailing,
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
        preferredSize: const Size.fromHeight(_hairlineWidth),
        child: Container(color: color.borderStrong, height: _hairlineWidth),
      ),
      actions: trailing == null
          ? null
          : <Widget>[
              Padding(
                padding: const EdgeInsets.only(right: AppSpace.space4),
                child: Center(child: trailing),
              ),
            ],
    ),
    body: body,
  );
}

/// `/settings/about/licences`: the package index, per R-31-19-15.
class LicenceIndexScreen extends StatefulWidget {
  const LicenceIndexScreen({super.key, this.onOpenPackage});

  /// Callout 6. `null` is a deliberate no-op.
  final void Function(LicensedPackage package)? onOpenPackage;

  @override
  State<LicenceIndexScreen> createState() => _LicenceIndexScreenState();
}

class _LicenceIndexScreenState extends State<LicenceIndexScreen> {
  List<LicensedPackage>? _packages;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final packages = await loadLicensedPackages();
    if (mounted) {
      setState(() => _packages = packages);
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppColor color = AppColor.of(context);
    final packages = _packages;

    // R-03-107 (amended 2026-09-09): the two list pages have content, so they paint plain
    // `color.bg.base` with no ground grid and no paper block; only `/settings/about` itself is
    // a hero. No brand mark and no eyebrow here (decided 2026-09-03 by the product owner).
    final content = SafeArea(
      child: CustomScrollView(
        slivers: <Widget>[
          SliverList.list(
            children: <Widget>[
              if (packages == null)
                const SizedBox.shrink()
              else if (packages.isEmpty)
                const BundleFailedBlock()
              else
                for (final package in packages)
                  AppListRow(
                    primary: package.displayName,
                    secondary:
                        '${package.entries.length} ${package.entries.length == 1 ? 'licence' : 'licences'}',
                    trailing: Icon(
                      Symbols.chevron_right_rounded,
                      size: AppSize.iconMd,
                      color: color.fgSecondary,
                    ),
                    onTap: widget.onOpenPackage == null
                        ? null
                        : () => widget.onOpenPackage!(package),
                    // A null `onOpenPackage` is a deliberate no-op (callout 6),
                    // not a disabled control: R-31-19-07 forbids dimming any row
                    // on these pages, so the unwired row stays at full ink with
                    // its semantics.
                    isStatic: widget.onOpenPackage == null,
                  ),
            ],
          ),
        ],
      ),
    );

    final title = Text(
      'Licences',
      style: AppType.heading.copyWith(color: color.fgPrimary),
    );

    return _scaffold(color: color, title: title, body: content);
  }
}

/// `/settings/about/licences/:package`: one package's licence text, per R-31-19-15.2. The
/// router segment supplies [packageName] (percent-decoded); [entries] comes from whatever
/// already loaded the index — this screen never re-drains [LicenseRegistry.licenses] itself,
/// so the two pages always show the same data from one load.
class LicenceDetailScreen extends StatelessWidget {
  const LicenceDetailScreen({
    super.key,
    required this.packageName,
    required this.entries,
  });

  final String packageName;
  final List<LicenseEntry> entries;

  @override
  Widget build(BuildContext context) {
    final AppColor color = AppColor.of(context);
    final int count = entries.length;

    final title = Text(
      packageName,
      style: AppType.heading.copyWith(color: color.fgPrimary),
    );

    // R-31-19-13: the licence text MUST be selectable. `SelectionArea` wraps the whole body
    // rather than each paragraph individually, so the fix `LicensePage` needs (a
    // `SelectionArea` wrapper, per `docs/31-mockups/19-about.md`'s own analysis) is applied
    // from the start here. R-03-107 (amended 2026-09-09): the text sits on plain
    // `color.bg.base` at its `space.4` inset, no ground grid and no paper block. No brand
    // mark and no eyebrow, like the index (decided 2026-09-03 by the product owner).
    final body = SafeArea(
      child: SelectionArea(
        child: CustomScrollView(
          slivers: <Widget>[
            SliverPadding(
              padding: const EdgeInsets.all(AppSpace.space4),
              sliver: SliverList.list(
                children: <Widget>[
                  for (var i = 0; i < entries.length; i++) ...<Widget>[
                    if (i > 0)
                      Padding(
                        padding: const EdgeInsets.only(
                          top: AppSpace.space4,
                          bottom: AppSpace.space4,
                        ),
                        child: Divider(
                          height: 1,
                          thickness: 1,
                          color: color.borderSubtle,
                        ),
                      ),
                    for (final paragraph in entries[i].paragraphs)
                      Padding(
                        padding: const EdgeInsets.only(bottom: AppSpace.space3),
                        child: SelectableText(
                          paragraph.text,
                          style: AppType.monoCode.copyWith(
                            color: color.fgPrimary,
                          ),
                        ),
                      ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );

    return _scaffold(
      color: color,
      title: title,
      body: body,
      trailing: Text(
        count == 1 ? '1 licence' : '$count licences',
        style: AppType.caption.copyWith(color: color.fgSecondary),
      ),
    );
  }
}
