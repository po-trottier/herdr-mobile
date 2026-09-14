//! Herdr's grid palette and config watch (R-10-073, R-03-131).
use herdr_relay_proto::messages::ThemePalette;
use serde::Deserialize;
use std::path::{Path, PathBuf};
use std::time::{Duration, Instant, SystemTime};

// R-10-073: ThemePalette.cs:82-204; catppuccin uses that class's property defaults.
const CATALOGUE: &[(&str, [&str; 16])] = &[
    (
        "catppuccin",
        [
            "#89B4FA", "#181825", "#313244", "#45475A", "#1E1E2E", "#6C7086", "#7F849C", "#CDD6F4",
            "#A6ADC8", "#CBA6F7", "#A6E3A1", "#F9E2AF", "#F38BA8", "#89B4FA", "#94E2D5", "#FAB387",
        ],
    ),
    (
        "catppuccin-latte",
        [
            "#1E66F5", "#EFF1F5", "#CCD0DA", "#BCC0CC", "#E6E9EF", "#9CA0B0", "#8C8FA1", "#4C4F69",
            "#6C6F85", "#8839EF", "#40A02B", "#DF8E1D", "#D20F39", "#1E66F5", "#179299", "#FE640B",
        ],
    ),
    (
        "tokyo-night",
        [
            "#7AA2F7", "#1A1B26", "#24283B", "#414868", "#1A1B26", "#565F89", "#697196", "#C0CAF5",
            "#A9B1D6", "#BB9AF7", "#9ECE6A", "#E0AF68", "#F7768E", "#7AA2F7", "#7DCFFF", "#FF9E64",
        ],
    ),
    (
        "tokyo-night-day",
        [
            "#2E7DE9", "#E1E2E7", "#D5D6DB", "#C4C6CE", "#DFE1E6", "#8C8FA1", "#6C6E7E", "#3760BF",
            "#6172B0", "#9854F1", "#587539", "#8C6C3E", "#F52A65", "#2E7DE9", "#007197", "#B15C00",
        ],
    ),
    (
        "dracula",
        [
            "#BD93F9", "#21222C", "#343746", "#424450", "#282A36", "#6272A4", "#6272A4", "#F8F8F2",
            "#BFBFB8", "#BD93F9", "#50FA7B", "#F1FA8C", "#FF5555", "#8BE9FD", "#8BE9FD", "#FFB86C",
        ],
    ),
    (
        "nord",
        [
            "#88C0D0", "#2E3440", "#3B4252", "#434C5E", "#2E3440", "#4C566A", "#616E88", "#D8DEE9",
            "#ABB9CF", "#B48EAD", "#A3BE8C", "#EBCB8B", "#BF616A", "#81A1C1", "#88C0D0", "#D08770",
        ],
    ),
    (
        "gruvbox",
        [
            "#83A598", "#282828", "#3C3836", "#504945", "#282828", "#665C54", "#7C6F64", "#EBDBB2",
            "#BDAE93", "#D3869B", "#B8BB26", "#FABD2F", "#FB4934", "#83A598", "#8EC07C", "#FE8019",
        ],
    ),
    (
        "gruvbox-light",
        [
            "#076678", "#FBF1C7", "#F2E5BC", "#EBDBB2", "#FBF1C7", "#BDAE93", "#928374", "#3C3836",
            "#665C54", "#8F3F71", "#79740E", "#B57614", "#9D0006", "#076678", "#427B58", "#AF3A03",
        ],
    ),
    (
        "one-dark",
        [
            "#61AFEF", "#21252B", "#2C313A", "#3E4451", "#282C34", "#5C6370", "#6B717D", "#ABB2BF",
            "#8B919E", "#C678DD", "#98C379", "#E5C07B", "#E06C75", "#61AFEF", "#56B6C2", "#D19A66",
        ],
    ),
    (
        "one-light",
        [
            "#4078F2", "#FAFAFA", "#E5E5E6", "#D3D3D3", "#F0F0F1", "#A0A1A7", "#8A8B91", "#383A42",
            "#696C77", "#A626A4", "#50A14F", "#C18401", "#E45649", "#4078F2", "#0184BC", "#B76B01",
        ],
    ),
    (
        "solarized",
        [
            "#268BD2", "#002B36", "#073642", "#0D4350", "#002B36", "#586E75", "#657B83", "#839496",
            "#6C7C80", "#6C71C4", "#859900", "#B58900", "#DC322F", "#268BD2", "#2AA198", "#CB4B16",
        ],
    ),
    (
        "solarized-light",
        [
            "#268BD2", "#FDF6E3", "#EEE8D5", "#E4E0C8", "#FDF6E3", "#93A1A1", "#839496", "#657B83",
            "#586E75", "#6C71C4", "#859900", "#B58900", "#DC322F", "#268BD2", "#2AA198", "#CB4B16",
        ],
    ),
    (
        "kanagawa",
        [
            "#7E9CD8", "#1F1F28", "#2A2A37", "#363646", "#16161D", "#54546D", "#6A6A7E", "#DCD7BA",
            "#A6A69C", "#957FB8", "#98BB6C", "#E6C384", "#C34043", "#7E9CD8", "#7AA89F", "#FFA066",
        ],
    ),
    (
        "kanagawa-lotus",
        [
            "#4D699B", "#F2ECBC", "#E7DDB0", "#D9CFA3", "#E5DDB0", "#8A8980", "#716E61", "#545464",
            "#6F6F69", "#B35B79", "#6F894E", "#E98A00", "#C84053", "#4D699B", "#597B75", "#E35A00",
        ],
    ),
    (
        "rose-pine",
        [
            "#C4A7E7", "#191724", "#1F1D2E", "#26233A", "#191724", "#6E6A86", "#908CAA", "#E0DEF4",
            "#908CAA", "#C4A7E7", "#31748F", "#F6C177", "#EB6F92", "#9CCFD8", "#9CCFD8", "#EBBCBA",
        ],
    ),
    (
        "rose-pine-dawn",
        [
            "#907AA9", "#FAF4ED", "#FFFDF9", "#F2E9E1", "#FAF4ED", "#9893A5", "#797593", "#575279",
            "#797593", "#907AA9", "#286983", "#EA9D34", "#B4637A", "#56949F", "#56949F", "#D7827E",
        ],
    ),
    (
        "vesper",
        [
            "#8A9A7B", "#101010", "#1C1C1C", "#282828", "#101010", "#505050", "#606060", "#D0D0D0",
            "#909090", "#8A9A7B", "#8A9A7B", "#D0A050", "#C05050", "#6080A0", "#70A0A0", "#D08050",
        ],
    ),
    (
        "terminal",
        [
            "#000080", "reset", "reset", "#808080", "#808080", "#C0C0C0", "#FFFFFF", "reset",
            "#C0C0C0", "#C0C0C0", "#008000", "#808000", "#FF0000", "#000080", "#008080", "#808000",
        ],
    ),
];

