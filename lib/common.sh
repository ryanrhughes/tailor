#!/bin/bash
# Shared output helpers for tailor setup scripts. Source, don't execute:
#   source "$SCRIPT_DIR/lib/common.sh"

hdr()  { echo ""; echo "=== $1 ==="; }
ok()   { echo "  ✓ $1"; }
info() { echo "  ℹ $1"; }
warn() { echo "  ⚠ $1"; }
fail() { echo "  ✗ $1"; }
hint() { echo "    $1"; }
