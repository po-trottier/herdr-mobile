Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# test-ensure-service.ps1 - asserts ensure-service.ps1 reconciles the
# \Herdr\herdr-relay Task Scheduler job idempotently, never starts the task
# more than once across two reconciles (R-10-049, R-10-050, R-40-029,
# R-40-030), and installs the default pairing key binding through the binary's
# `install-keybind` subcommand for every R-10-060 case.
#
# Standalone shim test: no test framework. The ScheduledTasks cmdlets
# ensure-service.ps1 calls are shadowed by stub functions defined in this
# scope before it is dot-sourced, so no real Task Scheduler job is ever
# touched. The binary is the real debug build, copied into the stub plugin
# root; `herdr` itself is a fake `herdr.cmd` selected through HERDR_BIN_PATH,
# so the live Herdr server and the live config.toml are never read or written.

$ErrorCount = 0
function Assert-True([bool]$Condition, [string]$Case) {
    if (-not $Condition) {
        Write-Host "FAIL: $Case"
        $script:ErrorCount++
    } else {
        Write-Host "ok: $Case"
    }
}

# --- stub Task Scheduler ------------------------------------------------
$script:Tasks = @{}
$script:RegisterCalls = 0
$script:SetCalls = 0
$script:StartCalls = 0

function Get-ScheduledTask {
    [CmdletBinding()]
    param([string]$TaskName, [string]$TaskPath)
    $key = "$TaskPath|$TaskName"
    if ($script:Tasks.ContainsKey($key)) { return $script:Tasks[$key] }
    return $null
}
function Register-ScheduledTask {
    [CmdletBinding()]
    param([string]$TaskName, [string]$TaskPath, $Action, $Trigger, $Settings)
    $key = "$TaskPath|$TaskName"
    $script:Tasks[$key] = [PSCustomObject]@{ TaskName = $TaskName; TaskPath = $TaskPath; State = 'Ready' }
    $script:RegisterCalls++
    return $script:Tasks[$key]
}
function Set-ScheduledTask {
    [CmdletBinding()]
    param([string]$TaskName, [string]$TaskPath, $Action, $Trigger, $Settings)
    $script:SetCalls++
    return $script:Tasks["$TaskPath|$TaskName"]
}
function Start-ScheduledTask {
    [CmdletBinding()]
    param([string]$TaskName, [string]$TaskPath)
    $script:Tasks["$TaskPath|$TaskName"].State = 'Running'
    $script:StartCalls++
}
function New-ScheduledTaskAction {
    [CmdletBinding()]
    param([string]$Execute, [string]$Argument)
    $script:ActionExecute = $Execute
    $script:ActionArgument = $Argument
    return @{ Execute = $Execute; Argument = $Argument }
}
function New-ScheduledTaskTrigger {
    [CmdletBinding()]
    param([switch]$AtLogOn, [string]$User)
    $script:TriggerUser = $User
    return @{ AtLogOn = $true; User = $User }
}
function New-ScheduledTaskSettingsSet {
    [CmdletBinding()]
    param([int]$RestartCount, $RestartInterval, [switch]$AllowStartIfOnBatteries, [switch]$DontStopIfGoingOnBatteries, [switch]$StartWhenAvailable)
    return @{ RestartCount = $RestartCount }
}

