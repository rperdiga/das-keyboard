<#
.SYNOPSIS
    Controls the RGB LEDs on a Das Keyboard 4Q / 5Q / 5QS directly over USB HID. No Das Keyboard Q software needed.

.DESCRIPTION
    Uses only hid.dll / setupapi.dll (built into Windows) and the protocol reverse-engineered by OpenRGB.
    Colors are not saved to the keyboard's flash; they revert when the keyboard loses power.

.PARAMETER Color
    Color for -Keys (or for the whole keyboard when -Keys is omitted). Hex "FFC800", "#ff0000",
    or a name: red, green, blue, yellow, orange, white, cyan, magenta, purple, pink, off/black, ...

.PARAMETER Keys
    Comma-separated key names and/or groups to color. Omit to color every key.
    Run with -ListKeys to see all names. Groups: letters, numbers, fkeys, numpad, arrows, nav,
    modifiers, wasd, media, all.

.PARAMETER Mode
    Direct (static, default), Breathing, Flashing, SpectrumCycle.

.PARAMETER Map
    Path to a JSON file mapping key/group names to colors, applied in file order. Use "all" as the
    first entry to set a base color. Example: { "all": "202020", "wasd": "red", "Escape": "FF00FF" }

.PARAMETER Off
    Turn every LED off.

.PARAMETER Info
    Print the detected keyboard model, firmware, and layout, then exit.

.PARAMETER ListKeys
    Print every key name and group, then exit.
#>
[CmdletBinding(DefaultParameterSetName = 'Set')]
param(
    [Parameter(ParameterSetName = 'Set', Position = 0)] [string]$Color,
    [Parameter(ParameterSetName = 'Set')] [string]$Keys,
    [Parameter(ParameterSetName = 'Set')] [Parameter(ParameterSetName = 'Map')]
    [ValidateSet('Direct', 'Breathing', 'Flashing', 'SpectrumCycle')] [string]$Mode = 'Direct',
    [Parameter(ParameterSetName = 'Map', Mandatory)] [string]$Map,
    [Parameter(ParameterSetName = 'Off', Mandatory)] [switch]$Off,
    [Parameter(ParameterSetName = 'Info', Mandatory)] [switch]$Info,
    [Parameter(ParameterSetName = 'ListKeys', Mandatory)] [switch]$ListKeys
)

$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# Key table: LED id -> name (from OpenRGB's RGBController_DasKeyboard). Index = key id.
# ---------------------------------------------------------------------------
$keyNames = @(
    'LeftControl', 'LeftShift', 'CapsLock', 'Tab', 'Backtick', 'Escape', 'LeftWindows', 'Backslash',
    'A', 'Q', '1', $null, 'LeftAlt', 'Z', 'S', 'W', '2', 'F1', $null, 'X', 'D', 'E', '3', 'F2', $null,
    'C', 'F', 'R', '4', 'F3', $null, 'V', 'G', 'T', '5', 'F4', 'Space', 'B', 'H', 'Y', '6', 'F5', $null,
    'N', 'J', 'U', '7', 'F6', $null, 'M', 'K', 'I', '8', 'F7', $null, 'Comma', 'L', 'O', '9', 'F8',
    'RightAlt', 'Period', 'Semicolon', 'P', '0', 'F9', 'RightWindows', 'Slash', 'Quote', 'LeftBracket',
    'Minus', 'F10', 'Menu', $null, $null, 'RightBracket', 'Equals', 'F11', 'RightControl', 'RightShift',
    'Enter', 'Pound', 'Backspace', 'F12', 'LeftArrow', $null, $null, 'Delete', 'Insert', 'PrintScreen',
    'DownArrow', 'UpArrow', $null, 'End', 'Home', 'ScrollLock', 'RightArrow', $null, $null, 'PageDown',
    'PageUp', 'PauseBreak', 'Numpad0', 'Numpad1', 'Numpad4', 'Numpad7', 'NumLock', $null, $null,
    'Numpad2', 'Numpad5', 'Numpad8', 'NumpadDivide', $null, 'NumpadPeriod', 'Numpad3', 'Numpad6',
    'Numpad9', 'NumpadTimes', $null, $null, $null, 'NumpadEnter', 'NumpadPlus', 'NumpadMinus', $null,
    'Sleep', 'Brightness', 'MediaPlayPause', 'MediaNext', 'QButton'
)

