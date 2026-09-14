Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# test-plugin-root.ps1 - asserts common.ps1 resolves $PluginRoot from
# HERDR_PLUGIN_ROOT directly, and by discovery through a stubbed `herdr`
# CLI when the variable is absent, stripping a \\?\ verbatim prefix in both
# cases (R-41-138, R-41-140, R-10-046, R-41-133).

$ErrorCount = 0
function Assert-Equal([string]$Actual, [string]$Expected, [string]$Case) {
    if ($Actual -ne $Expected) {
        Write-Host "FAIL: $Case -- expected '$Expected', got '$Actual'"
        $script:ErrorCount++
    } else {
        Write-Host "ok: $Case"
    }
}

$CommonPs1 = Join-Path $PSScriptRoot '..\..\windows\common.ps1'
$Root = Join-Path ([System.IO.Path]::GetTempPath()) ("herdr-relay-test-" + [guid]::NewGuid())
New-Item -ItemType Directory -Force -Path $Root | Out-Null
New-Item -ItemType File -Path (Join-Path $Root 'herdr-relay.exe') | Out-Null

try {
    # Case 1: HERDR_PLUGIN_ROOT set directly with a verbatim prefix, the form
    # measured live in docs/10-herdr-integration.md section 7.2.
    $env:HERDR_PLUGIN_ROOT = '\\?\' + $Root
    Remove-Item Env:HERDR_BIN_PATH -ErrorAction SilentlyContinue
    . $CommonPs1
    Assert-Equal $PluginRoot $Root 'HERDR_PLUGIN_ROOT set directly, prefix stripped'

    # Case 2: HERDR_PLUGIN_ROOT absent, discovered through a stubbed herdr CLI
    # that reports a \\?\-prefixed plugin_root, the shape a Task Scheduler
    # invocation (no herdr environment) must handle.
    Remove-Item Env:HERDR_PLUGIN_ROOT -ErrorAction SilentlyContinue
    $stubObj = @{ result = @{ plugins = @(@{ plugin_id = 'herdr-relay'; plugin_root = ('\\?\' + $Root) }) } }
    $jsonBody = $stubObj | ConvertTo-Json -Depth 5 -Compress
    $jsonEscaped = $jsonBody -replace "'", "''"
    $stubHerdr = Join-Path $Root 'stub-herdr.ps1'
    Set-Content -Path $stubHerdr -Value "Write-Output '$jsonEscaped'" -Encoding UTF8
    $env:HERDR_BIN_PATH = $stubHerdr
    . $CommonPs1
    Assert-Equal $PluginRoot $Root 'discovered via herdr plugin list --json, prefix stripped'

    # Case 3: the exact `plugin_root` value measured against a real `herdr
    # plugin link crates/herdr-relay` on this workstation (R-10-046,
    # R-41-133), verified stripped via the shared Remove-VerbatimPrefix
    # helper (R-41-140), locked in as a regression fixture so this assertion
    # does not depend on a live Herdr install or an active link at test time.
    # Measured 2026-08-27 with `herdr plugin list --json` after
    # `herdr plugin link C:/Development/Repositories/other/herdr-mobile/crates/herdr-relay`:
    # plugin_root was `\\?\D:\Repositories\other\herdr-mobile\crates\herdr-relay`
    # -- the same D:\Repositories\... substitute-drive shape already measured
    # for herdr-scheduled in docs/10-herdr-integration.md section 7.2.
    $Measured = '\\?\D:\Repositories\other\herdr-mobile\crates\herdr-relay'
    $Stripped = Remove-VerbatimPrefix $Measured
    Assert-Equal $Stripped 'D:\Repositories\other\herdr-mobile\crates\herdr-relay' 'live-measured plugin_root, prefix stripped'
} finally {
    Remove-Item Env:HERDR_PLUGIN_ROOT, Env:HERDR_BIN_PATH -ErrorAction SilentlyContinue
    Remove-Item -Recurse -Force $Root -ErrorAction SilentlyContinue
}

if ($ErrorCount -gt 0) { Write-Host "$ErrorCount failure(s)"; exit 1 }
Write-Host 'all tests passed'
exit 0
