# Slackbox — Plan 1: Scaffold + Phase 1 (Core Outbound + Test Adapter) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Scaffold the `slackbox` Mix library and build the outbound choke point — the `Slackbox.Message` struct + builders, the adapter behaviour, the `Slackbox.Notifier` dispatcher, the `Test` adapter, and `Slackbox.TestAssertions` — so an app can call `MyApp.Slack.post_message(...)` and assert on it in tests.

**Architecture:** One `use Slackbox.Notifier` module is the single outbound choke point. It builds a `%Slackbox.Message{}` (or accepts a raw map) and dispatches every action through a single `Slackbox.Adapter.call/3` callback to a per-environment adapter. Phase 1 ships the `Test` adapter (captures calls to the test process mailbox, `$callers`-aware for `async: true`). `Live` and `Local` adapters arrive in later plans.

**Tech Stack:** Elixir (~> 1.15, using 1.20/OTP 29 locally), ExUnit, Credo (strict). No runtime dependencies in Phase 1 — the scaffold's library deps (credo, ex_doc, usage_rules) are enough.

**Roadmap (subsequent plans, generated when reached):**
- **Plan 2 — Phase 2:** `Live` adapter (`Req`-based Web API client; adds `req`, `jason`).
- **Plan 3 — Phase 3:** `Local` store + LiveView fake-Slack dashboard, outbound-only (adds `phoenix_live_view`, `phoenix_pubsub`).
- **Plan 4 — Phase 4:** Inbound simulation — interactive components (`Simulator`, `trigger_id`/`response_url` lifecycle, in-process `respond/2`, optional signing).
- **Plan 5 — Phase 5:** Inbound simulation — modals/views + Events API + `Slackbox.Test` inbound payload builders.

---

## File Structure (Phase 1)

Created by the scaffold, then filled in by later tasks:

- `lib/slackbox.ex` — top-level `@moduledoc` / public entry (scaffold default; light-touch)
- `lib/slackbox/message.ex` — **Message struct + pipe builders + Block Kit helpers + introspection** (Task 1–2)
- `lib/slackbox/adapter.ex` — **the adapter behaviour** (Task 3)
- `lib/slackbox/adapters/test.ex` — **Test adapter** (Task 3)
- `lib/slackbox/notifier.ex` — **`use` macro + `dispatch/4`** (Task 4)
- `lib/slackbox/test_assertions.ex` — **assertions** (Task 5)
- `test/support/test_notifier.ex` — fixture notifier used by Task 4–5 tests
- `test/slackbox/message_test.exs` — Task 1–2 tests
- `test/slackbox/notifier_test.exs` — Task 4 tests
- `test/slackbox/test_assertions_test.exs` — Task 5 tests
- `test/test_helper.exs` — sets the Test adapter env (Task 4)

Each file has one responsibility: `message.ex` = data + builders, `adapter.ex` = the contract, `notifier.ex` = dispatch, adapters = one adapter each, `test_assertions.ex` = test ergonomics.

---

## Task 0: Scaffold the library

**Files:** whole project tree (generated).

- [ ] **Step 1: Run the scaffold skill**

Invoke the `elixir-scaffold:new-elixir-project` skill and answer its prompts:
- **Project name:** `slackbox`
- **Project type:** `Mix Library`
- **GitLab namespace:** `Pinault` (confirm with the user; their other repos use `git@gitlab.com:Pinault/...`)
- **Optional extras (Step 3):** select `dialyxir` (recommended for a library); skip `benchee`.
- **Hex description** (asked for the Library `project/0`): `A Swoosh-style Slack library — send Slack messages through one choke point with per-environment adapters, plus a fake Slack dev UI and test assertions.`

This runs `mix new slackbox` in `/Users/manu/Projects`, applies the Mix Library `mix.exs`/`.credo.exs`/`.gitlab-ci.yml`/`CLAUDE.md`/`AGENTS.md`/`.claude/settings.json` templates, and does the initial git commit.

