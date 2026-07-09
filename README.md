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