fn palette(name: &str) -> Option<ThemePalette> {
    let (name, colors) = CATALOGUE.iter().find(|(candidate, _)| *candidate == name)?;
    Some(ThemePalette {
        name: (*name).to_owned(),
        accent: colors[0].to_owned(),
        panel_bg: colors[1].to_owned(),
        surface0: colors[2].to_owned(),
        surface1: colors[3].to_owned(),
        surface_dim: colors[4].to_owned(),
        overlay0: colors[5].to_owned(),
        overlay1: colors[6].to_owned(),
        text: colors[7].to_owned(),
        subtext0: colors[8].to_owned(),
        mauve: colors[9].to_owned(),
        green: colors[10].to_owned(),
        yellow: colors[11].to_owned(),
        red: colors[12].to_owned(),
        blue: colors[13].to_owned(),
        teal: colors[14].to_owned(),
        peach: colors[15].to_owned(),
    })
}

fn reset() -> ThemePalette {
    ThemePalette {
        name: String::new(),
        accent: "reset".to_owned(),
        panel_bg: "reset".to_owned(),
        surface0: "reset".to_owned(),
        surface1: "reset".to_owned(),
        surface_dim: "reset".to_owned(),
        overlay0: "reset".to_owned(),
        overlay1: "reset".to_owned(),
        text: "reset".to_owned(),
        subtext0: "reset".to_owned(),
        mauve: "reset".to_owned(),
        green: "reset".to_owned(),
        yellow: "reset".to_owned(),
        red: "reset".to_owned(),
        blue: "reset".to_owned(),
        teal: "reset".to_owned(),
        peach: "reset".to_owned(),
    }
}

#[derive(Default, Deserialize)]
#[serde(default)]
struct ThemeConfig {
    name: Option<String>,
    dark_name: Option<String>,
    light_name: Option<String>,
    auto_switch: bool,
}

fn canonical(name: &str) -> String {
    let name = name.trim().to_lowercase().replace([' ', '_'], "-");
    match name.as_str() {
        "catppuccin-mocha" | "catppuccin-dark" => "catppuccin",
        "latte" | "catppuccin-light" => "catppuccin-latte",
        "tokyo-night-dark" => "tokyo-night",
        "tokyo-night-light" => "tokyo-night-day",
        "onedark" => "one-dark",
        "onelight" => "one-light",
        "solarized-dark" => "solarized",
        "rosepine" | "rose-pine-dark" => "rose-pine",
        "rose-pine-light" => "rose-pine-dawn",
        _ => return name,
    }
    .to_owned()
}

