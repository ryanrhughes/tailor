#!/bin/bash
# Configure Claude and Codex to use the shared CLIProxyAPI gateway.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

hdr "Claude + Codex proxy authentication"
python3 "$SCRIPT_DIR/lib/ai-proxy.py" setup
