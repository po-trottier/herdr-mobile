Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ensure-service.ps1 - reconciles the \Herdr\herdr-relay Task Scheduler job
# that supervises the bridge, then exits. It never runs the bridge in the
# foreground (R-10-050). Restart every 1 minute, up to 999 times, triggered
# at logon (R-10-049). The action is `conhost.exe --headless` running a
# PowerShell host that executes run.ps1, never the console binary itself.
# Measured live 2026-09-17: with Windows Terminal as the default terminal
# (the Windows 11 default), `powershell -WindowStyle Hidden` still opens a
# visible Windows Terminal window, and closing that window kills the bridge.
# `conhost --headless` allocates a pseudoconsole with no window at all, for
# any default terminal setting (AGENTS.md, never spawn a console-visible
# child). run.ps1 executes the binary inline, so it inherits that console.

try {
    . (Join-Path $PSScriptRoot 'common.ps1')
} catch {
    # [Console]::Error.WriteLine, not Write-Error: measured live, Write-Error
    # itself becomes a terminating error under $ErrorActionPreference =
    # 'Stop' and re-throws past this catch block's own exit call, turning
    # the one clean line R-41-152 requires into a multi-line stack dump and
    # replacing this exit code with PowerShell's own default.
    [Console]::Error.WriteLine("herdr-relay: $($_.Exception.Message)")
    exit 1
}

try {
    $TaskPath = '\Herdr\'
    $TaskName = 'herdr-relay'
    $ConhostExe = 'C:\Windows\System32\conhost.exe'
    $PsExe = 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe'
    $RunPs1 = Join-Path $PSScriptRoot 'run.ps1'
    $action = New-ScheduledTaskAction -Execute $ConhostExe `
        -Argument ('--headless {0} -NoProfile -ExecutionPolicy Bypass -File "{1}"' -f $PsExe, $RunPs1)
    # -User: an unscoped -AtLogOn trigger means "any user" and needs
    # elevation; measured live, Register-ScheduledTask returns "Access is
    # denied" for a standard user. Scoped to this user it registers without
    # elevation, and this user is the one whose Herdr the bridge serves.
    $trigger = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
    # -ExecutionTimeLimit 0: Task Scheduler's default stops any task after 72 hours, and
    # the restart policy fires only on a failure exit, so a bridge older than three days
    # died silently until the next logon (measured live 2026-09-17: PT72H on the registered
    # task). Zero means no limit.
    $settings = New-ScheduledTaskSettingsSet -RestartCount 999 -RestartInterval (New-TimeSpan -Minutes 1) `
        -ExecutionTimeLimit (New-TimeSpan -Seconds 0) `
        -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable

    # -ErrorAction Stop is explicit on every ScheduledTasks cmdlet below:
    # measured live, these CIM-backed cmdlets do not reliably honor the
    # script-level $ErrorActionPreference, so an access-denied failure would
    # otherwise print and continue straight into $task.State on a $null
    # task instead of reaching this catch block.
    if (Get-ScheduledTask -TaskName $TaskName -TaskPath $TaskPath -ErrorAction SilentlyContinue) {
        Set-ScheduledTask -TaskName $TaskName -TaskPath $TaskPath -Action $action -Trigger $trigger -Settings $settings -ErrorAction Stop | Out-Null
    } else {
        Register-ScheduledTask -TaskName $TaskName -TaskPath $TaskPath -Action $action -Trigger $trigger -Settings $settings -ErrorAction Stop | Out-Null
    }

    $task = Get-ScheduledTask -TaskName $TaskName -TaskPath $TaskPath -ErrorAction Stop
    if ($task.State -ne 'Running') { Start-ScheduledTask -TaskName $TaskName -TaskPath $TaskPath -ErrorAction Stop }

    # R-10-050/R-10-060: the hook's second idempotent step. The binary owns every
    # decision and writes its diagnostics to relay.log; the shim captures its output
    # so native stderr never becomes a PowerShell error (R-41-082) and forwards only
    # the exit code.
    $null = & $RelayBin install-keybind --action pair-windows 2>&1
    if ($LASTEXITCODE -ne 0) { throw "install-keybind exited $LASTEXITCODE" }

    Write-Host 'herdr-relay: service reconciled'
    exit 0
} catch {
    [Console]::Error.WriteLine("herdr-relay: $($_.Exception.Message)")
    exit 2
}
