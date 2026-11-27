# Velora desktop assistant

Ordinary search, Lens, and the assistant are separate choices. The assistant is
off by default. When enabled, it can prepare an installed CPU model after login.
Submitting a request, checking a model or opening saved transactions starts the
desktop service. Opening saved history reads the conversation from disk. Lens can
also disable **Search by meaning** independently: names, paths and indexed text
remain available, and existing vectors are retained.

## Asking about local files

Open **⋯** in the sidebar to set **File access**, attach documents with **Choose files**, or use **Run a script file…**. **Run commands and code** controls execution separately. Turning it on from a local chat without execution tools enables the desktop assistant and keeps the displayed file permission. With desktop actions disabled, turning on file access for ordinary local Ollama chat opens a read-only file conversation. Dolphin’s **Ask Velora** also accepts selected paths.

Local Ollama models can find installed apps, matching windows and files by name without asking. To review each lookup, turn off **Allow local searches without asking** in **Settings → AI → File access**. Turning off **File access** in the chat disables file search. Name search works with Lens off. Lens adds indexed document and content search. Both searches return file references.

When you name a file in your message and the local search returns just that file, the assistant can read it for this request. Selecting a folder makes its contents available for the task. Add trusted folders on the same settings page to limit the default file search and allow reads there across local chats. Searching beyond that list or reading another result asks for approval. Directory measurements flag incomplete scans when protected entries or time, depth and entry limits prevent full coverage.

Text and PDFs can be read directly. A model without tools receives excerpts or folder measurements for up to three items per question. A tool-capable model can page through UTF-8 text in chunks of up to 2,500 characters and request individual PDF pages. The initial PDF excerpt covers the first 12 pages. An image-only PDF needs OCR.

Under **Settings → AI → Models & connections**, choose **After each response**, a duration in minutes, or **Auto** to unload after 30 minutes on battery and 60 on AC. Conversation context is shared by local chat and desktop actions. Auto selects 4K, 8K or 16K according to RAM. The model’s own context limit also applies.

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

Gemma 4 E4B (`gemma4:e4b`) is the default local model for chat and desktop actions.
An explicit model choice takes priority. If Gemma is absent, Velora can use the
smallest installed model. With an empty library, **Download model** offers Gemma.
Discovery reads local manifests. Downloads start when you click the button.

