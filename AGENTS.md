# AGENTS.md

Slackbox is an Elixir library (published to hex.pm, MIT) that works like Swoosh for Slack: an app defines one
notifier module (`use Slackbox.Notifier`), every outbound Slack call flows through that choke point, and a
per-environment adapter decides what happens (real Slack Web API, an in-memory fake Slack dev UI, or message capture
for tests). It also simulates inbound Slack interactions (block actions, modal submissions, Events API) with signed
requests. Users are Elixir/Phoenix app developers. There is no deployment target: the artifacts are the hex package
and the HexDocs site. There is no database, no migrations, and no OTP application callback (`mix.exs` has no `mod:`).

## Project Overview

| Item | Value |
|---|---|
| Elixir / OTP (pinned) | 1.20.4-otp-29 / 29.0.5 (`.tool-versions`, `mise.toml`); `mix.exs` requires `~> 1.15` |
| Version | `0.1.0` (`@version` in `mix.exs`); changelog in `CHANGELOG.md` (Keep a Changelog, SemVer) |
| Phoenix / LiveView | 1.8.13 / 1.2.11 locked (declared `~> 1.7` / `~> 1.0`); Bandit 1.12.5, Plug 1.20.3 |
| HTTP client | `req ~> 0.5` (locked 0.7.4); JSON via `jason` |
| Dev tools | `credo ~> 1.7`, `dialyxir ~> 1.4`, `ex_doc ~> 0.34` (dev only), `usage_rules ~> 1.2` (dev only) |
| Persistence | none; `Slackbox.Store` is an in-memory GenServer |
| CI | GitHub Actions (`.github/workflows/`), remote `github.com/epinault/slackbox` |
| Root module | `Slackbox`; demo endpoint `Slackbox.Demo.Endpoint`; no Repo |

Phoenix, LiveView, Bandit and Req are real runtime deps because the dev UI and demo server ship in the package.

## Essential Commands

Only these aliases exist (`mix.exs`): `setup` (= `deps.get`) and `precommit`.

### Setup
```bash
mix setup
```

### Dev (fake Slack UI)
```bash
mix slackbox.demo              # boots demo server at http://localhost:4000 (blocks forever)
iex -S mix                     # then: Slackbox.Demo.start(port: 4000); Slackbox.Demo.post("hi", "#alerts")
```

### Test
```bash
mix test                                          # whole suite
mix test test/slackbox/store_test.exs             # one file
mix test test/slackbox/store_test.exs:12          # one test by line
mix test --warnings-as-errors --cover             # what CI runs; coverage threshold is 55% (mix.exs test_coverage)
```

### Quality
```bash
mix precommit    # compile --warnings-as-errors, format --check-formatted, credo --strict, test (runs in MIX_ENV=test)
mix dialyzer     # dialyxir is a dep but NOT part of precommit or CI; no PLT cache is configured
```

### Docs and publishing
```bash
mix docs         # ExDoc into doc/ (main: Slackbox; extras: README.md, CHANGELOG.md)
mix hex.build    # verify the package builds; produces slackbox-*.tar (gitignored)
mix usage_rules.sync   # regenerate the usage-rules block at the bottom of this file
```
Releasing (`mix hex.publish`) is a human action; see Constraints.

## Architecture

