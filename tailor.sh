#!/bin/bash
# Tailor — provision personal customizations on top of Omarchy.
# Idempotent: safe to re-run.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Pre-flight: bail early if any prerequisite is missing.
"$SCRIPT_DIR/setup-preflight.sh"

# Remove stale Tailor-managed artifacts from previous versions.
"$SCRIPT_DIR/setup-cleanup.sh"

mkdir -p ~/Work/

# Clone repos only if they don't already exist
if [ ! -d ~/Work/omarchy/omarchy-installer ]; then
  gh repo clone basecamp/omarchy ~/Work/omarchy/omarchy-installer
fi
if [ ! -d ~/Work/omarchy/omarchy-iso ]; then
  gh repo clone omacom-io/omarchy-iso ~/Work/omarchy/omarchy-iso
fi
if [ ! -d ~/Work/omarchy/omarchy-pkgs ]; then
  gh repo clone omacom-io/omarchy-pkgs ~/Work/omarchy/omarchy-pkgs
fi
if [ ! -d ~/Work/kanata-homerow-mods ]; then
  gh repo clone ryanrhughes/kanata-homerow-mods ~/Work/kanata-homerow-mods
fi

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
    echo "✓ $label already installed"
  else
    echo "Installing $label with Omarchy..."
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
    echo "✓ $label already installed"
  else
    echo "Installing $label from AUR..."
    omarchy pkg aur add "$@"
  fi
}

# Install optional Omarchy apps only when missing.
ensure_omarchy_install "Dropbox" dropbox_installed dropbox
ensure_omarchy_install "GeForce NOW" geforce_now_installed geforce now
ensure_omarchy_install "Tailscale" tailscale_installed tailscale
ensure_omarchy_command "Voxtype dictation" voxtype_installed voxtype install

# Install optional AUR apps only when missing.
ensure_aur_install "Vesktop" vesktop_installed vesktop

# Ensure Kitty is installed and selected as the Omarchy terminal.
omarchy install terminal kitty

# Mailcatcher (idempotent — skip if container already exists)
if ! docker ps -a --format '{{.Names}}' | grep -q '^mailcatcher$'; then
  docker run -d --name mailcatcher -p 1025:1025 -p 1080:1080 dockage/mailcatcher:0.9.0
fi

# Generate ~/.config/hypr/envs.conf from 1Password (item: tailor-envs)
"$SCRIPT_DIR/setup-envs.sh"

# Generate ~/.ssh/config from 1Password (Server items tagged 'tailor-ssh')
"$SCRIPT_DIR/setup-ssh.sh"

# Set up zsh (omarchy-zsh package + template)
"$SCRIPT_DIR/setup-zsh.sh"

# Configure Pi (settings + extensions)
"$SCRIPT_DIR/setup-pi.sh"

# Install/maintain canonical AI skills allowlist
"$SCRIPT_DIR/setup-ai-skills.sh"

# Install internal CLIs (cortex, nebula, hey, fizzy, basecamp) + bundled skills
"$SCRIPT_DIR/setup-cli-tools.sh"

# Auth: write token configs from 1P + verify OAuth status for each CLI
"$SCRIPT_DIR/setup-cli-auth.sh"

# Codexbar (waybar wrapper for Codex/Claude usage)
"$SCRIPT_DIR/setup-codexbar.sh"

# Copy Hypr config files (excluding ssh, opencode, amp directories - those have their own setup)
mkdir -p ~/.config
find config -type f ! -path "config/ssh/*" ! -path "config/opencode/*" ! -path "config/amp/*" -exec sh -c 'mkdir -p ~/.config/$(dirname ${1#config/}) && cp "$1" ~/.config/${1#config/}' _ {} \;

# Install custom scripts to ~/.local/bin
mkdir -p ~/.local/bin
for script in bin/*; do
  if [ -f "$script" ]; then
    cp "$script" ~/.local/bin/
    chmod +x ~/.local/bin/$(basename "$script")
    echo "✓ Installed $(basename "$script") to ~/.local/bin/"
  fi
done

# Setup AI coding tools (OpenCode skills, MCP servers, etc.)
"$SCRIPT_DIR/setup-ai.sh"

# Add source line to hyprland.conf if it doesn't already exist
if ! grep -q "source = ~/.config/hypr/windows.conf" ~/.config/hypr/hyprland.conf 2>/dev/null; then
  echo "source = ~/.config/hypr/windows.conf" >> ~/.config/hypr/hyprland.conf
fi

# Check monitor resolution and adjust monitors.conf for 4K displays
if pgrep -x Hyprland &> /dev/null; then
  resolution=$(hyprctl monitors -j | jq -r '.[0] | "\(.width)x\(.height)"')
  if [ "$resolution" = "3840x2160" ] && [ -f ~/.config/hypr/monitors.conf ]; then
    sed -i 's/^# monitor=,preferred,auto,1.666667/monitor=,preferred,auto,1.666667/' ~/.config/hypr/monitors.conf
    sed -i 's/^monitor=,preferred,auto,auto/# monitor=,preferred,auto,auto/' ~/.config/hypr/monitors.conf
  fi
fi

# Link home directories to Dropbox
for dir in Pictures Videos Documents; do
  home_dir=~/"$dir"
  dropbox_dir=~/Dropbox/"$dir"

  if [ -d "$dropbox_dir" ]; then
    if [ -e "$home_dir" ] && [ ! -L "$home_dir" ]; then
      echo "Backing up ~/$dir to ~/${dir}.bak"
      mv "$home_dir" "${home_dir}.bak"
      ln -s "$dropbox_dir" "$home_dir"
      echo "✓ Linked ~/$dir to ~/Dropbox/$dir"
    elif [ ! -e "$home_dir" ]; then
      ln -s "$dropbox_dir" "$home_dir"
      echo "✓ Linked ~/$dir to ~/Dropbox/$dir"
    else
      echo "✓ ~/$dir is already a symlink"
    fi
  fi
done
