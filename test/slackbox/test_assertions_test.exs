defmodule Slackbox.TestAssertionsTest do
  use ExUnit.Case, async: true

  import Slackbox.TestAssertions

  alias Slackbox.Message
  alias Slackbox.TestNotifier

  test "assert_message_sent/1 matches on attrs, including a regex" do
    TestNotifier.post_message(Message.new(channel: "#alerts", text: "Build failed on main"))

    assert_message_sent(channel: "#alerts")
    assert_message_sent(text: ~r/failed/)
  end

  test "assert_message_sent/1 accepts a predicate function" do
    buttons = [Message.button("Retry", action_id: "retry_build")]
    msg = Message.blocks(Message.new(channel: "#alerts"), [Message.actions(buttons)])

    TestNotifier.post_message(msg)

    assert_message_sent(fn m ->
      assert Message.action_ids(m) == ["retry_build"]
    end)
  end

  test "refute_message_sent/1 passes when nothing was sent" do
    refute_message_sent(channel: "#nope")
  end

  test "assert_ephemeral_sent and assert_message_updated match their actions" do
    TestNotifier.post_ephemeral(Message.new(channel: "#c", user: "U1", text: "psst"))
    assert_ephemeral_sent(channel: "#c")

    TestNotifier.update(Message.new(channel: "#c", ts: "1783.1", text: "edited"))
    assert_message_updated(text: "edited")
  end

  test "assert_view_opened yields the trigger_id and view" do
    TestNotifier.open_view("trigger-9", %{type: "modal", callback_id: "cfg"})

    assert_view_opened(fn %{trigger_id: trigger_id, view: view} ->
      assert trigger_id == "trigger-9"
      assert view.callback_id == "cfg"
    end)
  end
end
