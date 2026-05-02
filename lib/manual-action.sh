#!/bin/bash
# Shared helper: pause for a manual action, then recheck via a verification
# command. Source this from any setup-*.sh that has a step which can't be
# scripted (e.g. an interactive TUI install).
#
# Usage:
#   prompt_manual_action "human-readable description" \
#                        "verification command (returns 0 when done)" \
#                        "hint to print (the command for the user to run)"
#
# Behavior:
#   - If verification already passes: return 0 silently.
#   - If verification fails AND TTY/gum available: loop with gum confirm,
#     re-running verification each time the user says they're done.
#   - If verification fails AND no TTY: print the warn + hint, return 0.
#     (Lets non-interactive runs continue without blocking.)

prompt_manual_action() {
  local description="$1"
  local verify_cmd="$2"
  local hint="$3"

  # Already done — nothing to do.
  if eval "$verify_cmd" >/dev/null 2>&1; then
    ok "$description (already done)"
    return 0
  fi

  warn "$description"
  echo "    $hint"

  # No-TTY or no-gum: print and continue (don't block).
  if ! command -v gum >/dev/null 2>&1 || [ ! -t 0 ] || [ ! -t 1 ]; then
    return 0
  fi

  while true; do
    if gum confirm --default=true --affirmative="Done" --negative="Skip" "Press Done after running the manual step."; then
      if eval "$verify_cmd" >/dev/null 2>&1; then
        ok "verified — $description"
        return 0
      else
        warn "Verification still failing. Press Done after retrying, or Skip."
      fi
    else
      return 0
    fi
  done
}
