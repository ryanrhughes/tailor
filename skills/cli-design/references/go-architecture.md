# Go CLI Architecture (house style)

Patterns extracted from mosaic-cli, nebula-cli, fizzy-cli, and cortex-cli. Framework: **cobra** (+ pflag). Keep dependencies minimal — stdlib HTTP, `yaml.v3` for config, charmbracelet `huh`/`lipgloss` only where interactive UI genuinely helps.

## Layout

```
main.go                     # tiny: version wiring + cmd.Execute()
Makefile                    # build install link unlink clean fmt vet test
cmd/
  root.go                   # rootCmd, persistent flags, Execute(), update notice
  <resource>/<resource>.go  # one package per resource noun
  cmdutil/                  # shared helpers: Setup, BuildPath, BuildQuery, validators
  config/  skill/           # meta commands
internal/
  api/client.go             # HTTP client, typed APIError
  config/config.go          # layered load + guards
  output/output.go          # THE formatter — all output goes through here
  version/version.go        # Version var (own package: no import cycles, usable by client)
skills/<app>/SKILL.md       # embedded agent skill
e2e/                        # subprocess contract tests
```

`main.go` stays ~10 lines. All logic lives in packages so it's testable. `internal/` never imports `cmd/`.

```go
func main() {
    if version == "dev" {
        if info, ok := debug.ReadBuildInfo(); ok && info.Main.Version != "(devel)" {
            version = info.Main.Version
        }
    }
    cmd.SetVersion(version)
    cmd.Execute()
}
```

## The NewCmd constructor pattern

Commands are constructed functions receiving pointers to the global flags — no package-level mutable state, no import cycles, independently testable:

```go
// cmd/publish/publish.go
func NewCmd(flagBaseURL, flagToken, flagTokenFile *string, flagJSON *bool) *cobra.Command {
    var to string
    cmd := &cobra.Command{
        Use:     "publish <file-or-directory>",
        Short:   "Publish a static artifact",
        Args:    cobra.ExactArgs(1),
        Example: `  app publish ./site
  app publish report.html --to reports/q3 --json`,
        RunE: func(cmd *cobra.Command, args []string) error { ... },
    }
    cmd.Flags().StringVar(&to, "to", "", "Destination location")
    return cmd
}
```

Root registers everything and centralizes exit:

```go
rootCmd := &cobra.Command{
    Use:           "app",
    SilenceUsage:  true,   // no usage wall on runtime errors
    SilenceErrors: true,   // we format errors ourselves
}
rootCmd.PersistentFlags().StringVar(&flagToken, "token", "",
    "API token (env: APP_TOKEN; prefer env or --token-file)")

func Execute() {
    if err := rootCmd.Execute(); err != nil {
        e := output.AsError(err)                    // coerce to typed error
        fmt.Fprintln(os.Stderr, "Error: "+e.Message)
        if e.Hint != "" { fmt.Fprintln(os.Stderr, "Hint: "+e.Hint) }
        os.Exit(e.ExitCode())
    }
}
```

Commands **return errors** (`RunE`); they never call `os.Exit`. Coerce cobra's own parse errors to the Usage exit code.

**Reusable Run functions**: extract command logic into `Run(cfg Config, opts Options, stdout, stderr io.Writer) (Result, error)` with a typed `Options`/`Result`. Other commands compose in-process (`contract init --publish` calls `publish.Run`) instead of shelling out, and tests inject buffers.

## PATCH semantics: the Changed() idiom

Send only fields the user actually set — the only way to distinguish "clear this field" from "didn't mention it":

```go
payload := map[string]any{}
if cmd.Flags().Changed("name")   { payload["name"] = name }
if cmd.Flags().Changed("due-on") { payload["due_on"] = dueOn }
if len(payload) == 0 {
    return fmt.Errorf("no fields to update")
}
```

Every create/update also gets `--input-json` — a raw-payload escape hatch overriding typed flags, for fields not (yet) exposed. Pair `--body` with `--body-file`; make attachment flags repeatable (`StringArrayVar`) and also accept comma-separated values.

Declare exclusivity, don't discover it: `cmd.MarkFlagsMutuallyExclusive("public", "private")`, plus manual cross-checks with actionable messages where cobra can't express the rule.

## HTTP client

```go
type Client struct {
    httpClient *http.Client   // Timeout: 30–60s; uploads/downloads get their own longer-lived client
    baseURL    string          // trailing slash trimmed
    token      string
}

func (c *Client) do(req *http.Request) { 
    req.Header.Set("Authorization", "Bearer "+c.token)
    req.Header.Set("Accept", "application/json")
    req.Header.Set("User-Agent", "app-cli/"+version.Version)   // ALWAYS — servers need to know who's calling
    // Content-Type: application/json only when there's a body
}
```

- **Typed API errors** — one struct, one place mapping status → exit code:

