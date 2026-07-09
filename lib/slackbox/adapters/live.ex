defmodule Slackbox.Adapters.Live do
  @moduledoc """
  Live adapter. A thin, owned [`Req`](https://hexdocs.pm/req)-based Slack Web API
  client — the SAME app code that renders in the fake dev UI (`Local`) actually
  posts to Slack when this adapter is configured.

      # config/prod.exs
      config :my_app, MyApp.Slack,
        adapter: Slackbox.Adapters.Live,
        token: System.get_env("SLACK_BOT_TOKEN")

  ## Config keys

  Read from the merged `config` keyword list (adapter config plus per-call `opts`):

    * `:token` — Slack bot token (`xoxb-...`). Required for Web API methods
      (`post_message`, `post_ephemeral`, `update`, `delete`, `open_view`); a
      missing token yields `{:error, :missing_token}`. Not needed for `respond`,
      which posts to a signed `response_url`.
    * `:base_url` — Slack Web API base. Defaults to `"https://slack.com/api"`;
      override it to point at a fake server.
    * `:req_options` — keyword list merged into every `Req` request. Handy for a
      test `plug:` stub, or for app-level timeouts/retries. Defaults to `[]`.

  ## Return shapes

    * `post_message` / `update` → `{:ok, %{ts: ..., channel: ...}}`
    * `open_view` → `{:ok, %{view_id: ...}}`
    * `post_ephemeral` → `{:ok, %{}}` (with `:message_ts` when Slack returns one)
    * `delete` / `respond` → `{:ok, %{}}`
    * Slack API failure → `{:error, {:slack, reason}}`
    * HTTP 429 → `{:error, {:rate_limited, retry_after_seconds | nil}}`
    * `respond` non-200 → `{:error, {:http, status}}`
    * transport error → `{:error, exception}`

  Errors are always returned as tagged tuples; the adapter never raises into the
  caller.
  """

  @behaviour Slackbox.Adapter

  alias Slackbox.Message

  @default_base_url "https://slack.com/api"

  @impl Slackbox.Adapter
  def call(:post_message, %{message: msg}, config) do
    web_api("chat.postMessage", Message.to_payload(msg), config, &message_result/1)
  end

  def call(:post_ephemeral, %{message: msg}, config) do
    web_api("chat.postEphemeral", Message.to_payload(msg), config, &ephemeral_result/1)
  end

  def call(:update, %{message: msg}, config) do
    web_api("chat.update", Message.to_payload(msg), config, &message_result/1)
  end

  def call(:delete, %{message: msg}, config) do
    body = %{"channel" => msg.channel, "ts" => msg.ts}
    web_api("chat.delete", body, config, fn _body -> %{} end)
  end

  def call(:open_view, %{trigger_id: trigger_id, view: view}, config) do
    body = %{"trigger_id" => trigger_id, "view" => view}
    web_api("views.open", body, config, &view_result/1)
  end

  def call(:respond, %{response_url: response_url, message: msg} = args, config) do
    body = respond_body(msg, Map.get(args, :opts, []))
    respond(response_url, body, config)
  end

  # --- Web API (token'd) ---

  defp web_api(method, body, config, on_success) do
    case fetch_token(config) do
      {:ok, token} -> do_web_api(method, body, token, config, on_success)
      :error -> {:error, :missing_token}
    end
  end

  defp do_web_api(method, body, token, config, on_success) do
    url = base_url(config) <> "/" <> method

    options =
      [
        method: :post,
        url: url,
        json: body,
        auth: {:bearer, token},
        headers: [{"content-type", "application/json"}]
      ] ++ req_options(config)

    case Req.request(options) do
      {:ok, %Req.Response{status: 200, body: %{"ok" => true} = ok_body}} ->
        {:ok, on_success.(ok_body)}

      {:ok, %Req.Response{status: 200, body: %{"ok" => false} = err_body}} ->
        {:error, {:slack, err_body["error"]}}

      {:ok, %Req.Response{status: 429} = resp} ->
        {:error, {:rate_limited, retry_after(resp)}}

      {:ok, %Req.Response{status: status}} ->
        {:error, {:http, status}}

      {:error, exception} ->
        {:error, exception}
    end
  end

  # --- response_url (no token) ---

  defp respond(response_url, body, config) do
    options =
      [
        method: :post,
        url: response_url,
        json: body,
        headers: [{"content-type", "application/json"}]
      ] ++ req_options(config)

    case Req.request(options) do
      {:ok, %Req.Response{status: 200}} -> {:ok, %{}}
      {:ok, %Req.Response{status: status}} -> {:error, {:http, status}}
      {:error, exception} -> {:error, exception}
    end
  end

  defp respond_body(msg, opts) do
    Message.to_payload(msg)
    |> maybe_put("replace_original", Keyword.get(opts, :replace_original))
    |> maybe_put("response_type", Keyword.get(opts, :response_type))
  end

  # --- success shaping ---

  defp message_result(body), do: %{ts: body["ts"], channel: body["channel"]}

  defp view_result(body), do: %{view_id: get_in(body, ["view", "id"])}

  defp ephemeral_result(body), do: maybe_put(%{}, :message_ts, body["message_ts"])

  # --- helpers ---

  defp fetch_token(config) do
    case Keyword.get(config, :token) do
      token when is_binary(token) and token != "" -> {:ok, token}
      _ -> :error
    end
  end

  defp base_url(config), do: Keyword.get(config, :base_url, @default_base_url)

  defp req_options(config), do: Keyword.get(config, :req_options, [])

  defp retry_after(%Req.Response{} = resp) do
    case Req.Response.get_header(resp, "retry-after") do
      [value | _] -> parse_retry_after(value)
      [] -> nil
    end
  end

  defp parse_retry_after(value) do
    case Integer.parse(value) do
      {seconds, _} -> seconds
      :error -> nil
    end
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
