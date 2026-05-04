#!/bin/bash
# Setup AI coding tools (OpenCode)
# This script is idempotent - safe to run multiple times

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "Setting up AI coding tools..."

# Setup Claude Code settings
setup_claude_code() {
  echo ""
  echo "=== Claude Code ==="

  local settings_file="$HOME/.claude/settings.json"
  mkdir -p "$HOME/.claude"

  if [ ! -f "$settings_file" ]; then
    echo '{}' > "$settings_file"
  fi

  # Disable co-authored-by attribution on commits and PRs
  local updated
  updated=$(jq '.attribution = { commit: "", pr: "" }' "$settings_file")
  echo "$updated" > "$settings_file"
  echo "  ✓ Claude Code settings configured"
}

# Setup OpenCode
setup_opencode() {
  echo ""
  echo "=== OpenCode ==="
  
  local config_dir="$HOME/.config/opencode"
  local source_file="$SCRIPT_DIR/config/opencode/opencode.jsonc"
  local target_file="$config_dir/opencode.jsonc"
  local source_cmd_dir="$SCRIPT_DIR/config/opencode/command"
  local target_cmd_dir="$config_dir/command"
  
  if [ ! -f "$source_file" ]; then
    echo "  ! Source config not found: $source_file"
    return 1
  fi
  
  mkdir -p "$config_dir"
  
  # Copy config (overwrites existing)
  cp "$source_file" "$target_file"
  echo "  ✓ Copied opencode.jsonc to $config_dir"
  
  # Copy custom commands
  if [ -d "$source_cmd_dir" ]; then
    mkdir -p "$target_cmd_dir"
    cp -r "$source_cmd_dir"/* "$target_cmd_dir"/
    echo "  ✓ Copied custom commands to $target_cmd_dir"
  fi
}

# Run setup (skills moved to setup-ai-skills.sh)
setup_claude_code
setup_opencode

echo ""
echo "Done!"
