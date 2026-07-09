defmodule Slackbox.DashboardLive do
  @moduledoc """
  A Slack-like "fake Slack" dashboard, rendered live. A host app can mount it
  with `live "/dev/slack", Slackbox.DashboardLive`.

  It subscribes to the `Slackbox.Store` PubSub topic, so messages stored by the
  `Slackbox.Adapters.Local` adapter appear in real time. Each message renders
  its Block Kit blocks and offers a per-message "raw payload" toggle.
  """

  use Phoenix.LiveView

  alias Slackbox.Store

  @topic "slackbox"

  @impl Phoenix.LiveView
  def mount(_params, _session, socket) do
    if connected?(socket), do: Phoenix.PubSub.subscribe(Slackbox.PubSub, @topic)

    channels = Store.list_channels()
    selected = List.first(channels)

    {:ok,
     socket
     |> assign(:channels, channels)
     |> assign(:selected, selected)
     |> assign(:messages, messages_for(selected))
     |> assign(:open_raw, MapSet.new())}
  end

  @impl Phoenix.LiveView
  def handle_info({:slackbox_store, _op, _entry}, socket) do
    channels = Store.list_channels()
    selected = socket.assigns.selected || List.first(channels)

    {:noreply,
     socket
     |> assign(:channels, channels)
     |> assign(:selected, selected)
     |> assign(:messages, messages_for(selected))}
  end

  @impl Phoenix.LiveView
  def handle_event("select", %{"channel" => ch}, socket) do
    {:noreply,
     socket
     |> assign(:selected, ch)
     |> assign(:messages, messages_for(ch))}
  end

  def handle_event("action", %{"ts" => ts} = params, socket) do
    entry = Enum.find(socket.assigns.messages, &(&1.ts == ts))
    config = simulator_config()

    cond do
      is_nil(entry) ->
        {:noreply, socket}

      is_nil(Map.get(config, :interactivity_url)) ->
        {:noreply,
         put_flash(socket, :error, "No simulator configured — set :slackbox, :simulator.")}

      true ->
        action = %{"action_id" => params["action_id"], "value" => params["value"]}
        Slackbox.Simulator.click(entry, action, config)
        {:noreply, socket}
    end
  end

  def handle_event("toggle_raw", %{"ts" => ts}, socket) do
    open_raw = socket.assigns.open_raw

    open_raw =
      if MapSet.member?(open_raw, ts),
        do: MapSet.delete(open_raw, ts),
        else: MapSet.put(open_raw, ts)

    {:noreply, assign(socket, :open_raw, open_raw)}
  end

  defp messages_for(nil), do: []
  defp messages_for(channel), do: Store.list_messages(channel)

  @default_config %{
    response_base: "http://localhost:4000/slackbox/response",
    signing_secret: nil,
    user: "U_DEMO"
  }

  defp simulator_config do
    Map.merge(@default_config, Application.get_env(:slackbox, :simulator, %{}))
  end

  @impl Phoenix.LiveView
  def render(assigns) do
    ~H"""
    <div class="sb-app">
      <aside class="sb-sidebar">
        <div class="sb-workspace">Slackbox</div>
        <div class="sb-section-label">Channels</div>
        <ul class="sb-channels">
          <li
            :for={ch <- @channels}
            class={["sb-channel", @selected == ch && "sb-channel--active"]}
            phx-click="select"
            phx-value-channel={ch}
          >
            <span class="sb-hash">#</span>{channel_name(ch)}
          </li>
        </ul>
        <div :if={@channels == []} class="sb-empty-side">No messages yet</div>
      </aside>

      <main class="sb-main">
        <header class="sb-header">
          <div class="sb-header-title">
            <span class="sb-hash">#</span>{channel_name(@selected) || "no channel"}
          </div>
          <span class="sb-chip">DEV · SLACKBOX</span>
        </header>

        <div class="sb-messages">
          <div :if={@messages == []} class="sb-empty">
            No messages in this channel yet.
          </div>

          <div :for={entry <- @messages} class="sb-message">
            <div class="sb-avatar">{avatar_initial(entry.message)}</div>
            <div class="sb-body">
              <div class="sb-meta">
                <span class="sb-username">{entry.message.username || "bot"}</span>
                <span class="sb-app-badge">APP</span>
                <span class="sb-time">{format_time(entry.at)}</span>
              </div>

              <div :if={entry.message.text} class="sb-text">{entry.message.text}</div>

              <div :for={block <- entry.message.blocks} class="sb-block">
                {render_block(assigns, entry.ts, block)}
              </div>

              <div class="sb-raw-toggle">
                <span class="sb-raw-link" phx-click="toggle_raw" phx-value-ts={entry.ts}>
                  {"{ } raw"}
                </span>
              </div>
              <pre :if={MapSet.member?(@open_raw, entry.ts)} class="sb-raw"><%= Jason.encode!(entry.raw, pretty: true) %></pre>
            </div>
          </div>
        </div>
      </main>
    </div>
    """
  end

  defp render_block(assigns, _ts, %{"type" => "section"} = block) do
    assigns = assign(assigns, :text, block_text(block))

    ~H"""
    <div class="sb-section">{@text}</div>
    """
  end

  defp render_block(assigns, ts, %{"type" => "actions", "elements" => elements}) do
    assigns = assigns |> assign(:elements, elements) |> assign(:ts, ts)

    ~H"""
    <div class="sb-actions">
      <button
        :for={el <- @elements}
        type="button"
        class="sb-btn"
        phx-click="action"
        phx-value-ts={@ts}
        phx-value-action_id={el["action_id"]}
        phx-value-value={el["value"]}
      >
        {block_text(el)}
      </button>
    </div>
    """
  end

  defp render_block(assigns, _ts, block) do
    assigns = assign(assigns, :type, block["type"] || "block")

    ~H"""
    <div class="sb-section sb-section--unknown">[{@type}]</div>
    """
  end

  defp block_text(%{"text" => %{"text" => text}}), do: text
  defp block_text(%{"text" => text}) when is_binary(text), do: text
  defp block_text(_), do: ""

  defp channel_name(nil), do: nil
  defp channel_name("#" <> rest), do: rest
  defp channel_name(ch), do: ch

  defp avatar_initial(%{username: username}) when is_binary(username) and username != "" do
    String.upcase(String.first(username))
  end

  defp avatar_initial(_), do: "B"

  defp format_time(ms) when is_integer(ms) do
    {:ok, dt} = DateTime.from_unix(ms, :millisecond)
    :io_lib.format("~2..0B:~2..0B", [dt.hour, dt.minute]) |> to_string()
  end

  defp format_time(_), do: ""
end
