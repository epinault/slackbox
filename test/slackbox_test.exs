defmodule SlackboxTest do
  use ExUnit.Case
  doctest Slackbox

  test "greets the world" do
    assert Slackbox.hello() == :world
  end
end
