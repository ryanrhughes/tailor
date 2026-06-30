#!/bin/bash
# Configure Herdr, its Omarchy-driven theme integration, and the herdr-omarchy layout plugin.
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

HERDR_OMARCHY_PLUGIN_ID="herdr-omarchy"
HERDR_OMARCHY_PLUGIN_SOURCE="$SCRIPT_DIR/herdr-omarchy"
HERDR_OMARCHY_COMMANDS=(hdl hds hdlm hsl)

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

migrate_legacy_herdr_layout_helpers() {
  local found=false
  local path rc

  for path in \
    "$HOME/.local/bin/herdr-dev" \
    "$HOME/.local/bin/herdr-tds" \
    "$HOME/.local/bin/herdr-tdlm" \
    "$HOME/.local/bin/herdr-tsl"; do
    if [[ -f $path ]] && grep -q 'HERDR_DEV_\|exec herdr-dev --layout\|herdr-tdlm' "$path" 2>/dev/null; then
      rm -f "$path"
      ok "Removed legacy Herdr helper $path"
      found=true
    fi
  done

  for rc in "$HOME/.zshrc" "$HOME/.bashrc"; do
    [[ -f $rc ]] || continue
    if grep -q '# BEGIN TAILOR HERDR ALIASES' "$rc"; then
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
      found=true
    fi
  done

  if [[ $found == true ]]; then
    info "Open a new shell, or run 'unalias hdl hds hdlm hsl hic hix hicx 2>/dev/null || true', to drop aliases already loaded in this shell"
  else
    ok "No legacy Herdr layout helpers found"
  fi
}

install_herdr_omarchy_plugin() {
  if [[ ! -d $HERDR_OMARCHY_PLUGIN_SOURCE ]]; then
    warn "Missing Herdr Omarchy plugin source: $HERDR_OMARCHY_PLUGIN_SOURCE"
    return 1
  fi

  if ! command -v herdr >/dev/null 2>&1; then
    warn "herdr not in PATH — cannot link $HERDR_OMARCHY_PLUGIN_ID plugin yet"
    return 1
  fi

  # Tailor links the plugin from this checkout so local updates take effect on
  # the next run. If an older GitHub-managed install exists, remove it first.
  herdr plugin unlink "$HERDR_OMARCHY_PLUGIN_ID" >/dev/null 2>&1 || \
    herdr plugin uninstall "$HERDR_OMARCHY_PLUGIN_ID" >/dev/null 2>&1 || true

  if herdr plugin link "$HERDR_OMARCHY_PLUGIN_SOURCE" >/dev/null 2>&1; then
    ok "Linked $HERDR_OMARCHY_PLUGIN_ID plugin from $HERDR_OMARCHY_PLUGIN_SOURCE"
    return 0
  fi

  warn "Could not link $HERDR_OMARCHY_PLUGIN_ID plugin"
  if herdr status server 2>/dev/null | grep -q '^compatible: no'; then
    warn "Running Herdr server is older than the CLI; run 'herdr update --handoff' or restart Herdr, then re-run Tailor"
  else
    warn "Run 'herdr plugin link $HERDR_OMARCHY_PLUGIN_SOURCE' after Herdr is running with plugin support"
  fi
  return 1
}

install_herdr_omarchy_commands() {
  local command target wrapper

  if [[ ! -x $HERDR_OMARCHY_PLUGIN_SOURCE/bin/herdr-omarchy ]]; then
    warn "Missing Herdr Omarchy command implementation: $HERDR_OMARCHY_PLUGIN_SOURCE/bin/herdr-omarchy"
    return 1
  fi

  mkdir -p "$HOME/.local/bin"
  for command in "${HERDR_OMARCHY_COMMANDS[@]}"; do
    target="$HOME/.local/bin/$command"
    wrapper=$(cat <<EOF
#!/usr/bin/env bash
# Tailor-managed dispatcher for the herdr-omarchy plugin.
# The layout implementation lives in the plugin; this command only preserves the
# fast shell workflow for Herdr-specific h* names and leaves tmux t* names alone.
set -euo pipefail

if [[ -z \${HERDR_ENV:-} || -z \${HERDR_PANE_ID:-} ]]; then
  echo "$command: run this from inside a Herdr pane (start Herdr with: herdr)" >&2
  exit 1
fi

export HERDR_OMARCHY_CWD="\$PWD"
exec "$HERDR_OMARCHY_PLUGIN_SOURCE/bin/herdr-omarchy" "$command" "\$@"
EOF
)
    if [[ ! -f $target ]] || [[ $(<"$target") != "$wrapper" ]]; then
      printf '%s\n' "$wrapper" >"$target"
      chmod 0755 "$target"
      ok "Installed $command dispatcher to $target"
    else
      ok "$command dispatcher already installed"
    fi
  done
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
migrate_legacy_herdr_layout_helpers
copy_file 0644 "$HERDR_CONFIG_SOURCE" "$HERDR_CONFIG_TARGET"
ok "Installed Herdr config to $HERDR_CONFIG_TARGET"

copy_file 0644 "$THEME_TEMPLATE_SOURCE" "$THEME_TEMPLATE_TARGET"
ok "Installed Omarchy Herdr theme template"

copy_file 0755 "$HOOK_SOURCE" "$HOOK_TARGET"
ok "Installed Omarchy Herdr theme sync hook"

install_herdr_omarchy_plugin || true
install_herdr_omarchy_commands || true

if refresh_omarchy_theme; then
  # omarchy theme refresh runs the theme-set hooks, including sync-herdr. Run it
  # once more directly as a belt-and-suspenders check and to emit a clear status.
  run_sync_hook_directly || true
else
  run_sync_hook_directly || reload_herdr_config_without_theme
fi

ok "Herdr setup complete"
