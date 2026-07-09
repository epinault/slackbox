defmodule Slackbox.Store do
  @moduledoc """
  In-memory store of Slack messages for the fake-Slack dev UI.

  A `GenServer` that keeps an ordered list of entries (insertion order). Each
  entry is a map: `%{ts:, channel:, message:, raw:, at:}`. On every `put/1` and
  `clear/0` it broadcasts `{:slackbox_store, op, entry_or_nil}` on the
  `"slackbox"` topic of the `Slackbox.PubSub` server — but only when that
  PubSub server is actually running, so the store stays usable in plain tests.
  """

  use GenServer

  alias Slackbox.Message

  @pubsub Slackbox.PubSub
  @topic "slackbox"

  @type entry :: %{
          ts: String.t(),
          channel: String.t() | nil,
          message: Message.t(),
          raw: map(),
          at: integer()
        }

  @type view :: %{view_id: String.t(), trigger_id: String.t(), view: map()}

  @doc "Start the store (registered under its module name by default)."
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, :ok, name: name)
  end

  @doc """
  Store a message. Assigns a `ts` if the message has none, computes the raw
  Slack payload, appends an entry, and returns `%{ts:, channel:}`.
  """
  @spec put(Message.t()) :: %{ts: String.t(), channel: String.t() | nil}
  def put(%Message{} = message), do: GenServer.call(__MODULE__, {:put, message})

  @doc "List every channel that has at least one message, in insertion order."
  @spec list_channels() :: [String.t()]
  def list_channels, do: GenServer.call(__MODULE__, :list_channels)

  @doc "List the entries for a channel, in insertion order."
  @spec list_messages(String.t() | nil) :: [entry()]
  def list_messages(channel), do: GenServer.call(__MODULE__, {:list_messages, channel})

  @doc "Drop every stored message."
  @spec clear() :: :ok
  def clear, do: GenServer.call(__MODULE__, :clear)

  @doc """
  Register a `response_url` callback token for the entry identified by
  `{channel, ts}`. Returns an opaque random token; a later `apply_response/2`
  with that token updates the corresponding message. Mirrors Slack's
  `response_url` mechanism for the inbound simulation loop.
  """
  @spec register_response(String.t() | nil, String.t()) :: String.t()
  def register_response(channel, ts),
    do: GenServer.call(__MODULE__, {:register_response, channel, ts})

  @doc """
  Apply a Slack response payload to the message a `token` points at.

  `response_map["text"]` overrides the message text when present and
  `response_map["blocks"]` overrides the blocks when present; the raw payload is
  recomputed and a `{:slackbox_store, :update, entry}` broadcast is emitted.
  Returns `{:error, :not_found}` for an unknown token.
  """
  @spec apply_response(String.t(), map()) :: :ok | {:error, :not_found}
  def apply_response(token, response_map),
    do: GenServer.call(__MODULE__, {:apply_response, token, response_map})

  @doc """
  Open a modal `view` for `trigger_id`. Generates a `view_id`, appends a view
  entry, broadcasts `{:slackbox_store, :view_open, entry}`, and returns
  `%{view_id: view_id}` — mirroring Slack's `views.open` response.
  """
  @spec open_view(String.t(), map()) :: %{view_id: String.t()}
  def open_view(trigger_id, view),
    do: GenServer.call(__MODULE__, {:open_view, trigger_id, view})

  @doc """
  Close the modal identified by `view_id`, broadcasting
  `{:slackbox_store, :view_close, view_id}`.
  """
  @spec close_view(String.t()) :: :ok
  def close_view(view_id), do: GenServer.call(__MODULE__, {:close_view, view_id})

  @doc "List the currently open modal views, in insertion order (newest last)."
  @spec list_views() :: [view()]
  def list_views, do: GenServer.call(__MODULE__, :list_views)

  @impl GenServer
  def init(:ok), do: {:ok, %{entries: [], tokens: %{}, views: []}}

  @impl GenServer
  def handle_call({:put, message}, _from, %{entries: entries} = state) do
    ts = message.ts || generate_ts()
    message = %{message | ts: ts}

    entry = %{
      ts: ts,
      channel: message.channel,
      message: message,
      raw: Message.to_payload(message),
      at: System.system_time(:millisecond)
    }

    broadcast(:put, entry)
    {:reply, %{ts: ts, channel: message.channel}, %{state | entries: entries ++ [entry]}}
  end

  def handle_call(:list_channels, _from, %{entries: entries} = state) do
    channels =
      entries
      |> Enum.map(& &1.channel)
      |> Enum.uniq()

    {:reply, channels, state}
  end

  def handle_call({:list_messages, channel}, _from, %{entries: entries} = state) do
    {:reply, Enum.filter(entries, &(&1.channel == channel)), state}
  end

  def handle_call(:clear, _from, state) do
    broadcast(:clear, nil)
    {:reply, :ok, %{state | entries: [], tokens: %{}, views: []}}
  end

  def handle_call({:open_view, trigger_id, view}, _from, %{views: views} = state) do
    view_id = "V" <> (:crypto.strong_rand_bytes(12) |> Base.url_encode64(padding: false))
    entry = %{view_id: view_id, trigger_id: trigger_id, view: view}
    broadcast(:view_open, entry)
    {:reply, %{view_id: view_id}, %{state | views: views ++ [entry]}}
  end

  def handle_call({:close_view, view_id}, _from, %{views: views} = state) do
    broadcast(:view_close, view_id)
    {:reply, :ok, %{state | views: Enum.reject(views, &(&1.view_id == view_id))}}
  end

  def handle_call(:list_views, _from, %{views: views} = state) do
    {:reply, views, state}
  end

  def handle_call({:register_response, channel, ts}, _from, %{tokens: tokens} = state) do
    token = :crypto.strong_rand_bytes(12) |> Base.url_encode64(padding: false)
    {:reply, token, %{state | tokens: Map.put(tokens, token, {channel, ts})}}
  end

  def handle_call({:apply_response, token, response_map}, _from, %{tokens: tokens} = state) do
    case Map.fetch(tokens, token) do
      {:ok, {channel, ts}} ->
        {entries, updated} = update_entry(state.entries, channel, ts, response_map)
        Enum.each(updated, &broadcast(:update, &1))
        {:reply, :ok, %{state | entries: entries}}

      :error ->
        {:reply, {:error, :not_found}, state}
    end
  end

  defp update_entry(entries, channel, ts, response_map) do
    Enum.map_reduce(entries, [], fn entry, acc ->
      if entry.channel == channel and entry.ts == ts do
        message = apply_response_to_message(entry.message, response_map)
        updated = %{entry | message: message, raw: Message.to_payload(message)}
        {updated, [updated | acc]}
      else
        {entry, acc}
      end
    end)
  end

  defp apply_response_to_message(message, response_map) do
    message
    |> maybe_override(:text, Map.get(response_map, "text"))
    |> maybe_override(:blocks, Map.get(response_map, "blocks"))
  end

  defp maybe_override(message, _key, nil), do: message
  defp maybe_override(message, key, value), do: Map.put(message, key, value)

  defp generate_ts do
    "#{System.system_time(:second)}.#{:erlang.unique_integer([:positive])}"
  end

  defp broadcast(op, entry) do
    if Process.whereis(@pubsub) do
      Phoenix.PubSub.broadcast(@pubsub, @topic, {:slackbox_store, op, entry})
    end

    :ok
  end
end
