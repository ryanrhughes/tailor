#!/bin/bash
# Install dotfiles and custom scripts:
#   - config/** → ~/.config/** (excluding dirs owned by their own setup script)
#   - bin/**    → ~/.local/bin/
# Idempotent: copies overwrite in place.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"
source "$SCRIPT_DIR/lib/common.sh"

hdr "Config files"

# Copy ~/.config files, excluding directories that have their own setup script
# (opencode → setup-ai.sh).
mkdir -p ~/.config
find config -type f \
  ! -path "config/opencode/*" \
  -exec sh -c 'mkdir -p ~/.config/$(dirname ${1#config/}) && cp "$1" ~/.config/${1#config/}' _ {} \;
ok "Copied config/ files to ~/.config/"

hdr "Custom scripts"

mkdir -p ~/.local/bin
for script in bin/*; do
  if [ -f "$script" ]; then
    cp "$script" ~/.local/bin/
    chmod +x ~/.local/bin/"$(basename "$script")"
    ok "Installed $(basename "$script") to ~/.local/bin/"
  fi
done
