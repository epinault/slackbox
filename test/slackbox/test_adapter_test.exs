defmodule Slackbox.Adapters.TestTest do
  use ExUnit.Case, async: true

  alias Slackbox.Adapters.Test
  alias Slackbox.Message

  test "call/3 sends the action tuple to the current process" do
    msg = Message.new(channel: "#alerts", text: "hi")

    assert {:ok, %{ts: ts, channel: "#alerts"}} =
             Test.call(:post_message, %{message: msg, opts: []}, [])

    assert is_binary(ts)
    assert_received {:slackbox, :post_message, %{message: ^msg}}
  end

  test "call/3 also reaches processes listed in $callers (async support)" do
    parent = self()
    Process.put(:"$callers", [parent])
    msg = Message.new(channel: "#c")

    task =
      Task.async(fn ->
        Process.put(:"$callers", [parent])
        Test.call(:post_message, %{message: msg, opts: []}, [])
      end)

    Task.await(task)
    assert_received {:slackbox, :post_message, %{message: ^msg}}
  end

  test "open_view returns a view_id" do
    assert {:ok, %{view_id: "V" <> _rest}} =
             Test.call(:open_view, %{trigger_id: "t1", view: %{}, opts: []}, [])
  end
end
