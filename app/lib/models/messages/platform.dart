/// A Device operating-system platform (`docs/11-relay-protocol.md` §4.2,
/// §4.19). Mirrors `Platform` in
/// `crates/herdr-relay-proto/src/messages/session.rs:45-51`
/// (`#[serde(rename_all = "snake_case")]`)
/// (`docs/90-implementation-plan.md` §5.2 `WP-5-c`).
library;

import 'package:freezed_annotation/freezed_annotation.dart';

enum Platform {
  @JsonValue('ios')
  ios,
  @JsonValue('android')
  android,
}