- [ ] **Step 2: Verify scaffold compiles**

Run: `cd /Users/manu/Projects/slackbox && mix deps.get && mix compile`
Expected: compiles clean, no warnings.

- [ ] **Step 3: Enable `test/support` compilation**

In `/Users/manu/Projects/slackbox/mix.exs`, add `elixirc_paths/1` and wire it into `project/0`:

```elixir
def project do
  [
    app: :slackbox,
    version: "0.1.0",
    elixir: "~> 1.15",
    elixirc_paths: elixirc_paths(Mix.env()),
    start_permanent: Mix.env() == :prod,
    deps: deps(),
    aliases: aliases(),
    description: "A Swoosh-style Slack library — send Slack messages through one choke point with per-environment adapters, plus a fake Slack dev UI and test assertions.",
    package: package(),
    name: "Slackbox",
    source_url: "https://gitlab.com/Pinault/slackbox",
    docs: [main: "Slackbox", extras: ["README.md"]]
  ]
end

defp elixirc_paths(:test), do: ["lib", "test/support"]
defp elixirc_paths(_), do: ["lib"]
```

- [ ] **Step 4: Move the spec and this plan into the project**

```bash
mkdir -p /Users/manu/Projects/slackbox/docs/superpowers/specs /Users/manu/Projects/slackbox/docs/superpowers/plans
cp /Users/manu/Projects/slackbox_brainstorm/docs/superpowers/specs/2026-07-02-slackbox-design.md /Users/manu/Projects/slackbox/docs/superpowers/specs/
cp /Users/manu/Projects/slackbox_brainstorm/docs/superpowers/plans/2026-07-02-slackbox-phase1-core-outbound.md /Users/manu/Projects/slackbox/docs/superpowers/plans/
```

- [ ] **Step 5: Commit**

```bash
cd /Users/manu/Projects/slackbox
git add mix.exs docs/
git commit -m "chore: add test/support path, design spec, and phase-1 plan"
```

---

## Task 1: Message struct + core builders

**Files:**
- Create: `lib/slackbox/message.ex`
- Test: `test/slackbox/message_test.exs`

- [ ] **Step 1: Write the failing test**

Create `test/slackbox/message_test.exs`:

```elixir
defmodule Slackbox.MessageTest do
  use ExUnit.Case, async: true

  import Slackbox.Message

  describe "builders" do
    test "new/1 accepts attrs and returns a struct with defaults" do
      msg = new(channel: "#alerts")
      assert msg.channel == "#alerts"
      assert msg.blocks == []
      assert msg.metadata == %{}
    end

    test "pipe builders set fields" do
      msg =
        new()
        |> to_channel("#alerts")
        |> text("Build failed")
        |> thread("1783017.0001")
        |> to_user("U123")
        |> unfurl_links(false)

      assert msg.channel == "#alerts"
      assert msg.text == "Build failed"
      assert msg.thread_ts == "1783017.0001"
      assert msg.user == "U123"
      assert msg.unfurl_links == false
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /Users/manu/Projects/slackbox && mix test test/slackbox/message_test.exs`
Expected: FAIL — `Slackbox.Message` is not available / `import` fails to compile.

- [ ] **Step 3: Write minimal implementation**

Create `lib/slackbox/message.ex`:

