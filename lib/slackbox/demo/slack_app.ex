defmodule Slackbox.Demo.SlackApp do
  @moduledoc """
  A sample Slack app standing in for *the user's own app* in the demo. It plays
  the role of the app that receives interactions and events:

    * `block_actions` — either opens a modal (`open_config`) or acknowledges the
      click by replying to the `response_url`.
    * `view_submission` — reads the submitted value and posts a confirmation
      message into the store.
    * `view_closed` — acknowledged.
    * Events API (`/events`) — handles `url_verification` challenges and
      `app_mention` events by posting a reply into the store.

  Mounted at `/demo` in `Slackbox.Demo.Router`; the simulator posts here.
  """

  use Plug.Router

  import Slackbox.Message

  alias Slackbox.Message
  alias Slackbox.Store

  plug(Plug.Parsers, parsers: [:urlencoded, :json], pass: ["*/*"], json_decoder: Jason)
  plug(:match)
  plug(:dispatch)

  post "/interactivity" do
    payload = conn.params["payload"] |> Jason.decode!()

    case payload["type"] do
      "block_actions" -> handle_block_actions(conn, payload)
      "view_submission" -> handle_view_submission(conn, payload)
      "view_closed" -> send_resp(conn, 200, "ok")
      _ -> send_resp(conn, 200, "ok")
    end
  end

  post "/events" do
    body = conn.body_params

    cond do
      is_binary(body["challenge"]) ->
        send_resp(conn, 200, body["challenge"])

      get_in(body, ["event", "type"]) == "app_mention" ->
        event = body["event"]

        new()
        |> to_channel(event["channel"])
        |> Message.text("👋 <@#{event["user"]}> you rang? (mention received)")
        |> Map.put(:username, "demo-bot")
        |> Store.put()

        send_resp(conn, 200, "ok")

      true ->
        send_resp(conn, 200, "ok")
    end
  end

  match _ do
    send_resp(conn, 404, "not found")
  end

  defp handle_block_actions(conn, payload) do
    action_id =
      payload["actions"]
      |> List.first(%{})
      |> Map.get("action_id", "unknown")

    if action_id == "open_config" do
      Store.open_view(payload["trigger_id"], config_view())
      send_resp(conn, 200, "ok")
    else
      response_url = payload["response_url"]
      user = get_in(payload, ["user", "id"]) || "unknown"
      base_text = get_in(payload, ["message", "text"]) || ""
      new_text = base_text <> "\n✅ `#{action_id}` clicked by <@#{user}>"

      if response_url do
        Req.post(response_url, json: %{"replace_original" => true, "text" => new_text})
      end

      send_resp(conn, 200, "ok")
    end
  end

  defp handle_view_submission(conn, payload) do
    value = get_in(payload, ["view", "state", "values", "name_block", "name", "value"])

    new()
    |> to_channel("#alerts")
    |> Message.text("🛠️ Config saved: name = #{value}")
    |> Map.put(:username, "config-bot")
    |> Store.put()

    conn
    |> put_resp_content_type("application/json")
    |> send_resp(200, Jason.encode!(%{"response_action" => "clear"}))
  end

  defp config_view do
    %{
      "type" => "modal",
      "callback_id" => "config_modal",
      "title" => %{"type" => "plain_text", "text" => "Configure alert"},
      "submit" => %{"type" => "plain_text", "text" => "Save"},
      "blocks" => [
        %{
          "type" => "input",
          "block_id" => "name_block",
          "label" => %{"type" => "plain_text", "text" => "Alert name"},
          "element" => %{"type" => "plain_text_input", "action_id" => "name"}
        }
      ]
    }
  end
end
