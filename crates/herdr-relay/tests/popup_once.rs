//! `--once`'s exact rendered output for a known device list, in both layouts
//! (`docs/31-mockups/16-host-popup.md` R-31-16-04, R-31-16-06, R-40-029).
//!
//! The pane is a control client of the bridge (R-10-066): this test drives
//! the same seam `popup::run_once` itself uses (`popup::App` +
//! `render_to_buffer`), with a caller-supplied status fixture behind the
//! injected status source instead of a running bridge, so the test is
//! deterministic and free of every live side effect. The fixture carries
//! fixed credentials (the mockup's own worked-example handle and six fixed
//! words on a fixed origin), so the rendered QR decodes against a known URI.

use std::time::Instant;

use ratatui::layout::Rect;
use time::OffsetDateTime;

use herdr_relay::control::{self, Command, LinkState};
use herdr_relay::popup::{self, App};

/// The fixture origin: the mockup's own worked example.
const ORIGIN: &str = "https://relay.example.com";
/// The fixture handle: the mockup's own 22-character worked example.
const HANDLE: &str = "n6Loxf94CfyIO6hOxlaHvA";
/// The fixture phrase (display form): six fixed words, matching the
/// synthetic-wordlist convention `pairing.rs`'s own tests use (R-13-025
/// forbids committing the real EFF list, even in a fixture).
const PHRASE: &str = "remedy tapestry hubcap oversleep jailbird kinetic";

/// The fixture pairing URI, built with the one shared builder, so the QR the
/// pane encodes from `status.pairing.uri` (R-10-066) decodes to exactly this
/// string.
fn pairing_uri_fixture() -> String {
    herdr_relay_proto::handle::PairingUri {
        relay_origin: ORIGIN.to_string(),
        handle: HANDLE.parse().expect("the fixture handle parses"),
        phrase: PHRASE.replace(' ', "-"),
    }
    .build()
}

fn device_row(
    device_id: &str,
    name: &str,
    platform: herdr_relay_proto::messages::Platform,
    os_version: &str,
    connected: bool,
) -> control::DeviceRow {
    control::DeviceRow {
        device_id: device_id.to_string(),
        device_name: name.to_string(),
        platform,
        os_version: os_version.to_string(),
        fingerprint: "3f9a-1c04-be77-20d5".to_string(),
        paired_at: "2026-08-22T17:02:00Z".to_string(),
        last_seen: "2026-08-24T09:14:00Z".to_string(),
        connected,
    }
}

/// The known status fixture every test in this file renders against: two
/// devices, matching `docs/31-mockups/16-host-popup.md`'s own worked example
/// shape (one Android, one iOS), plus a registered open pairing (R-10-064:
/// the credential fields are set once `registered` is true).
fn fixture_status() -> control::Status {
    use herdr_relay_proto::messages::Platform;
    control::Status {
        relay_origin: ORIGIN.to_string(),
        link: control::LinkStatus {
            state: LinkState::Idle,
            attempt: 0,
            error: None,
        },
        pairing: Some(control::PairingStatus {
            registered: true,
            uri: Some(pairing_uri_fixture()),
            phrase: Some(PHRASE.to_string()),
            handle: Some(HANDLE.to_string()),
            expires_in_s: 600,
        }),
        devices: vec![
            device_row("device-a", "pixel-8-pat", Platform::Android, "15", false),
            device_row("device-b", "iphone-15-pat", Platform::Ios, "18.5", false),
        ],
    }
}

/// Builds the pane against the injected status source (R-10-066). The
/// command sink records nothing and answers `ok`: no test in this file
/// sends a command.
fn fixture_app() -> App {
    let mut app = App::with_sources(
        Box::new(|| Ok(fixture_status())),
        Box::new(|_: &Command| Ok(serde_json::json!({}))),
    );
    app.refresh();
    app
}

fn render(app: &mut App, width: u16, height: u16, now: Instant) -> Vec<String> {
    let buffer = popup::render_to_buffer(
        app,
        Rect::new(0, 0, width, height),
        now,
        OffsetDateTime::now_utc(),
    );
    popup::buffer_lines(&buffer)
}

