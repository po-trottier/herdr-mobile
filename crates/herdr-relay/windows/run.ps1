# run.ps1 - launches the herdr-relay bridge binary and forwards its exit
# code. With no arguments it runs the long-lived bridge; with `popup` it
# renders the pairing popup pane. All application logic lives in the Rust
# binary (R-41-139).
param([Parameter(ValueFromRemainingArguments)][string[]]$RelayArgs = @())

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'common.ps1')

# The half-block QR glyphs are not ASCII (R-31-16-12).
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

& $RelayBin @RelayArgs
exit $LASTEXITCODE
