#!/bin/bash
# Cleanup stale Tailor-managed artifacts from previous versions.
# Idempotent: safe to re-run on every machine during migration.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

removed_any=false

remove_path() {
  local path="$1"

  if [ -e "$path" ] || [ -L "$path" ]; then
    rm -rf "$path"
    ok "Removed $path"
    removed_any=true
  fi
}

cleanup_figma_developer_mcp() {
  hdr "figma-developer-mcp"

  local figma_mcp_dir="$HOME/.local/share/figma-mcp"
  local opencode_config="$HOME/.config/opencode/opencode.jsonc"
  local found=false

  if [ -d "$figma_mcp_dir/node_modules/figma-developer-mcp" ] || \
     { [ -f "$figma_mcp_dir/package.json" ] && grep -q 'figma-developer-mcp' "$figma_mcp_dir/package.json"; }; then
    found=true
    remove_path "$figma_mcp_dir"
  fi

  if command -v npm >/dev/null 2>&1 && npm list -g figma-developer-mcp --depth=0 >/dev/null 2>&1; then
    found=true
    if npm uninstall -g figma-developer-mcp >/dev/null 2>&1; then
      ok "Uninstalled global npm package figma-developer-mcp"
      removed_any=true
    else
      warn "Could not uninstall global npm package figma-developer-mcp"
    fi
  fi

  # setup-ai.sh rewrites this config later in the run. Removing the stale copy
  # avoids leaving a config that points at the old package if cleanup is run by itself.
  if [ -f "$opencode_config" ] && grep -q 'figma-developer-mcp\|figma-mcp' "$opencode_config"; then
    found=true
    remove_path "$opencode_config"
  fi

  if [ "$found" = false ]; then
    ok "figma-developer-mcp not installed"
  fi
}

cleanup_legacy_herdr_layout_helpers() {
  hdr "legacy Herdr layout helpers"

  local found=false
  local path rc

  for path in \
    "$HOME/.local/bin/herdr-dev" \
    "$HOME/.local/bin/herdr-tds" \
    "$HOME/.local/bin/herdr-tdlm" \
    "$HOME/.local/bin/herdr-tsl"; do
    if [ -f "$path" ] && grep -q 'HERDR_DEV_\|exec herdr-dev --layout\|herdr-tdlm' "$path" 2>/dev/null; then
      found=true
      remove_path "$path"
    fi
  done

  for rc in "$HOME/.zshrc" "$HOME/.bashrc"; do
    [ -f "$rc" ] || continue
    if grep -q '# BEGIN TAILOR HERDR ALIASES' "$rc"; then
      found=true
      python3 - "$rc" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
begin = "# BEGIN TAILOR HERDR ALIASES\n"
end = "# END TAILOR HERDR ALIASES\n"
text = path.read_text()
start = text.find(begin)
if start != -1:
    stop = text.find(end, start)
    if stop != -1:
        stop += len(end)
        text = text[:start].rstrip() + "\n" + text[stop:].lstrip("\n")
        path.write_text(text)
PY
      ok "Removed legacy Herdr alias block from $rc"
      removed_any=true
    fi
  done

  if [ "$found" = false ]; then
    ok "legacy Herdr layout helpers not installed"
  fi
}

cleanup_legacy_hypr_bindings_conf() {
  hdr "legacy Hyprland bindings.conf"

  local path="$HOME/.config/hypr/bindings.conf"

  if [ -f "$path" ] && \
     grep -q 'Personal Hyprland bindings' "$path" 2>/dev/null && \
     grep -q 'config/hypr/bindings.conf' "$path" 2>/dev/null; then
    remove_path "$path"
  else
    ok "legacy Tailor bindings.conf not installed"
  fi
}

