defmodule Slackbox.LiveAdapterTest do
  use ExUnit.Case, async: true

  alias Slackbox.Adapters.Live
  alias Slackbox.Message

  # A Req `plug:` stub. It records what the request looked like (path, body,
  # authorization header) by sending it to the test process, then replies with a
  # canned response, so no network is ever used.
  defp stub(fun) do
    test_pid = self()

    fn conn ->
      {:ok, raw, conn} = Plug.Conn.read_body(conn)
      body = if raw == "", do: %{}, else: Jason.decode!(raw)

      send(
        test_pid,
        {:request,
         %{
           path: conn.request_path,
           body: body,
           authorization: Plug.Conn.get_req_header(conn, "authorization")
         }}
      )

      fun.(conn, body)
    end
  end

  defp json(conn, status, data) do
    conn
    |> Plug.Conn.put_resp_content_type("application/json")
    |> Plug.Conn.resp(status, Jason.encode!(data))
  end

  defp config(plug), do: [token: "xoxb-test", req_options: [plug: plug]]

  test "post_message success returns ts/channel and sends bearer + body" do
    plug =
      stub(fn conn, _body ->
        json(conn, 200, %{"ok" => true, "ts" => "1503435956.000247", "channel" => "C123"})
      end)

    msg =
      Message.new()
      |> Message.to_channel("C123")
      |> Message.text("hello there")
      |> Message.blocks([Message.section("hi")])

    assert {:ok, %{ts: "1503435956.000247", channel: "C123"}} =
             Live.call(:post_message, %{message: msg, opts: []}, config(plug))

    assert_received {:request, req}
    assert req.path == "/api/chat.postMessage"
    assert req.body["text"] == "hello there"
    assert req.body["channel"] == "C123"
    assert [%{"type" => "section"}] = req.body["blocks"]
    assert req.authorization == ["Bearer xoxb-test"]
  end

  test "post_message Slack error returns {:error, {:slack, reason}}" do
    plug =
      stub(fn conn, _body ->
        json(conn, 200, %{"ok" => false, "error" => "channel_not_found"})
      end)

    msg = Message.new() |> Message.to_channel("C999") |> Message.text("x")

    assert {:error, {:slack, "channel_not_found"}} =
             Live.call(:post_message, %{message: msg, opts: []}, config(plug))

    assert_received {:request, %{path: "/api/chat.postMessage"}}
  end

  test "update success hits chat.update and returns ts/channel" do
    plug =
      stub(fn conn, _body ->
        json(conn, 200, %{"ok" => true, "ts" => "1503435956.000247", "channel" => "C123"})
      end)

    msg =
      Message.new()
      |> Message.to_channel("C123")
      |> Message.text("edited")
      |> Map.put(:ts, "1503435956.000247")

    assert {:ok, %{ts: "1503435956.000247", channel: "C123"}} =
             Live.call(:update, %{message: msg, opts: []}, config(plug))

    assert_received {:request, req}
    assert req.path == "/api/chat.update"
    assert req.body["ts"] == "1503435956.000247"
  end

  test "open_view success hits views.open and returns view_id" do
    plug =
      stub(fn conn, _body ->
        json(conn, 200, %{"ok" => true, "view" => %{"id" => "V1"}})
      end)

    view = %{"type" => "modal", "title" => %{"type" => "plain_text", "text" => "Hi"}}

    assert {:ok, %{view_id: "V1"}} =
             Live.call(:open_view, %{trigger_id: "T99", view: view, opts: []}, config(plug))

    assert_received {:request, req}
    assert req.path == "/api/views.open"
    assert req.body["trigger_id"] == "T99"
    assert req.body["view"] == view
  end

  test "post_ephemeral success returns empty map and includes user" do
    plug =
      stub(fn conn, _body ->
        json(conn, 200, %{"ok" => true, "message_ts" => "1503435956.000247"})
      end)

    msg =
      Message.new()
      |> Message.to_channel("C123")
      |> Message.to_user("U1")
      |> Message.text("just for you")

    assert {:ok, %{message_ts: "1503435956.000247"}} =
             Live.call(:post_ephemeral, %{message: msg, opts: []}, config(plug))

    assert_received {:request, req}
    assert req.path == "/api/chat.postEphemeral"
    assert req.body["user"] == "U1"
  end

  test "delete hits chat.delete with channel and ts" do
    plug =
      stub(fn conn, _body ->
        json(conn, 200, %{"ok" => true})
      end)

    msg = Message.new() |> Message.to_channel("C123") |> Map.put(:ts, "1503435956.000247")

    assert {:ok, %{}} = Live.call(:delete, %{message: msg, opts: []}, config(plug))

    assert_received {:request, req}
    assert req.path == "/api/chat.delete"
    assert req.body == %{"channel" => "C123", "ts" => "1503435956.000247"}
  end

  test "respond posts to the response_url and returns ok" do
    plug =
      stub(fn conn, _body ->
        Plug.Conn.resp(conn, 200, "ok")
      end)

    msg = Message.new() |> Message.text("replacing")
    url = "https://hooks.slack.com/actions/T1/B2/xyz"

    assert {:ok, %{}} =
             Live.call(
               :respond,
               %{
                 response_url: url,
                 message: msg,
                 opts: [replace_original: true, response_type: "in_channel"]
               },
               req_options: [plug: plug]
             )

    assert_received {:request, req}
    assert req.path == "/actions/T1/B2/xyz"
    assert req.body["text"] == "replacing"
    assert req.body["replace_original"] == true
    assert req.body["response_type"] == "in_channel"
    # No token needed for response_url.
    assert req.authorization == []
  end

  test "rate limited (429) returns retry-after seconds" do
    plug =
      stub(fn conn, _body ->
        conn
        |> Plug.Conn.put_resp_header("retry-after", "30")
        |> Plug.Conn.resp(429, Jason.encode!(%{"ok" => false, "error" => "rate_limited"}))
      end)

    msg = Message.new() |> Message.to_channel("C123") |> Message.text("x")

    assert {:error, {:rate_limited, 30}} =
             Live.call(:post_message, %{message: msg, opts: []}, config(plug))
  end

  test "missing token for a Web API call returns error without making a request" do
    test_pid = self()

    plug = fn conn ->
      send(test_pid, :requested)
      json(conn, 200, %{"ok" => true})
    end

    msg = Message.new() |> Message.to_channel("C123") |> Message.text("x")

    assert {:error, :missing_token} =
             Live.call(:post_message, %{message: msg, opts: []}, req_options: [plug: plug])

    refute_received :requested
  end
end
