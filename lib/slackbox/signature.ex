defmodule Slackbox.Signature do
  @moduledoc """
  Slack request signing (HMAC-SHA256).

  Slack signs every request to your app so you can verify it really came from
  Slack. The signature is computed over the string `"v0:<timestamp>:<body>"`
  using your app's *signing secret* as the HMAC-SHA256 key, and is sent in the
  `x-slack-signature` header (with the timestamp in `x-slack-request-timestamp`).

  This module produces and verifies those signatures so the inbound simulation
  loop can exercise the same code path a real Slack request would.
  """

  @version "v0"

  @doc """
  Compute the Slack signature for `body` at `timestamp` using `signing_secret`.

  Returns `"v0=" <> lowercase_hex`.
  """
  @spec sign(String.t(), String.t() | integer(), String.t()) :: String.t()
  def sign(signing_secret, timestamp, body) do
    base = "#{@version}:#{timestamp}:#{body}"

    digest =
      :crypto.mac(:hmac, :sha256, signing_secret, base)
      |> Base.encode16(case: :lower)

    "#{@version}=#{digest}"
  end

  @doc """
  Return whether `signature` is the valid Slack signature for `body` at
  `timestamp` under `signing_secret`. Uses a constant-time comparison.
  """
  @spec valid?(String.t(), String.t() | integer(), String.t(), String.t()) :: boolean()
  def valid?(signing_secret, timestamp, body, signature) do
    expected = sign(signing_secret, timestamp, body)
    Plug.Crypto.secure_compare(expected, signature)
  end
end
