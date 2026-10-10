---
name: das-keyboard
description: Control the RGB backlight on the user's Das Keyboard 4Q (also works for 5Q/5QS) directly over USB on Windows or macOS, without the Das Keyboard Q software. Use this whenever the user mentions their keyboard lights, LEDs, backlight, key colors, lighting effects, turning the keyboard lighting off or on, highlighting specific keys (WASD, arrows, F-keys, numpad), or the Das Keyboard / "DAS" / "4Q" by name, even if they do not say "RGB" or "LED". Also use it for requests like "make my keyboard red", "dim the keyboard", "breathing effect", or "what color is my keyboard set to at startup".
---

# Das Keyboard lighting

The user has a Das Keyboard Q-series keyboard and does not want the vendor software installed. This
skill ships one script per platform, both in this skill's `scripts/` directory, both speaking the
protocol reverse-engineered by OpenRGB. Nothing is installed and nothing is written to the keyboard's
flash. The script is the whole interface: run it, read its output, report back.

| Platform | Script | How to run |
|----------|--------|------------|
| Windows | `scripts/Set-DasKeyboard.ps1` (Windows HID API via hid.dll/setupapi.dll) | `powershell -NoProfile -ExecutionPolicy Bypass -File "<skill dir>\scripts\Set-DasKeyboard.ps1" <args>` |
| macOS | `scripts/das_keyboard.py` (IOKit via ctypes, system python3, no packages) | `/usr/bin/python3 -I "<skill dir>/scripts/das_keyboard.py" <args>` |

Pick the script for the OS you are running on. `<skill dir>` is this skill's base directory (the
path shown when the skill loads, normally `~/.claude/skills/das-keyboard`).

## Arguments

The two scripts take the same arguments; only the flag style differs (PowerShell `-Keys`, Python
`--keys`). The first positional argument is the color (not needed with map, off, info, list-keys).

| Goal | Windows | macOS |
|------|---------|-------|
| Whole keyboard one color | `yellow` / `FFC800` / `"#ff0000"` | same |
| Only some keys (others keep their color) | `red -Keys "wasd,arrows"` | `red --keys "wasd,arrows"` |
| Effect instead of static | `cyan -Mode Breathing` | `cyan --mode Breathing` |
| Several colors at once | `-Map C:\path\layout.json` | `--map /path/layout.json` |
| Lights off | `-Off` | `--off` |
| Detect keyboard, firmware, layout | `-Info` | `--info` |
| Every valid key, group, and color name | `-ListKeys` | `--list-keys` |

Modes: `Direct` (static, default), `Breathing`, `Flashing`, `SpectrumCycle`.

Colors are 6-digit hex or names: red, green, blue, yellow (FFC800, a true LED yellow), lightyellow,
orange, white, warmwhite, coolwhite, cyan, magenta, purple, pink, lime, teal, gold, amber, gray
(404040), dim (202020, a faint gray), off. For a "dim white" or "soft white" background, a hex like
`606060` reads better than `dim`; pick the hex that matches how strong the user wants it.

Key names follow the physical key (`W`, `F5`, `Escape`, `LeftShift`, `Numpad7`, `UpArrow`, `Space`,
`QButton`) and common shorthand is accepted (`esc`, `ctrl`, `pgup`, `num7`, `up`). The keyboard is a
PC layout: on a Mac the Windows key is Command (`cmd`/`command` alias `LeftWindows`) and Alt is
Option (`option` aliases `LeftAlt`). Groups: `letters`, `numbers`, `fkeys`, `numpad`, `arrows`,
`nav`, `modifiers`, `wasd`, `media`, `punctuation`, `extras`, `all`. Names are case-insensitive and
ignore spaces, underscores, and hyphens.

### Multi-color layouts with a map file

For anything with more than one color, write a small JSON file (the scratchpad directory is fine) and
pass it with `-Map` / `--map`. Entries apply in order and later entries overwrite earlier ones (last
write wins), so put the base color first and the highlights after it:

```json
{ "all": "dim", "wasd": "red", "arrows": "red", "fkeys": "cyan", "Escape": "FF00FF" }
```

The user usually describes layouts in plain words ("gaming layout", "highlight the keys I use for
vim"). Translate that into keys and groups yourself; do not ask them for key IDs.

## Things worth knowing

- **Colors do not survive a power cycle.** The keyboard reverts to its built-in default whenever it
  loses USB power: reboot, replug, every KVM switch, and some sleep/wake cycles. The repo's installer
  registers a background watcher that applies the color at login and again each time the keyboard
  reconnects (no polling). Run it again with a new value to change the color; it replaces and restarts
  the watcher.
  - Windows: `install.ps1 -StartupColor <color>` or `-StartupMap <layout.json>` creates the logon
    scheduled task "Das Keyboard Startup Color" running `scripts/Watch-DasKeyboard.ps1`.
    `install.ps1 -RemoveStartupTask` removes it. Check with `Get-ScheduledTask`; log at
    `%LOCALAPPDATA%\das-keyboard\watch.log`.
  - macOS: `install.sh --startup-color <color>` or `--startup-map <layout.json>` writes the launchd
    agent `com.das-keyboard.startup-color` running `scripts/watch_das_keyboard.py`.
    `install.sh --remove-startup-task` removes it. Check with
    `launchctl print gui/$(id -u)/com.das-keyboard.startup-color`; log at
    `~/Library/Logs/das-keyboard/watch.log`.
  If the user says the color is lost after a KVM switch or replug, check whether the watcher is
  registered and running, and read its log.
- **There is no brightness command.** Dim by choosing a darker color (`808000` is half-brightness
  yellow, `dim` is a faint gray). "Maximum intensity" means full-value channels, e.g. `FF0000`.
- **Effects are per key.** Breathing on `fkeys` makes only the F-keys breathe; everything else keeps
  its previous color and mode.
- **The Q button (top right) takes a color but no effect mode.** The scripts handle this.
- **Verification is by eye.** The script reports what it sent, and the keyboard has no readback. Tell
  the user what you set and let them confirm it looks right. If the output says the keyboard was not
  found, it is unplugged, switched away on the KVM, or a different model; the scripts look for USB
  vendor 24F0 with product IDs 2037 (4Q), 2020 (5Q), 209A (5QS).
- **If the handshake warning appears** ("did not answer the handshake") the colors are still applied.
  It only means firmware/layout detection failed that run.

## Examples

**User:** make my keyboard blue
**Run (Windows):** `... -File "<skill dir>\scripts\Set-DasKeyboard.ps1" blue`
**Run (macOS):** `/usr/bin/python3 -I "<skill dir>/scripts/das_keyboard.py" blue`

**User:** light up wasd and the arrow keys in green, everything else off
**Run:** map file `{ "all": "off", "wasd": "green", "arrows": "green" }`

**User:** can you make it slowly pulse orange
**Run:** `... orange -Mode Breathing` / `... orange --mode Breathing`

**User:** turn the keyboard lights off, I'm done for the night
**Run:** `... -Off` / `... --off`, and mention they come back at next login if a startup watcher is registered.