```
lib/
  slackbox.ex                 Moduledoc-only top-level module (no functions)
  slackbox/
    adapter.ex                Slackbox.Adapter behaviour (single call/3 callback)
    adapters/live.ex          Real Slack Web API via Req (needs :token)
    adapters/local.ex         Writes to Slackbox.Store; powers the dev UI
    adapters/test.ex          Sends {:slackbox, action, args} to self() and $callers
    notifier.ex               `use Slackbox.Notifier, otp_app:` macro + dispatch/4
    message.ex                Slackbox.Message struct + pipe builders + Block Kit helpers (section/actions/button, action_ids)
    store.ex                  In-memory GenServer: messages, channels, views, response tokens; broadcasts on PubSub
    simulator.ex              Builds/sends inbound payloads (block_actions, view_submission, view_closed, event_callback)
    signature.ex              Slack v0 request signing (sign/3, valid?/4)
    response_plug.ex          Plug.Router receiving response_url callbacks -> Store.apply_response/2
    dashboard_live.ex         Slackbox.DashboardLive, the fake Slack LiveView UI
    test.ex                   Slackbox.Test payload builders (block_actions/1, view_submission/1, event/2, form_body, signature_headers)
    test_assertions.ex        assert_message_sent, assert_ephemeral_sent, assert_message_updated, assert_view_opened, refute_message_sent
    demo.ex                   Slackbox.Demo.start/1 + post/2; seeds sample messages
    demo/{endpoint,router,layouts,slack_app}.ex   Demo-only Phoenix endpoint, router, root layout, sample app receiving simulated Slack requests
  mix/tasks/slackbox.demo.ex  `mix slackbox.demo`
test/
  test_helper.exs             Sets TestNotifier adapter to Adapters.Test, ExUnit.start()
  support/test_notifier.ex    Slackbox.TestNotifier (compiled only in :test via elixirc_paths)
  slackbox_test.exs, slackbox/*_test.exs   One test file per module, plus loop tests (interactive_loop_test, phase5_loop_test)
docs/superpowers/             Design spec and Phase 1 plan (historical)
```

### Public API surface

- `Slackbox.Notifier` (`use ... otp_app: :my_app`) generates `post_message/1,2` (alias `deliver/1,2`),
  `post_ephemeral/1,2`, `update/1,2`, `delete/1,2`, `open_view/2,3`, `respond/2,3`. The trailing `opts` are
  runtime overrides merged over the adapter config; message content belongs on `Slackbox.Message`.
- `Slackbox.Message` builders, `Slackbox.Test` payload builders, `Slackbox.TestAssertions`, `Slackbox.Signature`,
  `Slackbox.ResponsePlug`, `Slackbox.DashboardLive`, `Slackbox.Store`, `Slackbox.Simulator`, `Slackbox.Demo`.
- Anything marked `@moduledoc false` or `@doc false` (e.g. `Notifier.dispatch/4`, `Demo.*` router/endpoint) is internal.
- Adding, removing or renaming a public function is a user-visible change: update `CHANGELOG.md` under `[Unreleased]`.

### Adapter contract (`Slackbox.Adapter`)

```elixir
@type action :: :post_message | :post_ephemeral | :update | :delete | :open_view | :respond
@callback call(action(), args :: map(), config :: keyword()) :: {:ok, map()} | {:error, term()}
```
- `args` shapes: `%{message:, opts:}` for post_message/post_ephemeral/update/delete; `%{trigger_id:, view:, opts:}`
  for open_view; `%{response_url:, message:, opts:}` for respond.
- `config` is the app's `config :my_app, MyNotifier, ...` keyword merged with per-call `opts`. `:adapter` is
  required (`Keyword.fetch!` in `dispatch/4`, so a missing adapter raises `KeyError`).
- Return shapes: post_message/update -> `{:ok, %{ts:, channel:}}`; open_view -> `{:ok, %{view_id:}}`; others `{:ok, %{}}`.
  Errors are tagged tuples and adapters never raise into the caller. Live uses `{:error, {:slack, reason}}`,
  `{:error, {:rate_limited, retry_after | nil}}`, `{:error, {:http, status}}`, `{:error, :missing_token}`, or the transport exception.
- A new adapter must `@behaviour Slackbox.Adapter`, use `@impl Slackbox.Adapter`, pattern-match on the action atom, and handle all six actions.
  Adding an action means touching `Adapter.action`, `Notifier`, all three adapters, `TestAssertions` if capturable, README and CHANGELOG.

### Dev UI wiring

- `Slackbox.Adapters.Local` -> `Slackbox.Store.put/1` -> `Phoenix.PubSub.broadcast(Slackbox.PubSub, "slackbox", {:slackbox_store, op, entry})`
  (only when the PubSub process is running, so the Store works in plain tests) -> `Slackbox.DashboardLive` subscribes and re-renders.
- The library has no supervision tree of its own. A host app must start `{Phoenix.PubSub, name: Slackbox.PubSub}`,
  `Slackbox.Store`, and mount `live "/", Slackbox.DashboardLive` itself. `Slackbox.Demo.start/1` is the reference wiring:
  it sets app env for `Slackbox.Demo.Endpoint` (Bandit adapter, fixed dev secret) and `:simulator`, then starts
  PubSub, Store and Endpoint under `Slackbox.Demo.Supervisor`.
