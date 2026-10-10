<#
.SYNOPSIS
    Keeps a Das Keyboard Q-series color applied: sets it now and again every time the keyboard reconnects.

.DESCRIPTION
    The keyboard forgets its lighting whenever it loses USB power, which happens on reboot, replug, and
    every KVM switch. Windows has no "device arrived" trigger for Task Scheduler, so this script stays
    running (hidden, idle, no polling) and listens for the WMI device-arrival notification. When one
    fires and the keyboard is present, it re-runs Set-DasKeyboard.ps1 with the configured color or map.

    install.ps1 -StartupColor / -StartupMap registers this as a logon task; you normally never run it by hand.

.PARAMETER Color
    Color to apply (hex or name), passed straight to Set-DasKeyboard.ps1.

.PARAMETER Map
    Path to a JSON layout file, passed to Set-DasKeyboard.ps1 -Map. Use instead of -Color.

.PARAMETER SettleSeconds
    How long to wait after an arrival notification before talking to the keyboard (its HID
    interfaces take a moment to enumerate). Default 3.
#>
[CmdletBinding()]
param(
    [string]$Color,
    [string]$Map,
    [int]$SettleSeconds = 3
)

$ErrorActionPreference = 'Continue'
$setScript = Join-Path $PSScriptRoot 'Set-DasKeyboard.ps1'
if ($Map)        { $setArgs = @('-Map', $Map) }
elseif ($Color)  { $setArgs = @($Color) }
else             { throw 'Specify -Color or -Map.' }

$logDir  = Join-Path $env:LOCALAPPDATA 'das-keyboard'
$logFile = Join-Path $logDir 'watch.log'
New-Item -ItemType Directory -Force -Path $logDir | Out-Null

function Write-Log([string]$msg) {
    try {
        if ((Test-Path $logFile) -and (Get-Item $logFile).Length -gt 200KB) { Clear-Content $logFile }
        Add-Content -Path $logFile -Value "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') $msg"
    } catch { }
}

function Test-KeyboardPresent {
    $devs = Get-CimInstance Win32_PnPEntity -Filter "DeviceID LIKE 'USB\\VID_24F0&PID_%' AND Status = 'OK'" -ErrorAction SilentlyContinue
    return [bool]($devs | Where-Object { $_.DeviceID -match 'PID_(2037|2020|209A)' } | Select-Object -First 1)
}

function Invoke-Apply([string]$reason) {
    for ($attempt = 1; $attempt -le 3; $attempt++) {
        $out = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $setScript @setArgs 2>&1 | Out-String
        if ($LASTEXITCODE -eq 0) {
            Write-Log "$reason -> applied (attempt $attempt): $(($out -split "`n" | Select-Object -Last 2) -join ' | ')".Trim()
            return
        }
        Write-Log "$reason -> attempt $attempt failed: $($out.Trim())"
        Start-Sleep -Seconds 3
    }
}

Write-Log "watcher started (args: $($setArgs -join ' '))"
if (Test-KeyboardPresent) { Invoke-Apply 'startup' } else { Write-Log 'startup: keyboard not present, waiting for it' }

# Win32_DeviceChangeEvent EventType 2 = device arrival. Extrinsic event: no polling, the process sleeps until it fires.
$sourceId = 'DasKeyboardDeviceArrival'
Register-CimIndicationEvent -Query 'SELECT * FROM Win32_DeviceChangeEvent WHERE EventType = 2' -SourceIdentifier $sourceId | Out-Null
try {
    while ($true) {
        $ev = Wait-Event -SourceIdentifier $sourceId
        Remove-Event -EventIdentifier $ev.EventIdentifier
        Start-Sleep -Seconds $SettleSeconds
        # One physical plug produces a burst of arrival events (one per interface); collapse them into one apply.
        Get-Event -SourceIdentifier $sourceId -ErrorAction SilentlyContinue | Remove-Event
        if (Test-KeyboardPresent) { Invoke-Apply 'device arrival' }
    }
}
finally {
    Unregister-Event -SourceIdentifier $sourceId -ErrorAction SilentlyContinue
    Write-Log 'watcher stopped'
}
