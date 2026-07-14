defmodule Slackbox do
  @moduledoc """
  Slackbox — a Swoosh-style Slack library.

  Define a notifier with `use Slackbox.Notifier` and send messages through it; a
  per-environment adapter decides where they go: `Slackbox.Adapters.Live` (real
  Slack) in prod, `Slackbox.Adapters.Local` (the fake Slack dev UI) in dev, and
  `Slackbox.Adapters.Test` (with `Slackbox.TestAssertions`) in tests.

  See `Slackbox.Notifier` and `Slackbox.Message` to get started.
  """
end