- Demo router: `/` -> DashboardLive, `/demo` -> `Slackbox.Demo.SlackApp` (receives simulated interactivity/events),
  `/slackbox/response` -> `Slackbox.ResponsePlug`.
- Inbound loop: dashboard click -> `Simulator.click/3` builds a `block_actions` payload with a `response_url`
  (`<response_base>/<token>`, token from `Store.register_response/2`), signs it with `Signature` if a signing secret is set,
  POSTs via Req to the app's `interactivity_url`; the app answers to `response_url`, `ResponsePlug` calls `Store.apply_response/2`.
- Simulator config: `Application.get_env(:slackbox, :simulator, %{})` with keys `interactivity_url`, `events_url`,
  `response_base`, `signing_secret`, `user`.

## Conventions

- Formatter: default `mix format` over `{mix,.formatter}.exs` and `{config,lib,test}/**/*.{ex,exs}`.
- Credo strict (`.credo.exs`): max line length 120; `StrictModuleLayout` (`@moduledoc` -> `use` -> `import` -> `alias` -> `require`
  -> attributes -> functions); `AliasOrder`, `MultiAlias`, `SinglePipe`, `BlockPipe`, `WithSingleClause`; `UnusedVariableNames` forced
  meaningful (no bare `_`; use `_rest`, `_config`); `TagTODO` exits with status 2; `ABCSize` max 50; `ModuleDoc` required.
- Docs policy: `@moduledoc` on every module (`@moduledoc false` for internal ones); `@doc` and `@spec` on public functions.
- Adapters pattern-match on the action atom in `call/3` clause heads; helper clauses are `defp`.
- Fallible operations return `{:ok, _} | {:error, _}`; do not raise for control flow in library code.
- The Store is accessed only via its public functions (GenServer.call with the module as the registered name by default).
- Dependencies of the dev UI (Phoenix, LiveView, Bandit) are compile-time deps of the package; do not add heavy new runtime deps. Keep
  the public surface small.
- Dev UI uses plain inline HTML/CSS in `Slackbox.Demo.Layouts` and `DashboardLive`: no Tailwind, daisyUI or asset pipeline.

## Testing

- Plain ExUnit, one file per module under `test/slackbox/`. Default to `use ExUnit.Case, async: true`; use `async: false` only for tests
  touching the globally named `Slackbox.Store`, `Application.put_env(:slackbox, :simulator, ...)`, or the demo server.
- `test/test_helper.exs` points `Slackbox.TestNotifier` (in `test/support/test_notifier.ex`) at `Slackbox.Adapters.Test`.
- Adapter tests: call `Adapter.call/3` directly and assert on return shape (Test, Local), or use `assert_received {:slackbox, action, args}`.
  The Test adapter also delivers to `$callers`, so captures survive `Task.async`.
- Live adapter: `live_adapter_test.exs` stubs Slack with Req's `plug:` via the `:req_options` / `:base_url` config; never hit the real
  Slack API in tests.
- Loop tests (`interactive_loop_test.exs`, `phase5_loop_test.exs`) start the demo/server pieces and exercise the signed inbound loop
  end to end; they tolerate an already-terminating `Slackbox.Demo.Supervisor` in cleanup.
- Coverage gate: `mix test --cover` fails under 55%.
- Example:

```elixir
test "call/3 sends the action tuple to the current process" do
  msg = Message.new(channel: "#alerts", text: "hi")
  assert {:ok, %{ts: ts, channel: "#alerts"}} = Test.call(:post_message, %{message: msg, opts: []}, [])
  assert is_binary(ts)
  assert_received {:slackbox, :post_message, %{message: ^msg}}
end
```
- Avoid `Process.sleep` in new tests (the loop tests still use 20ms sleeps for async HTTP settling); prefer `assert_receive` or process calls.
- CI matrix (GitHub Actions) covers Elixir 1.15 through 1.20 on OTP 26-29, so do not use syntax or stdlib functions newer than Elixir 1.15
  in `lib/` without checking. CI also runs `mix deps.unlock --check-unused`.