```elixir
defmodule Slackbox.Message do
  @moduledoc """
  A Slack message with composable pipe builders — the Slack analogue of
  `Swoosh.Email`. The struct alone fully determines what the fake Slack dev UI
  renders, so message *content* lives here (not in per-call options).

  A raw Slack JSON map may be supplied via `:raw` as an escape hatch.
  """

  @type t :: %__MODULE__{
          channel: String.t() | nil,
          text: String.t() | nil,
          blocks: [map()],
          attachments: [map()],
          thread_ts: String.t() | nil,
          ts: String.t() | nil,
          user: String.t() | nil,
          username: String.t() | nil,
          icon: String.t() | nil,
          metadata: map(),
          unfurl_links: boolean() | nil,
          unfurl_media: boolean() | nil,
          reply_broadcast: boolean() | nil,
          raw: map() | nil
        }

  defstruct channel: nil,
            text: nil,
            blocks: [],
            attachments: [],
            thread_ts: nil,
            ts: nil,
            user: nil,
            username: nil,
            icon: nil,
            metadata: %{},
            unfurl_links: nil,
            unfurl_media: nil,
            reply_broadcast: nil,
            raw: nil

  @doc "Build a new message from keyword/map attrs."
  @spec new(keyword() | map()) :: t()
  def new(attrs \\ []), do: struct(__MODULE__, attrs)

  @doc "Set the destination channel (e.g. `\"#alerts\"` or a channel id)."
  @spec to_channel(t(), String.t()) :: t()
  def to_channel(%__MODULE__{} = msg, channel), do: %{msg | channel: channel}

  @doc "Set the fallback/notification text."
  @spec text(t(), String.t()) :: t()
  def text(%__MODULE__{} = msg, text), do: %{msg | text: text}

  @doc "Post this message as a threaded reply to `parent_ts`."
  @spec thread(t(), String.t()) :: t()
  def thread(%__MODULE__{} = msg, parent_ts), do: %{msg | thread_ts: parent_ts}

  @doc "Target user for `post_ephemeral`."
  @spec to_user(t(), String.t()) :: t()
  def to_user(%__MODULE__{} = msg, user), do: %{msg | user: user}

  @doc "Toggle Slack link unfurling for this message."
  @spec unfurl_links(t(), boolean()) :: t()
  def unfurl_links(%__MODULE__{} = msg, bool), do: %{msg | unfurl_links: bool}
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd /Users/manu/Projects/slackbox && mix test test/slackbox/message_test.exs`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
cd /Users/manu/Projects/slackbox
git add lib/slackbox/message.ex test/slackbox/message_test.exs
git commit -m "feat: add Slackbox.Message struct and core builders"
```

---

## Task 2: Block Kit builders + `action_ids/1` introspection

**Files:**
- Modify: `lib/slackbox/message.ex`
- Test: `test/slackbox/message_test.exs` (add a describe block)

- [ ] **Step 1: Write the failing test**

Add this `describe` block inside `test/slackbox/message_test.exs`:

```elixir
  describe "block kit" do
    test "blocks/2 stores blocks built from section/actions/button" do
      msg =
        new()
        |> to_channel("#alerts")
        |> blocks([
          section("Build *failed* on `main`"),
          actions([
            button("Retry", action_id: "retry_build", value: "1234"),
            button("View logs", action_id: "view_logs")
          ])
        ])

      assert [section_block, actions_block] = msg.blocks
      assert section_block["type"] == "section"
      assert section_block["text"] == %{"type" => "mrkdwn", "text" => "Build *failed* on `main`"}
      assert actions_block["type"] == "actions"
      assert [retry, _logs] = actions_block["elements"]
      assert retry["type"] == "button"
      assert retry["action_id"] == "retry_build"
      assert retry["value"] == "1234"
    end

    test "action_ids/1 collects action_ids across all action blocks" do
      msg =
        new()
        |> blocks([
          actions([button("Retry", action_id: "retry_build")]),
          section("ignored"),
          actions([button("Approve", action_id: "approve"), button("Reject", action_id: "reject")])
        ])

      assert Slackbox.Message.action_ids(msg) == ["retry_build", "approve", "reject"]
    end

    test "action_ids/1 is empty when there are no action blocks" do
      assert Slackbox.Message.action_ids(new()) == []
    end
  end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /Users/manu/Projects/slackbox && mix test test/slackbox/message_test.exs`
Expected: FAIL — `blocks/2`, `section/1`, `actions/1`, `button/2`, `action_ids/1` undefined.

- [ ] **Step 3: Write minimal implementation**

Add these functions to `lib/slackbox/message.ex`, after `unfurl_links/2`:

