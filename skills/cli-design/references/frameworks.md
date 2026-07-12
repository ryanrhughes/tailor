# Choosing a Language and Framework

The house default is **Go + cobra** (see `go-architecture.md`). This file exists for when Go isn't the right call, or the user's team dictates otherwise. The output contract, exit codes, config precedence, and agent-integration rules in this skill are language-independent — only the implementation library changes.

## Decision guide

| Factor | Go | Rust | TypeScript | Python |
|--------|-----|------|------------|--------|
| Single-binary distribution | yes | yes | via oclif pack / bun compile | no (needs runtime) |
| Cross-compilation | trivial | good (cross-rs, cargo-dist) | awkward | n/a |
| Startup time | fast | fastest | slow (Node) | slow |
| Learning curve | low-medium | high | low | low |
| Best for | API CLIs, wide distribution (the default) | performance-critical tools, called-in-tight-loops | JS-first teams, plugin architectures | internal/data tools, prototypes |

Pick Go unless: raw performance is the product (Rust), the team is JS-only (TypeScript), or it's an internal data tool that will never leave the org (Python). Startup time matters more than it looks — a CLI called in a shell loop or by an agent hundreds of times pays the Node/Python interpreter tax on every invocation.

## Stacks per language

- **Go**: cobra + pflag (commands), stdlib `net/http`, `yaml.v3`; charmbracelet huh/lipgloss/bubbletea for interactive UI. Avoid viper unless config needs are genuinely complex — hand-rolled layered loading (see `config-and-auth.md`) is more transparent.
- **Rust**: clap (derive macros), serde/serde_json, anyhow/thiserror, indicatif (progress), dialoguer (prompts), ratatui (TUI). cargo-dist for releases.
- **TypeScript**: oclif (large CLIs, plugins — it's the framework behind Heroku/Salesforce CLIs) or Clipanion (yarn's, best type safety) or commander (small tools). Ship prebuilt binaries via npm (hybrid: Rust/Go binary in an npm wrapper is a proven pattern).
- **Python**: Typer (type-hint driven, on Click) + Rich for output. Distribute via `uv tool install` / `pipx`. No single-binary story — accept it or switch language.

## Structure translates directly

The Go layout in `go-architecture.md` maps 1:1 to other languages: commands/ (parsing only) call into lib/ or src/ business logic; output formatting centralized in one module so every command gets `--json` for free; input validation as a shared layer; `skills/<app>/SKILL.md` at the root regardless of language.
