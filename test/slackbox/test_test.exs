defmodule Slackbox.TestTest do
  use ExUnit.Case, async: true

  alias Slackbox.Test, as: SB

  test "block_actions/1 builds a block_actions payload with defaults + overrides" do
    payload = SB.block_actions(action_id: "retry", value: "v1", channel: "#alerts")

    assert payload["type"] == "block_actions"
    assert payload["user"] == %{"id" => "U_TEST"}
    assert payload["channel"]["id"] == "#alerts"
    assert payload["response_url"] == "https://example.test/response"

    [act] = payload["actions"]
    assert act["action_id"] == "retry"
    assert act["value"] == "v1"
  end

  test "view_submission/1 builds a view_submission payload" do
    state = %{"name_block" => %{"name" => %{"type" => "plain_text_input", "value" => "x"}}}
    payload = SB.view_submission(callback_id: "config_modal", view_id: "V9", state: state)

    assert payload["type"] == "view_submission"
    assert payload["view"]["id"] == "V9"
    assert payload["view"]["callback_id"] == "config_modal"
    assert payload["view"]["state"]["values"] == state
    assert payload["user"] == %{"id" => "U_TEST"}
  end

  test "event/2 wraps an event_callback with stringified opts" do
    payload = SB.event("app_mention", text: "<@U1> hi", channel: "#alerts")

    assert payload["type"] == "event_callback"
    assert payload["event"]["type"] == "app_mention"
    assert payload["event"]["text"] == "<@U1> hi"
    assert payload["event"]["channel"] == "#alerts"
  end

  test "form_body/1 form-encodes a payload" do
    body = SB.form_body(%{"type" => "block_actions"})
    assert "payload=" <> encoded = body
    assert URI.decode_www_form(encoded) == ~s({"type":"block_actions"})
  end

  test "signature_headers/2 produces timestamp + signature headers" do
    body = "payload=abc"
    headers = SB.signature_headers("secret", body)

    assert {_, ts} = List.keyfind(headers, "x-slack-request-timestamp", 0)
    assert {_, sig} = List.keyfind(headers, "x-slack-signature", 0)
    assert Slackbox.Signature.valid?("secret", ts, body, sig)
  end
end
