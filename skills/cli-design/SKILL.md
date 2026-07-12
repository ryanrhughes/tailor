---
name: cli-design
description: Best practices for designing and building command-line applications, distilled from clig.dev, the GitHub/Heroku CLI style guides, the 37signals CLI rubric, and our own CLIs (mosaic, nebula, fizzy, cortex). Covers command grammar, output contracts (--json, stdout/stderr discipline), typed exit codes, actionable errors, config precedence, credential storage, agent-first features (embedded SKILL.md, --agent mode, breadcrumbs), HTTP client patterns, testing, and distribution. Use this skill whenever you are creating a new CLI tool, adding commands or flags to an existing CLI, wrapping an API in a CLI, reviewing or refactoring CLI code, or the user mentions cobra, subcommands, exit codes, JSON output, piping, shell scripting ergonomics, or making a tool usable by AI agents — even if they don't say "CLI".
---

# Building Great CLIs

How to design and build command-line tools that serve humans and AI agents equally well. The core insight of the last few years: **agents are now the heaviest users of CLIs, and the same properties that make a CLI good for shell scripts make it good for agents — but stricter.** A human works around a missing `--json` flag; an agent burns tokens or fails. Every rule below exists because violating it breaks a pipeline, a script, or an agent loop.

## Philosophy

1. **stdout is the API, stderr is the conversation.** Data/results go to stdout; progress, warnings, hints, and errors go to stderr. Piping stdout to `jq` must always yield clean output.
2. **Structured output is the default contract.** Every data-bearing command supports `--json`. The JSON schema is versioned and additive-only — it's an API, treat it like one.
3. **Exit codes are control flow.** Typed, documented, stable exit codes let scripts and agents branch without parsing error text.
4. **Errors are actionable data.** Every error says what happened AND what to do next (the exact command or flag that fixes it), plus a machine-readable code and retryable flag.
5. **Never require interactivity.** Prompt when stdin is a TTY; when it isn't, use defaults or fail fast naming the flag to pass. An agent cannot type "y".
6. **The right thing must be the easy thing.** TTY auto-detection picks human vs machine output; sensible defaults make the zero-flag invocation correct; sidecar state makes repeat invocations flagless.
7. **Surface stability enables automation.** Removing a flag or subcommand is a breaking change. Evolve additively; catch removals in CI.

## Language and framework

Go + cobra is the house default: single binary, trivial cross-compilation, fast startup (a CLI invoked in loops or by agents pays interpreter startup tax on every call). When Go isn't the right fit — performance-critical (Rust/clap), JS-only team (TypeScript/oclif), internal data tooling (Python/Typer) — read **`references/frameworks.md`**. Every rule in this skill is language-independent; only the implementation library changes. For concrete tools worth imitating (gh's `--json` field selection, gws's schema introspection, fzf's dual-mode, ripgrep's defaults), see **`references/exemplars.md`**.

## Command grammar

- **noun → verb**: `app board list`, `app card show 42`, `app config setup`. The resource noun is the parent command, actions are subcommands. This turns agent discovery into deterministic tree search (`app --help` → nouns; `app board --help` → verbs).
- **Standard CRUD verbs everywhere**: `list`, `show`, `create`, `update`, `delete` — plus resource-specific verbs (`close`, `archive`, `duplicate`). Never invent synonyms across resources (`remove` here, `delete` there). Avoid ambiguous siblings like `update` vs `upgrade` for different things.
- **Generous aliases**, applied uniformly across the tree: `list`→`ls`, `show`→`view`, `delete`→`rm`, plural/singular noun aliases (`project`/`projects`/`proj`). Aliases cost nothing and forgive muscle memory.
- **`Use` strings encode the argument shape**: required in `<angle-brackets>`, optional in `[square-brackets]`, repeatable with `...`. Validate arg counts declaratively (`cobra.ExactArgs(1)`), never with hand-rolled length checks.
- **Prefer flags to positional args.** One positional (an ID or file) is fine; two of different kinds is a smell; three is a bug. Positional args can't be reordered, are hard to make optional, and their meaning is invisible at the call site.
- **Kebab-case for multi-word commands and flags** (`media-plan`, `--client-id`). Command name itself: short, lowercase, easy to type, not shadowing common commands.
- Respect POSIX/GNU conventions: `--` terminates option parsing; `-` as a file arg means stdin/stdout; every short flag has a long form; short flags can bundle (`-abc`).

## Output contract

The full spec — formats, JSON envelope, TTY detection, color, pagination — is in **`references/output-contract.md`**. Read it when implementing any output code. The essentials:

