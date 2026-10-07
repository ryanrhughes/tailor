#!/bin/bash
# Install optional desktop apps (Omarchy + AUR), Brave Origin as the default
# browser with the 1Password extension, and the mailcatcher container.
# Idempotent: each install is guarded by a "already installed" check. A failed
# install is recorded and the rest still run; the step fails at the end.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

failed=()

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

t3code_installed() {
  package_installed t3code-bin
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
    omarchy "$@" || { fail "$label install failed"; failed+=("$label"); }
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
    retry omarchy pkg aur add "$@" || { fail "$label install failed"; failed+=("$label"); }
  fi
}

hdr "Omarchy apps"
ensure_omarchy_install "Dropbox" dropbox_installed service dropbox
ensure_omarchy_install "GeForce NOW" geforce_now_installed gaming geforce-now
ensure_omarchy_install "Tailscale" tailscale_installed service tailscale
ensure_omarchy_command "Voxtype dictation" voxtype_installed voxtype install
# Omarchy's installer also themes T3 Code and opens it for T3 Connect sign-in.
ensure_omarchy_install "T3 Code" t3code_installed ai t3 code

hdr "AUR apps"
ensure_aur_install "Vesktop" vesktop_installed vesktop

hdr "Browser"
# Brave Origin via Omarchy, which also sets up its managed-policy directory,
# flags, and theme color. Then make it the default for Omarchy and XDG handlers.
if package_installed brave-origin-bin; then
  ok "Brave Origin already installed"
else
  info "Installing Brave Origin with Omarchy..."
  omarchy install browser brave-origin || { fail "Brave Origin install failed"; failed+=("brave-origin"); }
fi

if [ "$(omarchy default browser 2>/dev/null)" = "brave-origin" ]; then
  ok "Brave Origin is the default browser"
elif package_installed brave-origin-bin; then
  omarchy default browser brave-origin >/dev/null &&
    ok "Brave Origin set as the default browser" ||
    { fail "Could not set Brave Origin as the default browser"; failed+=("default-browser"); }
fi

# Install the 1Password extension in every Chromium-family browser Omarchy has
# set up, through managed policy: installed for every profile, user can't
# remove it, and Omarchy's own policy files (color.json) are left untouched.
ONEPASSWORD_EXTENSION_ID=aeblfdkhhhdcdjpifhhbdiojplfjncoa
onepassword_extension_policy() {
  printf '{"ExtensionSettings": {"%s": {"installation_mode": "normal_installed", "update_url": "https://clients2.google.com/service/update2/crx"}}}\n' \
    "$ONEPASSWORD_EXTENSION_ID"
}

ensure_onepassword_extension() {
  local dir="$1" target="$1/tailor-1password.json" staged
  staged=$(mktemp)
  onepassword_extension_policy > "$staged"

  if cmp -s "$staged" "$target"; then
    ok "1Password extension policy already in $dir"
  elif sudo install -m 0644 -o root -g root "$staged" "$target"; then
    ok "1Password extension policy installed in $dir (restart the browser to load it)"
  else
    fail "Could not write $target"
    failed+=("1password-extension")
  fi
  rm -f "$staged"
}

found_policy_dir=false
for dir in /etc/brave/policies/managed /etc/chromium/policies/managed \
    /etc/opt/chrome/policies/managed /etc/opt/edge/policies/managed; do
  [ -d "$dir" ] || continue
  found_policy_dir=true
  ensure_onepassword_extension "$dir"
done
[ "$found_policy_dir" = true ] || warn "No Chromium-family policy directory found — 1Password extension not configured"

hdr "Mailcatcher"
MAILCATCHER_IMAGE=dockage/mailcatcher:0.9.0
if ! docker info >/dev/null 2>&1; then
  fail "docker daemon not reachable — can't set up mailcatcher"
  hint "Start it: sudo systemctl enable --now docker"
  failed+=("mailcatcher")
elif docker ps -a --format '{{.Names}}' | grep -q '^mailcatcher$'; then
  ok "mailcatcher container already exists"
elif retry docker pull -q "$MAILCATCHER_IMAGE" >/dev/null &&
    docker run -d --name mailcatcher -p 1025:1025 -p 1080:1080 "$MAILCATCHER_IMAGE" >/dev/null; then
  ok "mailcatcher running (smtp :1025, web :1080)"
else
  fail "mailcatcher container failed to start"
  failed+=("mailcatcher")
fi

if [ "${#failed[@]}" -gt 0 ]; then
  echo ""
  fail "failed: ${failed[*]}"
  exit 1
fi
