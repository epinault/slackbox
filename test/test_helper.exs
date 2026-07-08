Application.put_env(:slackbox, Slackbox.TestNotifier, adapter: Slackbox.Adapters.Test)

ExUnit.start()
