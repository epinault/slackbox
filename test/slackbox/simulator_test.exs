defmodule Slackbox.SimulatorTest do
  use ExUnit.Case, async: true

  alias Slackbox.Simulator

  test "build_block_actions/3 shape" do
    entry = %{channel: "#alerts", ts: "123.456", raw: %{"channel" => "#alerts", "text" => "hi"}}
    action = %{"action_id" => "acknowledge", "value" => "1"}

    payload =
      Simulator.build_block_actions(entry, action, %{
        user: "U1",
        response_url: "http://localhost/slackbox/response/tok"
      })

    assert payload["type"] == "block_actions"
    assert payload["response_url"] == "http://localhost/slackbox/response/tok"
    assert payload["message"] == entry.raw
    assert payload["channel"] == %{"id" => "#alerts", "name" => "alerts"}
    assert payload["user"] == %{"id" => "U1"}

    [act] = payload["actions"]
    assert act["action_id"] == "acknowledge"
    assert act["value"] == "1"
    assert act["type"] == "button"
  end
end
