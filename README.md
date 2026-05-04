# Tailor

Personal environment provisioning on top of Omarchy. Re-runnable, idempotent, opinionated.

Tailor doesn't try to do everything — it builds on what Omarchy already provides (mise, node, claude/codex/pi/etc., AUR helpers) and layers in personal customization: env vars, SSH hosts, AI skills, internal CLI tooling, and per-tool config.

## Quick start

1. Install [1Password CLI](https://developer.1password.com/docs/cli/get-started/) and enable the desktop-app integration (Settings → Developer → "Integrate with 1Password CLI").
2. Sign in to 1Password (`op vault list` should succeed).
3. Run:
   ```bash
   ./tailor.sh
   ```

The pre-flight bails with clear hints if anything's missing. First run on a fresh machine will tell you exactly what 1Password items to create.

## Pipeline

`tailor.sh` runs these in order. Each is idempotent and can be invoked standalone.

| Script | What it does |
|---|---|
| `setup-preflight.sh` | Verifies Omarchy, mise/node/npm, jq/curl/gh/docker, AI CLIs (claude/codex/pi/gemini/copilot/opencode/playwright-cli/ghui), and 1Password auth. Bails on missing prerequisites. |
| `setup-cleanup.sh` | Removes stale Tailor-managed artifacts from previous versions, like the old unofficial `figma-developer-mcp` install/config. |
| `setup-envs.sh` | Reads 1P item `tailor-envs` → writes `~/.config/hypr/envs.conf`. |
| `setup-ssh.sh` | Reads 1P Server items tagged `tailor-ssh` → writes `~/.ssh/config` (managed block with markers; preserves any hand-written entries above/below). Always includes `Host * IdentityAgent ~/.1password/agent.sock`. |
| `setup-zsh.sh` | Installs `omarchy-zsh` package and runs `omarchy-setup-zsh` (idempotent — detects template signature in `.zshrc`/`.bashrc`). |
| `setup-pi.sh` | Forces canonical Pi defaults (provider/model/thinking) and installs the canonical extension list. |
| `setup-ai-skills.sh` | Installs canonical universal skills (firecrawl, rails-skills, skill-creator) via `npx skills add`. Sweeps rejected skills (find-skills, agent-browser). |
| `setup-cli-tools.sh` | Installs internal CLIs (cortex, nebula, hey, fizzy, basecamp) and runs each one's `skill install` to register the bundled agent skill. |
| `setup-cli-auth.sh` | For token-based CLIs (cortex/nebula/fizzy): pulls token + config from 1P → writes the CLI's config file. For OAuth CLIs (claude/codex/pi/hey/basecamp): actively verifies auth by exercising the API. Loops with a `gum` prompt to recheck after fixing. |
| `setup-codexbar.sh` | Installs `codexbar-waybar` (built from `~/Work/codexbar-waybar`), runs `codexbar-waybar-install`, and warns if `codexbar-tui` is installed. |
| `setup-ai.sh` | Claude Code attribution settings, OpenCode config + slash commands. |

## 1Password items used

All in `chamberofsecrets.1password.com` by default (override via `TAILOR_OP_ACCOUNT`).

| Item | Type | Fields | Used by |
|---|---|---|---|
| `tailor-envs` | Secure Note | one text/concealed field per env var (label = name, value = value) | `setup-envs.sh` |
| `Cortex API` | API Credential | `token`, `tenant_id`, `api_url` | `setup-cli-auth.sh` |
| `Nebula API` | API Credential | `token`, `workspace`/`workspace_url`/`domain`/`scheme`/`api_url` | `setup-cli-auth.sh` |
| `Fizzy API` | API Credential | `token`, `account`, `api_url` | `setup-cli-auth.sh` |
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

## What's intentionally NOT in tailor

Per the "tailor builds on Omarchy baseline" principle, these belong upstream:

- Installing AI CLIs (claude, codex, pi, gemini, copilot, opencode, playwright-cli, ghui) — Omarchy does this via `omarchy-npx-install` and `omarchy-base.packages`.
- Installing system utilities (jq, curl, gh, docker, mise) — Omarchy.
- Configuring node via mise — Omarchy.

If a fresh-machine tailor run fails the preflight on one of these, the fix is to file an Omarchy issue / re-run Omarchy install — not to add install logic here.
