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

  test "build_view_submission/4 shape" do
    view = %{"type" => "modal", "callback_id" => "config_modal"}
    state = %{"name_block" => %{"name" => %{"type" => "plain_text_input", "value" => "prod"}}}

    payload = Simulator.build_view_submission("V123", view, state, %{user: "U1"})

    assert payload["type"] == "view_submission"
    assert payload["user"] == %{"id" => "U1"}
    assert payload["view"]["id"] == "V123"
    assert payload["view"]["callback_id"] == "config_modal"
    assert payload["view"]["state"]["values"] == state
    assert is_binary(payload["trigger_id"])
  end

  test "build_view_closed/3 shape" do
    payload = Simulator.build_view_closed("V123", %{"type" => "modal"}, %{user: "U1"})

    assert payload["type"] == "view_closed"
    assert payload["view"]["id"] == "V123"
    assert payload["user"] == %{"id" => "U1"}
  end

  test "build_event_callback/1 wraps the event" do
    event = %{"type" => "app_mention", "text" => "hi"}
    payload = Simulator.build_event_callback(event)

    assert payload["type"] == "event_callback"
    assert payload["event"] == event
    assert payload["team_id"] == "T_SLACKBOX"
    assert is_binary(payload["event_id"])
    assert is_integer(payload["event_time"])
  end
end
