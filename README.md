# Slackbox

**TODO: Add description**

## Trying the fake Slack UI (dev)

Run the self-contained demo server from the project root:

```bash
mix slackbox.demo
```

Then open <http://localhost:4000>. You'll see a Slack-like UI — a channel
sidebar, messages rendered with Block Kit (section text + buttons), and a
per-message "{ } raw" toggle that shows the outgoing Slack payload. Seeded
messages land in `#alerts` and `#deploys`.

Messages update in real time (LiveView). To push your own from an IEx session:

```bash
iex -S mix
```

```elixir
Slackbox.Demo.start()
Slackbox.Demo.post("hello", "#alerts")
```

The new message appears in the browser instantly. Under the hood the
`Slackbox.Adapters.Local` adapter writes messages into the in-memory
`Slackbox.Store`, which broadcasts over `Phoenix.PubSub` to the dashboard.

### Interactive components (inbound loop)

Block Kit buttons in the dashboard are live. Clicking one fires a **realistic
simulated Slack `block_actions` interaction** — a real HTTP POST
(`application/x-www-form-urlencoded`, single `payload` field, optionally signed
with HMAC-SHA256) to your app's interactivity URL. Your app replies to the
interaction's `response_url`, and that reply updates the originating message
live in the dashboard.

In `mix slackbox.demo` this whole loop is wired for you: a sample app
(`Slackbox.Demo.SlackApp`, mounted at `/demo/interactivity`) acknowledges the
click and posts back to the `response_url`, so clicking **Acknowledge** or
**Rollback** appends a `✅ ...clicked by @U_DEMO` line to the message in front of
you — no browser automation, real HTTP end to end.

The dashboard reads its simulation config from
`Application.get_env(:slackbox, :simulator)`, a map with these keys:

- `:interactivity_url` — where the simulated interaction POST is sent
  (your app's Slack interactivity request URL).
- `:response_base` — base URL for `response_url`; the store token is appended.
  Mount `Slackbox.ResponsePlug` here to route callbacks back into the store.
- `:signing_secret` — Slack signing secret; when set, requests carry
  `x-slack-request-timestamp` + `x-slack-signature`. `nil` = unsigned.
- `:user` — the simulated Slack user id (default `"U_DEMO"`).

A real app wires the same values from its own config, e.g.:

```elixir
# config/dev.exs
config :my_app, MyApp.Slack,
  simulate: [
    interactivity_url: "http://localhost:4000/slack/interactivity",
    response_base: "http://localhost:4000/slackbox/response",
    signing_secret: System.get_env("SLACK_SIGNING_SECRET")
  ]
```

then mounts `Slackbox.ResponsePlug` (at `response_base`) in its router to close
the loop, and puts the resolved map into `:slackbox, :simulator` before serving
the dashboard.

### Modals & events

The dashboard also simulates **modals (views)** and the **Events API**.

**Modal loop.** When your app calls `open_view(trigger_id, view)` (or, in the
demo, when a `block_actions` handler does), the modal is registered in the store
and pops up as an overlay in the dashboard. The user fills the inputs and clicks
**Save**, firing a real HTTP `view_submission` POST to your interactivity URL;
your app reads `view.state.values` and reacts. **Close** fires `view_closed`
instead. In `mix slackbox.demo`: open `#alerts`, click **Open config** → a
"Configure alert" modal appears → type a name → **Save**, and the sample app
posts a `🛠️ Config saved: name = …` message back into `#alerts`.

**Events.** The message-pane header has a **⚡ Simulate event** button. Clicking
it delivers an `event_callback` (an `app_mention`) to your app's Events API URL
as an `application/json` body (signed over the raw body when a secret is set).
The demo app replies with a `👋 …you rang?` message. This needs one extra
simulator config key:

- `:events_url` — your app's Slack Events API request URL. Events use a JSON
  body (not form-urlencoded); leave unset to disable the Simulate-event button.

### Unit-testing your endpoints (`Slackbox.Test`)

`Slackbox.Test` builds the same inbound payloads without the UI or a server, so
you can drive your controllers/plugs directly:

```elixir
# block_actions — form-urlencoded interaction body
payload = Slackbox.Test.block_actions(action_id: "retry", user: "U1", channel: "#alerts")
conn = post(conn, "/slack/interactivity", Slackbox.Test.form_body(payload))

# view_submission
state = %{"name_block" => %{"name" => %{"type" => "plain_text_input", "value" => "prod"}}}
payload = Slackbox.Test.view_submission(callback_id: "config_modal", state: state)

# Events API — JSON body
payload = Slackbox.Test.event("app_mention", text: "<@U_BOT> hi", channel: "#alerts")
conn = post(conn, "/slack/events", Jason.encode!(payload))
```

`Slackbox.Test.signature_headers/2` builds matching signing headers for tests
that verify signature checking.

## Usage (outbound + tests)

Define a notifier:

```elixir
defmodule MyApp.Slack do
  use Slackbox.Notifier, otp_app: :my_app
end
```

Configure the adapter per environment:

```elixir
# config/test.exs
config :my_app, MyApp.Slack, adapter: Slackbox.Adapters.Test
```

Send messages through the one choke point:

```elixir
import Slackbox.Message

new()
|> to_channel("#alerts")
|> text("Build failed on main")
|> blocks([
     section("Build *failed* on `main`"),
     actions([button("Retry", action_id: "retry_build", value: "1234")])
   ])
|> MyApp.Slack.post_message()
```

Assert in tests:

```elixir
import Slackbox.TestAssertions

test "notifies #alerts on failure" do
  MyApp.Notifier.on_build_failed(build)
  assert_message_sent(channel: "#alerts", text: ~r/failed/)
  refute_message_sent(channel: "#general")
end
```

## Sending to real Slack (prod)

Swap in the `Live` adapter and give it a bot token — it's a thin
[`Req`](https://hexdocs.pm/req)-based Slack Web API client:

```elixir
# config/prod.exs
config :my_app, MyApp.Slack,
  adapter: Slackbox.Adapters.Live,
  token: System.get_env("SLACK_BOT_TOKEN")
```

The **same** `MyApp.Slack.post_message(...)` (and `update`, `delete`,
`post_ephemeral`, `open_view`, `respond`) code runs in every environment — only
the configured adapter changes:

| Env  | Adapter                    | What happens                              |
| ---- | -------------------------- | ----------------------------------------- |
| dev  | `Slackbox.Adapters.Local`  | renders in the fake Slack dev UI          |
| test | `Slackbox.Adapters.Test`   | captured for `assert_message_sent/1`      |
| prod | `Slackbox.Adapters.Live`   | posts to the real Slack Web API           |

`Live` maps each action to its Slack method (`chat.postMessage`, `chat.update`,
`chat.delete`, `chat.postEphemeral`, `views.open`, and a direct POST to a
`response_url` for `respond`), returns `{:ok, %{ts:, channel:}}` /
`{:ok, %{view_id:}}` on success, and tagged errors otherwise —
`{:error, {:slack, reason}}`, `{:error, {:rate_limited, retry_after}}`,
`{:error, {:http, status}}`, or `{:error, :missing_token}`. Extra config keys:
`:base_url` (defaults to `https://slack.com/api`) and `:req_options` (merged
into every `Req` request, e.g. timeouts/retries).

