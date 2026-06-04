# Copilot Backend

Ralph supports `claude` and `codex` backends (see `multi-backend.md`). This spec adds GitHub Copilot CLI (`@github/copilot`) as a third backend, selectable via `-b copilot` / `--backend copilot`.

## Supported Backends

Extends the list in `multi-backend.md`:

### Copilot

- CLI binary: `copilot` (distributed as the `@github/copilot` npm package)
- Default model: the latest Claude Opus available via Copilot CLI's model registry
- Runs non-interactively via `copilot -p <prompt>` with `--output-format=json`, `--yolo` (Copilot CLI's catch-all "skip every approval" flag; required when running programmatically, since the JSON stream has no way to answer approval prompts), and `--model <model>`
- The prompt is passed as the value of `-p` / `--prompt`, not via stdin
- Output is JSONL (one JSON object per line)

## Output Schema

Every event in the Copilot CLI's JSONL stream shares the envelope:

```json
{
  "id": "<uuid>",
  "timestamp": "<ISO 8601>",
  "parentId": "<uuid|null>",
  "ephemeral": false,
  "type": "<event-type>",
  "data": { ... }
}
```

The final assistant text response is the `data.content` of the last event whose `type == "assistant.message"`:

```json
{
  "type": "assistant.message",
  "data": {
    "messageId": "...",
    "content": "the assistant's text response",
    "toolRequests": [ ... ],
    "outputTokens": 123,
    "phase": "response"
  }
}
```

A single run may emit multiple `assistant.message` events when tool calls are interleaved; the final one is the response that would have been printed to the user.

When no `assistant.message` event is present (e.g. the run aborted after tool calls), ralph falls back to a transcript of completed `tool.execution_complete` events (events where `data.success == true`), using `data.result.content` (or `data.result.detailedContent` if `content` is absent) as the per-tool text. This parallels the codex fallback.

Other event types ralph should ignore for response extraction (non-exhaustive): `assistant.turn_start`, `assistant.turn_end`, `assistant.message_delta`, `assistant.reasoning`, `assistant.reasoning_delta`, `assistant.usage`, `tool.execution_start`, `session.idle`, `session.shutdown`, `session.error`, `user.message`, `system.message`, `permission.requested` (this last one should never fire when `--yolo` is set).

## Authentication

Copilot CLI authenticates against GitHub. There are two host-side mechanisms it recognises, in order of preference:

1. **`gh` CLI credentials** — Copilot CLI reuses the GitHub auth established by `gh auth login`, stored under `~/.config/gh/`.
2. **`GH_TOKEN` / `GITHUB_TOKEN` environment variables** — Used as a fallback when no interactive `gh` login is available (e.g. CI-style flows).

Copilot CLI also stores its own configuration, session state, and logs under `~/.copilot/` on the host (`auth.json`, sessions, logs, etc.). This directory is independent of `gh` credentials but is what `copilot login` writes if the user authenticates via Copilot CLI directly rather than via `gh`.

## Behaviour

### plan and build commands

- Accept `-b copilot` / `--backend copilot` like the existing backends
- The default model when `-b copilot` is set is the latest Claude Opus available via Copilot (overridable with `-m`)
- The loop header displays `copilot` as the active backend name
- The permission warning outside a devcontainer reflects Copilot's permission flag
- If `copilot` is not in `PATH`, ralph exits with an error naming the missing binary
- Dry-run output identifies the copilot backend and the model it would use

### Sandbox

The devcontainer must provide everything Copilot CLI needs to run without manual setup:

- The `@github/copilot` npm package is pre-installed inside the container, alongside the existing claude and codex CLIs
- `~/.copilot` on the host is mounted into the container *if it exists*, using the same optional-mount pattern already used for `~/.codex`, `~/.ssh`, and `~/.config/gh` (static bind mounts of a non-existent host path break or get auto-created as root). The sandbox command should `mkdir -p ~/.copilot` on the host before launching, so a session inside the container can run `copilot login` and persist credentials back to the host — mirroring how `~/.claude` and `~/.codex` are handled.
- If Copilot CLI exposes an environment variable to relocate its config directory (analogous to `CODEX_HOME` / `CLAUDE_CONFIG_DIR`), set it inside the container to point at the mounted location. If no such variable exists, the default `~/.copilot` location inside the container is used.
- The existing `~/.config/gh` mount continues to provide `gh auth` credentials; no separate mount is required for GitHub auth.
- `GH_TOKEN` and `GITHUB_TOKEN` are forwarded into the container when set on the host, using the same `--remote-env` mechanism already used for `SSH_AUTH_SOCK` and `OPENAI_API_KEY`.

### Prompt templates

The prompts under `prompts/plan.md` and `prompts/build.md` are already backend-agnostic and reference both `AGENTS.md` and `CLAUDE.md`. No prompt template changes are expected for this spec. Copilot honours `AGENTS.md` / `CLAUDE.md` via the existing prompt content.

### Usage text

- The supported-backend list shown in the `-b` / `--backend` flag description includes `copilot`
- Errors that enumerate supported backends include `copilot`

## Documentation

### README

- The `-b, --backend` row in the options table mentions `copilot` alongside `claude` and `codex`
- The default-model section lists the copilot default
- The sandbox section notes that Copilot CLI is pre-installed, `~/.copilot` is mounted conditionally, and `GH_TOKEN` / `GITHUB_TOKEN` are forwarded
- The troubleshooting section has an entry for "copilot CLI not found", parallel to the claude and codex entries
- At least one example uses `-b copilot` (e.g. `ralph build -b copilot -n 10`)

### CLAUDE.md

- The "What is Ralph?" line names GitHub Copilot CLI alongside Claude Code and OpenAI Codex
- No other CLAUDE.md changes are expected; the generic backend flow already covers copilot

## Testing

All tests use `--dry-run` and do not require the Copilot CLI to actually run.

- `-b copilot` selects the copilot backend
- Unknown-backend errors list `copilot` in the supported set
- Dry-run output reflects the copilot backend and its default model
- The CLI-not-found check fires with `copilot` as the missing binary when `-b copilot` is used and `copilot` is not in PATH
- Existing claude, codex, dry-run, and validation tests continue to pass
- Sandbox-side behaviour exercised by existing tests continues to work: the `~/.copilot` mount is skipped gracefully when the host directory does not exist, and `GH_TOKEN` / `GITHUB_TOKEN` are forwarded when set

## Out of Scope

- Additional backends beyond claude, codex, and copilot
- Auto-detection of installed backends
- `copilot login` / OAuth browser flow inside the container (users authenticate on the host)
- Streaming-delta or reasoning-event surfacing (ralph consumes only the final `assistant.message` content, with the `tool.execution_complete` fallback)
- Changes to base devcontainer image semantics beyond adding the Copilot CLI install