```elixir
  @doc "Set the Block Kit blocks for this message."
  @spec blocks(t(), [map()]) :: t()
  def blocks(%__MODULE__{} = msg, blocks), do: %{msg | blocks: blocks}

  @doc "A Block Kit `section` block with mrkdwn text."
  @spec section(String.t()) :: map()
  def section(text) do
    %{"type" => "section", "text" => %{"type" => "mrkdwn", "text" => text}}
  end

  @doc "A Block Kit `actions` block wrapping interactive elements."
  @spec actions([map()]) :: map()
  def actions(elements), do: %{"type" => "actions", "elements" => elements}

  @doc """
  A Block Kit `button` element. Supported opts: `:action_id`, `:value`.
  Nil opts are dropped so the payload matches Slack's shape.
  """
  @spec button(String.t(), keyword()) :: map()
  def button(text, opts \\ []) do
    %{"type" => "button", "text" => %{"type" => "plain_text", "text" => text}}
    |> maybe_put("action_id", Keyword.get(opts, :action_id))
    |> maybe_put("value", Keyword.get(opts, :value))
  end

  @doc "Collect every `action_id` from the message's `actions` blocks, in order."
  @spec action_ids(t()) :: [String.t()]
  def action_ids(%__MODULE__{blocks: blocks}) do
    blocks
    |> Enum.filter(&(&1["type"] == "actions"))
    |> Enum.flat_map(fn block -> Enum.map(block["elements"] || [], & &1["action_id"]) end)
    |> Enum.reject(&is_nil/1)
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
```

Note: the Task 1 test asserted `retry["value"] == "1234"` and `retry["action_id"] == "retry_build"` — both present, so `maybe_put` keeps them. The `_logs` button omits `:value`, so its map simply has no `"value"` key.

- [ ] **Step 4: Run test to verify it passes**

Run: `cd /Users/manu/Projects/slackbox && mix test test/slackbox/message_test.exs`
Expected: PASS (5 tests total).

- [ ] **Step 5: Commit**

```bash
cd /Users/manu/Projects/slackbox
git add lib/slackbox/message.ex test/slackbox/message_test.exs
git commit -m "feat: add Block Kit builders and action_ids introspection"
```

---

## Task 3: Adapter behaviour + Test adapter

**Files:**
- Create: `lib/slackbox/adapter.ex`
- Create: `lib/slackbox/adapters/test.ex`
- Test: `test/slackbox/test_adapter_test.exs`

- [ ] **Step 1: Write the failing test**

Create `test/slackbox/test_adapter_test.exs`:

```elixir
defmodule Slackbox.Adapters.TestTest do
  use ExUnit.Case, async: true

  alias Slackbox.Adapters.Test, as: TestAdapter
  alias Slackbox.Message

  test "call/3 sends the action tuple to the current process" do
    msg = Message.new(channel: "#alerts", text: "hi")
    assert {:ok, %{ts: ts, channel: "#alerts"}} = TestAdapter.call(:post_message, %{message: msg, opts: []}, [])
    assert is_binary(ts)
    assert_received {:slackbox, :post_message, %{message: ^msg}}
  end

  test "call/3 also reaches processes listed in $callers (async support)" do
    parent = self()
    Process.put(:"$callers", [parent])
    msg = Message.new(channel: "#c")

    task =
      Task.async(fn ->
        Process.put(:"$callers", [parent])
        TestAdapter.call(:post_message, %{message: msg, opts: []}, [])
      end)

    Task.await(task)
    assert_received {:slackbox, :post_message, %{message: ^msg}}
  end

  test "open_view returns a view_id" do
    assert {:ok, %{view_id: "V" <> _}} = TestAdapter.call(:open_view, %{trigger_id: "t1", view: %{}, opts: []}, [])
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /Users/manu/Projects/slackbox && mix test test/slackbox/test_adapter_test.exs`
Expected: FAIL — `Slackbox.Adapters.Test` undefined.

- [ ] **Step 3a: Write the behaviour**

