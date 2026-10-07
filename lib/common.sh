#!/bin/bash
# Shared helpers for tailor setup scripts. Source, don't execute:
#   source "$SCRIPT_DIR/lib/common.sh"

hdr()  { echo ""; echo "=== $1 ==="; }
ok()   { echo "  ✓ $1"; }
info() { echo "  ℹ $1"; }
warn() { echo "  ⚠ $1"; }
fail() { echo "  ✗ $1"; }
hint() { echo "    $1"; }

TAILOR_OP_ACCOUNT="${TAILOR_OP_ACCOUNT:-chamberofsecrets.1password.com}"
TAILOR_OP_TIMEOUT="${TAILOR_OP_TIMEOUT:-20}"
TAILOR_RETRIES="${TAILOR_RETRIES:-3}"

# A human is at the keyboard and gum can prompt them.
is_interactive() {
  [ -t 0 ] && [ -t 1 ] && command -v gum >/dev/null 2>&1
}

# Run a command, retrying with exponential backoff (2s, 4s, ...) on failure.
# For flaky network operations: clones, downloads, package installs.
#   retry [-n attempts] cmd args...
retry() {
  local attempts="$TAILOR_RETRIES" delay=2 n=1
  if [ "${1:-}" = "-n" ]; then
    attempts="$2"
    shift 2
  fi

  until "$@"; do
    if [ "$n" -ge "$attempts" ]; then
      warn "gave up after $attempts attempts: $*"
      return 1
    fi
    warn "attempt $n/$attempts failed: $* — retrying in ${delay}s"
    sleep "$delay"
    n=$((n + 1))
    delay=$((delay * 2))
  done
}

# Run op so it can never block on the terminal: no stdin (so it can't fall into
# its own "add an account? [Y/n]" prompt) and a hard timeout (it waits
# indefinitely on a locked desktop app).
op_run() {
  timeout "$TAILOR_OP_TIMEOUT" op "$@" </dev/null
}

# Silent check: can op read $TAILOR_OP_ACCOUNT right now? With no accounts at
# all, op prompts on /dev/tty ("add an account manually? [Y/n]") even without
# stdin, so bail early on an empty `account list`. Then use `vault list` rather
# than `whoami`: the desktop app integration leaves whoami reporting "not
# signed in" while CLI commands actually succeed.
op_signed_in() {
  command -v op >/dev/null 2>&1 &&
    op_run account list --format json 2>/dev/null | jq -e 'length > 0' >/dev/null 2>&1 &&
    op_run vault list --account "$TAILOR_OP_ACCOUNT" >/dev/null 2>&1
}

# Ensure op can read secrets. Interactive runs loop on a Retry/Skip prompt so
# you can sign in or unlock 1Password and carry on without restarting tailor.
op_ready() {
  until op_signed_in; do
    if ! command -v op >/dev/null 2>&1; then
      warn "1Password CLI (op) not installed"
      hint "Install: https://developer.1password.com/docs/cli/get-started/"
    else
      warn "1Password CLI can't read $TAILOR_OP_ACCOUNT (signed out, locked, or no answer within ${TAILOR_OP_TIMEOUT}s)"
      hint "Unlock the 1Password app with Settings > Developer > 'Integrate with 1Password CLI' enabled"
      hint "No desktop app? Quit tailor, run: op account add && eval \$(op signin), then re-run"
    fi
    is_interactive || return 1
    gum confirm --default=true --affirmative="Retry" --negative="Skip" \
      "Sign in / unlock 1Password, then Retry." || return 1
  done
  ok "1Password CLI authenticated ($TAILOR_OP_ACCOUNT)"
}

# Clone a GitHub repo with `gh` unless it's already there, retrying network
# failures. Clears an empty leftover directory from an interrupted clone, but
# refuses to touch a non-empty directory that isn't a git checkout.
#   gh_clone owner/repo target_dir
gh_clone() {
  local repo="$1" target="$2"

  if [ -d "$target/.git" ]; then
    return 0
  fi
  if [ -d "$target" ]; then
    if [ -n "$(ls -A "$target")" ]; then
      warn "$target exists but is not a git checkout — move it aside and re-run"
      return 1
    fi
    rmdir "$target"
  fi

  info "Cloning $repo to $target..."
  mkdir -p "$(dirname "$target")"
  retry gh repo clone "$repo" "$target"
}

# Download a URL to a file, retrying transient failures. Download fully before
# running install scripts so a dropped connection can't run half a script.
#   fetch url dest
fetch() {
  curl -fsSL --retry "$TAILOR_RETRIES" --retry-all-errors --connect-timeout 15 -o "$2" "$1"
}