$aliases = @{
    'esc' = 'Escape'; 'ctrl' = 'LeftControl'; 'lctrl' = 'LeftControl'; 'rctrl' = 'RightControl';
    'shift' = 'LeftShift'; 'lshift' = 'LeftShift'; 'rshift' = 'RightShift'; 'alt' = 'LeftAlt';
    'lalt' = 'LeftAlt'; 'ralt' = 'RightAlt'; 'win' = 'LeftWindows'; 'lwin' = 'LeftWindows';
    'rwin' = 'RightWindows'; 'windows' = 'LeftWindows'; 'super' = 'LeftWindows'; 'return' = 'Enter';
    'caps' = 'CapsLock'; 'del' = 'Delete'; 'ins' = 'Insert'; 'prtsc' = 'PrintScreen'; 'printscreen' = 'PrintScreen';
    'pgup' = 'PageUp'; 'pgdn' = 'PageDown'; 'pgdown' = 'PageDown'; 'pause' = 'PauseBreak'; 'break' = 'PauseBreak';
    'up' = 'UpArrow'; 'down' = 'DownArrow'; 'left' = 'LeftArrow'; 'right' = 'RightArrow';
    'grave' = 'Backtick'; 'tilde' = 'Backtick'; 'apostrophe' = 'Quote'; 'dash' = 'Minus'; 'hyphen' = 'Minus';
    'dot' = 'Period'; 'bracketleft' = 'LeftBracket'; 'bracketright' = 'RightBracket';
    'num0' = 'Numpad0'; 'num1' = 'Numpad1'; 'num2' = 'Numpad2'; 'num3' = 'Numpad3'; 'num4' = 'Numpad4';
    'num5' = 'Numpad5'; 'num6' = 'Numpad6'; 'num7' = 'Numpad7'; 'num8' = 'Numpad8'; 'num9' = 'Numpad9';
    'numpadmultiply' = 'NumpadTimes'; 'numpadstar' = 'NumpadTimes'; 'numpadsubtract' = 'NumpadMinus';
    'numpadadd' = 'NumpadPlus'; 'numpaddot' = 'NumpadPeriod'; 'numpaddecimal' = 'NumpadPeriod';
    'numpadslash' = 'NumpadDivide'; 'play' = 'MediaPlayPause'; 'playpause' = 'MediaPlayPause';
    'next' = 'MediaNext'; 'q-button' = 'QButton'; 'qbutton' = 'QButton'; 'qkey' = 'QButton';
    'hash' = 'Pound'; 'app' = 'Menu'; 'context' = 'Menu'
}

$groups = @{
    'letters'   = 'A,B,C,D,E,F,G,H,I,J,K,L,M,N,O,P,Q,R,S,T,U,V,W,X,Y,Z'
    'numbers'   = '1,2,3,4,5,6,7,8,9,0'
    'fkeys'     = 'F1,F2,F3,F4,F5,F6,F7,F8,F9,F10,F11,F12'
    'numpad'    = 'NumLock,NumpadDivide,NumpadTimes,NumpadMinus,NumpadPlus,NumpadEnter,NumpadPeriod,Numpad0,Numpad1,Numpad2,Numpad3,Numpad4,Numpad5,Numpad6,Numpad7,Numpad8,Numpad9'
    'arrows'    = 'UpArrow,DownArrow,LeftArrow,RightArrow'
    'nav'       = 'Insert,Delete,Home,End,PageUp,PageDown,PrintScreen,ScrollLock,PauseBreak'
    'modifiers' = 'LeftControl,LeftShift,LeftAlt,LeftWindows,RightControl,RightShift,RightAlt,RightWindows,Menu'
    'wasd'      = 'W,A,S,D'
    'media'     = 'Sleep,Brightness,MediaPlayPause,MediaNext,QButton'
    'punctuation' = 'Backtick,Minus,Equals,LeftBracket,RightBracket,Backslash,Semicolon,Quote,Comma,Period,Slash,Pound'
    'extras'    = 'Escape,Tab,CapsLock,Backspace,Enter,Space'
}

