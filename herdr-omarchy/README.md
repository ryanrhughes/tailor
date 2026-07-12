# herdr-omarchy

Omarchy-style development layouts for [Herdr](https://herdr.dev). This packages the tmux-inspired layout shapes as Herdr plugin actions and direct `h*` commands, leaving the original tmux command names untouched.

## Install

From this repository:

```sh
herdr plugin install ryanrhughes/tailor/herdr-omarchy --yes
```

While developing locally:

```sh
herdr plugin link ./herdr-omarchy
```

Requires Herdr 0.7.0 or newer plus `bash`, `jq`, `awk`, and Python 3.11 or newer.

## Actions

```sh
herdr plugin action list --plugin herdr-omarchy
herdr plugin action invoke hdl --plugin herdr-omarchy
herdr plugin action invoke hds --plugin herdr-omarchy
herdr plugin action invoke hdlm --plugin herdr-omarchy
herdr plugin action invoke hsl --plugin herdr-omarchy
herdr plugin action invoke preset-review --plugin herdr-omarchy
herdr plugin action invoke preset-swarm --plugin herdr-omarchy
```

Tailor-managed machines also get `hdl`, `hds`, `hdlm`, and `hsl` on `PATH`. Run them from a shell inside a single-pane Herdr tab:

```sh
hdl                    # opencode2 in the AI pane
hdl cx                 # cx in the AI pane
hdl cx codex           # stacked cx and codex panes
hds                    # editor/diff/terminal/agent square
hdlm cx                # one hdl tab per direct subdirectory
hsl 6 cx               # six tiled cx panes
hdl --preset review    # named preset from config.toml
```

The direct commands build the surrounding panes and then launch the editor or swarm command in their own process. They do not send a command back into the still-running helper process. Plugin actions run headlessly and use Herdr's injected pane context instead.

The `h` prefix is for Herdr:

| Action | What it does |
| --- | --- |
| `hdl` | Herdr dev layout: current pane becomes editor; adds bottom terminal + right AI pane. |
| `hdl-cx` | Same as `hdl`, but runs `cx` in the AI pane. |
| `hdl-cx-codex` | Same as `hdl`, but runs `cx` and a second `codex` pane. |
| `hds` | Herdr dev square: editor, diff watch, terminal, and agent. |
| `hdlm` | Herdr dev-layout multi: use the current tab, then add one `hdl` tab per remaining matching direct subdirectory; existing tabs are kept. |
| `hdlm-cx` | Same as `hdlm`, but runs `cx` in each AI pane. |
| `hsl` | Herdr swarm layout: six panes running the default AI command. |
| `hsl-cx` | Six-pane Herdr swarm running `cx` in each pane. |

The default AI command is `opencode2`; override it with `HERDR_OMARCHY_AI_COMMAND`. Layout commands refuse to add another layout to a tab that already has multiple panes and lock the invoking tab against concurrent layout commands.

`hdl`, `hds`, and `hsl` preserve the invoking tab's name. `hdlm` names its directory tabs, but never focuses or renames a workspace; additional tabs are created with `--no-focus`.

## Configuration

Tailor seeds `~/.config/herdr/plugins/config/herdr-omarchy/config.toml` once and preserves subsequent edits. GitHub installs can start from `config.example.toml` in the plugin directory.

```toml
editor = "nvim"
ai = "opencode2"
diff = "hunk diff --watch"

[ratios]
editor_terminal = 0.85
editor_ai = 0.70
ai_stack = 0.50

[hdlm]
warn_threshold = 5
exclude = ["node_modules", "vendor"]
only = []

[presets.review]
layout = "hdl"
commands = ["cx", "codex"]

[presets.swarm]
layout = "hsl"
count = 6
command = "opencode2"
```

Run a preset through its matching command or directly from the plugin checkout:

```sh
hdl --preset review
./bin/herdr-omarchy preset review
```

Explicit command arguments override preset commands. Presets override environment variables and global config values. Environment variables override global config values. Set `HERDR_OMARCHY_CONFIG` to use another config file.

## Multi-Directory Layouts

`hdlm` supports repeatable directory-name glob filters and a non-mutating preview:

```sh
hdlm --dry-run
hdlm --exclude 'archive-*' --exclude node_modules
hdlm --only 'api-*'
hdlm --yes
```

When more than `hdlm.warn_threshold` folders match, `hdlm` prints the complete current/existing/new tab plan. Interactive use asks for confirmation. Headless plugin actions notify and stop; rerun `hdlm --yes` from the current shell to approve the plan.

## Optional keybindings

Add any of these to `~/.config/herdr/config.toml` after installing the plugin:

```toml
[[keys.command]]
key = "prefix+shift+l"
type = "plugin_action"
command = "herdr-omarchy.hdl"
description = "Herdr dev layout"

[[keys.command]]
key = "prefix+shift+s"
type = "plugin_action"
command = "herdr-omarchy.hds"
description = "Herdr dev square"
```

## Runtime notes

Herdr plugin actions run from the plugin directory, so `herdr-omarchy` resolves the project directory and workspace/tab ids from the focused pane instead of trusting the plugin process's working directory. It controls Herdr through `HERDR_BIN_PATH`, which keeps the action pointed at the session that invoked it.

Direct commands use the invoking shell's current directory and validate that `HERDR_PANE_ID` still exists. If a server restart restored the session under new pane ids, open a new shell before running a layout command.

## Test

```sh
bash tests/herdr-omarchy-test.sh
bash tests/live-test.sh
```

The live suite creates non-focused temporary workspaces, verifies every layout against the running Herdr server, checks that ordinary tab names and workspace focus are preserved, and removes all test workspaces on exit.
