/// The Device's pairing service (Phase 15, `WP-15-a`): the `herdr-remote://pair` URI codec
/// (`docs/11-relay-protocol.md` §9, R-11-140), the six-word phrase codec
/// (`docs/13-security-pairing.md` R-13-017 to R-13-027), the QR scanner wrapper, and the
/// point where the QR path, the manual-entry path and the deep-link path converge on one
/// [PairingInput] record (R-13-026, R-11-140, R-03-071) — this file's published contract for
/// `WP-15-b` and `WP-15-c`. It also drives one first-pairing `Noise_XXpsk0` handshake to
/// completion ([attemptPairing]) and persists a successful one ([persistPairing]).
///
/// This file owns no screen. `app/lib/screens/qr_scan_screen.dart`,
/// `welcome_screen.dart` and `manual_pairing_screen.dart` (`WP-15-b`, `WP-15-c`) paint every
/// state this file raises; this file only parses, validates and drives the handshake
/// (R-90-024).
///
/// The EFF long word list (R-13-017, 7776 entries) is never fetched by this file, and never
/// by any code that ships in the app: `AGENTS.md`'s "Never build" rule forbids an HTTP
/// client in the app outright ("the app persists no terminal content by design, and one
/// WebSocket carries everything", R-01-013). [loadEffWordlist] only ever reads an
/// already-bundled, already-normalised Flutter asset; the download and the BLAKE2s-256
/// checksum verification against the exact digest
/// `crates/herdr-relay/src/pairing/wordlist.rs`'s `RAW_SOURCE_CHECKSUM_BLAKE2S256_HEX`
/// records happen once, against the raw source bytes, in `app/tool/fetch_eff_wordlist.dart`
/// — a build-time dev tool that never compiles into the shipped binary, mirroring that same
/// Host file's `curl`/`wget` shell-out, which `AGENTS.md` treats as a separate, permitted
/// case from the app's own "Never build". See [loadEffWordlist]'s own doc comment for the
/// exact split.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:mobile_scanner/mobile_scanner.dart';

import '../core/result/result.dart' show Err, Ok, Result;
import '../models/messages/device_info.dart';
import 'biometric_gate.dart';
import 'keystore.dart' show HostSecrets, KeystoreService;
import 'noise.dart' show hostFingerprint, pskFromPhrase;
import 'origin.dart';
import 'plain_store.dart' show PairedHostRecord, PlainStore;
import 'relay.dart';

/// The pairing URI scheme (R-03-013).
const String _pairingUriScheme = 'herdr-remote';

/// The pairing URI's maximum total length in bytes (R-11-141).
const int _pairingUriMaxLen = 512;

/// The routing handle's raw size in bytes (R-11-112).
const int _handleBytes = 16;

/// The routing handle's encoded length: 22 unpadded base64url characters (R-11-112).
const int _handleLen = 22;

/// The number of words in a pairing phrase (R-13-017).
const int _phraseWordCount = 6;

/// The exact size of the EFF long wordlist (R-13-025).
const int _effWordlistEntryCount = 7776;

/// The build-time-bundled asset [loadEffWordlist] reads. See this file's own header comment
/// for why this is a bundled asset, never a runtime fetch.
const String _effWordlistAssetPath = 'assets/wordlists/eff_large_wordlist.txt';

/// `docs/11-relay-protocol.md` §9.5's pairing-URI-structure failure codes, excluding the two
/// relay-origin codes `origin.dart`'s [RelayOriginErrorCode] already owns, and excluding the
/// six phrase codes [PhraseErrorCode] owns. Mirrors
/// `crates/herdr-relay-proto/src/handle.rs`'s `PairingUriError::code()`.
enum PairingUriErrorCode {
  /// The scheme is not `herdr-remote`.
  scheme('pair_uri_scheme'),

  /// The path is not `pair`.
  path('pair_uri_path'),

  /// `v` is absent, or is not `1`.
  version('pair_uri_version'),

  /// `r`, `h` or `p` is absent.
  fieldMissing('pair_uri_field_missing'),

  /// A field appears more than once.
  fieldRepeated('pair_uri_field_repeated'),

  /// The URI exceeds 512 bytes.
  tooLong('pair_uri_too_long'),

  /// `h` is not 22 unpadded base64url characters decoding to 16 bytes.
  handleMalformed('handle_malformed');

  const PairingUriErrorCode(this.wireValue);

  /// The exact string this code appears as in `docs/11-relay-protocol.md` §9.5.
  final String wireValue;
}