Multilingual download profiles include Qwen3.5 2B, 4B and 9B, Ministral 3 3B (about 3.0 GB) and Gemma 4 E4B (about 6.6 GB). The picker shows whether a selected download is missing, incomplete or failed. Resume reuses Ollama’s existing layers. [Ministral](https://ollama.com/library/ministral-3:3b) · [Gemma](https://ollama.com/library/gemma4:e4b) · [Qwen](https://ollama.com/library/qwen3.5/tags)

### Multilingual CPU comparison

Ministral 3 3B is the fastest download profile for desktop actions in this test. Gemma 4 E4B completed all 42 checks, including all language switches. Either can be selected under **AI → Models & connections → Model for actions**.

| Ollama model | Chat | Language switch | Two apps on workspace 5 | First tool output, median | Task complete, median | Download |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Ministral 3 3B | 14/14 | 13/14 | 14/14 | 1.24 s | 5.18 s | 2.95 GB |
| Gemma 4 E4B | 14/14 | 14/14 | 14/14 | 4.57 s | 9.23 s | 6.58 GB |
| Qwen3.5 9B (`qwen3.5:latest`) | 14/14 | 14/14 | 13/14 | 18.59 s | 31.61 s | 6.59 GB |

Measured on 26 November 2026 with an AMD Ryzen AI 9 HX 370, Ollama 0.40.13, Q4_K_M, four CPU threads and a 16,384-token context. The tool task required the exact desktop IDs for VS Code and Firefox and workspace 5. Tool results were simulated. The other two checks asked a short question in each language with an empty chat and with a preceding exchange in a different language. Each case ran once in German, English, Spanish, French, Hebrew, Indonesian, Italian, Japanese, Portuguese, Russian, Turkish, Ukrainian, Vietnamese and Chinese. Ministral missed the switch to Turkish. Qwen missed the Russian tool task. These scores cover these particular prompts.

The median time to first text in the single-question chat was 0.36 s for Ministral, 0.60 s for Gemma and 1.05 s for Qwen. Ollama reported loaded-model sizes of 4.16 GB, 2.09 GB and 6.64 GB respectively, with zero VRAM for every trial. This is the size reported by `/api/ps`. Total process memory can differ. The [benchmark](../tests/local_model_languages.py) accepts a local model directory and writes a row for every trial.

A model name can also be
entered directly, including larger installed models. The stronger model is a
separate explicit per-request choice. Velora never silently changes the selected
model. Desktop actions use CPU by default. Ordinary chat and desktop actions each have a GPU setting, available on external power. Both use CPU on battery or in power-saving mode. In Integrated mode, local inference uses Velora’s device-isolated CPU server on port 11435. The GPU-enabled backend uses port 11434. Velora stops a backend it started when its idle timeout expires.

Compatible APIs accept a full Chat Completions URL. Gemini accepts its base URL
(`https://generativelanguage.googleapis.com/v1beta`) or a full
`streamGenerateContent?alt=sse` URL; `{model}` in a full URL follows the selected
model. Keys are stored with the existing system keyring service, never in config
JSON or process arguments. Local-only policy blocks remote endpoints and cloud
Ollama model aliases. Each remote task asks permission before sending its
conversation, file excerpts or screenshots.

## Use

**Settings → Search → AI in search** adds **Ask AI** to the launcher for questions
and tasks. This setting is off by default.
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

**Unload model** is available in the model picker and chat options for a local
Ollama model. It sends an empty generation request with `keep_alive: 0`, never
deletes model files, and leaves the conversation intact. It is disabled during
generation. Velora checks the loaded models before confirming the result. The next request loads the model again. The isolated CUDA check
verifies that `/api/ps` is empty afterwards and the message count is unchanged.

Endpoint references: [OpenAI Docs](https://developers.openai.com/api/reference/chat-completions/overview),
[Claude compatibility](https://platform.claude.com/docs/en/cli-sdks-libraries/libraries/openai-sdk),
[DeepSeek](https://api-docs.deepseek.com/),
[OpenRouter](https://openrouter.ai/docs/api/api-reference/chat/create-a-chat-completion),
[Groq](https://console.groq.com/docs/openai),
[Mistral](https://docs.mistral.ai/api/endpoint/chat),
[Grok](https://docs.x.ai/developers/rest-api-reference/inference/chat-completions),
and [Ollama model lifetime](https://docs.ollama.com/faq#how-can-i-keep-a-model-loaded-in-memory-or-make-it-unload-immediately).

Press Super, enter a request and select **Ask AI**. The launcher and sidebar use the same desktop assistant. For example, “на 5 десктопе открой фаерфокс и вс код” looks up Firefox and Visual Studio Code in the installed app catalog and offers to open or move each one to workspace 5. System diagnostics and commands ask for approval. A follow-up such as “да, посмотри сам” continues the current sidebar conversation. Each new launcher submission saves a fresh chat before execution.

Terminal applications such as btop open in the emulator selected under **Shell commands → Terminal for shell actions** in the default apps settings. The assistant tracks the window it opens and verifies its workspace. If several windows could be the requested one, you can select it by title. If the window takes longer to appear, **Check window** continues the original launch.

System diagnostics can report failed system and user services and recent journal errors from this boot, as well as disk space, RAM, processes, network, power, audio, monitors and workspaces. For a change in brightness or volume, the approval shows the device and the old and proposed percentages. Application launch and window controls show the target application or window and workspace. The executor checks the resulting level, active workspace or application window before reporting success. These controls act on the live desktop.

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

Opening saved history reads the conversation from disk. Assistant restoration sends only
user/assistant text on the next request; approvals, object references, screenshots
and file permissions are not restored. Select files again for new actions.
Locking clears the active context, and saved history must be opened explicitly
after unlocking. Sidebar attachments follow the selected backend's capabilities:
ordinary Gemini chat accepts one file, desktop tasks accept up to 100, and other
ordinary providers currently have no file adapter.

**Settings → AI → Models & connections → Prepare the local assistant after login** is enabled by default. With desktop actions enabled, Velora loads the installed CPU model on external power when memory and system load permit. Opening the composer can also start preparation. On battery or in power-saving mode it starts when you type. For models that support tools, Velora prepares the shared system instructions and tool description. The draft and conversation are sent when you press Send. **After each response** disables advance loading. [Ollama’s preload API](https://docs.ollama.com/faq#how-can-i-preload-a-model-into-ollama-to-get-faster-response-times)

The local desktop assistant initially sends descriptions of tools relevant to the request. It can ask for additional tool groups as it works. A general question can start streaming after processing a much shorter prompt.

Ordinary local chat uses Ollama’s native streaming API,
including reasoning fragments. GPU acceleration can be disabled in Chat options;
it is enabled by default on external power and disabled on battery. The desktop
assistant retains its separate GPU setting. Cancellation stops the request and
preserves output; only a server owned by Velora is stopped on idle.

Files can be found by name, by Lens, through the file picker, or with Dolphin’s **Ask Velora**. A ZIP goes to the XDG desktop by default. Creating, copying, moving, archiving or deleting files requires confirmation of a prepared checkpoint. Copy, move and archive operations require a free destination name. A deleted file stays in the private checkpoint until the person explicitly removes that checkpoint.

The agent can propose a shell command, write Python, Bash or JavaScript, or run a script selected under **⋯ → Run a script file…**. The confirmation shows the entire command or script, its interpreter and arguments, and the working folder. The preview stays visible during execution. Expand the completed steps in the sidebar to see it again. Selected script source is captured once, so editing the file while the confirmation is open cannot change what runs. Script previews accept up to 32 KiB of UTF-8 source. The executor returns the exit code and bounded program output for the answer.

Bubblewrap runs the approved program in a disposable folder or a staging copy of a chosen folder at `/work`. The staging copy is also visible at its original path inside the sandbox. Network and desktop sockets are isolated. The environment is cleared and CPU, memory, processes, output, temporary storage and execution time are bounded. Changes to a real folder require a second approval showing the affected paths, sizes and text differences. The executor revalidates file identities before publishing them. Cancelling or rejecting the diff discards the pending changes.

For a task spanning several files, attach the input files or select their working folder. Programs receive read-only snapshots of individual inputs at `/inputs/1`, `/inputs/2` and so on, in the order shown in the approval. The assistant can inspect a directory, transform data with a script, create or edit UTF-8 text, and read back its output. Failed programs return their exit status and diagnostic so the model can correct its approach. A declined approval ends the operation.

In applications exposing an accessibility tree, the assistant can inspect the current form, enter text in an observed editable field or activate an action offered by an observed control. The confirmation identifies the target. Velora rechecks the window and control before acting, then asks the model to inspect the result. Password fields are excluded.

## Rollback and restrictions

File content reads hold no-follow descriptors for every ancestor and the file,
verify the remembered device/inode and user ownership, reject hard links, and
bound each text read to 10,000 bytes. File changes during reading are rejected. Agent search
returns names, paths and relevance without stored index excerpts; current text
must pass the same guarded read. The ordinary launcher keeps its own search
previews.

The executor manages file rollback. Before the first filesystem mutation of a
step it durably stores before-images, expected after-images and an undo journal.
Snapshots use copy-on-write cloning where the filesystem supports it, with a
copy fallback. Files retain bytes, permissions, group, modification time and
extended attributes. Unsupported ownership, privileged files, hard links,
symbolic links, special files and directories with extended attributes are
rejected. Directory contents and permissions are restored; directory access and
modification timestamps are not promised. Existing files that change after
preparation are rejected. Rollback preserves conflicting newer content and
reports the paths requiring review instead of overwriting it.

File changes within one submission form a single transaction. Error, rejection, timeout, Stop, locking and orderly shutdown roll back its completed file changes in reverse order. Live desktop controls, such as a brightness change or an application launch, take effect when approved and are outside file rollback. A read-only result has no file checkpoint to remove.

An exclusive executor lease prevents concurrent daemons from recovering each other’s work. After a crash the executor recovers unfinished journal entries before accepting work. Recovery runs from recorded filesystem state. Successful file changes retain their checkpoint for manual rollback from chat history.

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
an applied diff. Interactive desktop tools support the specific verified controls described above. Free-form simulated input, preset changes and dispatching documents to arbitrary external openers are restricted. Commands suggested by any provider go through the same executor and approval flow.

## Protocol and execution

`velora-agentd` is a Rust stdio JSON-lines service using protocol **6**. Requests
retain increasing numeric transport IDs. `submit` additionally requires stable
ASCII `submission_id` and `conversation_id` values; its transaction ID is the
submission ID. The executor persists that ID before doing work and rejects its
reuse across restarts. The default chat intent permits read-only tools. Action intent permits proposed changes after confirmation. The interactive desktop profile adds `desktop_agent: true` on an action submission. The per-request flags `allow_files` and `allow_commands` control available tools and are checked again at execution time.

A direct `terminal_run` request accepts a shell `command`, generated `code` with a supported `language`, or a script file reference. The shell file picker can supply a local `script_path`. With an approved working directory the process receives a staging copy. Interactive commands and scripts with no working directory run in a temporary folder. The legacy explicit command entry point can prompt for a working directory.

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

An interactive desktop task can use up to 24 model turns and 64 tool calls. Extended tasks allow 48 turns and 128 calls. Ordinary requests allow four turns and 20 calls. During long tasks the model can track a plan, discover tools, correct invalid calls and use verified results from earlier steps. Repeated actions and no-progress loops are bounded. A runtime lease limits generation to one shell process at a time. Search and indexing yield resources while a main-shell task runs. Context size follows **Models & connections**. Cancellation stops owned processes and recovers journaled file changes.

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

`tests/agent_workflows_live.py` times the first streamed reply on a real CPU model, verifies a generated CSV against its input and checks retrieval of a fresh code from a Spanish note. Run it inside `tests/run_isolated.py` with `OLLAMA_MODELS` pointing to the installed model store and pass the path to `velora-agentd`. Add `--prewarm` to measure requests after the assistant’s shared prompt has been prepared.

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
