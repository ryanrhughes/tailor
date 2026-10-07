#!/bin/bash
# Clone project repos into ~/Work. Optional: not part of a default tailor run
# (./tailor.sh full, or pick it).
# Idempotent: clones only if the target isn't already a checkout. One failed
# clone doesn't stop the others.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

hdr "Projects"

mkdir -p ~/Work/

failed=()

ensure_repo() {
  local repo="$1" target="$2"

  if [ -d "$target/.git" ]; then
    ok "$repo already cloned ($target)"
  elif gh_clone "$repo" "$target"; then
    ok "$repo cloned"
  else
    fail "could not clone $repo"
    failed+=("$repo")
  fi
}

ensure_repo basecamp/omarchy ~/Work/omarchy/omarchy-installer
ensure_repo omacom-io/omarchy-iso ~/Work/omarchy/omarchy-iso
ensure_repo omacom-io/omarchy-pkgs ~/Work/omarchy/omarchy-pkgs

[ "${#failed[@]}" -eq 0 ]
