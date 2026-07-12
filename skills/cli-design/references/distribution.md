# Distribution, Versioning, and Updates

## Versioning

- Semver with `v` prefix. Version injected at build time via ldflags from `git describe --tags --always --dirty`; default `"dev"` in source; `debug.ReadBuildInfo()` fallback for `go install` builds.
- `--version` and a `version` command both work; include commit and date if cheap. Send the version in the User-Agent of every HTTP request — it's how you debug field issues.
- Version lives in its own `internal/version` package so the HTTP client can import it without cycles.

## Release pipeline

- **GoReleaser** is the standard: cross-platform matrix (darwin/linux × amd64/arm64 minimum; windows amd64 if the tool supports it), `CGO_ENABLED=0`, `-s -w` stripped, SHA256 `checksums.txt`, GitHub Release with categorized changelog.
- Refuse to release from a dirty tree (`git describe` ending in `-dirty` → abort).
- Higher tiers as adoption grows: cosign keyless signing, Syft SBOMs, macOS notarization, Homebrew tap, Scoop, AUR, deb/rpm via nfpm. Prerelease tags (`-rc.1`) publish as GitHub prereleases only — never update package-manager manifests, so existing users don't auto-upgrade onto a candidate.
- Dogfood when possible (mosaic-cli releases are published *with* mosaic).

## Install script

`curl -fsSL .../install.sh | bash` — POSIX sh, and it must:

1. Detect OS/arch, normalizing `x86_64→amd64`, `aarch64→arm64`; reject unsupported platforms with a clear message
2. Download the right binary
3. **Verify SHA256** when `sha256sum`/`shasum` exists
4. Install to `~/.local/bin` (overridable via env), never sudo by default
5. Warn if the install dir isn't on `PATH`, and print next steps (`app config setup`)

## Self-update (`app upgrade`)

Only via an explicit command — never automatic. The careful implementation, point for point:

1. Compare semver against the latest release; no-op when current unless `--force`
2. Pick the asset for `runtime.GOOS + "-" + runtime.GOARCH`
3. **Refuse to install without a checksums file** ("refusing to install unverified binary")
4. Download to a temp file *in the target directory* (rename across filesystems fails), streaming through a SHA-256 hasher (`io.MultiWriter`)
5. Verify checksum, `chmod 0755`, **atomic `os.Rename`** over the running binary
6. **Refuse to overwrite a symlink** — that's a dev install (`make link`); check both PATH-resolved argv[0] and `os.Executable()`
7. Permission errors suggest `sudo` in the error message rather than escalating
8. Resolve the install target *before* downloading — fail fast on dev installs and permission problems

Respect the package manager that installed you: if the binary came from Homebrew/AUR, say so and defer. A softer alternative to self-update: `doctor` compares against the latest release and nudges.

## Passive update check

The etiquette (gh is the reference):

- At most **once per 24h**, result cached in the state dir (`update_check.json`)
- Async or hard-capped at 1–2s — a slow release server must never delay a command
- **All failures silent** — the check must never break or slow normal operation
- Notice printed to **stderr**, human mode only (never pollutes `--json` stdout)
- Skipped for: `dev` builds, `upgrade`/`version`/`help`/`completion` commands, and when `<APP>_NO_UPDATE_CHECK` is set
- Never a "time bomb": the CLI must work forever without phoning home

## Telemetry

Default position: don't. If the value is real:

- Disclose on first run with a plain-language list of exactly what's collected; link full docs
- Honor `DO_NOT_TRACK=1` *and* your own `<APP>_NO_TELEMETRY=1` / `config set telemetry false`
- Provide `telemetry status` that reports on/off *and why* (which mechanism disabled it)
- The transparency pattern worth copying: `<APP>_TELEMETRY=log` prints the exact payload to stderr instead of sending
- Never collect silently in CI

## Shell completion

`app completion bash|zsh|fish|powershell` via cobra's generators, with copy-paste install instructions in its help. Dynamic completions for resource IDs (with a short-TTL file cache) are a nice higher tier.

## Docs that ship with the repo

- **README**: quick start (install one-liner → auth → first command), every install channel, output-format documentation (the JSON envelope IS user-facing API docs), config precedence, troubleshooting pointing at `doctor`
- **AGENTS.md**: repo structure, testing commands, conventions — for coding agents working *on* the CLI (SKILL.md is for agents *using* it)
- **RELEASING.md**: the exact release procedure including dry-run
- **SECURITY.md**, CONTRIBUTING.md, MIT-LICENSE as appropriate
