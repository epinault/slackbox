defmodule Slackbox.Demo.Layouts do
  @moduledoc false
  use Phoenix.Component

  @doc "Root HTML document for the demo server, with inline CSS + LiveView JS from CDN."
  def root(assigns) do
    ~H"""
    <!DOCTYPE html>
    <html lang="en">
      <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <meta name="csrf-token" content={Phoenix.Controller.get_csrf_token()} />
        <title>Slackbox — fake Slack (dev)</title>
        <style>
          * { box-sizing: border-box; }
          html, body { margin: 0; padding: 0; height: 100%; }
          body {
            font-family: "Lato", -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
            color: #1d1c1d;
            background: #fff;
          }
          .sb-app { display: flex; height: 100vh; }

          /* Sidebar */
          .sb-sidebar {
            width: 260px;
            flex: 0 0 260px;
            background: #3f0e40;
            color: #cfc3cf;
            padding: 16px 0;
            overflow-y: auto;
          }
          .sb-workspace {
            font-size: 18px; font-weight: 800; color: #fff;
            padding: 0 18px 14px; border-bottom: 1px solid rgba(255,255,255,.12);
            margin-bottom: 10px;
          }
          .sb-section-label {
            font-size: 12px; text-transform: uppercase; letter-spacing: .04em;
            padding: 6px 18px; color: #bca9bc;
          }
          .sb-channels { list-style: none; margin: 0; padding: 0; }
          .sb-channel {
            padding: 5px 18px; cursor: pointer; font-size: 15px;
            display: flex; align-items: center; gap: 4px; color: #cfc3cf;
          }
          .sb-channel:hover { background: rgba(255,255,255,.06); }
          .sb-channel--active { background: #1164a3; color: #fff; }
          .sb-hash { opacity: .7; margin-right: 2px; }
          .sb-empty-side { padding: 8px 18px; font-size: 13px; color: #bca9bc; }

          /* Main */
          .sb-main { flex: 1 1 auto; display: flex; flex-direction: column; min-width: 0; }
          .sb-header {
            height: 56px; flex: 0 0 56px; border-bottom: 1px solid #e8e8e8;
            display: flex; align-items: center; justify-content: space-between;
            padding: 0 20px;
          }
          .sb-header-title { font-weight: 800; font-size: 17px; display: flex; align-items: center; }
          .sb-chip {
            font-size: 11px; font-weight: 700; letter-spacing: .05em;
            background: #f3e8f3; color: #611f69; padding: 4px 10px; border-radius: 12px;
          }

          .sb-messages { flex: 1 1 auto; overflow-y: auto; padding: 16px 20px; }
          .sb-empty { color: #868686; font-size: 15px; padding: 20px 0; }

          .sb-message {
            display: flex; gap: 10px; padding: 8px 0;
          }
          .sb-message:hover { background: #f8f8f8; }
          .sb-avatar {
            width: 36px; height: 36px; flex: 0 0 36px; border-radius: 6px;
            background: #611f69; color: #fff; font-weight: 700;
            display: flex; align-items: center; justify-content: center;
          }
          .sb-body { min-width: 0; flex: 1 1 auto; }
          .sb-meta { display: flex; align-items: center; gap: 8px; }
          .sb-username { font-weight: 800; font-size: 15px; }
          .sb-app-badge {
            font-size: 10px; font-weight: 700; background: #e8e8e8; color: #616061;
            padding: 1px 5px; border-radius: 3px; text-transform: uppercase;
          }
          .sb-time { font-size: 12px; color: #868686; }
          .sb-text { font-size: 15px; margin-top: 2px; white-space: pre-wrap; }

          .sb-block { margin-top: 6px; }
          .sb-section { font-size: 15px; }
          .sb-section--unknown { color: #868686; font-style: italic; }
          .sb-actions { display: flex; gap: 8px; margin-top: 8px; flex-wrap: wrap; }
          .sb-btn {
            font-size: 14px; font-weight: 700; padding: 8px 14px;
            border: 1px solid #d0d0d0; border-radius: 4px; background: #fff;
            color: #1d1c1d; cursor: default;
          }
          .sb-btn:hover { background: #f4f4f4; }

          .sb-raw-toggle { margin-top: 6px; }
          .sb-raw-link {
            font-size: 12px; color: #1264a3; cursor: pointer; font-family: monospace;
          }
          .sb-raw-link:hover { text-decoration: underline; }
          .sb-raw {
            margin-top: 6px; background: #1d1c1d; color: #d7f5d7;
            padding: 12px; border-radius: 6px; font-size: 12px;
            overflow-x: auto; white-space: pre;
          }

          /* Header tools */
          .sb-header-tools { display: flex; align-items: center; gap: 10px; }
          .sb-btn--tool { cursor: pointer; font-size: 13px; padding: 6px 12px; }
          .sb-btn--primary {
            cursor: pointer; background: #007a5a; color: #fff; border-color: #007a5a;
          }
          .sb-btn--primary:hover { background: #148567; }

          /* Modal overlay */
          .sb-modal-backdrop {
            position: fixed; inset: 0; background: rgba(0,0,0,.5);
            display: flex; align-items: center; justify-content: center; z-index: 50;
          }
          .sb-modal {
            background: #fff; border-radius: 10px; width: 480px; max-width: 90vw;
            padding: 24px; box-shadow: 0 12px 48px rgba(0,0,0,.35);
          }
          .sb-modal-title { font-size: 20px; font-weight: 800; margin-bottom: 16px; }
          .sb-modal-block { margin-bottom: 14px; }
          .sb-modal-label { display: block; font-weight: 700; font-size: 14px; margin-bottom: 6px; }
          .sb-modal-input {
            width: 100%; font-size: 15px; padding: 9px 12px;
            border: 1px solid #d0d0d0; border-radius: 4px;
          }
          .sb-modal-actions {
            display: flex; justify-content: flex-end; gap: 8px; margin-top: 20px;
          }
        </style>
      </head>
      <body>
        {@inner_content}
        <script type="module">
          import {Socket} from "https://esm.sh/phoenix@1.8.9"
          import {LiveSocket} from "https://esm.sh/phoenix_live_view@1.2.6"
          const csrf = document.querySelector("meta[name='csrf-token']").getAttribute("content")
          const liveSocket = new LiveSocket("/live", Socket, {params: {_csrf_token: csrf}})
          liveSocket.connect()
        </script>
      </body>
    </html>
    """
  end
end
