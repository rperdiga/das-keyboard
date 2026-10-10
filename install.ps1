<#
.SYNOPSIS
    Installs the das-keyboard skill for Claude Code and (optionally) a logon task that sets a startup color.

.DESCRIPTION
    Copies SKILL.md and scripts\ into %USERPROFILE%\.claude\skills\das-keyboard (skipped when you already
    cloned the repo there). Nothing else is installed; the script only needs Windows and PowerShell 5.1+.

.PARAMETER StartupColor
    Register (or replace) a scheduled task named "Das Keyboard Startup Color" that runs at your logon and
    sets every key to this color. Hex (FFC800) or a name (yellow, red, cyan, ...). The color is applied
    immediately as well so you can see it.

.PARAMETER RemoveStartupTask
    Remove the "Das Keyboard Startup Color" scheduled task.

.PARAMETER SkipSkill
    Only manage the startup task; do not copy the skill files.

.EXAMPLE
    .\install.ps1
    .\install.ps1 -StartupColor yellow
    .\install.ps1 -RemoveStartupTask
#>
[CmdletBinding()]
param(
    [string]$StartupColor,
    [switch]$RemoveStartupTask,
    [switch]$SkipSkill
)

$ErrorActionPreference = 'Stop'
$taskName = 'Das Keyboard Startup Color'
$source   = $PSScriptRoot
$target   = Join-Path $HOME '.claude\skills\das-keyboard'

# --- skill files -----------------------------------------------------------
if (-not $SkipSkill) {
    $sameDir = (Test-Path $target) -and ((Resolve-Path $target).Path -eq (Resolve-Path $source).Path)
    if ($sameDir) {
        Write-Host "Skill already lives at $target (this folder). Nothing to copy."
    } else {
        New-Item -ItemType Directory -Force -Path (Join-Path $target 'scripts') | Out-Null
        Copy-Item (Join-Path $source 'SKILL.md') $target -Force
        Copy-Item (Join-Path $source 'scripts\Set-DasKeyboard.ps1') (Join-Path $target 'scripts') -Force
        Write-Host "Installed skill to $target"
    }
}

$script = Join-Path $target 'scripts\Set-DasKeyboard.ps1'
if (-not (Test-Path $script)) { $script = Join-Path $source 'scripts\Set-DasKeyboard.ps1' }

# --- startup task ----------------------------------------------------------
if ($RemoveStartupTask) {
    if (Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue) {
        Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
        Write-Host "Removed scheduled task '$taskName'."
    } else {
        Write-Host "No scheduled task named '$taskName' exists."
    }
}

if ($StartupColor) {
    # Apply now; this also validates the color and confirms the keyboard is reachable.
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $script $StartupColor
    if ($LASTEXITCODE -ne 0) { throw 'Could not set the color, so the startup task was not registered.' }

    $trigger = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
    $trigger.Delay = 'PT10S'   # give the keyboard a moment to enumerate after sign-in
    $action = New-ScheduledTaskAction -Execute 'powershell.exe' `
        -Argument "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$script`" $StartupColor"
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
        -ExecutionTimeLimit (New-TimeSpan -Minutes 2)
    Register-ScheduledTask -TaskName $taskName -Trigger $trigger -Action $action -Settings $settings -Force | Out-Null
    Write-Host "Registered scheduled task '$taskName': sets $StartupColor at every logon."
}

if (-not $StartupColor -and -not $RemoveStartupTask) {
    Write-Host "Tip: run '.\install.ps1 -StartupColor yellow' to reapply a color automatically after every reboot."
}
