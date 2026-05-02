#!/bin/bash
# Install internal/related CLI tools and their bundled agent skills.
# Idempotent: safe to re-run.
#
# Tools and install methods:
#   cortex   — git clone ThinkOodle/cortex-cli + make link  (private repo)
#   nebula   — git clone ThinkOodle/nebula-cli + make link  (private repo)
#   hey      — git clone basecamp/hey-cli + make build      (no release binaries yet)
#   fizzy    — yay AUR fizzy-cli, or basecamp install.sh fallback
#   basecamp — yay -S basecamp-cli  (AUR)
#
# Each CLI ships a skill via `<cli> skill install` — we run it post-install.
# Skill targets: ~/.agents/skills (canonical) + ~/.claude/skills (symlink).
#
# Auth is NOT handled here — set tokens manually for now; we'll add a
# setup-cli-auth.sh that pulls from 1Password later.

set -euo pipefail

hdr()  { echo ""; echo "=== $1 ==="; }
ok()   { echo "  ✓ $1"; }
info() { echo "  ℹ $1"; }
warn() { echo "  ⚠ $1"; }
hint() { echo "    $1"; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/manual-action.sh
source "$SCRIPT_DIR/lib/manual-action.sh"

WORK_DIR="$HOME/Work"
BIN_DIR="$HOME/.local/bin"
SKILLS_DIR="$HOME/.agents/skills"
CLAUDE_SKILLS_DIR="$HOME/.claude/skills"
mkdir -p "$WORK_DIR" "$BIN_DIR" "$SKILLS_DIR" "$CLAUDE_SKILLS_DIR"

# Run "<cli> skill install" with the canonical target + symlink. Best-effort.
install_skill_for() {
  local cli="$1"
  if "$cli" skill install --target "$SKILLS_DIR" --symlink-to "$CLAUDE_SKILLS_DIR" >/dev/null 2>&1; then
    ok "$cli skill installed"
  elif "$cli" skill install >/dev/null 2>&1; then
    ok "$cli skill installed (default args)"
  else
    warn "$cli skill install failed or interactive-only — run '$cli skill install' manually"
  fi
}

# Build-and-link a Go private repo to ~/.local/bin/<cli> via the repo's Makefile.
make_link_repo() {
  local cli="$1"
  local repo="$2"
  local cli_dir="$WORK_DIR/$repo"

  if command -v "$cli" >/dev/null 2>&1; then
    ok "$cli installed: $($cli version 2>&1 | head -1)"
    return 0
  fi

  if [ ! -d "$cli_dir" ]; then
    info "Cloning ThinkOodle/$repo to $cli_dir..."
    gh repo clone "ThinkOodle/$repo" "$cli_dir"
  fi

  info "Building $cli (make link)..."
  make -C "$cli_dir" link >/dev/null
  ok "$cli installed: $($cli version 2>&1 | head -1)"
}

# --- cortex --------------------------------------------------------------
hdr "cortex"
make_link_repo cortex cortex-cli
install_skill_for cortex

# --- nebula --------------------------------------------------------------
hdr "nebula"
make_link_repo nebula nebula-cli
install_skill_for nebula

# --- hey -----------------------------------------------------------------
# basecamp/hey-cli has no release binaries yet. Build from source.
hdr "hey"
HEY_DIR="$WORK_DIR/hey-cli"
if command -v hey >/dev/null 2>&1; then
  ok "hey installed: $(hey --version 2>&1 | head -1)"
else
  if [ ! -d "$HEY_DIR" ]; then
    info "Cloning basecamp/hey-cli to $HEY_DIR..."
    gh repo clone basecamp/hey-cli "$HEY_DIR"
  fi
  # mise.toml in the repo needs trusting before make can use the toolchain
  if [ -f "$HEY_DIR/.mise.toml" ]; then
    mise trust "$HEY_DIR/.mise.toml" >/dev/null 2>&1 || true
  fi
  info "Building hey (make build)..."
  make -C "$HEY_DIR" build >/dev/null
  ln -sf "$HEY_DIR/bin/hey" "$BIN_DIR/hey"
  ok "hey installed: $(hey --version 2>&1 | head -1)"
fi
install_skill_for hey

# --- fizzy ---------------------------------------------------------------
# Prefer AUR fizzy-cli when present. Otherwise install via basecamp's
# install.sh (latest tagged release into ~/.local/bin/).
hdr "fizzy"
FIZZY_BIN="$BIN_DIR/fizzy"

if pacman -Q fizzy-cli >/dev/null 2>&1; then
  ok "fizzy-cli installed (AUR): $(pacman -Q fizzy-cli | awk '{print $2}')"
else
  latest_fizzy=$(curl -sI https://github.com/basecamp/fizzy-cli/releases/latest 2>/dev/null \
    | awk -F/ '/^location:/ {sub(/[\r\n]+$/, "", $NF); print $NF}')
  if [ -x "$FIZZY_BIN" ] && [ "$("$FIZZY_BIN" --version 2>&1 | awk '{print $NF}')" = "$latest_fizzy" ]; then
    ok "fizzy installed: $("$FIZZY_BIN" --version 2>&1 | head -1) (latest)"
  else
    info "Installing fizzy via basecamp install.sh ($latest_fizzy)..."
    curl -fsSL https://raw.githubusercontent.com/basecamp/fizzy-cli/master/scripts/install.sh \
      | FIZZY_BIN_DIR="$BIN_DIR" bash >/dev/null
    ok "fizzy installed: $("$FIZZY_BIN" --version 2>&1 | head -1)"
  fi
fi

# `fizzy skill` is interactive-only (no flags to skip prompts).
hdr "fizzy skill"
prompt_manual_action \
  "fizzy skill not installed" \
  "[ -f \"$SKILLS_DIR/fizzy/SKILL.md\" ]" \
  "Run in another terminal: fizzy skill"

# --- basecamp ------------------------------------------------------------
hdr "basecamp"
if pacman -Q basecamp-cli >/dev/null 2>&1; then
  ok "basecamp-cli installed (AUR): $(pacman -Q basecamp-cli | awk '{print $2}')"
elif command -v basecamp >/dev/null 2>&1; then
  ok "basecamp installed (non-AUR — consider migrating to AUR via 'yay -S basecamp-cli')"
else
  info "Installing basecamp-cli via yay..."
  yay -S --needed --noconfirm basecamp-cli
  ok "basecamp-cli installed"
fi
install_skill_for basecamp


