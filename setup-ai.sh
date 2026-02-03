#!/bin/bash
# Setup AI coding tools (OpenCode, Amp)
# This script is idempotent - safe to run multiple times

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "Setting up AI coding tools..."

# Install dependencies
install_deps() {
  echo ""
  echo "=== Dependencies ==="

  # Install beads MCP server
  if ! command -v beads-mcp &> /dev/null; then
    echo "  Installing beads-git..."
    yay -S --noconfirm beads-git
    echo "  ✓ Installed beads-git"
  else
    echo "  ✓ beads-mcp already installed"
  fi

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

# Install AI skills
install_skills() {
  echo ""
  echo "=== AI Skills ==="

  # Check if skills CLI is available
  if ! command -v npx &> /dev/null; then
    echo "  ! npx not found, skipping skill installation"
    return 1
  fi

  # Install firecrawl skill for web operations
  echo "  Installing firecrawl skill..."
  npx skills add -g -y firecrawl/cli 2>/dev/null || echo "  ! Failed to install firecrawl skill"

  # Install rails-skills for Minitest testing
  echo "  Installing rails-skills..."
  npx skills add -g -y ThinkOodle/rails-skills 2>/dev/null || echo "  ! Failed to install rails-skills"

  # Install skill-creator for creating Agent Skills
  echo "  Installing skill-creator..."
  npx skills add -g -y https://github.com/anthropics/skills --skill skill-creator 2>/dev/null || echo "  ! Failed to install skill-creator"

  echo "  ✓ Skills installation complete"
}

# Install agent-browser for web automation
install_agent_browser() {
  echo ""
  echo "=== Agent Browser ==="

  # Check if agent-browser is already installed
  if ! command -v agent-browser &> /dev/null; then
    echo "  Installing agent-browser..."
    npm install -g agent-browser 2>/dev/null || echo "  ! Failed to install agent-browser"
  else
    echo "  ✓ agent-browser already installed"
  fi

  # Download Chromium browser
  echo "  Downloading Chromium for agent-browser..."
  agent-browser install 2>/dev/null || echo "  ! Failed to download Chromium"

  echo "  ✓ Agent browser setup complete"
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

# Setup Amp
setup_amp() {
  echo ""
  echo "=== Amp ==="
  
  local config_dir="$HOME/.config/amp"
  local source_file="$SCRIPT_DIR/config/amp/settings.json"
  local target_file="$config_dir/settings.json"
  
  if [ ! -f "$source_file" ]; then
    echo "  ! Source config not found: $source_file"
    return 1
  fi
  
  mkdir -p "$config_dir"
  
  # For Amp, we merge with existing settings to preserve user-specific data
  # like guardedFiles.allowlist entries and mcpTrustedServers
  if [ -f "$target_file" ] && command -v jq &> /dev/null; then
    # Merge: source values override target, but preserve target keys not in source
    jq -s '.[0] * .[1]' "$target_file" "$source_file" > "$target_file.tmp"
    mv "$target_file.tmp" "$target_file"
    echo "  ✓ Merged settings.json with existing config"
  else
    cp "$source_file" "$target_file"
    echo "  ✓ Copied settings.json to $config_dir"
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

# Run setup
install_deps
install_skills
install_agent_browser
setup_opencode
setup_amp
check_env

echo ""
echo "=== Post-setup ==="
echo "  For MCP servers requiring OAuth, run:"
echo "    opencode mcp auth <server-name>"
echo "    amp mcp oauth login <server-name>"
echo ""
echo "Done!"
