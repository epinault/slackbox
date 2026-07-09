defmodule Slackbox.SignatureTest do
  use ExUnit.Case, async: true

  alias Slackbox.Signature

  @secret "8f742231b10e8888abcd99yyyzzz85a5"
  @timestamp "1531420618"
  @body "token=xyz&team_id=T1DC2JH3J"

  test "sign/3 produces a stable v0-prefixed lowercase hex signature" do
    sig = Signature.sign(@secret, @timestamp, @body)

    assert String.starts_with?(sig, "v0=")
    assert sig == String.downcase(sig)
    # Stable value for these exact inputs.
    assert sig ==
             Signature.sign(@secret, @timestamp, @body)

    assert sig ==
             "v0=" <>
               (:crypto.mac(:hmac, :sha256, @secret, "v0:#{@timestamp}:#{@body}")
                |> Base.encode16(case: :lower))
  end

  test "valid?/4 accepts a matching signature and rejects a tampered body" do
    sig = Signature.sign(@secret, @timestamp, @body)

    assert Signature.valid?(@secret, @timestamp, @body, sig)
    refute Signature.valid?(@secret, @timestamp, @body <> "tampered", sig)
  end
end
