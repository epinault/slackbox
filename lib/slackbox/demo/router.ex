defmodule Slackbox.Demo.Router do
  @moduledoc false
  use Phoenix.Router
  import Phoenix.LiveView.Router

  pipeline :browser do
    plug(:accepts, ["html"])
    plug(:fetch_session)
    plug(:fetch_live_flash)
    plug(:put_root_layout, html: {Slackbox.Demo.Layouts, :root})
    plug(:protect_from_forgery)
    plug(:put_secure_browser_headers)
  end

  scope "/" do
    pipe_through(:browser)
    live("/", Slackbox.DashboardLive, :index)
  end

  # The sample app that receives simulated Slack interactions.
  forward("/demo", Slackbox.Demo.SlackApp)

  # Receives `response_url` callbacks and updates the store.
  forward("/slackbox/response", Slackbox.ResponsePlug)
end
