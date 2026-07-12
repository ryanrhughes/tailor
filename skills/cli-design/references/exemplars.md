# Exemplars — CLIs to Steal From

When designing a feature, check how these tools do it first. Each earns its place for a specific pattern.

## gh (GitHub CLI) — structured output done right
Go/cobra. The gold standard for machine output: `--json` takes a comma-separated **field list**, and omitting the list prints the available field names (self-discovering schema); `--jq` evaluates jq expressions via embedded gojq (no jq install needed); `--template` for Go-template rendering. Also exemplary: documented exit codes (0/1/2/4), a `help environment` topic listing every env var with its precedence chain (`GH_EDITOR > GIT_EDITOR > VISUAL > EDITOR`), keyring credential storage with `gh auth token` for scripts, and update notices ≤ once/24h on stderr with `GH_NO_UPDATE_NOTIFIER`. Piped output switches to tab-separated, no truncation, no header.

## fizzy (Basecamp) — the agent contract
Go/cobra on the shared basecamp/cli library. The reference implementation of this skill's highest tier: JSON envelope with breadcrumbs, 9 typed exit codes, `--agent` / `--help --agent` / `commands --json`, embedded SKILL.md with installer and freshness check, SURFACE.txt compat-checked in CI, method-aware retries, e2e contract tests. Study alongside mosaic-cli (stdout/stderr discipline, secure self-update, sidecar state), nebula-cli (config guards, multipart uploads, query normalization), and cortex-cli (Changed() PATCH gating, typed-name delete confirmation).

## gws (Google Workspace CLI) — agent-first API wrapping
Rust/clap. Builds its entire command tree at runtime from Google's API Discovery Document — new endpoints appear automatically. `gws schema <method>` dumps machine-readable method signatures (params, body, response, scopes); `--json` request bodies map 1:1 to API schemas (zero translation loss for agents); MCP server mode (`gws mcp -s drive,gmail`) derived from the same source; input hardening against path traversal/control chars/double-encoding; `--sanitize` pipes responses through a content filter. The model for "the CLI is the canonical API documentation."

## ripgrep — sensible defaults
Rust. The common case needs zero flags: respects .gitignore, skips binaries, smart case. Proof that opinionated defaults beat configurability — design the zero-flag invocation first, then add flags for deviations.

## fzf — dual-mode interactivity
Go. Interactive fuzzy finder on a TTY, `--filter` for non-interactive/pipeline use, stdin→stdout composability throughout. The model for how every interactive feature should degrade: same binary, same semantics, no TTY required.

## starship — config-driven extensibility
Rust. Users extend behavior through a well-documented TOML config, not code or plugins. When you're tempted to add a plugin system, try a config schema first.

## lazygit — when a TUI is right
Go/bubbletea. A full TUI beats flags when the task is visual and stateful (staging hunks, browsing logs). But TUI is a *mode*, not the tool: the underlying operations must stay scriptable.

## Anti-exemplar: AWS CLI v2's pager default
Shipped output-to-pager as the default in 2019; the pager waited for keypresses and broke thousands of CI pipelines overnight. The canonical lesson in why interactivity must be TTY-gated and why changing output behavior is a breaking change.
