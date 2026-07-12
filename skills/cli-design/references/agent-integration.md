# Agent Integration

AI agents are now the heaviest CLI users. They discover tools by running `--help`, chain commands by parsing output, branch on exit codes, and retry on failure. Everything in the base contract (JSON output, typed exit codes, non-interactivity) is the foundation; this file covers the features built on top.

Why CLI over MCP for most tools: MCP tool definitions cost ambient context tokens before first use; a CLI costs nothing until invoked, models are pre-trained on shell usage, shell history is an audit trail, and OS permissions apply. Rule of thumb: if a human would use a CLI for it, an agent should too.

## The embedded SKILL.md (house pattern — our strongest differentiator)

Ship the agent documentation *inside the binary* and give it a lifecycle:

1. **Author** `skills/<app>/SKILL.md` in the repo (structure below).
2. **Embed** it: `//go:embed <app>/SKILL.md` → the binary is self-documenting even offline.
3. **Install**: `<app> skill install` writes it to `~/.agents/skills/<app>/SKILL.md` (the cross-agent location used by Claude Code, Cursor, Codex, Copilot, Gemini CLI, OpenCode...) and optionally symlinks into `~/.claude/skills/<app>/`. Support global vs project-local scope. `skill show` prints it.
4. **Freshness check**: a `PersistentPreRun` on every command sha256-compares the embedded copy against installed copies and nudges on drift — stderr, human mode only, never for `skill` subcommands themselves, silent on any error. Auto-refresh on version change is even better.
5. Retire legacy skill dirs on install if the tool was renamed — agents must never load two.

### What goes IN the SKILL.md

Front matter: `name` (lowercase-hyphen, matches dir) and a `description` packed with trigger keywords — the phrases users actually say ("project management, task tracking, work item, gantt, invoice..."). Then:

