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

