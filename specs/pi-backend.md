# Pi Backend

Ralph supports `claude`, `codex`, and `copilot` backends (see `multi-backend.md`, `copilot-backend.md`). This spec adds pi (`@earendil-works/pi-coding-agent`) as a fourth backend, selectable via `-b pi` / `--backend pi`.

## Supported Backends

Extends the list in `multi-backend.md`:

### Pi

- CLI binary: `pi` (distributed as the `@earendil-works/pi-coding-agent` npm package)
- Default model: `anthropic/claude-opus-4-8` (the latest Claude Opus in pi's model registry at the time of writing). This is a hardcoded `BACKEND_DEFAULT_MODEL`; bump it when pi ships a newer Opus
- Runs non-interactively via `pi -p --mode json --model <model>`
- The prompt is piped via stdin; in print mode pi merges piped stdin into the initial prompt
- Output is JSONL (one JSON event per line)

## Output Schema

The first line of every run is a session header:

```json
{ "type": "session", "version": 3, "id": "<uuid>", "timestamp": "<ISO 8601>", "cwd": "<path>" }
```

Subsequent lines are typed agent events. Ralph extracts everything it needs from a single event, `agent_end`:

`agent_end` is the terminal event for the run. Auto-retry can emit more than one `agent_end` (an interim one with `willRetry == true` followed by the real terminal event), so ralph always consumes the **last** `agent_end` line. Its `messages` field holds the full conversation, where `role` is one of `user`, `assistant`, or `toolResult`. The last entry with `role == "assistant"` is the final response; its `content` array can mix `type == "text"`, `type == "thinking"`, and `type == "toolCall"` items, and ralph keeps only the `text` ones:

```json
{
  "type": "agent_end",
  "messages": [
    { "role": "user", "content": [ { "type": "text", "text": "..." } ] },
    { "role": "assistant", "content": [ { "type": "toolCall", "id": "...", "name": "bash", "arguments": { "command": "ls" } } ] },
    { "role": "toolResult", "toolCallId": "...", "toolName": "bash", "content": [ { "type": "text", "text": "file output" } ], "isError": false },
    { "role": "assistant", "content": [ { "type": "thinking", "thinking": "..." }, { "type": "text", "text": "the assistant's text response" } ] }
  ],
  "willRetry": false
}
```

The final assistant text is extracted from the **last** `agent_end` event: its last `role == "assistant"` message, concatenating the `text` field of every `type == "text"` content item.

When no assistant text is present (e.g. the run ended after tool calls only), ralph falls back to a transcript reconstructed from `agent_end.messages`, which already holds the whole conversation. For each `role == "toolResult"` message with `isError == false`, ralph concatenates the `text` of its `content` items; for the `bash` tool the line is prefixed with `$ <command>`, taking the command from the matching assistant `toolCall` content item (`arguments.command`, matched by `toolCallId`). This parallels the codex and copilot fallbacks, but reads from `agent_end.messages` rather than the standalone `tool_execution_end` events — those events carry neither the tool `args` nor a `stdout` field (their `result` has the shape `{ "content": [ { "type": "text", "text": "..." } ] }`).

Other event types ralph ignores for response extraction (non-exhaustive): `agent_start`, `turn_start`, `turn_end`, `message_start`, `message_update`, `message_end`, `tool_execution_start`, `tool_execution_update`, `tool_execution_end`, `queue_update`, `compaction_start`, `compaction_end`, `auto_retry_start`, `auto_retry_end`.

Because both stages need to scan every line, ralph slurps the JSONL stream with `jq -rs` (like the codex and copilot backends) and applies a two-stage filter: the primary stage selects the **last** `agent_end`, takes its last `role == "assistant"` message, and joins the `text` of each `type == "text"` content item; when that yields no text, the fallback stage builds the `agent_end.messages` transcript described above. The filter emits the empty string when neither stage produces output, so an empty run behaves like the other backends.

## Authentication

Pi supports two host-side mechanisms, in order of preference:

1. **Subscription / API-key login via `/login`** — Credentials are stored in `~/.pi/agent/auth.json` and auto-refreshed. A Claude Pro/Max login writes an OAuth credential (`{ "type": "oauth", ... }`) to that file, not an environment variable; this is the path the sandbox relies on (via the mounted `~/.pi`). Built-in subscription logins include Claude Pro/Max, ChatGPT Plus/Pro, and GitHub Copilot.
2. **Provider API-key environment variables** — `ANTHROPIC_API_KEY`, `ANTHROPIC_OAUTH_TOKEN`, `OPENAI_API_KEY`, `GEMINI_API_KEY`, `OPENROUTER_API_KEY`, and many others are honoured as a fallback when no `/login` credential is present.

Pi stores its configuration, sessions, and logs under `~/.pi/agent/` on the host. The location is overridable via `PI_CODING_AGENT_DIR`.

## Permissions

Pi has no permission flag. By design it does not implement permission popups: the built-in tools (`read`, `bash`, `edit`, `write`, `grep`, `find`, `ls`) are enabled without prompting. The `BACKEND_PERMISSION_FLAG` slot for this backend is therefore empty, and `build_backend_cmd` does not add any permission-related argument to the pi invocation. Ralph still emits the unrestricted-tools warning outside a devcontainer, parallel to the other backends.

## Behaviour

### plan and build commands

- Accept `-b pi` / `--backend pi` like the existing backends
- The default model when `-b pi` is set is `anthropic/claude-opus-4-8` (overridable with `-m`). The default must use the fully-qualified `provider/id` form: pi's default provider is `google`, so a bare `opus` would be resolved against the wrong provider. Users may still pass shorthand or thinking-level patterns via `-m` (e.g. `sonnet`, `opus:high`, `anthropic/claude-opus-4-8:high`)
- The loop header displays `pi` as the active backend name
- The permission warning outside a devcontainer still fires; like the other backends it warns about unrestricted tool access (file writes, shell commands, etc.), but since pi has no permission flag the text does not reference one
- If `pi` is not in `PATH`, ralph exits with an error naming the missing binary
- Dry-run output identifies the pi backend and the model it would use
- Each iteration is a fresh ephemeral run: ralph passes `--no-session` so pi does not write session files for ralph-driven iterations

### Sandbox

The devcontainer must provide everything pi needs to run without manual setup:

- The `@earendil-works/pi-coding-agent` npm package is pre-installed inside the container, alongside the existing claude, codex, and copilot CLIs
- `~/.pi` on the host is mounted into the container *if it exists*, using the same optional-mount pattern already used for `~/.codex`, `~/.copilot`, `~/.ssh`, and `~/.config/gh`. The sandbox command should `mkdir -p ~/.pi/agent` on the host before launching, so a session inside the container can run `/login` and persist credentials back to the host — mirroring how `~/.claude`, `~/.codex`, and `~/.copilot` are handled.
- `PI_CODING_AGENT_DIR` is set inside the container to `/home/node/.pi/agent` (the mounted location), analogous to `CLAUDE_CONFIG_DIR` and `CODEX_HOME`.
- The Dockerfile pre-creates `/home/node/.pi` and `chown`s it to `node:node` in the same `mkdir`/`chown` line that already covers `/home/node/.codex` and `/home/node/.copilot`, so the bind mount lands on a node-owned directory with correct UID mapping.
- Of the env vars ralph already forwards, pi honours `OPENAI_API_KEY`, `OPENROUTER_API_KEY`, and `ANTHROPIC_API_KEY` as API-key fallbacks. It does **not** read `ANTHROPIC_AUTH_TOKEN` (pi has no such variable) or `ANTHROPIC_BASE_URL` (pi only consults that for its cloudflare provider, not the standard anthropic provider); both stay forwarded for the other backends but have no effect on pi. For pi the primary credential is the mounted `~/.pi/agent/auth.json` written by `/login` (see Authentication), so the common Claude Pro/Max flow needs no env-var forwarding.
- `GEMINI_API_KEY` is forwarded into the container when set on the host, using the same `--remote-env` mechanism — pi's default provider is google, so this is the most commonly missing key from the current forwarding list.

### Prompt templates

The prompts under `prompts/plan.md` and `prompts/build.md` are already backend-agnostic and reference both `AGENTS.md` and `CLAUDE.md`. No prompt template changes are expected for this spec. Pi loads `AGENTS.md` and `CLAUDE.md` automatically from the working directory and its parents.

### Usage text

- The supported-backend list shown in the `-b` / `--backend` flag description includes `pi`
- Errors that enumerate supported backends include `pi`

## Documentation

### README

- The `-b, --backend` row in the options table mentions `pi` alongside `claude`, `codex`, and `copilot`
- The default-model section lists pi's default
- The sandbox section notes that pi is pre-installed, `~/.pi` is mounted conditionally, `PI_CODING_AGENT_DIR` is set inside the container, and `GEMINI_API_KEY` is forwarded
- The troubleshooting section has an entry for "pi CLI not found", parallel to the claude, codex, and copilot entries
- At least one example uses `-b pi` (e.g. `ralph build -b pi -n 10`)

### CLAUDE.md

- The "What is Ralph?" line names pi alongside Claude Code, OpenAI Codex, and GitHub Copilot CLI
- No other CLAUDE.md changes are expected; the generic backend flow already covers pi

## Testing

All tests use `--dry-run` and do not require pi to actually run.

- `-b pi` selects the pi backend
- Unknown-backend errors list `pi` in the supported set
- Dry-run output reflects the pi backend and its default model
- The CLI-not-found check fires with `pi` as the missing binary when `-b pi` is used and `pi` is not in `PATH`
- Existing claude, codex, copilot, dry-run, and validation tests continue to pass
- Sandbox-side behaviour exercised by existing tests continues to work: the `~/.pi` mount is skipped gracefully when the host directory does not exist, and `GEMINI_API_KEY` is forwarded when set

## Out of Scope

- Additional backends beyond claude, codex, copilot, and pi
- Auto-detection of installed backends
- `/login` / OAuth browser flow inside the container (users authenticate on the host or set API-key env vars)
- Streaming-delta, reasoning, queue, compaction, or auto-retry event surfacing (ralph consumes only the final assistant text, with the `agent_end.messages` fallback)
- Configuring pi extensions, skills, prompt templates, themes, or tool allowlists from ralph (pi loads them from its own discovery paths)
- Resuming or continuing pi sessions between iterations (each iteration is a fresh ephemeral run)
- Forwarding the long tail of provider-specific env vars pi supports beyond those already forwarded plus `GEMINI_API_KEY`
- Changes to base devcontainer image semantics beyond adding pi and its config plumbing
