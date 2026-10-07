#!/bin/bash
# Set up AI tooling config: Mosaic, Claude Code settings, OpenCode.
# The AI CLIs themselves come from Omarchy. Idempotent - safe to re-run.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

MOSAIC_BASE_URL="${MOSAIC_BASE_URL:-https://mosaic.heyoodle.com}"
MOSAIC_CLI_INSTALL_URL="https://a.mosaic.heyoodle.com/a/mosaic/cli/install.sh"

mosaic_authenticated() {
  timeout 20 mosaic --base-url "$MOSAIC_BASE_URL" list </dev/null >/dev/null 2>&1
}

# Install Mosaic and trigger login when needed. Its skills come from ai-skills.
setup_mosaic() {
  hdr "Mosaic"

  if command -v mosaic >/dev/null 2>&1; then
    ok "mosaic installed: $(mosaic version 2>&1 | head -1)"
  else
    info "Installing mosaic..."
    local installer rc
    installer=$(mktemp)
    fetch "$MOSAIC_CLI_INSTALL_URL" "$installer" && bash "$installer"
    rc=$?
    rm -f "$installer"
    [ "$rc" -eq 0 ] || return 1
    hash -r

    if ! command -v mosaic >/dev/null 2>&1; then
      warn "mosaic still not on PATH after install"
      hint "Ensure ~/.local/bin is on PATH, then re-run tailor."
      return 1
    fi

    ok "mosaic installed: $(mosaic version 2>&1 | head -1)"
  fi

  if mosaic_authenticated; then
    ok "mosaic authenticated"
    return 0
  fi

  # Prompt with a hidden input: mosaic's own paste prompt echoes the token.
  local token="${MOSAIC_TOKEN:-}"
  if [ -z "$token" ] && is_interactive; then
    info "mosaic login required — create a token at:"
    hint "$MOSAIC_BASE_URL/my/api_keys (personal) or $MOSAIC_BASE_URL/my/agents (scoped)"
    token=$(gum input --password --placeholder "mosaic_pat_..." \
      --header "Paste your Mosaic API token (hidden; Esc to skip)") || token=""
  fi

  if [ -z "$token" ]; then
    warn "mosaic login required"
    hint "Create a token: $MOSAIC_BASE_URL/my/api_keys (personal) or $MOSAIC_BASE_URL/my/agents (scoped)"
    hint "Then re-run: ./tailor.sh ai  (or set MOSAIC_TOKEN)"
    return 0
  fi

  # Hand the token over in a private file rather than argv, where ps shows it.
  local token_file rc
  token_file=$(mktemp)
  printf '%s\n' "$token" > "$token_file"
  mosaic login --base-url "$MOSAIC_BASE_URL" --token-file "$token_file" </dev/null >/dev/null 2>&1
  rc=$?
  rm -f "$token_file"

  if [ "$rc" -eq 0 ] && mosaic_authenticated; then
    ok "mosaic login saved and verified"
  else
    warn "mosaic rejected that token"
    return 1
  fi
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
  updated=$(jq '.attribution = { commit: "", pr: "" }' "$settings_file") || {
    warn "$settings_file is not valid JSON — left untouched"
    return 1
  }
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
  cp "$source_file" "$target_file" || return 1
  ok "Copied opencode.jsonc to $config_dir"

  # Copy custom commands
  if [ -d "$source_cmd_dir" ]; then
    mkdir -p "$target_cmd_dir"
    cp -r "$source_cmd_dir"/* "$target_cmd_dir"/ || return 1
    ok "Copied custom commands to $target_cmd_dir"
  fi
}

# Run setup (skills are synced by setup-ai-skills.sh). Each part runs even if
# an earlier one failed; the step fails at the end if any did.
failed=()
setup_mosaic        || failed+=("mosaic")
setup_claude_code   || failed+=("claude-code")
setup_opencode      || failed+=("opencode")

if [ "${#failed[@]}" -gt 0 ]; then
  echo ""
  fail "failed: ${failed[*]}"
  exit 1
fi