$namedColors = @{
    'red' = 'FF0000'; 'green' = '00FF00'; 'blue' = '0000FF'; 'yellow' = 'FFC800'; 'lightyellow' = 'FFFF80';
    'orange' = 'FF5000'; 'white' = 'FFFFFF'; 'cyan' = '00FFFF'; 'aqua' = '00FFFF'; 'magenta' = 'FF00FF';
    'purple' = '8000FF'; 'violet' = '8000FF'; 'pink' = 'FF2080'; 'lime' = '80FF00'; 'teal' = '008080';
    'gold' = 'FFB000'; 'amber' = 'FFA000'; 'warmwhite' = 'FFD0A0'; 'coolwhite' = 'C0D8FF'; 'gray' = '404040';
    'grey' = '404040'; 'dim' = '202020'; 'off' = '000000'; 'black' = '000000'
}

function Resolve-KeyIds([string]$list) {
    $ids = New-Object System.Collections.Generic.List[int]
    foreach ($raw in $list -split '[,; ]+') {
        if (-not $raw) { continue }
        $tok = $raw.Trim().ToLower() -replace '[_\-\s]', ''
        if ($tok -eq 'all' -or $tok -eq '*') { 0..130 | ForEach-Object { $ids.Add($_) }; continue }
        if ($groups.ContainsKey($tok)) { foreach ($i in Resolve-KeyIds $groups[$tok]) { $ids.Add($i) }; continue }
        if ($aliases.ContainsKey($tok)) { $tok = $aliases[$tok].ToLower() }
        $idx = -1
        for ($i = 0; $i -lt $keyNames.Count; $i++) {
            if ($keyNames[$i] -and $keyNames[$i].ToLower() -eq $tok) { $idx = $i; break }
        }
        if ($idx -lt 0) { throw "Unknown key or group '$raw'. Run with -ListKeys to see valid names." }
        $ids.Add($idx)
    }
    return $ids | Select-Object -Unique
}

function Resolve-Rgb([string]$c) {
    $tok = $c.Trim().TrimStart('#').ToLower() -replace '[_\-\s]', ''
    if ($namedColors.ContainsKey($tok)) { $tok = $namedColors[$tok] }
    if ($tok -notmatch '^[0-9a-f]{6}$') { throw "Unknown color '$c'. Use 6 hex digits (FFC800) or a name like red, yellow, cyan, off." }
    return [byte[]]@([Convert]::ToByte($tok.Substring(0, 2), 16), [Convert]::ToByte($tok.Substring(2, 2), 16), [Convert]::ToByte($tok.Substring(4, 2), 16))
}

if ($ListKeys) {
    Write-Host "Keys:"
    ($keyNames | Where-Object { $_ }) -join ', ' | Write-Host
    Write-Host "`nGroups:"
    foreach ($g in $groups.Keys | Sort-Object) { Write-Host "  $g = $($groups[$g])" }
    Write-Host "  all = every key"
    Write-Host "`nColors: hex (FFC800) or $(($namedColors.Keys | Sort-Object) -join ', ')"
    return
}

