<#
.SYNOPSIS
    Installs the das-keyboard skill for Claude Code and (optionally) a logon task that keeps a color applied.

.DESCRIPTION
    Copies SKILL.md and scripts\ into %USERPROFILE%\.claude\skills\das-keyboard (skipped when you already
    cloned the repo there). Nothing else is installed; the scripts only need Windows and PowerShell 5.1+.

    The keyboard forgets its lighting whenever it loses USB power: reboot, replug, or a KVM switch. The
    startup task therefore runs a small hidden watcher (scripts\Watch-DasKeyboard.ps1) at logon that
    applies your color immediately and again every time the keyboard reconnects.

.PARAMETER StartupColor
    Register (or replace) the scheduled task "Das Keyboard Startup Color" so every key is set to this
    color at logon and after every reconnect. Hex (FFC800) or a name (yellow, red, cyan, ...).

.PARAMETER StartupMap
    Same as -StartupColor but with a multi-color JSON layout file (see README). The file is copied to
    the installed skill folder as startup-layout.json so it keeps working if you delete the original.

.PARAMETER RemoveStartupTask
    Stop and remove the "Das Keyboard Startup Color" scheduled task.

.PARAMETER SkipSkill
    Only manage the startup task; do not copy the skill files.

.EXAMPLE
    .\install.ps1
    .\install.ps1 -StartupColor yellow
    .\install.ps1 -StartupMap .\my-layout.json
    .\install.ps1 -RemoveStartupTask
#>
[CmdletBinding()]
param(
    [string]$StartupColor,
    [string]$StartupMap,
    [switch]$RemoveStartupTask,
    [switch]$SkipSkill
)

$ErrorActionPreference = 'Stop'
$taskName = 'Das Keyboard Startup Color'
$source   = $PSScriptRoot
$target   = Join-Path $HOME '.claude\skills\das-keyboard'

if ($StartupColor -and $StartupMap) { throw 'Use either -StartupColor or -StartupMap, not both.' }

# --- skill files -----------------------------------------------------------
if (-not $SkipSkill) {
    $sameDir = (Test-Path $target) -and ((Resolve-Path $target).Path -eq (Resolve-Path $source).Path)
    if ($sameDir) {
        Write-Host "Skill already lives at $target (this folder). Nothing to copy."
    } else {
        New-Item -ItemType Directory -Force -Path (Join-Path $target 'scripts') | Out-Null
        Copy-Item (Join-Path $source 'SKILL.md') $target -Force
        Copy-Item (Join-Path $source 'scripts\*.ps1') (Join-Path $target 'scripts') -Force
        Write-Host "Installed skill to $target"
    }
}

$scriptsDir = Join-Path $target 'scripts'
if (-not (Test-Path (Join-Path $scriptsDir 'Watch-DasKeyboard.ps1'))) { $scriptsDir = Join-Path $source 'scripts' }
$setScript   = Join-Path $scriptsDir 'Set-DasKeyboard.ps1'
$watchScript = Join-Path $scriptsDir 'Watch-DasKeyboard.ps1'

# --- startup task ----------------------------------------------------------
if ($RemoveStartupTask) {
    if (Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue) {
        Stop-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
        Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
        Write-Host "Removed scheduled task '$taskName'."
    } else {
        Write-Host "No scheduled task named '$taskName' exists."
    }
}

if ($StartupColor -or $StartupMap) {
    if ($StartupMap) {
        $mapFile = Join-Path $target 'startup-layout.json'
        if ((Resolve-Path $StartupMap).Path -ne $mapFile) { Copy-Item $StartupMap $mapFile -Force }
        $setArgs   = "-Map `"$mapFile`""
        $watchArgs = "-Map `"$mapFile`""
        $what      = "layout $mapFile"
    } else {
        $setArgs   = $StartupColor
        $watchArgs = "-Color $StartupColor"
        $what      = $StartupColor
    }

    # Apply once now; this validates the color/map and confirms the keyboard is reachable.
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "& '$setScript' $setArgs"
    if ($LASTEXITCODE -ne 0) { throw 'Could not set the color, so the startup task was not registered.' }

    $trigger = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
    $trigger.Delay = 'PT5S'
    # Launch through a headless conhost. Windows Terminal (the Windows 11 default console host) ignores
    # -WindowStyle Hidden and would pop a terminal window for the watcher at every logon and task restart.
    $action = New-ScheduledTaskAction -Execute "$env:SystemRoot\System32\conhost.exe" `
        -Argument "--headless powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$watchScript`" $watchArgs"
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
        -ExecutionTimeLimit (New-TimeSpan -Seconds 0) -MultipleInstances IgnoreNew `
        -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1)

    Stop-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
    Register-ScheduledTask -TaskName $taskName -Trigger $trigger -Action $action -Settings $settings -Force | Out-Null
    Start-ScheduledTask -TaskName $taskName
    Write-Host "Registered and started '$taskName': applies $what at logon and whenever the keyboard reconnects (KVM switch, replug)."
    Write-Host "Watcher log: $env:LOCALAPPDATA\das-keyboard\watch.log"
}

if (-not $StartupColor -and -not $StartupMap -and -not $RemoveStartupTask) {
    Write-Host "Tip: run '.\install.ps1 -StartupColor yellow' to keep a color applied across reboots and KVM switches."
}