# Older tailor managed Herdr: its own config.toml, a theme template + sync hook
# in ~/.config/omarchy, the herdr-omarchy plugin, and hdl/hds/hdlm/hsl
# symlinks. Omarchy now ships Herdr's config (themed via the terminal palette)
# and those layouts as shell functions, which the symlinks would shadow. Only
# files tailor recognizably wrote are touched.
cleanup_tailor_herdr() {
  hdr "Tailor-managed Herdr"

  local omarchy_path="${OMARCHY_PATH:-/usr/share/omarchy}"
  local config=~/.config/herdr/config.toml
  local backup="$config.bak.before-tailor-herdr"
  local default_config="$omarchy_path/config/herdr/config.toml"
  local found=false cmd link path

  if [ -f "$config" ] && grep -q '^# Managed by Tailor' "$config" && [ -f "$default_config" ]; then
    found=true
    cp -f "$default_config" "$config"
    ok "Restored Omarchy's Herdr config at $config"
    removed_any=true
    herdr server reload-config >/dev/null 2>&1 || true
  fi
  if [ -f "$backup" ] && cmp -s "$backup" "$default_config"; then
    remove_path "$backup"
  elif [ -f "$backup" ]; then
    info "Kept $backup — it differs from Omarchy's default; merge anything you still want"
  fi

  # Unlinking goes through the herdr server. With no server running, drop the
  # local link from the registry directly; nothing is holding it open.
  local registry=~/.config/herdr/plugins.json linked='.plugin_id == "herdr-omarchy" and .source.kind == "local"'
  if [ -f "$registry" ] && jq -e "any(.[]; $linked)" "$registry" >/dev/null 2>&1; then
    found=true
    if herdr plugin unlink herdr-omarchy >/dev/null 2>&1; then
      ok "Unlinked herdr-omarchy plugin"
      removed_any=true
    elif jq "map(select(($linked) | not))" "$registry" > "$registry.tmp" && mv "$registry.tmp" "$registry"; then
      ok "Removed herdr-omarchy from $registry (herdr server not running)"
      removed_any=true
    else
      rm -f "$registry.tmp"
      warn "Could not unlink herdr-omarchy plugin"
    fi
  fi
  [ -d ~/.config/herdr/plugins/config/herdr-omarchy ] && { found=true; remove_path ~/.config/herdr/plugins/config/herdr-omarchy; }

  for cmd in hdl hds hdlm hsl; do
    link=~/.local/bin/$cmd
    if [ -L "$link" ] && [[ "$(readlink "$link")" == */herdr-omarchy/bin/herdr-omarchy ]]; then
      found=true
      remove_path "$link"
    fi
  done

  path=~/.config/omarchy/themed/herdr.toml.tpl
  if [ -f "$path" ] && grep -q 'sync-herdr merges it into' "$path"; then
    found=true
    remove_path "$path"
  fi
  path=~/.config/omarchy/hooks/theme-set.d/sync-herdr
  if [ -f "$path" ] && grep -q 'Sync the generated Omarchy Herdr theme fragment' "$path"; then
    found=true
    remove_path "$path"
  fi

  if [ "$found" = false ]; then
    ok "no Tailor-managed Herdr setup found"
  fi
}

# Older tailor copied input.conf and windows.conf into ~/.config/hypr. Omarchy's
# Lua config never loads them, and its defaults now cover their settings. Only
# removed on Lua-based setups (where nothing can source them) and only when the
# file is recognizably tailor's.
cleanup_legacy_hypr_conf_overrides() {
  hdr "legacy Hyprland .conf overrides"

  local input=~/.config/hypr/input.conf windows=~/.config/hypr/windows.conf
  local found=false

  if [ ! -f ~/.config/hypr/hyprland.lua ]; then
    ok "not a Lua-based Hyprland config — leaving .conf files alone"
    return 0
  fi

  if [ -f "$input" ] && grep -q '^# Personal Hyprland input overrides' "$input"; then
    found=true
    remove_path "$input"
  fi
  if [ -f "$windows" ] && grep -q 'name = windowrule-1' "$windows" && grep -q 'match:class = qemu' "$windows"; then
    found=true
    remove_path "$windows"
  fi

  if [ "$found" = false ]; then
    ok "legacy Tailor input.conf/windows.conf not installed"
  fi
}

