// Build-time-only dev tool for `WP-15-a` (self-declared under Phase 15's `Owns.` line,
// R-90-018): downloads the EFF long Diceware word list, verifies it against the recorded
// checksum, normalises it, and writes the bundled asset `app/lib/services/pairing.dart`'s
// `loadEffWordlist()` reads at runtime (R-13-025, R-30-904).
//
// Run with: `dart run tool/fetch_eff_wordlist.dart` from `app/`, before `flutter build` or
// `flutter test`. Re-run only when the recorded checksum below changes.
//
// This is the Device-side build-time counterpart to
// `crates/herdr-relay/src/pairing/wordlist.rs`'s `curl`/`wget` shell-out (R-13-025). This
// script never ships: `app/tool/` sits outside `app/lib/`, so nothing here compiles into the
// app binary. `AGENTS.md`'s "Never build: HTTP client" rule is scoped to the shipped app (one
// WebSocket carries everything, R-01-013); a `dart:io` `HttpClient` call in a standalone dev
// tool that never ships is the same permitted category as that Rust file's own `curl`/`wget`
// shell-out, not an instance of the forbidden pattern.
//
// The output, `assets/wordlists/eff_large_wordlist.txt`, is gitignored (`app/.gitignore`) and
// declared as a Flutter asset in `app/pubspec.yaml`: R-13-025 forbids committing the word list
// itself, never a fetch script that holds no word-list data of its own.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart' show Blake2s;

/// The canonical EFF long wordlist URL (R-13-017).
const String _wordlistUrl =
    'https://www.eff.org/files/2016/07/18/eff_large_wordlist.txt';

/// `BLAKE2s-256` of the raw downloaded source bytes, the exact same constant
/// `crates/herdr-relay/src/pairing/wordlist.rs`'s `RAW_SOURCE_CHECKSUM_BLAKE2S256_HEX`
/// records — never a second, independently invented value (R-13-025).
const String _expectedChecksumHex =
    'e246c56edf8a06d87d89fd37966576ee70302c19ce128dac5004a87a7990d060';

/// The exact size of the EFF long wordlist (R-13-025).
const int _entryCount = 7776;

/// The bundled asset path `app/pubspec.yaml` declares and
/// `app/lib/services/pairing.dart`'s `loadEffWordlist()` reads.
const String _outputPath = 'assets/wordlists/eff_large_wordlist.txt';

Future<void> main() async {
  stdout.writeln('Fetching the EFF long wordlist from $_wordlistUrl ...');
  final Uint8List bytes;
  try {
    bytes = await _fetch(Uri.parse(_wordlistUrl));
  } on Exception catch (e) {
    stderr.writeln('Fetch failed: $e');
    exitCode = 1;
    return;
  }

  final digest = await Blake2s().hash(bytes);
  final digestHex = digest.bytes
      .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
      .join();
  if (digestHex != _expectedChecksumHex) {
    stderr.writeln(
      'Checksum mismatch (R-13-025): expected $_expectedChecksumHex, got '
      '$digestHex. Refusing to write a possibly-tampered word list.',
    );
    exitCode = 1;
    return;
  }

  final words = _extractWords(utf8.decode(bytes));
  if (words.length != _entryCount) {
    stderr.writeln(
      'Word list does not hold exactly $_entryCount entries, found '
      '${words.length}. Refusing to write it.',
    );
    exitCode = 1;
    return;
  }

  final outFile = File(_outputPath);
  await outFile.create(recursive: true);
  await outFile.writeAsString('${words.join('\n')}\n');
  stdout.writeln(
    'Wrote ${words.length} checksum-verified words to $_outputPath.',
  );
}

/// Parses the `<dice-roll>\t<word>` source format (R-13-025's normalisation: lowercase ASCII,
/// one word per line, no blank lines, no leading or trailing whitespace), taking the last
/// tab-separated field of each non-blank line. Mirrors
/// `crates/herdr-relay/src/pairing/wordlist.rs`'s `extract_words` exactly.
List<String> _extractWords(String raw) {
  final words = <String>[];
  for (final rawLine in const LineSplitter().convert(raw)) {
    final line = rawLine.trim();
    if (line.isEmpty) {
      continue;
    }
    final fields = line.split('\t');
    words.add(fields.last.trim().toLowerCase());
  }
  return words;
}

Future<Uint8List> _fetch(Uri url) async {
  final client = HttpClient();
  try {
    final request = await client.getUrl(url);
    final response = await request.close();
    if (response.statusCode != 200) {
      throw HttpException(
        'EFF word list fetch returned HTTP ${response.statusCode}',
        uri: url,
      );
    }
    final builder = BytesBuilder();
    await for (final chunk in response) {
      builder.add(chunk);
    }
    return builder.toBytes();
  } finally {
    client.close();
  }
}