# ---------------------------------------------------------------------------
# Low-level HID access (compiled in memory; nothing written to disk)
# ---------------------------------------------------------------------------
if (-not ('DasHid' -as [type])) {
Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;

public static class DasHid
{
    [StructLayout(LayoutKind.Sequential)]
    struct SP_DEVICE_INTERFACE_DATA { public int cbSize; public Guid InterfaceClassGuid; public int Flags; public IntPtr Reserved; }

    [StructLayout(LayoutKind.Sequential)]
    public struct HIDP_CAPS
    {
        public ushort Usage; public ushort UsagePage;
        public ushort InputReportByteLength; public ushort OutputReportByteLength; public ushort FeatureReportByteLength;
        [MarshalAs(UnmanagedType.ByValArray, SizeConst = 17)] public ushort[] Reserved;
        public ushort NumberLinkCollectionNodes;
        public ushort NumberInputButtonCaps; public ushort NumberInputValueCaps; public ushort NumberInputDataIndices;
        public ushort NumberOutputButtonCaps; public ushort NumberOutputValueCaps; public ushort NumberOutputDataIndices;
        public ushort NumberFeatureButtonCaps; public ushort NumberFeatureValueCaps; public ushort NumberFeatureDataIndices;
    }

    [DllImport("hid.dll")] static extern void HidD_GetHidGuid(out Guid guid);
    [DllImport("setupapi.dll", CharSet = CharSet.Unicode)] static extern IntPtr SetupDiGetClassDevs(ref Guid guid, IntPtr e, IntPtr h, int flags);
    [DllImport("setupapi.dll")] static extern bool SetupDiEnumDeviceInterfaces(IntPtr set, IntPtr info, ref Guid guid, int index, ref SP_DEVICE_INTERFACE_DATA data);
    [DllImport("setupapi.dll", CharSet = CharSet.Unicode)] static extern bool SetupDiGetDeviceInterfaceDetail(IntPtr set, ref SP_DEVICE_INTERFACE_DATA data, IntPtr detail, int size, out int required, IntPtr info);
    [DllImport("setupapi.dll")] static extern bool SetupDiDestroyDeviceInfoList(IntPtr set);
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)] static extern SafeFileHandle CreateFile(string path, uint access, uint share, IntPtr sa, uint disposition, uint flags, IntPtr template);
    [DllImport("hid.dll")] static extern bool HidD_GetPreparsedData(SafeFileHandle h, out IntPtr data);
    [DllImport("hid.dll")] static extern bool HidD_FreePreparsedData(IntPtr data);
    [DllImport("hid.dll")] static extern int HidP_GetCaps(IntPtr data, out HIDP_CAPS caps);
    [DllImport("hid.dll", SetLastError = true)] static extern bool HidD_SetFeature(SafeFileHandle h, byte[] buf, int len);
    [DllImport("hid.dll", SetLastError = true)] static extern bool HidD_GetFeature(SafeFileHandle h, byte[] buf, int len);

    public static List<string> EnumeratePaths()
    {
        var paths = new List<string>();
        Guid hidGuid; HidD_GetHidGuid(out hidGuid);
        IntPtr set = SetupDiGetClassDevs(ref hidGuid, IntPtr.Zero, IntPtr.Zero, 0x12);
        if (set == new IntPtr(-1)) return paths;
        try
        {
            for (int i = 0; ; i++)
            {
                var ifData = new SP_DEVICE_INTERFACE_DATA();
                ifData.cbSize = Marshal.SizeOf(ifData);
                if (!SetupDiEnumDeviceInterfaces(set, IntPtr.Zero, ref hidGuid, i, ref ifData)) break;
                int required;
                SetupDiGetDeviceInterfaceDetail(set, ref ifData, IntPtr.Zero, 0, out required, IntPtr.Zero);
                IntPtr detail = Marshal.AllocHGlobal(required);
                try
                {
                    Marshal.WriteInt32(detail, IntPtr.Size == 8 ? 8 : 6);
                    if (SetupDiGetDeviceInterfaceDetail(set, ref ifData, detail, required, out required, IntPtr.Zero))
                        paths.Add(Marshal.PtrToStringUni(new IntPtr(detail.ToInt64() + 4)));
                }
                finally { Marshal.FreeHGlobal(detail); }
            }
        }
        finally { SetupDiDestroyDeviceInfoList(set); }
        return paths;
    }

    public static SafeFileHandle Open(string path)
    {
        SafeFileHandle h = CreateFile(path, 0xC0000000, 3, IntPtr.Zero, 3, 0, IntPtr.Zero);
        if (h.IsInvalid) h = CreateFile(path, 0, 3, IntPtr.Zero, 3, 0, IntPtr.Zero);
        return h;
    }

    public static HIDP_CAPS GetCaps(SafeFileHandle h)
    {
        IntPtr pp;
        if (!HidD_GetPreparsedData(h, out pp)) throw new Exception("HidD_GetPreparsedData failed");
        try { HIDP_CAPS caps; HidP_GetCaps(pp, out caps); return caps; }
        finally { HidD_FreePreparsedData(pp); }
    }

    public static bool SetFeature(SafeFileHandle h, byte[] buf) { return HidD_SetFeature(h, buf, buf.Length); }
    public static bool GetFeature(SafeFileHandle h, byte[] buf) { return HidD_GetFeature(h, buf, buf.Length); }
    public static int LastError() { return Marshal.GetLastWin32Error(); }
}
'@
}

