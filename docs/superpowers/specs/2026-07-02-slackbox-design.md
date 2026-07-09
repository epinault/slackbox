# Slackbox — Design Spec

**Date:** 2026-07-02
**Status:** Approved design, pre-plan
**One-liner:** A Swoosh-style Elixir library for Slack — send Slack messages through one choke point with per-environment adapters, and in dev get a real-time **fake Slack UI** that both renders what your app sends *and* lets you simulate Slack calling your app back.

---

## 1. Motivation

Swoosh makes email pleasant: your app always calls `Mailer.deliver(email)`, and a per-environment adapter decides whether it hits a real provider (prod), an in-memory mailbox with a `/dev/mailbox` preview (dev), or a test capture you can assert on (test). There is no equivalent for Slack.

`slackbox` brings that same pattern to Slack, and goes one step further: because Slack apps are **bidirectional** (your app posts messages *and* receives interaction/modal/event callbacks), the dev tool is not just a passive mailbox — it is a **local Slack simulator** that can POST realistic payloads back into your app so you can exercise the full loop without a real Slack workspace.

## 2. Goals / Non-goals

**Goals (v1)**
- One outbound choke point with `Live` / `Local` / `Test` adapters (true Swoosh parity: same app code in every environment).
- `Live` adapter is a real, production-usable Slack Web API client (thin, `Req`-based, owned by us — no third-party Slack lib dependency).
- Dev: real-time LiveView "fake Slack" dashboard mounted in the host app's router, rendering messages + Block Kit, with a slide-out raw-payload inspector per message.
- Dev: simulate **interactive components**, **modals/views**, and **Events API** callbacks — POSTed to the host app's real endpoints with a working `response_url` and optional Slack request signing.
- Test: `Slackbox.Adapters.Test` + `Slackbox.TestAssertions` for outbound; `Slackbox.Test` payload builders for inbound controller tests.

