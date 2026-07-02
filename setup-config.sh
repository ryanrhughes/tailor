#!/bin/bash
# Install dotfiles and custom scripts:
#   - config/** → ~/.config/** (excluding dirs owned by their own setup script)
#   - bin/**    → ~/.local/bin/
#   - Hyprland: source windows.conf, enable 4K scaling in monitors.conf
# Idempotent: copies overwrite in place; Hyprland edits are guarded.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"
source "$SCRIPT_DIR/lib/common.sh"

hdr "Config files"

# Copy ~/.config files, excluding directories that have their own setup script
# (opencode → setup-ai.sh, herdr/omarchy → setup-herdr.sh).
mkdir -p ~/.config
find config -type f \
  ! -path "config/opencode/*" \
  ! -path "config/herdr/*" \
  ! -path "config/omarchy/*" \
  -exec sh -c 'mkdir -p ~/.config/$(dirname ${1#config/}) && cp "$1" ~/.config/${1#config/}' _ {} \;
ok "Copied config/ files to ~/.config/"

hdr "Custom scripts"

mkdir -p ~/.local/bin
for script in bin/*; do
  if [ -f "$script" ]; then
    cp "$script" ~/.local/bin/
    chmod +x ~/.local/bin/"$(basename "$script")"
    ok "Installed $(basename "$script") to ~/.local/bin/"
  fi
done

hdr "Hyprland"

# Legacy Hyprland .conf installs need windows.conf sourced explicitly. Modern
# Omarchy uses hyprland.lua, so do not create a stale hyprland.conf on Lua-based
# systems.
if [ ! -f ~/.config/hypr/hyprland.conf ] || [ -f ~/.config/hypr/hyprland.lua ]; then
  ok "Lua-based Hyprland config — windows.conf source line not needed"
elif grep -q "source = ~/.config/hypr/windows.conf" ~/.config/hypr/hyprland.conf 2>/dev/null; then
  ok "windows.conf already sourced in hyprland.conf"
else
  echo "source = ~/.config/hypr/windows.conf" >> ~/.config/hypr/hyprland.conf
  ok "Added windows.conf source to hyprland.conf"
fi

# Check monitor resolution and adjust monitors.conf for 4K displays
if pgrep -x Hyprland &>/dev/null; then
  resolution=$(hyprctl monitors -j | jq -r '.[0] | "\(.width)x\(.height)"')
  if [ "$resolution" = "3840x2160" ] && [ -f ~/.config/hypr/monitors.conf ]; then
    sed -i 's/^# monitor=,preferred,auto,1.666667/monitor=,preferred,auto,1.666667/' ~/.config/hypr/monitors.conf
    sed -i 's/^monitor=,preferred,auto,auto/# monitor=,preferred,auto,auto/' ~/.config/hypr/monitors.conf
    ok "4K display detected — monitors.conf scaling applied"
  else
    ok "No monitors.conf changes needed (resolution: $resolution)"
  fi
else
  info "Hyprland not running — skipped monitor resolution check"
fi
