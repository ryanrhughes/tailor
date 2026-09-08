#!/bin/bash
# Install Kanata, its shared layout, local device selection, and desktop service.
# Pending markers make interrupted installs retryable without restarting healthy
# services on every run or turning off gaming mode.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

CONFIG_DIR="$HOME/.config/kanata"
SERVICE_TARGET="$HOME/.config/systemd/user/kanata.service"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/tailor/kanata"
RULE_SOURCE="$SCRIPT_DIR/udev/70-kanata.rules"
RULE_TARGET=/etc/udev/rules.d/70-kanata.rules
MODULE_TARGET=/etc/modules-load.d/kanata.conf

hdr "Kanata homerow mods"

mkdir -p "$STATE_DIR"
exec 9>"$STATE_DIR/setup.lock"
flock 9

if ! command -v kanata >/dev/null 2>&1; then
  info "Installing Kanata from AUR..."
  omarchy pkg aur add kanata
fi

stage=$(mktemp -d "$STATE_DIR/stage.XXXXXX")
trap 'rm -rf "$stage"' EXIT
cp "$SCRIPT_DIR/kanata/homerow-mods.kbd" "$stage/homerow-mods.kbd"

# Auto-detect keyboards on first install, including internal and combined
# keyboard/pointing devices. Preserve local policy unless explicitly replaced.
if [ -n "${TAILOR_KANATA_DEVICES:-}" ] || [ "${TAILOR_KANATA_EXCLUDE+x}" = x ] ||
    [ ! -f "$CONFIG_DIR/devices.kbd" ]; then
  python3 - "$stage/devices.kbd" <<'PYCFG'
import json
import os
from pathlib import Path
import sys

selection = os.environ.get("TAILOR_KANATA_DEVICES", "auto").strip()
def names(value):
    return list(dict.fromkeys(name.strip() for name in value.splitlines() if name.strip()))

def name_list(option, values):
    return "  " + option + " (\n" + "\n".join(
        "    " + json.dumps(name, ensure_ascii=False) for name in values
    ) + "\n  )\n"

policy = "  linux-device-detect-mode keyboard-mice\n"
if selection != "auto":
    selected = names(selection)
    if not selected:
        sys.exit("TAILOR_KANATA_DEVICES must be 'auto' or contain keyboard names")
    policy += name_list("linux-dev-names-include", selected)
excluded = names(os.environ.get("TAILOR_KANATA_EXCLUDE", ""))
if excluded:
    policy += name_list("linux-dev-names-exclude", excluded)
Path(sys.argv[1]).write_text(
    ";; Local keyboard selection. Tailor preserves this file on subsequent runs.\n"
    "(defcfg\n"
    "  process-unmapped-keys yes\n"
    "  concurrent-tap-hold yes\n"
    "  linux-continue-if-no-devs-found yes\n" + policy + ")\n"
)
PYCFG
else
  cp "$CONFIG_DIR/devices.kbd" "$stage/devices.kbd"
fi

# Check the complete candidate, including its local include, before replacing
# any live configuration. The typing guard requires Kanata 1.12 or later.
kanata --check --no-wait -c "$stage/homerow-mods.kbd"
udevadm verify --no-summary "$RULE_SOURCE"

# Also notice edits made directly to the local device selection. Comparing
# source and destination alone cannot tell whether the running service loaded it.
desired_hash=$(sha256sum "$stage/homerow-mods.kbd" "$stage/devices.kbd" \
  "$SCRIPT_DIR/kanata/kanata.service" | awk '{print $1}' | sha256sum | cut -d ' ' -f 1)
if [ ! -f "$STATE_DIR/applied-config" ] ||
    [ "$(cat "$STATE_DIR/applied-config")" != "$desired_hash" ]; then
  touch "$STATE_DIR/service-pending"
fi

install_user_file() {
  local source="$1" target="$2" mode="$3" restart="$4"
  if cmp -s "$source" "$target" && [ "$(stat -c %a "$target")" = "${mode#0}" ]; then
    return
  fi
  if [ "$restart" = yes ]; then touch "$STATE_DIR/service-pending"; fi
  mkdir -p "$(dirname "$target")"
  if [ -e "$target" ] && [ ! -e "$target.bak.before-tailor-kanata" ]; then
    cp -a "$target" "$target.bak.before-tailor-kanata"
  fi
  install -m "$mode" "$source" "$target"
  ok "Installed $target"
}