## Elixir / Phoenix Guidelines

- Phoenix 1.8 / LiveView 1.2 are locked, but the declared minimums are Phoenix 1.7 / LiveView 1.0. Write code that works on those
  minimums (no APIs introduced later) since users of the library choose their own versions.
- This is a library: never read `Application.get_env` at compile time for user config; resolve at runtime (as `Notifier.dispatch/4` does).
- No `use MyAppWeb` helpers exist here; LiveView/Router modules `use Phoenix.LiveView` / `use Phoenix.Router` directly.
- Prefer pattern matching and `with`; avoid nested `case`; no `String.to_atom` on user input; `@impl true` (or `@impl Behaviour`) on callbacks.
- Use `Req` for HTTP (already used by Live and Simulator); do not add another HTTP client.
- Keep GenServer state simple (the Store is `%{entries:, tokens:, views:}`); use `call` for back-pressure.
- Do not add `config/*.exs` to the library; configuration is documented for the host app in the README.

## Workflow for Agents

1. Read the module you change and its test file; for adapter work read `lib/slackbox/adapter.ex` and all three adapters.
2. Write or adjust the test first.
3. Implement. Keep the public API small and documented (`@moduledoc`, `@doc`, `@spec`).
4. Update `README.md` for user-facing behavior and `CHANGELOG.md` under `[Unreleased]`.
5. Run `mix precommit`; also run `mix docs` and `mix hex.build` when you touched docs, `mix.exs` package config, or version.
6. Commit with conventional commits (history uses `feat:`, `fix:`, `docs:`, `chore:`, `build(deps):`, `ci:`, `style:`, `test:`) on a
   branch; work lands via GitHub pull requests (`epinault/slackbox`, `main`).
7. Re-run `mix usage_rules.sync` after dependency updates that move `phoenix`, `phoenix_live_view` or `usage_rules`, or after editing
   the `usage_rules/0` config in `mix.exs` (run `mix deps.get` first).

Release checklist (human-driven): bump `@version` in `mix.exs`, move `[Unreleased]` entries into a dated version section in `CHANGELOG.md`,
run `mix precommit`, `mix docs`, `mix hex.build`, tag `v<version>` (docs use `source_ref: "v#{@version}"`), then `mix hex.publish`.

## Constraints — Never Do

- Never bypass `mix precommit`, and never commit with `--no-verify`.
- Never commit TODO comments (Credo `TagTODO` exits with status 2) or `IO.inspect` / `IEx.pry` / `dbg`.
- Never edit `mix.lock` by hand; use `mix deps.get` / `mix deps.update`.
- Never hand-edit the usage-rules block below; regenerate with `mix usage_rules.sync`.
- Never run `mix hex.publish`, `mix hex.retire` or `mix hex.revert`, or bump the version, unless the user explicitly asks.
- Never call the real Slack API from tests, or commit real tokens/signing secrets (`SLACK_BOT_TOKEN`, `SLACK_SIGNING_SECRET`, `xoxb-...`).
- Never break the adapter contract (`call/3` signature or return shapes) without a CHANGELOG entry and a version decision.
- Never add Mix-env-specific behavior (`Mix.env()`) to code under `lib/` that ships in the package, other than the Mix task.
- Don't commit `doc/`, `cover/`, `_build/`, `deps/`, or `slackbox-*.tar` (gitignored).

## Gotchas

- `Slackbox.Store` and `Slackbox.PubSub` are not started automatically; tests or hosts that need them must start them.
  `Store.put/1` skips broadcasting when PubSub is not running.
- `Slackbox.Demo.start/1` mutates global app env (`:simulator`, `Slackbox.Demo.Endpoint`); tests using it must be `async: false`.
- `mix slackbox.demo` blocks with `Process.sleep(:infinity)`; run it in the background or use `iex -S mix` with `Demo.start/0`.
- The demo endpoint uses a fixed insecure `secret_key_base` and binds 127.0.0.1; it is for local dev only.
- `Notifier.dispatch/4` raises `KeyError` if `:adapter` is not configured for the notifier module.
- `mix docs`, `credo` and `usage_rules` are dev/test-only deps; `mix docs` must run in dev (the default).
- `dialyxir` is installed but unused in CI; expect possible unreviewed warnings if you run it.
- Test file `phase5_loop_test.exs` is named after a development phase, not a feature; keep naming in mind when searching.
- `.claude/settings.json` lists plugins including `claude-mem` and `elixir-scaffold`.
- README documents behavior users rely on (simulator config, `Slackbox.Test` helpers); keep it in sync with code.

