#!/bin/bash
# Generate ~/.ssh/config from 1Password Server items tagged "tailor-ssh"
# and install the local GitHub SSH key from 1Password.
#
# Sources:
# - 1P SSH Key item $TAILOR_GITHUB_SSH_KEY_ITEM_UUID writes
#   $TAILOR_GITHUB_SSH_KEY_PATH and pins github.com to that local key.
# - 1P Server-category items in $TAILOR_OP_ACCOUNT with tag "tailor-ssh".
# Each item should have:
#   - tag: "tailor-ssh"
#   - field "alias" (or "host_alias" / "ssh_alias"): SSH Host alias
#     (falls back to a slugified item title)
#   - field for hostname: matched against (ip|host|hostname|server|address)
#   - field for username: matched against (user|username)
#   - field for port (optional, default 22): "port"
#
# GitHub key item: a 1Password SSH Key item with a private key field and, when
# available, public key / fingerprint attributes. Override the default item UUID
# with TAILOR_GITHUB_SSH_KEY_ITEM_UUID.
#
# Adding a new host: in 1P, create/find the Server item, add tag "tailor-ssh"
# and an "alias" field. Re-run tailor.
#
# The generated block in ~/.ssh/config is delimited by markers — re-runs replace
# only that block, leaving any hand-written config above/below intact.
# GitHub is pinned to the local on-disk SSH key and is the only host excluded
# from the 1Password SSH agent.

set -euo pipefail

TAILOR_OP_ACCOUNT="${TAILOR_OP_ACCOUNT:-chamberofsecrets.1password.com}"
TAILOR_GITHUB_SSH_KEY_ITEM_UUID="${TAILOR_GITHUB_SSH_KEY_ITEM_UUID:-dp7wepzy37ou6dirqsc4jmje7i}"
DEFAULT_TAILOR_GITHUB_SSH_KEY_PATH="$HOME/.ssh/id_ed25519_github"
TAILOR_GITHUB_SSH_KEY_PATH="${TAILOR_GITHUB_SSH_KEY_PATH:-$DEFAULT_TAILOR_GITHUB_SSH_KEY_PATH}"
TAG="tailor-ssh"
MARKER_START="# --- BEGIN tailor SSH (generated from 1Password) ---"
MARKER_END="# --- END tailor SSH ---"

