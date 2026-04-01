# Multi-Backend Support

Ralph currently only works with Claude Code. This spec describes support for multiple AI coding agent backends, starting with Claude and OpenAI Codex.

## Backend Selection

Ralph defaults to the `claude` backend. Users can override this with the `-b` / `--backend` CLI flag.

There is no auto-detection. If an unrecognised backend name is given, ralph exits with an error listing the supported backends.

## Supported Backends

### Claude

- CLI binary: `claude`
- Default model: `opus`
- Runs in headless pipe mode with `--dangerously-skip-permissions`, `--output-format=stream-json`, and `--verbose`
- Output is a JSON stream; the final result is extracted from the `type == "result"` event

### Codex

- CLI binary: `codex`
- Default model: `gpt-5.2-codex`
- Runs via `codex exec` with `--json` and `--dangerously-bypass-approvals-and-sandbox`
- Output is JSONL; the agent's text response is extracted from `item.completed` events where `.item.type == "agent_message"`; if none exist, the fallback is a transcript of completed `command_execution` items formatted as `$ command\noutput`

## Behaviour

### plan and build commands

- Accept a new `-b` / `--backend` option alongside existing flags
- The default model depends on the selected backend (not hardcoded to `opus`)
- The loop header displays the active backend name
- The permission warning outside a devcontainer is backend-appropriate
- If the backend's CLI binary is not in PATH, ralph exits with an error naming the missing binary
- Dry-run output identifies which backend and model would be used

### Prompt templates

The prompts (`prompts/plan.md` and `prompts/build.md`) should be backend-agnostic. Claude-specific references (Sonnet/Opus subagents, `/commit` skill) are replaced with generic language. A `{{BACKEND_HINTS}}` placeholder is injected at runtime with backend-specific guidance so each backend gets relevant advice without duplicating the entire prompt.

References to `CLAUDE.md` become `AGENTS.md` or `CLAUDE.md` (check for either).

### usage text

- The tagline reflects that ralph supports multiple backends, not just Claude
- The `-b` / `--backend` option is documented
- The model option description does not reference Claude specifically

### Extensibility

Adding a new backend should not require changes outside the backend definitions themselves and the list of supported backends.

## Testing

All backend-related tests use `--dry-run` mode so they don't require actual backend CLIs installed.

- Default backend is `claude` when `-b` flag is not set
- `-b` flag selects the backend
- Unknown backend name produces an error with the list of supported backends
- Dry-run output reflects the selected backend and its default model
- Existing dry-run and validation tests continue to pass
- The CLI-not-found test checks for the resolved backend's binary name

## Out of Scope

- Container/Dockerfile changes
- README.md and CLAUDE.md updates
- Additional backends beyond Claude and Codex
- Auto-detection of installed backends