if [ ! -e "$SERVICE_TARGET" ]; then touch "$STATE_DIR/first-install"; fi
install_user_file "$stage/devices.kbd" "$CONFIG_DIR/devices.kbd" 0644 yes
install_user_file "$stage/homerow-mods.kbd" "$CONFIG_DIR/homerow-mods.kbd" 0644 yes
install_user_file "$SCRIPT_DIR/kanata/kanata.service" "$SERVICE_TARGET" 0644 yes
install_user_file "$SCRIPT_DIR/bin/kanata-status" "$HOME/.local/bin/kanata-status" 0755 no
install_user_file "$SCRIPT_DIR/bin/kanata-gaming-toggle" "$HOME/.local/bin/kanata-gaming-toggle" 0755 no

if [ -t 0 ] && [ -t 1 ]; then
  privilege=(sudo)
else
  privilege=(pkexec)
fi

# A static /dev/uinput node can exist before the module is loaded. In that
# state there is no sysfs device to trigger, so uaccess never grants access.
# Load it at boot and now, before applying device permissions.
printf 'uinput\n' > "$stage/kanata.conf"
if ! cmp -s "$stage/kanata.conf" "$MODULE_TARGET"; then
  touch "$STATE_DIR/udev-pending" "$STATE_DIR/service-pending"
  if [ -e "$MODULE_TARGET" ] && [ ! -e "$MODULE_TARGET.bak.before-tailor-kanata" ]; then
    "${privilege[@]}" cp -a "$MODULE_TARGET" "$MODULE_TARGET.bak.before-tailor-kanata"
  fi
  "${privilege[@]}" install -D -o root -g root -m 0644 "$stage/kanata.conf" "$MODULE_TARGET"
fi
if [ ! -d /sys/class/misc/uinput ]; then
  touch "$STATE_DIR/udev-pending" "$STATE_DIR/service-pending"
  "${privilege[@]}" modprobe uinput
fi

if ! cmp -s "$RULE_SOURCE" "$RULE_TARGET"; then
  touch "$STATE_DIR/udev-pending" "$STATE_DIR/service-pending"
  if [ -e "$RULE_TARGET" ] && [ ! -e "$RULE_TARGET.bak.before-tailor-kanata" ]; then
    "${privilege[@]}" cp -a "$RULE_TARGET" "$RULE_TARGET.bak.before-tailor-kanata"
  fi
  "${privilege[@]}" install -D -o root -g root -m 0644 "$RULE_SOURCE" "$RULE_TARGET"
fi

if [ -e "$STATE_DIR/udev-pending" ]; then
  # Keep both markers on failure, even if the installed file already matches.
  touch "$STATE_DIR/service-pending"
  "${privilege[@]}" udevadm control --reload-rules
  "${privilege[@]}" udevadm trigger --action=change --subsystem-match=input \
    --property-match=ID_INPUT_KEYBOARD=1 --settle
  "${privilege[@]}" udevadm trigger --action=change --subsystem-match=misc \
    --sysname-match=uinput --settle
  rm "$STATE_DIR/udev-pending"
  ok "Applied Kanata device permissions"
fi

if [ -e "$STATE_DIR/service-pending" ]; then
  systemctl --user daemon-reload
  # Reenable also migrates the old default.target link to graphical-session.
  systemctl --user reenable kanata.service

  service_state=$(systemctl --user show kanata.service -p ActiveState --value)
  case "$service_state" in
    active|activating|reloading|failed)
      systemctl --user restart kanata.service
      "$HOME/.local/bin/kanata-status" --wait 6
      ;;
    *)
      if [ -e "$STATE_DIR/first-install" ] &&
          systemctl --user is-active --quiet graphical-session.target; then
        systemctl --user start kanata.service
        "$HOME/.local/bin/kanata-status" --wait 6
      else
        info "Kanata will start at graphical login; an existing stopped service stays stopped"
      fi
      ;;
  esac
  printf '%s\n' "$desired_hash" > "$STATE_DIR/applied-config"
  rm -f "$STATE_DIR/service-pending" "$STATE_DIR/first-install"
else
  ok "Kanata setup already current"
fi