/// The six pairing-phrase validation failure codes (R-13-027,
/// `docs/11-relay-protocol.md` §9.5). Mirrors [`PhraseErrorCode`] in
/// `crates/herdr-relay-proto/src/codes.rs:161-175`. No generated Dart mirror of this exists:
/// `WP-5-c`'s `app/lib/models/` mirror stops at the message envelope and `ErrorCode`; this
/// codec is Device-only, like `noise.dart`'s hand-rolled Noise state machine, so this is a
/// fresh, exact definition, not an import.
enum PhraseErrorCode {
  /// The phrase does not hold exactly six words. Raised locally, before any network attempt,
  /// by [validatePhrase].
  phraseWordCount('phrase_word_count'),

  /// A word is not in the EFF long list. Raised locally by [validatePhrase].
  phraseWordUnknown('phrase_word_unknown'),

  /// An empty word, a repeated hyphen, a leading or trailing hyphen, or whitespace inside
  /// the phrase. Raised locally by [validatePhrase].
  phraseSeparator('phrase_separator'),

  /// A character is not lowercase ASCII after normalisation. Raised locally by
  /// [validatePhrase].
  phraseCase('phrase_case'),

  /// More than 600 seconds elapsed since the Host generated the phrase. Raised only after a
  /// network handshake attempt, by [attemptPairing] (relay close `4000` `pairing_expired`,
  /// R-13-022).
  phraseExpired('phrase_expired'),

  /// More than three failed handshake attempts used this phrase. Raised only after a network
  /// handshake attempt, by [attemptPairing] ([PairingAttemptTracker] — see that class's doc
  /// comment for why this is tracked client-side).
  phraseAttempts('phrase_attempts');

  const PhraseErrorCode(this.wireValue);

  /// The exact string this code appears as in `docs/11-relay-protocol.md` §9.5.
  final String wireValue;
}

/// Set as an [Err.cause] when [parsePairingUri] or [buildManualPairingInput] rejects a
/// malformed URI structure or handle. [message] is a generic, static description — never the
/// candidate text, which may carry the routing handle or the phrase (`AGENTS.md` "Never
/// log").
final class PairingUriException implements Exception {
  const PairingUriException(this.code, this.message);
  final PairingUriErrorCode code;
  final String message;
  @override
  String toString() => message;
}

/// Set as an [Err.cause] when [validatePhrase] rejects a phrase, or when [attemptPairing]
/// maps a network-level failure onto `phrase_expired`/`phrase_attempts`. [message] is a
/// generic, static description — never the candidate phrase text (`AGENTS.md` "Never log").
final class PhraseException implements Exception {
  const PhraseException(this.code, this.message);
  final PhraseErrorCode code;
  final String message;
  @override
  String toString() => message;
}

/// Set as an [Err.cause] when [loadEffWordlist] cannot produce a usable word list: the
/// bundled asset is missing, unreadable, or does not hold exactly 7776 entries (R-13-025).
final class WordlistException implements Exception {
  const WordlistException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// The one pairing input every entry path — QR scan, manual entry, deep link — converges on
/// (R-11-140, R-13-026, R-03-071). `WP-15-b` and `WP-15-c`'s screens consume this directly;
/// none of them re-parses a URI or re-validates a phrase.
final class PairingInput {
  const PairingInput({
    required this.relayOrigin,
    required this.handle,
    required this.phrase,
  });

  final RelayOrigin relayOrigin;

  /// The 22-character unpadded base64url routing handle text, already structurally validated
  /// (`handle_malformed` on failure), used directly as the `/device/<handle>` path segment
  /// (R-11-110) — never decoded to raw bytes, since nothing on the Device needs the bytes.
  final String handle;

  /// The canonical hyphenated six-word phrase (R-13-019), already fully validated against the
  /// EFF long list.
  final String phrase;

  @override
  bool operator ==(Object other) =>
      other is PairingInput &&
      other.relayOrigin == relayOrigin &&
      other.handle == handle &&
      other.phrase == phrase;

  @override
  int get hashCode => Object.hash(relayOrigin, handle, phrase);

