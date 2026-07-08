defmodule Slackbox.Demo.Endpoint do
  @moduledoc false
  use Phoenix.Endpoint, otp_app: :slackbox

  @session_options [
    store: :cookie,
    key: "_slackbox_key",
    signing_salt: "slackboxsess",
    same_site: "Lax"
  ]

  socket("/live", Phoenix.LiveView.Socket, websocket: [connect_info: [session: @session_options]])

  plug(Plug.Session, @session_options)
  plug(Slackbox.Demo.Router)
end
