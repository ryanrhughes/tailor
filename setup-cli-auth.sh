#!/bin/bash
# Authenticate AI and internal CLIs.
# Idempotent: re-running is safe and refreshes token-based configs from 1Password.
#
# Two flavors:
#
#   1. Token-based — tailor pulls API tokens from 1Password and writes the CLI's
#      config file. Run on every tailor invocation; 1P is source of truth.
#      CLIs: cortex, nebula, fizzy.
#
#   2. OAuth-based — interactive login flows. Tailor verifies auth by exercising
#      the API (active check, not just file existence) and prints the login
#      command if not authed.
#      CLIs: claude, codex, pi, hey, basecamp.
#
#   3. Dropbox — not a CLI, but tailor's symlink step in tailor.sh depends on
#      ~/Dropbox being a signed-in sync root. Same recheck/skip flow.
#
# After all checks: if anything failed, summarize and prompt (via gum) to either
# re-run the checks (after fixing) or continue anyway. Tailor never blocks on
# auth — worst case, you get warnings and the rest of the run proceeds.
#
# 1Password items expected in $TAILOR_OP_ACCOUNT (default: chamberofsecrets):
#   Cortex API   fields: token, tenant_id, api_url
#   Nebula API   fields: token, workspace, workspace_url, domain, scheme, api_url
#   Fizzy API    fields: token, account, api_url

set -uo pipefail

TAILOR_OP_ACCOUNT="${TAILOR_OP_ACCOUNT:-chamberofsecrets.1password.com}"

hdr()  { echo ""; echo "=== $1 ==="; }
ok()   { echo "  ✓ $1"; }
info() { echo "  ℹ $1"; }
warn() { echo "  ⚠ $1"; }
hint() { echo "    $1"; }

field_value() {
  local json="$1" label="$2"
  echo "$json" | jq -r --arg L "$label" '
    [.fields[] | select(.label | ascii_downcase == ($L | ascii_downcase)) | .value]
    | map(select(. != null and . != ""))
    | first // empty
  '
}

fetch_item() {
  op item get "$1" --account "$TAILOR_OP_ACCOUNT" --format json 2>/dev/null || true
}

bootstrap_hint() {
  local title="$1" fields_desc="$2"
  warn "1Password item '$title' not found in $TAILOR_OP_ACCOUNT"
  hint "Create it manually with fields: $fields_desc"
  hint "Example (replace placeholders):"
  hint "  op item create --category 'API Credential' --title '$title' \\"
  hint "    --vault Private --account $TAILOR_OP_ACCOUNT \\"
  hint "    'token[concealed]=<your-token>' '<other fields...>'"
}

# --- token-based: cortex, nebula, fizzy --------------------------------
# Each returns 0 on success, 1 if config could not be written.

write_cortex_config() {
  hdr "cortex auth"
  local item; item=$(fetch_item "Cortex API")
  if [ -z "$item" ]; then
    bootstrap_hint "Cortex API" \
      "token (concealed), tenant_id, api_url (e.g. https://my.cortexhq.app)"
    return 1
  fi

  local token tenant api_url
  token=$(field_value "$item" "token")
  tenant=$(field_value "$item" "tenant_id")
  api_url=$(field_value "$item" "api_url")
  : "${api_url:=https://my.cortexhq.app}"

  if [ -z "$token" ] || [ -z "$tenant" ]; then
    warn "Cortex API missing required fields (token, tenant_id)"
    return 1
  fi

  mkdir -p ~/.config/cortex
  umask 077
  cat > ~/.config/cortex/config.yaml <<EOF
api_url: $api_url
tenant_id: $tenant
token: $token
EOF
  ok "wrote ~/.config/cortex/config.yaml from Cortex API"
}

write_nebula_config() {
  hdr "nebula auth"
  local item; item=$(fetch_item "Nebula API")
  if [ -z "$item" ]; then
    bootstrap_hint "Nebula API" \
      "token (concealed), workspace, workspace_url, domain, scheme, api_url (any of the location fields, optional)"
    return 1
  fi

  local token workspace workspace_url domain scheme api_url
  token=$(field_value "$item" "token")
  workspace=$(field_value "$item" "workspace")
  workspace_url=$(field_value "$item" "workspace_url")
  domain=$(field_value "$item" "domain")
  scheme=$(field_value "$item" "scheme")
  api_url=$(field_value "$item" "api_url")

  if [ -z "$token" ]; then
    warn "Nebula API missing required field: token"
    return 1
  fi

  mkdir -p ~/.config/nebula
  umask 077
  {
    [ -n "$workspace_url" ] && echo "workspace_url: \"$workspace_url\""
    [ -n "$workspace" ]     && echo "workspace: \"$workspace\""
    [ -n "$domain" ]        && echo "domain: $domain"
    [ -n "$scheme" ]        && echo "scheme: $scheme"
    [ -n "$api_url" ]       && echo "api_url: \"$api_url\""
    echo "token: $token"
  } > ~/.config/nebula/config.yaml
  ok "wrote ~/.config/nebula/config.yaml from Nebula API"
}

write_fizzy_config() {
  hdr "fizzy auth"
  local item; item=$(fetch_item "Fizzy API")
  if [ -z "$item" ]; then
    bootstrap_hint "Fizzy API" \
      "token (concealed), account, api_url"
    return 1
  fi

  local token account api_url
  token=$(field_value "$item" "token")
  account=$(field_value "$item" "account")
  api_url=$(field_value "$item" "api_url")
  : "${api_url:=https://app.fizzy.do}"

  if [ -z "$token" ] || [ -z "$account" ]; then
    warn "Fizzy API missing required fields (token, account)"
    return 1
  fi

  mkdir -p ~/.config/fizzy
  umask 077
  cat > ~/.config/fizzy/config.yaml <<EOF
token: $token
account: "$account"
api_url: $api_url
board: ""
EOF
  ok "wrote ~/.config/fizzy/config.yaml from Fizzy API"
}

