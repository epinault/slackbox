# Slackbox

**TODO: Add description**

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

