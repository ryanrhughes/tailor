# The Output Contract

How a CLI writes output is its most load-bearing design decision. Scripts, pipelines, and agents all consume stdout programmatically; humans read whatever the terminal shows. One codebase must serve both without either audience configuring anything.

## stdout / stderr discipline

**stdout = the payload. stderr = everything else.**

| stdout | stderr |
|---|---|
| The requested data (JSON, table, IDs) | Progress ("Uploading 3 files...") |
| Human result summary ("Published foo/bar") | Warnings, deprecation notices |
| | Errors and hints |
| | Update-available notices |
| | Row-count summaries ("5 projects") |
| | Interactive prompts |

The test: `app list --json | jq .` must always work, and `app publish 2>/dev/null` must still print the result. Progress lines are additionally gated on human mode — in JSON mode, suppress them entirely rather than relying on redirection:

```go
if !jsonMode {
    fmt.Fprintf(os.Stderr, "Creating session for %s (%d files)...\n", loc, n)
}
```

Success messages (`PrintSuccess`) go to **stderr** and are suppressed under `--json` — the JSON body already communicates success.

## Format selection

Resolve the output format in one central place, from flags first, then TTY detection:

```
--json      → JSON (envelope)
--quiet     → raw JSON data, no envelope
--ids-only  → one ID per line
--count     → a single integer
--markdown  → GitHub-flavored markdown
--styled    → force ANSI styling (like FORCE_COLOR)
(none)      → Auto: styled/human if stdout is a TTY, JSON if piped
```

Format flags are mutually exclusive — error if two are passed. `isatty()` is checked **per stream**: stdout piped with stderr on a terminal should still show colored progress on stderr. Treat "machine output" broadly: any format flag, `--agent`, or non-TTY stdout/stdin all suppress prompts, spinners, and notices.

A simpler tier (fine for small tools): skip auto-detection, make `--json` the explicit switch, human output otherwise. If you do this, keep everything else in this document the same. What you may NOT do is make JSON impossible.

## The JSON envelope (API CLIs)

For CLIs wrapping an API, wrap every response in a stable envelope:

```json
{
  "ok": true,
  "data": [ ... ],
  "summary": "5 boards",
  "notice": "Showing 20 of 143 results (use --all for complete list)",
  "breadcrumbs": [
    {"action": "show", "cmd": "app board show <id>", "description": "View a board"}
  ]
}
```

Errors:

```json
{"ok": false, "error": "Not Found", "code": "not_found", "hint": "Run `app board list` to see valid IDs"}
```

Why an envelope: agents can branch on `ok` without checking exit codes AND get navigation (`breadcrumbs`) and truncation warnings (`notice`) in-band. `--quiet` strips the envelope for pipelines that just want the data.

Envelope rules:
- `ok` is always present. `data` omitted when empty is fine, but a command that "returns nothing" (delete, archive) still emits the envelope — **never zero bytes in JSON mode** (nebula's `PrintJSON` prints `{}` for empty bodies; there's a test for it, because agent parsers choke on empty output).
- **The CLI owns its schema.** Present stable snake_case keys even if the upstream API uses camelCase; the CLI's JSON is a contract independent of the server's wire format.
- **Preserve large-integer IDs**: decode with `json.Decoder.UseNumber()` (or equivalent) so 64-bit IDs don't get mangled through float64.
- Schema changes are additive-only. If you must break, that's a major version.

## Human output

- **Brief on success, explicit about state change**: `Published mosaic/cli (version 14)`. If the command changed state, say what changed and suggest the inspection/next command.
- Lists: aligned columns via tabwriter, or simple `label: value` pairs for detail views. **No decorative borders** — every row should be one greppable line. When piped, switch to tab-separated, no header, no truncation, no color (tabs because `cut` defaults to them).
- **Empty states are explicit**: `No artifact locations found.` — silence looks like a hang or a bug.
- Truncation always announces itself: `Showing 20 of 143 results (use --all for complete list)` — in human mode on stderr, in JSON mode as `notice`.
- Optional/missing values render as `-`, booleans as `yes`/`no`. Truncate long cells rune-aware with `…`.
- Page long output only when interactive; honor `$PAGER`, use `less -FIRX` defaults. Never page when piped.

## Color

- Color only when: stream is a TTY, AND `NO_COLOR` is unset/empty, AND `TERM != dumb`, AND `--no-color` not passed. `FORCE_COLOR`/`--styled`/`CLICOLOR_FORCE` override TTY detection (for `less -R`, CI logs). Per no-color.org: env vars set *defaults*; explicit flags win.
- Only the 8 basic ANSI colors are reliable across terminals. Color must never be the sole carrier of meaning — piped output states things explicitly ("state: closed") that color merely reinforced.
- No spinners/animations when not a TTY; emit occasional plain progress lines instead.
- Deliberately colorless is a valid choice for an agent-first tool (mosaic-cli has zero color) — simplicity beats styling if humans are the minority audience.

## Convenience formats

Cheap to add, disproportionately loved by scripts and agents:

- `--ids-only`: one ID per line → `app card list --ids-only | xargs -n1 app card close`
- `--count`: just the integer
- `--jq '<expr>'`: embed gojq so no external jq is needed; implies JSON mode; never pipe *error* envelopes through the user's filter
- `--fields id,name,status` (or gh's variant: `--json` takes a field list, and passing no list prints the available field names — a self-discovering schema). Field selection protects context windows better than post-hoc jq filtering, and when the upstream API supports field masks, pass them through so the *server* trims the payload.
- `--limit N` / `--all` / `--page N` on every list command. `--limit` and `--all` together is an error.
- For large/streaming result sets, offer NDJSON (one JSON object per line): stream-processable without buffering a giant array, and both Unix tools and agents handle it natively. `--page-all` emitting one object per page is the common shape.

## Startup and responsiveness

Print *something* within 100ms for long operations (validation, "Connecting..."). Total startup under 500ms feels good; 2s+ feels broken. Never make a blocking network call (update check, telemetry) that a command doesn't need — do those async with a 1–2s cap, cached, silent on failure.

## Exit codes (full table)

```
0 = OK          success
1 = Usage       bad flags/args/invocation (cobra parse errors coerced here)
2 = NotFound    resource doesn't exist
3 = Auth        authentication missing/invalid
4 = Forbidden   authenticated but not allowed
5 = RateLimit   429, Retry-After honored
6 = Network     connection/DNS/timeout
7 = API         upstream 5xx or unexpected response
8 = Ambiguous   query matched multiple resources
```

Map exit in exactly one place (root `Execute()`); commands return typed errors. Avoid shell-reserved codes for other meanings: 126/127 (command not found/not executable), 128+N (signals; 130 = Ctrl-C). E2E tests assert the table. HTTP→code mapping lives beside the client: 401→3, 403→4, 404→2, 429→5, 5xx→7 (+retryable), transport error→6.
