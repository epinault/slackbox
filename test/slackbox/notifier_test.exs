defmodule Slackbox.NotifierTest do
  use ExUnit.Case, async: true

  alias Slackbox.Message
  alias Slackbox.TestNotifier

  test "post_message dispatches to the configured adapter and returns {:ok, meta}" do
    msg = Message.new(channel: "#alerts", text: "hi")
    assert {:ok, %{ts: _ts, channel: "#alerts"}} = TestNotifier.post_message(msg)
    assert_received {:slackbox, :post_message, %{message: ^msg}}
  end

  test "deliver/1 is an alias for post_message" do
    msg = Message.new(channel: "#c")
    assert {:ok, _meta} = TestNotifier.deliver(msg)
    assert_received {:slackbox, :post_message, %{message: ^msg}}
  end

  test "open_view dispatches with trigger_id and view" do
    assert {:ok, %{view_id: _view_id}} = TestNotifier.open_view("trigger-1", %{type: "modal"})
    assert_received {:slackbox, :open_view, %{trigger_id: "trigger-1", view: %{type: "modal"}}}
  end

  test "respond dispatches with the response_url" do
    msg = Message.new(text: "updated")
    assert {:ok, _meta} = TestNotifier.respond("https://example/response/abc", msg)

    assert_received {:slackbox, :respond,
                     %{response_url: "https://example/response/abc", message: ^msg}}
  end

  test "per-call opts override configured adapter config" do
    msg = Message.new(channel: "#c")
    assert {:ok, _meta} = TestNotifier.post_message(msg, token: "override")
    assert_received {:slackbox, :post_message, %{opts: [token: "override"]}}
  end
end