**Non-goals (v1)**
- Slash commands (deferred; easy add later).
- Socket Mode / RTM.
- Persistence of the dev store across restarts (purely in-memory, like Swoosh's Local).
- A standalone (non-Phoenix) dashboard — the host app is assumed to be Phoenix + LiveView.
- Full coverage of the entire Slack Web API surface — only the methods used (see §4).

## 3. Architecture overview

```
YourApp.Slack.post_message(channel: "#alerts", blocks: [...])
        │
        ▼
  MyApp.Slack (use Slackbox.Notifier)   ← the one choke point
        │  dispatches to configured adapter (per env)
        ├── Slackbox.Adapters.Live   → real Slack Web API (Req, bot token)      [prod]
        ├── Slackbox.Adapters.Local  → in-memory Store + LiveView fake Slack UI [dev]
        └── Slackbox.Adapters.Test   → test-process capture + assertions        [test]
```

**Two directions, one dev server (dev only):**
- **Outbound (app → Slack):** `Local` writes each message into `Slackbox.Store`; PubSub notifies the LiveView dashboard, which renders it instantly.
- **Inbound (Slack → app):** a UI interaction (button click / modal submit / simulated event) is turned by `Slackbox.Simulator` into a real-shaped Slack payload and POSTed to the host app's configured request URL. The `response_url` handed to the app routes back into the `Store` (in-process, via the `respond/2` choke point), so the UI updates when the app replies.

## 4. Message model & outbound API

### 4.1 `Slackbox.Message` struct + builders

The Slack analogue of `Swoosh.Email`. Composable pipe builders; a raw JSON map is always accepted as an escape hatch.

```elixir
import Slackbox.Message

new()
|> to_channel("#alerts")
|> text("Build failed on main")            # fallback text
|> blocks([
     section("Build *failed* on `main`"),
     actions([button("Retry", action_id: "retry_build", value: "1234")])
   ])
|> thread(parent_ts)                        # optional threading
|> unfurl_links(false)
|> to_user("U123")                          # target for post_ephemeral
```

Fields: `:channel`, `:text`, `:blocks`, `:attachments` (legacy), `:thread_ts`, `:ts` (assigned on delivery), `:user`, `:username`/`:icon` overrides, `:metadata`, plus API flags (`:unfurl_links`, `:unfurl_media`, `:reply_broadcast`, …).

**Message identity:** `ts` is the identity. `post_message` assigns it (`Live` → Slack's real value, `Local` → a generated fake). `update`/`delete`/threading reference it. App code that stores a `ts` and later updates it behaves identically in dev and prod.

### 4.2 Notifier module

```elixir
defmodule MyApp.Slack do
  use Slackbox.Notifier, otp_app: :my_app
end
```

Generated functions dispatch to the configured adapter. Each takes an optional trailing `opts` keyword list for **runtime/adapter overrides** (token, timeout, per-call config) and rare API flags — *not* message content (that lives on the struct):

| Function | Slack method | Returns |
|---|---|---|
| `post_message(message, opts \\ [])` (alias `deliver/1,2`) | chat.postMessage | `{:ok, %{ts, channel}}` |
| `post_ephemeral(message, opts \\ [])` | chat.postEphemeral | `{:ok, %{}}` |
| `update(message, opts \\ [])` | chat.update | `{:ok, %{ts, channel}}` |
| `delete(message, opts \\ [])` | chat.delete | `{:ok, %{}}` |
| `open_view(trigger_id, view, opts \\ [])` | views.open | `{:ok, %{view_id}}` |
| `respond(response_url, message, opts \\ [])` | response_url POST | `{:ok, %{}}` |

**Rule of thumb:** if it changes *what the message is*, it's a builder on the struct; if it changes *how/where this one call is delivered*, it's `opts`. This preserves "the struct alone determines what the fake UI shows."

### 4.3 Adapter behaviour

`Slackbox.Adapter` defines callbacks for the methods above. Each adapter implements them:
- `Live` — thin `Req`-based Web API client (bot token auth, error/rate-limit handling). Owned by us; a small internal seam allows swapping the HTTP layer later, but no third-party Slack dependency in v1.
- `Local` — writes to / mutates `Slackbox.Store`.
- `Test` — sends the call to the test process mailbox (respects `$callers` for `async: true`).

## 5. Dev-only runtime (Local adapter)

Started by a `Slackbox.Dev` supervisor added to the host app's tree in `dev` (mirrors Swoosh's Local memory store).

- **`Slackbox.Store`** — GenServer + ETS. Messages keyed by `{channel, ts}`; also threads, ephemeral messages, and open modal views. In-memory only; cleared on restart.
- **PubSub** — every insert/update/delete broadcasts so the dashboard reflects changes in real time.
- **`Slackbox.Simulator`** — turns a UI interaction into a real-shaped Slack payload and POSTs it to the host app.

### 5.1 Inbound loop

```
[Fake Slack UI]  ── click "Retry" ──▶
  Simulator builds a block_actions payload
    (fresh trigger_id, response_url token, optionally SIGNED)
      ── HTTP POST ──▶  host app's real endpoint (interactivity_url)
        controller runs for real and calls back through Slackbox:
           MyApp.Slack.respond(response_url, msg)   → updates that message in the UI
           MyApp.Slack.open_view(trigger_id, modal) → modal appears in the UI
           MyApp.Slack.post_message(...)            → new message appears
```

- **`response_url` is in-process.** Because the reply goes through `respond/2` (our choke point), `Local` recognizes the token and writes straight to the `Store` — no HTTP round-trip — while prod code is unchanged.
- **Signing (optional).** With a configured `signing_secret`, the Simulator adds `X-Slack-Signature` / `X-Slack-Request-Timestamp` so the app's *real* verification plug passes in dev instead of being bypassed.
- **trigger_id lifecycle.** A button click mints a `trigger_id`; the app calls `open_view(trigger_id, view)`; `Local` stores the modal and the dashboard renders it; submitting sends a `view_submission` payload carrying the view state.

### 5.2 Configuration

```elixir
config :my_app, MyApp.Slack,
  adapter: Slackbox.Adapters.Local,
  simulate: [
    interactivity_url: "http://localhost:4000/slack/interactivity",
    events_url:        "http://localhost:4000/slack/events",
    signing_secret:    System.get_env("SLACK_SIGNING_SECRET")  # optional
  ]
```

## 6. Dev UI (LiveView dashboard)

Mounted in the host app's router behind a dev-only pipeline, e.g. `/dev/slack` (parallels Swoosh's `/dev/mailbox`).

