#!/bin/sh
# test-ensure-service.sh - asserts ensure-service.sh reconciles the systemd
# user unit idempotently against a stubbed systemctl, and never runs the
# bridge in the foreground (R-10-049, R-10-050, R-40-029, R-40-030). Also
# proves the scripts locate the plugin root via HERDR_PLUGIN_ROOT (R-41-136)
# and fail with the exact :? message when it is unset (R-41-137), require no
# jq/python/perl (R-41-055), and that the sourced
# common.sh carries no shebang but does carry set -eu (R-41-057).
#
# Standalone shim test: no test framework, a stub systemctl and uname, and
# a temp HOME and plugin root. The real committed posix/ scripts are copied
# into the temp plugin root and run unmodified, so this exercises the exact
# files shipped in the plugin.
set -eu

fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }

REAL_PLUGIN_ROOT=$(CDPATH= cd "$(dirname "$0")/../.." && pwd)

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT INT TERM

# --- stub plugin root: the real scripts plus a placeholder binary -----------
PLUGIN_ROOT=$TMP/plugin
mkdir -p "$PLUGIN_ROOT/posix"
cp "$REAL_PLUGIN_ROOT/posix/common.sh" "$PLUGIN_ROOT/posix/common.sh"
cp "$REAL_PLUGIN_ROOT/posix/run.sh" "$PLUGIN_ROOT/posix/run.sh"
cp "$REAL_PLUGIN_ROOT/posix/ensure-service.sh" "$PLUGIN_ROOT/posix/ensure-service.sh"
: > "$PLUGIN_ROOT/herdr-relay"
chmod +x "$PLUGIN_ROOT/herdr-relay"

# --- stub uname (force the Linux branch) and systemctl (record, never touch
# the real service manager) -------------------------------------------------
STUB_BIN=$TMP/bin
mkdir -p "$STUB_BIN"
cat > "$STUB_BIN/uname" <<'EOF'
#!/bin/sh
echo Linux
EOF
chmod +x "$STUB_BIN/uname"

CALLS=$TMP/systemctl.calls
: > "$CALLS"
cat > "$STUB_BIN/systemctl" <<EOF
#!/bin/sh
echo "\$*" >> "$CALLS"
exit 0
EOF
chmod +x "$STUB_BIN/systemctl"

export HOME=$TMP/home
mkdir -p "$HOME"
export HERDR_PLUGIN_ROOT=$PLUGIN_ROOT
export PATH=$STUB_BIN:$PATH

UNIT_FILE=$HOME/.config/systemd/user/herdr-relay.service

sh "$PLUGIN_ROOT/posix/ensure-service.sh" || fail "first reconcile exited non-zero"
[ -f "$UNIT_FILE" ] || fail "unit file was not written"
FIRST_SUM=$(cksum < "$UNIT_FILE")
FIRST_CALL_COUNT=$(wc -l < "$CALLS")
[ "$FIRST_CALL_COUNT" -ge 3 ] || fail "expected systemctl daemon-reload/enable/start on the first reconcile"

sh "$PLUGIN_ROOT/posix/ensure-service.sh" || fail "second reconcile exited non-zero"
SECOND_SUM=$(cksum < "$UNIT_FILE")
[ "$FIRST_SUM" = "$SECOND_SUM" ] || fail "reconcile is not idempotent: unit file changed on second run"

# The reconcile must only ever manage the unit, never run the bridge itself.
if grep -q ExecStart=/bin/sh "$UNIT_FILE" && grep -q "$PLUGIN_ROOT/posix/run.sh" "$UNIT_FILE"; then
    :
else
    fail "unit file does not point ExecStart at run.sh"
fi

printf 'ok: ensure-service.sh reconciles the systemd unit idempotently\n'

