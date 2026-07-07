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
end