# ---------------------------------------------------------------------------
# Find the keyboard: Metadot VID 24F0, Q-series PID, "system control" collection (usage page 1, usage 0x80)
# ---------------------------------------------------------------------------
$knownPids = @{ '2037' = 'Das Keyboard 4Q'; '2020' = 'Das Keyboard 5Q'; '209a' = 'Das Keyboard 5QS' }
$handle = $null; $caps = $null; $model = $null
foreach ($path in [DasHid]::EnumeratePaths()) {
    if ($path -notmatch 'vid_24f0&pid_([0-9a-f]{4})') { continue }
    $productId = $Matches[1].ToLower()
    if (-not $knownPids.ContainsKey($productId)) { continue }
    $h = [DasHid]::Open($path)
    if ($h.IsInvalid) { continue }
    try { $c = [DasHid]::GetCaps($h) } catch { $h.Close(); continue }
    if ($c.UsagePage -eq 1 -and $c.Usage -eq 0x80 -and $c.FeatureReportByteLength -ge 2) {
        $handle = $h; $caps = $c; $model = $knownPids[$productId]; break
    }
    $h.Close()
}
if (-not $handle) { throw 'No Das Keyboard Q-series keyboard found (looked for USB VID 24F0 with PID 2037, 2020, or 209A).' }
$reportLen = [int]$caps.FeatureReportByteLength

# ---------------------------------------------------------------------------
# Protocol (OpenRGB DasKeyboardController): report ID 1, payload + XOR checksum, chunked to the report size.
# ---------------------------------------------------------------------------
function Send-Packet([byte[]]$data) {
    $chk = 0; foreach ($b in $data) { $chk = $chk -bxor $b }
    $payload = [byte[]]($data + [byte]$chk)
    $chunk = $reportLen - 1
    for ($i = 0; $i -lt $payload.Length; $i += $chunk) {
        $buf = New-Object byte[] $reportLen
        $buf[0] = 1
        $n = [Math]::Min($chunk, $payload.Length - $i)
        [Array]::Copy($payload, $i, $buf, 1, $n)
        $ok = $false
        for ($try = 0; $try -lt 4 -and -not $ok; $try++) {
            $ok = [DasHid]::SetFeature($handle, $buf)
            if (-not $ok) { Start-Sleep -Milliseconds 5 }
        }
        if (-not $ok) { throw "HidD_SetFeature failed (Win32 error $([DasHid]::LastError()))" }
        [Threading.Thread]::Sleep(1)
    }
}

function Receive-Packet {
    # Reads reply chunks until the keyboard returns a zero report. The XOR of every byte of a
    # complete reply is 0 (the last byte is a checksum), so a non-zero XOR means a truncated or
    # stale reply and we return an empty array.
    $all = New-Object System.Collections.Generic.List[byte]
    $chk = 0
    for ($reads = 0; $reads -lt 32; $reads++) {
        $buf = New-Object byte[] $reportLen
        $buf[0] = 1
        if (-not [DasHid]::GetFeature($handle, $buf)) { break }
        if ($buf[0] -eq 0) { break }
        $all.AddRange([byte[]]$buf)
        foreach ($b in $buf) { $chk = $chk -bxor $b }
    }
    if ($chk -ne 0) { return [byte[]]@() }
    return $all.ToArray()
}

