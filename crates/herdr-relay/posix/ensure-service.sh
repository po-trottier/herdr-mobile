#!/bin/sh
set -eu
# ensure-service.sh - reconciles the OS user-service unit that supervises the
# herdr-relay bridge, then exits. It never runs the bridge in the foreground
# (R-10-050). One mechanism per platform: a systemd user unit on Linux, a
# launchd user agent on macOS (R-10-049).

: "${HERDR_PLUGIN_ROOT:?herdr-relay: HERDR_PLUGIN_ROOT not set}"
. "$HERDR_PLUGIN_ROOT/posix/common.sh"

RUN_SH=$HERDR_PLUGIN_ROOT/posix/run.sh

case "$(os_kind)" in
    linux)
        UNIT_DIR=${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user
        UNIT_FILE=$UNIT_DIR/herdr-relay.service
        mkdir -p "$UNIT_DIR" || fail 2 "cannot create $UNIT_DIR"
        cat > "$UNIT_FILE" <<EOF
[Unit]
Description=Herdr Relay bridge

[Service]
ExecStart=/bin/sh $RUN_SH
Restart=on-failure
RestartSec=5

[Install]
WantedBy=default.target
EOF
        command -v systemctl >/dev/null 2>&1 || fail 1 "systemctl not found; cannot manage the user service"
        systemctl --user daemon-reload || fail 2 "systemctl --user daemon-reload failed"
        systemctl --user enable herdr-relay.service || fail 2 "systemctl --user enable failed"
        systemctl --user start herdr-relay.service || fail 2 "systemctl --user start failed"
        ;;
    macos)
        AGENT_DIR=$HOME/Library/LaunchAgents
        AGENT_FILE=$AGENT_DIR/dev.herdr.relay.plist
        mkdir -p "$AGENT_DIR" || fail 2 "cannot create $AGENT_DIR"
        cat > "$AGENT_FILE" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>dev.herdr.relay</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/sh</string>
        <string>$RUN_SH</string>
    </array>
    <key>KeepAlive</key>
    <dict><key>SuccessfulExit</key><false/></dict>
    <key>RunAtLoad</key>
    <true/>
</dict>
</plist>
EOF
        command -v launchctl >/dev/null 2>&1 || fail 1 "launchctl not found; cannot manage the user agent"
        launchctl unload "$AGENT_FILE" >/dev/null 2>&1 || :
        launchctl load "$AGENT_FILE" || fail 2 "launchctl load failed"
        ;;
esac

# R-10-050/R-10-060: the hook's second idempotent step. The binary owns every
# decision and prints no user path; this shim only forwards a failure.
"$HERDR_RELAY_BIN" install-keybind --action pair || fail 2 "install-keybind failed"

printf 'herdr-relay: service reconciled\n'