  // `AGENTS.md` "Never log": the handle and the phrase never appear in a printable string.
  @override
  String toString() =>
      'PairingInput(relayOrigin: $relayOrigin, handle: <redacted>, phrase: <redacted>)';
}

final class _QueryFields {
  String? version;
  String? relayOrigin;
  String? handle;
  String? phrase;
}

Result<_QueryFields> _parseQuery(String query) {
  final fields = _QueryFields();
  for (final pair in query.split('&')) {
    final eq = pair.indexOf('=');
    if (eq < 0) {
      return const Err(
        'parse pairing URI',
        cause: PairingUriException(
          PairingUriErrorCode.fieldMissing,
          'The pairing URI is missing a required field.',
        ),
      );
    }
    final key = pair.substring(0, eq);
    final rawValue = pair.substring(eq + 1);
    if (key != 'v' && key != 'r' && key != 'h' && key != 'p') {
      continue;
    }
    final already = switch (key) {
      'v' => fields.version,
      'r' => fields.relayOrigin,
      'h' => fields.handle,
      _ => fields.phrase,
    };
    if (already != null) {
      return const Err(
        'parse pairing URI',
        cause: PairingUriException(
          PairingUriErrorCode.fieldRepeated,
          'A pairing URI field appears more than once.',
        ),
      );
    }
    final value = key == 'r' ? _percentDecode(rawValue) : rawValue;
    switch (key) {
      case 'v':
        fields.version = value;
      case 'r':
        fields.relayOrigin = value;
      case 'h':
        fields.handle = value;
      case 'p':
        fields.phrase = value;
    }
  }
  return Ok(fields);
}

/// Percent-decodes [input] leniently (an unrecognised `%XY` escape passes through literally),
/// mirroring `crates/herdr-relay-proto/src/handle.rs`'s `percent_decode` exactly.
String _percentDecode(String input) {
  final inputBytes = input.codeUnits;
  final out = <int>[];
  var i = 0;
  while (i < inputBytes.length) {
    if (inputBytes[i] == 0x25 /* % */ && i + 3 <= inputBytes.length) {
      final hex = String.fromCharCodes(inputBytes.sublist(i + 1, i + 3));
      final value = int.tryParse(hex, radix: 16);
      if (value != null) {
        out.add(value);
        i += 3;
        continue;
      }
    }
    out.add(inputBytes[i]);
    i += 1;
  }
  return utf8.decode(out, allowMalformed: true);
}

/// Validates a routing handle candidate: exactly 22 unpadded base64url characters decoding to
/// 16 bytes (R-11-112). Mirrors `crates/herdr-relay-proto/src/handle.rs`'s `Handle::from_str`.
Result<String> _validateHandle(String candidate) {
  const malformed = Err<String>(
    'validate routing handle',
    cause: PairingUriException(
      PairingUriErrorCode.handleMalformed,
      'The routing handle is not 22 unpadded base64url characters.',
    ),
  );
  if (candidate.length != _handleLen) {
    return malformed;
  }
  try {
    final decoded = base64Url.decode(base64Url.normalize(candidate));
    if (decoded.length != _handleBytes) {
      return malformed;
    }
  } on FormatException {
    return malformed;
  }
  return Ok(candidate);
}

/// Normalises manual entry before validation (R-13-026): trims outer whitespace, lowercases
/// ASCII letters, and collapses a run of spaces or hyphens to one hyphen. Mirrors
/// `crates/herdr-relay-proto/src/phrase.rs`'s `normalize` exactly, including that a leading
/// or trailing hyphen survives as a length-one run, so [validatePhrase] can still reject it as
/// [PhraseErrorCode.phraseSeparator].
String normalizePhraseInput(String input) {
  final whitespace = RegExp(r'\s', unicode: true);
  final trimmed = input.trim();
  final out = StringBuffer();
  var lastWasSeparator = false;
  for (var i = 0; i < trimmed.length; i++) {
    final ch = trimmed[i];
    if (ch == '-' || whitespace.hasMatch(ch)) {
      if (!lastWasSeparator) {
        out.write('-');
      }
      lastWasSeparator = true;
    } else {
      out.write(ch.toLowerCase());
      lastWasSeparator = false;
    }
  }
  return out.toString();
}

/// Greedily segments [parts] (the naive tokens of [normalized] split on every `-`) into
/// dictionary words, merging two adjacent tokens with a hyphen when [words] holds that
/// hyphenated form. Mirrors `crates/herdr-relay-proto/src/phrase.rs`'s `segment_words`
/// exactly — see that function's own doc comment for why a single lookahead is unambiguous
/// against the real EFF long list's four internal-hyphen entries (`drop-down`, `felt-tip`,
/// `t-shirt`, `yo-yo`).
List<String> _segmentWords(
  String normalized,
  List<String> parts,
  List<String> words,
) {
  final spans = <(int, int)>[];
  var offset = 0;
  for (final part in parts) {
    final start = offset;
    final end = start + part.length;
    spans.add((start, end));
    offset =
        end +
        1; // skip the hyphen separator normalizePhraseInput guarantees here
  }
  final segmented = <String>[];
  var i = 0;
  while (i < parts.length) {
    if (i + 1 < parts.length) {
      final joined = normalized.substring(spans[i].$1, spans[i + 1].$2);
      if (words.contains(joined)) {
        segmented.add(joined);
        i += 2;
        continue;
      }
    }
    segmented.add(parts[i]);
    i += 1;
  }
  return segmented;
}

bool _isLowercaseAscii(String word) {
  for (var i = 0; i < word.length; i++) {
    final code = word.codeUnitAt(i);
    if (code < 0x61 || code > 0x7a) {
      return false;
    }
  }
  return true;
}

/// Parses and validates a candidate phrase, normalising it first (R-13-026). [words] MUST
/// hold exactly [_effWordlistEntryCount] entries. Returns the first structural failure the
/// candidate exhibits, in the order separator, case, word count, then word membership —
/// mirrors `crates/herdr-relay-proto/src/phrase.rs`'s `Phrase::parse_canonical` exactly.
Result<String> validatePhrase(String candidate, List<String> words) {
  if (words.length != _effWordlistEntryCount) {
    return Err(
      'validate pairing phrase',
      cause: WordlistException(
        'word list does not hold exactly $_effWordlistEntryCount entries, '
        'found ${words.length}',
      ),
    );
  }
  final normalized = normalizePhraseInput(candidate);
  final parts = normalized.split('-');
  if (parts.any((word) => word.isEmpty)) {
    return const Err(
      'validate pairing phrase',
      cause: PhraseException(
        PhraseErrorCode.phraseSeparator,
        'phrase has an empty word, a repeated hyphen, or a leading or trailing hyphen',
      ),
    );
  }
  if (parts.any((word) => !_isLowercaseAscii(word))) {
    return const Err(
      'validate pairing phrase',
      cause: PhraseException(
        PhraseErrorCode.phraseCase,
        'phrase contains a character that is not lowercase ASCII after normalisation',
      ),
    );
  }
  final segmented = _segmentWords(normalized, parts, words);
  if (segmented.length != _phraseWordCount) {
    return const Err(
      'validate pairing phrase',
      cause: PhraseException(
        PhraseErrorCode.phraseWordCount,
        'phrase does not hold exactly $_phraseWordCount words',
      ),
    );
  }
  if (segmented.any((word) => !words.contains(word))) {
    return const Err(
      'validate pairing phrase',
      cause: PhraseException(
        PhraseErrorCode.phraseWordUnknown,
        'phrase contains a word that is not in the EFF long list',
      ),
    );
  }
  return Ok(segmented.join('-'));
}

/// Splits a pasted phrase candidate into its constituent words (R-30-907, R-31-03-03):
/// normalises first (R-13-026), then segments exactly as [validatePhrase] will, so a pasted
/// internal-hyphen EFF word (e.g. `t-shirt`) fills one field, not two. Returns however many
/// words the paste actually contained — validating the count and every word is
/// [validatePhrase]'s job; R-30-907 requires the screen to "fill the six fields from word 1
/// ... so the person always sees exactly what was accepted", which needs the raw split even
/// when it is wrong.
///
/// A value that is still a prefix of one dictionary word is one word being typed, not a
/// paste, and returns a single element. Without this, typing `yo-yo` reaches `yo-y` and
/// splits into two tokens no entry joins, the paste path fires, clears every field and
/// reports word 1 as unknown. Measured live on the emulator against a real phrase whose
/// first word was one of the four internal-hyphen entries.
List<String> splitPastedPhrase(String pasted, List<String> words) {
  final normalized = normalizePhraseInput(pasted);
  if (normalized.isEmpty) {
    return const [];
  }
  if (words.any((word) => word.startsWith(normalized))) {
    return <String>[normalized];
  }
  return _segmentWords(normalized, normalized.split('-'), words);
}

/// Prefix-autocomplete suggestions for one manual-entry word field (R-30-904): at most
/// [maxSuggestions] EFF long-list entries starting with [prefix], only once [prefix] holds at
/// least two characters ("after the second character"). An exact prefix match only, never a
/// fuzzy or edit-distance match (R-30-909: validation MUST NOT correct a word or accept a
/// near match).
List<String> autocompleteWords(
  String prefix,
  List<String> words, {
  int maxSuggestions = 6,
}) {
  if (prefix.length < 2) {
    return const [];
  }
  final lowerPrefix = prefix.toLowerCase();
  final matches = <String>[];
  for (final word in words) {
    if (word.startsWith(lowerPrefix)) {
      matches.add(word);
      if (matches.length >= maxSuggestions) {
        break;
      }
    }
  }
  return matches;
}

Result<PairingInput> _assemblePairingInput({
  required String relayOriginText,
  required String handleText,
  required String phraseText,
  required List<String> effWords,
}) {
  final originResult = parseRelayOrigin(relayOriginText);
  if (originResult is Err<RelayOrigin>) {
    return Err(originResult.message, cause: originResult.cause);
  }
  final handleResult = _validateHandle(handleText);
  if (handleResult is Err<String>) {
    return Err(handleResult.message, cause: handleResult.cause);
  }
  final phraseResult = validatePhrase(phraseText, effWords);
  if (phraseResult is Err<String>) {
    return Err(phraseResult.message, cause: phraseResult.cause);
  }
  return Ok(
    PairingInput(
      relayOrigin: (originResult as Ok<RelayOrigin>).value,
      handle: (handleResult as Ok<String>).value,
      phrase: (phraseResult as Ok<String>).value,
    ),
  );
}

/// Parses and validates a `herdr-remote://pair` pairing URI (R-11-140), from a QR scan or a
/// deep link, against every code in `docs/11-relay-protocol.md` §9.5. Accepts fields in any
/// order (R-11-140: "A parser MUST accept any order"). [effWords] MUST hold exactly
/// [_effWordlistEntryCount] entries (from [loadEffWordlist]).
///
/// Mirrors `crates/herdr-relay-proto/src/handle.rs`'s `PairingUri::parse` exactly, composed
/// with [_validateHandle], [validatePhrase] and `origin.dart`'s [parseRelayOrigin] so a QR
/// scan and a deep link converge on the exact same validation path manual entry uses
/// ([buildManualPairingInput], both call [_assemblePairingInput]).
Result<PairingInput> parsePairingUri(String uri, List<String> effWords) {
  if (utf8.encode(uri).length > _pairingUriMaxLen) {
    return const Err(
      'parse pairing URI',
      cause: PairingUriException(
        PairingUriErrorCode.tooLong,
        'The pairing URI exceeds 512 bytes.',
      ),
    );
  }
  const schemePrefix = '$_pairingUriScheme://';
  if (!uri.startsWith(schemePrefix)) {
    return const Err(
      'parse pairing URI',
      cause: PairingUriException(
        PairingUriErrorCode.scheme,
        'The pairing URI scheme is not herdr-remote.',
      ),
    );
  }
  final rest = uri.substring(schemePrefix.length);
  final queryIndex = rest.indexOf('?');
  if (queryIndex < 0) {
    return const Err(
      'parse pairing URI',
      cause: PairingUriException(
        PairingUriErrorCode.fieldMissing,
        'The pairing URI is missing a required field.',
      ),
    );
  }
  final path = rest.substring(0, queryIndex);
  final query = rest.substring(queryIndex + 1);
  if (path != 'pair') {
    return const Err(
      'parse pairing URI',
      cause: PairingUriException(
        PairingUriErrorCode.path,
        'The pairing URI path is not pair.',
      ),
    );
  }

  final fieldsResult = _parseQuery(query);
  if (fieldsResult is Err<_QueryFields>) {
    return Err(fieldsResult.message, cause: fieldsResult.cause);
  }
  final fields = (fieldsResult as Ok<_QueryFields>).value;

  if (fields.version != '1') {
    return const Err(
      'parse pairing URI',
      cause: PairingUriException(
        PairingUriErrorCode.version,
        'v is absent, or is not 1.',
      ),
    );
  }
  final relayOriginText = fields.relayOrigin;
  final handleText = fields.handle;
  final phraseText = fields.phrase;
  if (relayOriginText == null || handleText == null || phraseText == null) {
    return const Err(
      'parse pairing URI',
      cause: PairingUriException(
        PairingUriErrorCode.fieldMissing,
        'r, h or p is absent.',
      ),
    );
  }

  return _assemblePairingInput(
    relayOriginText: relayOriginText,
    handleText: handleText,
    phraseText: phraseText,
    effWords: effWords,
  );
}

/// Whether [rawValue] is a `herdr-remote://pair` payload this service will attempt to parse.
/// Every other QR payload is `not one of ours` (R-31-02-02); the screen shows the unreadable
/// state without ever calling [parsePairingUri] on it (R-03-013).
bool isPairingPayload(String rawValue) =>
    rawValue.startsWith('$_pairingUriScheme://');

/// Builds and validates the pairing input from manual entry (R-22-032, R-30-921): the relay
/// origin field, the computer-code (handle) field, and the six word fields joined with
/// spaces. Manual entry and QR entry MUST converge on one identical [PairingInput] record
/// (R-13-026, R-11-140, R-03-071); this function and [parsePairingUri] both route through
/// [_assemblePairingInput], so this is a structural guarantee, not a coincidence of matching
/// output shapes.
Result<PairingInput> buildManualPairingInput({
  required String relayOriginText,
  required String handleText,
  required String phraseText,
  required List<String> effWords,
}) => _assemblePairingInput(
  relayOriginText: relayOriginText,
  handleText: handleText,
  phraseText: phraseText,
  effWords: effWords,
);

/// Wraps [MobileScannerController], restricted to the QR format only (R-03-070, R-22-029),
/// for `qr_scan_screen.dart` (`WP-15-b`) to embed. This file owns the camera lifecycle
/// methods R-31-02-03 and Android 14+'s while-in-use release requirement (R-22-031) call for;
/// only a widget can observe `didChangeAppLifecycleState`, so the screen calls [pause] on
/// focus loss and [dispose] on dismissal, mirroring [RelayConnection.noteLifecycleChange]'s
/// own "a widget calls in, this file never listens itself" pattern.
final class PairingScanner {
  PairingScanner({MobileScannerController? controller})
    : controller =
          controller ??
          MobileScannerController(formats: const [BarcodeFormat.qrCode]);

