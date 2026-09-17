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

# ponytail: Stop-ScheduledTask ends only this wrapper; the binary is not in a
# job object and survives. Its own Herdr probe exits it within 5 minutes of the
# server going away, so the orphan is bounded (R-10-049). Add a job object if
# an immediate stop ever matters.
& $RelayBin @RelayArgs
exit $LASTEXITCODE
