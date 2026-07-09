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
    post_interaction(config.interactivity_url, payload, config)
  end

  @doc """
  Build a Slack `view_submission` interaction payload.

  Merges `view_id` and the collected `state` (Block Kit `state.values`) into
  `view`. `opts` carries `:user`. Exposed for testing.
  """
  @spec build_view_submission(String.t(), map(), map(), map()) :: map()
  def build_view_submission(view_id, view, state, opts) do
    %{
      "type" => "view_submission",
      "user" => %{"id" => Map.get(opts, :user, @default_user)},
      "api_app_id" => @api_app_id,
      "token" => @verification_token,
      "trigger_id" => trigger_id(),
      "view" => Map.merge(view, %{"id" => view_id, "state" => %{"values" => state}})
    }
  end

  @doc """
  Simulate a modal submission, POSTing a `view_submission` interaction to
  `config.interactivity_url`. Signed when `config.signing_secret` is set.
  """
  @spec submit_view(String.t(), map(), map(), map()) :: {:ok, integer()} | {:error, term()}
  def submit_view(view_id, view, state, config) do
    user = Map.get(config, :user, @default_user)
    payload = build_view_submission(view_id, view, state, %{user: user})
    post_interaction(config.interactivity_url, payload, config)
  end

  @doc """
  Build a Slack `view_closed` interaction payload. `opts` carries `:user`.
  Exposed for testing.
  """
  @spec build_view_closed(String.t(), map(), map()) :: map()
  def build_view_closed(view_id, view, opts) do
    %{
      "type" => "view_closed",
      "user" => %{"id" => Map.get(opts, :user, @default_user)},
      "api_app_id" => @api_app_id,
      "token" => @verification_token,
      "view" => Map.merge(view, %{"id" => view_id})
    }
  end

  @doc """
  Simulate closing a modal, POSTing a `view_closed` interaction to
  `config.interactivity_url`. Signed when `config.signing_secret` is set.
  """
  @spec close_view(String.t(), map(), map()) :: {:ok, integer()} | {:error, term()}
  def close_view(view_id, view, config) do
    user = Map.get(config, :user, @default_user)
    payload = build_view_closed(view_id, view, %{user: user})
    post_interaction(config.interactivity_url, payload, config)
  end

  @doc """
  Wrap `event` in a Slack `event_callback` envelope (Events API). Exposed for
  testing.
  """
  @spec build_event_callback(map()) :: map()
  def build_event_callback(event) do
    %{
      "type" => "event_callback",
      "team_id" => "T_SLACKBOX",
      "api_app_id" => @api_app_id,
      "event_id" => "Ev" <> (:erlang.unique_integer([:positive]) |> Integer.to_string()),
      "event_time" => System.system_time(:second),
      "event" => event
    }
  end

  @doc """
  Deliver `event` to the app's Events API URL (`config.events_url`) as a JSON
  body. Signed over the raw JSON body when `config.signing_secret` is set.
  """
  @spec send_event(map(), map()) :: {:ok, integer()} | {:error, term()}
  def send_event(event, config) do
    body = Jason.encode!(build_event_callback(event))
    headers = json_headers(body, Map.get(config, :signing_secret))

    case Req.post(config.events_url, headers: headers, body: body) do
      {:ok, %Req.Response{status: status}} -> {:ok, status}
      {:error, reason} -> {:error, reason}
    end
  rescue
    error -> {:error, error}
  end

  # Form-encode `payload` and POST it to `url`, signing when configured.
  defp post_interaction(url, payload, config) do
    body = "payload=" <> URI.encode_www_form(Jason.encode!(payload))
    headers = form_headers(body, Map.get(config, :signing_secret))

    case Req.post(url, headers: headers, body: body) do
      {:ok, %Req.Response{status: status}} -> {:ok, status}
      {:error, reason} -> {:error, reason}
    end
  rescue
    error -> {:error, error}
  end

  defp form_headers(body, signing_secret) when is_binary(signing_secret) do
    [
      {"content-type", "application/x-www-form-urlencoded"}
      | signature_headers(body, signing_secret)
    ]
  end

  defp form_headers(_body, _signing_secret) do
    [{"content-type", "application/x-www-form-urlencoded"}]
  end

  defp json_headers(body, signing_secret) when is_binary(signing_secret) do
    [{"content-type", "application/json"} | signature_headers(body, signing_secret)]
  end

  defp json_headers(_body, _signing_secret) do
    [{"content-type", "application/json"}]
  end

  defp signature_headers(body, signing_secret) do
    ts = "#{System.system_time(:second)}"

    [
      {"x-slack-request-timestamp", ts},
      {"x-slack-signature", Signature.sign(signing_secret, ts, body)}
    ]
  end

  defp trigger_id do
    "#{System.system_time(:millisecond)}.#{:erlang.unique_integer([:positive])}.slackbox"
  end

  defp channel_name(nil), do: nil
  defp channel_name(channel), do: String.trim_leading(channel, "#")
end
