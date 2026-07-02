#!/bin/bash
# Link ~/Pictures, ~/Videos, ~/Documents to their Dropbox counterparts.
# Idempotent: skips dirs that are already symlinks; backs up real dirs first.
# Requires ~/Dropbox to be a signed-in sync root (see setup-apps.sh /
# setup-cli-auth.sh's Dropbox check).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

hdr "Dropbox home links"

if [ ! -d ~/Dropbox ]; then
  warn "~/Dropbox does not exist — sign in to Dropbox and let it sync first"
  exit 0
fi

for dir in Pictures Videos Documents; do
  home_dir=~/"$dir"
  dropbox_dir=~/Dropbox/"$dir"

  if [ ! -d "$dropbox_dir" ]; then
    warn "~/Dropbox/$dir not found — skipped ~/$dir"
    continue
  fi

  if [ -L "$home_dir" ]; then
    ok "~/$dir is already a symlink"
  elif [ -e "$home_dir" ]; then
    info "Backing up ~/$dir to ~/${dir}.bak"
    mv "$home_dir" "${home_dir}.bak"
    ln -s "$dropbox_dir" "$home_dir"
    ok "Linked ~/$dir to ~/Dropbox/$dir"
  else
    ln -s "$dropbox_dir" "$home_dir"
    ok "Linked ~/$dir to ~/Dropbox/$dir"
  fi
done
