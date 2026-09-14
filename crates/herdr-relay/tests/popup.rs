//! Popup pane behaviour with no sibling test file before this one
//! (`docs/31-mockups/16-host-popup.md` R-31-16-17, R-31-16-20, R-31-16-21,
//! R-31-16-23, R-31-16-30).
//!
//! Same seam as `tests/popup_once.rs` (`popup::App` + `render_to_buffer`)
//! with a caller-supplied `control::Status` fixture behind the injected
//! status source (R-10-066), so these tests are deterministic and free of
//! every live side effect.

use std::time::Instant;

use herdr_relay::control::{self, Command, LinkState};
use herdr_relay::popup::{self, App};
use herdr_relay_proto::messages::Platform;
use ratatui::buffer::Buffer;
use ratatui::layout::Rect;
use ratatui::style::{Color, Modifier};
use time::OffsetDateTime;

/// The fixture origin: the mockup's own worked example.
const ORIGIN: &str = "https://relay.example.com";

fn link(state: LinkState) -> control::LinkStatus {
    control::LinkStatus {
        state,
        attempt: 0,
        error: None,
    }
}

fn device_row(
    device_id: &str,
    name: &str,
    platform: Platform,
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

/// Two devices (`device-a` Android, `device-b` iOS), matching
/// `docs/31-mockups/16-host-popup.md`'s own worked example shape.
fn two_device_status(link: control::LinkStatus, connected_a: bool) -> control::Status {
    control::Status {
        relay_origin: ORIGIN.to_string(),
        link,
        pairing: None,
        devices: vec![
            device_row(
                "device-a",
                "pixel-8-pat",
                Platform::Android,
                "15",
                connected_a,
            ),
            device_row("device-b", "iphone-15-pat", Platform::Ios, "18.5", false),
        ],
    }
}

/// No paired devices at all, for the empty-store footer forms.
fn no_device_status(link: control::LinkStatus) -> control::Status {
    control::Status {
        relay_origin: ORIGIN.to_string(),
        link,
        pairing: None,
        devices: vec![],
    }
}

/// Builds the pane against the injected status source (R-10-066). The
/// command sink answers `ok`; no test in this file sends a command.
fn app_for(status: control::Status) -> App {
    let mut app = App::with_sources(
        Box::new(move || Ok(status.clone())),
        Box::new(|_: &Command| Ok(serde_json::json!({}))),
    );
    app.refresh();
    app
}

fn render_buffer(app: &mut App, width: u16, height: u16) -> Buffer {
    popup::render_to_buffer(
        app,
        Rect::new(0, 0, width, height),
        Instant::now(),
        OffsetDateTime::now_utc(),
    )
}

fn render(app: &mut App, width: u16, height: u16) -> Vec<String> {
    popup::buffer_lines(&render_buffer(app, width, height))
}

/// R-31-16-17: the pane holds no light/dark theme state (`App` has no such
/// field), so it stays readable under any theme only if every colour it
/// emits is a terminal-relative ANSI value the terminal remaps itself,
/// never a fixed RGB/indexed value and never a printed hex string. Checked
/// across two different app states (a link with a connected phone, and an
/// offline link) so the eight-colour claim is not just checked against one
/// code path. Selection itself MUST be reverse video alone, never a
/// distinct background colour.
#[test]
fn colors_are_named_ansi_values_and_selection_is_reverse_video_only() {
    let mut idle_app = app_for(two_device_status(link(LinkState::Connected), true));
    let idle_lines = render(&mut idle_app, 72, 20);
    let idle_buffer = render_buffer(&mut idle_app, 72, 20);

    let row_a = idle_lines
        .iter()
        .position(|l| l.trim_start().starts_with("pixel-8-pat"))
        .expect("device-a's row is rendered") as u16;
    let row_b = idle_lines
        .iter()
        .position(|l| l.trim_start().starts_with("iphone-15-pat"))
        .expect("device-b's row is rendered") as u16;

    let selected_cell = &idle_buffer[(0, row_a)];
    let unselected_cell = &idle_buffer[(0, row_b)];
    assert!(
        selected_cell.modifier.contains(Modifier::REVERSED),
        "the selected row (device-a, index 0) must be reverse video"
    );
    assert!(
        !unselected_cell.modifier.contains(Modifier::REVERSED),
        "an unselected row must not be reverse video"
    );
    assert_eq!(
        selected_cell.bg,
        Color::Reset,
        "selection must not use a distinct background colour, only reverse video"
    );
    assert_eq!(unselected_cell.bg, Color::Reset);

    let mut offline_app = app_for(two_device_status(
        control::LinkStatus {
            state: LinkState::Offline,
            attempt: 3,
            error: Some("connection refused".to_string()),
        },
        false,
    ));
    let offline_lines = render(&mut offline_app, 72, 20);
    let offline_buffer = render_buffer(&mut offline_app, 72, 20);

    for buffer in [&idle_buffer, &offline_buffer] {
        for y in 0..buffer.area.height {
            for x in 0..buffer.area.width {
                let cell = &buffer[(x, y)];
                assert!(
                    !matches!(cell.fg, Color::Rgb(..) | Color::Indexed(_)),
                    "cell ({x},{y}) foreground must be a named ANSI colour, not {:?}",
                    cell.fg
                );
                assert!(
                    !matches!(cell.bg, Color::Rgb(..) | Color::Indexed(_)),
                    "cell ({x},{y}) background must be a named ANSI colour, not {:?}",
                    cell.bg
                );
            }
        }
    }
    for lines in [&idle_lines, &offline_lines] {
        let text = lines.join("\n");
        assert!(
            !text.contains('#'),
            "no rendered line may print a hex colour value"
        );
    }
}

/// R-31-16-20: the title's phone count is the stored paired-device count,
/// and it does not change as the connected device or the link state
/// change - only the device list's own size moves it.
#[test]
fn title_phone_count_is_the_stored_count_regardless_of_connection_state() {
    let mut app_a = app_for(two_device_status(link(LinkState::Idle), false));
    let mut app_b = app_for(two_device_status(link(LinkState::Connected), true));
    let mut app_c = app_for(two_device_status(
        control::LinkStatus {
            state: LinkState::Offline,
            attempt: 1,
            error: Some("i/o timeout".to_string()),
        },
        false,
    ));

    let lines_a = render(&mut app_a, 72, 20);
    let lines_b = render(&mut app_b, 72, 20);
    let lines_c = render(&mut app_c, 72, 20);

    assert_eq!(lines_a[0], "herdr relay (2 phones)");
    assert_eq!(
        lines_b[0], lines_a[0],
        "a connected phone must not change the title's phone count"
    );
    assert_eq!(
        lines_c[0], lines_a[0],
        "an offline relay link must not change the title's phone count"
    );
}

/// R-31-16-21 with R-10-064: the link object the bridge serves carries no
/// round trip, and the pane holds no relay connection to measure one with
/// (R-10-066), so the relay line prints the state word alone and the pane
/// MUST NOT print a manufactured `ms` value.
#[test]
fn relay_line_prints_the_state_word_alone_never_a_manufactured_round_trip() {
    let mut app_connected = app_for(two_device_status(link(LinkState::Connected), true));
    let mut app_idle = app_for(two_device_status(link(LinkState::Idle), false));

    let lines_connected = render(&mut app_connected, 72, 20);
    let lines_idle = render(&mut app_idle, 72, 20);

    assert_eq!(
        lines_connected[1], "relay: https://relay.example.com   connected",
        "the connected state word prints alone"
    );
    assert_eq!(
        lines_idle[1], "relay: https://relay.example.com   idle",
        "the idle state word prints alone"
    );
    for lines in [&lines_connected, &lines_idle] {
        assert!(
            !lines.join("\n").contains(" ms"),
            "no round trip is ever printed: the pane has nothing to measure one with"
        );
    }
}

/// R-31-16-23: the pane offers no rename-a-phone affordance. Checked across
/// every footer width form (labelled, short, keys-only), since that is the
/// only place a key binding's label could ever mention one.
#[test]
fn no_rename_affordance_appears_in_any_rendered_form() {
    let mut app = app_for(two_device_status(link(LinkState::Connected), false));

    for width in [72, 65, 28] {
        let text = render(&mut app, width, 40).join("\n").to_lowercase();
        assert!(
            !text.contains("rename"),
            "width {width}: no rendered form may offer to rename a phone"
        );
    }
}

/// R-31-16-30: the footer prints the widest of its three forms that fits,
/// and a binding `R-31-16-29` made inert (no phones to remove) never
/// appears in any form.
#[test]
fn footer_prints_widest_fitting_form_and_omits_inert_bindings() {
    let mut labelled_app = app_for(two_device_status(link(LinkState::Idle), false));
    let labelled_lines = render(&mut labelled_app, 72, 20);
    assert!(
        labelled_lines.iter().any(
            |l| l == "up/down select  p pair  d remove  r remove all  s stop  f reload  q quit"
        ),
        "72 columns must fit the fully labelled footer"
    );

    let mut short_app = app_for(two_device_status(link(LinkState::Idle), false));
    let short_lines = render(&mut short_app, 65, 20);
    assert!(
        short_lines
            .iter()
            .any(|l| l == "p pair  d remove  r all  s stop  f reload  q quit"),
        "65 columns must fall back to the short footer form"
    );

    let mut empty_app = app_for(no_device_status(link(LinkState::Idle)));
    let empty_wide_lines = render(&mut empty_app, 72, 15);
    assert!(
        empty_wide_lines
            .iter()
            .any(|l| l == "p pair  s stop  f reload  q quit"),
        "with no phones, remove-one and remove-all are inert and must be omitted"
    );
    assert!(
        !empty_wide_lines.iter().any(|l| l.contains("remove")),
        "an inert binding must never appear, even with room to spare"
    );

    let mut empty_narrow_app = app_for(no_device_status(link(LinkState::Idle)));
    let empty_narrow_lines = render(&mut empty_narrow_app, 28, 15);
    assert!(
        empty_narrow_lines.iter().any(|l| l == "p s f q"),
        "28 columns must fall back to the keys-only footer form"
    );
}
