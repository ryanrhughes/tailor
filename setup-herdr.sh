#!/bin/bash
# Configure Herdr and its Omarchy-driven theme integration.
# Idempotent: safe to re-run.

set -euo pipefail

hdr()  { echo ""; echo "=== $1 ==="; }
ok()   { echo "  ✓ $1"; }
info() { echo "  ℹ $1"; }
warn() { echo "  ⚠ $1"; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

HERDR_CONFIG_SOURCE="$SCRIPT_DIR/config/herdr/config.toml"
HERDR_CONFIG_TARGET="$HOME/.config/herdr/config.toml"
HERDR_CONFIG_BACKUP="$HOME/.config/herdr/config.toml.bak.before-tailor-herdr"

THEME_TEMPLATE_SOURCE="$SCRIPT_DIR/config/omarchy/themed/herdr.toml.tpl"
THEME_TEMPLATE_TARGET="$HOME/.config/omarchy/themed/herdr.toml.tpl"

HOOK_SOURCE="$SCRIPT_DIR/config/omarchy/hooks/theme-set.d/sync-herdr"
HOOK_TARGET="$HOME/.config/omarchy/hooks/theme-set.d/sync-herdr"

CURRENT_THEME_FRAGMENTS=(
  "$HOME/.local/state/omarchy/current/theme/herdr.toml"
  "$HOME/.config/omarchy/current/theme/herdr.toml"
)

copy_file() {
  local mode="$1" source="$2" target="$3"

  if [[ ! -f $source ]]; then
    warn "Missing source file: $source"
    return 1
  fi

  mkdir -p "$(dirname "$target")"
  install -m "$mode" "$source" "$target"
}

backup_existing_config_once() {
  if [[ -f $HERDR_CONFIG_TARGET && ! -f $HERDR_CONFIG_BACKUP ]]; then
    cp -p "$HERDR_CONFIG_TARGET" "$HERDR_CONFIG_BACKUP"
    ok "Backed up existing Herdr config to $HERDR_CONFIG_BACKUP"
  fi
}

refresh_omarchy_theme() {
  if ! command -v omarchy >/dev/null 2>&1; then
    warn "omarchy not in PATH — installed theme files but could not render current Herdr theme"
    return 1
  fi

  info "Rendering current Omarchy theme for Herdr..."
  if OMARCHY_THEME_SKIP_BACKGROUND=1 omarchy theme refresh; then
    ok "Omarchy theme refreshed"
  else
    warn "omarchy theme refresh failed — trying the Herdr sync hook directly"
    return 1
  fi
}

run_sync_hook_directly() {
  local fragment

  for fragment in "${CURRENT_THEME_FRAGMENTS[@]}"; do
    if [[ -f $fragment ]]; then
      if bash "$HOOK_TARGET"; then
        ok "Herdr theme synced from $fragment"
      else
        warn "Herdr sync hook failed"
      fi
      return 0
    fi
  done

  warn "No generated Herdr theme fragment found yet; it will be created on the next Omarchy theme change"
  return 1
}

reload_herdr_config_without_theme() {
  local herdr_bin=""

  if [[ -x $HOME/.local/bin/herdr ]]; then
    herdr_bin="$HOME/.local/bin/herdr"
  elif command -v herdr >/dev/null 2>&1; then
    herdr_bin="$(command -v herdr)"
  elif [[ -x $HOME/.local/share/mise/installs/herdr/latest/herdr ]]; then
    herdr_bin="$HOME/.local/share/mise/installs/herdr/latest/herdr"
  fi

  [[ -n $herdr_bin ]] || return 0
  "$herdr_bin" server reload-config >/dev/null 2>&1 || true
}

hdr "Herdr"

if command -v herdr >/dev/null 2>&1; then
  ok "herdr installed: $(herdr --version 2>&1 | head -1)"
elif [[ -x $HOME/.local/bin/herdr || -x $HOME/.local/share/mise/installs/herdr/latest/herdr ]]; then
  ok "herdr installed"
else
  warn "herdr not found — installing config/theme files anyway"
fi

backup_existing_config_once
copy_file 0644 "$HERDR_CONFIG_SOURCE" "$HERDR_CONFIG_TARGET"
ok "Installed Herdr config to $HERDR_CONFIG_TARGET"

copy_file 0644 "$THEME_TEMPLATE_SOURCE" "$THEME_TEMPLATE_TARGET"
ok "Installed Omarchy Herdr theme template"

copy_file 0755 "$HOOK_SOURCE" "$HOOK_TARGET"
ok "Installed Omarchy Herdr theme sync hook"

if refresh_omarchy_theme; then
  # omarchy theme refresh runs the theme-set hooks, including sync-herdr. Run it
  # once more directly as a belt-and-suspenders check and to emit a clear status.
  run_sync_hook_directly || true
else
  run_sync_hook_directly || reload_herdr_config_without_theme
fi

ok "Herdr setup complete"
