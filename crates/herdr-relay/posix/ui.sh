#!/bin/sh
set -eu
# ui.sh - launches the herdr-relay binary in popup mode to render the
# pairing QR code, the six-word phrase, and the paired-device list. All
# rendering logic lives in the Rust binary's popup screen (R-41-139); the
# popup screen itself does not yet exist (WP-10-c adds it).

: "${HERDR_PLUGIN_ROOT:?herdr-relay: HERDR_PLUGIN_ROOT not set}"
. "$HERDR_PLUGIN_ROOT/posix/common.sh"
exec "$HERDR_RELAY_BIN" popup
