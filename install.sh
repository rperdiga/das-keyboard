#!/bin/bash
# Installs the das-keyboard skill for Claude Code on macOS and (optionally) a launchd agent that
# keeps a color applied across reboots, replugs and KVM switches.
#
#   ./install.sh                             install/confirm the skill only
#   ./install.sh --startup-color yellow      also keep every key yellow (at login and on every reconnect)
#   ./install.sh --startup-map layout.json   same with a multi-color JSON layout
#   ./install.sh --remove-startup-task       stop and remove the agent
#   ./install.sh --skip-skill                only manage the agent; do not copy the skill files
set -euo pipefail

LABEL="com.das-keyboard.startup-color"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
SOURCE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET="$HOME/.claude/skills/das-keyboard"
LOG_DIR="$HOME/Library/Logs/das-keyboard"

startup_color=""; startup_map=""; remove=0; skip_skill=0
while [ $# -gt 0 ]; do
  case "$1" in
    --startup-color) startup_color="$2"; shift 2 ;;
    --startup-map)   startup_map="$2"; shift 2 ;;
    --remove-startup-task) remove=1; shift ;;
    --skip-skill)    skip_skill=1; shift ;;
    -h|--help) sed -n '2,10p' "$0"; exit 0 ;;
    *) echo "Unknown option: $1" >&2; exit 2 ;;
  esac
done
if [ -n "$startup_color" ] && [ -n "$startup_map" ]; then
  echo "Use either --startup-color or --startup-map, not both." >&2; exit 2
fi

# --- skill files -----------------------------------------------------------
if [ "$skip_skill" -eq 0 ]; then
  if [ -d "$TARGET" ] && [ "$(cd "$TARGET" && pwd -P)" = "$(cd "$SOURCE" && pwd -P)" ]; then
    echo "Skill already lives at $TARGET (this folder). Nothing to copy."
  else
    mkdir -p "$TARGET/scripts"
    cp "$SOURCE/SKILL.md" "$TARGET/"
    cp "$SOURCE/scripts/"*.py "$TARGET/scripts/"
    chmod +x "$TARGET/scripts/"*.py
    echo "Installed skill to $TARGET"
  fi
fi

SCRIPTS="$TARGET/scripts"
[ -f "$SCRIPTS/watch_das_keyboard.py" ] || SCRIPTS="$SOURCE/scripts"
SET_SCRIPT="$SCRIPTS/das_keyboard.py"
WATCH_SCRIPT="$SCRIPTS/watch_das_keyboard.py"

# --- startup agent ---------------------------------------------------------
if [ "$remove" -eq 1 ]; then
  if [ -f "$PLIST" ]; then
    launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
    rm -f "$PLIST"
    echo "Removed launch agent '$LABEL'."
  else
    echo "No launch agent named '$LABEL' exists."
  fi
fi

if [ -n "$startup_color" ] || [ -n "$startup_map" ]; then
  if [ -n "$startup_map" ]; then
    map_file="$TARGET/startup-layout.json"
    if [ "$(cd "$(dirname "$startup_map")" && pwd -P)/$(basename "$startup_map")" != "$map_file" ]; then
      cp "$startup_map" "$map_file"
    fi
    set_args=(--map "$map_file"); watch_args=(--map "$map_file"); what="layout $map_file"
  else
    set_args=("$startup_color"); watch_args=(--color "$startup_color"); what="$startup_color"
  fi

  # Apply once now; this validates the color/map and confirms the keyboard is reachable.
  /usr/bin/python3 -I "$SET_SCRIPT" "${set_args[@]}" || {
    echo "Could not set the color, so the startup agent was not registered." >&2; exit 1; }

  mkdir -p "$HOME/Library/LaunchAgents" "$LOG_DIR"
  {
    cat <<PL
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key>
  <array>
    <string>/usr/bin/python3</string>
    <string>-I</string>
    <string>$WATCH_SCRIPT</string>
PL
    for arg in "${watch_args[@]}"; do printf '    <string>%s</string>\n' "$arg"; done
    cat <<PL
  </array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>ProcessType</key><string>Background</string>
  <key>StandardOutPath</key><string>$LOG_DIR/agent.out.log</string>
  <key>StandardErrorPath</key><string>$LOG_DIR/agent.err.log</string>
</dict>
</plist>
PL
  } > "$PLIST"

  launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
  launchctl bootstrap "gui/$(id -u)" "$PLIST"
  echo "Registered and started '$LABEL': applies $what at login and whenever the keyboard reconnects (KVM switch, replug)."
  echo "Watcher log: $LOG_DIR/watch.log"
fi

if [ -z "$startup_color" ] && [ -z "$startup_map" ] && [ "$remove" -eq 0 ]; then
  echo "Tip: run './install.sh --startup-color yellow' to keep a color applied across reboots and KVM switches."
fi
