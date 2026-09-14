# relayctl.ps1 - forwards a relay control subcommand (status, clients,
# refresh, stop, revoke <device_id>) to the herdr-relay binary's `ctl`
# subcommand (R-10-067) and forwards its exit code. All application logic
# lives in the Rust binary (R-41-139).
param([Parameter(ValueFromRemainingArguments)][string[]]$RelayArgs = @())

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'common.ps1')

& $RelayBin ctl @RelayArgs
exit $LASTEXITCODE
