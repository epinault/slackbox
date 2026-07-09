defmodule Slackbox.StoreTest do
  use ExUnit.Case, async: false

  import Slackbox.Message

  alias Slackbox.Store

  setup do
    start_supervised!(Store)
    :ok
  end

  test "put/1 assigns a ts when the message has none and returns ts + channel" do
    msg = new() |> to_channel("#alerts") |> text("hi")
    assert %{ts: ts, channel: "#alerts"} = Store.put(msg)
    assert is_binary(ts)

    [entry] = Store.list_messages("#alerts")
    assert entry.ts == ts
    assert entry.message.ts == ts
    assert entry.raw["channel"] == "#alerts"
    assert entry.raw["text"] == "hi"
  end

  test "put/1 keeps an existing ts" do
    msg = new(channel: "#alerts", ts: "123.456", text: "hi")
    assert %{ts: "123.456"} = Store.put(msg)
  end

  test "list_channels/0 dedups and preserves insertion order" do
    Store.put(new(channel: "#alerts", text: "a"))
    Store.put(new(channel: "#deploys", text: "b"))
    Store.put(new(channel: "#alerts", text: "c"))

    assert Store.list_channels() == ["#alerts", "#deploys"]
  end

  test "list_messages/1 filters to a channel in insertion order" do
    Store.put(new(channel: "#alerts", text: "a"))
    Store.put(new(channel: "#deploys", text: "b"))
    Store.put(new(channel: "#alerts", text: "c"))

    alerts = Store.list_messages("#alerts")
    assert Enum.map(alerts, & &1.message.text) == ["a", "c"]
    assert Store.list_messages("#deploys") |> Enum.map(& &1.message.text) == ["b"]
  end

  test "clear/0 empties the store" do
    Store.put(new(channel: "#alerts", text: "a"))
    assert Store.list_channels() == ["#alerts"]
    assert :ok = Store.clear()
    assert Store.list_channels() == []
  end

  test "register_response/2 returns an opaque token" do
    %{ts: ts} = Store.put(new(channel: "#alerts", text: "a"))
    token = Store.register_response("#alerts", ts)
    assert is_binary(token)
    assert byte_size(token) > 0
  end

  test "apply_response/2 updates the entry text and broadcasts :update" do
    start_supervised!({Phoenix.PubSub, name: Slackbox.PubSub})
    Phoenix.PubSub.subscribe(Slackbox.PubSub, "slackbox")

    %{ts: ts} = Store.put(new(channel: "#alerts", text: "original"))
    token = Store.register_response("#alerts", ts)

    assert :ok = Store.apply_response(token, %{"text" => "updated ✅ acknowledge"})

    [entry] = Store.list_messages("#alerts")
    assert entry.message.text == "updated ✅ acknowledge"
    assert entry.raw["text"] == "updated ✅ acknowledge"

    assert_receive {:slackbox_store, :update, ^entry}
  end

  test "apply_response/2 with an unknown token returns error" do
    assert {:error, :not_found} = Store.apply_response("nope", %{"text" => "x"})
  end

  test "open_view/2 returns a view_id and list_views/0 reflects it, broadcasting :view_open" do
    start_supervised!({Phoenix.PubSub, name: Slackbox.PubSub})
    Phoenix.PubSub.subscribe(Slackbox.PubSub, "slackbox")

    view = %{"type" => "modal", "callback_id" => "cfg"}
    assert %{view_id: view_id} = Store.open_view("trig-1", view)
    assert String.starts_with?(view_id, "V")

    assert [%{view_id: ^view_id, trigger_id: "trig-1", view: ^view}] = Store.list_views()
    assert_receive {:slackbox_store, :view_open, %{view_id: ^view_id}}
  end

  test "close_view/1 removes the view and broadcasts :view_close" do
    start_supervised!({Phoenix.PubSub, name: Slackbox.PubSub})
    Phoenix.PubSub.subscribe(Slackbox.PubSub, "slackbox")

    %{view_id: view_id} = Store.open_view("trig-1", %{"type" => "modal"})
    assert length(Store.list_views()) == 1

    assert :ok = Store.close_view(view_id)
    assert Store.list_views() == []
    assert_receive {:slackbox_store, :view_close, ^view_id}
  end

  test "clear/0 also clears views" do
    Store.open_view("trig-1", %{"type" => "modal"})
    assert length(Store.list_views()) == 1
    assert :ok = Store.clear()
    assert Store.list_views() == []
  end
end