## Code Search

`sgrep` is a semantic code search tool (ripgrep candidates re-ranked by local embeddings). It may not be installed on every machine: check with `command -v sgrep`; if it is missing, use `rg`/`grep` as usual and do not try to install it.

- Prefer `sgrep "natural-language question" lib/` when you are looking for a concept or behaviour and do not know the exact identifier, when the codebase is unfamiliar, or when `rg` returned too many hits or none because the naming did not match your guess.
- Keep `rg`/`grep` when you know the exact symbol, string, module name or regex, when you need every occurrence (renames, call-site audits), or when matching structured patterns (config keys, log formats, file paths).
- Always pass a directory as the second argument (`lib/`, `test/`, `assets/js/`) so `deps/`, `_build/`, `node_modules/` are skipped. The first run on a corpus builds an embedding index (slow); later runs reuse the cache. Use `--refresh-cache` after large refactors if results look stale.

## Key Files

- `lib/slackbox/notifier.ex` - the `use` macro and adapter dispatch
- `lib/slackbox/adapter.ex` - adapter behaviour contract
- `lib/slackbox/adapters/live.ex` - real Slack Web API client, error shapes
- `lib/slackbox/adapters/local.ex`, `lib/slackbox/adapters/test.ex` - dev UI and test capture adapters
- `lib/slackbox/message.ex` - message struct and Block Kit builders
- `lib/slackbox/store.ex` - in-memory state and PubSub broadcast
- `lib/slackbox/simulator.ex`, `lib/slackbox/signature.ex` - inbound simulation and request signing
- `lib/slackbox/dashboard_live.ex`, `lib/slackbox/demo.ex` - dev UI and its wiring
- `lib/slackbox/test_assertions.ex`, `lib/slackbox/test.ex` - public test helpers
- `test/test_helper.exs`, `test/support/test_notifier.ex` - test setup
- `mix.exs` - deps, `precommit` alias, package, docs and usage_rules config
- `CHANGELOG.md`, `README.md` - user-facing docs; `.github/workflows/ci.yml` - CI
- `docs/superpowers/specs/2026-07-02-slackbox-design.md` - original design spec

<!-- usage-rules-start -->
<!-- usage_rules-start -->
## usage_rules usage
_A config-driven dev tool for Elixir projects to manage AGENTS.md files and agent skills from dependencies_

## Using Usage Rules

Many packages have usage rules, which you should *thoroughly* consult before taking any
action. These usage rules contain guidelines and rules *directly from the package authors*.
They are your best source of knowledge for making decisions.

## Modules & functions in the current app and dependencies

When looking for docs for modules & functions that are dependencies of the current project,
or for Elixir itself, use `mix usage_rules.docs`

```
# Search a whole module
mix usage_rules.docs Enum

# Search a specific function
mix usage_rules.docs Enum.zip

# Search a specific function & arity
mix usage_rules.docs Enum.zip/1
```


## Searching Documentation

You should also consult the documentation of any tools you are using, early and often. The best 
way to accomplish this is to use the `usage_rules.search_docs` mix task. Once you have
found what you are looking for, use the links in the search results to get more detail. For example:

```
# Search docs for all packages in the current application, including Elixir
mix usage_rules.search_docs Enum.zip

# Search docs for specific packages
mix usage_rules.search_docs Req.get -p req

# Search docs for multi-word queries
mix usage_rules.search_docs "making requests" -p req

# Search only in titles (useful for finding specific functions/modules)
mix usage_rules.search_docs "Enum.zip" --query-by title
```


<!-- usage_rules-end -->
<!-- usage_rules:elixir-start -->
## usage_rules:elixir usage
# Elixir Core Usage Rules

