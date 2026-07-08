defmodule Slackbox.TestAssertions do
  @moduledoc """
  Assertions for the `Slackbox.Adapters.Test` adapter, in the spirit of
  `Swoosh.TestAssertions`. `import` it in your test module:

      import Slackbox.TestAssertions

      test "notifies #alerts" do
        MyApp.Notifier.on_failure(build)
        assert_message_sent(channel: "#alerts", text: ~r/failed/)
      end

  Attribute assertions match against the *next* captured message of that action
  in the process mailbox (same semantics as Swoosh). A `Regex` value is matched
  with `=~`; any other value with `==`. A 1-arity function is called with the
  `%Slackbox.Message{}` for custom assertions.
  """

  import ExUnit.Assertions

  @doc "Assert a `post_message` was sent, matching attrs (keyword) or a predicate fn."
  def assert_message_sent(attrs_or_fun), do: assert_message(:post_message, attrs_or_fun)

  @doc "Assert a `post_ephemeral` was sent."
  def assert_ephemeral_sent(attrs_or_fun), do: assert_message(:post_ephemeral, attrs_or_fun)

  @doc "Assert a `chat.update` was sent."
  def assert_message_updated(attrs_or_fun), do: assert_message(:update, attrs_or_fun)

  @doc "Assert `views.open` happened; the predicate receives `%{trigger_id:, view:, opts:}`."
  def assert_view_opened(fun) when is_function(fun, 1) do
    assert_received {:slackbox, :open_view, args}
    fun.(args)
    args
  end

  @doc "Refute a `post_message` matching attrs (default: any) was sent."
  def refute_message_sent(attrs \\ []) do
    receive do
      {:slackbox, :post_message, %{message: message}} ->
        if attrs == [] or attrs_match?(message, attrs) do
          flunk(
            "Expected no post_message matching #{inspect(attrs)}, but got: #{inspect(message)}"
          )
        end
    after
      0 -> :ok
    end
  end

  defp assert_message(action, fun) when is_function(fun, 1) do
    message = receive_message(action)
    fun.(message)
    message
  end

  defp assert_message(action, attrs) when is_list(attrs) do
    message = receive_message(action)
    Enum.each(attrs, fn {key, expected} -> assert_attr(message, key, expected) end)
    message
  end

  defp receive_message(action) do
    {:messages, pending} = Process.info(self(), :messages)

    case Enum.find(pending, fn
           {:slackbox, ^action, %{message: _msg}} -> true
           _other -> false
         end) do
      nil -> flunk("Expected a #{action} to have been sent, but none was captured.")
      {:slackbox, _action, %{message: message}} -> message
    end
  end

  defp assert_attr(message, key, %Regex{} = expected) do
    actual = Map.get(message, key)

    assert is_binary(actual) and actual =~ expected,
           "Expected #{key} to match #{inspect(expected)}, got: #{inspect(actual)}"
  end

  defp assert_attr(message, key, expected) do
    assert Map.get(message, key) == expected
  end

  defp attrs_match?(message, attrs) do
    Enum.all?(attrs, fn
      {key, %Regex{} = expected} ->
        actual = Map.get(message, key)
        is_binary(actual) and actual =~ expected

      {key, expected} ->
        Map.get(message, key) == expected
    end)
  end
end
