Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Shared state and helpers for the herdr-relay Windows scripts. Dot-source:
#   . (Join-Path $PSScriptRoot 'common.ps1')

# Plugin root: the injected variable, or discovered through `herdr plugin
# list --json` when a scheduled task invokes this with no herdr environment.
# The verbatim \\?\ prefix is stripped inline. This is the exact form
# required by R-41-138.
$r = $env:HERDR_PLUGIN_ROOT
if (-not $r) {
    $b = $env:HERDR_BIN_PATH
    if (-not $b) { $b = 'herdr' }
    $r = ((& $b plugin list --json | ConvertFrom-Json).result.plugins |
        Where-Object { $_.plugin_id -eq 'herdr-relay' }).plugin_root
}
if ($r -and $r.StartsWith('\\?\')) { $r = $r.Substring(4) }
$PluginRoot = $r

# The bridge binary: bundled beside the manifest in an installed plugin, or
# built by cargo into the workspace target directory during development. The
# Rust binary owns every behaviour; this is the only lookup a shim performs
# (R-41-139). A bundled binary wins. Between the two cargo profiles the
# newest build wins: measured live, a stale release build from an earlier
# protocol shadowed a fresh debug build and the task ran a bridge that
# refused the server.
$Bundled = Join-Path $PluginRoot 'herdr-relay.exe'
if (Test-Path $Bundled) {
    $RelayBin = $Bundled
} else {
    $RelayBin = @(
        (Join-Path $PluginRoot '..\target\release\herdr-relay.exe'),
        (Join-Path $PluginRoot '..\target\debug\herdr-relay.exe')
    ) | Where-Object { Test-Path $_ } | Sort-Object { (Get-Item $_).LastWriteTime } -Descending | Select-Object -First 1
}
if (-not $RelayBin) { throw "herdr-relay: no herdr-relay.exe binary found under $PluginRoot" }

# The general-purpose verbatim-prefix strip (R-41-140), for a path source
# other than HERDR_PLUGIN_ROOT, such as `plugin config-dir` output
# (R-41-141).
function Remove-VerbatimPrefix([string]$path) {
    if ($path -and $path.StartsWith('\\?\')) { return $path.Substring(4) }
    return $path
}
