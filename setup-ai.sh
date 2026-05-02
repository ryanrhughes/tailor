#!/bin/bash
# Setup AI coding tools (OpenCode)
# This script is idempotent - safe to run multiple times

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "Setting up AI coding tools..."

# Install dependencies
install_deps() {
  echo ""
  echo "=== Dependencies ==="

  # Install figma-developer-mcp locally
  # Note: Uses --ignore-scripts to bypass sharp's broken install check on Node 25+
  local figma_mcp_dir="$HOME/.local/share/figma-mcp"
  if [ ! -d "$figma_mcp_dir/node_modules/figma-developer-mcp" ]; then
    echo "  Installing figma-developer-mcp..."
    mkdir -p "$figma_mcp_dir"
    cd "$figma_mcp_dir"
    npm init -y > /dev/null 2>&1
    npm install --ignore-scripts figma-developer-mcp > /dev/null 2>&1
    cd - > /dev/null
    echo "  ✓ Installed figma-developer-mcp"
  else
    echo "  ✓ figma-developer-mcp already installed"
  fi
}

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

# Check for required environment variables
check_env() {
  echo ""
  echo "=== Environment Check ==="
  
  local missing=()
  
  if [ -z "$FIGMA_API_KEY" ]; then
    missing+=("FIGMA_API_KEY")
  fi
  
  if [ ${#missing[@]} -gt 0 ]; then
    echo "  ! Missing environment variables (MCP servers may not work):"
    for var in "${missing[@]}"; do
      echo "    - $var"
    done
    echo ""
    echo "  To set them, either:"
    echo "    - Add to your shell profile (~/.bashrc, ~/.zshrc)"
    echo "    - Run: mise set $var=your-value"
  else
    echo "  ✓ All required environment variables set"
  fi
}

# Run setup (skills moved to setup-ai-skills.sh)
install_deps
setup_claude_code
setup_opencode
check_env

echo ""
echo "Done!"
