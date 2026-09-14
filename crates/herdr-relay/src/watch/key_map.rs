//! Pure `keys` vocabulary validation for `send_input` (`docs/10-herdr-integration.md`
//! §6.2 through §6.7: R-10-036 through R-10-039). No Herdr call and no [`super::Bridge`]
//! state, so `tests/input_map.rs` exercises every accepted and rejected name with
//! no stub server. Every name here was probed live against Herdr `0.8.0`
//! (`docs/10-herdr-integration.md` §6.1); a rejected name returns `invalid_key`.

use std::fmt;

/// A `keys` entry the bridge MUST refuse before it reaches Herdr (R-11-055).
#[derive(Debug, Clone, PartialEq, Eq)]
pub(super) struct RejectedKey(pub(super) String);

impl fmt::Display for RejectedKey {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "unsupported key {:?}", self.0)
    }
}

/// Bare names Herdr accepts (§6.2), lowercased for this module's case-insensitive
/// match throughout (§6.2: "Names are case-insensitive").
const NAMED_KEYS: &[&str] = &[
    "up",
    "down",
    "left",
    "right",
    "enter",
    "return",
    "tab",
    "esc",
    "escape",
    "backspace",
    "space",
];

/// Modifiers R-10-039 lets the Device send, in the required join order.
const PERMITTED_MODIFIERS: &[&str] = &["ctrl", "alt", "shift"];

/// Modifiers Herdr's own vocabulary accepts (§6.2) but R-10-039 forbids the Device
/// from sending, "because no terminal application consumes them and their encoding
/// is unverified". `win` (§6.3) is simply absent from both lists, so it falls
/// through to the same rejection as an unrecognised modifier.
const FORBIDDEN_MODIFIERS: &[&str] = &["super", "cmd", "meta"];

/// `true` for `F0` through `F99` (§6.2), case-insensitively.
fn is_function_key(lower: &str) -> bool {
    let Some(rest) = lower.strip_prefix('f') else {
        return false;
    };
    if rest.is_empty() || !rest.bytes().all(|b| b.is_ascii_digit()) {
        return false;
    }
    rest.parse::<u32>().is_ok_and(|n| n <= 99)
}

/// Validates one `keys` entry against the accepted vocabulary (§6.2) and the
/// explicitly rejected forms (§6.3, R-10-038, R-10-039). Case-insensitive; the
/// modifier separator is `+` only (`ctrl-c` and `^C` are rejected, matching §6.3).
pub(super) fn validate_key(raw: &str) -> Result<(), RejectedKey> {
    let lower = raw.to_ascii_lowercase();
    if let Some((modifiers, base)) = split_chord(&lower) {
        validate_chord(&modifiers, base, raw)
    } else if NAMED_KEYS.contains(&lower.as_str()) || is_function_key(&lower) {
        Ok(())
    } else {
        Err(RejectedKey(raw.to_string()))
    }
}

/// Splits `ctrl+alt+a` into (`["ctrl", "alt"]`, `"a"`). `None` for a name with no
/// `+`, which is not a chord and falls through to the plain-name check.
fn split_chord(lower: &str) -> Option<(Vec<&str>, &str)> {
    if !lower.contains('+') {
        return None;
    }
    let mut parts: Vec<&str> = lower.split('+').collect();
    let base = parts.pop()?;
    Some((parts, base))
}

/// R-10-038, R-10-039: modifiers MUST join in `ctrl`, `alt`, `shift` order, each at
/// most once, and `super`/`cmd`/`meta` (accepted by Herdr, forbidden from the
/// Device) and `win` (accepted by neither) are both rejected here.
fn validate_chord(modifiers: &[&str], base: &str, raw: &str) -> Result<(), RejectedKey> {
    if modifiers.is_empty() || base.is_empty() {
        return Err(RejectedKey(raw.to_string()));
    }
    if modifiers
        .iter()
        .any(|m| !PERMITTED_MODIFIERS.contains(m) || FORBIDDEN_MODIFIERS.contains(m))
    {
        return Err(RejectedKey(raw.to_string()));
    }
    let expected: Vec<&str> = PERMITTED_MODIFIERS
        .iter()
        .filter(|m| modifiers.contains(m))
        .copied()
        .collect();
    if modifiers != expected.as_slice() {
        return Err(RejectedKey(raw.to_string())); // out-of-order or repeated
    }
    let is_valid_base = base.chars().count() == 1 || NAMED_KEYS.contains(&base);
    if is_valid_base {
        Ok(())
    } else {
        Err(RejectedKey(raw.to_string()))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn accepts_every_row_of_the_accepted_table() {
        for name in [
            "Up",
            "Down",
            "Left",
            "Right",
            "Enter",
            "Return",
            "Tab",
            "Esc",
            "escape",
            "Escape",
            "Backspace",
            "Space",
            "F1",
            "F99",
            "F0",
            "ctrl+c",
            "Ctrl+C",
            "CTRL+C",
            "ctrl+shift+c",
            "ctrl+alt+a",
            "alt+b",
            "shift+tab",
        ] {
            assert!(validate_key(name).is_ok(), "{name} should be accepted");
        }
    }

    #[test]
    fn rejects_super_cmd_meta_from_the_device() {
        for name in ["super+a", "cmd+a", "meta+a"] {
            assert!(
                validate_key(name).is_err(),
                "{name} must be refused (R-10-039)"
            );
        }
    }

    #[test]
    fn rejects_every_row_of_the_rejected_table() {
        for name in [
            "Home", "End", "PageUp", "PageDown", "Delete", "Insert", "Del", "Ins", "Newline",
            "BackTab", "ShiftTab", "M-x", "A-x", "S-Tab", "ctrl-c", "^C", "win+a",
        ] {
            assert!(validate_key(name).is_err(), "{name} should be rejected");
        }
    }
}