Create `lib/slackbox/adapter.ex`:

```elixir
defmodule Slackbox.Adapter do
  @moduledoc """
  The contract every Slackbox adapter implements (`Live`, `Local`, `Test`).

  A single `call/3` entry point dispatches every Slack action, so adapters can
  pattern-match on the action atom rather than implementing one callback each.
  """

  @type action :: :post_message | :post_ephemeral | :update | :delete | :open_view | :respond
  @type args :: map()
  @type config :: keyword()

  @callback call(action(), args(), config()) :: {:ok, map()} | {:error, term()}
end
```

- [ ] **Step 3b: Write the Test adapter**

Create `lib/slackbox/adapters/test.ex`:

```elixir
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
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd /Users/manu/Projects/slackbox && mix test test/slackbox/test_adapter_test.exs`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
cd /Users/manu/Projects/slackbox
git add lib/slackbox/adapter.ex lib/slackbox/adapters/test.ex test/slackbox/test_adapter_test.exs
git commit -m "feat: add adapter behaviour and Test adapter"
```

---

## Task 4: Notifier dispatch

**Files:**
- Create: `lib/slackbox/notifier.ex`
- Create: `test/support/test_notifier.ex`
- Modify: `test/test_helper.exs`
- Test: `test/slackbox/notifier_test.exs`

- [ ] **Step 1: Create the fixture notifier and configure the Test adapter**

Create `test/support/test_notifier.ex`:

```elixir
defmodule Slackbox.TestNotifier do
  @moduledoc false
  use Slackbox.Notifier, otp_app: :slackbox
end
```

Replace `test/test_helper.exs` with:

```elixir
Application.put_env(:slackbox, Slackbox.TestNotifier, adapter: Slackbox.Adapters.Test)

ExUnit.start()
```

- [ ] **Step 2: Write the failing test**

Create `test/slackbox/notifier_test.exs`:

```elixir
defmodule Slackbox.NotifierTest do
  use ExUnit.Case, async: true

  alias Slackbox.Message
  alias Slackbox.TestNotifier

  test "post_message dispatches to the configured adapter and returns {:ok, meta}" do
    msg = Message.new(channel: "#alerts", text: "hi")
    assert {:ok, %{ts: _ts, channel: "#alerts"}} = TestNotifier.post_message(msg)
    assert_received {:slackbox, :post_message, %{message: ^msg}}
  end

  test "deliver/1 is an alias for post_message" do
    msg = Message.new(channel: "#c")
    assert {:ok, _} = TestNotifier.deliver(msg)
    assert_received {:slackbox, :post_message, %{message: ^msg}}
  end

  test "open_view dispatches with trigger_id and view" do
    assert {:ok, %{view_id: _}} = TestNotifier.open_view("trigger-1", %{type: "modal"})
    assert_received {:slackbox, :open_view, %{trigger_id: "trigger-1", view: %{type: "modal"}}}
  end

  test "respond dispatches with the response_url" do
    msg = Message.new(text: "updated")
    assert {:ok, _} = TestNotifier.respond("https://example/response/abc", msg)
    assert_received {:slackbox, :respond, %{response_url: "https://example/response/abc", message: ^msg}}
  end

  test "per-call opts override configured adapter config" do
    msg = Message.new(channel: "#c")
    assert {:ok, _} = TestNotifier.post_message(msg, token: "override")
    assert_received {:slackbox, :post_message, %{opts: [token: "override"]}}
  end
