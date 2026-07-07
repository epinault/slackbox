# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Plugin Setup

Run once after cloning:

```bash
claude plugin install elixir@claude-code-elixir
claude plugin install superpowers@claude-plugins-official
claude plugin install code-review@claude-plugins-official
claude plugin install claude-mem@thedotmack
claude plugin install elixir-scaffold
```

## Project Overview

Elixir library published to hex.pm.

**Module:** `Slackbox`

## Essential Commands

```bash
mix setup        # install deps
mix test         # run all tests
mix docs         # generate documentation (ex_doc)
mix hex.build    # verify hex package builds cleanly
mix precommit    # full quality gate — run before every commit
```

**Always run `mix precommit` before committing.**

## Architecture

Public API lives in `lib/slackbox.ex`. Keep the surface area small — expose only what users need. Internal implementation modules go in `lib/slackbox/`.

Add `@moduledoc`, `@doc`, and `@spec` to all public functions.

## Code Quality Standards

- Max line length: 120 characters
- `@moduledoc` required on all modules
- `@doc` and `@spec` required on all public functions
- Strict module layout: `use → import → alias → require → attributes → functions`
- Run `mix precommit` before every commit

## Key Files

- `lib/slackbox.ex` — public API
- `mix.exs` — package metadata, deps, docs config
- `README.md` — user-facing documentation
