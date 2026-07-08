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

  @impl GenServer
  def init(:ok), do: {:ok, %{entries: []}}

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
    {:reply, :ok, %{state | entries: []}}
  end

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
