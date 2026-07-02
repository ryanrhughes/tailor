#!/bin/bash
# Clone Omarchy + personal repos into ~/Work.
# Idempotent: clones only if the target directory doesn't exist.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

hdr "Work repos"

mkdir -p ~/Work/

ensure_repo() {
  local repo="$1" target="$2"

  if [ -d "$target" ]; then
    ok "$repo already cloned ($target)"
  else
    info "Cloning $repo to $target..."
    gh repo clone "$repo" "$target"
    ok "$repo cloned"
  fi
}

ensure_repo basecamp/omarchy ~/Work/omarchy/omarchy-installer
ensure_repo omacom-io/omarchy-iso ~/Work/omarchy/omarchy-iso
ensure_repo omacom-io/omarchy-pkgs ~/Work/omarchy/omarchy-pkgs
ensure_repo ryanrhughes/kanata-homerow-mods ~/Work/kanata-homerow-mods
