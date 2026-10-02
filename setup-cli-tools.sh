#!/bin/bash
# Install internal/related CLI tools.
# Idempotent: safe to re-run.
#
# Tools and install methods:
#   cortex   — git clone ThinkOodle/cortex-cli + make link  (private repo)
#   nebula   — git clone ThinkOodle/nebula-cli + make link  (private repo)
#   hey      — git clone basecamp/hey-cli + make build      (no release binaries yet)
#   fizzy    — yay AUR fizzy-cli, or basecamp install.sh fallback
#   basecamp — yay -S basecamp-cli  (AUR)
#
# Their agent skills are installed and kept current by the ai-skills step
# (ryanrhughes/agent-skills external.txt), which runs after this one.
#
# Auth is NOT handled here — set tokens manually for now; we'll add a
# setup-cli-auth.sh that pulls from 1Password later.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

WORK_DIR="$HOME/Work"
BIN_DIR="$HOME/.local/bin"
mkdir -p "$WORK_DIR" "$BIN_DIR"

# Ensure Go is available for building cortex/nebula. Installed globally via
# mise since neither repo ships a .mise.toml.
ensure_go() {
  if command -v go >/dev/null 2>&1; then
    return 0
  fi
  info "Installing go via mise (global)..."
  mise use -g go@latest >/dev/null
  hash -r
  command -v go >/dev/null 2>&1 || {
    warn "go still not on PATH after 'mise use -g go@latest' — open a new shell and re-run"
    return 1
  }
  ok "go installed: $(go version)"
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

# --- go (needed by cortex + nebula) -------------------------------------
hdr "go"
ensure_go

# --- cortex --------------------------------------------------------------
hdr "cortex"
make_link_repo cortex cortex-cli

# --- nebula --------------------------------------------------------------
hdr "nebula"
make_link_repo nebula nebula-cli

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