  /// The wrapped controller, exposed for `MobileScanner(controller: ...)` — the screen builds
  /// the camera preview widget itself; this file paints nothing (R-90-024).
  final MobileScannerController controller;

  /// Every scanned barcode's raw text, `null` for a detection with no decodable value. The
  /// screen decides how to react to each value, calling [isPairingPayload] itself
  /// (R-31-02-02's `not one of ours` state).
  Stream<String?> get scannedValues => controller.barcodes.map(
    (capture) =>
        capture.barcodes.isEmpty ? null : capture.barcodes.first.rawValue,
  );

  /// Stops the camera (R-31-02-03, R-22-031): call on focus loss. The camera can restart with
  /// [MobileScannerController.start].
  Future<void> pause() => controller.pause();

  /// Releases the camera entirely (R-22-031's "release... when the scanner view is
  /// dismissed"): call when the scanner route is popped.
  Future<void> dispose() => controller.dispose();
}

/// Loads the build-time-bundled EFF long word list (7776 entries, R-13-017) for
/// [autocompleteWords] and [validatePhrase]'s word-membership checks.
///
/// The list is never fetched by this function, and never by any code that ships in the app:
/// `AGENTS.md`'s "Never build" rule forbids an HTTP client in the app outright (one WebSocket
/// carries everything, R-01-013). The download and the BLAKE2s-256 checksum verification
/// against the exact digest `crates/herdr-relay/src/pairing/wordlist.rs`'s
/// `RAW_SOURCE_CHECKSUM_BLAKE2S256_HEX` records happen once, against the raw source bytes, in
/// `app/tool/fetch_eff_wordlist.dart` — a build-time dev tool that never compiles into the
/// shipped binary, mirroring that same Host file's `curl`/`wget` shell-out, which
/// `AGENTS.md` treats as a separate, permitted case from the app's own "Never build". That
/// tool writes the checksum-verified, normalised list to [_effWordlistAssetPath], a
/// gitignored asset `app/pubspec.yaml` bundles: the same "generated, gitignored,
/// build-step-produced, code depends on it" shape this repository already uses for
/// `*.freezed.dart`/`*.g.dart` (`app/.gitignore`).
///
/// This function only ever reads that already-verified, already-bundled asset via
/// [assetLoader] and checks it holds exactly [_effWordlistEntryCount] entries — a corruption
/// sanity check, not a second checksum: a byte-for-byte re-verification is impossible here by
/// construction, since the bundled asset is the build tool's *normalised* output (one word
/// per line) and the recorded checksum is of the *raw* downloaded source (the
/// `<dice-roll>\t<word>` file), which are never byte-identical. Flutter's own asset bundling
/// already gives this statically-packaged, read-only resource the same tamper-resistance as
/// the rest of the compiled app.
///
/// [assetLoader] lets a test inject a small fixture instead of the real 7776-entry bundled
/// asset (mirrors [RelayConnection]'s own `ChannelFactory` injection seam).
Future<Result<List<String>>> loadEffWordlist({
  Future<Uint8List> Function()? assetLoader,
}) async {
  try {
    final bytes = await (assetLoader ?? _loadBundledWordlistAsset)();
    final words = _parseWordlistAsset(utf8.decode(bytes));
    if (words.length != _effWordlistEntryCount) {
      return Err(
        'load EFF word list',
        cause: WordlistException(
          'word list does not hold exactly $_effWordlistEntryCount entries, '
          'found ${words.length}',
        ),
      );
    }
    return Ok(words);
  } on Exception catch (e) {
    return Err('load EFF word list', cause: e);
  }
}

Future<Uint8List> _loadBundledWordlistAsset() async {
  final data = await rootBundle.load(_effWordlistAssetPath);
  return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
}

List<String> _parseWordlistAsset(String raw) => raw
    .split('\n')
    .map((line) => line.trim())
    .where((line) => line.isNotEmpty)
    .toList();

/// The outcome of a completed first-pairing handshake (R-13-035 step 9): what a caller needs
/// to show the confirmation screen's fingerprint (R-13-041) and to persist the pairing
/// ([persistPairing]).
final class PairingOutcome {
  const PairingOutcome({
    required this.hostId,
    required this.hostName,
    required this.hostStaticPublicKey,
    required this.hostFingerprintText,
    required this.connectedAt,
  });

