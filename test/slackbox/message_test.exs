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

  describe "to_payload/1" do
    test "includes channel and text, drops nil fields" do
      payload =
        new()
        |> to_channel("#alerts")
        |> text("Build failed")
        |> Slackbox.Message.to_payload()

      assert payload["channel"] == "#alerts"
      assert payload["text"] == "Build failed"
      refute Map.has_key?(payload, "thread_ts")
      refute Map.has_key?(payload, "blocks")
      refute Map.has_key?(payload, "user")
    end

    test "includes blocks when non-empty and omits them when empty" do
      blocks_list = [section("Hi *there*")]

      with_blocks =
        new()
        |> to_channel("#alerts")
        |> blocks(blocks_list)
        |> Slackbox.Message.to_payload()

      assert with_blocks["blocks"] == blocks_list

      without_blocks =
        new()
        |> to_channel("#alerts")
        |> Slackbox.Message.to_payload()

      refute Map.has_key?(without_blocks, "blocks")
    end

    test "includes optional identity/threading fields when set" do
      payload =
        new(channel: "#alerts", ts: "1.2", thread_ts: "0.1", user: "U1", username: "deploybot")
        |> Slackbox.Message.to_payload()

      assert payload["ts"] == "1.2"
      assert payload["thread_ts"] == "0.1"
      assert payload["user"] == "U1"
      assert payload["username"] == "deploybot"
    end
  end
end
