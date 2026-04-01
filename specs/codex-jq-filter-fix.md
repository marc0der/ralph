# Codex Backend jq Filter Fix

The codex backend's jq filter is broken. It produces no output because it looks for a `.message` field on the last JSONL event, but the last event (`turn.completed`) has no such field. The claude backend's filter is correct and must not be affected by this change.

## Actual Codex JSONL Output Format

When `codex exec --json` runs, it emits newline-delimited JSON events:

```jsonl
{"type":"thread.started","thread_id":"..."}
{"type":"turn.started"}
{"type":"item.completed","item":{"id":"item_0","type":"agent_message","text":"..."}}
{"type":"turn.completed","usage":{"input_tokens":...,"cached_input_tokens":...,"output_tokens":...}}
```

The agent's text response is in `item.completed` events where `.item.type == "agent_message"`. The text content is in `.item.text`. There may be multiple `item.completed` events in a turn (e.g. tool calls interleaved with messages); we take the **last** `agent_message` because it represents the agent's final response after all tool use is complete.

The `turn.completed` event is always last and contains only usage stats — no message content.

### Edge cases

- **No `agent_message` events:** If codex performs a pure tool-use turn with no text response, the filter produces empty output. This is acceptable — the loop continues to the next iteration.
- **Multiple `agent_message` events:** The filter takes the last one. Concatenation is not needed because Ralph treats the output as a single final response, not a transcript.

## Current (Broken) Filter

```bash
BACKEND_JQ_FLAGS=(-rs)
BACKEND_JQ_FILTER='last | .message // empty'
```

This selects the last JSONL event (`turn.completed`) and looks for `.message`, which doesn't exist. The `// empty` fallback produces no output silently.

## Correct Filter

```bash
BACKEND_JQ_FLAGS=(-rs)
BACKEND_JQ_FILTER='map(select(.item.type == "agent_message")) | last | .item.text // empty'
```

This:
1. Slurps all JSONL events into an array (`-s`)
2. Filters to only `item.completed` events where the item is an `agent_message`
3. Takes the last such event (the final agent response)
4. Extracts the `.item.text` field (raw text output, `-r`)

## Changes

Update `BACKEND_JQ_FILTER` in the `backend_codex()` function in `ralph` (line 47). No other code changes are needed — the claude backend's filter (`select(.type == "result") | .result // empty`) is independent and unaffected.

## Spec Correction

The multi-backend spec (`specs/multi-backend.md`, line 25) incorrectly states:

> Output is JSONL; the final result is extracted from the last event's `message` field

Update to:

> Output is JSONL; the agent's text response is extracted from `item.completed` events where `.item.type == "agent_message"`

## Testing

New tests in `test/pipeline.bats`:

### 1. Codex jq filter happy path

Create a mock `codex` that emits realistic JSONL (thread.started, turn.started, item.completed with agent_message, turn.completed). Run `ralph build -n 1 -b codex --skip-push`. Assert exit 0 and that the agent message text appears in the output.

### 2. Codex jq filter with multiple agent_message events

Mock codex emits two `item.completed` events with `type == "agent_message"` (simulating tool use interleaved with messages). Assert that only the last agent message text appears in the output.

### 3. Codex jq filter with no agent_message events

Mock codex emits only thread.started, turn.started, and turn.completed (no agent_message). Assert exit 0 with no crash — empty output is acceptable.

### 4. Claude backend still works (regression)

The existing tests (`backend stderr remains visible`, `non-verbose non-failure run produces no extra verbose output`, etc.) already exercise the claude backend's jq filter with mock `claude` binaries emitting `{"type":"result","result":"..."}`. These must all continue to pass unchanged.

### Not changed

The existing `pipeline failure (backend exits non-zero)` and `jq failure is reported distinctly` tests are backend-agnostic (they test error handling, not jq filters) and should not be modified.

## Out of Scope

- Changes to the claude backend's jq filter (it works correctly)
- Changes to codex CLI invocation flags
- Changes to the pipeline error handling logic
