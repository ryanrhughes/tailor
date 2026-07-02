#!/bin/bash
# Pre-flight checks for tailor.
# Exits non-zero on any critical failure with a clear "fix this then re-run" message.
#
# Checks only the basics tailor itself relies on: pacman/gum, the mise
# toolchain, common utilities, and 1Password auth. Everything else is
# installed or repaired by the individual setup steps.

set -uo pipefail

# Route stderr through stdout for clean, in-order output.
exec 2>&1

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

errors=0

# Override common.sh's fail to also count failures for the final verdict.
fail() { echo "  ✗ $1"; errors=$((errors+1)); }

check() {
  # check "label" "test cmd" "hint on failure"
  local label="$1" test_cmd="$2" h="${3:-}"
  if eval "$test_cmd" >/dev/null 2>&1; then
    ok "$label"
  else
    fail "$label"
    [ -n "$h" ] && hint "$h"
  fi
}

hdr "Basics"
check "pacman installed" \
  'command -v pacman' \
  "tailor targets Arch — no pacman means this isn't going to work"

check "gum installed" \
  'command -v gum' \
  "sudo pacman -S gum"

for cmd in jq curl gh docker; do
  check "$cmd installed" \
    "command -v $cmd" \
    "sudo pacman -S $cmd"
done

hdr "Toolchain"
check "mise installed" \
  'command -v mise' \
  "sudo pacman -S mise"

check "node available" \
  'command -v node' \
  "Install via mise: mise use -g node@latest"

check "npm available" \
  'command -v npm' \
  "npm ships with mise's node install: mise use -g node@latest"

# AI CLIs (claude, codex, pi, opencode, gemini, copilot, playwright, ghui)
# are installed/repaired by tailor via `mise use -g` in setup-ai.sh — not
# pre-flight requirements.

hdr "Secrets (1Password)"
check "op CLI installed" \
  'command -v op' \
  "Install 1Password CLI: https://developer.1password.com/docs/cli/get-started/"

# Use `op vault list` rather than `op whoami` because the desktop app integration
# (Settings > Developer > Integrate with 1Password CLI) leaves whoami reporting
# "not signed in" while CLI commands actually succeed via biometric auth.
check "op CLI authenticated (can list vaults)" \
  'op vault list' \
  "Enable 1Password app: Settings > Developer > 'Integrate with 1Password CLI', OR: op account add && eval \$(op signin)"

# Tailor configs come from 1Password directly during the main tailor run:
# envs from a 'tailor-envs' item, the GitHub SSH key from the 'Github SSH Key'
# SSH Key item, and SSH hosts from Server items tagged 'tailor-ssh'. No local
# config files needed.

echo ""
if [ "$errors" -gt 0 ]; then
  echo "$errors pre-flight check(s) failed. Fix the above and re-run tailor."
  exit 1
fi

echo "All pre-flight checks passed."
