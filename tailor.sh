#!/bin/bash
# Tailor — provision personal customizations on top of Omarchy.
# Idempotent: safe to re-run, in whole or one step at a time.
#
# Usage:
#   ./tailor.sh              interactive picker (gum): set up, set up + projects, or pick steps
#   ./tailor.sh all          set up this machine (also the non-interactive default)
#   ./tailor.sh full         set up this machine + clone projects
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
  "apps|Desktop apps, Brave Origin (default) + 1Password extension, mailcatcher"
  "kanata|Kanata homerow mods, keyboard access + desktop service"
  "envs|~/.config/hypr/envs.conf from 1Password"
  "ssh|GitHub SSH key + ~/.ssh/config from 1Password"
  "zsh|zsh via omarchy-zsh"
  "ai|Mosaic, Claude Code + OpenCode config"
  "ai-proxy|Claude + Codex CLIProxyAPI settings from 1Password"
  "cli-tools|Internal CLIs (cortex, nebula, fizzy)"
  "ai-skills|Agent skills sync (ryanrhughes/agent-skills + timer)"
  "cli-auth|CLI tokens from 1Password + proxy/OAuth verification"
  "config|Dotfiles, ~/.local/bin scripts, Hyprland tweaks"
  "dropbox|Link ~/Pictures ~/Videos ~/Documents to Dropbox"
  "projects|Clone project repos into ~/Work (optional)"
)

# Steps left out of a default run; included by `full` or when picked.
OPTIONAL_STEPS=(projects)

is_optional() {
  printf '%s\n' "${OPTIONAL_STEPS[@]}" | grep -qx "$1"
}

# Every step except the optional ones.
default_step_ids() {
  local id
  for id in $(step_ids); do
    is_optional "$id" || echo "$id"
  done
}

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

# Steps that can't do anything without 1Password. cli-auth also reads
# 1Password but handles it being unavailable on its own.
OP_STEPS=(envs ssh ai-proxy)

# setup-preflight.sh exit code: everything passed except 1Password.
PREFLIGHT_NO_OP=3

# Decided once here: inside $(...) stdout is a pipe, so is_interactive would
# always say no.
INTERACTIVE=false
is_interactive && INTERACTIVE=true

step_needs_op() {
  local id="$1"
  # ai-proxy can run from environment-supplied credentials instead.
  if [ "$id" = "ai-proxy" ] && [ -n "${TAILOR_AI_PROXY_BASE_URL:-}" ]; then
    return 1
  fi
  printf '%s\n' "${OP_STEPS[@]}" | grep -qx "$id"
}

# After a failed step, ask whether to retry it, skip it, or stop the run.
# Prints retry, skip, or abort. Non-interactive runs always skip.
failure_choice() {
  local id="$1" rc="$2" choice options=("Retry" "Skip" "Abort")
  [ "$INTERACTIVE" = true ] || { echo skip; return; }

  # Nothing downstream is trustworthy without preflight; no skipping it.
  [ "$id" = "preflight" ] && options=("Retry" "Abort")

  echo "" >&2
  choice=$(gum choose --header "Step '$id' failed (exit $rc). Fix it, then:" \
    "${options[@]}") || choice="Abort"
  echo "$choice" | tr '[:upper:]' '[:lower:]'
}

summarize() {
  hdr "tailor: summary"
  [ "${#done_steps[@]}" -gt 0 ] && ok "${#done_steps[@]} step(s) completed: ${done_steps[*]}"
  if [ "${#skipped[@]}" -gt 0 ]; then
    warn "${#skipped[@]} step(s) skipped (1Password unavailable): ${skipped[*]}"
  fi
  if [ "${#failed[@]}" -gt 0 ]; then
    fail "${#failed[@]} step(s) failed: ${failed[*]}"
  fi
  local rerun=("${failed[@]}" "${skipped[@]}")
  if [ "${#rerun[@]}" -gt 0 ]; then
    hint "Re-run just those: ./tailor.sh ${rerun[*]}"
    return 1
  fi
}

# Run the given step ids in registry order. A failed step offers
# Retry/Skip/Abort when interactive; otherwise it's recorded and the run
# continues. Preflight failures stop the run (except a missing 1Password,
# which only skips the steps that need it).
run_steps() {
  local requested=("$@")
  local entry id rc choice op_available=true
  local done_steps=() failed=() skipped=()

  for entry in "${STEPS[@]}"; do
    id="${entry%%|*}"
    printf '%s\n' "${requested[@]}" | grep -qx "$id" || continue

    if [ "$op_available" = false ] && step_needs_op "$id"; then
      hdr "tailor: $id"
      warn "skipped — needs 1Password"
      skipped+=("$id")
      continue
    fi

    while true; do
      hdr "tailor: $id"
      rc=0
      "$SCRIPT_DIR/setup-$id.sh" || rc=$?

      if [ "$rc" -eq 0 ]; then
        done_steps+=("$id")
        break
      fi
      if [ "$id" = "preflight" ] && [ "$rc" -eq "$PREFLIGHT_NO_OP" ]; then
        op_available=false
        warn "continuing without 1Password — will skip: ${OP_STEPS[*]}"
        done_steps+=("$id")
        break
      fi

      choice=$(failure_choice "$id" "$rc")
      case "$choice" in
        retry)
          info "Retrying '$id'..."
          ;;
        skip)
          [ "$id" = "preflight" ] && exit 1
          failed+=("$id")
          warn "step '$id' failed — continuing with remaining steps"
          break
          ;;
        *)
          failed+=("$id")
          summarize || true
          exit 1
          ;;
      esac
    done
  done

  summarize || exit 1
}

interactive_pick() {
  local mode
  mode=$(gum choose --header "Tailor — what do you want to run?" \
    "Set up this machine" "Set up this machine + clone projects" "Pick steps") || exit 0

  case "$mode" in
    "Set up this machine")
      run_steps $(default_step_ids)
      return
      ;;
    "Set up this machine + clone projects")
      run_steps $(step_ids)
      return
      ;;
  esac

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
        run_steps $(default_step_ids)
        exit 0
        ;;
      full | --full)
        run_steps $(step_ids)
        exit 0
        ;;
      help | --help | -h)
        sed -n '2,11p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
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

  # No args: gum picker when interactive, machine setup otherwise (provisioning).
  if [ "$INTERACTIVE" = true ]; then
    interactive_pick
  else
    run_steps $(default_step_ids)
  fi
}

main "$@"
