/// `send_input` (`docs/11-relay-protocol.md` §4.12). Sender: Device. Reply:
/// `send_input_ack`. Correlation: yes. Mirrors `SendInput` in
/// `crates/herdr-relay-proto/src/messages/input.rs:6-19`
/// (`docs/90-implementation-plan.md` §5.2 `WP-5-c`). The bridge resolves the
/// four-step key order of R-11-054 and maps to the correct Herdr method
/// (R-11-056).
library;

import 'package:freezed_annotation/freezed_annotation.dart';

part 'send_input.freezed.dart';
part 'send_input.g.dart';

@freezed
abstract class SendInput with _$SendInput {
  const factory SendInput({
    @JsonKey(name: 'pane_id') required String paneId,

    /// Complete composer text, including an empty line.
    @JsonKey(includeIfNull: false) String? line,

    /// Literal text: printable characters and the six unnamed keys as raw
    /// sequences (R-10-036).
    @JsonKey(includeIfNull: false) String? text,

    /// Named keys, for example `["Enter"]` or `["ctrl+c"]`
    /// (R-10-036 to R-10-039).
    @JsonKey(includeIfNull: false) String? defer,
    @JsonKey(includeIfNull: false) List<String>? keys,

    /// R-11-254: forward `text`/`keys` past the pane's line shadow, so an
    /// answer send never touches the held composer draft. Valid only with
    /// `text` and/or `keys`, never with `line` or `defer`. Carried on the
    /// wire only when true.
    @JsonKey(name: 'bypass_line', includeIfNull: false) bool? bypassLine,
  }) = _SendInput;

  factory SendInput.fromJson(Map<String, dynamic> json) =>
      _$SendInputFromJson(json);
}