- Every data command gets `--json`. For API CLIs, the gold standard is a **JSON envelope**: `{ok, data, summary, breadcrumbs}` on success, `{ok: false, error, code, hint}` on failure, with `--quiet` to strip the envelope to raw data.
- **Auto-detect TTY**: styled/human output on a terminal, JSON when piped. Check `isatty()` per stream. When not a TTY, also disable color, spinners, truncation, pagers, and prompts.
- Honor `NO_COLOR` (disable when set non-empty), `FORCE_COLOR`, `TERM=dumb`, and `--no-color`. Color enhances meaning, never carries it alone.
- Human success output is brief and says what changed, then suggests the next command. Empty result sets print an explicit "No X found." — never nothing. In JSON mode, empty results are `[]`/`{}` — never zero bytes (parsers choke).
- Convenience formats pay for themselves with agents: `--ids-only` (one ID per line), `--count`, built-in `--jq` (embed gojq so jq needn't be installed), `--fields id,name,status` field selection, and NDJSON for streaming large sets.

## Errors and exit codes

- Typed exit code contract (from the 37signals rubric, the strongest scheme in use):
  `0=OK 1=Usage 2=NotFound 3=Auth 4=Forbidden 5=RateLimit 6=Network 7=API 8=Ambiguous`.
  At minimum: 0 success, 1 general failure, distinct codes for usage, not-found, and auth. Document them in help. Keep them stable forever.
- Error values carry `code` (machine string), `message` (human), `hint` (the fix: exact command or flag), and `retryable` (bool). Map HTTP status → typed error in one place (401→Auth+"run `app auth login`", 429→RateLimit+Retry-After, 502/503/504→API+retryable).
- **Every error message includes the fix**: `"API token not configured (set APP_TOKEN, use --token-file, or run \`app config setup\`)"`. Wrap errors with context as they propagate (`fmt.Errorf("reading token file %s: %w", path, err)`).
- Silence the framework's reflexive usage-dump on runtime errors (cobra: `SilenceUsage: true, SilenceErrors: true`); print `Error: <msg>` (+ `Hint:` line) to stderr and exit from ONE place. Commands return errors; they never call `os.Exit` themselves.
- Truncate error bodies from upstream services (a few hundred chars) — a failure must never spew megabytes of HTML into a terminal or an agent's context.

## Accepting input

For any command whose purpose is creating/sending text, resolve input in this order (first non-empty wins):

1. **Named flag** with a semantic name and short form: `--title/-t`, `--message/-m`, `--content/-c` (don't normalize everything to `--message`)
2. **Positional shorthand** when there's exactly one unambiguous text input: `app todo add "Buy milk"`
3. **Stdin** when piped: `cat notes.md | app journal write`
4. **$EDITOR** when interactive and multi-line makes sense

Flag + positional both set → error ("mutually exclusive"), never silently pick one. Missing input → error that shows BOTH forms: `Hint: app todo add "Buy milk"  or  app todo add --title "Buy milk"`. Large payloads get a `--body-file` twin for every `--body` flag, and an `--input-json` escape hatch on every create/update lets callers pass the full raw payload for fields not exposed as flags.

For partial updates (PATCH semantics), **send only the fields the user actually set** — in cobra, gate each field on `cmd.Flags().Changed("name")`. This is the only way to distinguish "set to empty" from "not provided". Refuse a no-op update ("no fields to update").

## Configuration and credentials

Full spec in **`references/config-and-auth.md`**. The essentials:

- **Precedence, lowest→highest: system config → user config file → project config → env vars → flags.** State it in `--help` and README; implement it literally as layered loading in that order.
- Config file at `$XDG_CONFIG_HOME/<app>/` (default `~/.config/<app>/`), written `0600`, dir `0700`. Cache in `~/.cache/<app>`, state (history, update-check stamps) in `~/.local/state/<app>`. Provide `<APP>_CONFIG_DIR` override — it makes tests and sandboxes trivial.
- Env vars are `<APP>_`-prefixed, documented in flag help text right where they apply: `--token string   API token (env: APP_TOKEN)`.
- **Secrets never go in argv** (visible in `ps` and shell history). Offer, in preference order: OS keyring → `--token-file` → env var. Mask secrets in `config show` output (`abcd****wxyz`). `config show` should also attribute where each value came from (flag/env/file/default).
- Loading config never fails on missing credentials; commands that need auth call an explicit `Validate()`/`EnsureConfigured()` guard that produces the actionable error. Read-only commands (`config show`, `version`) skip it.
- Ship `config setup` (interactive wizard that auto-switches to flag-driven when any flag is passed, preserving existing values) and a read-only `doctor` command that checks connectivity/auth/config with pass/warn/fail statuses and hints.

## Destructive operations

Tier the friction to the severity:

- **Mild** (delete one easily-recreated thing): just do it, print what happened.
- **Moderate**: prompt to confirm when TTY; require `--force`/`--yes` when not.
- **Severe** (delete a named resource and its history): require re-typing the resource name — interactively when TTY, or via `--confirm "<exact-name>"` for scripts. A bare `-y` is too easy to cargo-cult.
- Anything destructive or expensive offers `--dry-run` printing a structured preview of what WOULD happen. Agents rely on preview-then-execute.
- Idempotency matters because agents retry: prefer declarative verbs (`ensure`, `sync`), support `--if-not-exists`, and make conflicts detectable via a distinct exit code rather than a generic failure.

## Agent integration

This is what separates a good CLI from a great one in 2026. Full spec in **`references/agent-integration.md`** — read it when adding agent features or authoring the CLI's SKILL.md. The essentials:

- **Ship a SKILL.md embedded in the binary** (`//go:embed`), installed via `<app> skill install` into `~/.agents/skills/<app>/` (+ symlink into `~/.claude/skills/`), with a sha256 freshness check on every run that nudges (stderr, human mode only) when the installed copy is stale.
- `--agent` flag = quiet JSON + all interactive prompts suppressed. `--help --agent` and `<app> commands --json` emit the command tree as structured JSON so agents can discover the surface without docs.
- **Breadcrumbs**: every success response suggests follow-up commands with real values pre-filled. This is the primary agent-chaining mechanism.
- **Token economy**: filtering flags (`--status failed`), `--limit`/`--all` with an explicit truncation notice ("Showing 20 of 143 — use --all"), field selection (`--fields`), batch operations, and high-signal fields. Verbose output burns someone else's context window.
- **Treat agent input as untrusted**: agents hallucinate plausible-looking garbage — validate IDs (no `?`/`#`/`%`/control chars), reject path traversal, validate enums before the network. And if the CLI surfaces user-generated content (emails, comments), that's a prompt-injection vector into the agent reading it — delineate it and warn in the SKILL.md.
- Snapshot the CLI surface to a checked-in file and fail CI on removals.
- API-wrapping CLIs can add `schema <method>` introspection and an optional MCP server mode derived from the same command definitions.

## Architecture (Go house style)

Our CLIs are Go + cobra. Full patterns with code in **`references/go-architecture.md`** — read it before scaffolding a new CLI or adding a resource. The skeleton:

```
main.go                  # tiny: version wiring + cmd.Execute()
cmd/root.go              # root command, persistent flags, Execute() with centralized exit
cmd/<resource>/          # one package per resource noun, exposing NewCmd() *cobra.Command
internal/api/            # HTTP client: typed errors, retries, User-Agent
internal/config/         # layered load, validate guards
internal/output/         # ONE formatter enforcing the output contract
skills/<app>/SKILL.md    # embedded agent skill
e2e/                     # subprocess tests asserting the output contract
```

Key patterns: `NewCmd(...)` constructors receiving pointers to global flags (no package globals, no import cycles); command logic extracted into a callable `Run(cfg, opts, stdout, stderr)` so commands can compose in-process; `PathEscape` every URL segment; retries only for idempotent methods, always honoring `Retry-After`.

## Testing

- **Unit-test the logic, not the cobra wiring**: parsers, path/query builders, formatters, error mapping — table-driven, no network. HTTP layer against `httptest.Server`.
- **E2E tests run the real binary as a subprocess** and assert the *contract*: `--quiet` output contains no envelope keys, `--ids-only` lines aren't JSON, exit codes match the documented table, stdout stays clean when piped. These are the tests that catch what agents depend on.
- Surface snapshot test: regenerate the command/flag inventory and diff against the checked-in copy; a removal fails the build.

## Distribution

Full spec in **`references/distribution.md`** — read it when setting up builds, releases, install scripts, self-update, or update checks. The essentials: version via ldflags from `git describe`; Makefile with `build/install/link/fmt/vet/test`; cross-compile with `CGO_ENABLED=0` + SHA256SUMS; `curl | bash` installer that verifies checksums; self-update only via explicit `upgrade` command with mandatory checksum verification and atomic rename; passive update check ≤ once/24h, async, stderr-only, silent-on-failure, with an opt-out env var; telemetry only with disclosure + `DO_NOT_TRACK` support.

## Checklist for a new CLI

Before calling a CLI done, verify:

- [ ] `--json` on every data command; stdout clean when piped; empty results emit `[]`/`{}`
- [ ] All progress/warnings/errors on stderr; success messages suppressed in JSON mode
- [ ] Typed exit codes, documented, tested in e2e
- [ ] Every error names its fix; auth errors name the login command
- [ ] No prompt ever blocks a non-TTY run; `--force`/`--yes`/`--confirm` escape hatches exist
- [ ] Config precedence file < env < flags, documented and implemented in that order
- [ ] Secrets: keyring or `--token-file` or env — never a bare required `--token`; masked in `config show`
- [ ] `NO_COLOR`, `TERM=dumb`, non-TTY all disable color/animation
- [ ] Destructive ops: typed-name confirmation + `--dry-run` where meaningful
- [ ] SKILL.md embedded, installable, freshness-checked
- [ ] `-h`/`--help` everywhere, examples in every leaf command's help
- [ ] `--version` works; User-Agent sent on every HTTP request
- [ ] `doctor` command for health, `config setup` for onboarding
- [ ] E2E contract tests + surface snapshot in CI
