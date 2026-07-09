defmodule Slackbox.Demo.SlackApp do
  @moduledoc """
  A sample interactivity endpoint standing in for *the user's own app* in the
  demo. It plays the role of the Slack app that receives `block_actions`
  interactions and closes the loop by replying to the `response_url`.

  Mounted at `/demo` in `Slackbox.Demo.Router`; the simulator posts here.
  """

  use Plug.Router

  plug(Plug.Parsers, parsers: [:urlencoded])
  plug(:match)
  plug(:dispatch)

  post "/interactivity" do
    payload = conn.params["payload"] |> Jason.decode!()

    action_id =
      payload["actions"]
      |> List.first(%{})
      |> Map.get("action_id", "unknown")

    response_url = payload["response_url"]
    user = get_in(payload, ["user", "id"]) || "unknown"
    base_text = get_in(payload, ["message", "text"]) || ""
    new_text = base_text <> "\n✅ `#{action_id}` clicked by <@#{user}>"

    if response_url do
      Req.post(response_url, json: %{"replace_original" => true, "text" => new_text})
    end

    send_resp(conn, 200, "ok")
  end

  match _ do
    send_resp(conn, 404, "not found")
  end
end
