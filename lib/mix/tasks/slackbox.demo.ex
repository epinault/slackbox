defmodule Mix.Tasks.Slackbox.Demo do
  @shortdoc "Boot the fake-Slack dev UI at http://localhost:4000"
  @moduledoc """
  Boot a self-contained demo server for the fake-Slack dev UI.

      mix slackbox.demo

  Then open http://localhost:4000. Seeded messages render with Block Kit and a
  per-message "raw payload" toggle. New messages appear in real time.
  """
  use Mix.Task

  @impl Mix.Task
  def run(_args) do
    {:ok, _} = Application.ensure_all_started(:phoenix_live_view)
    {:ok, _} = Application.ensure_all_started(:bandit)
    {:ok, _} = Slackbox.Demo.start()
    Process.sleep(:infinity)
  end
end