```go
type APIError struct {
    StatusCode int
    ErrorType  string           `json:"error"`
    Message    string           `json:"message"`
    Errors     map[string]any   `json:"errors,omitempty"`
}
func (e *APIError) Error() string {
    return fmt.Sprintf("%s: %s (HTTP %d)", e.ErrorType, e.Message, e.StatusCode)
}
```

  Non-JSON error bodies: truncate to a few hundred chars (`io.LimitReader`); optionally scrape `<h1>`/message divs from HTML error pages. Never surface raw HTML.
- **Retries, method-aware**: 429 always retried honoring `Retry-After` (seconds or HTTP-date, capped ~300s); 5xx and transport errors retried only for idempotent methods (GET/PUT/DELETE); exponential backoff `1<<attempt` seconds; rewind bodies via `req.GetBody`. Small tools may skip retries entirely — but then a distinct Network exit code matters more.
- **URL safety**: `PathEscape` every path segment individually (never the joined string); query builders drop empty values. Both are pure functions — unit-test them.
- **Timeouts per use case**: default 30–60s; background update check 1–2s; large file transfers 10min. Presigned-URL uploads use a separate bare client (no API bearer).
- Multipart uploads: detect Content-Type by extension, fall back to sniffing the first 512 bytes.

## Output formatter

One package owns the contract (see `output-contract.md`). Minimum viable core:

```go
func PrintJSON(v any) error {              // stdout, 2-space indent, {} for empty
    enc := json.NewEncoder(os.Stdout)
    enc.SetIndent("", "  ")
    return enc.Encode(v)
}
func PrintError(msg string)   { fmt.Fprintln(os.Stderr, msg) }
func PrintSuccess(msg string) { if !jsonMode { fmt.Fprintln(os.Stderr, msg) } }
```

Full tier adds the envelope, format enum (`Auto/JSON/Quiet/IDs/Count/Markdown/Styled`), per-stream TTY detection, tabwriter tables, `Truncate` (rune-aware), `FormatOptional` (`-` for nil, `yes`/`no` for bools).

## Interactivity

```go
func interactiveStdin() bool {
    info, err := os.Stdin.Stat()
    return err == nil && info.Mode()&os.ModeCharDevice != 0
}
```

Prompt only when true AND not in machine mode; otherwise fail with the flag to pass. Interactive flows use charmbracelet `huh`; every prompt has a flag equivalent. Ctrl-C always works; say something, clean up fast, second Ctrl-C skips cleanup.

## Safety details worth stealing

- **Path traversal defense** when writing server-supplied paths to disk: reject `..`, empty, and backslash segments before extracting archives or downloads.
- **Harden agent-supplied identifiers**: reject control chars, `?`, `#`, and `%` in resource IDs before building URLs — agents hallucinate IDs with embedded query strings and pre-encoded characters (see `agent-integration.md`).
- **Slugify user-supplied names** destined for URLs/paths: lowercase, `[a-z0-9]`, collapse runs to dashes.
- **Deterministic manifests**: sort file lists, normalize to forward slashes (`filepath.ToSlash`), hash with SHA-256 — enables content-addressed dedup (server skips unchanged files).
- **Visibility ratchets**: a republish may carry forward `public` but must never silently flip public→private (or vice versa) without an explicit flag.
- Soft warnings vs hard errors: malformed-looking token → warn and continue; missing token → actionable error.

## Testing

- **Unit** (table-driven, no network): path/query builders, date/enum validators, query normalizers, formatters, `parseRetryAfter`. Fuzz parsers that consume external input.
- **HTTP layer**: `httptest.Server` asserting auth headers, paths, multipart fields, content-type detection.
- **Command layer**: inject a mock client (`SetTestModeWithSDK(mock)`), capture output to a buffer, parse it back as the envelope, assert. Gotcha: JSON round-trips turn `int` into `float64`.
- **E2E** (`e2e/`): build the real binary, run as subprocess via a small harness returning stdout/stderr/exit code + parsed JSON. Assert the *contract*: `--quiet` has no `ok` key, `--ids-only` lines aren't JSON, `--count` is an integer, exit codes match the table, stdout is clean when piped. Gate on env creds (`APP_TEST_TOKEN`), skip otherwise.
- **Surface snapshot**: `SURFACE.txt` regenerated by a `-generate` test; CI diffs and fails on removals.
- CI: test + golangci-lint + `govulncheck` + gitleaks + e2e + surface check. Race detector on.

## Makefile (minimum targets)

```make
VERSION := $(shell git describe --tags --always --dirty 2>/dev/null || echo dev)
LDFLAGS := -ldflags "-s -w -X $(MODULE)/internal/version.Version=$(VERSION)"

build:    ## go build $(LDFLAGS) -o bin/app .
install:  ## copy to ~/.local/bin
link:     ## symlink bin/app into ~/.local/bin (dev)
unlink: clean: fmt: vet: test:
```