case "$TAILOR_GITHUB_SSH_KEY_PATH" in
  ~/*) TAILOR_GITHUB_SSH_KEY_PATH="$HOME/${TAILOR_GITHUB_SSH_KEY_PATH#~/}" ;;
esac
case "$TAILOR_GITHUB_SSH_KEY_PATH" in
  "$HOME"/*) GITHUB_SSH_CONFIG_IDENTITY_FILE="~/${TAILOR_GITHUB_SSH_KEY_PATH#"$HOME"/}" ;;
  *) GITHUB_SSH_CONFIG_IDENTITY_FILE="$TAILOR_GITHUB_SSH_KEY_PATH" ;;
esac

mkdir -p ~/.ssh "$(dirname "$TAILOR_GITHUB_SSH_KEY_PATH")"

# Backup
[ -f ~/.ssh/config ] && cp ~/.ssh/config ~/.ssh/config.backup."$(date +%Y%m%d_%H%M%S)"

echo "  Installing GitHub SSH key from 1Password item $TAILOR_GITHUB_SSH_KEY_ITEM_UUID..."

if ! github_key_item=$(op item get "$TAILOR_GITHUB_SSH_KEY_ITEM_UUID" \
    --account "$TAILOR_OP_ACCOUNT" \
    --format json 2>/dev/null); then
  echo "  ✗ Failed to fetch GitHub SSH key item $TAILOR_GITHUB_SSH_KEY_ITEM_UUID from $TAILOR_OP_ACCOUNT"
  exit 1
fi

github_private_key=$(echo "$github_key_item" | jq -r '
  [
    .fields[]? |
      select(
        ((.id? // .label? // .n? // "") | ascii_downcase) == "private_key" or
        ((.label? // .t? // "") | ascii_downcase | test("private key"))
      ) |
      (.value? // .v?)
  ] + [
    .details.sections[]?.fields[]? |
      select(
        ((.n? // .label? // "") | ascii_downcase) == "private_key" or
        ((.label? // .t? // "") | ascii_downcase | test("private key"))
      ) |
      (.v? // .value?)
  ] | map(select(. != null and . != "")) | first // empty
')

github_public_key=$(echo "$github_key_item" | jq -r '
  [
    (.fields[]? |
      select(((.id? // .label? // "") | ascii_downcase | test("^(public_key|public key)$"))) |
      (.value? // .v?)),
    (.details.sections[]?.fields[]? |
      select(((.n? // .id? // .label? // "") | ascii_downcase | test("^(public_key|public key)$"))) |
      (.v? // .value?)),
    .fields[]?.sshKeyAttributes?.publicKey?,
    .fields[]?.a?.sshKeyAttributes?.publicKey?,
    .details.sections[]?.fields[]?.sshKeyAttributes?.publicKey?,
    .details.sections[]?.fields[]?.a?.sshKeyAttributes?.publicKey?
  ] | map(select(. != null and . != "")) | first // empty
')

github_fingerprint=$(echo "$github_key_item" | jq -r '
  [
    .overview.ainfo?,
    (.fields[]? |
      select(((.id? // .label? // "") | ascii_downcase | test("^fingerprint$"))) |
      (.value? // .v?)),
    (.details.sections[]?.fields[]? |
      select(((.n? // .id? // .label? // "") | ascii_downcase | test("^fingerprint$"))) |
      (.v? // .value?)),
    .fields[]?.sshKeyAttributes?.fingerprint?,
    .fields[]?.a?.sshKeyAttributes?.fingerprint?,
    .details.sections[]?.fields[]?.sshKeyAttributes?.fingerprint?,
    .details.sections[]?.fields[]?.a?.sshKeyAttributes?.fingerprint?
  ] | map(select(. != null and . != "")) | first // empty
')

if [ -z "$github_private_key" ]; then
  echo "  ✗ GitHub SSH key item is missing a private key field"
  exit 1
fi

github_key_tmp=$(mktemp)
printf '%s\n' "$github_private_key" > "$github_key_tmp"
chmod 600 "$github_key_tmp"

if [ ! -f "$TAILOR_GITHUB_SSH_KEY_PATH" ] || ! cmp -s "$github_key_tmp" "$TAILOR_GITHUB_SSH_KEY_PATH"; then
  install -m 600 "$github_key_tmp" "$TAILOR_GITHUB_SSH_KEY_PATH"
  echo "  ✓ GitHub SSH private key written to $TAILOR_GITHUB_SSH_KEY_PATH"
else
  chmod 600 "$TAILOR_GITHUB_SSH_KEY_PATH"
  echo "  ✓ GitHub SSH private key already up to date at $TAILOR_GITHUB_SSH_KEY_PATH"
fi

rm -f "$github_key_tmp"

if [ -n "$github_public_key" ]; then
  printf '%s\n' "$github_public_key" > "$TAILOR_GITHUB_SSH_KEY_PATH.pub"
  chmod 644 "$TAILOR_GITHUB_SSH_KEY_PATH.pub"
  echo "  ✓ GitHub SSH public key written to $TAILOR_GITHUB_SSH_KEY_PATH.pub"
fi

[ -n "$github_fingerprint" ] && echo "  GitHub SSH key fingerprint: $github_fingerprint"

echo "  Querying $TAILOR_OP_ACCOUNT for Server items tagged '$TAG'..."

if ! items=$(op item list \
    --categories Server \
    --tags "$TAG" \
    --account "$TAILOR_OP_ACCOUNT" \
    --format json 2>/dev/null); then
  echo "  ✗ Failed to query 1Password account $TAILOR_OP_ACCOUNT"
  exit 1
fi

# GitHub must use the local on-disk key, not the 1Password SSH agent. Keep this
# host-specific block before Host * because ssh_config uses the first value it
# finds for each option across matching Host blocks.
block=$'\nHost github.com\n'
block+="    IdentityFile $GITHUB_SSH_CONFIG_IDENTITY_FILE"$'\n'
block+=$'    IdentitiesOnly yes\n    IdentityAgent none\n\n'

# Always include the 1Password SSH agent in Host * — required for the
# 1Password integration to work for every other host.
block+=$'Host *\n    IdentityAgent ~/.1password/agent.sock\n'

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
