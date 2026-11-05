# CLAUDE.md

Claude Code guidance for this repository. The canonical agent instructions live in AGENTS.md.

@AGENTS.md

## Plugin Setup

Run once after cloning (also listed in `.claude/settings.json`):

```bash
claude plugin install elixir@claude-code-elixir
claude plugin install superpowers@claude-plugins-official
claude plugin install code-review@claude-plugins-official
claude plugin install claude-mem@thedotmack
claude plugin install elixir-scaffold
```

## Claude-specific notes

- Run `mix precommit` before every commit; for anything touching docs or `mix.exs` package config also run `mix docs` and `mix hex.build`.
- Use the `superpowers` skills for non-trivial work (brainstorming before new features, test-driven-development, verification-before-completion).
  Past design material is in `docs/superpowers/`.
- Use `/code-review` for review; it should not modify code.
- Use the `update-dependencies` skill for dep bumps, then `mix usage_rules.sync`.
- Never run `mix hex.publish` yourself; releases are a human step.
- Keep AGENTS.md as the single source of truth; do not copy its content here.