/// Resolves only the four theme keys; unknown names have no override (R-10-073).
pub fn resolve(config_text: &str, host_is_light: bool) -> Option<ThemePalette> {
    #[derive(Deserialize)]
    struct Config {
        theme: Option<ThemeConfig>,
    }
    let config: Config = toml::from_str(config_text).ok()?;
    let config = config.theme?;
    let base = canonical(config.name.as_deref().unwrap_or("catppuccin"));
    if !config.auto_switch {
        return palette(&base);
    }
    let selected = if host_is_light {
        config.light_name
    } else {
        config.dark_name
    };
    if let Some(selected) = selected {
        return palette(&canonical(&selected));
    }
    const SIBLINGS: &[(&str, &str)] = &[
        ("catppuccin", "catppuccin-latte"),
        ("tokyo-night", "tokyo-night-day"),
        ("gruvbox", "gruvbox-light"),
        ("one-dark", "one-light"),
        ("solarized", "solarized-light"),
        ("kanagawa", "kanagawa-lotus"),
        ("rose-pine", "rose-pine-dawn"),
    ];
    if let Some((dark, light)) = SIBLINGS
        .iter()
        .find(|(dark, light)| *dark == base || *light == base)
    {
        return palette(if host_is_light { light } else { dark });
    }
    palette(&base)?;
    palette(if host_is_light {
        "catppuccin-latte"
    } else {
        &base
    })
}

/// Returns Herdr's own config location, not the plugin config (R-10-073).
pub fn config_path() -> PathBuf {
    #[cfg(windows)]
    let base = std::env::var_os("APPDATA")
        .map(PathBuf::from)
        .unwrap_or_default();
    #[cfg(target_os = "macos")]
    let base = PathBuf::from(std::env::var_os("HOME").unwrap_or_default())
        .join("Library/Application Support");
    #[cfg(not(any(windows, target_os = "macos")))]
    let base = std::env::var_os("XDG_CONFIG_HOME")
        .filter(|v| !v.is_empty())
        .map(PathBuf::from)
        .unwrap_or_else(|| {
            PathBuf::from(std::env::var_os("HOME").unwrap_or_default()).join(".config")
        });
    base.join("herdr").join("config.toml")
}

fn host_is_light() -> bool {
    #[cfg(windows)]
    let (program, args): (&str, &[&str]) = (
        "reg",
        &[
            "query",
            r"HKCU\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize",
            "/v",
            "AppsUseLightTheme",
        ],
    );
    #[cfg(target_os = "macos")]
    let (program, args): (&str, &[&str]) = ("defaults", &["read", "-g", "AppleInterfaceStyle"]);
    #[cfg(not(any(windows, target_os = "macos")))]
    let (program, args): (&str, &[&str]) = (
        "gsettings",
        &["get", "org.gnome.desktop.interface", "color-scheme"],
    );
    let mut command = std::process::Command::new(program);
    command.args(args).stdin(std::process::Stdio::null());
    crate::process::suppress_console_window(&mut command);
    let Ok(output) = command.output() else {
        return false;
    };
    let value = String::from_utf8_lossy(&output.stdout);
    #[cfg(windows)]
    {
        output.status.success() && value.split_whitespace().last().is_some_and(|v| v != "0x0")
    }
    #[cfg(target_os = "macos")]
    {
        !output.status.success() || value.trim() != "Dark"
    }
    #[cfg(not(any(windows, target_os = "macos")))]
    {
        output.status.success() && value.contains("prefer-light")
    }
}

fn modified(path: &Path) -> Option<SystemTime> {
    std::fs::metadata(path)
        .ok()
        .and_then(|metadata| metadata.modified().ok())
}

fn load(path: &Path) -> std::io::Result<Option<ThemePalette>> {
    match std::fs::read_to_string(path) {
        Ok(text) => Ok(resolve(&text, host_is_light())),
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => Ok(None),
        Err(error) => Err(error),
    }
}

/// Polls in the existing bridge loop; it never logs config data (R-10-073).
pub(crate) struct Watcher {
    path: PathBuf,
    modified: Option<SystemTime>,
    next_poll: Instant,
    pending: Option<Instant>,
    pub(crate) current: Option<ThemePalette>,
}

impl Watcher {
    pub(crate) fn new() -> Self {
        Self::at(config_path(), Instant::now())
    }

    fn at(path: PathBuf, now: Instant) -> Self {
        let modified = modified(&path);
        let current = load(&path).ok().flatten();
        Self {
            path,
            modified,
            next_poll: now + Duration::from_secs(2),
            pending: None,
            current,
        }
    }