# --- no jq/python/perl invocation in any shipped posix/*.sh (R-41-055) ------
for f in "$REAL_PLUGIN_ROOT"/posix/*.sh; do
    if grep -Eq '(^|[^A-Za-z0-9_./-])(jq|python[0-9.]*|perl)([^A-Za-z0-9_-]|$)' "$f"; then
        fail "$f invokes a non-POSIX tool (jq/python/perl), violating R-41-055"
    fi
done
printf 'ok: posix/*.sh scripts require no jq/python/perl\n'

# --- common.sh is a sourced library: no shebang, but carries set -eu (R-41-057)
COMMON_SH=$REAL_PLUGIN_ROOT/posix/common.sh
case "$(sed -n '1p' "$COMMON_SH")" in
    '#!'*) fail "common.sh must not carry a shebang" ;;
esac
grep -qx 'set -eu' "$COMMON_SH" || fail "common.sh must carry set -eu"
printf 'ok: common.sh has no shebang and carries set -eu\n'

# --- HERDR_PLUGIN_ROOT unset triggers the exact :? failure (R-41-137) ------
# The literal exit code of a `:?` failure is shell-dependent (dash exits 2,
# bash exits 1); both are POSIX-valid non-zero exits, so this checks the
# portable contract: the script stops and the exact configured message
# reaches stderr, not a specific numeric code.
set +e
(unset HERDR_PLUGIN_ROOT; sh "$PLUGIN_ROOT/posix/ensure-service.sh") \
    >"$TMP/unset.stdout" 2>"$TMP/unset.stderr"
UNSET_STATUS=$?
set -e
[ "$UNSET_STATUS" -ne 0 ] || fail "expected a non-zero exit with HERDR_PLUGIN_ROOT unset"
[ -s "$TMP/unset.stdout" ] && fail "expected no stdout when HERDR_PLUGIN_ROOT is unset"
grep -qF 'herdr-relay: HERDR_PLUGIN_ROOT not set' "$TMP/unset.stderr" ||
    fail "expected the exact :? message on stderr when HERDR_PLUGIN_ROOT is unset"
printf 'ok: ensure-service.sh stops with the exact message when HERDR_PLUGIN_ROOT is unset\n'

# --- R-10-060: the default pairing key binding, every case, through the real
# shim and the real binary against a fake herdr. The fake herdr is selected by
# HERDR_BIN_PATH, so the live server and the live config.toml are never
# touched. Written on Windows and reviewed only there (R-41-146); run it on
# Linux or macOS before the twin is trusted. --------------------------------
BUILT_BIN=$REAL_PLUGIN_ROOT/../target/debug/herdr-relay
[ -x "$BUILT_BIN" ] || fail "build herdr-relay first: $BUILT_BIN is absent"
cp "$BUILT_BIN" "$PLUGIN_ROOT/herdr-relay"
STATE=$TMP/state
CFG=$TMP/herdr/config.toml
MODE=$TMP/mode
RELOADS=$TMP/reload.log
mkdir -p "$STATE"
printf 'default\n' > "$MODE"
cat > "$STUB_BIN/herdr" <<EOF
#!/bin/sh
mode=\$(cat "$MODE")
case "\$1" in
    --help) echo 'Options:'; [ "\$mode" = nocfg ] || echo "Config: $CFG"; exit 0 ;;
    plugin) echo "$STATE"; exit 0 ;;
    config) [ "\$mode" = checkfail ] && exit 1; exit 0 ;;
    server) echo reload >> "$RELOADS"; exit 0 ;;
esac
exit 1
EOF
chmod +x "$STUB_BIN/herdr"
export HERDR_BIN_PATH=$STUB_BIN/herdr
reloads() { [ -f "$RELOADS" ] && wc -l < "$RELOADS" || echo 0; }
reset_keybind() { rm -f "$STATE/keybind.installed" "$CFG"; }
BLOCK='command = "herdr-relay.pair"'

# case 2: clean install, no config.toml
reset_keybind
sh "$PLUGIN_ROOT/posix/ensure-service.sh" >/dev/null || fail "keybind: reconcile with no config.toml exited non-zero"
[ -f "$CFG" ] || fail "keybind: a missing config.toml must be created"
grep -qF "$BLOCK" "$CFG" || fail "keybind: created file must hold the pair block"
grep -qF 'description = "pair a phone"' "$CFG" || fail "keybind: created block must carry the description"
[ "$(sed -n 1p "$CFG")" = '# herdr-relay: default pairing binding. Change the key here; the plugin never rewrites this block.' ] || fail "keybind: created file must start with the marker comment"
[ -f "$STATE/keybind.installed" ] || fail "keybind: marker must exist after the first decision"
[ "$(cat "$STATE/keybind.installed")" = created ] || fail "keybind: marker must hold only the case name, never the config path"
[ "$(reloads)" -eq 1 ] || fail "keybind: reload-config must run once after a create"
grep -qF 'created config.toml' "$STATE/relay.log" || fail "keybind: relay.log must record the create"

# second run: marker honoured
SUM=$(cksum < "$CFG")
sh "$PLUGIN_ROOT/posix/ensure-service.sh" >/dev/null || fail "keybind: second reconcile exited non-zero"
[ "$(cksum < "$CFG")" = "$SUM" ] || fail "keybind: second run must write nothing"
[ "$(reloads)" -eq 1 ] || fail "keybind: second run must not reload"

# case 5: append preserves every existing line and comment
reset_keybind
mkdir -p "$(dirname "$CFG")"
printf '# user note\nonboarding = false\n[[keys.command]]\nkey = "prefix+f"\ntype = "plugin_action"\ncommand = "herdr-sidebar.open-sidebar"' > "$CFG"
cp "$CFG" "$TMP/existing"
sh "$PLUGIN_ROOT/posix/ensure-service.sh" >/dev/null || fail "keybind: append reconcile exited non-zero"
head -c "$(wc -c < "$TMP/existing")" "$CFG" | cmp -s - "$TMP/existing" || fail "keybind: append must keep every existing byte as a prefix"
grep -qF "$BLOCK" "$CFG" || fail "keybind: appended block must be the pair block"
[ "$(reloads)" -eq 2 ] || fail "keybind: reload-config must run after an append"

# case 3: an existing pair binding under another key wins
reset_keybind
printf '[[keys.command]]\nkey = "prefix+alt+m"\ntype = "plugin_action"\ncommand = "herdr-relay.pair"\n' > "$CFG"
cp "$CFG" "$TMP/custom"
sh "$PLUGIN_ROOT/posix/ensure-service.sh" >/dev/null || fail "keybind: customised reconcile exited non-zero"
cmp -s "$CFG" "$TMP/custom" || fail "keybind: an existing pair binding under another key must leave the file untouched"

# case 4: prefix+shift+m taken by another command
reset_keybind
printf '[[keys.command]]\nkey = "prefix+shift+m"\ntype = "popup"\ncommand = "lazygit"\n' > "$CFG"
cp "$CFG" "$TMP/taken"
sh "$PLUGIN_ROOT/posix/ensure-service.sh" >/dev/null || fail "keybind: occupied-key reconcile exited non-zero"
cmp -s "$CFG" "$TMP/taken" || fail "keybind: an occupied default key must never be overwritten"
grep -qF 'taken by another command' "$STATE/relay.log" || fail "keybind: relay.log must name the occupied key"
grep -qF lazygit "$STATE/relay.log" && fail "keybind: relay.log must never echo the occupying command"

# case 1: no Config: line
reset_keybind
printf 'nocfg\n' > "$MODE"
sh "$PLUGIN_ROOT/posix/ensure-service.sh" >/dev/null || fail "keybind: unresolved-path reconcile exited non-zero"
[ ! -e "$CFG" ] || fail "keybind: an unresolved path must write nothing"
[ ! -e "$STATE/keybind.installed" ] || fail "keybind: an unresolved path must write no marker, so the next start retries"
grep -qF 'could not resolve' "$STATE/relay.log" || fail "keybind: relay.log must record the unresolved path"
printf 'default\n' > "$MODE"

# failed check: a created file is deleted; existing bytes are restored
reset_keybind
printf 'checkfail\n' > "$MODE"
BEFORE=$(reloads)
sh "$PLUGIN_ROOT/posix/ensure-service.sh" >/dev/null 2>&1 && fail "keybind: a failed check must make the shim exit non-zero"
[ ! -e "$CFG" ] || fail "keybind: a failed check must delete the file it created"
[ "$(reloads)" -eq "$BEFORE" ] || fail "keybind: a failed check must never reload"
[ ! -e "$STATE/keybind.installed" ] || fail "keybind: a failed check must leave no marker"
cp "$TMP/existing" "$CFG"
sh "$PLUGIN_ROOT/posix/ensure-service.sh" >/dev/null 2>&1 && fail "keybind: a failed check on an existing file must exit non-zero"
cmp -s "$CFG" "$TMP/existing" || fail "keybind: a failed check must restore the original bytes"
printf 'default\n' > "$MODE"
printf 'ok: ensure-service.sh installs the default pairing key binding for every R-10-060 case\n'
