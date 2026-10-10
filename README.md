# das-keyboard

Control the RGB backlight on a **Das Keyboard 4Q / 5Q / 5QS** on Windows without installing the
Das Keyboard Q software. Works as a standalone PowerShell script and as a
[Claude Code](https://claude.com/claude-code) skill, so you can just tell Claude
"make my keyboard blue" or "light up WASD in red".

It talks to the keyboard over the Windows HID API (`hid.dll` and `setupapi.dll`, both part of
Windows) using the protocol reverse-engineered by the [OpenRGB](https://openrgb.org) project.
Nothing is installed on your machine and nothing is written to the keyboard's firmware.

## Requirements

- Windows 10 or 11 with Windows PowerShell 5.1 (built in) or PowerShell 7
- A Das Keyboard 4Q, 5Q, or 5QS connected by USB
- Claude Code, if you want to use it as a skill (optional)

## Install on a new machine

Open PowerShell and run:

```powershell
git clone https://github.com/rperdiga/das-keyboard.git "$HOME\.claude\skills\das-keyboard"
cd "$HOME\.claude\skills\das-keyboard"
.\install.ps1
```

That is the whole install. Cloning directly into `~\.claude\skills\das-keyboard` makes the skill
available to every Claude Code session on that machine; `install.ps1` just confirms the location.

No git? Download the repo as a ZIP from GitHub, extract it anywhere, and run `.\install.ps1` from the
extracted folder. It copies `SKILL.md` and `scripts\` into `~\.claude\skills\das-keyboard` for you.

If PowerShell refuses to run scripts, launch it with the policy bypassed for that one command:

```powershell
powershell -ExecutionPolicy Bypass -File .\install.ps1
```

### Keep a color after reboot, replug, or KVM switch

The keyboard forgets its color whenever it loses USB power, which includes every switch on a KVM.
Register the startup task and it stays set:

```powershell
.\install.ps1 -StartupColor yellow
```

This creates a logon task named "Das Keyboard Startup Color" that runs `scripts\Watch-DasKeyboard.ps1`
hidden in the background. The watcher applies the color at sign-in, then sleeps until Windows reports a
device arrival, checks that the keyboard is back, and applies it again. It does not poll and uses no
CPU while idle. It is the only piece that stays running; nothing is installed.

Run it again with a different color to change it, use `-StartupMap my-layout.json` for a multi-color
layout, or `.\install.ps1 -RemoveStartupTask` to stop. The watcher writes a short log to
`%LOCALAPPDATA%\das-keyboard\watch.log` if you need to see what it did.

## Use from Claude Code

Once installed, just ask in any Claude Code session on that machine:

- "make my keyboard purple"
- "highlight wasd and the arrow keys in red, everything else dim"
- "breathing orange on the F keys"
- "turn the keyboard lights off"
- "what keyboard is this and what firmware does it have"

Claude reads [SKILL.md](SKILL.md) and runs the script for you.

## Use the script directly

```powershell
$s = "$HOME\.claude\skills\das-keyboard\scripts\Set-DasKeyboard.ps1"

powershell -ExecutionPolicy Bypass -File $s yellow                      # whole keyboard
powershell -ExecutionPolicy Bypass -File $s FF0000 -Keys "wasd,arrows"  # only some keys
powershell -ExecutionPolicy Bypass -File $s cyan -Mode Breathing        # effect
powershell -ExecutionPolicy Bypass -File $s -Map .\layout.json          # several colors at once
powershell -ExecutionPolicy Bypass -File $s -Off                        # lights off
powershell -ExecutionPolicy Bypass -File $s -Info                       # model, firmware, layout
powershell -ExecutionPolicy Bypass -File $s -ListKeys                   # all key, group, color names
```

Colors are 6-digit hex or names (`red`, `green`, `blue`, `yellow`, `orange`, `white`, `cyan`,
`magenta`, `purple`, `pink`, `amber`, `gold`, `dim`, `off`, and more). Keys use their physical names
(`W`, `F5`, `Escape`, `LeftShift`, `Numpad7`, `UpArrow`) with shorthand accepted (`esc`, `ctrl`,
`pgup`, `num7`). Groups: `letters`, `numbers`, `fkeys`, `numpad`, `arrows`, `nav`, `modifiers`,
`wasd`, `media`, `punctuation`, `extras`, `all`.

A `-Map` file is a JSON object applied top to bottom, so put the base color first:

```json
{ "all": "dim", "wasd": "red", "arrows": "red", "fkeys": "cyan", "Escape": "FF00FF" }
```

Modes are `Direct` (static, default), `Breathing`, `Flashing`, and `SpectrumCycle`, and they apply
per key, so you can make only the F-keys breathe. There is no brightness command; use a darker color.

## Uninstall

```powershell
.\install.ps1 -RemoveStartupTask
Remove-Item -Recurse "$HOME\.claude\skills\das-keyboard"
```

## How it works

The keyboard exposes a "system control" HID collection (usage page 1, usage 0x80) on its second USB
interface. Commands are sent as 8-byte feature reports: report ID 1, up to 7 payload bytes, with an
XOR checksum terminating the packet. Each key is addressed by an LED index from 0 to 130, with a
mode byte and RGB value, followed by an apply command. The script compiles a tiny C# helper in memory
with `Add-Type` to call `SetupDi*` and `HidD_*`; it does not write any files.

Protocol details, LED indices, and mode bytes come from OpenRGB's `DasKeyboardController`
(GPL-2.0-or-later). This repository contains an independent PowerShell implementation of that
protocol.

## License

MIT. See [LICENSE](LICENSE).
