# das-keyboard

Control the RGB backlight on a **Das Keyboard 4Q / 5Q / 5QS** on **Windows or macOS** without
installing the Das Keyboard Q software. Works as a standalone script and as a
[Claude Code](https://claude.com/claude-code) skill, so you can just tell Claude
"make my keyboard blue" or "light up WASD in red".

Both implementations speak the protocol reverse-engineered by the [OpenRGB](https://openrgb.org)
project and need nothing beyond what the OS ships with:

- **Windows**: PowerShell 5.1 or 7, talking to `hid.dll` / `setupapi.dll`.
- **macOS**: the system `/usr/bin/python3`, talking to IOKit through `ctypes`. No Homebrew, no
  hidapi, no pip packages.

Nothing is installed on your machine and nothing is written to the keyboard's firmware.

## Requirements

- Windows 10/11, or macOS with the Command Line Tools python3
- A Das Keyboard 4Q, 5Q, or 5QS connected by USB
- Claude Code, if you want to use it as a skill (optional)

## Install

Clone straight into the Claude Code skills folder; that makes the skill available to every Claude
Code session on the machine. The installer just confirms the location (or copies the files there if
you unpacked the repo somewhere else).

**Windows (PowerShell):**

```powershell
git clone https://github.com/rperdiga/das-keyboard.git "$HOME\.claude\skills\das-keyboard"
cd "$HOME\.claude\skills\das-keyboard"
.\install.ps1
```

If PowerShell refuses to run scripts: `powershell -ExecutionPolicy Bypass -File .\install.ps1`.

**macOS (Terminal):**

```bash
git clone https://github.com/rperdiga/das-keyboard.git "$HOME/.claude/skills/das-keyboard"
cd "$HOME/.claude/skills/das-keyboard"
./install.sh
```

### Keep a color after reboot, replug, or KVM switch

The keyboard forgets its color whenever it loses USB power, which includes every switch on a KVM.
Register the startup watcher and it stays set:

```powershell
.\install.ps1 -StartupColor yellow        # Windows
```

```bash
./install.sh --startup-color yellow       # macOS
```

On Windows this creates a logon task named "Das Keyboard Startup Color" that runs
`scripts\Watch-DasKeyboard.ps1` hidden; it applies the color at sign-in, then sleeps until Windows
reports a device arrival. On macOS it writes `~/Library/LaunchAgents/com.das-keyboard.startup-color.plist`,
which runs `scripts/watch_das_keyboard.py`; it applies the color at login, then waits in a run loop
for an IOKit device-arrival callback. Neither one polls.

Run it again with a different color to change it, use `-StartupMap` / `--startup-map my-layout.json`
for a multi-color layout, or `-RemoveStartupTask` / `--remove-startup-task` to stop. Logs:
`%LOCALAPPDATA%\das-keyboard\watch.log` on Windows, `~/Library/Logs/das-keyboard/watch.log` on macOS.

## Use from Claude Code

Once installed, just ask in any Claude Code session on that machine:

- "make my keyboard purple"
- "highlight wasd and the arrow keys in red, everything else dim"
- "breathing orange on the F keys"
- "turn the keyboard lights off"
- "what keyboard is this and what firmware does it have"

Claude reads [SKILL.md](SKILL.md) and runs the right script for the OS.

## Use the scripts directly

**Windows:**

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

**macOS:**

```bash
s="$HOME/.claude/skills/das-keyboard/scripts/das_keyboard.py"

python3 "$s" yellow                         # whole keyboard
python3 "$s" FF0000 --keys "wasd,arrows"    # only some keys
python3 "$s" cyan --mode Breathing          # effect
python3 "$s" --map ./layout.json            # several colors at once
python3 "$s" --off                          # lights off
python3 "$s" --info                         # model, firmware, layout
python3 "$s" --list-keys                    # all key, group, color names
```

Colors are 6-digit hex or names (`red`, `green`, `blue`, `yellow`, `orange`, `white`, `cyan`,
`magenta`, `purple`, `pink`, `amber`, `gold`, `dim`, `off`, and more). Keys use their physical names
(`W`, `F5`, `Escape`, `LeftShift`, `Numpad7`, `UpArrow`) with shorthand accepted (`esc`, `ctrl`,
`pgup`, `num7`; on a Mac also `cmd` for the Windows/Command key and `option` for Alt). Groups:
`letters`, `numbers`, `fkeys`, `numpad`, `arrows`, `nav`, `modifiers`, `wasd`, `media`,
`punctuation`, `extras`, `all`.

A map file is a JSON object applied top to bottom, so put the base color first:

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

```bash
./install.sh --remove-startup-task
rm -rf "$HOME/.claude/skills/das-keyboard"
```

## How it works

The keyboard exposes a "system control" HID collection (usage page 1, usage 0x80) on its second USB
interface. Commands are sent as 8-byte feature reports: report ID 1, up to 7 payload bytes, with an
XOR checksum terminating the packet. Each key is addressed by an LED index from 0 to 130, with a mode
byte and RGB value, followed by an apply command.

On Windows the script compiles a tiny C# helper in memory with `Add-Type` to call `SetupDi*` and
`HidD_*`. On macOS the script loads IOKit and CoreFoundation with `ctypes`, matches the collection
through `IOHIDManager`, and uses `IOHIDDeviceSetReport` / `GetReport`. One difference worth knowing:
IOKit strips the report-ID byte from feature-report reads, so the reply offsets differ from Windows.

Protocol details, LED indices, and mode bytes come from OpenRGB's `DasKeyboardController`
(GPL-2.0-or-later). This repository contains independent PowerShell and Python implementations of
that protocol.

## License

MIT. See [LICENSE](LICENSE).
