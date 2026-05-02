#!/bin/bash
# Set up codexbar-waybar (the chosen Codexbar wrapper).
#
# codexbar-waybar is built from a personal AUR-style PKGBUILD repo
# (github.com/ryanrhughes/codexbar-waybar) and installed via pacman.
# codexbar-tui is the rejected sibling — warn for removal if found.
#
# Idempotent: skips install if already at the repo's version.

set -euo pipefail

hdr()  { echo ""; echo "=== $1 ==="; }
ok()   { echo "  ✓ $1"; }
info() { echo "  ℹ $1"; }
warn() { echo "  ⚠ $1"; }
hint() { echo "    $1"; }

REPO_DIR="$HOME/Work/codexbar-waybar"

hdr "codexbar-waybar"

if pacman -Q codexbar-waybar >/dev/null 2>&1; then
  ok "codexbar-waybar installed: $(pacman -Q codexbar-waybar | awk '{print $2}')"
else
  if [ ! -d "$REPO_DIR" ]; then
    info "Cloning ryanrhughes/codexbar-waybar to $REPO_DIR..."
    gh repo clone ryanrhughes/codexbar-waybar "$REPO_DIR"
  fi
  info "Building + installing codexbar-waybar via makepkg (will prompt for sudo)..."
  ( cd "$REPO_DIR" && makepkg -si --noconfirm )
  ok "codexbar-waybar installed: $(pacman -Q codexbar-waybar | awk '{print $2}')"
fi

if pacman -Q codexbar-tui >/dev/null 2>&1; then
  warn "codexbar-tui is installed — codexbar-waybar is the chosen wrapper"
  hint "Remove: sudo pacman -Rns codexbar-tui"
fi
