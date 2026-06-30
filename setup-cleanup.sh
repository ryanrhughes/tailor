#!/bin/bash
# Cleanup stale Tailor-managed artifacts from previous versions.
# Idempotent: safe to re-run on every machine during migration.

set -euo pipefail

removed_any=false

hdr() { echo ""; echo "=== $1 ==="; }
ok()  { echo "  ✓ $1"; }
warn(){ echo "  ! $1"; }

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

echo "Cleaning up stale Tailor-managed artifacts..."
cleanup_figma_developer_mcp
cleanup_legacy_herdr_layout_helpers
cleanup_legacy_hypr_bindings_conf

if [ "$removed_any" = true ]; then
  echo ""
  ok "Cleanup complete"
else
  echo ""
  ok "Nothing to clean up"
fi
