defmodule SlackboxTest do
  use ExUnit.Case, async: true
  doctest Slackbox

  test "greets the world" do
    assert Slackbox.hello() == :world
  end
end
