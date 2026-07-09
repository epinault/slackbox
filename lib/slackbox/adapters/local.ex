defmodule Slackbox.Adapters.Local do
  @moduledoc """
  Local adapter. Persists outbound messages into the in-memory `Slackbox.Store`
  (which powers the fake-Slack dev UI) instead of talking to the real Slack API.

  `open_view` opens a modal in the store (surfaced by the dev UI). The remaining
  interactive actions (`respond`, `delete`) are safe no-ops here.
  """

  @behaviour Slackbox.Adapter

  alias Slackbox.Store

  @impl Slackbox.Adapter
  def call(:post_message, %{message: msg}, _config) do
    {:ok, Store.put(msg)}
  end

  def call(:post_ephemeral, %{message: msg}, _config) do
    Store.put(msg)
    {:ok, %{}}
  end

  def call(:update, %{message: msg}, _config) do
    Store.put(msg)
    {:ok, %{ts: msg.ts, channel: msg.channel}}
  end

  def call(:open_view, %{trigger_id: trigger_id, view: view}, _config) do
    {:ok, Store.open_view(trigger_id, view)}
  end

  def call(_action, _args, _config), do: {:ok, %{}}
end