## Pattern Matching
- Use pattern matching over conditional logic when possible
- Prefer to match on function heads instead of using `if`/`else` or `case` in function bodies
- `%{}` matches ANY map, not just empty maps. Use `map_size(map) == 0` guard to check for truly empty maps

## Error Handling
- Use `{:ok, result}` and `{:error, reason}` tuples for operations that can fail
- Avoid raising exceptions for control flow
- Use `with` for chaining operations that return `{:ok, _}` or `{:error, _}`

## Common Mistakes to Avoid
- Elixir has no `return` statement, nor early returns. The last expression in a block is always returned.
- Don't use `Enum` functions on large collections when `Stream` is more appropriate
- Avoid nested `case` statements - refactor to a single `case`, `with` or separate functions
- Don't use `String.to_atom/1` on user input (memory leak risk)
- Lists and enumerables cannot be indexed with brackets. Use pattern matching or `Enum` functions
- Prefer `Enum` functions like `Enum.reduce` over recursion
- When recursion is necessary, prefer to use pattern matching in function heads for base case detection
- Using the process dictionary is typically a sign of unidiomatic code
- Only use macros if explicitly requested
- There are many useful standard library functions, prefer to use them where possible

## Function Design
- Use guard clauses: `when is_binary(name) and byte_size(name) > 0`
- Prefer multiple function clauses over complex conditional logic
- Name functions descriptively: `calculate_total_price/2` not `calc/2`
- Predicate function names should not start with `is` and should end in a question mark.
- Names like `is_thing` should be reserved for guards

## Data Structures
- Use structs over maps when the shape is known: `defstruct [:name, :age]`
- Prefer keyword lists for options: `[timeout: 5000, retries: 3]`
- Use maps for dynamic key-value data
- Prefer to prepend to lists `[new | list]` not `list ++ [new]`

## Mix Tasks

- Use `mix help` to list available mix tasks
- Use `mix help task_name` to get docs for an individual task
- Read the docs and options fully before using tasks

## Testing
- Run tests in a specific file with `mix test test/my_test.exs` and a specific test with the line number `mix test path/to/test.exs:123`
- Limit the number of failed tests with `mix test --max-failures n`
- Use `@tag` to tag specific tests, and `mix test --only tag` to run only those tests
- Use `assert_raise` for testing expected exceptions: `assert_raise ArgumentError, fn -> invalid_function() end`
- Use `mix help test` to for full documentation on running tests

## Debugging

- Use `dbg/1` to print values while debugging. This will display the formatted value and other relevant information in the console.

<!-- usage_rules:elixir-end -->
<!-- usage_rules:otp-start -->
## usage_rules:otp usage
# OTP Usage Rules

## GenServer Best Practices
- Keep state simple and serializable
- Handle all expected messages explicitly
- Use `handle_continue/2` for post-init work
- Implement proper cleanup in `terminate/2` when necessary

## Process Communication
- Use `GenServer.call/3` for synchronous requests expecting replies
- Use `GenServer.cast/2` for fire-and-forget messages.
- When in doubt, use `call` over `cast`, to ensure back-pressure
- Set appropriate timeouts for `call/3` operations

## Fault Tolerance
- Set up processes such that they can handle crashing and being restarted by supervisors
- Use `:max_restarts` and `:max_seconds` to prevent restart loops

## Task and Async
- Use `Task.Supervisor` for better fault tolerance
- Handle task failures with `Task.yield/2` or `Task.shutdown/2`
- Set appropriate task timeouts
- Use `Task.async_stream/3` for concurrent enumeration with back-pressure

<!-- usage_rules:otp-end -->
<!-- phoenix:phoenix-start -->
## phoenix:phoenix usage
[phoenix:phoenix usage rules](deps/phoenix/usage-rules/phoenix.md)
<!-- phoenix:phoenix-end -->
<!-- phoenix:liveview-start -->
## phoenix:liveview usage
[phoenix:liveview usage rules](deps/phoenix/usage-rules/liveview.md)
<!-- phoenix:liveview-end -->
<!-- phoenix:html-start -->
## phoenix:html usage
[phoenix:html usage rules](deps/phoenix/usage-rules/html.md)
<!-- phoenix:html-end -->
<!-- usage-rules-end -->
