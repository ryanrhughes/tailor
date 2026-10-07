#!/bin/bash
# Pre-flight checks for tailor.
# Exits 1 on any critical failure with a clear "fix this then re-run" message.
# Exits 3 when everything passed except 1Password: tailor.sh then runs the
# remaining steps and skips the ones that need secrets.
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

# AI CLIs (claude, codex, opencode, ...) come from Omarchy, not tailor.

hdr "Secrets (1Password)"
# Never fatal: interactive runs get a Retry/Skip prompt, and skipping just
# means the 1Password-backed steps are skipped this run.
op_ok=true
op_ready || op_ok=false

# Tailor configs come from 1Password directly during the main tailor run:
# envs from a 'tailor-envs' item, the GitHub SSH key from the 'Github SSH Key'
# SSH Key item, and SSH hosts from Server items tagged 'tailor-ssh'. No local
# config files needed.

echo ""
if [ "$errors" -gt 0 ]; then
  echo "$errors pre-flight check(s) failed. Fix the above and re-run tailor."
  exit 1
fi

if [ "$op_ok" = false ]; then
  echo "Pre-flight passed, but 1Password is unavailable."
  exit 3
fi

echo "All pre-flight checks passed."
