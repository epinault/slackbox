defmodule Slackbox.ResponsePlug do
  @moduledoc """
  A `Plug.Router` a host app mounts to receive Slack `response_url` callbacks.

  In the inbound simulation loop, `Slackbox.Simulator` hands the app a
  `response_url` of the form `<response_base>/<token>`. When the app POSTs its
  Slack response there (a JSON body like `%{"text" => ..., "blocks" => ...}`),
  this plug decodes it and calls `Slackbox.Store.apply_response/2`, updating the
  originating message and broadcasting the change to the dashboard.

  Mount it at the same path you use for `response_base`, e.g.:

      forward "/slackbox/response", Slackbox.ResponsePlug

  paired with `response_base: "http://localhost:4000/slackbox/response"`.
  """

  use Plug.Router

  plug(Plug.Parsers, parsers: [:json], pass: ["application/json"], json_decoder: Jason)
  plug(:match)
  plug(:dispatch)

  post "/:token" do
    case Slackbox.Store.apply_response(token, conn.body_params) do
      :ok -> send_resp(conn, 200, "ok")
      {:error, :not_found} -> send_resp(conn, 404, "not found")
    end
  end

  match _ do
    send_resp(conn, 404, "not found")
  end
end
