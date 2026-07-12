#!/usr/bin/env bash

set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
tmp=$(mktemp -d)
original_focus=$(herdr workspace list | jq -r 'first(.result.workspaces[] | select(.focused == true) | .workspace_id) // empty')
workspace_ids=()

cleanup() {
  local workspace_id
  for workspace_id in "${workspace_ids[@]}"; do
    herdr workspace close "$workspace_id" >/dev/null 2>&1 || true
  done
  [[ -z $original_focus ]] || herdr workspace focus "$original_focus" >/dev/null 2>&1 || true
  rm -rf "$tmp"
}
trap cleanup EXIT

for command in herdr jq python3; do
  command -v "$command" >/dev/null 2>&1 || {
    printf 'missing required command: %s\n' "$command" >&2
    exit 1
  }
done

cat >"$tmp/config.toml" <<'EOF'
editor = "true"
ai = "true"
diff = "true"
hds_agent = "true"

[hdlm]
warn_threshold = 5
exclude = ["node_modules", "vendor"]
only = []
EOF

mkdir -p "$tmp/runtime"

create_workspace() {
  local dir=$1 label=$2 response
  response=$(herdr workspace create --cwd "$dir" --label "$label" --no-focus)
  workspace_id=$(jq -r '.result.workspace.workspace_id' <<<"$response")
  tab_id=$(jq -r '.result.tab.tab_id' <<<"$response")
  pane_id=$(jq -r '.result.root_pane.pane_id' <<<"$response")
  workspace_ids+=("$workspace_id")
}

invoke() {
  HERDR_ENV=1 \
  HERDR_PLUGIN_ID=herdr-omarchy-live-test \
  HERDR_BIN_PATH="$(command -v herdr)" \
  HERDR_WORKSPACE_ID="$workspace_id" \
  HERDR_TAB_ID="$tab_id" \
  HERDR_PANE_ID="$pane_id" \
  HERDR_OMARCHY_CONFIG="$tmp/config.toml" \
  XDG_RUNTIME_DIR="$tmp/runtime" \
    "$root/bin/herdr-omarchy" "$@"
}

assert_focus_unchanged() {
  local current_focus
  current_focus=$(herdr workspace list | jq -r 'first(.result.workspaces[] | select(.focused == true) | .workspace_id) // empty')
  [[ $current_focus == "$original_focus" ]] || {
    printf 'focus changed from %s to %s\n' "$original_focus" "$current_focus" >&2
    exit 1
  }
}

assert_layout() {
  local expected_count=$1 expected_labels=$2 count labels
  count=$(herdr tab get "$tab_id" | jq -r '.result.tab.pane_count')
  labels=$(herdr pane list --workspace "$workspace_id" | jq -r --arg tab "$tab_id" '
    [.result.panes[] | select(.tab_id == $tab) | .label] | sort | join(",")
  ')
  [[ $count == "$expected_count" ]]
  [[ $labels == "$expected_labels" ]]
  assert_focus_unchanged
}

mkdir -p "$tmp/hdl"
create_workspace "$tmp/hdl" keep-hdl-name
herdr tab rename "$tab_id" keep-hdl-name >/dev/null
invoke hdl >/dev/null
assert_layout 3 'ai,editor,terminal'
[[ $(herdr tab get "$tab_id" | jq -r '.result.tab.label') == keep-hdl-name ]]

mkdir -p "$tmp/hds"
create_workspace "$tmp/hds" keep-hds-name
herdr tab rename "$tab_id" keep-hds-name >/dev/null
invoke hds >/dev/null
assert_layout 4 'agent,diff,editor,terminal'
[[ $(herdr tab get "$tab_id" | jq -r '.result.tab.label') == keep-hds-name ]]

mkdir -p "$tmp/hsl"
create_workspace "$tmp/hsl" keep-hsl-name
herdr tab rename "$tab_id" keep-hsl-name >/dev/null
invoke hsl 6 true >/dev/null
assert_layout 6 'swarm-1,swarm-2,swarm-3,swarm-4,swarm-5,swarm-6'
[[ $(herdr tab get "$tab_id" | jq -r '.result.tab.label') == keep-hsl-name ]]

mkdir -p "$tmp/hdlm"/{01,02,03,04,05,06,node_modules}
create_workspace "$tmp/hdlm" hdlm-source
invoke hdlm --dry-run true >"$tmp/hdlm-dry-run.out" 2>"$tmp/hdlm-dry-run.err"
grep -Fq 'hdlm will prepare 6 folders' "$tmp/hdlm-dry-run.err"
[[ $(herdr tab list --workspace "$workspace_id" | jq -r '.result.tabs | length') == 1 ]]
invoke hdlm --yes true >/dev/null
tabs=$(herdr tab list --workspace "$workspace_id")
[[ $(jq -r '.result.tabs | length' <<<"$tabs") == 6 ]]
[[ $(jq -r '[.result.tabs[].pane_count] | all(. == 3)' <<<"$tabs") == true ]]
assert_focus_unchanged

printf 'herdr-omarchy live tests passed\n'
