# herdr-omarchy

Omarchy-style development layouts for [Herdr](https://herdr.dev). This packages those tmux-inspired development layout shapes as Herdr-native `h*` plugin actions, leaving the original tmux command names untouched.

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

Tailor-managed machines also get lightweight `hdl`, `hds`, `hdlm`, and `hsl` shell dispatchers. Run those from inside a Herdr pane; they call the plugin implementation with the invoking shell's current directory, without taking over tmux's `t*` command names.

The `h` prefix is for Herdr:

| Action | What it does |
| --- | --- |
| `hdl` | Herdr dev layout: current pane becomes editor; adds bottom terminal + right AI pane. |
| `hdl-cx` | Same as `hdl`, but runs `cx` in the AI pane. |
| `hdl-cx-codex` | Same as `hdl`, but runs `cx` and a second `codex` pane. |
| `hds` | Herdr dev square: editor, diff watch, terminal, and agent. |
| `hdlm` | Herdr dev-layout multi: one `hdl` tab per direct subdirectory of the current pane cwd. |
| `hdlm-cx` | Same as `hdlm`, but runs `cx` in each AI pane. |
| `hsl` | Herdr swarm layout: six panes running the default AI command. |
| `hsl-cx` | Six-pane Herdr swarm running `cx` in each pane. |

The default AI command is `omarchy-launch-ai --path .`; override it in the Herdr server environment with `HERDR_OMARCHY_AI_COMMAND`.

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

Herdr plugin actions run from the plugin directory, so `herdr-omarchy` resolves the project directory from the focused pane (`foreground_cwd`, falling back to pane `cwd`). It then controls Herdr through `HERDR_BIN_PATH`, which keeps the action pointed at the session that invoked it.
