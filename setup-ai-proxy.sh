#!/bin/bash
# Configure Claude and Codex to use the shared CLIProxyAPI gateway.
#   ./setup-ai-proxy.sh            credentials from 1Password (prompts if op is locked and a TTY exists)
#   ./setup-ai-proxy.sh --manual   type base_url + token directly (no 1Password / no GUI needed)
#   TAILOR_AI_PROXY_BASE_URL=... TAILOR_AI_PROXY_TOKEN=... ./setup-ai-proxy.sh   fully non-interactive
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

hdr "Claude + Codex proxy authentication and model discovery"
python3 "$SCRIPT_DIR/lib/ai-proxy.py" setup "$@"
info "Restart Claude/Codex and refresh T3's Codex model list to load updated capabilities."
