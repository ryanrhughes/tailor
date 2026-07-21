#!/bin/bash
# Memory/swap tuning on top of the Omarchy baseline.
#
# Omarchy ships vm.swappiness=60 and a 4 GB zram (zram-generator's default
# cap of min(ram/2, 4096 MB)). On lower-RAM machines under a heavy desktop
# workload that combination bites: swappiness=60 proactively evicts idle
# window/render buffers to swap even with RAM free, the 4 GB zram fills and
# spills to the (LUKS-encrypted) disk swapfile, and any bulk repaint — e.g.
# re-tiling on a layout toggle — faults that memory back in, stalling the
# display page-flip for hundreds of ms. See the investigation notes in the
# team memory ("omarchy-swap-tuning").
#
# This lowers swappiness so anon pages stay resident, and grows zram to
# ram/2 so the little swapping that does happen stays in fast compressed RAM
# instead of encrypted disk. On high-RAM machines both are effectively
# no-ops (nothing swaps), so it's safe to apply everywhere.
#
# Idempotent: only touches the system (and prompts for sudo) when a value
# actually differs from the desired state.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

SWAPPINESS=10
SYSCTL_FILE=/etc/sysctl.d/99-swappiness.conf
ZRAM_CONF=/etc/systemd/zram-generator.conf
ZRAM_SERVICE=systemd-zram-setup@zram0.service

# --- swappiness ---------------------------------------------------------------
setup_swappiness() {
  hdr "swappiness"

  local desired="vm.swappiness=${SWAPPINESS}"
  local file_ok=false live_ok=false

  [ -f "$SYSCTL_FILE" ] && grep -qxF "$desired" "$SYSCTL_FILE" && file_ok=true
  [ "$(cat /proc/sys/vm/swappiness 2>/dev/null)" = "$SWAPPINESS" ] && live_ok=true

  if $file_ok && $live_ok; then
    ok "already vm.swappiness=${SWAPPINESS} (persisted + live)"
    return
  fi

  if ! $file_ok; then
    printf '%s\n' "$desired" | sudo tee "$SYSCTL_FILE" >/dev/null
    ok "wrote $SYSCTL_FILE"
  fi
  if ! $live_ok; then
    sudo sysctl -w "vm.swappiness=${SWAPPINESS}" >/dev/null
    ok "applied vm.swappiness=${SWAPPINESS} live"
  fi
}

# --- zram size ----------------------------------------------------------------
setup_zram() {
  hdr "zram"

  local desired
  desired=$(printf '%s\n' \
    "[zram0]" \
    "zram-size = ram / 2" \
    "compression-algorithm = zstd")

  local conf_ok=false
  [ -f "$ZRAM_CONF" ] && [ "$(cat "$ZRAM_CONF")" = "$desired" ] && conf_ok=true

  if ! $conf_ok; then
    printf '%s\n' "$desired" | sudo tee "$ZRAM_CONF" >/dev/null
    ok "wrote $ZRAM_CONF (zram-size = ram / 2, zstd)"
  fi

  # Only recreate the device when the live disksize doesn't match ram/2.
  # Recreating restarts swap on zram0, so we avoid doing it needlessly.
  local ram_bytes want have
  ram_bytes=$(awk '/MemTotal/{print $2*1024}' /proc/meminfo)
  want=$((ram_bytes / 2))
  have=$(zramctl --noheadings --bytes --output DISKSIZE /dev/zram0 2>/dev/null | tr -d ' ')

  if [ -z "$have" ] || [ "$have" -lt $((want * 90 / 100)) ]; then
    sudo systemctl daemon-reload
    sudo systemctl restart "$ZRAM_SERVICE"
    ok "recreated zram0 at ~$((want / 1073741824)) GB"
  else
    ok "zram0 already ~$((have / 1073741824)) GB"
  fi
}

# --- hibernation guard --------------------------------------------------------
# We demote the disk swapfile below zram, but suspend-to-disk still writes the
# full RAM image there (zram can't hold it). Warn — don't fail — if the disk
# swap is smaller than RAM, which would break hibernation.
check_hibernation() {
  hdr "hibernation guard"

  local ram_bytes swap_bytes
  ram_bytes=$(awk '/MemTotal/{print $2*1024}' /proc/meminfo)
  swap_bytes=$(awk '$1 !~ /zram/ && NR>1 {sum+=$3*1024} END{print sum+0}' /proc/swaps)

  if [ "$swap_bytes" -ge "$ram_bytes" ]; then
    ok "disk swap ($((swap_bytes / 1073741824)) GB) >= RAM — hibernation OK"
  else
    warn "disk swap ($((swap_bytes / 1073741824)) GB) < RAM ($((ram_bytes / 1073741824)) GB): hibernation would fail. Grow the disk swapfile to >= RAM if this machine hibernates."
  fi
}

echo "Tuning memory/swap behavior..."
setup_swappiness
setup_zram
check_hibernation
echo ""
ok "Memory/swap tuning complete"
