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

echo "Cleaning up stale Tailor-managed artifacts..."
cleanup_figma_developer_mcp

if [ "$removed_any" = true ]; then
  echo ""
  ok "Cleanup complete"
else
  echo ""
  ok "Nothing to clean up"
fi
