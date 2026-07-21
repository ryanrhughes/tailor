#!/bin/bash
# Tailor — provision personal customizations on top of Omarchy.
# Idempotent: safe to re-run, in whole or one step at a time.
#
# Usage:
#   ./tailor.sh              interactive picker (gum): everything, or select steps
#   ./tailor.sh all          run everything (also the non-interactive default)
#   ./tailor.sh <step>...    run specific steps, e.g. ./tailor.sh envs ssh
#   ./tailor.sh list         list available steps

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"
source "$SCRIPT_DIR/lib/common.sh"

# Ordered step registry: "<id>|<description>". Step <id> runs setup-<id>.sh.
# Order matters for full runs (preflight gates, cli-tools before cli-auth, etc.)
STEPS=(
  "preflight|Verify prerequisites (Omarchy, toolchain, 1Password)"
  "cleanup|Remove stale artifacts from previous tailor versions"
  "swap|Memory/swap tuning (lower swappiness + grow zram)"
  "repos|Clone Omarchy + personal repos into ~/Work"
  "apps|Desktop apps (Dropbox, Tailscale, Voxtype, ...) + mailcatcher"
  "envs|~/.config/hypr/envs.conf from 1Password"
  "ssh|GitHub SSH key + ~/.ssh/config from 1Password"
  "zsh|zsh via omarchy-zsh"
  "ai|AI CLI binaries, Mosaic, Claude Code + OpenCode config"
  "pi|Pi settings + extensions"
  "ai-skills|Canonical AI skills allowlist"
  "cli-tools|Internal CLIs (cortex, nebula, hey, fizzy, basecamp)"
  "cli-auth|CLI tokens from 1Password + OAuth verification"
  "codexbar|codexbar-waybar install + Waybar integration"
  "herdr|Herdr config, theme sync + layout plugin"
  "config|Dotfiles, ~/.local/bin scripts, Hyprland tweaks"
  "dropbox|Link ~/Pictures ~/Videos ~/Documents to Dropbox"
)

step_ids() {
  local entry
  for entry in "${STEPS[@]}"; do
    echo "${entry%%|*}"
  done
}

step_desc() {
  local id="$1" entry
  for entry in "${STEPS[@]}"; do
    if [ "${entry%%|*}" = "$id" ]; then
      echo "${entry#*|}"
      return 0
    fi
  done
  return 1
}

list_steps() {
  local entry id
  echo "Available steps (run with: ./tailor.sh <step>...):"
  echo ""
  for entry in "${STEPS[@]}"; do
    id="${entry%%|*}"
    printf "  %-11s %s\n" "$id" "${entry#*|}"
  done
}

# Run the given step ids in registry order, keep going on failure, and
# summarize at the end. A preflight failure aborts immediately — nothing
# downstream is trustworthy without it.
run_steps() {
  local requested=("$@")
  local entry id failed=() ran=()

  for entry in "${STEPS[@]}"; do
    id="${entry%%|*}"
    printf '%s\n' "${requested[@]}" | grep -qx "$id" || continue

    hdr "tailor: $id"
    ran+=("$id")
    if "$SCRIPT_DIR/setup-$id.sh"; then
      continue
    elif [ "$id" = "preflight" ]; then
      exit 1
    else
      failed+=("$id")
      warn "step '$id' failed — continuing with remaining steps"
    fi
  done

  hdr "tailor: summary"
  if [ "${#failed[@]}" -gt 0 ]; then
    fail "${#failed[@]}/${#ran[@]} step(s) failed: ${failed[*]}"
    hint "Re-run just those: ./tailor.sh ${failed[*]}"
    exit 1
  fi
  ok "${#ran[@]} step(s) completed: ${ran[*]}"
}

interactive_pick() {
  local mode
  mode=$(gum choose --header "Tailor — what do you want to run?" \
    "Run everything" "Pick steps") || exit 0

  if [ "$mode" = "Run everything" ]; then
    run_steps $(step_ids)
    return
  fi

  local entry choices=() picked
  for entry in "${STEPS[@]}"; do
    choices+=("$(printf '%-11s %s' "${entry%%|*}" "${entry#*|}")")
  done

  picked=$(gum choose --no-limit --height 20 \
    --header "Select steps (space to toggle, enter to run)" \
    "${choices[@]}") || exit 0

  if [ -z "$picked" ]; then
    echo "Nothing selected."
    exit 0
  fi

  run_steps $(echo "$picked" | awk '{print $1}')
}

main() {
  # Explicit args: list, all, or specific step ids.
  if [ "$#" -gt 0 ]; then
    case "$1" in
      list | --list | -l)
        list_steps
        exit 0
        ;;
      all | --all)
        run_steps $(step_ids)
        exit 0
        ;;
      help | --help | -h)
        sed -n '2,10p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
        exit 0
        ;;
    esac

    local id
    for id in "$@"; do
      if ! step_desc "$id" >/dev/null; then
        fail "unknown step: $id"
        echo ""
        list_steps
        exit 1
      fi
    done
    run_steps "$@"
    exit
  fi

  # No args: gum picker when interactive, full run otherwise (CI/provisioning).
  if [ -t 0 ] && [ -t 1 ] && command -v gum >/dev/null 2>&1; then
    interactive_pick
  else
    run_steps $(step_ids)
  fi
}

main "$@"