  /// The Host's pairing identifier (R-13-048), for `plain_store.dart`'s
  /// `PairedHostRecord.hostId` and for routing.
  final String hostId;

  /// The Host's display name from `host_info`, rewritten on every connection (R-13-065).
  final String hostName;

  /// The Host's pinned Noise static public key (R-13-048), for `keystore.dart`'s
  /// `HostSecrets.hostStaticPublicKey`.
  final Uint8List hostStaticPublicKey;

  /// The display fingerprint (R-13-040, R-13-041), already computed via `noise.dart`'s
  /// `hostFingerprint`, ready for the pairing confirmation screen.
  final String hostFingerprintText;

  /// When `connect()` returned `Ok`: the link-open time R-13-065 defines as a contact. Taken
  /// here, not at persistence, because the confirmation step can hold the outcome for as long
  /// as the person looks at the fingerprint.
  final DateTime connectedAt;
}

/// Tracks failed first-pairing handshake attempts against ONE phrase, so a caller retrying
/// `Pair` with the same six words can distinguish the third consecutive failure
/// (`phrase_attempts`, R-13-023) from an ordinary retry. The wire protocol carries no attempt
/// count (`docs/11-relay-protocol.md` §7.1's `handshake_failed` row has no attempts field);
/// the Host's own three-strikes counter (`crates/herdr-relay/src/pairing.rs`'s
/// `PairingSession`) is private to its side of the connection. This mirrors that same rule on
/// the Device, scoped to the exact phrase text a retry keeps using, so the two counters stay
/// in lockstep as long as the phrase does not change out from under a retry loop. One
/// instance MUST be reused across retries of the same manual-entry attempt (a fresh instance
/// per attempt would never reach three).
final class PairingAttemptTracker {
  String? _phrase;
  int _failures = 0;

