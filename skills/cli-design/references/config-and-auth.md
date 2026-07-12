# Configuration and Credentials

## Precedence

Lowest to highest — later layers overwrite earlier ones:

```
1. Built-in defaults
2. System config        (/etc/xdg/<app>/, rarely needed)
3. User config file     (~/.config/<app>/config.yaml)
4. Project config       (.<app>.yaml at repo root — walk up to git root)
5. Environment variables (<APP>_*)
6. Flags                 (--token, --url, ...)
7. --token-file          (reads the file, trumps --token)
```

Implement it literally as layered loading in this order — read the file, then overwrite from env, then overwrite from flags. State the precedence in the root command's `Long` help and the README, identically.

Why this order: config files are durable intent, env vars are session intent, flags are *this-invocation* intent. The more ephemeral and explicit the mechanism, the higher it wins. Agents rely on flags being deterministic overrides.

Subtleties:

- **Flag defaults must be empty**, not the real default. The real default lives in the config layer, so the loader can distinguish "user passed the default value" from "user passed nothing". (`--url` defaults to `""`; after layering, `if cfg.URL == "" { cfg.URL = DefaultURL }`.)
- When two config fields can conflict (e.g. `--workspace` subdomain vs `workspace_url` full URL), reconcile explicitly: passing one clears the stored other. Never let two sources silently disagree.
- Legacy env var names: keep accepting them as fallbacks (`APP_API_TOKEN` after `APP_TOKEN`), document them as deprecated.

## File locations (XDG)

| Purpose | Env override | Default |
|---|---|---|
| Config | `$XDG_CONFIG_HOME/<app>/` | `~/.config/<app>/` |
| Cache | `$XDG_CACHE_HOME/<app>/` | `~/.cache/<app>/` |
| State (history, update-check stamp) | `$XDG_STATE_HOME/<app>/` | `~/.local/state/<app>/` |
| Data | `$XDG_DATA_HOME/<app>/` | `~/.local/share/<app>/` |

- Create dirs `0700`, files `0600`. Never loosen existing permissions.
- Provide `<APP>_CONFIG_DIR` to override the whole config dir — this single feature makes tests, CI, and sandboxes clean (`CORTEX_CONFIG_DIR=$(mktemp -d)`).
- On macOS/Windows, honoring `XDG_*` when set is friendlier than platform purity (gh does this).
- Per-directory sidecar state (e.g. `.mosaic.json` remembering the publish location) makes repeat invocations flagless — hugely valuable for stateless agents. Keep sidecars tiny, JSON, and documented.

## Environment variables

- Prefix everything with the app name: `FIZZY_TOKEN`, `NEBULA_WORKSPACE`. Uppercase, digits, underscores.
- **Document each env var in the flag help where it applies**: `--token string   API token (env: APP_TOKEN; prefer env or --token-file)`. Also give env vars their own section in root help or a `help environment` topic.
- Honor the general-purpose vars you didn't invent: `NO_COLOR`, `FORCE_COLOR`, `TERM`, `EDITOR`/`VISUAL`, `PAGER`, `HTTP_PROXY`/`HTTPS_PROXY`/`NO_PROXY`, `TMPDIR`, `DO_NOT_TRACK`.
- Layered editor/pager chains follow gh's pattern: `APP_EDITOR > GIT_EDITOR > VISUAL > EDITOR`.

## Credentials

**Secrets never go in argv.** `--token abc123` leaks via `ps`, shell history, and agent transcripts. Preference order:

1. **OS keyring** (macOS Keychain, Secret Service, Windows Credential Manager — `zalando/go-keyring`), probed at startup, with `<APP>_NO_KEYRING=1` to force file storage
2. **Token file**: `--token-file <path>`, contents trimmed; or the config file itself at `0600`
3. **Env var** (`<APP>_TOKEN`) — fine for CI, wins over stored credentials
4. `--token` flag exists as an escape hatch but help text steers away from it

Rules:

- `config show` **masks** secrets (`abcd****wxyz`) and shows which source each value came from (flag/env/file/default). A `config explain` that spells out why each value won is even better.
- `login` verifies the token against the API (`/me`) and reports the identity; treat verification failure as a warning (save anyway — the API might be down), not a hard fail. Sniff obviously-wrong token formats and warn softly.
- Provide `auth login` / `auth logout` / `auth status` (or `config setup`). For OAuth: device flow or PKCE + localhost callback; auto-refresh with an expiry buffer.
- Prompted secret input disables echo. For agents, the pattern is: write the secret to a `0600` temp file and pipe via stdin — never into argv or the transcript.
- Enforce HTTPS for non-localhost endpoints — warn loudly on stderr for `http://`.

## Load vs Validate

`Load()` never fails on missing credentials — it just assembles the layers. Commands that need auth call an explicit guard:

```go
func (c *Config) EnsureTokenConfigured() error {
    if c.Token == "" {
        return fmt.Errorf("API token not configured (set APP_TOKEN, use --token-file, or run `app config setup`)")
    }
    return nil
}
```

Granular guards beat one monolithic `Validate()` — a discovery command may need only a token while data commands also need a workspace, and each should produce exactly the right actionable error. Read-only meta commands (`config show`, `version`, `doctor`) skip guards entirely.

## Onboarding commands

- **`config setup`** — dual-mode: interactive wizard (charmbracelet `huh`: select forms, password-masked input) when TTY and no flags; fully flag-driven otherwise. Non-interactive mode **preserves existing values** for anything not passed.
- **`doctor`** — read-only structured health check: typed checks `{name, status: pass|warn|fail|skip, message, hint}` covering config, connectivity, auth, version freshness. Cascading skips (auth failed → skip account checks). Supports `--json`. This is the first thing you tell a user (or agent) to run when something's wrong.
