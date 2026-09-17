# WP-7: isolate Windows Herdr -> OMP input without touching an existing pane.
# Run from an interactive PowerShell. Requires existing herdr and omp commands.
[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$HerdrCommand = (Get-Command herdr -ErrorAction Stop).Source
$OmpCommand = (Get-Command omp -ErrorAction Stop).Source
$SocketPath = $env:HERDR_SOCKET_PATH
if (-not $SocketPath) {
    $StatusOutput = & $HerdrCommand status 2>$null
    foreach ($StatusLine in $StatusOutput) {
        if ($StatusLine -match '^\s*socket:\s*(.+?)\s*$') { $SocketPath = $Matches[1] }
    }
}
if (-not $SocketPath) { throw 'Herdr did not report a socket. Start this from a Herdr terminal.' }
$PipeName = $SocketPath -replace '^\\\\\.\\pipe\\', ''
$RequestNumber = 0
function Invoke-ProbeRequest([string]$Method, [hashtable]$Params) {
    $script:RequestNumber++
    $Pipe = [System.IO.Pipes.NamedPipeClientStream]::new('.', $PipeName,
        [System.IO.Pipes.PipeDirection]::InOut,
        [System.IO.Pipes.PipeOptions]::Asynchronous)
    $Reader = $null
    $Writer = $null
    try {
        $Pipe.Connect(5000)
        $Encoding = [System.Text.UTF8Encoding]::new($false)
        $Reader = [System.IO.StreamReader]::new($Pipe, $Encoding, $false, 4096, $true)
        $Writer = [System.IO.StreamWriter]::new($Pipe, $Encoding, 4096, $true)
        $Writer.AutoFlush = $true
        $Request = @{ id = "input-probe-$script:RequestNumber"; method = $Method; params = $Params }
        $Writer.WriteLine(($Request | ConvertTo-Json -Compress -Depth 20))
        $Reading = $Reader.ReadLineAsync()
        if (-not $Reading.Wait(5000)) { throw 'Herdr request timed out; the probe will not retry input.' }
        $Reply = $Reading.Result | ConvertFrom-Json
        if ($Reply.PSObject.Properties.Name -contains 'error') {
            throw "Herdr rejected $Method ($($Reply.error.code))."
        }
        return $Reply.result
    } finally {
        if ($Writer) { $Writer.Dispose() }
        if ($Reader) { $Reader.Dispose() }
        $Pipe.Dispose()
    }
}

$ProbeRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('herdr-input-probe-' + [guid]::NewGuid())
[void](New-Item -ItemType Directory -Path $ProbeRoot)
$PaneId = $null
try {
    $Ping = Invoke-ProbeRequest 'ping' @{}
    Write-Output "Herdr version: $($Ping.version); protocol: $($Ping.protocol)"
    $OmpVersion = & $OmpCommand --version
    Write-Output "OMP version: $OmpVersion"
    $Hook = @'
import * as fs from "node:fs";
import * as path from "node:path";
const root = process.env.HERDR_INPUT_PROBE_ROOT!;
export default function(api: any) {
  api.on("session_start", () => fs.writeFileSync(path.join(root, "ready"), "ready"));
  api.on("input", (event: any) => {
    try {
      const request = JSON.parse(fs.readFileSync(path.join(root, "request.json"), "utf8"));
      const actual = event.text;
      let firstDifference = -1;
      for (let i = 0; i < Math.max(actual.length, request.expected.length); i++) {
        if (actual[i] !== request.expected[i]) { firstDifference = i; break; }
      }
      // Counts and comparisons only; neither terminal content nor identifiers are logged.
      const result = {name: request.name, matches: actual === request.expected,
        expectedLength: request.expected.length, actualLength: actual.length, firstDifference};
      const pending = path.join(root, "result.pending");
      fs.writeFileSync(pending, JSON.stringify(result));
      fs.renameSync(pending, path.join(root, "result.json"));
    } catch {
      // Let the parent time out, but consume the input even if the observer fails.
    }
    return {handled: true}; // Never submit the synthetic input to a model.
  });
}
'@
    $Encoding = [System.Text.UTF8Encoding]::new($false)
    $HookPath = Join-Path $ProbeRoot 'observe.ts'
    $ConfigPath = Join-Path $ProbeRoot 'config.yml'
    [System.IO.File]::WriteAllText($HookPath, $Hook, $Encoding)
    [System.IO.File]::WriteAllText($ConfigPath, "setupVersion: 1000`nstartup:`n  setupWizard: false`n", $Encoding)
    $ProfilePath = Join-Path $ProbeRoot 'profile'
    [void](New-Item -ItemType Directory -Path $ProfilePath)
    $Workspace = Invoke-ProbeRequest 'workspace.create' @{
        cwd = $ProbeRoot; focus = $false; label = 'Input fidelity test'
    }
    $PaneId = $Workspace.root_pane.pane_id
    if (-not $PaneId) { throw 'Scratch pane creation returned no id.' }
    function Quote-ProbeLiteral([string]$Value) { return "'" + $Value.Replace("'", "''") + "'" }
    $Launch = '$env:OMP_PROFILE=$null;$env:PI_PROFILE=$null;' +
        '$env:PI_CODING_AGENT_DIR=' + (Quote-ProbeLiteral $ProfilePath) + ';' +
        '$env:HERDR_INPUT_PROBE_ROOT=' + (Quote-ProbeLiteral $ProbeRoot) + ';' +
        '$env:ANTHROPIC_API_KEY=''herdr-test-only'';' +
        '& ' + (Quote-ProbeLiteral $OmpCommand) +
        ' --model anthropic/claude-sonnet-4-5 --api-key herdr-test-only' +
        ' --no-session --no-tools --no-lsp --no-pty --no-extensions --no-skills --no-rules --no-title' +
        ' --config ' + (Quote-ProbeLiteral $ConfigPath) + ' --extension ' + (Quote-ProbeLiteral $HookPath)
    $EncodedLaunch = [Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($Launch))
    $null = Invoke-ProbeRequest 'pane.send_input' @{
        pane_id = $PaneId; text = "powershell -NoProfile -EncodedCommand $EncodedLaunch"; keys = @('Enter')
    }
    $ReadyPath = Join-Path $ProbeRoot 'ready'
    $Deadline = [DateTime]::UtcNow.AddSeconds(45)
    while (-not (Test-Path $ReadyPath) -and [DateTime]::UtcNow -lt $Deadline) { Start-Sleep -Milliseconds 100 }
    if (-not (Test-Path $ReadyPath)) { throw 'The isolated OMP observer did not start.' }
    Start-Sleep -Seconds 3
    $Sample = 'Fast typing keeps every letter and  every space 0123456789'
    foreach ($DelayMs in @(50, 0)) {
        foreach ($Raw in @($false, $true)) {
            $Name = "delay_ms=$DelayMs raw_text=$Raw"
            $RequestPath = Join-Path $ProbeRoot 'request.json'
            $ResultPath = Join-Path $ProbeRoot 'result.json'
            Remove-Item $ResultPath -Force -ErrorAction SilentlyContinue
            $Expected = @{ name = $Name; expected = $Sample } | ConvertTo-Json -Compress
            [System.IO.File]::WriteAllText($RequestPath, $Expected, $Encoding)
            $Method = if ($Raw) { 'pane.send_text' } else { 'pane.send_input' }
            $Clock = [System.Diagnostics.Stopwatch]::StartNew()
            foreach ($Character in $Sample.ToCharArray()) {
                $null = Invoke-ProbeRequest $Method @{ pane_id = $PaneId; text = [string]$Character }
                if ($DelayMs -gt 0) { Start-Sleep -Milliseconds $DelayMs }
            }
            $Clock.Stop()
            Start-Sleep -Milliseconds 500
            $null = Invoke-ProbeRequest 'pane.send_input' @{ pane_id = $PaneId; keys = @('Enter') }
            $Deadline = [DateTime]::UtcNow.AddSeconds(10)
            while (-not (Test-Path $ResultPath) -and [DateTime]::UtcNow -lt $Deadline) { Start-Sleep -Milliseconds 100 }
            if (-not (Test-Path $ResultPath)) { throw 'OMP did not return the input comparison.' }
            $Result = Get-Content -Raw $ResultPath | ConvertFrom-Json
            Write-Output ("{0}; matches={1}; expected={2}; received={3}; first_difference={4}; send_ms={5}" -f
                $Name, $Result.matches, $Result.expectedLength, $Result.actualLength,
                $Result.firstDifference, $Clock.ElapsedMilliseconds)
            Start-Sleep -Milliseconds 200
        }
    }
} finally {
    try {
        if ($PaneId) {
            # Close only the pane this script created, even if someone added another pane.
            $null = Invoke-ProbeRequest 'pane.close' @{ pane_id = $PaneId }
            Write-Output 'Removed the pane created by this probe.'
        }
    } finally {
        # Windows can retain the child's file handles briefly after the close reply.
        $CleanupDeadline = [DateTime]::UtcNow.AddSeconds(10)
        while (Test-Path $ProbeRoot) {
            try {
                Remove-Item -LiteralPath $ProbeRoot -Recurse -Force
                break
            } catch {
                if ([DateTime]::UtcNow -ge $CleanupDeadline) {
                    Write-Warning 'The temporary diagnostic folder could not be removed; a child may still be exiting.'
                    break
                }
                Start-Sleep -Milliseconds 200
            }
        }
    }
}
