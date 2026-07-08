defmodule Slackbox.Demo do
  @moduledoc """
  A one-command demo server for the fake-Slack dev UI.

  `Slackbox.Demo.start/1` boots a self-contained supervision tree (PubSub, the
  in-memory `Slackbox.Store`, and a Phoenix endpoint serving
  `Slackbox.DashboardLive`), seeds a few messages, and prints the URL. Push more
  messages live from IEx with `Slackbox.Demo.post/2` and watch them appear.
  """

  import Slackbox.Message

  alias Slackbox.Message
  alias Slackbox.Store

  @default_port 4000

  @doc """
  Start the demo server. Options: `:port` (default #{@default_port}).

  Returns `{:ok, supervisor_pid}`.
  """
  @spec start(keyword()) :: {:ok, pid()} | {:error, term()}
  def start(opts \\ []) do
    port = Keyword.get(opts, :port, @default_port)

    Application.put_env(:slackbox, Slackbox.Demo.Endpoint,
      url: [host: "localhost"],
      http: [ip: {127, 0, 0, 1}, port: port],
      server: true,
      secret_key_base: String.duplicate("slackbox", 8),
      live_view: [signing_salt: "slackboxdemo"],
      pubsub_server: Slackbox.PubSub,
      adapter: Bandit.PhoenixAdapter
    )

    children = [
      {Phoenix.PubSub, name: Slackbox.PubSub},
      Slackbox.Store,
      Slackbox.Demo.Endpoint
    ]

    case Supervisor.start_link(children, strategy: :one_for_one, name: Slackbox.Demo.Supervisor) do
      {:ok, pid} ->
        seed()
        IO.puts("slackbox demo running at http://localhost:#{port}")
        {:ok, pid}

      other ->
        other
    end
  end

  @doc "Build a plain-text message to `channel` and store it (appears live in the UI)."
  @spec post(String.t(), String.t()) :: %{ts: String.t(), channel: String.t() | nil}
  def post(text, channel \\ "#alerts") do
    new()
    |> to_channel(channel)
    |> Message.text(text)
    |> Map.put(:username, "slackbot")
    |> Store.put()
  end

  defp seed do
    new()
    |> to_channel("#alerts")
    |> Message.text("Production error rate spiked above 5%")
    |> Map.put(:username, "monitoring")
    |> blocks([
      section(":rotating_light: *High error rate* on `web-prod` — 5.4% over the last 5m."),
      actions([
        button("Acknowledge", action_id: "ack", value: "incident-42"),
        button("View dashboard", action_id: "view_dashboard")
      ])
    ])
    |> Store.put()

    new()
    |> to_channel("#alerts")
    |> Message.text("Error rate back to normal (0.3%)")
    |> Map.put(:username, "monitoring")
    |> Store.put()

    new()
    |> to_channel("#deploys")
    |> Message.text("Deploy started for slackbox v0.1.0")
    |> Map.put(:username, "deploybot")
    |> blocks([
      section("*Deploy started* :rocket:\n`slackbox` v0.1.0 → production"),
      actions([
        button("Rollback", action_id: "rollback", value: "v0.1.0"),
        button("View build", action_id: "view_build")
      ])
    ])
    |> Store.put()

    new()
    |> to_channel("#deploys")
    |> Message.text("Deploy of slackbox v0.1.0 succeeded in 42s")
    |> Map.put(:username, "deploybot")
    |> Store.put()
  end
end
