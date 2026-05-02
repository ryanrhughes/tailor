#!/bin/bash
# Configure Pi (the AI coding harness from @mariozechner/pi-coding-agent).
#
# Idempotent: safe to re-run.
#
# What this does:
#   1. Verifies pi is installed (run setup-ai-binaries.sh first if not).
#   2. Writes ~/.pi/agent/settings.json defaults — only fills missing fields,
#      so a user-changed provider/model is preserved across runs.
#   3. Installs any canonical extensions that aren't already in settings.json.

set -euo pipefail

hdr()  { echo ""; echo "=== $1 ==="; }
ok()   { echo "  ✓ $1"; }
info() { echo "  ℹ $1"; }
warn() { echo "  ⚠ $1"; }

hdr "Pi"

if ! command -v pi >/dev/null 2>&1; then
  warn "pi not in PATH — run setup-ai-binaries.sh first (or migrate off non-canonical install)"
  exit 0
fi

ok "pi installed: $(pi --version 2>&1 | head -1)"

SETTINGS="$HOME/.pi/agent/settings.json"
mkdir -p "$(dirname "$SETTINGS")"

# Canonical defaults (set only if not already present)
DEFAULT_PROVIDER="openai-codex"
DEFAULT_MODEL="gpt-5.5"
DEFAULT_THINKING="xhigh"
DEFAULT_QUIET_STARTUP=true

# Canonical npm extension list — order doesn't matter
EXTENSIONS=(
  pi-subagents
  pi-claude-bridge
  pi-web-access
  pi-powerline-footer
)

# pi-updater is a fork at github.com/ryanrhughes/pi-updater. We install
# it from a local clone so changes can be developed in place.
PI_UPDATER_DIR="$HOME/Work/pi-updater"
PI_UPDATER_REPO="git@github.com:ryanrhughes/pi-updater.git"
PI_UPDATER_PACKAGE_KEY="../../Work/pi-updater"

# Force canonical defaults on every run. To use a different provider/model
# for a session, change via `pi config` or pi's `/model` slash command;
# don't expect manual edits to settings.json to survive a tailor run.
existing=$(cat "$SETTINGS" 2>/dev/null || echo '{}')
echo "$existing" | jq \
  --arg p "$DEFAULT_PROVIDER" \
  --arg m "$DEFAULT_MODEL" \
  --arg t "$DEFAULT_THINKING" \
  --argjson q "$DEFAULT_QUIET_STARTUP" \
  '
  .defaultProvider      = $p |
  .defaultModel         = $m |
  .defaultThinkingLevel = $t |
  .quietStartup         = $q
  ' > "$SETTINGS.tmp"
mv "$SETTINGS.tmp" "$SETTINGS"

provider=$(jq -r '.defaultProvider'      "$SETTINGS")
model=$(jq    -r '.defaultModel'         "$SETTINGS")
thinking=$(jq -r '.defaultThinkingLevel' "$SETTINGS")
quiet=$(jq    -r '.quietStartup'         "$SETTINGS")
ok "settings: provider=$provider model=$model thinking=$thinking quietStartup=$quiet"

# Install missing npm extensions
for ext in "${EXTENSIONS[@]}"; do
  if jq -e --arg e "npm:$ext" '.packages // [] | index($e)' "$SETTINGS" > /dev/null 2>&1; then
    ok "$ext already installed"
  else
    info "Installing $ext..."
    pi install "npm:$ext"
    ok "$ext installed"
  fi
done

# Install pi-updater fork from local clone
if [[ ! -d "$PI_UPDATER_DIR/.git" ]]; then
  info "Cloning pi-updater fork to $PI_UPDATER_DIR..."
  mkdir -p "$(dirname "$PI_UPDATER_DIR")"
  git clone "$PI_UPDATER_REPO" "$PI_UPDATER_DIR"
  ok "pi-updater cloned"
else
  ok "pi-updater clone present at $PI_UPDATER_DIR"
fi

if jq -e --arg e "$PI_UPDATER_PACKAGE_KEY" '.packages // [] | index($e)' "$SETTINGS" > /dev/null 2>&1; then
  ok "pi-updater (fork) already installed"
else
  info "Installing pi-updater from $PI_UPDATER_DIR..."
  pi install "$PI_UPDATER_DIR"
  ok "pi-updater (fork) installed"
fi

# Log fork details + warn if working tree is dirty.
(
  cd "$PI_UPDATER_DIR"
  branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "?")
  commit=$(git rev-parse --short HEAD 2>/dev/null || echo "?")
  version=$(jq -r '.version' package.json 2>/dev/null || echo "?")
  ahead_behind=$(git rev-list --left-right --count "@{upstream}"...HEAD 2>/dev/null || echo "")
  ok "pi-updater fork: v$version branch=$branch commit=$commit"
  if [[ -n "$ahead_behind" ]]; then
    behind=${ahead_behind%%[[:space:]]*}
    ahead=${ahead_behind##*[[:space:]]}
    if [[ "$behind" != "0" || "$ahead" != "0" ]]; then
      info "pi-updater vs origin/$branch: $ahead ahead, $behind behind"
    fi
  fi
  if ! git diff --quiet || ! git diff --cached --quiet; then
    warn "pi-updater working tree has uncommitted changes"
    git -c color.status=always status -sb | sed 's/^/      /'
  fi
)