  /// Classifies one [attemptPairing] failure against [phrase]: resets the counter when
  /// [phrase] differs from the last call (a new phrase, R-13-023's own reset trigger), then
  /// returns `true` once this is the third consecutive failure for the same phrase.
  bool recordFailure(String phrase) {
    if (_phrase != phrase) {
      _phrase = phrase;
      _failures = 0;
    }
    _failures += 1;
    return _failures >= 3;
  }

  /// Resets the counter: call on a successful pairing, or when the person changes the phrase
  /// (a fresh phrase deserves a fresh three attempts, R-13-023).
  void reset() {
    _phrase = null;
    _failures = 0;
  }
}

/// Drives one first-pairing `Noise_XXpsk0` handshake (R-13-014, R-13-035 steps 4-9) over
/// [connection] from a validated [input]: derives the PSK from the phrase (`noise.dart`'s
/// `pskFromPhrase`), calls [RelayConnection.connect] with [PairingMode], and on success reads
/// back the pinned Host static key and `host_info` for the confirmation screen (R-13-041) and
/// for [persistPairing]. [tracker] MUST be the same instance across retries of the same
/// manual-entry attempt (see [PairingAttemptTracker]'s own doc comment).
///
/// This function performs no persistence: [persistPairing] is a separate, explicit step a
/// screen calls once its confirmation step accepts the pairing (R-90-024).
Future<Result<PairingOutcome>> attemptPairing({
  required RelayConnection connection,
  required PairingInput input,
  required BiometricGate gate,
  required DeviceInfo deviceInfo,
  required PairingAttemptTracker tracker,
}) async {
  final psk = await pskFromPhrase(input.phrase);
  final result = await connection.connect(
    origin: input.relayOrigin,
    handle: input.handle,
    mode: PairingMode(psk: psk),
    gate: gate,
    deviceInfo: deviceInfo,
  );
  if (result is Err<void>) {
    return Err(
      result.message,
      cause: _classifyAttemptFailure(result.cause, input.phrase, tracker),
    );
  }
  final DateTime connectedAt = DateTime.now();
  tracker.reset();
  final pinnedKey = connection.pinnedHostKey;
  final info = connection.lastHostInfo;
  if (pinnedKey == null || info == null) {
    return Err(
      'complete pairing',
      cause: StateError(
        'connect() returned Ok but captured no pinned host key or host_info',
      ),
    );
  }
  return Ok(
    PairingOutcome(
      hostId: info.hostId,
      hostName: info.hostName,
      hostStaticPublicKey: pinnedKey,
      hostFingerprintText: await hostFingerprint(pinnedKey),
      connectedAt: connectedAt,
    ),
  );
}

Object? _classifyAttemptFailure(
  Object? cause,
  String phrase,
  PairingAttemptTracker tracker,
) {
  if (cause is RelayRegistrationException &&
      cause.code == RelayRegistrationErrorCode.pairingExpired) {
    return PhraseException(PhraseErrorCode.phraseExpired, cause.message);
  }
  if (cause is RelayConnectException &&
      cause.failure == RelayConnectFailure.handshakeFailed &&
      tracker.recordFailure(phrase)) {
    return PhraseException(PhraseErrorCode.phraseAttempts, cause.message);
  }
  return cause;
}

/// Returns the last connected computer's origin as a form default (R-03-126).
/// A pairing URI supplies its own origin and takes priority over this default.
Future<RelayOrigin?> loadPairingOriginDefault({
  required KeystoreService keystore,
  required PlainStore plainStore,
}) async {
  final hostsResult = await plainStore.pairedHosts();
  if (hostsResult is! Ok<List<PairedHostRecord>>) return null;
  PairedHostRecord? latest;
  for (final host in hostsResult.value) {
    final seen = host.lastSeen;
    if (seen != null && (latest == null || seen.isAfter(latest.lastSeen!))) {
      latest = host;
    }
  }
  if (latest == null) return null;
  // The narrow read, never `hostSecrets`: a form default must not touch the pinned Host key or
  // the routing handle (`keystore.dart` `hostRelayOrigin`).
  final originResult = await keystore.hostRelayOrigin(latest.hostId);
  if (originResult is! Ok<Uri?>) return null;
  final origin = originResult.value;
  if (origin == null) return null;
  final parsed = parseRelayOrigin(origin.toString());
  return parsed is Ok<RelayOrigin> ? parsed.value : null;
}

/// Stores the Host key, handle, and relay origin together (R-13-048, R-03-126).
/// The plain store keeps the pairing identifier, display name, and last-seen time.
Future<Result<void>> persistPairing({
  required KeystoreService keystore,
  required PlainStore plainStore,
  required PairingInput input,
  required PairingOutcome outcome,
}) async {
  final secretsResult = await keystore.storeHostSecrets(
    outcome.hostId,
    HostSecrets(
      hostStaticPublicKey: outcome.hostStaticPublicKey,
      routingHandle: input.handle,
      relayOrigin: Uri.parse(input.relayOrigin.canonical),
    ),
  );
  if (secretsResult is Err<void>) {
    return secretsResult;
  }
  // `attemptPairing` opened the link and `RelayConnected` arrived before this record existed,
  // so the connect-time stamp had nothing to touch. The record carries that link-open time
  // (R-13-065); a cold start needs it to auto-connect.
  return plainStore.savePairedHost(
    PairedHostRecord(
      hostId: outcome.hostId,
      hostName: outcome.hostName,
      lastSeen: outcome.connectedAt,
    ),
  );
}

/// Clears one revoked computer's key, handle, origin, and plain record (R-13-054).
/// Other computers and the Device key remain unchanged (R-03-126).
/// Returns `Ok(true)` once no saved computer remains. The caller then routes to `/welcome`
/// (`docs/31-mockups/01-welcome.md` R-31-01-01); `Ok(false)` otherwise. Detecting the `4004`
/// close itself is `RelayConnection`'s job (`WP-14-a`), not this function's: this is the
/// clearing action a caller invokes once it already knows a close was a revocation, the same
/// "this file only raises or acts, a caller wires detection" boundary [PairingScanner]'s
/// lifecycle methods already use.
Future<Result<bool>> clearRevokedHost({
  required KeystoreService keystore,
  required PlainStore plainStore,
  required String hostId,
}) async {
  final deleteSecretsResult = await keystore.deleteHostSecrets(hostId);
  if (deleteSecretsResult is Err<void>) {
    return Err(deleteSecretsResult.message, cause: deleteSecretsResult.cause);
  }
  final removeRecordResult = await plainStore.removePairedHost(hostId);
  if (removeRecordResult is Err<void>) {
    return Err(removeRecordResult.message, cause: removeRecordResult.cause);
  }
  final remainingResult = await plainStore.pairedHosts();
  if (remainingResult is Err<List<PairedHostRecord>>) {
    return Err(remainingResult.message, cause: remainingResult.cause);
  }
  return Ok((remainingResult as Ok<List<PairedHostRecord>>).value.isEmpty);
}
