# Shared helpers for the herdr-relay POSIX scripts. Sourced by the others:
#   . "$HERDR_PLUGIN_ROOT/posix/common.sh"
set -eu

# --- plugin root (R-41-136, R-41-137) ----------------------------------------
: "${HERDR_PLUGIN_ROOT:?herdr-relay: HERDR_PLUGIN_ROOT not set}"

# --- the bridge binary --------------------------------------------------------
# Bundled beside the manifest in an installed plugin, or built by cargo into
# the workspace target directory during development. The Rust binary owns
# every behaviour; this is the only lookup a shim performs (R-41-139). A
# bundled binary wins. Between the two cargo profiles the newest build wins:
# a stale release build from an earlier protocol must not shadow a fresh
# debug build (same rule as windows/common.ps1).
HERDR_RELAY_BIN=
if [ -x "$HERDR_PLUGIN_ROOT/herdr-relay" ]; then
    HERDR_RELAY_BIN="$HERDR_PLUGIN_ROOT/herdr-relay"
else
    for _cand in \
        "$HERDR_PLUGIN_ROOT/../target/release/herdr-relay" \
        "$HERDR_PLUGIN_ROOT/../target/debug/herdr-relay"; do
        [ -x "$_cand" ] || continue
        if [ -z "$HERDR_RELAY_BIN" ] || [ "$_cand" -nt "$HERDR_RELAY_BIN" ]; then
            HERDR_RELAY_BIN=$_cand
        fi
    done
fi
: "${HERDR_RELAY_BIN:?herdr-relay: no herdr-relay binary found under $HERDR_PLUGIN_ROOT}"

# --- OS kind -------------------------------------------------------------
# posix/ covers both Linux and macOS; the supervisor mechanism differs
# per R-10-049.
os_kind() {  # os_kind -> "linux" or "macos" on stdout; exit 2 on anything else
    case "$(uname -s)" in
        Linux)  printf 'linux\n' ;;
        Darwin) printf 'macos\n' ;;
        *) printf 'herdr-relay: unsupported OS %s\n' "$(uname -s)" >&2; exit 2 ;;
    esac
}

# --- error helper (R-41-148 to R-41-152) --------------------------------------
fail() {  # fail <exit-code> <message>: write the message to stderr, exit
    printf 'herdr-relay: %s\n' "$2" >&2
    exit "$1"
}