- **When to use this skill** — bullet list of intents
- **Setup** — install one-liner, the env vars needed, how to verify (`doctor`)
- **Key conventions** — "always use `--json`", ID semantics (cards use *number*, everything else *id*), date formats, exit codes
- **Bootstrap checklist** — the ordered first commands (`config show` → `workspace list` → ...), and *what not to guess* when discovery fails
- **Resource reference** — per-resource CRUD examples with exact enum values (agents can't infer valid values from flag names)
- **Common workflows** — multi-step recipes chaining commands with `jq`, because the unit of agent work is the workflow, not the command
- **Gotchas** — real semantic traps: fields that go stale after a toggle, endpoints that silently no-op, double-charge risks. Domain knowledge an agent cannot infer from `--help` is the highest-value content
- **Safety rules** — "never publish secrets/.env", "stop and ask the user when X"

Keep it under ~500 lines / 5000 tokens; small and focused beats comprehensive. Progressive disclosure: the description is always loaded (~100 tokens), the body only on activation.

## Programmatic discovery

- **`--help --agent`**: emit the command's help as JSON — name, description, flags (with types and defaults, inherited flags included), subcommands. Prose help is for humans; agents want the schema.
- **`<app> commands --json`**: the full command catalog in one call — categories, every command, every flag. An agent can plan a workflow without N help invocations.
- **Agent notes via annotations**: per-command hints for agents (cobra `Annotations`) surfaced in the JSON help.
- **`--agent` flag**: quiet JSON output + every interactive prompt suppressed (confirmations auto-fail with the flag to pass instead). Composable with `--markdown`, conflicts with `--styled`.
- **Schema introspection for API-wrapping CLIs**: `<app> schema <method>` dumps the underlying method signature — params with types, request body shape, response type, required scopes — as JSON (the gws pattern). The CLI becomes the canonical, always-current API documentation; far cheaper than stuffing API docs into a prompt. For complex payloads, pair it with the `--input-json` escape hatch: LLMs generate schema-conformant JSON easily but struggle to map nested structures onto flat flag namespaces.

## Breadcrumbs

Every success envelope includes suggested next commands **with real values pre-filled**:

```json
"breadcrumbs": [
  {"action": "cards",   "cmd": "app card list --board 8412", "description": "List cards on this board"},
  {"action": "invite",  "cmd": "app board invite 8412 --email <email>", "description": "Invite a member"}
]
```

This is navigation, not decoration — it's the primary mechanism by which an agent chains from one command to the next without re-reading docs. Mutations also include `context.location` (the resource path just touched).

## Token economy

Output is spent from someone else's context window:

- **Filter server-side, not in the agent**: `--status failed --assignee me` beats dumping everything through jq.
- **`--limit` defaults + explicit truncation notices**: `"Showing 20 of 143 results (use --all for complete list)"` — never silently truncate; silent truncation reads as "that's everything".
- **Batch operations** (`batch-update --input-json '{"changes": [...]}'`, `delete --selector app=old`) — one call beats fifty.
- High-signal fields first: names alongside UUIDs, human-readable states. Offer `--ids-only`/`--count` when that's all the caller needs.
- Error messages are prompt engineering: specific, actionable, naming the exact flag or command that fixes the problem.

## Idempotency and retries

Agents retry failed operations and verify with follow-up reads:

- Prefer declarative verbs (`ensure`, `sync`, `apply`) or `--if-not-exists` over bare `create`.
- Conflicts get a **distinct exit code / error code** (`already_exists` + the existing ID in the error data) so a retry loop can branch instead of failing.
- Every mutation must be observable afterwards via a `show`/`status` command.
- `--dry-run` with structured diff output for anything destructive or expensive — agents do preview-then-execute.

## The agent is not a trusted operator

Agents don't typo — they hallucinate *plausible-looking garbage*. Treat agent-supplied input like untrusted web input:

- **Path traversal**: reject `..`, canonicalize paths, sandbox file output to the working directory
- **Control characters**: reject anything below ASCII 0x20 in identifiers and names
- **Embedded query params**: reject `?` and `#` inside resource IDs (an agent will happily pass `abc123?limit=5` as an ID)
- **Double encoding**: reject `%` in resource names — agents pre-encode strings that your HTTP layer then encodes again; percent-encode exactly once, at the HTTP layer
- Validate enums and formats *before* the network call, with errors naming the valid values

And the reverse direction — **response sanitization**: if the CLI surfaces untrusted content (emails, comments, user-generated docs), that content is a prompt-injection vector into the agent reading it ("Ignore previous instructions..."). At minimum, clearly delineate user-generated content in output, and warn in the SKILL.md that output may contain untrusted content. High-security contexts can pipe responses through a content filter (`--sanitize`).

## MCP server mode (optional tier)

For API-wrapping CLIs that agents use heavily, `<app> mcp` can expose commands as typed MCP tools over stdio — structured invocation with no shell escaping or output parsing. When to bother: agents without shell access, or hosts that strongly prefer MCP. Keep the CLI primary (MCP definitions cost ambient context tokens; the CLI costs nothing until invoked). Rules if you build it:

- Derive tool definitions from the same source as the cobra commands — one source of truth, no drift
- Support subsetting (`mcp --services drive,gmail`); every exposed tool costs ~50–100 schema tokens in the host's context
- The typed input schema doubles as validation before execution

## Surface stability

Agents memorize your CLI's surface (in skills, in prompts, in fine-tuning). Removals break silently and catastrophically:

- Generate a surface snapshot (`SURFACE.txt`: one typed line per `CMD`/`FLAG`/`ARG`/`SUB`) from the command tree; regenerate via a `-generate` test flag; **CI fails if anything was removed**. Additions are fine.
- Renames keep the old name as a hidden alias/deprecated flag for at least one major version.
- Keep JSON field names and types consistent across commands (never `age: 259200` in one command and `age: "3 days"` in another); dates in ISO 8601.

## Claude Code plugin (optional, highest tier)

A `.claude-plugin/` dir with `plugin.json` and a `SessionStart` hook that runs a lightweight liveness/auth check and primes the session with CLI context. `<app> setup claude` installs it via marketplace. Worth it for CLIs agents use constantly; the SKILL.md alone covers most of the value.
