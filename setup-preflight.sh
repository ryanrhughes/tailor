#!/bin/bash
# Pre-flight checks for tailor.
# Exits non-zero on any critical failure with a clear "fix this then re-run" message.
#
# Two categories of failure:
#   (omarchy) — should be provided by Omarchy. If missing, fix upstream.
#   (user)    — user action required (sign in, install config file, etc).

set -uo pipefail

# Route stderr through stdout for clean, in-order output.
exec 2>&1

errors=0

hdr()  { echo ""; echo "=== $1 ==="; }
ok()   { echo "  ✓ $1"; }
fail() { echo "  ✗ $1"; errors=$((errors+1)); }
hint() { echo "    $1"; }

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

hdr "Omarchy"
check "Omarchy installed" \
  '[ -d "$HOME/.local/share/omarchy" ]' \
  "Install Omarchy first: https://omarchy.org"

hdr "Toolchain (Omarchy provides)"
check "mise installed" \
  'command -v mise' \
  "(omarchy) Should be in Omarchy baseline. Install: sudo pacman -S mise"

check "node available" \
  'command -v node' \
  "(omarchy) Install via mise: mise use -g node@latest"

check "npm available" \
  'command -v npm' \
  "(omarchy) Should be in Omarchy baseline. npm ships with mise's node install"

hdr "Utilities (Omarchy provides)"
for cmd in jq curl gh docker; do
  check "$cmd installed" \
    "command -v $cmd" \
    "(omarchy) sudo pacman -S $cmd"
done

hdr "AI CLIs (Omarchy provides)"
# Omarchy installs these via ~/.local/share/omarchy/install/packaging/npx.sh
# (omarchy-npx-install wrappers) and the omarchy-base.packages list (claude).
# Tailor only verifies they're present — install/upgrade is Omarchy's job.
for cmd in claude codex gemini copilot opencode pi playwright-cli ghui; do
  check "$cmd installed" \
    "command -v $cmd" \
    "(omarchy) Should be installed by omarchy-npx-install or omarchy-base.packages — re-run omarchy install or file upstream"
done

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

# Tailor configs (envs + SSH hosts) come from 1Password directly during the
# main tailor run — envs from a 'tailor-envs' item, SSH hosts from Server
# items tagged 'tailor-ssh'. No local config files needed.

echo ""
if [ "$errors" -gt 0 ]; then
  echo "$errors pre-flight check(s) failed. Fix the above and re-run tailor."
  exit 1
fi

echo "All pre-flight checks passed."
