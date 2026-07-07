# AGENTS.md

This file defines agent roles, constraints, and integration points for AI-assisted development in this repository.

## Agent Roles

### Claude Code (primary development agent)

Responsible for:
- Writing, editing, and refactoring code in `lib/` and `test/`
- Running `mix precommit` before every commit
- Keeping `CLAUDE.md` up to date when architecture changes

### Code Review Agent (`/code-review`)

Invoked by the developer to review changes. Reads diff, checks for architectural drift, suggests improvements. Does not modify code directly.

## usage_rules Integration

This project uses the `usage_rules` package to generate machine-readable documentation for AI agents.

**When to regenerate:** Run `mix usage_rules` after:
- Adding or modifying a public module in `lib/slackbox/`
- Changing public API functions

Generated output goes to `priv/usage_rules/`.

Agents should read `priv/usage_rules/` before writing code that touches public API modules.

## Constraints — What Agents Must Never Do

- **Never bypass `mix precommit`** — all four checks must pass before committing
- **Never commit with TODO comments** — Credo's `TagTODO` check exits with status 2
- **Never modify `mix.lock` manually** — only `mix deps.get` / `mix deps.update` should touch it
- **Never add `IO.inspect` or `IEx.pry` to committed code** — these fail Credo

## Project Context

- **App module:** `Slackbox`
- **Test isolation:** Standard ExUnit — use `async: true` where safe
- **Key patterns:** Adapter pattern (like Swoosh), per-environment configuration, test assertions via the `Slackbox.Test` module
