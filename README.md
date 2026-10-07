# Tailor

Personal environment provisioning on top of Omarchy. Re-runnable, idempotent, opinionated.

Tailor doesn't try to do everything — it builds on what Omarchy already provides (mise, node, the AI CLIs, AUR helpers) and layers in personal customization: env vars, SSH hosts, AI skills, internal CLI tooling, and per-tool config.

## Quick start

1. Install [1Password CLI](https://developer.1password.com/docs/cli/get-started/) and enable the desktop-app integration (Settings → Developer → "Integrate with 1Password CLI").
2. Sign in to 1Password (`op vault list` should succeed).
3. Run:
   ```bash
   ./tailor.sh
   ```

Run interactively and `tailor.sh` opens a gum picker: set up this machine, set up this machine and clone your projects, or pick individual steps. Non-interactive runs (no TTY) set up the machine without cloning projects.

```bash
./tailor.sh              # interactive picker
./tailor.sh all          # set up this machine, no prompts
./tailor.sh full         # set up this machine + clone projects
./tailor.sh envs ssh     # re-run specific steps (changed an env? just: ./tailor.sh envs)
./tailor.sh list         # list available steps
```

Steps always execute in pipeline order regardless of the order you name them. When a step fails in an interactive run, you're asked to **Retry** it (after fixing whatever broke), **Skip** it, or **Abort** the run. Non-interactive runs skip and continue. Either way the summary tells you exactly which steps to re-run. Network operations (clones, downloads, `mise`/`yay` installs, `docker pull`) retry with backoff on their own (`TAILOR_RETRIES`, default 3), and a multi-part step like `apps` or `cli-tools` finishes its other parts before reporting the failure.

The pre-flight bails with clear hints if a basic tool is missing. 1Password is not fatal: `op` never gets a terminal and is capped at `TAILOR_OP_TIMEOUT` seconds, so a signed-out or locked 1Password can't hang the run. Interactive runs get a Retry/Skip prompt so you can unlock it in place. If you skip, the steps that need secrets (`envs`, `ssh`, `ai-proxy`) are skipped and listed for re-running. First run on a fresh machine will tell you exactly what 1Password items to create.

## Pipeline

Each step is `setup-<step>.sh`, idempotent, and can be invoked standalone or via `./tailor.sh <step>`.

| Step | What it does |
|---|---|
| `preflight` | Verifies the basics: pacman, gum, jq/curl/gh/docker, mise/node/npm, and 1Password auth. Bails on missing prerequisites. |
| `cleanup` | Removes stale Tailor-managed artifacts from previous versions, like the old unofficial `figma-developer-mcp` install/config. |
| `apps` | Installs optional desktop apps via Omarchy (Dropbox, GeForce NOW, Tailscale, Voxtype, T3 Code) and AUR (Vesktop), installs Brave Origin and makes it the default browser, adds the 1Password extension to every Chromium-family browser via managed policy, and starts the mailcatcher container. |
| `kanata` | Installs Kanata, the shared home-row layout, automatic keyboard detection, udev permissions, the desktop service, and gaming/status helpers. Retries interrupted setup and preserves gaming mode. Supports local device exclusions or an explicit keyboard list. |
| `envs` | Reads 1P item `tailor-envs` → writes `~/.config/hypr/envs.conf`. |
| `ssh` | Reads 1P SSH Key item `Github SSH Key` → writes `~/.ssh/id_ed25519_github` + `.pub`; reads 1P Server items tagged `tailor-ssh` → writes `~/.ssh/config` (managed block with markers; preserves any hand-written entries above/below). Pins `github.com` to the GitHub-named local key; every other host defaults to `Host * IdentityAgent ~/.1password/agent.sock`. |
| `zsh` | Installs `omarchy-zsh` package and runs `omarchy-setup-zsh` (idempotent — detects template signature in `.zshrc`/`.bashrc`). |
| `ai` | Installs + logs into Mosaic (token entered hidden), Claude Code attribution settings, OpenCode config + slash commands. The AI CLIs themselves come from Omarchy. |
| `ai-proxy` | Configures Claude and Codex to use CLIProxyAPI on Mercury with the client token from 1Password. Adds missing settings, refreshes the proxy URL/token, and preserves models, hooks, plugins, and other settings. |
| `cli-tools` | Installs internal CLIs (cortex, nebula, fizzy); hey and basecamp come from Omarchy. Their skills come from `ai-skills`. |
| `ai-skills` | Clones [ryanrhughes/agent-skills](https://github.com/ryanrhughes/agent-skills) and installs its sync timer: personal skills plus every outside skill in its `external.txt`, kept current automatically across machines. |
| `cli-auth` | For token-based CLIs (cortex/nebula/fizzy): pulls token + config from 1P → writes the CLI's config file. Verifies Claude/Codex proxy credentials through authenticated model discovery, and checks HEY/Basecamp authentication. Loops with a `gum` prompt to recheck after fixing. |
| `config` | Copies `config/**` → `~/.config/` (excluding dirs owned by other steps) and `bin/**` → `~/.local/bin/`. |
| `dropbox` | Symlinks `~/Pictures`, `~/Videos`, `~/Documents` to their `~/Dropbox` counterparts (backs up existing dirs first). |
| `projects` | Optional — only with `./tailor.sh full`, the picker's "+ clone projects" option, or by name. Clones Omarchy repos (installer/iso/pkgs) into `~/Work`. |

Shared output helpers live in `lib/common.sh`; `lib/manual-action.sh` provides the gum-based "do this manually, then recheck" loop.

## Claude and Codex proxy authentication

Full runs include `ai-proxy` before `cli-auth`. To configure or repair just the proxy setup:

```bash
./tailor.sh ai-proxy
```

The `CLI Proxy API` 1Password item supplies `token` (the concealed client API key) and `base_url` (normally `http://mercury:8317`). Its existing `password` field is the management password and is never used for client authentication. Override the item name or UUID with `TAILOR_AI_PROXY_ITEM`.

The `op` lookup is capped at 20 seconds (`TAILOR_OP_TIMEOUT`). If 1Password is locked (the Omarchy screen lock also locks the app) and you cannot reach its unlock dialog, for example over SSH, supply the values yourself instead:

```bash
./setup-ai-proxy.sh --manual                         # prompts for base_url and token (token hidden)
TAILOR_AI_PROXY_BASE_URL=http://mercury:8317 TAILOR_AI_PROXY_TOKEN=... ./setup-ai-proxy.sh
```

Environment variables take precedence over 1Password. When `op` fails on an interactive terminal the step falls back to the same prompts; without a terminal it exits with a hint instead of hanging.

Claude receives `ANTHROPIC_BASE_URL`, `ANTHROPIC_AUTH_TOKEN`, gateway model discovery, and missing timeout defaults in `~/.claude/settings.json`. Codex receives the `cliproxyapi` provider in `~/.codex/config.toml`, using the Responses API and WebSockets at `<base_url>/v1`. The client token is stored in Codex's `experimental_bearer_token` setting so terminal and desktop launches use the same configuration without shell exports; `requires_openai_auth = false` lets fresh systems connect without an additional ChatGPT login. These settings are described in the [official OpenAI configuration reference](https://developers.openai.com/codex/config-reference/).

Existing model choices, unrelated config, and OAuth credential files are preserved. Changed configs get a one-time `.bak.before-tailor-ai-proxy` backup, configs and backups are private (mode `0600`), and identical reruns do not rewrite them. Both candidates are validated before either is written; unsupported TOML layouts fail without replacing the existing config. Rerun the step after changing the client token or URL in 1Password, then restart Claude/Codex to load the settings. Mercury must be reachable over Tailscale for API requests.

Codex also receives these settings so it discovers model capabilities from the shared proxy. Routing inference through Mercury alone does not enable catalog discovery:

```toml
[features]
api_key_model_discovery = true

[model_providers.cliproxyapi]
model_catalog_url = "http://mercury:8317/v1/models"
```

The catalog URL follows the `base_url` from 1Password. This exposes service tiers advertised by Mercury, including Ultrafast for GPT-6 Astra. After setup, restart Codex and refresh T3's Codex provider/model list to update an already-running T3 instance. Select Astra to see its tiers; a different default model, such as Sol, has different capabilities. If migrating from the earlier local-catalog workaround, remove the top-level `model_catalog_json` setting from `~/.codex/config.toml`: that startup override takes precedence over discovery. Tailor preserves existing local-catalog overrides, so they need this explicit migration.

Existing model choices, unrelated config, and OAuth credential files are preserved. Changed configs get a one-time `.bak.before-tailor-ai-proxy` backup, configs and backups are private (mode `0600`), and identical reruns do not rewrite them. Both candidates are validated before either is written; unsupported TOML layouts fail without replacing the existing config. Rerun the step after changing the client token or URL in 1Password, then restart Claude/Codex to load the settings. Mercury must be reachable over Tailscale for API requests.

`cli-auth` checks authenticated `/v1/models` access for both clients; it does not verify service-tier metadata, run inference or rely on cached OAuth login status. Run the provisioning regression checks with `python3 tests/ai-proxy-test.py`.

## Kanata

Tailor owns the Kanata installation. The shared layout lives in `kanata/homerow-mods.kbd`: mirrored Ctrl/Alt/Super/Shift on `a/s/d/f` and `;/l/k/j`, a 150 ms hold threshold, a 200 ms tap-repress window, and a 100 ms typing-idle guard. Left Alt remains ordinary Alt. There is no symbols layer.

Internal and external keyboards are detected automatically, including keyboards with built-in pointing devices. Newly connected keyboards are picked up without rerunning setup:

```bash
./tailor.sh kanata
```

The local policy is saved in `~/.config/kanata/devices.kbd` and preserved on subsequent runs. Use `TAILOR_KANATA_DEVICES=auto` to replace an existing restricted list with automatic detection. Some mice expose a keyboard interface; exclude those locally with `TAILOR_KANATA_EXCLUDE`. Both variables accept exact Linux device names, with multiple names separated by newlines. Explicit keyboard names in `TAILOR_KANATA_DEVICES` restrict remapping to those devices. Replacing the policy also replaces its exclusions, so supply both variables when needed:

```bash
TAILOR_KANATA_DEVICES=auto \
  TAILOR_KANATA_EXCLUDE='Pulsar Feinmann 8K Dongle Keyboard' ./tailor.sh kanata
```

Setup loads the `uinput` kernel module immediately and at boot via `/etc/modules-load.d/kanata.conf`. The udev rule grants the active desktop user keyboard and uinput access without the `input` group. The service starts with the graphical session and restarts on failure; Ctrl+Space+Esc leaves it stopped. Super+F12 toggles gaming mode. `kanata-status` checks whether the process has opened an actual keyboard, without reading keystrokes.

Existing config, service, and helpers are backed up with `.bak.before-tailor-kanata` before replacement. Setup records pending work in `~/.local/state/tailor/kanata/` so failed permission reloads or service restarts are retried. Unchanged runs do not restart Kanata. An existing stopped service stays stopped; fresh installs start immediately when a graphical session is active.

Run the regression checks with `python3 tests/kanata-test.py`. To test the layout using Kanata 1.12's simulator, run `KANATA_SIM_BIN=/path/to/kanata_simulated_input python3 tests/kanata-sim.py`.

## 1Password items used

All in `chamberofsecrets.1password.com` by default (override via `TAILOR_OP_ACCOUNT`).

| Item | Type | Fields | Used by |
|---|---|---|---|
| `tailor-envs` | Secure Note | one text/concealed field per env var (label = name, value = value) | `setup-envs.sh` |
| `Github SSH Key` (`dp7wepzy37ou6dirqsc4jmje7i`) | SSH Key | `private_key` plus 1Password SSH key public key/fingerprint attributes | `setup-ssh.sh` |
| `Cortex API` | API Credential | `token`, `tenant_id`, `api_url` | `setup-cli-auth.sh` |
| `Nebula API` | API Credential | `token`, `workspace`/`workspace_url`/`domain`/`scheme`/`api_url` | `setup-cli-auth.sh` |
| `Fizzy API` | API Credential | `token`, `account`, `api_url` | `setup-cli-auth.sh` |
| `CLI Proxy API` | Login | `token` (concealed client key), `base_url`; existing management `password` is preserved | `setup-ai-proxy.sh` |
| (any Server item, tagged `tailor-ssh`) | Server | `alias`, `IP`/hostname, `username`, optionally `port` | `setup-ssh.sh` |

When `setup-cli-auth.sh` runs and an item is missing, it prints an `op item create` command tailored to your defaults — paste, run, re-run tailor.

## OpenCode MCP servers

In `config/opencode/opencode.jsonc`:

| Server | Default | Why |
|---|---|---|
| `chrome-devtools` | **disabled** | Heavy local-process MCP — large tool catalog loads into context every turn. Toggle on per-session/project. |
| `figma` | **disabled** | Official remote Figma MCP. Enable per-session/project and authenticate via OAuth when needed. |
| `context7` | enabled | Lightweight remote (docs search). |
| `gh_grep` | enabled | Lightweight remote (GitHub code search). |

Toggle by editing `enabled` in the jsonc, or use a project-local `opencode.jsonc` override.

## Custom commands (OpenCode)

Installed to `~/.config/opencode/command/`:

- `/create-prd` — generate a PRD from a feature description
- `/generate-tasks` — generate a task list from requirements/PRD

## Environment variables

- `TAILOR_OP_ACCOUNT` — 1Password account hosting tailor's items. Default: `chamberofsecrets.1password.com`.
- `TAILOR_OP_TIMEOUT` — seconds any single `op` call may take before tailor gives up on it (for example, while the app waits to be unlocked). Default: `20`.
- `TAILOR_RETRIES` — attempts for network operations before a step reports failure. Default: `3`.
- `TAILOR_AI_PROXY_ITEM` — 1Password item name or UUID supplying the shared Claude/Codex proxy client key and URL. Default: `CLI Proxy API`.
- `TAILOR_GITHUB_SSH_KEY_ITEM_UUID` — 1Password SSH Key item used for the local GitHub key. Default: `dp7wepzy37ou6dirqsc4jmje7i`.
- `TAILOR_GITHUB_SSH_KEY_PATH` — local path for the GitHub-only SSH private key. Default: `~/.ssh/id_ed25519_github`.

## What's intentionally NOT in tailor

Per the "tailor builds on Omarchy baseline" principle, these belong upstream:

- Installing system utilities (jq, curl, gh, docker, mise) — Omarchy.
- Configuring node via mise — Omarchy.

- Installing the AI CLIs (claude, codex, opencode, ...) — Omarchy.

If a fresh-machine tailor run fails the preflight on one of these, the fix is to file an Omarchy issue / re-run Omarchy install — not to add install logic here.
