#!/bin/bash
# Setup AI coding tools (Claude Code, Pi, Codex, Mosaic, OpenCode)
# This script is idempotent - safe to run multiple times

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

MOSAIC_BASE_URL="${MOSAIC_BASE_URL:-https://mosaic.heyoodle.com}"
MOSAIC_CLI_INSTALL_URL="https://a.mosaic.heyoodle.com/a/mosaic/cli/install.sh"

# Canonical AI CLIs — installed globally via mise on every machine.
# "<command>=<mise tool>": command is the bin that must be on PATH, tool is
# the mise registry id (or backend-prefixed spec when not in the registry).
# Package sources match Omarchy's install/packaging/npm.sh list.
AI_CLIS=(
  "claude=claude"
  "codex=codex"
  "pi=pi"
  "opencode=opencode"
  "gemini=gemini"
  "copilot=copilot"
  "playwright=npm:playwright"
  "ghui=npm:@kitlangton/ghui"
  "hunk=hunk"
)

# On PATH, or installed via mise even if this shell's PATH predates it.
cli_available() {
  command -v "$1" >/dev/null 2>&1 ||
    { command -v mise >/dev/null 2>&1 && mise which "$1" >/dev/null 2>&1; }
}

# Install AI CLI binaries through mise when any canonical CLI is missing.
ensure_mise_ai_clis() {
  hdr "AI CLI binaries"

  local entry cmd tool
  local missing=()
  for entry in "${AI_CLIS[@]}"; do
    cmd="${entry%%=*}"
    if ! cli_available "$cmd"; then
      missing+=("$entry")
    fi
  done

  if [ "${#missing[@]}" -eq 0 ]; then
    ok "all AI CLIs already installed (${AI_CLIS[*]%%=*})"
    return 0
  fi

  if ! command -v mise >/dev/null 2>&1; then
    warn "mise is required to install missing AI CLIs: ${missing[*]%%=*}"
    return 1
  fi

  for entry in "${missing[@]}"; do
    cmd="${entry%%=*}"
    tool="${entry#*=}"
    info "Installing $cmd via mise ($tool)..."
    mise use -g "$tool"
  done
  hash -r

  # Verify via mise, not command -v: a shell whose PATH predates the install
  # won't see the new shims until mise activate refreshes it.
  local still_missing=() path_stale=()
  for entry in "${missing[@]}"; do
    cmd="${entry%%=*}"
    if command -v "$cmd" >/dev/null 2>&1; then
      continue
    elif mise which "$cmd" >/dev/null 2>&1; then
      path_stale+=("$cmd")
    else
      still_missing+=("$cmd")
    fi
  done

  if [ "${#still_missing[@]}" -gt 0 ]; then
    warn "Still missing after mise install: ${still_missing[*]}"
    hint "Check the tool spec in AI_CLIS and re-run: ./tailor.sh ai"
    return 1
  fi

  if [ "${#path_stale[@]}" -gt 0 ]; then
    info "Installed but not on this shell's PATH yet: ${path_stale[*]} (new shells will see them)"
  fi

  ok "AI CLIs installed via mise"
}

# Install Mosaic, trigger login when needed, then install the agent skill.
setup_mosaic() {
  hdr "Mosaic"

  if command -v mosaic >/dev/null 2>&1; then
    ok "mosaic installed: $(mosaic version 2>&1 | head -1)"
  else
    info "Installing mosaic..."
    curl -fsSL "$MOSAIC_CLI_INSTALL_URL" | bash
    hash -r

    if ! command -v mosaic >/dev/null 2>&1; then
      warn "mosaic still not on PATH after install"
      hint "Ensure ~/.local/bin is on PATH, then re-run tailor."
      return 1
    fi

    ok "mosaic installed: $(mosaic version 2>&1 | head -1)"
  fi

  if mosaic --base-url "$MOSAIC_BASE_URL" list >/dev/null 2>&1; then
    ok "mosaic authenticated"
  elif [ -n "${MOSAIC_TOKEN:-}" ]; then
    info "Logging into mosaic with MOSAIC_TOKEN..."
    mosaic login --base-url "$MOSAIC_BASE_URL" --token "$MOSAIC_TOKEN"
    ok "mosaic login saved"
  elif [ -t 0 ] && [ -t 1 ]; then
    info "Starting mosaic login workflow..."
    mosaic login --base-url "$MOSAIC_BASE_URL"
  else
    warn "mosaic login required"
    hint "Create a scoped agent token: $MOSAIC_BASE_URL/my/agents"
    hint "Or create a personal token: $MOSAIC_BASE_URL/my/api_keys"
    hint "Then run: mosaic login --base-url $MOSAIC_BASE_URL --token \"mosaic_pat_...\""
  fi

  info "Installing mosaic agent skill..."
  mosaic skill install
  ok "mosaic skill installed"
}

# Setup Claude Code settings
setup_claude_code() {
  hdr "Claude Code"

  local settings_file="$HOME/.claude/settings.json"
  mkdir -p "$HOME/.claude"

  if [ ! -f "$settings_file" ]; then
    echo '{}' > "$settings_file"
  fi

  # Disable co-authored-by attribution on commits and PRs
  local updated
  updated=$(jq '.attribution = { commit: "", pr: "" }' "$settings_file")
  echo "$updated" > "$settings_file"
  ok "Claude Code settings configured"
}

# Setup OpenCode
setup_opencode() {
  hdr "OpenCode"

  local config_dir="$HOME/.config/opencode"
  local source_file="$SCRIPT_DIR/config/opencode/opencode.jsonc"
  local target_file="$config_dir/opencode.jsonc"
  local source_cmd_dir="$SCRIPT_DIR/config/opencode/command"
  local target_cmd_dir="$config_dir/command"

  if [ ! -f "$source_file" ]; then
    warn "Source config not found: $source_file"
    return 1
  fi

  mkdir -p "$config_dir"

  # Copy config (overwrites existing)
  cp "$source_file" "$target_file"
  ok "Copied opencode.jsonc to $config_dir"

  # Copy custom commands
  if [ -d "$source_cmd_dir" ]; then
    mkdir -p "$target_cmd_dir"
    cp -r "$source_cmd_dir"/* "$target_cmd_dir"/
    ok "Copied custom commands to $target_cmd_dir"
  fi
}

# Run setup (skills moved to setup-ai-skills.sh)
ensure_mise_ai_clis
setup_mosaic
setup_claude_code
setup_opencode
