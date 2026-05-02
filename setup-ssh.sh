#!/bin/bash
# Generate ~/.ssh/config from 1Password Server items tagged "tailor-ssh".
#
# Source: 1P Server-category items in $TAILOR_OP_ACCOUNT with tag "tailor-ssh".
# Each item should have:
#   - tag: "tailor-ssh"
#   - field "alias" (or "host_alias" / "ssh_alias"): SSH Host alias
#     (falls back to a slugified item title)
#   - field for hostname: matched against (ip|host|hostname|server|address)
#   - field for username: matched against (user|username)
#   - field for port (optional, default 22): "port"
#
# Adding a new host: in 1P, create/find the Server item, add tag "tailor-ssh"
# and an "alias" field. Re-run tailor.
#
# The generated block in ~/.ssh/config is delimited by markers — re-runs replace
# only that block, leaving any hand-written config above/below intact.

set -euo pipefail

TAILOR_OP_ACCOUNT="${TAILOR_OP_ACCOUNT:-chamberofsecrets.1password.com}"
TAG="tailor-ssh"
MARKER_START="# --- BEGIN tailor SSH (generated from 1Password) ---"
MARKER_END="# --- END tailor SSH ---"

mkdir -p ~/.ssh

# Backup
[ -f ~/.ssh/config ] && cp ~/.ssh/config ~/.ssh/config.backup."$(date +%Y%m%d_%H%M%S)"

echo "  Querying $TAILOR_OP_ACCOUNT for Server items tagged '$TAG'..."

if ! items=$(op item list \
    --categories Server \
    --tags "$TAG" \
    --account "$TAILOR_OP_ACCOUNT" \
    --format json 2>/dev/null); then
  echo "  ✗ Failed to query 1Password account $TAILOR_OP_ACCOUNT"
  exit 1
fi

# Always include the 1Password SSH agent in Host * — required for the
# 1Password integration to work for any host.
block=$'\nHost *\n    IdentityAgent ~/.1password/agent.sock\n'

count=$(echo "$items" | jq 'length')
if [ "$count" -eq 0 ]; then
  echo "  ℹ No Server items tagged '$TAG' in $TAILOR_OP_ACCOUNT"
else
  echo "  Found $count host(s) — fetching details..."
  while read -r summary; do
    uuid=$(echo "$summary" | jq -r '.id')
    full=$(op item get "$uuid" --account "$TAILOR_OP_ACCOUNT" --format json)

    title=$(echo "$full" | jq -r '.title')
    alias=$(echo "$full" | jq -r '
      ([.fields[] | select(.label | ascii_downcase | test("^(alias|host_alias|ssh_alias)$")) | .value] | map(select(. != null and . != "")) | first)
      // empty
    ')
    if [ -z "$alias" ]; then
      alias=$(echo "$title" | tr '[:upper:]' '[:lower:]' | tr ' ' '-')
    fi

    hostname=$(echo "$full" | jq -r '
      [.fields[] | select(.label | ascii_downcase | test("^(ip|host|hostname|server|address)$")) | .value] | map(select(. != null and . != "")) | first // empty
    ')
    username=$(echo "$full" | jq -r '
      [.fields[] | select(.label | ascii_downcase | test("^(user|username)$")) | .value] | map(select(. != null and . != "")) | first // empty
    ')
    port=$(echo "$full" | jq -r '
      [.fields[] | select(.label | ascii_downcase | test("^port$")) | .value] | map(select(. != null and . != "")) | first // empty
    ')
    [ -z "$port" ] && port=22

    if [ -z "$hostname" ] || [ -z "$username" ]; then
      echo "    ⚠ Skipping '$title' — missing hostname or username field"
      continue
    fi

    block+=$'\n'
    block+="Host $alias"$'\n'
    block+="    HostName $hostname"$'\n'
    block+="    User $username"$'\n'
    block+="    Port $port"$'\n'

    echo "    ✓ $alias ($username@$hostname:$port)"
  done < <(echo "$items" | jq -c '.[]')
fi

# Strip any existing tailor block (both old single-marker style and current
# BEGIN/END style). Also strip a redundant standalone "Host *" block whose
# only directive is `IdentityAgent ~/.1password/agent.sock` — that line is
# now part of the managed block, so a freestanding copy is duplication.
# A "Host *" block with any other directives is left alone (real user config).
if [ -f ~/.ssh/config ]; then
  awk -v s="$MARKER_START" -v e="$MARKER_END" '
    function finalize() {
      if (collecting_host_star) {
        if (!saw_only_identity_agent)
          for (i = 1; i <= buf_n; i++) print buf[i]
        buf_n = 0
        collecting_host_star = 0
        saw_only_identity_agent = 1
      }
    }
    BEGIN { saw_only_identity_agent = 1 }

    $0 == "# --- Tailor SSH Config (Generated from 1Password) ---" {
      finalize(); in_old=1; next
    }
    $0 == s { finalize(); in_old=0; in_new=1; next }
    $0 == e { in_new=0; next }
    in_old || in_new { next }

    /^Host \*[[:space:]]*$/ {
      finalize()
      collecting_host_star = 1
      saw_only_identity_agent = 1
      buf_n = 1; buf[1] = $0
      next
    }

    /^Host[[:space:]]+/ {
      finalize()
      print; next
    }

    collecting_host_star {
      buf_n++; buf[buf_n] = $0
      if ($0 ~ /^[[:space:]]+IdentityAgent[[:space:]]+~\/\.1password\/agent\.sock[[:space:]]*$/) next
      if ($0 ~ /^[[:space:]]*$/) next
      saw_only_identity_agent = 0
      next
    }

    { print }

    END { finalize() }
  ' ~/.ssh/config > ~/.ssh/config.tmp
else
  : > ~/.ssh/config.tmp
fi

{
  cat ~/.ssh/config.tmp
  echo ""
  echo "$MARKER_START"
  echo "$block"
  echo "$MARKER_END"
} > ~/.ssh/config

rm -f ~/.ssh/config.tmp
chmod 600 ~/.ssh/config

echo "  ✓ SSH config updated"
