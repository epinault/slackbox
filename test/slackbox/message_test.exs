defmodule Slackbox.MessageTest do
  use ExUnit.Case, async: true

  import Slackbox.Message

  describe "builders" do
    test "new/1 accepts attrs and returns a struct with defaults" do
      msg = new(channel: "#alerts")
      assert msg.channel == "#alerts"
      assert msg.blocks == []
      assert msg.metadata == %{}
    end

    test "pipe builders set fields" do
      msg =
        new()
        |> to_channel("#alerts")
        |> text("Build failed")
        |> thread("1783017.0001")
        |> to_user("U123")
        |> unfurl_links(false)

      assert msg.channel == "#alerts"
      assert msg.text == "Build failed"
      assert msg.thread_ts == "1783017.0001"
      assert msg.user == "U123"
      assert msg.unfurl_links == false
    end
  end
end
