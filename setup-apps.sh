#!/bin/bash
# Install optional desktop apps (Omarchy + AUR) and the mailcatcher container.
# Idempotent: each install is guarded by a "already installed" check.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

package_installed() {
  pacman -Q "$1" >/dev/null 2>&1
}

dropbox_installed() {
  command -v dropbox >/dev/null 2>&1 || package_installed dropbox
}

tailscale_installed() {
  command -v tailscale >/dev/null 2>&1 &&
    tailscale status --json 2>/dev/null | jq -e '.BackendState == "Running"' >/dev/null
}

voxtype_installed() {
  command -v voxtype >/dev/null 2>&1 &&
    [ -f "$HOME/.config/voxtype/config.toml" ] &&
    systemctl --user is-enabled --quiet voxtype.service 2>/dev/null &&
    find "$HOME/.local/share/voxtype/models" -type f -print -quit 2>/dev/null | grep -q .
}

vesktop_installed() {
  command -v vesktop >/dev/null 2>&1 || package_installed vesktop || package_installed vesktop-bin
}

geforce_now_desktop_installed() {
  local dir

  for dir in "$HOME/.local/share/applications" /usr/share/applications; do
    [ -d "$dir" ] || continue
    find "$dir" -maxdepth 1 -iname '*geforce*now*.desktop' -print -quit | grep -q . && return 0
  done

  return 1
}

geforce_now_installed() {
  command -v geforcenow >/dev/null 2>&1 ||
    command -v geforce-now >/dev/null 2>&1 ||
    geforce_now_desktop_installed ||
    { command -v flatpak >/dev/null 2>&1 && flatpak list --app --columns=application,name 2>/dev/null | grep -qi 'geforce.*now'; }
}

ensure_omarchy_command() {
  local label="$1" check_function="$2"
  shift 2

  if "$check_function"; then
    ok "$label already installed"
  else
    info "Installing $label with Omarchy..."
    omarchy "$@"
  fi
}

ensure_omarchy_install() {
  local label="$1" check_function="$2"
  shift 2

  ensure_omarchy_command "$label" "$check_function" install "$@"
}

ensure_aur_install() {
  local label="$1" check_function="$2"
  shift 2

  if "$check_function"; then
    ok "$label already installed"
  else
    info "Installing $label from AUR..."
    omarchy pkg aur add "$@"
  fi
}

hdr "Omarchy apps"
ensure_omarchy_install "Dropbox" dropbox_installed dropbox
ensure_omarchy_install "GeForce NOW" geforce_now_installed geforce now
ensure_omarchy_install "Tailscale" tailscale_installed tailscale
ensure_omarchy_command "Voxtype dictation" voxtype_installed voxtype install

hdr "AUR apps"
ensure_aur_install "Vesktop" vesktop_installed vesktop

hdr "Terminal"
# Ensure Kitty is installed and selected as the Omarchy terminal.
omarchy install terminal kitty

hdr "Mailcatcher"
if docker ps -a --format '{{.Names}}' | grep -q '^mailcatcher$'; then
  ok "mailcatcher container already exists"
else
  info "Starting mailcatcher container..."
  docker run -d --name mailcatcher -p 1025:1025 -p 1080:1080 dockage/mailcatcher:0.9.0
  ok "mailcatcher running (smtp :1025, web :1080)"
fi
