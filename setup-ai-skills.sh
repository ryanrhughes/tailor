#!/bin/bash
# Reconcile the global AI skills listed in ai-skills.txt.
# Idempotent: `skills add` updates existing skills and `skills remove` ignores
# skills that are already absent.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

SKILLS_MANIFEST="${AI_SKILLS_MANIFEST:-$SCRIPT_DIR/ai-skills.txt}"

hdr "AI skills"

if ! command -v npx >/dev/null 2>&1; then
  warn "npx not in PATH — skills install skipped (node/npm are preflight requirements)"
  exit 0
fi

if [ ! -f "$SKILLS_MANIFEST" ]; then
  fail "Skills manifest not found: $SKILLS_MANIFEST"
  exit 1
fi

line_number=0
failures=0
while IFS= read -r line || [ -n "$line" ]; do
  ((line_number += 1))

  fields=()
  read -r -a fields <<< "$line"
  [ "${#fields[@]}" -eq 0 ] && continue
  [[ "${fields[0]}" == \#* ]] && continue

  action="${fields[0]}"
  if [ "${#fields[@]}" -lt 2 ]; then
    warn "$SKILLS_MANIFEST:$line_number: missing source or skill name"
    ((failures += 1))
    continue
  fi

  case "$action" in
    +)
      source="${fields[1]}"
      options=("${fields[@]:2}")
      info "Syncing skills from $source..."
      if npx -y skills add "$source" -g -y "${options[@]}" </dev/null >/dev/null 2>&1; then
        ok "$source synced"
      else
        warn "Failed to sync skills from $source"
        ((failures += 1))
      fi
      ;;
    -)
      name="${fields[1]}"
      info "Ensuring $name is absent..."
      if npx -y skills remove "$name" -g -y </dev/null >/dev/null 2>&1; then
        ok "$name absent"
      else
        warn "Failed to remove $name"
        ((failures += 1))
      fi
      ;;
    *)
      warn "$SKILLS_MANIFEST:$line_number: expected '+' or '-', got '$action'"
      ((failures += 1))
      ;;
  esac
done < "$SKILLS_MANIFEST"

if [ "$failures" -gt 0 ]; then
  fail "$failures skill operation(s) failed"
  exit 1
fi
