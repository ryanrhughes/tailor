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

Requires Herdr 0.7.0 or newer plus `bash`, `jq`, and `awk`.

## Actions

```sh
herdr plugin action list --plugin herdr-omarchy
herdr plugin action invoke hdl --plugin herdr-omarchy
herdr plugin action invoke hds --plugin herdr-omarchy
herdr plugin action invoke hdlm --plugin herdr-omarchy
herdr plugin action invoke hsl --plugin herdr-omarchy
```

Tailor-managed machines also get `hdl`, `hds`, `hdlm`, and `hsl` on `PATH`. Run them from a shell inside a single-pane Herdr tab:

```sh
hdl                    # opencode2 in the AI pane
hdl cx                 # cx in the AI pane
hdl cx codex           # stacked cx and codex panes
hds                    # editor/diff/terminal/agent square
hdlm cx                # one hdl tab per direct subdirectory
hsl 6 cx               # six tiled cx panes
```

The direct commands build the surrounding panes and then launch the editor or swarm command in their own process. They do not send a command back into the still-running helper process. Plugin actions run headlessly and use Herdr's injected pane context instead.

The `h` prefix is for Herdr:

| Action | What it does |
| --- | --- |
| `hdl` | Herdr dev layout: current pane becomes editor; adds bottom terminal + right AI pane. |
| `hdl-cx` | Same as `hdl`, but runs `cx` in the AI pane. |
| `hdl-cx-codex` | Same as `hdl`, but runs `cx` and a second `codex` pane. |
| `hds` | Herdr dev square: editor, diff watch, terminal, and agent. |
| `hdlm` | Herdr dev-layout multi: use the current tab, then add one `hdl` tab per remaining direct subdirectory; existing tabs are kept. |
| `hdlm-cx` | Same as `hdlm`, but runs `cx` in each AI pane. |
| `hsl` | Herdr swarm layout: six panes running the default AI command. |
| `hsl-cx` | Six-pane Herdr swarm running `cx` in each pane. |

The default AI command is `opencode2`; override it with `HERDR_OMARCHY_AI_COMMAND`. Layout commands refuse to add another layout to a tab that already has multiple panes. They never focus or rename a workspace; new `hdlm` tabs are created with `--no-focus`.

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
```
