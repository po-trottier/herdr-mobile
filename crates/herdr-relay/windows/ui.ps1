Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ui.ps1 - launches the herdr-relay binary in popup mode to render the
# pairing QR code, the six-word phrase, and the paired-device list. All
# rendering logic lives in the Rust binary's popup screen (R-41-139); the
# popup screen itself does not yet exist (WP-10-c adds it).

. (Join-Path $PSScriptRoot 'common.ps1')

# The half-block QR glyphs are not ASCII (R-31-16-12).
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

& $RelayBin popup
exit $LASTEXITCODE
