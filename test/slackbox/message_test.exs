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

  describe "block kit" do
    test "blocks/2 stores blocks built from section/actions/button" do
      msg =
        new()
        |> to_channel("#alerts")
        |> blocks([
          section("Build *failed* on `main`"),
          actions([
            button("Retry", action_id: "retry_build", value: "1234"),
            button("View logs", action_id: "view_logs")
          ])
        ])

      assert [section_block, actions_block] = msg.blocks
      assert section_block["type"] == "section"
      assert section_block["text"] == %{"type" => "mrkdwn", "text" => "Build *failed* on `main`"}
      assert actions_block["type"] == "actions"
      assert [retry, _logs] = actions_block["elements"]
      assert retry["type"] == "button"
      assert retry["action_id"] == "retry_build"
      assert retry["value"] == "1234"
    end

    test "action_ids/1 collects action_ids across all action blocks" do
      msg =
        blocks(new(), [
          actions([button("Retry", action_id: "retry_build")]),
          section("ignored"),
          actions([
            button("Approve", action_id: "approve"),
            button("Reject", action_id: "reject")
          ])
        ])

      assert Slackbox.Message.action_ids(msg) == ["retry_build", "approve", "reject"]
    end

    test "action_ids/1 is empty when there are no action blocks" do
      assert Slackbox.Message.action_ids(new()) == []
    end
  end
end
