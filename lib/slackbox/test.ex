defmodule Slackbox.Test do
  @moduledoc """
  Pure inbound-payload builders for unit-testing your Slack endpoints.

  These build the exact payloads Slack (and `Slackbox.Simulator`) POST to your
  app — `block_actions`, `view_submission`, and Events API `event_callback`
  envelopes — so you can drive your controllers/plugs directly, no UI or HTTP
  server required. They delegate to the `Slackbox.Simulator.build_*` functions,
  so the shapes stay identical to the live simulation loop.

  ## Example

      payload = Slackbox.Test.block_actions(action_id: "retry", user: "U1", channel: "#alerts")
      conn = post(conn, "/slack/interactivity", Slackbox.Test.form_body(payload))

  For the Events API, POST the JSON directly instead:

      payload = Slackbox.Test.event("app_mention", %{"text" => "<@U_BOT> hi"})
      conn = post(conn, "/slack/events", Jason.encode!(payload))
  """

  alias Slackbox.Signature
  alias Slackbox.Simulator

  @default_message %{
    "type" => "message",
    "text" => "hello",
    "ts" => "1.1"
  }

  @doc """
  Build a `block_actions` payload.

  Options: `:action_id`, `:value`, `:user` (default `"U_TEST"`), `:channel`
  (default `"#test"`), `:message` (default a minimal raw message map),
  `:response_url` (default `"https://example.test/response"`).
  """
  @spec block_actions(keyword()) :: map()
  def block_actions(opts \\ []) do
    channel = Keyword.get(opts, :channel, "#test")
    message = Keyword.get(opts, :message, @default_message)
    entry = %{channel: channel, ts: "1.1", raw: message}

    action = %{
      "action_id" => Keyword.get(opts, :action_id),
      "value" => Keyword.get(opts, :value)
    }

    Simulator.build_block_actions(entry, action, %{
      user: Keyword.get(opts, :user, "U_TEST"),
      response_url: Keyword.get(opts, :response_url, "https://example.test/response")
    })
  end

  @doc """
  Build a `view_submission` payload.

  Options: `:callback_id`, `:view_id` (default `"V_TEST"`), `:state`
  (default `%{}`), `:user` (default `"U_TEST"`).
  """
  @spec view_submission(keyword()) :: map()
  def view_submission(opts \\ []) do
    view = %{"callback_id" => Keyword.get(opts, :callback_id), "type" => "modal"}

    Simulator.build_view_submission(
      Keyword.get(opts, :view_id, "V_TEST"),
      view,
      Keyword.get(opts, :state, %{}),
      %{user: Keyword.get(opts, :user, "U_TEST")}
    )
  end

  @doc """
  Build an Events API `event_callback` payload wrapping an event of `type`.

  `opts` (a keyword list or map) is merged, with string keys, into the event.
  """
  @spec event(String.t(), keyword() | map()) :: map()
  def event(type, opts \\ []) do
    extra = opts |> Map.new() |> Map.new(fn {k, v} -> {to_string(k), v} end)
    Simulator.build_event_callback(Map.merge(%{"type" => type}, extra))
  end

  @doc """
  Encode `payload` as an `application/x-www-form-urlencoded` body for
  interaction endpoints (`payload=<json>`).
  """
  @spec form_body(map()) :: binary()
  def form_body(payload), do: "payload=" <> URI.encode_www_form(Jason.encode!(payload))

  @doc """
  Build Slack signing headers (`x-slack-request-timestamp` + `x-slack-signature`)
  for `body` under `secret`, for tests that verify signature checking.
  """
  @spec signature_headers(String.t(), binary()) :: [{binary(), binary()}]
  def signature_headers(secret, body) do
    ts = "#{System.system_time(:second)}"

    [
      {"x-slack-request-timestamp", ts},
      {"x-slack-signature", Signature.sign(secret, ts, body)}
    ]
  end
end
