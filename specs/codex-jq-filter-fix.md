# Codex Backend jq Filter Fix

## Problem

The codex backend produces no useful stdout output during ralph loops. The user sees lots of JSON activity in `--verbose` mode, but nothing reaches stdout. By contrast, the claude backend always shows a result summary.

This has two root causes:

1. **Original filter was wrong** (now fixed in commit `5fc461d`): the old filter `last | .message // empty` selected the last JSONL event (`turn.completed`) and looked for `.message`, which doesn't exist.
2. **Current filter is too narrow**: the replacement filter `map(select(.item.type == "agent_message")) | last | .item.text // empty` correctly extracts `agent_message` text, but **codex frequently performs entire turns of pure tool use** (file edits, shell commands, reasoning) without ever emitting an `agent_message` event. In those cases the filter produces empty output silently.

The claude backend doesn't have this problem because Claude Code always emits a `{"type":"result","result":"..."}` event with a summary, even for tool-heavy turns.

## Actual Codex JSONL Output Format

When `codex exec --json` runs, it emits newline-delimited JSON events. The full set of event/item types:

```jsonl
{"type":"thread.started","thread_id":"..."}
{"type":"turn.started"}
{"type":"item.started","item":{"id":"item_0","type":"command_execution","command":"/bin/bash -lc ls","aggregated_output":"","exit_code":null,"status":"in_progress"}}
{"type":"item.completed","item":{"id":"item_0","type":"reasoning","text":"Let me look at the code..."}}
{"type":"item.completed","item":{"id":"item_1","type":"command_execution","command":"/bin/bash -lc cat main.py","aggregated_output":"...file contents...","exit_code":0,"status":"completed"}}
{"type":"item.completed","item":{"id":"item_2","type":"agent_message","text":"I fixed the bug in main.py"}}
{"type":"turn.completed","usage":{"input_tokens":11852,"cached_input_tokens":11776,"output_tokens":200}}
```

### Item types within `item.completed` events

| `.item.type` | Description | Key fields |
|---|---|---|
| `reasoning` | Internal chain-of-thought | `.item.text` |
| `command_execution` | Shell command that was run | `.item.command`, `.item.aggregated_output`, `.item.exit_code`, `.item.status` |
| `agent_message` | Agent's text response to the user | `.item.text` |

### Key behavioral difference from Claude

- **Claude**: Always emits a final `result` event with a text summary, even after tool-heavy turns.
- **Codex**: Only emits `agent_message` when the model explicitly decides to write a response. During build iterations where codex edits files, runs tests, and commits — it often never produces an `agent_message` at all. The turn goes: reasoning -> command_execution (repeated) -> turn.completed. This is the primary cause of the silent output.

### Edge cases

- **No `agent_message` events (common):** Codex performs a pure tool-use turn with no text response. The current filter produces empty output. This is the most common scenario during `ralph build` and is the core UX problem.
- **Multiple `agent_message` events:** The filter should take the last one. Concatenation is not needed because Ralph treats the output as a single final response, not a transcript.
- **No `item.completed` events at all:** Possible if codex errors early. The filter should produce empty output gracefully (no jq crash).

## Current Filter (Insufficient)

```bash
BACKEND_JQ_FLAGS=(-rs)
BACKEND_JQ_FILTER='map(select(.item.type == "agent_message")) | last | .item.text // empty'
```

This is syntactically correct but too narrow — it only captures `agent_message` items, which codex often doesn't emit during build turns.

## Correct Filter

```bash
BACKEND_JQ_FLAGS=(-rs)
BACKEND_JQ_FILTER='(map(select(.item.type == "agent_message")) | last | .item.text // null) // ([ .[] | select(.item.type == "command_execution" and .item.status == "completed") | "$ " + .item.command + "\n" + (.item.aggregated_output // "") ] | join("\n") | if . == "" then null else . end) // empty'
```

This implements a **fallback chain**:

1. **Primary**: extract the last `agent_message` text (same as before — when codex does provide a summary, use it)
2. **Fallback**: if no `agent_message` exists, build a transcript of completed shell commands and their output, formatted as `$ command\noutput` blocks — this gives the user visibility into what codex actually did
3. **Empty**: if neither exists (e.g. codex errored with no completed items), produce empty output gracefully

### Why a fallback transcript instead of just the last command?

During a typical codex build turn, multiple commands run (read files, edit, test, commit). Showing only the last command would hide the context. The full command transcript gives feedback comparable to what claude's result summary provides.

### Why not show `reasoning` items?

Reasoning items contain internal chain-of-thought which can be extremely verbose and not actionable. Commands and their outputs show what *happened*, which is what the user needs to assess iteration progress.

## Changes

### 1. Update `BACKEND_JQ_FILTER` in `backend_codex()` (`ralph`, line 48)

Replace the current filter with the fallback-chain filter above.

### 2. Spec correction

The multi-backend spec (`specs/multi-backend.md`, line 25) incorrectly states:

> Output is JSONL; the final result is extracted from the last event's `message` field

Update to:

> Output is JSONL; the agent's text response is extracted from `item.completed` events where `.item.type == "agent_message"`, with a fallback to command execution transcripts

## Testing

### Existing tests to update

The three existing codex jq filter tests in `test/pipeline.bats` need updating to reflect the new fallback behavior:

### 1. Codex jq filter happy path (update existing)

Keep the mock that emits an `agent_message`. Assert that the agent message text appears in output (primary path still works).

### 2. Codex jq filter with multiple agent_message events (update existing)

Keep the mock with two `agent_message` events. Assert that only the last agent message text appears (primary path takes precedence over fallback).

### 3. Codex jq filter with no agent_message events (update existing — this is the key fix)

Update the mock to emit `command_execution` items (no `agent_message`). Assert that the command transcript appears in output instead of silence. This is the test that validates the core fix.

### New tests

### 4. Codex jq filter fallback: command execution transcript

Mock codex emits reasoning + multiple command_execution items + turn.completed (no agent_message). Assert that output contains the command names and their aggregated output.

### 5. Codex jq filter: agent_message takes precedence over commands

Mock codex emits command_execution items AND an agent_message. Assert that only the agent_message text appears (not the command transcript).

### 6. Codex jq filter: completely empty turn

Mock codex emits only thread.started, turn.started, turn.completed (no items at all). Assert exit 0 with empty output.

### Unchanged

- All claude backend tests (the claude filter is independent and unaffected)
- The `pipeline failure (backend exits non-zero)` and `jq failure is reported distinctly` tests (backend-agnostic error handling)

## Regarding Codex `ERROR` Messages on stderr

The user also observes occasional errors like:

```
ERROR codex_core::tools::router: error=apply_patch verification failed: Failed to find expected lines in /workspace/IMPLEMENTATION_PLAN.md
```

These are **internal codex errors written to stderr** — they do NOT affect the ralph loop. The stderr handling (ralph lines 532-540) pipes backend stderr through to the terminal but never checks it for errors. The loop only aborts if the codex process exits non-zero (`backend_exit` check at line 543). These errors mean codex tried to apply a patch that didn't match the file contents; codex handles this internally and continues its turn. No ralph changes needed for this.

## Out of Scope

- Changes to the claude backend's jq filter (it works correctly)
- Changes to codex CLI invocation flags
- Changes to the pipeline error handling logic
- Suppressing or filtering codex stderr errors (they are harmless and informative)
