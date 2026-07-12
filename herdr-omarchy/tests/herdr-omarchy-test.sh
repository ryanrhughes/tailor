#!/usr/bin/env bash

set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

project="$tmp/project"
mkdir -p "$project"

cat >"$tmp/herdr" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >>"$FAKE_HERDR_LOG"

case "$1 $2" in
  "pane get")
    printf '{"result":{"pane":{"pane_id":"w1:p1","tab_id":"w1:t1","workspace_id":"w1","cwd":"%s","foreground_cwd":"%s"}}}\n' "$FAKE_CWD" "$FAKE_CWD"
    ;;
  "tab get")
    printf '{"result":{"tab":{"tab_id":"w1:t1","pane_count":%s}}}\n' "${FAKE_PANE_COUNT:-1}"
    ;;
  "tab list")
    current_label=1
    [[ ! -f $FAKE_TAB_LABEL ]] || current_label=$(<"$FAKE_TAB_LABEL")
    printf '{"result":{"tabs":[{"tab_id":"w1:t1","label":"%s","pane_count":1}' "$current_label"
    if [[ -f $FAKE_CREATED_TAB_LABEL ]]; then
      printf ',{"tab_id":"w1:t2","label":"%s","pane_count":3}' "$(<"$FAKE_CREATED_TAB_LABEL")"
    fi
    printf ']}}\n'
    ;;
  "tab rename")
    printf '%s' "$4" >"$FAKE_TAB_LABEL"
    printf '{"result":{"type":"ok"}}\n'
    ;;
  "tab create")
    label=
    args=("$@")
    for ((index = 0; index < ${#args[@]}; index++)); do
      if [[ ${args[$index]} == --label ]]; then
        label=${args[$((index + 1))]}
      fi
    done
    printf '%s' "$label" >"$FAKE_CREATED_TAB_LABEL"
    count=1
    [[ ! -f $FAKE_HERDR_STATE ]] || count=$(<"$FAKE_HERDR_STATE")
    count=$((count + 1))
    printf '%s' "$count" >"$FAKE_HERDR_STATE"
    printf '{"result":{"tab":{"tab_id":"w1:t2"},"root_pane":{"pane_id":"w1:p%s"}}}\n' "$count"
    ;;
  "pane split")
    count=1
    [[ ! -f $FAKE_HERDR_STATE ]] || count=$(<"$FAKE_HERDR_STATE")
    count=$((count + 1))
    printf '%s' "$count" >"$FAKE_HERDR_STATE"
    printf '{"result":{"pane":{"pane_id":"w1:p%s"}}}\n' "$count"
    ;;
  "pane process-info")
    printf '{"result":{"process_info":{"shell_pid":10,"foreground_processes":[{"pid":10}]}}}\n'
    ;;
  *)
    printf '{"result":{"type":"ok"}}\n'
    ;;
esac
EOF
chmod +x "$tmp/herdr"

export FAKE_HERDR_LOG="$tmp/herdr.log"
export FAKE_HERDR_STATE="$tmp/herdr.state"
export FAKE_TAB_LABEL="$tmp/tab-label"
export FAKE_CREATED_TAB_LABEL="$tmp/created-tab-label"
export FAKE_CWD="$project"
export HERDR_BIN_PATH="$tmp/herdr"
export HERDR_ENV=1
export HERDR_PANE_ID=w1:p1
export HERDR_TAB_ID=w1:t1
export HERDR_WORKSPACE_ID=w1
export HERDR_OMARCHY_EDITOR=true

ln -s "$root/bin/herdr-omarchy" "$tmp/hdl"
env -u HERDR_ENV -u HERDR_PANE_ID "$tmp/hdl" --help >/dev/null

assert_contains() {
  grep -Fqx "$1" "$FAKE_HERDR_LOG" || {
    printf 'missing command: %s\n' "$1" >&2
    cat "$FAKE_HERDR_LOG" >&2
    exit 1
  }
}

assert_not_contains() {
  if grep -Fqx "$1" "$FAKE_HERDR_LOG"; then
    printf 'unexpected command: %s\n' "$1" >&2
    cat "$FAKE_HERDR_LOG" >&2
    exit 1
  fi
}

# Plugin actions run headlessly, so the editor is sent to the source pane.
: >"$FAKE_HERDR_LOG"
rm -f "$FAKE_HERDR_STATE"
HERDR_PLUGIN_ID=herdr-omarchy bash "$root/bin/herdr-omarchy" hdl >/dev/null
assert_contains "pane split w1:p1 --direction down --cwd $project --ratio 0.85 --no-focus"
assert_contains "pane split w1:p1 --direction right --cwd $project --ratio 0.70 --no-focus"
assert_contains "pane run w1:p3 cd '$project' && opencode2"
assert_contains "pane run w1:p1 cd '$project' && true ."

# A shell command must not send editor input into the helper running in its pane.
: >"$FAKE_HERDR_LOG"
rm -f "$FAKE_HERDR_STATE"
(cd "$project" && env -u HERDR_PLUGIN_ID bash "$root/bin/herdr-omarchy" hdl true >/dev/null)
assert_contains "pane run w1:p3 cd '$project' && true"
assert_not_contains "pane run w1:p1 cd '$project' && true ."

# Refuse to stack a layout onto an already split tab.
: >"$FAKE_HERDR_LOG"
if FAKE_PANE_COUNT=2 HERDR_PLUGIN_ID=herdr-omarchy bash "$root/bin/herdr-omarchy" hdl true >"$tmp/out" 2>"$tmp/err"; then
  echo "expected multi-pane invocation to fail" >&2
  exit 1
fi
grep -Fq "already has 2 panes" "$tmp/err"
if grep -Fq "pane split" "$FAKE_HERDR_LOG"; then
  echo "layout mutated a multi-pane tab" >&2
  exit 1
fi

# hdlm builds the first layout in the invoking tab and never moves focus.
: >"$FAKE_HERDR_LOG"
rm -f "$FAKE_HERDR_STATE" "$FAKE_TAB_LABEL" "$FAKE_CREATED_TAB_LABEL"
mkdir -p "$project/alpha" "$project/beta"
HERDR_PLUGIN_ID=herdr-omarchy bash "$root/bin/herdr-omarchy" hdlm true >/dev/null
assert_contains "tab rename w1:t1 alpha"
assert_contains "tab create --workspace w1 --cwd $project/beta --label beta --no-focus"
if grep -Eq '^(workspace focus|workspace rename|tab focus)' "$FAKE_HERDR_LOG"; then
  echo "hdlm changed workspace or tab focus" >&2
  cat "$FAKE_HERDR_LOG" >&2
  exit 1
fi

echo "herdr-omarchy tests passed"