end
```

- [ ] **Step 3: Run test to verify it fails**

Run: `cd /Users/manu/Projects/slackbox && mix test test/slackbox/notifier_test.exs`
Expected: FAIL — `Slackbox.Notifier` undefined (and `test/support/test_notifier.ex` fails to compile).

- [ ] **Step 4: Write minimal implementation**

Create `lib/slackbox/notifier.ex`:

```elixir
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
        Slackbox.Notifier.dispatch(__MODULE__, @otp_app, :post_message, %{message: message, opts: opts})
      end

      def deliver(message, opts \\ []), do: post_message(message, opts)

      def post_ephemeral(message, opts \\ []) do
        Slackbox.Notifier.dispatch(__MODULE__, @otp_app, :post_ephemeral, %{message: message, opts: opts})
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
  @spec dispatch(module(), atom(), Slackbox.Adapter.action(), map()) :: {:ok, map()} | {:error, term()}
  def dispatch(notifier, otp_app, action, args) do
    config = Application.get_env(otp_app, notifier, [])
    adapter = Keyword.fetch!(config, :adapter)
    merged_config = Keyword.merge(config, Map.get(args, :opts, []))
    adapter.call(action, args, merged_config)
  end
end
```

- [ ] **Step 5: Run test to verify it passes**

Run: `cd /Users/manu/Projects/slackbox && mix test test/slackbox/notifier_test.exs`
Expected: PASS (5 tests).

- [ ] **Step 6: Commit**

```bash
cd /Users/manu/Projects/slackbox
git add lib/slackbox/notifier.ex test/support/test_notifier.ex test/test_helper.exs test/slackbox/notifier_test.exs
git commit -m "feat: add Slackbox.Notifier dispatch macro"
```

---

## Task 5: Test assertions

**Files:**
- Create: `lib/slackbox/test_assertions.ex`
- Test: `test/slackbox/test_assertions_test.exs`

- [ ] **Step 1: Write the failing test**

Create `test/slackbox/test_assertions_test.exs`:

```elixir
defmodule Slackbox.TestAssertionsTest do
  use ExUnit.Case, async: true

  import Slackbox.TestAssertions

  alias Slackbox.Message
  alias Slackbox.TestNotifier

  test "assert_message_sent/1 matches on attrs, including a regex" do
    TestNotifier.post_message(Message.new(channel: "#alerts", text: "Build failed on main"))

    assert_message_sent(channel: "#alerts")
    assert_message_sent(text: ~r/failed/)
  end

  test "assert_message_sent/1 accepts a predicate function" do
    msg =
      Message.new(channel: "#alerts")
      |> Message.blocks([Message.actions([Message.button("Retry", action_id: "retry_build")])])

    TestNotifier.post_message(msg)

    assert_message_sent(fn m ->
      assert Message.action_ids(m) == ["retry_build"]
    end)
  end

  test "refute_message_sent/1 passes when nothing was sent" do
    refute_message_sent(channel: "#nope")
  end

  test "assert_ephemeral_sent and assert_message_updated match their actions" do
    TestNotifier.post_ephemeral(Message.new(channel: "#c", user: "U1", text: "psst"))
    assert_ephemeral_sent(channel: "#c")

    TestNotifier.update(Message.new(channel: "#c", ts: "1783.1", text: "edited"))
    assert_message_updated(text: "edited")
  end

  test "assert_view_opened yields the trigger_id and view" do
    TestNotifier.open_view("trigger-9", %{type: "modal", callback_id: "cfg"})

    assert_view_opened(fn %{trigger_id: trigger_id, view: view} ->
      assert trigger_id == "trigger-9"
      assert view.callback_id == "cfg"
    end)
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /Users/manu/Projects/slackbox && mix test test/slackbox/test_assertions_test.exs`
Expected: FAIL — `Slackbox.TestAssertions` undefined.

- [ ] **Step 3: Write minimal implementation**

Create `lib/slackbox/test_assertions.ex`:

```elixir
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
          flunk("Expected no post_message matching #{inspect(attrs)}, but got: #{inspect(message)}")
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
    receive do
      {:slackbox, ^action, %{message: message}} -> message
    after
      0 -> flunk("Expected a #{action} to have been sent, but none was captured.")
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
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd /Users/manu/Projects/slackbox && mix test test/slackbox/test_assertions_test.exs`
Expected: PASS (5 tests).

- [ ] **Step 5: Commit**

```bash
cd /Users/manu/Projects/slackbox
git add lib/slackbox/test_assertions.ex test/slackbox/test_assertions_test.exs
git commit -m "feat: add Slackbox.TestAssertions"
```

---

## Task 6: Phase 1 quality gate + README usage

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Document Phase 1 usage in the README**

Replace the generated `## Installation` placeholder section body in `README.md` with a usage section:

````markdown
## Usage (outbound + tests)

Define a notifier:

```elixir
defmodule MyApp.Slack do
  use Slackbox.Notifier, otp_app: :my_app
end
```

Configure the adapter per environment:

```elixir
# config/test.exs
config :my_app, MyApp.Slack, adapter: Slackbox.Adapters.Test
```

Send messages through the one choke point:

```elixir
import Slackbox.Message

new()
|> to_channel("#alerts")
|> text("Build failed on main")
|> blocks([
     section("Build *failed* on `main`"),
     actions([button("Retry", action_id: "retry_build", value: "1234")])
   ])
|> MyApp.Slack.post_message()
```

Assert in tests:

```elixir
import Slackbox.TestAssertions

test "notifies #alerts on failure" do
  MyApp.Notifier.on_build_failed(build)
  assert_message_sent(channel: "#alerts", text: ~r/failed/)
  refute_message_sent(channel: "#general")
end
```
````

- [ ] **Step 2: Run the full quality gate**

Run: `cd /Users/manu/Projects/slackbox && mix precommit`
Expected: PASS — `compile --warnings-as-errors`, `format --check-formatted`, `credo --strict`, and all tests (18 across the four test files) green.

If `mix format --check-formatted` fails, run `mix format` and re-run. If Credo flags an issue, fix it (common: add `@moduledoc`, wrap lines > 120). Do not commit until the gate is green.

- [ ] **Step 3: Commit**

```bash
cd /Users/manu/Projects/slackbox
git add README.md
git commit -m "docs: add Phase 1 usage to README"
```

---

## Self-Review

**Spec coverage (Phase 1 slice of §4 + §7):**
- §4.1 Message struct + builders → Tasks 1–2 ✓ (core fields, Block Kit `section`/`actions`/`button`, `action_ids/1`). Builders beyond v1's button/section — e.g. select menus, datepickers — are deferred to when the dashboard renders them (Plan 3+); Phase 1 only needs enough to prove the pattern and support tests.
- §4.2 Notifier functions (`post_message`/`deliver`/`post_ephemeral`/`update`/`delete`/`open_view`/`respond`, each with `opts`) → Task 4 ✓.
- §4.3 Adapter behaviour → Task 3 ✓ (single `call/3`).
- §7 Test adapter + assertions → Tasks 3, 5 ✓ (`assert_message_sent`, `refute_message_sent`, `assert_ephemeral_sent`, `assert_message_updated`, `assert_view_opened`). `Slackbox.Test` inbound payload builders are a Phase 5 item — correctly out of scope here.
- `Live` / `Local` adapters, store, dashboard, Simulator → deferred to Plans 2–5 ✓.

**Placeholder scan:** No TBD/TODO; every code step has complete code and an exact run command with expected result. (Task 0 delegates to the scaffold skill, which is itself the concrete procedure — inputs are fully specified.)

**Type consistency:** The action tuple `{:slackbox, action, args}` and the `args` maps (`%{message:, opts:}`, `%{trigger_id:, view:, opts:}`, `%{response_url:, message:, opts:}`) are identical across the Test adapter (Task 3), Notifier (Task 4), and assertions (Task 5). `Slackbox.Adapter.action()` type lists exactly the six actions the Notifier emits. `action_ids/1` name is consistent between Task 2 (definition) and Task 5 (use). `dispatch/4` name matches between the macro body and the `@doc false` function.

**Note on assertion semantics:** attribute assertions match the *next* captured message of an action (Swoosh parity), not "any captured message." This is documented in the module doc and is acceptable for v1; a future scan-all matcher is a possible enhancement, not a requirement.
