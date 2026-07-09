defmodule Slackbox.Phase5LoopTest do
  use ExUnit.Case, async: false

  import Slackbox.Message

  alias Slackbox.Message
  alias Slackbox.Simulator
  alias Slackbox.Store

  @port 41_124
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

    {:ok, config: Application.get_env(:slackbox, :simulator)}
  end

  test "modal loop: open_config click opens a modal, submit posts a Config saved message", %{
    config: config
  } do
    msg =
      new()
      |> to_channel(@channel)
      |> Message.text("Tune alert thresholds")
      |> Map.put(:username, "monitoring")
      |> blocks([
        section("*Alert configuration*"),
        actions([button("Open config", action_id: "open_config")])
      ])

    Store.put(msg)
    entry = Store.list_messages(@channel) |> List.last()

    assert {:ok, 200} = Simulator.click(entry, %{"action_id" => "open_config"}, config)

    view =
      wait_for(fn ->
        Enum.find(Store.list_views(), &(&1.view["callback_id"] == "config_modal"))
      end)

    assert view

    state = %{"name_block" => %{"name" => %{"type" => "plain_text_input", "value" => "prod-cpu"}}}
    assert {:ok, 200} = Simulator.submit_view(view.view_id, view.view, state, config)

    text = wait_for(fn -> find_message_text(&(&1 =~ "Config saved")) end)
    assert text =~ "Config saved"
    assert text =~ "prod-cpu"
  end

  test "event loop: an app_mention event posts a 'you rang' reply", %{config: config} do
    event = %{
      "type" => "app_mention",
      "user" => "U_DEMO",
      "text" => "hi",
      "channel" => @channel,
      "ts" => "1.1"
    }

    assert {:ok, 200} = Simulator.send_event(event, config)

    text = wait_for(fn -> find_message_text(&(&1 =~ "you rang")) end)
    assert text =~ "you rang"
  end

  defp find_message_text(pred) do
    @channel
    |> Store.list_messages()
    |> Enum.map(& &1.message.text)
    |> Enum.find(&(is_binary(&1) and pred.(&1)))
  end

  defp wait_for(fun, attempts \\ 50)
  defp wait_for(_fun, 0), do: flunk("condition never became true within the polling window")

  defp wait_for(fun, attempts) do
    case fun.() do
      nil ->
        Process.sleep(20)
        wait_for(fun, attempts - 1)

      false ->
        Process.sleep(20)
        wait_for(fun, attempts - 1)

      value ->
        value
    end
  end
end
