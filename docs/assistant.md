# Velora desktop assistant

Ordinary search, Lens, and the assistant are separate choices. The assistant is
off by default and starts `velora-agentd` after a submitted request, model
check, explicit download, or inspection of saved transactions. Enabling its switch
and opening history do not load a model. Lens can
also disable **Search by meaning** independently: names, paths and indexed text
remain available, and existing vectors are retained.

## Setup

Update the shell source and installed native tools together. After updating a
checkout, `./velora deps --skip-packages` rebuilds and installs the matching native
binaries without changing system packages; it also performs the existing font
and runtime checks. Then restart Quickshell. `velora relink` only updates links
and does not refresh binaries. A protocol mismatch deliberately blocks agent
execution until both sides are updated.

Build/install the native tools with the usual Velora installer. In
**Settings → AI → Desktop actions**, install the optional local backend
(`velora deps --add assistant`), enable the assistant, select a model, and use
**Download model** then **Check model**. The installed-model selector reads local
manifests without starting Ollama. Downloads show transferred bytes and support
cancellation. A cancelled download can leave reusable Ollama partial layers.

With no saved model choice, chat and desktop actions default to the smallest
installed model in the local Ollama runtime's model directory. Discovery reads
manifests without starting inference. If that directory is empty, choose a model
to download or configure a connection; no uninstalled model is selected by default.
Saved explicit model choices are preserved.

