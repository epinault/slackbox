defmodule Slackbox.Adapter do
  @moduledoc """
  The contract every Slackbox adapter implements (`Live`, `Local`, `Test`).

  A single `call/3` entry point dispatches every Slack action, so adapters can
  pattern-match on the action atom rather than implementing one callback each.
  """

  @type action :: :post_message | :post_ephemeral | :update | :delete | :open_view | :respond
  @type args :: map()
  @type config :: keyword()

  @callback call(action(), args(), config()) :: {:ok, map()} | {:error, term()}
end