# The old `swap` step wrote these; Omarchy now ships its own memory tuning.
# 99-swappiness.conf sorts after 99-omarchy-sysctl.conf, so it silently pins
# swappiness to 10 over Omarchy's zram-tuned value. The zram file is shadowed by
# Omarchy's drop-in but its migration keeps it as a "local edit". Only files
# still holding exactly what tailor wrote are removed.
cleanup_legacy_swap_tuning() {
  hdr "legacy swap tuning"

  local sysctl_file=/etc/sysctl.d/99-swappiness.conf
  local zram_conf=/etc/systemd/zram-generator.conf
  local zram_tailor=$'[zram0]\nzram-size = ram / 2\ncompression-algorithm = zstd'
  local found=false

  if [ -f "$sysctl_file" ] && [ "$(cat "$sysctl_file")" = "vm.swappiness=10" ]; then
    found=true
    if sudo rm -f "$sysctl_file" && sudo sysctl --system >/dev/null; then
      ok "Removed $sysctl_file (swappiness now $(cat /proc/sys/vm/swappiness))"
      removed_any=true
    else
      warn "Could not remove $sysctl_file"
      return 1
    fi
  fi

  if [ -f "$zram_conf" ] && [ "$(cat "$zram_conf")" = "$zram_tailor" ]; then
    found=true
    # No zram restart needed: Omarchy's drop-in already sizes the live device.
    if sudo rm -f "$zram_conf"; then
      ok "Removed $zram_conf"
      removed_any=true
    else
      warn "Could not remove $zram_conf"
      return 1
    fi
  fi

  if [ "$found" = false ]; then
    ok "legacy swap tuning not installed"
  fi
}

# Older tailor installed Kitty and forced it as the Omarchy terminal. Put the
# default back to foot, then drop the package and Omarchy's copied kitty config
# (only if it's still the unmodified default).
cleanup_tailor_kitty() {
  hdr "Tailor-installed Kitty"

  local kitty_config=~/.config/kitty
  local omarchy_kitty_conf="${OMARCHY_PATH:-$HOME/.local/share/omarchy}/config/kitty/kitty.conf"
  local found=false

  if [ "$(omarchy default terminal 2>/dev/null)" = "kitty" ]; then
    found=true
    if ! command -v foot >/dev/null 2>&1; then
      warn "foot is not installed — leaving Kitty as the default terminal"
      return 0
    fi
    if omarchy default terminal foot >/dev/null 2>&1; then
      ok "Restored foot as the default terminal"
      removed_any=true
    else
      warn "Could not restore foot as the default terminal"
      return 1
    fi
  fi

  if pacman -Q kitty >/dev/null 2>&1; then
    found=true
    if omarchy-pkg-drop kitty >/dev/null; then
      ok "Removed kitty package"
      removed_any=true
    else
      warn "Could not remove kitty package"
      return 1
    fi
  fi

  if [ -d "$kitty_config" ] && [ "$(ls -A "$kitty_config")" = "kitty.conf" ] && \
     [ -f "$omarchy_kitty_conf" ] && cmp -s "$kitty_config/kitty.conf" "$omarchy_kitty_conf"; then
    found=true
    remove_path "$kitty_config"
  elif [ -d "$kitty_config" ]; then
    warn "Keeping $kitty_config (customized)"
  fi

  if [ "$found" = false ]; then
    ok "Kitty not installed"
  fi
}

echo "Cleaning up stale Tailor-managed artifacts..."
cleanup_figma_developer_mcp
cleanup_legacy_herdr_layout_helpers
cleanup_legacy_hypr_bindings_conf
cleanup_legacy_hypr_conf_overrides
cleanup_tailor_herdr
cleanup_legacy_swap_tuning
cleanup_tailor_kitty

if [ "$removed_any" = true ]; then
  echo ""
  ok "Cleanup complete"
else
  echo ""
  ok "Nothing to clean up"
fi
