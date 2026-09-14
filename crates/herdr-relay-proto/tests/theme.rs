use herdr_relay_proto::frame::Frame;
use herdr_relay_proto::messages::{HostInfo, HostTheme, Message, ThemePalette};
use serde_json::json;

#[test]
fn host_theme_round_trips_with_exact_snake_case_fields() {
    let theme = ThemePalette {
        name: "vesper".to_owned(),
        accent: "#8A9A7B".to_owned(),
        panel_bg: "#101010".to_owned(),
        surface0: "#1C1C1C".to_owned(),
        surface1: "#282828".to_owned(),
        surface_dim: "#101010".to_owned(),
        overlay0: "#505050".to_owned(),
        overlay1: "#606060".to_owned(),
        text: "#D0D0D0".to_owned(),
        subtext0: "#909090".to_owned(),
        mauve: "#8A9A7B".to_owned(),
        green: "#8A9A7B".to_owned(),
        yellow: "#D0A050".to_owned(),
        red: "#C05050".to_owned(),
        blue: "#6080A0".to_owned(),
        teal: "#70A0A0".to_owned(),
        peach: "#D08050".to_owned(),
    };
    let expected_theme = json!({
        "name": "vesper", "accent": "#8A9A7B", "panel_bg": "#101010",
        "surface0": "#1C1C1C", "surface1": "#282828", "surface_dim": "#101010",
        "overlay0": "#505050", "overlay1": "#606060", "text": "#D0D0D0",
        "subtext0": "#909090", "mauve": "#8A9A7B", "green": "#8A9A7B",
        "yellow": "#D0A050", "red": "#C05050", "blue": "#6080A0",
        "teal": "#70A0A0", "peach": "#D08050"
    });
    let message = Message::HostTheme(HostTheme {
        theme: theme.clone(),
    });
    let expected = json!({"type": "host_theme", "payload": {"theme": expected_theme}});
    assert_eq!(message.type_name(), "host_theme");
    assert_eq!(serde_json::to_value(&message).unwrap(), expected);
    assert_eq!(
        serde_json::from_value::<Message>(expected).unwrap(),
        message
    );
    assert_eq!(
        Frame::wrap(2, None, &message).unwrap().message().unwrap(),
        message
    );

    let host_info = HostInfo {
        protocol: 1,
        host_id: "host".to_owned(),
        host_name: "desk".to_owned(),
        herdr_version: "1".to_owned(),
        herdr_protocol: 21,
        paired: false,
        theme: Some(theme),
    };
    let encoded = serde_json::to_value(&host_info).unwrap();
    assert_eq!(encoded["theme"], expected_theme);
    assert_eq!(
        serde_json::from_value::<HostInfo>(encoded).unwrap(),
        host_info
    );
}

#[test]
fn host_info_without_theme_stays_compatible() {
    let original = json!({
        "protocol": 1, "host_id": "host", "host_name": "desk",
        "herdr_version": "1", "herdr_protocol": 21, "paired": false
    });
    let host_info: HostInfo = serde_json::from_value(original.clone()).unwrap();
    assert_eq!(host_info.theme, None);
    assert_eq!(serde_json::to_value(host_info).unwrap(), original);
}
