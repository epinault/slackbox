defmodule Slackbox.Simulator do
  @moduledoc """
  Turns a UI button click in the fake-Slack dashboard into a realistic inbound
  Slack interaction.

  When a user clicks a Block Kit button, Slack POSTs a `block_actions`
  interaction payload to your app's *interactivity request URL* (as
  `application/x-www-form-urlencoded` with a single `payload` field). Your app
  replies out-of-band by POSTing to the interaction's `response_url`.

  `click/3` reproduces that exact flow over real HTTP against a configured
  endpoint, wiring in a `response_url` that routes back into `Slackbox.Store`
  (see `Slackbox.ResponsePlug`) so the message can be updated live.
  """

  alias Slackbox.Signature
  alias Slackbox.Store

  @api_app_id "A_SLACKBOX"
  @verification_token "slackbox-verification-token"
  @default_user "U_DEMO"

  @doc """
  Build the Slack `block_actions` interaction payload for `action` on `entry`.

  `action` is a map with `"action_id"` and optional `"value"`. `opts` carries
  `:user` and `:response_url`. Exposed for testing.
  """
  @spec build_block_actions(map(), map(), map()) :: map()
  def build_block_actions(entry, action, opts) do
    action_ts = "#{System.system_time(:millisecond) / 1000}"

    %{
      "type" => "block_actions",
      "user" => %{"id" => Map.get(opts, :user, @default_user)},
      "api_app_id" => @api_app_id,
      "token" => @verification_token,
      "trigger_id" => trigger_id(),
      "response_url" => Map.get(opts, :response_url),
      "channel" => %{"id" => entry.channel, "name" => channel_name(entry.channel)},
      "message" => entry.raw,
      "actions" => [
        %{
          "type" => "button",
          "action_id" => action["action_id"],
          "value" => action["value"],
          "block_id" => "b",
          "action_ts" => action_ts
        }
      ]
    }
  end

  @doc """
  Simulate a click on `action` for `entry`, POSTing a `block_actions`
  interaction to `config.interactivity_url` over real HTTP.

  `config` keys: `:interactivity_url`, `:response_base`, `:signing_secret`
  (`nil` = unsigned), `:user` (default `"U_DEMO"`). Returns `{:ok, status}` on a
  completed request or `{:error, reason}` — it never raises into the caller.
  """
  @spec click(map(), map(), map()) :: {:ok, integer()} | {:error, term()}
  def click(entry, action, config) do
    token = Store.register_response(entry.channel, entry.ts)
    response_url = config.response_base <> "/" <> token
    user = Map.get(config, :user, @default_user)

    payload = build_block_actions(entry, action, %{user: user, response_url: response_url})
    body = "payload=" <> URI.encode_www_form(Jason.encode!(payload))
    headers = build_headers(body, Map.get(config, :signing_secret))

    case Req.post(config.interactivity_url, headers: headers, body: body) do
      {:ok, %Req.Response{status: status}} -> {:ok, status}
      {:error, reason} -> {:error, reason}
    end
  rescue
    error -> {:error, error}
  end

  defp build_headers(body, signing_secret) when is_binary(signing_secret) do
    ts = "#{System.system_time(:second)}"

    [
      {"content-type", "application/x-www-form-urlencoded"},
      {"x-slack-request-timestamp", ts},
      {"x-slack-signature", Signature.sign(signing_secret, ts, body)}
    ]
  end

  defp build_headers(_body, _signing_secret) do
    [{"content-type", "application/x-www-form-urlencoded"}]
  end

  defp trigger_id do
    "#{System.system_time(:millisecond)}.#{:erlang.unique_integer([:positive])}.slackbox"
  end

  defp channel_name(nil), do: nil
  defp channel_name(channel), do: String.trim_leading(channel, "#")
end