The download profiles are Qwen3.5 2B, 4B and 9B Q4_K_M, with approximate download
sizes from the [Ollama catalogue](https://ollama.com/library/qwen3.5/tags). A model name can also be
entered directly, including larger installed models. The stronger model is a
separate explicit per-request choice. Velora never silently changes the selected
model. CPU is the default; GPU offload is opt-in on external power and disabled
on battery. Idle keep-alive is 60 seconds on battery and five minutes on external
power. Only a backend started by Velora is stopped by Velora.

Compatible APIs accept a full Chat Completions URL. Gemini accepts its base URL
(`https://generativelanguage.googleapis.com/v1beta`) or a full
`streamGenerateContent?alt=sse` URL; `{model}` in a full URL follows the selected
model. Keys are stored with the existing system keyring service, never in config
JSON or process arguments. Local-only policy blocks remote endpoints and cloud
Ollama model aliases. Each remote task asks permission before sending its
conversation, file excerpts or screenshots.

## Use

**Settings → Search → AI in search** controls the launcher's **Ask AI** and
**Run a task** choices separately from the sidebar assistant. It is off by default.
Enabling it also enables the desktop assistant; disabling it hides these choices
and cancels a pending launcher AI request. Explicit shell commands and ordinary
app, calculator, and web search continue to work.

Search and AI have separate settings pages. **Add** in the sidebar model picker
opens **Settings → AI** directly in the connection editor. Provider presets cover
OpenAI, Claude, Gemini, DeepSeek, OpenRouter, Groq, Mistral and Grok, plus a custom
Chat Completions endpoint. Enter the provider's model ID and key; model catalogue
and key-management links are included. Keys are stored only in the system
keyring, and a failed key write does not publish a connection. Provider/model IDs
do not collide across endpoints. Changes refresh the shell's model list and
credentials without restarting it; adding a connection does not enable cloud
access or generate a billable request. A saved connection can also be selected
for the desktop assistant.

The AI page keeps access policy at the top and separates **Models & connections**,
**Chat**, and **Desktop actions** into tabs. Connections show whether a key is
saved and offer explicit choices for chat and actions. The actions tab can use a
local model, a saved connection, or manual settings; advanced model parameters
are folded away. Opening these controls does not start inference.

The Search page separates the launcher preview, folders, indexing, and music
recognition. Its preview uses the launcher's results and configured prefixes;
pressing Enter updates the preview without opening a result or executing a
command. Settings search can reveal controls inside the appropriate tab.

**Free memory** is available in the model picker and chat options for a local
Ollama model. It sends an empty generation request with `keep_alive: 0`, never
deletes model files, and leaves the conversation intact. It is disabled during
generation; the next request loads the model again. The isolated CUDA check
verifies that `/api/ps` is empty afterwards and the message count is unchanged.

Endpoint references: [OpenAI Docs](https://developers.openai.com/api/reference/chat-completions/overview),
[Claude compatibility](https://platform.claude.com/docs/en/cli-sdks-libraries/libraries/openai-sdk),
[DeepSeek](https://api-docs.deepseek.com/),
[OpenRouter](https://openrouter.ai/docs/api/api-reference/chat/create-a-chat-completion),
[Groq](https://console.groq.com/docs/openai),
[Mistral](https://docs.mistral.ai/api/endpoint/chat),
[Grok](https://docs.x.ai/developers/rest-api-reference/inference/chat-completions),
and [Ollama model lifetime](https://docs.ollama.com/faq#how-can-i-keep-a-model-loaded-in-memory-or-make-it-unload-immediately).

Press Super and enter a request. **Ask AI** discusses it without modifying files;
**Run a task** permits proposing confirmed, reversible actions. Ambiguous requests
offer an explicit search/question/task choice. Each launcher submission creates a
new chat and durably saves it before execution. Dialogue remains
inside either launcher. The sidebar chat uses the same assistant conversation
while the assistant is enabled. Ordinary search still works when the model is
missing or fails. Requests are classified locally before submission. Search and discussion cannot
modify files. Actions start only after Enter or selection of the action result;
this starts the task and never approves its commands. Unsupported desktop/UI
mutations are blocked until they have a verified rollback adapter.

New configurations default to local-only AI; existing explicit choices are kept.
Ordinary sidebar cloud chat also requires approval of its conversation context.
Consent is bound to the model, endpoint, tool mode and actual message context;
locking or changing access policy revokes it. Consent notices remain visible in
history but never become model context or replayable permissions.

The sidebar presents ordinary chat and desktop tasks in one timeline. Requests
remember whether they came from the sidebar or launcher, so confirmations and
results return to that surface. The sidebar shows startup, loading, reasoning,
generation and task progress, with an elapsed timer and a Stop control. Model
reasoning, when supplied by the provider, can be expanded per response or by
default in Chat options. Opening and closing reasoning is animated; typography,
colors and motion duration follow the shell theme.

Conversations and drafts autosave locally after 500 ms of changes, and immediately
on completion, cancellation or switching. Files live under the existing AI chat
directory in `conversations/`, with atomic replacement and private permissions.
Old JSON chats, including `lastSession`, import once without modifying originals.
History supports content search, rename, confirmed deletion and Markdown export.
Editing a request creates a separate conversation with the preceding text context;
the original remains available. Interrupted replies retain their partial text.

Opening saved history never starts a model. Assistant restoration sends only
user/assistant text on the next request; approvals, object references, screenshots
and file permissions are not restored. Select files again for new actions.
Locking clears the active context, and saved history must be opened explicitly
after unlocking. Sidebar attachments follow the selected backend's capabilities:
ordinary Gemini chat accepts one file, desktop tasks accept up to 100, and other
ordinary providers currently have no file adapter.

Ordinary local chat starts Ollama lazily and uses its native streaming API,
including reasoning fragments. GPU acceleration can be disabled in Chat options;
it is enabled by default on external power and disabled on battery. The desktop
assistant retains its separate GPU setting. Cancellation stops the request and
preserves output; only a server owned by Velora is stopped on idle.

Files are introduced by Lens search, the file picker, or Dolphin's **Ask Velora**
service-menu action. A ZIP goes to the XDG desktop by default. Every supported
mutation—create, copy, move, archive, or recoverable deletion—requires an exact
confirmation after its checkpoint has been prepared. Existing destinations are
never overwritten by copy/move/archive. A deleted file is retained in the private
checkpoint until the person explicitly deletes that checkpoint; it is not sent
to a desktop trash service whose recovery cannot be verified.

Terminal commands require two decisions when they change files: first approve
the exact command and selected working folder, then review and approve the
resulting diff. Bubblewrap runs the command in a disposable copy at `/work` and an alias at the original folder path, with
no host writable bind, network, desktop sockets, IPC, elevated capabilities, or
nested user namespaces. Environment variables are cleared. CPU, address space,
process count, open-file count, file size and a 60-second timeout are bounded.
While a command runs, checkpoint storage is checked every 250 ms; exceeding the
budget stops the command. No diff reaches the real folder until approval and
revalidation of its original contents and file identities. A failed or cancelled
command discards the staging copy. Diff previews include bounded unified text,
exact paths and byte sizes; binary and large files are labeled explicitly.

## Rollback and restrictions

File content reads hold no-follow descriptors for every ancestor and the file,
verify the remembered device/inode and user ownership, reject hard links, and
bound reads to 128 KiB. File changes during reading are rejected. Agent search
returns names, paths and relevance without stored index excerpts; current text
must pass the same guarded read. The ordinary launcher keeps its own search
previews.

The executor, not the model, owns rollback. Before the first host mutation of a
step it durably stores before-images, expected after-images and an undo journal.
Snapshots use copy-on-write cloning where the filesystem supports it, with a
copy fallback. Files retain bytes, permissions, group, modification time and
extended attributes. Unsupported ownership, privileged files, hard links,
symbolic links, special files and directories with extended attributes are
rejected. Directory contents and permissions are restored; directory access and
modification timestamps are not promised. Existing files that change after
preparation are rejected. Rollback preserves conflicting newer content and
reports the paths requiring review instead of overwriting it.

The whole submitted task is a transaction. Error, rejection, timeout, Stop,
locking and orderly shutdown roll back its completed changes in reverse order.
An exclusive executor lease prevents concurrent daemons from recovering each
other's work. On the next startup after a crash, unfinished journal entries are
recovered before accepting work. Recovery never calls a model and never replays
the original command. Successful tasks retain their checkpoint for manual
rollback from chat history. A rolled-back task cannot truthfully report success.

Checkpoint files live under `$XDG_STATE_HOME/velora/transactions` (normally
`~/.local/state/velora/transactions`) with private permissions. The default total
budget is 2 GiB, configurable with `rollback_budget_bytes`; exhaustion blocks new
checkpoints. Existing checkpoints are never silently evicted. Explicit checkpoint
deletion keeps a small submission tombstone so a retransmitted request still
cannot run twice. Checkpoints with unresolved conflicts cannot be deleted.
The shell exposes this limit in **Settings → AI → Desktop actions → Rollback
checkpoints** and persists it as `assistant.rollbackBudgetBytes`.

Hard policy rejects system roots, the journal itself, credentials and browser or
keyring stores. The running executor source tree, agent binaries, runtime tool
paths, checkout/live Quickshell execution code and the main safety configuration
are immutable through the agent, including after ordinary approval. Staging omits
these paths and applying newly created replacements is rejected. Trusted Python
helpers use `/usr/bin/python3 -I`, ignoring PATH shadowing, PYTHONPATH and user-site
imports. Ordinary selected project/configuration folders, including `.config/hypr`, are supported.
The terminal copy omits protected entries and cannot create protected paths in
an applied diff. UI input, presets, application launches and document-open
requests are currently blocked: their effects cannot be given a deterministic
rollback guarantee. Read-only desktop inspection remains available. The legacy
sidebar must use this executor for commands; direct `bash -c` or configuration
writes from a provider response are not authorized execution routes.

## Protocol and execution

`velora-agentd` is a Rust stdio JSON-lines service using protocol **3**. Requests
retain increasing numeric transport IDs. `submit` additionally requires stable
ASCII `submission_id` and `conversation_id` values; its transaction ID is the
submission ID. The executor persists that ID before doing work and rejects its
reuse across restarts. `intent: "chat"` (the default) prohibits all mutating tools;
`intent: "action"` permits proposing changes, each still requiring confirmation.
An optional `tool: {name: "terminal_run", arguments: {command, cwd?, network: false}}`
executes that exact requested command through the same isolated flow; missing
`cwd` opens a folder picker. It does not ask a model to reinterpret the command.

Existing methods `configure`, `context`, `selection`, `approve`, `surface_ready`,
`cancel`, `reset`, `restore`, `probe`, `pull` and `status` remain. `transactions`
returns `{transactions: [...]}`. `rollback: {transaction_id}` performs manual
rollback while idle and unlocked. `delete_checkpoint: {transaction_id,
confirmed: true}` explicitly discards a completed checkpoint. Both return its
updated metadata. A `transaction` event contains stable IDs, `state`,
`rollback_available` and `conflicts`; cancellation is acknowledged after rollback.
Terminal approvals use `terminal_run` for isolated execution and `terminal_apply`
for publishing its reviewed diff. Approval IDs are single-use, task-scoped and
expire after five minutes; changing the prepared operation requires a new plan.

Providers normalize streamed arguments before execution. Tool schemas reject
unknown fields and invalid types/ranges. Retrieved text and images are untrusted
observations. Only user-selected action intent and exact approvals authorize
mutations; words in a request or a document never grant write permission.
Conversation restoration accepts only inert user/assistant text, not approvals,
live file references, capabilities or executable tool calls.

A normal task has four model turns, an extended task twenty; both are limited to
twenty tool calls. Repeated actions and no-progress loops stop. A runtime-file
lease permits only one generation across shell processes. Search/indexing yields
resources while the main-shell task is active. Context is bounded (default 4K),
with 512 output tokens for normal requests. No model starts while typing or
opening saved history. Cancellation kills owned subprocess groups and then
performs deterministic journal recovery.

## Validation

Run behavioral tests without a desktop:

```sh
cargo test --locked --offline --manifest-path tools/Cargo.toml -p velora-agentd -p velora-searchd --lib
python3 -m unittest discover -s tests -p test_agent_transactions.py -v
python3 -m unittest discover -s tests -p test_agent_qml.py -v
python3 -m unittest discover -s tests -p test_lens.py -v
```

Build binaries before GUI/process checks, then isolate them from the running
session (private PID, network, `/run` and `/dev`; the host filesystem is read-only):

```sh
cargo build --locked --offline --manifest-path tools/Cargo.toml -p velora-agentd -p velora-connectivityd -p velora-connectivity-fakes
python3 tests/run_isolated.py -m unittest discover -s tests -p test_agent.py -v
python3 tests/run_isolated.py -m unittest discover -s tests -p test_agent_pages.py -v
python3 tests/run_isolated.py -m unittest discover -s tests -p test_sidebar_chat_pages.py -v
python3 -m unittest discover -s tests -p 'test_chat_*.py' -v
```

These use synthetic files and substitute desktop actions. They cover stale
results, lazy startup, disabled/locked states, late events, protocol replay,
malformed calls, tool-result continuation, partial failure, approvals, local-only
policy, cancellation and archive collision handling. They do not establish
success rates for every external application.

The opt-in `tests/agent_live.py` uses an installed Ollama model, CPU only, and a
synthetic directory, approving only this fixture's reversible archive operation. Run it through
`tests/run_isolated.py` with a separate writable model-metadata directory;
Ollama may migrate old manifests. Model blobs can remain read-only. In the older
protocol-2 implementation, the local
Qwen3.5 9B (`latest` on this machine) CPU run on 2026-11-02 completed ZIP creation
and dispatch to the default opener in 89.15 s; its follow-up identified the archive
in 5.77 s. The opener was substituted, so this does not claim a real archive
manager window was verified. One synthetic run is not a task-success benchmark.

`tools/velora-searchd/evaluation/compare_precision.py` compares temporary FP32 and
INT8 bundles on the functional corpus, with three runs per precision. A missing
model invalidates the measurement. Promotion requires >=20% CPU p95 improvement,
<=0.01 absolute Recall@5/nDCG@10 loss and all required scenarios passing. In the
2026-11-02 synthetic CPU run, FP32 passed all 66 phase/scenario checks. INT8 p95
was 227 ms versus 444 ms, but nDCG@10 fell from 1.0 to 0.98975 and an assignment
query ranked the seminar first. **FP32 remains the shipped precision.** These
figures are corpus-specific, not a guarantee for personal indexes.

Real desktop input, mixed monitor layouts, battery energy per task, and the
<=5% idle-assistant launcher p95 acceptance need an isolated graphical desktop
and repeatable hardware measurements. Do not run unisolated integration tests
against a user's active session. Repository dotfiles may be live symlinks.

Sidebar fixtures capture the actual components in both themes at widths
360/460/760 and scales 100/150/200%, under `cache/sidebar-chat`. They exercise
mouse toggling, reasoning animations, text selection, horizontal code scrolling,
history restoration and branching. `tests/sidebar_chat_live.py` is an opt-in
native-Qwen smoke test of startup, streamed reasoning, a final answer and Stop:

```sh
OLLAMA_MODELS=/path/to/ollama/models python3 tests/run_isolated.py --gpu tests/sidebar_chat_live.py
```

It copies model manifests, keeps blobs read-only and runs a private server. The
optional isolation flag exposes only NVIDIA device nodes, not the active desktop.