function Clear-Stale {
    # Drain any reply left over from an earlier command so the next reply we read is ours.
    for ($reads = 0; $reads -lt 32; $reads++) {
        $buf = New-Object byte[] $reportLen
        $buf[0] = 1
        if (-not [DasHid]::GetFeature($handle, $buf) -or $buf[0] -eq 0) { break }
    }
}

function Send-KeyColor([int]$key, [byte]$modeByte, [byte[]]$rgb) {
    if ($key -lt 130) { Send-Packet ([byte[]](0xEA, 0x08, 0x78, 0x08, $key, $modeByte, $rgb[0], $rgb[1], $rgb[2])) }
    else              { Send-Packet ([byte[]](0xEA, 0x06, 0x78, 0x06, $rgb[0], $rgb[1], $rgb[2])) }  # Q button: color only
}

$modeByte = @{ Direct = 0x01; Breathing = 0x08; SpectrumCycle = 0x14; Flashing = 0x1F }[$Mode]

try {
    # Handshake: ask for the firmware/layout string. Retry a few times; the reply is not always ready immediately.
    $fwText = ''
    Clear-Stale
    for ($attempt = 0; $attempt -lt 5 -and $fwText.Length -lt 17; $attempt++) {
        Send-Packet ([byte[]](0xEA, 0x02, 0xB0))
        Start-Sleep -Milliseconds (10 + 20 * $attempt)
        $resp = Receive-Packet
        if ($resp.Length -gt 4) { $fwText = [Text.Encoding]::ASCII.GetString($resp, 4, $resp.Length - 4).Split([char]0)[0] }
    }
    $layout = 'unknown'; $fw = 'unknown'
    if ($fwText.Length -ge 17) {
        $layout = if ($fwText.Substring(3, 2) -in '16', '63') { 'US' } else { 'EU' }
        $fw = "V$($fwText.Substring(6,2)).$($fwText.Substring(15,2)).0"
    }
    Write-Host "Found $model, firmware $fw, $layout layout"
    if ($Info) { return }
    if ($fwText.Length -lt 17) { Write-Warning 'Keyboard did not answer the handshake; sending colors anyway.' }

    $changes = @()   # list of @{ids=..; rgb=..}
    switch ($PSCmdlet.ParameterSetName) {
        'Off' { $changes += @{ ids = (0..130); rgb = [byte[]](0, 0, 0); label = 'all keys off' } }
        'Map' {
            $json = Get-Content -LiteralPath $Map -Raw | ConvertFrom-Json
            foreach ($prop in $json.PSObject.Properties) {
                $changes += @{ ids = (Resolve-KeyIds $prop.Name); rgb = (Resolve-Rgb ([string]$prop.Value)); label = "$($prop.Name) -> $($prop.Value)" }
            }
        }
        default {
            if (-not $Color) { throw 'Specify a color (e.g. -Color yellow), or use -Off, -Map, -Info, or -ListKeys.' }
            $ids = if ($Keys) { Resolve-KeyIds $Keys } else { 0..130 }
            $what = if ($Keys) { $Keys } else { 'all keys' }
            $changes += @{ ids = $ids; rgb = (Resolve-Rgb $Color); label = "$what -> $Color" }
        }
    }

    foreach ($ch in $changes) {
        foreach ($id in $ch.ids) { Send-KeyColor $id $modeByte $ch.rgb }
    }
    Send-Packet ([byte[]](0xEA, 0x03, 0x78, 0x0A))
    [void](Receive-Packet)

    foreach ($ch in $changes) { Write-Host "Set $($ch.label) ($Mode)" }
}
finally {
    $handle.Close()
}