/// The full pairing layout (R-31-16-04): the QR block, the six words, the
/// relay origin and the handle all print as text, at the width/height this
/// document's own worked example uses (72x47). Also R-31-16-02: the
/// captured QR block, decoded straight from the rendered half-block
/// output (never the internal `QrGrid` struct), MUST equal the exact URI
/// the pane encoded — here, the `uri` field of the bridge's status answer
/// (R-10-066). This also proves R-13-028: the Host renders the pairing URI
/// as a QR code in the plugin popup pane.
#[test]
fn once_full_layout_prints_the_qr_words_origin_handle_and_device_list() {
    let mut app = fixture_app();
    let now = Instant::now();
    let expected_uri = app.pairing_uri().expect("a live pairing URI");
    assert_eq!(expected_uri, pairing_uri_fixture());
    let qr_width = app.qr_width().expect("a live QR grid");

    let lines = render(
        &mut app,
        popup::DEFAULT_ONCE_WIDTH,
        popup::DEFAULT_ONCE_HEIGHT,
        now,
    );
    let text = lines.join("\n");

    // The device list, with a fingerprint per entry (the phase's own `Done
    // when` line).
    assert!(lines[0].starts_with("herdr relay (2 phones)"));
    assert!(text.contains("pixel-8-pat"));
    assert!(text.contains("iphone-15-pat"));
    let fingerprint_lines: Vec<&String> = lines
        .iter()
        .filter(|l| l.trim_start().starts_with("key "))
        .collect();
    assert_eq!(
        fingerprint_lines.len(),
        1,
        "one fingerprint printed, for the selected phone's detail block"
    );

    // The relay origin and the handle as text (R-31-16-04), never a bare
    // numeric code (R-31-16-13).
    assert!(text.contains("relay:"));
    assert!(text.contains(ORIGIN));
    assert!(text.contains("computer:"));
    assert!(text.contains(HANDLE));

    // The six words, as text (R-31-16-04).
    assert!(text.contains("phrase:"));
    assert!(
        text.contains(PHRASE) || PHRASE.split(' ').all(|word| text.contains(word)),
        "the fixture phrase must print as text, whole or wrapped at a space"
    );

    // A QR block, sized from the encoder's own output (R-31-16-02) — never a
    // fixed constant: locate it, decode it straight from the rendered
    // glyphs, and compare against the exact URI this pane encoded.
    let decoded = decode_captured_qr(&lines, qr_width);
    assert_eq!(decoded, expected_uri);
}

/// The compact layout (R-31-16-03, R-31-16-26): at the 12-row pairing
/// floor (11 credential rows plus the copy hint of R-31-16-34) the QR region
/// does not fit and is dropped whole, but the origin, handle and words still
/// print as text in full (R-31-16-04).
#[test]
fn once_compact_layout_drops_the_qr_but_keeps_every_credential_as_text() {
    let mut app = fixture_app();
    let now = Instant::now();

    let lines = render(&mut app, 72, 12, now);
    let text = lines.join("\n");

    assert!(
        !lines
            .iter()
            .any(|l| l.contains('█') || l.contains('▀') || l.contains('▄')),
        "R-31-16-03/R-31-16-26: the QR region and its quiet zone must be dropped whole, never clipped"
    );
    assert!(text.contains("no room for the qr code"));
    assert!(text.contains(ORIGIN));
    assert!(text.contains("computer:"));
    assert!(text.contains(HANDLE));
    assert!(text.contains("phrase:"));
    assert!(
        PHRASE.split(' ').all(|word| text.contains(word)),
        "the fixture phrase must print as text"
    );
}

/// R-40-029: `--once` renders exactly one pass and produces stable,
/// deterministic output for the same state and the same instant — no
/// hidden interactive state leaks between calls.
#[test]
fn once_rendering_is_deterministic_for_the_same_state() {
    let mut app = fixture_app();
    let now = Instant::now();
    let first = render(
        &mut app,
        popup::DEFAULT_ONCE_WIDTH,
        popup::DEFAULT_ONCE_HEIGHT,
        now,
    );
    let second = render(
        &mut app,
        popup::DEFAULT_ONCE_WIDTH,
        popup::DEFAULT_ONCE_HEIGHT,
        now,
    );
    assert_eq!(first, second);
}

/// Reconstructs the QR module grid straight from the pane's own rendered
/// half-block characters (never the internal `QrGrid` struct) at the
/// encoder's own module width (`qr_width`, from `App::qr_width` — the
/// number this pane's region-sizing math is itself keyed on, per
/// R-31-16-02, not an assumed constant), and decodes it with `rqrr`, a
/// pure-Rust QR reader run directly over a boolean grid function — no
/// `image` crate needed.
fn decode_captured_qr(lines: &[String], qr_width: usize) -> String {
    let rows: Vec<Vec<char>> = lines.iter().map(|l| l.chars().collect()).collect();
    let first_glyph_row = rows
        .iter()
        .position(|row| row.iter().any(|c| matches!(c, '█' | '▀' | '▄')))
        .expect("the rendered output contains a QR block");
    // The QR region's own top 4-module quiet zone (2 printed rows, blank)
    // precedes the first row that can show a glyph — the finder pattern's
    // outer corner is always dark, so the first glyph row is always exactly
    // 2 printed rows into the region, never the region's own top row.
    let start_row = first_glyph_row - 2;
    // The QR region is indented two columns (R-31-16-02); the first glyph
    // column is the 2-column indent plus the 4-module quiet zone.
    const QUIET_ZONE: usize = 4;
    const INDENT: usize = 2;

    let grid = rqrr::SimpleGrid::from_func(qr_width, |module_x, module_y| {
        let padded_x = INDENT + QUIET_ZONE + module_x;
        let padded_y = QUIET_ZONE + module_y;
        let printed_row = start_row + padded_y / 2;
        let top_half = padded_y.is_multiple_of(2);
        let symbol = rows
            .get(printed_row)
            .and_then(|row| row.get(padded_x))
            .copied()
            .unwrap_or(' ');
        let (top, bottom) = match symbol {
            '█' => (true, true),
            '▀' => (true, false),
            '▄' => (false, true),
            _ => (false, false),
        };
        if top_half { top } else { bottom }
    });
    let decoded = rqrr::Grid::new(grid);
    let (_meta, content) = decoded.decode().expect("the captured QR block decodes");
    content
}
