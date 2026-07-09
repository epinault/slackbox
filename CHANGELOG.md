# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.0] - 2026-07-09

Initial release — a Swoosh-style Slack library with a fake Slack dev UI.

### Added

- **Outbound choke point** — `use Slackbox.Notifier` generates `post_message/1,2`
  (alias `deliver/1,2`), `post_ephemeral/1,2`, `update/1,2`, `delete/1,2`,
  `open_view/2,3`, and `respond/2,3`, all dispatching through a single
  `Slackbox.Adapter.call/3` to a per-environment adapter.
- **`Slackbox.Message`** — composable pipe builders (`to_channel/2`, `text/2`,
  `blocks/2`, `thread/2`, `to_user/2`, `unfurl_links/2`), Block Kit helpers
  (`section/1`, `actions/1`, `button/2`), `action_ids/1`, and `to_payload/1`.
- **`Slackbox.Adapters.Live`** — a `Req`-based Slack Web API client for production
  (`chat.postMessage`/`postEphemeral`/`update`/`delete`, `views.open`, and
  `response_url` replies) with Slack `ok:false`/rate-limit handling.
- **`Slackbox.Adapters.Local`** — captures messages into an in-memory
  `Slackbox.Store` and renders them in a real-time LiveView "fake Slack"
  dashboard (`Slackbox.DashboardLive`) with a per-message raw-payload inspector.
- **`Slackbox.Adapters.Test`** + **`Slackbox.TestAssertions`** — capture outbound
  calls and assert on them (`assert_message_sent/1`, `refute_message_sent/1`,
  `assert_ephemeral_sent/1`, `assert_message_updated/1`, `assert_view_opened/1`).
- **Inbound simulation** — clicking a Block Kit button, submitting a modal, or
  firing an event in the fake UI POSTs a real Slack-shaped payload
  (`block_actions`, `view_submission`, `view_closed`, `event_callback`) to your
  app's endpoint, with a working `response_url` and optional HMAC request signing
  (`Slackbox.Signature`, `Slackbox.Simulator`, `Slackbox.ResponsePlug`).
- **`Slackbox.Test`** — payload builders (`block_actions/1`, `view_submission/1`,
  `event/2`, `form_body/1`, `signature_headers/2`) for unit-testing your Slack
  endpoints without the UI.
- **`mix slackbox.demo`** — a standalone demo server to try the whole loop at
  <http://localhost:4000> without a real Slack workspace.

[Unreleased]: https://github.com/epinault/slackbox/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/epinault/slackbox/releases/tag/v0.1.0
