defmodule Slackbox.Adapters.Test do
  @moduledoc """
  Test adapter. Captures each outbound call by sending `{:slackbox, action, args}`
  to the current process and to every pid in `$callers` (so captures survive
  `Task.async` and `async: true` tests). Pair with `Slackbox.TestAssertions`.
  """

  @behaviour Slackbox.Adapter

  @impl Slackbox.Adapter
  def call(action, args, _config) do
    payload = {:slackbox, action, args}
    Enum.each(callers(), fn pid -> send(pid, payload) end)
    {:ok, response(action, args)}
  end

  defp callers do
    Enum.uniq([self() | Process.get(:"$callers", [])])
  end

  defp response(:post_message, %{message: msg}), do: %{ts: fake_ts(), channel: msg.channel}
  defp response(:update, %{message: msg}), do: %{ts: msg.ts || fake_ts(), channel: msg.channel}
  defp response(:open_view, _args), do: %{view_id: "V" <> unique()}
  defp response(_action, _args), do: %{}

  defp fake_ts do
    seconds = System.system_time(:second)
    micro = rem(System.system_time(:microsecond), 1_000_000)
    "#{seconds}.#{String.pad_leading(Integer.to_string(micro), 6, "0")}"
  end

  defp unique, do: Integer.to_string(System.unique_integer([:positive]))
end
