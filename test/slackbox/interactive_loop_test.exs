defmodule Slackbox.InteractiveLoopTest do
  use ExUnit.Case, async: false

  import Slackbox.Message

  alias Slackbox.Message
  alias Slackbox.Store

  @port 41_123
  @channel "#alerts"

  setup do
    {:ok, _} = Application.ensure_all_started(:phoenix_live_view)
    {:ok, _} = Application.ensure_all_started(:bandit)
    {:ok, _} = Application.ensure_all_started(:req)

    {:ok, sup} = Slackbox.Demo.start(port: @port)
    Store.clear()

    on_exit(fn ->
      ref = Process.monitor(sup)
      Supervisor.stop(sup, :shutdown)

      receive do
        {:DOWN, ^ref, :process, _, _} -> :ok
      after
        2_000 -> :ok
      end
    end)

    config = Application.get_env(:slackbox, :simulator)
    {:ok, config: config}
  end

  test "clicking a button drives the full block_actions -> response_url loop over HTTP", %{
    config: config
  } do
    msg =
      new()
      |> to_channel(@channel)
      |> Message.text("Production error rate spiked")
      |> Map.put(:username, "monitoring")
      |> blocks([
        section(":rotating_light: *High error rate*"),
        actions([button("Acknowledge", action_id: "acknowledge", value: "incident-42")])
      ])

    Store.put(msg)
    entry = Store.list_messages(@channel) |> List.last()

    assert {:ok, 200} =
             Slackbox.Simulator.click(
               entry,
               %{"action_id" => "acknowledge", "value" => "1"},
               config
             )

    # Poll the store for up to ~1s for the response_url callback to land.
    text = wait_for_update(entry.ts)

    assert text =~ "acknowledge"
    assert text =~ "✅"
  end

  defp wait_for_update(ts, attempts \\ 50)

  defp wait_for_update(_ts, 0),
    do: flunk("store entry was never updated by the response_url loop")

  defp wait_for_update(ts, attempts) do
    entry = Store.list_messages(@channel) |> Enum.find(&(&1.ts == ts))

    if entry && entry.message.text =~ "✅" do
      entry.message.text
    else
      Process.sleep(20)
      wait_for_update(ts, attempts - 1)
    end
  end
end