    pub(crate) fn poll(&mut self, now: Instant) -> Option<ThemePalette> {
        let due = self.pending.is_some_and(|deadline| now >= deadline);
        if now < self.next_poll && !due {
            return None;
        }
        self.next_poll = now + Duration::from_secs(2);
        let modified = modified(&self.path);
        if modified != self.modified {
            self.modified = modified;
            self.pending = Some(now + Duration::from_millis(500));
            return None;
        }
        if !due {
            return None;
        }
        let Ok(next) = load(&self.path) else {
            return None;
        };
        self.pending = None;
        if next == self.current {
            return None;
        }
        self.current = next;
        // R-11-242/R-11-243: loss of a palette clears every grid override.
        Some(self.current.clone().unwrap_or_else(reset))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn catalogue_matches_desktop_grid_colors() {
        let vesper = resolve("[theme]\nname = 'vesper'", false).unwrap();
        assert_eq!(vesper.surface_dim, "#101010");
        assert_eq!(vesper.text, "#D0D0D0");
        let terminal = resolve("[theme]\nname = 'terminal'", false).unwrap();
        assert_eq!(terminal.surface_dim, "#808080");
        assert_eq!(terminal.text, "reset");
    }

    #[test]
    fn config_selects_only_theme_keys_and_respects_auto_switch() {
        let config = r#"name = 'dracula'
[theme]
name = 'vesper' # The selected fixed theme.
dark_name = 'nord'
light_name = 'one-light'
auto_switch = false
[theme.custom]
text = '#000000'
[other]
name = 'terminal'
"#;
        assert_eq!(resolve(config, true).unwrap(), palette("vesper").unwrap());
        let automatic = config.replace("auto_switch = false", "auto_switch = true");
        assert_eq!(resolve(&automatic, false).unwrap().name, "nord");
        assert_eq!(resolve(&automatic, true).unwrap().name, "one-light");
        assert_eq!(
            resolve("[theme]\nname = 'Tokyo_Night'\nauto_switch = true", true)
                .unwrap()
                .name,
            "tokyo-night-day"
        );
        assert_eq!(
            resolve("[theme]\nauto_switch = true", false).unwrap().name,
            "catppuccin"
        );
        assert_eq!(
            resolve("[theme]\nauto_switch = true", true).unwrap().name,
            "catppuccin-latte"
        );
        assert!(resolve("[other]\nname = 'vesper'", false).is_none());
        assert!(resolve("[theme]\nname = 'unknown'", false).is_none());
        assert!(resolve("[theme]\nauto_switch = true\nlight_name = 'unknown'", true).is_none());
        assert!(resolve("[theme]\nname = [", false).is_none());
    }

    #[test]
    fn watcher_debounces_changes_and_clears_a_removed_config_once() {
        let directory = std::env::temp_dir().join(format!("herdr-theme-{}", uuid::Uuid::new_v4()));
        std::fs::create_dir(&directory).unwrap();
        let path = directory.join("config.toml");
        let stamp = SystemTime::now();
        let write = |name: &str, seconds: u64| {
            std::fs::write(&path, format!("[theme]\nname = '{name}'")).unwrap();
            std::fs::File::options()
                .write(true)
                .open(&path)
                .unwrap()
                .set_modified(stamp + Duration::from_secs(seconds))
                .unwrap();
        };
        write("vesper", 0);
        let now = Instant::now();
        let mut watcher = Watcher::at(path.clone(), now);
        assert_eq!(watcher.current.as_ref().unwrap().name, "vesper");
        write("nord", 1);
        assert!(watcher.poll(now + Duration::from_millis(1999)).is_none());
        assert!(watcher.poll(now + Duration::from_secs(2)).is_none());
        assert!(watcher.poll(now + Duration::from_millis(2499)).is_none());
        write("terminal", 2);
        assert!(watcher.poll(now + Duration::from_millis(2500)).is_none());
        assert_eq!(
            watcher.poll(now + Duration::from_secs(3)).unwrap().name,
            "terminal"
        );
        write("terminal", 3);
        assert!(watcher.poll(now + Duration::from_secs(5)).is_none());
        assert!(watcher.poll(now + Duration::from_millis(5500)).is_none());
        std::fs::remove_file(&path).unwrap();
        assert!(watcher.poll(now + Duration::from_millis(7500)).is_none());
        assert_eq!(watcher.poll(now + Duration::from_secs(8)).unwrap(), reset());
        assert!(watcher.current.is_none());
        assert!(watcher.poll(now + Duration::from_secs(10)).is_none());
        write("vesper", 4);
        assert!(watcher.poll(now + Duration::from_secs(12)).is_none());
        assert_eq!(
            watcher
                .poll(now + Duration::from_millis(12500))
                .unwrap()
                .name,
            "vesper"
        );
        std::fs::remove_dir_all(directory).unwrap();
    }
}
