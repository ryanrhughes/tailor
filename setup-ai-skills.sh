#!/bin/bash
# Agent skills: clone ryanrhughes/agent-skills and install its sync timer.
# From then on the timer keeps skills current on its own (pull every 30
# minutes, external.txt refresh about daily). See that repo's README.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

AGENT_SKILLS_DIR="${AGENT_SKILLS_DIR:-$HOME/Work/agent-skills}"

hdr "Agent skills"

gh_clone ryanrhughes/agent-skills "$AGENT_SKILLS_DIR"

if "$AGENT_SKILLS_DIR/scripts/sync" --install; then
  ok "agent skills synced; timer active"
else
  warn "agent skills sync reported problems"
  hint "Check: $AGENT_SKILLS_DIR/scripts/sync status"
  exit 1
fi