- **Look: faithful Slack clone** — workspace sidebar, channel list, messages with avatars/timestamps, Block Kit rendered (sections, buttons, selects, datepickers, etc.). Channels derived from the `:channel` of stored messages.
- **Raw-payload inspector** — a slide-out panel per message showing the exact JSON payload (the `{ }` toggle), for debugging serialization.
- **Interactivity** — clicking a rendered Block Kit element triggers the inbound loop (§5.1). Threads render inline/expandable.
- **Simulate control** — a toolbar affordance to fire an Events API callback (and other non-message inbound events) at the host app.
- **Real-time** — LiveView + PubSub; messages and updates appear the instant the app posts them, no polling.

## 7. Testing support

- **`Slackbox.Adapters.Test`** + **`Slackbox.TestAssertions`** (outbound):
  ```elixir
  import Slackbox.TestAssertions
  assert_message_sent(channel: "#alerts", text: ~r/failed/)
  assert_message_sent(fn msg -> assert Slackbox.Message.action_ids(msg) == ["retry_build"] end)
  refute_message_sent(channel: "#general")
  ```
  Plus `assert_ephemeral_sent/1`, `assert_view_opened/1`, `assert_message_updated/1`.
- **`Slackbox.Test` payload builders** (inbound controller tests):
  ```elixir
  payload = Slackbox.Test.block_actions(action_id: "retry_build", user: "U1", channel: "#alerts")
  conn = post(conn, "/slack/interactivity", payload)   # signed if secret configured
  ```

## 8. Packaging & dependencies

- A **Mix library** (scaffolded via `elixir-scaffold:new-elixir-project`, Mix Library type).
- Deps: `req` (HTTP for Live + Simulator), `jason`, `phoenix_live_view` + `phoenix_pubsub` (dashboard). LiveView is a hard dependency (acceptable: all target apps are Phoenix LiveView).
- Host-app integration: add `use Slackbox.Notifier`, configure the adapter per env, add `Slackbox.Dev` to the dev supervision tree, and mount the dashboard route.

## 9. Suggested build phases (for the implementation plan)

1. **Core outbound + Test adapter.** `Message` struct + builders, `Notifier`, `Adapter` behaviour, `Test` adapter, `TestAssertions`. (Delivers value immediately: assertable Slack sending.)
2. **Live adapter.** `Req`-based Web API client for the six methods; real bot-token config. ✅ Done (`Slackbox.Adapters.Live`).
3. **Local store + dashboard (outbound only).** `Store`, PubSub, LiveView Slack-clone UI rendering messages/blocks + raw inspector. (Delivers the "fake mailbox" experience.)
4. **Inbound simulation — interactive components.** `Simulator`, `trigger_id`/`response_url` lifecycle, in-process `respond/2` routing, optional signing. The button-click loop.
5. **Inbound simulation — modals/views + Events API.** Modal rendering + `view_submission`; event simulate control; `Slackbox.Test` inbound payload builders.

## 10. Open questions / deferred

- Slack request **signing** helper: ship a verification plug too, or only sign outbound sim payloads? (Lean: sign sim payloads in v1; a verification plug is a natural later add.)
- Multi-workspace modeling in the UI (v1 assumes a single workspace).
- Whether `Live` should eventually be backed by `slack_elixir` behind the HTTP seam (deferred; not a v1 dependency).