# --- stub plugin root with the real binary, and a fake herdr -----------------
$Root = Join-Path ([System.IO.Path]::GetTempPath()) ("herdr-relay-test-" + [guid]::NewGuid())
New-Item -ItemType Directory -Force -Path (Join-Path $Root 'state') | Out-Null
$BuiltBin = Join-Path $PSScriptRoot '..\..\..\target\debug\herdr-relay.exe'
if (-not (Test-Path $BuiltBin)) { Write-Host "FAIL: build herdr-relay first: $BuiltBin is absent"; exit 1 }
Copy-Item $BuiltBin (Join-Path $Root 'herdr-relay.exe')
$Cfg = Join-Path $Root 'herdr\config.toml'
$Mode = Join-Path $Root 'mode.txt'
$Reloads = Join-Path $Root 'reload.log'
$RelayLog = Join-Path $Root 'state\relay.log'
$Marker = Join-Path $Root 'state\keybind.installed'
# Modes: default; nocfg (no Config: line); checkfail (config check exits 1).
@"
@echo off
set /p MODE=<"$Mode"
if "%1"=="--help" ( if "%MODE%"=="nocfg" ( echo Options: & exit /b 0 ) else ( echo Options: & echo Config: $Cfg & exit /b 0 ) )
if "%1"=="plugin" ( echo $Root\state & exit /b 0 )
if "%1"=="config" ( if "%MODE%"=="checkfail" ( exit /b 1 ) else ( exit /b 0 ) )
if "%1"=="server" ( echo reload>> "$Reloads" & exit /b 0 )
exit /b 1
"@ | Set-Content (Join-Path $Root 'herdr.cmd') -Encoding ascii
Set-Content $Mode 'default' -Encoding ascii
function Reset-Keybind { Remove-Item $Marker, $Cfg -Force -ErrorAction SilentlyContinue }
function Reload-Count { if (Test-Path $Reloads) { @(Get-Content $Reloads).Count } else { 0 } }
$Block = "[[keys.command]]`nkey = `"prefix+shift+m`"`ntype = `"plugin_action`"`ncommand = `"herdr-relay.pair-windows`""

$EnsureServicePs1 = Join-Path $PSScriptRoot '..\..\windows\ensure-service.ps1'

try {
    $env:HERDR_PLUGIN_ROOT = $Root
    $env:HERDR_BIN_PATH = Join-Path $Root 'herdr.cmd'

    # --- service reconcile, plus R-10-060 case 2: clean install, no config.toml ---
    . $EnsureServicePs1
    Assert-True ($script:Tasks.ContainsKey('\Herdr\|herdr-relay')) 'first reconcile registers the task'
    Assert-True ($script:RegisterCalls -eq 1) 'first reconcile registers exactly once'
    Assert-True ($script:StartCalls -eq 1) 'first reconcile starts the task'
    Assert-True ($script:Tasks['\Herdr\|herdr-relay'].State -eq 'Running') 'task is running after the first reconcile'
    # Measured live: an unscoped -AtLogOn trigger ("any user") needs elevation and
    # Register-ScheduledTask denies it for a standard user. The shim MUST scope the
    # trigger to the current user, or the bridge never runs on a standard account.
    Assert-True ($script:TriggerUser -eq $env:USERNAME) 'logon trigger is scoped to the current user, not "any user"'
    # Measured live: a console binary started by Task Scheduler in the interactive
    # session opens a visible console window. The action MUST be the hidden
    # PowerShell host running run.ps1 (R-41-079 path), never the binary itself.
    Assert-True ($script:ActionExecute -eq 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe') 'task action is the fixed powershell.exe, not the console binary'
    Assert-True ($script:ActionArgument.Contains('-WindowStyle Hidden')) 'task action runs the host hidden'
    Assert-True ($script:ActionArgument -match '-File "[^"]*\\run\.ps1"') 'task action runs run.ps1'
    Assert-True (Test-Path $Cfg) 'keybind: a missing config.toml is created'
    $created = Get-Content $Cfg -Raw
    Assert-True ($created.Contains($Block) -and $created.Contains('description = "pair a phone"')) 'keybind: created file holds the pair-windows block'
    Assert-True ($created.StartsWith('# herdr-relay: default pairing binding')) 'keybind: created file starts with the marker comment'
    Assert-True (Test-Path $Marker) 'keybind: marker written after the first decision'
    Assert-True ((Get-Content $Marker -Raw) -eq "created`n") 'keybind: marker holds only the case name, never the config path'
    Assert-True ((Reload-Count) -eq 1) 'keybind: reload-config called once after a create'
    Assert-True ((Get-Content $RelayLog -Raw).Contains('created config.toml')) 'keybind: relay.log records the create'

    # --- second reconcile: marker honoured, nothing rewritten ---
    $hashBefore = (Get-FileHash $Cfg).Hash
    . $EnsureServicePs1
    Assert-True ($script:Tasks.Count -eq 1) 'second reconcile does not create a second task'
    Assert-True ($script:RegisterCalls -eq 1) 'second reconcile does not re-register'
    Assert-True ($script:SetCalls -eq 1) 'second reconcile updates the existing task'
    Assert-True ($script:StartCalls -eq 1) 'second reconcile does not start an already-running task again'
    Assert-True ((Get-FileHash $Cfg).Hash -eq $hashBefore) 'keybind: second run writes nothing'
    Assert-True ((Reload-Count) -eq 1) 'keybind: second run does not reload'

    # --- case 5: append preserves every existing line and comment ---
    Reset-Keybind
    $existing = "# user note`nonboarding = false`n[[keys.command]]`nkey = `"prefix+f`"`ntype = `"plugin_action`"`ncommand = `"herdr-sidebar.open-sidebar-windows`""
    New-Item -ItemType Directory -Force -Path (Split-Path $Cfg) | Out-Null
    Set-Content $Cfg $existing -Encoding ascii -NoNewline
    . $EnsureServicePs1
    $appended = Get-Content $Cfg -Raw
    Assert-True ($appended.StartsWith($existing)) 'keybind: append keeps every existing byte as a prefix'
    Assert-True ($appended.Contains("`n`n# herdr-relay: default pairing binding")) 'keybind: append separates the block with one blank line'
    Assert-True ($appended.Contains($Block)) 'keybind: appended block is the pair-windows block'
    Assert-True ((Reload-Count) -eq 2) 'keybind: reload-config called after an append'

    # --- case 3: an existing pair binding under another key wins ---
    Reset-Keybind
    $custom = "[[keys.command]]`nkey = `"prefix+alt+m`"`ntype = `"plugin_action`"`ncommand = `"herdr-relay.pair-windows`"`n"
    Set-Content $Cfg $custom -Encoding ascii -NoNewline
    . $EnsureServicePs1
    Assert-True ((Get-Content $Cfg -Raw) -eq $custom) 'keybind: existing pair binding under another key leaves the file untouched'
    Assert-True (Test-Path $Marker) 'keybind: a customised binding still records the decision'

    # --- case 4: prefix+shift+m taken by another command ---
    Reset-Keybind
    $taken = "[[keys.command]]`nkey = `"prefix+shift+m`"`ntype = `"popup`"`ncommand = `"lazygit`"`n"
    Set-Content $Cfg $taken -Encoding ascii -NoNewline
    . $EnsureServicePs1
    Assert-True ((Get-Content $Cfg -Raw) -eq $taken) 'keybind: an occupied default key is never overwritten'
    Assert-True ((Get-Content $RelayLog -Raw).Contains('taken by another command')) 'keybind: relay.log names the occupied key'
    Assert-True (-not (Get-Content $RelayLog -Raw).Contains('lazygit')) 'keybind: relay.log never echoes the occupying command'

    # --- case 1: no Config: line ---
    Reset-Keybind
    Set-Content $Mode 'nocfg' -Encoding ascii
    . $EnsureServicePs1
    Assert-True (-not (Test-Path $Cfg)) 'keybind: unresolved path writes nothing'
    Assert-True (-not (Test-Path $Marker)) 'keybind: unresolved path writes no marker, so the next start retries'
    Assert-True ((Get-Content $RelayLog -Raw).Contains('could not resolve')) 'keybind: relay.log records the unresolved path'
    Set-Content $Mode 'default' -Encoding ascii

    # --- failed check: created file is deleted; existing bytes are restored ---
    Reset-Keybind
    Set-Content $Mode 'checkfail' -Encoding ascii
    $reloadsBefore = Reload-Count
    . $EnsureServicePs1
    Assert-True (-not (Test-Path $Cfg)) 'keybind: a failed check deletes the file it created'
    Assert-True ((Reload-Count) -eq $reloadsBefore) 'keybind: a failed check never reloads'
    Assert-True (-not (Test-Path $Marker)) 'keybind: a failed check leaves no marker, so the next start retries'
    Set-Content $Cfg $existing -Encoding ascii -NoNewline
    . $EnsureServicePs1
    Assert-True ((Get-Content $Cfg -Raw) -eq $existing) 'keybind: a failed check restores the original bytes'
    Set-Content $Mode 'default' -Encoding ascii
} finally {
    Remove-Item Env:HERDR_PLUGIN_ROOT, Env:HERDR_BIN_PATH -ErrorAction SilentlyContinue
    Remove-Item -Recurse -Force $Root -ErrorAction SilentlyContinue
}

if ($ErrorCount -gt 0) { Write-Host "$ErrorCount failure(s)"; exit 1 }
Write-Host 'all tests passed'
exit 0
