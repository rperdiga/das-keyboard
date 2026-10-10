---
name: das-keyboard
description: Control the RGB backlight on the user's Das Keyboard 4Q (also works for 5Q/5QS) directly over USB on Windows, without the Das Keyboard Q software. Use this whenever the user mentions their keyboard lights, LEDs, backlight, key colors, lighting effects, turning the keyboard lighting off or on, highlighting specific keys (WASD, arrows, F-keys, numpad), or the Das Keyboard / "DAS" / "4Q" by name, even if they do not say "RGB" or "LED". Also use it for requests like "make my keyboard red", "dim the keyboard", "breathing effect", or "what color is my keyboard set to at startup".
---

# Das Keyboard lighting

The user has a Das Keyboard Q-series keyboard on Windows and does not want the vendor software
installed. `scripts/Set-DasKeyboard.ps1`, in this skill's own directory, talks to the keyboard over the
Windows HID API (hid.dll, setupapi.dll, both built in) using the protocol reverse-engineered by OpenRGB.
Nothing is installed and nothing is written to the keyboard's flash. The script is the whole interface:
run it, read its output, report back.

## Running it

The script lives at `scripts/Set-DasKeyboard.ps1` under this skill's base directory (the path shown
when the skill loads, normally `~\.claude\skills\das-keyboard`). Always invoke it through powershell.exe
with execution policy bypassed. From Bash or PowerShell:

```
powershell -NoProfile -ExecutionPolicy Bypass -File "<skill dir>\scripts\Set-DasKeyboard.ps1" <arguments>
```

| Goal | Arguments |
|------|-----------|
| Whole keyboard one color | `yellow` or `FFC800` or `"#ff0000"` |
| Only some keys | `red -Keys "wasd,arrows"` (other keys keep their current color) |
| Effect instead of static | `cyan -Mode Breathing` (`Direct`, `Breathing`, `Flashing`, `SpectrumCycle`) |
| Several colors at once | `-Map C:\path\layout.json` (see below) |
| Lights off | `-Off` |
| Detect keyboard, firmware, layout | `-Info` |
| Every valid key, group, and color name | `-ListKeys` |

The first positional argument is the color (not needed with `-Map`, `-Off`, `-Info`, `-ListKeys`).
Colors are 6-digit hex or names: red, green, blue, yellow (FFC800, a true LED yellow), lightyellow,
orange, white, warmwhite, coolwhite, cyan, magenta, purple, pink, lime, teal, gold, amber, gray
(404040), dim (202020, a faint gray), off. For a "dim white" or "soft white" background, a hex like
`606060` reads better than `dim`; pick the hex that matches how strong the user wants it.

Key names follow the physical key (`W`, `F5`, `Escape`, `LeftShift`, `Numpad7`, `UpArrow`, `Space`,
`QButton`) and common shorthand is accepted (`esc`, `ctrl`, `pgup`, `num7`, `up`). Groups: `letters`,
`numbers`, `fkeys`, `numpad`, `arrows`, `nav`, `modifiers`, `wasd`, `media`, `punctuation`, `extras`,
`all`. Names are case-insensitive and ignore spaces, underscores, and hyphens.

### Multi-color layouts with -Map

For anything with more than one color, write a small JSON file (the scratchpad directory is fine) and
pass it with `-Map`. Entries apply in order and later entries overwrite earlier ones (last write wins),
so put the base color first and the highlights after it:

```json
{ "all": "dim", "wasd": "red", "arrows": "red", "fkeys": "cyan", "Escape": "FF00FF" }
```

The user usually describes layouts in plain words ("gaming layout", "highlight the keys I use for
vim"). Translate that into keys and groups yourself; do not ask them for key IDs.

## Things worth knowing

- **Colors do not survive a power cycle.** The keyboard reverts to its built-in default whenever it
  loses USB power: reboot, replug, and every KVM switch. The repo's `install.ps1 -StartupColor <color>`
  (or `-StartupMap <layout.json>`) registers a logon scheduled task named "Das Keyboard Startup Color"
  that runs `scripts/Watch-DasKeyboard.ps1`, a hidden idle watcher that applies the color at sign-in and
  again each time the keyboard reconnects. To change the startup color or layout, run `install.ps1`
  again with the new value (it replaces and restarts the task); `install.ps1 -RemoveStartupTask`
  removes it. If the user says the color is lost after a KVM switch or replug, check whether that task
  exists and is Running (`Get-ScheduledTask`), and look at `%LOCALAPPDATA%\das-keyboard\watch.log`.
- **There is no brightness command.** Dim by choosing a darker color (`808000` is half-brightness
  yellow, `dim` is a faint gray).
- **Effects are per key.** `-Mode Breathing -Keys fkeys` makes only the F-keys breathe; everything
  else keeps its previous color and mode.
- **The Q button (top right) takes a color but no effect mode.** The script handles this.
- **Verification is by eye.** The script reports what it sent, and the keyboard has no readback. Tell
  the user what you set and let them confirm it looks right. If the output says the keyboard was not
  found, it is unplugged or a different model; the script looks for USB vendor 24F0 with product IDs
  2037 (4Q), 2020 (5Q), 209A (5QS).
- **If the handshake warning appears** ("did not answer the handshake") the colors are still applied.
  It only means firmware/layout detection failed that run.

## Examples

**User:** make my keyboard blue
**Run:** `... -File "<skill dir>\scripts\Set-DasKeyboard.ps1" blue`

**User:** light up wasd and the arrow keys in green, everything else off
**Run:** `-Map` with `{ "all": "off", "wasd": "green", "arrows": "green" }`

**User:** can you make it slowly pulse orange
**Run:** `... orange -Mode Breathing`

**User:** turn the keyboard lights off, I'm done for the night
**Run:** `... -Off` and mention they come back at next logon if a startup task is registered.
