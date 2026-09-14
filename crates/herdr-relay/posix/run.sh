#!/bin/sh
set -eu
# run.sh - launches the herdr-relay bridge binary and forwards its exit code.
# With no arguments it runs the long-lived bridge; with `popup` it renders
# the pairing popup pane. All application logic lives in the Rust binary
# (R-41-139).

: "${HERDR_PLUGIN_ROOT:?herdr-relay: HERDR_PLUGIN_ROOT not set}"
. "$HERDR_PLUGIN_ROOT/posix/common.sh"
exec "$HERDR_RELAY_BIN" "$@"
