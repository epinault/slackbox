defmodule Slackbox.Notifier do
  @moduledoc """
  Turns a module into your app's Slack notifier — the single choke point every
  outbound Slack call flows through, dispatching to a per-environment adapter.

      defmodule MyApp.Slack do
        use Slackbox.Notifier, otp_app: :my_app
      end

      # config :my_app, MyApp.Slack, adapter: Slackbox.Adapters.Local

  Generated functions: `post_message/1,2` (alias `deliver/1,2`), `post_ephemeral/1,2`,
  `update/1,2`, `delete/1,2`, `open_view/2,3`, `respond/2,3`. The optional trailing
  `opts` are runtime/adapter overrides (token, timeout, …), merged over the
  configured adapter config — message *content* belongs on the `Slackbox.Message`.
  """

  defmacro __using__(opts) do
    otp_app = Keyword.fetch!(opts, :otp_app)

    quote bind_quoted: [otp_app: otp_app] do
      @otp_app otp_app

      def post_message(message, opts \\ []) do
        Slackbox.Notifier.dispatch(__MODULE__, @otp_app, :post_message, %{
          message: message,
          opts: opts
        })
      end

      def deliver(message, opts \\ []), do: post_message(message, opts)

      def post_ephemeral(message, opts \\ []) do
        Slackbox.Notifier.dispatch(__MODULE__, @otp_app, :post_ephemeral, %{
          message: message,
          opts: opts
        })
      end

      def update(message, opts \\ []) do
        Slackbox.Notifier.dispatch(__MODULE__, @otp_app, :update, %{message: message, opts: opts})
      end

      def delete(message, opts \\ []) do
        Slackbox.Notifier.dispatch(__MODULE__, @otp_app, :delete, %{message: message, opts: opts})
      end

      def open_view(trigger_id, view, opts \\ []) do
        Slackbox.Notifier.dispatch(__MODULE__, @otp_app, :open_view, %{
          trigger_id: trigger_id,
          view: view,
          opts: opts
        })
      end

      def respond(response_url, message, opts \\ []) do
        Slackbox.Notifier.dispatch(__MODULE__, @otp_app, :respond, %{
          response_url: response_url,
          message: message,
          opts: opts
        })
      end
    end
  end

  @doc false
  @spec dispatch(module(), atom(), Slackbox.Adapter.action(), map()) ::
          {:ok, map()} | {:error, term()}
  def dispatch(notifier, otp_app, action, args) do
    config = Application.get_env(otp_app, notifier, [])
    adapter = Keyword.fetch!(config, :adapter)
    merged_config = Keyword.merge(config, Map.get(args, :opts, []))
    adapter.call(action, args, merged_config)
  end
end
