#!/bin/bash
# Set up zsh via Omarchy's tooling (omarchy-zsh package + omarchy-setup-zsh).
# Idempotent: skips package install if present, skips setup if templates are
# already applied (detected by signature lines in ~/.zshrc and ~/.bashrc).
#
# Note: omarchy-zsh doesn't change the user's default login shell — the bashrc
# template just exec's zsh when an interactive bash session starts. SHELL=bash
# is normal and expected even after setup.

set -euo pipefail

hdr()  { echo ""; echo "=== $1 ==="; }
ok()   { echo "  ✓ $1"; }
info() { echo "  ℹ $1"; }
warn() { echo "  ⚠ $1"; }

hdr "zsh (via Omarchy)"

if pacman -Q omarchy-zsh >/dev/null 2>&1; then
  ok "omarchy-zsh installed: $(pacman -Q omarchy-zsh | awk '{print $2}')"
else
  info "Installing omarchy-zsh..."
  omarchy-pkg-add omarchy-zsh
  ok "omarchy-zsh installed"
fi

# Detect "already set up" by template signature lines, not full diff
# (full diff would mis-trigger if the user appended their own customizations).
zshrc_marker='/usr/share/omarchy-zsh/shell/zoptions'
bashrc_marker='exec zsh $LOGIN_OPTION'

if grep -qF "$zshrc_marker" "$HOME/.zshrc" 2>/dev/null && \
   grep -qF "$bashrc_marker" "$HOME/.bashrc" 2>/dev/null; then
  ok "zsh setup already applied (.zshrc and .bashrc carry omarchy template signatures)"
else
  info "Running omarchy-setup-zsh (will back up existing .zshrc/.bashrc)..."
  omarchy-setup-zsh
  ok "zsh setup complete"
fi
