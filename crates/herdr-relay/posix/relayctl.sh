#!/bin/sh
set -eu
# relayctl.sh - forwards a relay control subcommand (status, clients,
# refresh, stop, revoke <device_id>) to the herdr-relay binary's `ctl`
# subcommand (R-10-067) and forwards its exit code. All application logic
# lives in the Rust binary (R-41-139).

: "${HERDR_PLUGIN_ROOT:?herdr-relay: HERDR_PLUGIN_ROOT not set}"
. "$HERDR_PLUGIN_ROOT/posix/common.sh"
exec "$HERDR_RELAY_BIN" ctl "$@"
