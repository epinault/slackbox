defmodule Slackbox.Message do
  @moduledoc """
  A Slack message with composable pipe builders — the Slack analogue of
  `Swoosh.Email`. The struct alone fully determines what the fake Slack dev UI
  renders, so message *content* lives here (not in per-call options).

  A raw Slack JSON map may be supplied via `:raw` as an escape hatch.
  """

  @type t :: %__MODULE__{
          channel: String.t() | nil,
          text: String.t() | nil,
          blocks: [map()],
          attachments: [map()],
          thread_ts: String.t() | nil,
          ts: String.t() | nil,
          user: String.t() | nil,
          username: String.t() | nil,
          icon: String.t() | nil,
          metadata: map(),
          unfurl_links: boolean() | nil,
          unfurl_media: boolean() | nil,
          reply_broadcast: boolean() | nil,
          raw: map() | nil
        }

  defstruct channel: nil,
            text: nil,
            blocks: [],
            attachments: [],
            thread_ts: nil,
            ts: nil,
            user: nil,
            username: nil,
            icon: nil,
            metadata: %{},
            unfurl_links: nil,
            unfurl_media: nil,
            reply_broadcast: nil,
            raw: nil

  @doc "Build a new message from keyword/map attrs."
  @spec new(keyword() | map()) :: t()
  def new(attrs \\ []), do: struct(__MODULE__, attrs)

  @doc "Set the destination channel (e.g. `\"#alerts\"` or a channel id)."
  @spec to_channel(t(), String.t()) :: t()
  def to_channel(%__MODULE__{} = msg, channel), do: %{msg | channel: channel}

  @doc "Set the fallback/notification text."
  @spec text(t(), String.t()) :: t()
  def text(%__MODULE__{} = msg, text), do: %{msg | text: text}

  @doc "Post this message as a threaded reply to `parent_ts`."
  @spec thread(t(), String.t()) :: t()
  def thread(%__MODULE__{} = msg, parent_ts), do: %{msg | thread_ts: parent_ts}

  @doc "Target user for `post_ephemeral`."
  @spec to_user(t(), String.t()) :: t()
  def to_user(%__MODULE__{} = msg, user), do: %{msg | user: user}

  @doc "Toggle Slack link unfurling for this message."
  @spec unfurl_links(t(), boolean()) :: t()
  def unfurl_links(%__MODULE__{} = msg, bool), do: %{msg | unfurl_links: bool}

  @doc "Set the Block Kit blocks for this message."
  @spec blocks(t(), [map()]) :: t()
  def blocks(%__MODULE__{} = msg, blocks), do: %{msg | blocks: blocks}

  @doc "A Block Kit `section` block with mrkdwn text."
  @spec section(String.t()) :: map()
  def section(text) do
    %{"type" => "section", "text" => %{"type" => "mrkdwn", "text" => text}}
  end

  @doc "A Block Kit `actions` block wrapping interactive elements."
  @spec actions([map()]) :: map()
  def actions(elements), do: %{"type" => "actions", "elements" => elements}

  @doc """
  A Block Kit `button` element. Supported opts: `:action_id`, `:value`.
  Nil opts are dropped so the payload matches Slack's shape.
  """
  @spec button(String.t(), keyword()) :: map()
  def button(text, opts \\ []) do
    %{"type" => "button", "text" => %{"type" => "plain_text", "text" => text}}
    |> maybe_put("action_id", Keyword.get(opts, :action_id))
    |> maybe_put("value", Keyword.get(opts, :value))
  end

  @doc "Collect every `action_id` from the message's `actions` blocks, in order."
  @spec action_ids(t()) :: [String.t()]
  def action_ids(%__MODULE__{blocks: blocks}) do
    blocks
    |> Enum.filter(&(&1["type"] == "actions"))
    |> Enum.flat_map(fn block -> Enum.map(block["elements"] || [], & &1["action_id"]) end)
    |> Enum.reject(&is_nil/1)
  end

  @doc "Serialize to a Slack Web API payload map (drops nil/empty fields)."
  @spec to_payload(t()) :: map()
  def to_payload(%__MODULE__{} = m) do
    %{"channel" => m.channel}
    |> maybe_put("text", m.text)
    |> maybe_put("blocks", (m.blocks != [] && m.blocks) || nil)
    |> maybe_put("thread_ts", m.thread_ts)
    |> maybe_put("ts", m.ts)
    |> maybe_put("user", m.user)
    |> maybe_put("username", m.username)
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
