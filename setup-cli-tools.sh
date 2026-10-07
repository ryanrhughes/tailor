#!/bin/bash
# Install internal/related CLI tools.
# Idempotent: safe to re-run.
#
# Tools and install methods:
#   cortex   — git clone ThinkOodle/cortex-cli + make link  (private repo)
#   nebula   — git clone ThinkOodle/nebula-cli + make link  (private repo)
#   fizzy    — yay AUR fizzy-cli, or basecamp install.sh fallback
#
# hey and basecamp come from Omarchy (mise), not tailor.
#
# Their agent skills are installed and kept current by the ai-skills step
# (ryanrhughes/agent-skills external.txt), which runs after this one.
#
# Auth is handled by setup-cli-auth.sh.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

WORK_DIR="$HOME/Work"
BIN_DIR="$HOME/.local/bin"
mkdir -p "$WORK_DIR" "$BIN_DIR"

# Each tool installs independently: a failure is recorded and the rest still
# run, so one broken repo doesn't block the others. Exits non-zero if any failed.
failed=()

# Ensure Go is available for building cortex/nebula. Installed globally via
# mise since neither repo ships a .mise.toml.
ensure_go() {
  if command -v go >/dev/null 2>&1; then
    ok "go installed: $(go version)"
    return 0
  fi
  info "Installing go via mise (global)..."
  retry mise use -g go@latest >/dev/null || return 1
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

  command -v go >/dev/null 2>&1 || { warn "go unavailable — can't build $cli"; return 1; }
  gh_clone "ThinkOodle/$repo" "$cli_dir" || return 1

  info "Building $cli (make link)..."
  make -C "$cli_dir" link >/dev/null || return 1
  ok "$cli installed: $($cli version 2>&1 | head -1)"
}

# Prefer AUR fizzy-cli when present. Otherwise install via basecamp's
# install.sh (latest tagged release into ~/.local/bin/).
install_fizzy() {
  local fizzy_bin="$BIN_DIR/fizzy" latest installer

  if pacman -Q fizzy-cli >/dev/null 2>&1; then
    ok "fizzy-cli installed (AUR): $(pacman -Q fizzy-cli | awk '{print $2}')"
    return 0
  fi

  latest=$(curl -sI --retry "$TAILOR_RETRIES" --connect-timeout 15 \
    https://github.com/basecamp/fizzy-cli/releases/latest 2>/dev/null \
    | awk -F/ '/^location:/ {sub(/[\r\n]+$/, "", $NF); print $NF}')

  if [ -x "$fizzy_bin" ]; then
    if [ -z "$latest" ]; then
      # Offline or GitHub unreachable: keep what's there rather than reinstall.
      ok "fizzy installed: $("$fizzy_bin" --version 2>&1 | head -1) (couldn't check for updates)"
      return 0
    fi
    if [ "$("$fizzy_bin" --version 2>&1 | awk '{print $NF}')" = "$latest" ]; then
      ok "fizzy installed: $("$fizzy_bin" --version 2>&1 | head -1) (latest)"
      return 0
    fi
  fi

  info "Installing fizzy via basecamp install.sh (${latest:-latest})..."
  installer=$(mktemp)
  fetch https://raw.githubusercontent.com/basecamp/fizzy-cli/master/scripts/install.sh "$installer" &&
    FIZZY_BIN_DIR="$BIN_DIR" bash "$installer" >/dev/null
  local rc=$?
  rm -f "$installer"
  [ "$rc" -eq 0 ] || return 1
  ok "fizzy installed: $("$fizzy_bin" --version 2>&1 | head -1)"
}

hdr "go"
ensure_go || failed+=("go")

hdr "cortex"
make_link_repo cortex cortex-cli || failed+=("cortex")

hdr "nebula"
make_link_repo nebula nebula-cli || failed+=("nebula")

hdr "fizzy"
install_fizzy || failed+=("fizzy")

if [ "${#failed[@]}" -gt 0 ]; then
  echo ""
  fail "failed: ${failed[*]}"
  exit 1
fi