# --- OAuth-based: ACTIVE verification ----------------------------------
# Each returns 0 on success, 1 on failure.

verify_claude() {
  hdr "claude auth"
  if timeout 30 claude --print "reply with only the word OK" </dev/null >/dev/null 2>&1; then
    ok "claude authenticated and reachable"
  else
    warn "claude not authenticated (or API unreachable)"
    hint "Run: claude  (then /login inside the session)"
    return 1
  fi
}

verify_codex() {
  hdr "codex auth"
  if codex login status 2>&1 | grep -q "Logged in"; then
    ok "codex authenticated"
  else
    warn "codex not authenticated"
    hint "Run: codex login"
    return 1
  fi
}

verify_pi() {
  hdr "pi auth"
  # pi --print does not exit cleanly even after producing output (it hangs on
  # TUI cleanup), so `pi --print | check exit code` always hits the timeout and
  # reports a false negative. Instead we run pi in JSON mode and consider auth
  # verified the moment the provider emits an assistant message_start event.
  # `head -c` closes the pipe, killing pi via SIGPIPE; we capture into a var so
  # pi's 141 exit status doesn't trip the script's pipefail.
  local out
  out=$(timeout 20 pi --print --mode json --no-session "ok" </dev/null 2>/dev/null \
          | head -c 4096 || true)
  if echo "$out" | grep -q '"type":"message_start","message":{"role":"assistant"'; then
    ok "pi authenticated and reachable (via provider)"
  else
    warn "pi not authenticated or provider unreachable"
    hint "Run: pi  (then sign in to the configured provider)"
    return 1
  fi
}

verify_hey() {
  hdr "hey auth"
  if hey auth status 2>/dev/null | jq -e '.data.authenticated == true' >/dev/null; then
    ok "hey authenticated"
  else
    warn "hey not authenticated"
    hint "Run: hey auth login"
    return 1
  fi
}

verify_basecamp() {
  hdr "basecamp auth"
  local status authed expired
  status=$(basecamp auth status 2>/dev/null || echo '{}')
  authed=$(echo "$status" | jq -r '.data.authenticated // false')
  expired=$(echo "$status" | jq -r '.data.expired // false')

  if [ "$authed" = "true" ] && [ "$expired" = "false" ]; then
    ok "basecamp authenticated"
    return 0
  fi

  if [ "$authed" = "true" ] && [ "$expired" = "true" ]; then
    info "basecamp token expired — attempting refresh..."
    if basecamp auth refresh 2>&1 | jq -e '.data.status == "refreshed"' >/dev/null 2>&1; then
      ok "basecamp token refreshed"
      return 0
    fi
    warn "basecamp refresh failed (refresh token likely also expired)"
  else
    warn "basecamp not authenticated"
  fi
  hint "Run: basecamp auth login"
  return 1
}

# --- Dropbox: required because tailor.sh symlinks ~/Pictures, ~/Videos,
# --- ~/Documents into ~/Dropbox/. If Dropbox isn't fully signed in, the
# --- symlink step is skipped (or worse, points into an empty stub), so we
# --- gate it here and let the user fix it before tailor proceeds.

verify_dropbox() {
  hdr "dropbox"

  if ! command -v dropbox >/dev/null 2>&1; then
    warn "dropbox not installed"
    hint "Install: omarchy install dropbox"
    return 1
  fi

  if ! pgrep -x dropbox >/dev/null 2>&1; then
    warn "dropbox daemon not running"
    hint "Start it: systemctl --user enable --now dropbox  (or launch the Dropbox app)"
    return 1
  fi

  # ~/.dropbox/info.json is created on first successful sign-in and lists
  # the sync roots. Empty/missing means the user hasn't completed setup.
  if [ ! -s "$HOME/.dropbox/info.json" ]; then
    warn "dropbox not signed in"
    hint "Launch Dropbox and sign in, then wait for initial sync to start"
    return 1
  fi

  if [ ! -d "$HOME/Dropbox" ]; then
    warn "~/Dropbox sync folder missing"
    hint "Open Dropbox preferences and confirm the sync location is ~/Dropbox"
    return 1
  fi

  ok "dropbox installed, running, and signed in"
}

# --- Run all checks; collect failures ---------------------------------

run_all_checks() {
  failures=()
  write_cortex_config || failures+=("cortex")
  write_nebula_config || failures+=("nebula")
  write_fizzy_config  || failures+=("fizzy")
  verify_claude       || failures+=("claude")
  verify_codex        || failures+=("codex")
  verify_pi           || failures+=("pi")
  verify_hey          || failures+=("hey")
  verify_basecamp     || failures+=("basecamp")
  verify_dropbox      || failures+=("dropbox")
}

# --- Loop: prompt to recheck after fixing -----------------------------

while true; do
  run_all_checks

  if [ "${#failures[@]}" -eq 0 ]; then
    echo ""
    ok "All auth checks passed"
    break
  fi

  echo ""
  echo "=== Auth issues ==="
  for f in "${failures[@]}"; do
    echo "  ✗ $f"
  done
  echo ""

  if ! command -v gum >/dev/null 2>&1; then
    warn "gum not installed — continuing anyway"
    break
  fi
  if [ ! -t 0 ] || [ ! -t 1 ]; then
    warn "Not a TTY — continuing without prompt"
    break
  fi

  if gum confirm --default=true --affirmative="Recheck" --negative="Continue anyway" "Press Recheck after fixing the failed checks."; then
    echo ""
    info "Re-checking..."
    continue
  else
    break
  fi
done
