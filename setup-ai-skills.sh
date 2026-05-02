#!/bin/bash
# Install/maintain the canonical AI skills allowlist.
# Idempotent: safe to re-run.
#
# Universal skills (installed on every machine):
#   - ThinkOodle/rails-skills    Rails dev (28 skills)
#   - firecrawl/cli              Web ops, replaces WebFetch/WebSearch
#   - skill-creator              Build/edit/test skills (Anthropic)
#
# Rejected (removed if found):
#   - find-skills                Not needed
#   - agent-browser              Replaced by chrome-devtools-mcp
#
# CLI-tied skills (cortex, nebula, hey, fizzy, basecamp) are installed by
# their respective CLI tools and are not managed here.
#
# The skills CLI writes to ~/.agents/skills/ by default, which Claude Code,
# Pi, and other harnesses pick up via their own resolution.

set -euo pipefail

hdr()  { echo ""; echo "=== $1 ==="; }
ok()   { echo "  ✓ $1"; }
info() { echo "  ℹ $1"; }
warn() { echo "  ⚠ $1"; }

hdr "AI skills"

if ! command -v npx >/dev/null 2>&1; then
  warn "npx not in PATH — skills install skipped (run setup-ai-binaries.sh first)"
  exit 0
fi

# Get currently installed global skills (names only, ANSI-stripped).
# Output format: indented "  <name> ~/.agents/skills/<name>" under category headers.
installed=$(npx --no-install skills list -g 2>&1 \
  | sed 's/\x1b\[[0-9;]*m//g' \
  | awk '/^[[:space:]]+[A-Za-z][A-Za-z0-9_-]* ~/{print $1}')

skill_present() {
  echo "$installed" | grep -qx "$1"
}

# --- Install canonical universal skills ---
declare -A INSTALL=(
  [firecrawl]="firecrawl/cli"
  [rails-skills]="ThinkOodle/rails-skills"
  # skill-creator lives in anthropics/skills repo; needs --skill subselection
  [skill-creator]="https://github.com/anthropics/skills --skill skill-creator"
)

for name in "${!INSTALL[@]}"; do
  source="${INSTALL[$name]}"
  # rails-skills installs many entries; check by sample name "active-storage"
  marker="$name"
  [ "$name" = "rails-skills" ] && marker="active-storage"

  if skill_present "$marker"; then
    ok "$name already installed"
  else
    info "Installing $name from $source..."
    # shellcheck disable=SC2086
    if npx skills add -g -y $source >/dev/null 2>&1; then
      ok "$name installed"
    else
      warn "Failed to install $name"
    fi
  fi
done

# --- Remove rejected skills ---
REMOVE=(find-skills agent-browser)

for name in "${REMOVE[@]}"; do
  if skill_present "$name"; then
    info "Removing $name..."
    if npx skills remove "$name" -g -y >/dev/null 2>&1; then
      ok "$name removed"
    else
      warn "Failed to remove $name (try: npx skills remove $name -g)"
    fi
  fi
done
