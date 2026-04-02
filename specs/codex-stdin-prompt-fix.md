# Codex Backend Prompt Delivery Fix

The codex backend fails at runtime with `write_stdin failed: Unknown process id 0` because ralph pipes the prompt via stdin, but `codex exec` expects the prompt as a positional CLI argument. The claude backend is unaffected because `claude -p` explicitly reads from stdin.

## Problem

Ralph's `cmd_loop` delivers the prompt to every backend the same way — via stdin pipe:

```bash
backend_output=$(echo "$prompt" | "${BACKEND_CMD[@]}" ...) || backend_exit=$?
```

This works for `claude -p`, which reads the prompt from stdin by design. It does not work for `codex exec`, which expects:

```
codex exec [flags] "the prompt text"
```

When Codex receives piped stdin data it did not ask for, its internal tool router interprets it as input destined for a subprocess. No subprocess has been registered yet (process id 0), so Codex errors:

```
codex_core::tools::router: error=write_stdin failed: Unknown process id 0
```

This was not caught earlier because the codex backend was only exercised via `--dry-run`, which prints the command without executing it.

## Fix

Introduce a per-backend variable `BACKEND_STDIN_PROMPT` that declares how the prompt is delivered to the backend CLI:

- `true` — pipe the prompt via stdin (current behaviour, correct for claude)
- `false` — pass the prompt as a trailing positional argument (required for codex)

### Backend definitions

In `backend_claude()`:

```bash
BACKEND_STDIN_PROMPT=true
```

In `backend_codex()`:

```bash
BACKEND_STDIN_PROMPT=false
```

### Execution in `cmd_loop`

The backend invocation block (currently a single pipeline) becomes a conditional:

```bash
if [[ "$BACKEND_STDIN_PROMPT" == true ]]; then
    backend_output=$(echo "$prompt" | "${BACKEND_CMD[@]}" 2> >(...)) || backend_exit=$?
else
    backend_output=$("${BACKEND_CMD[@]}" "$prompt" 2> >(...)) || backend_exit=$?
fi
```

The stderr handling (verbose labelling, passthrough) is identical in both branches. The only difference is whether the prompt arrives via stdin or as the last argument.

### Dry-run output

The dry-run block should also reflect the delivery mechanism. Today it prints:

```
[dry-run] Would run: ${BACKEND_CMD[*]}
```

When `BACKEND_STDIN_PROMPT` is `false`, the prompt is part of the command line, so dry-run should show it:

```
[dry-run] Would run: ${BACKEND_CMD[*]} "<prompt>"
```

When `BACKEND_STDIN_PROMPT` is `true`, the prompt is piped, so the current representation is correct. The dry-run block already prints the prompt content separately ("Prompt content ..."), so this is purely about accurately representing the invocation.

### Verbose output

The verbose "Backend command" line before execution should also include the prompt argument when `BACKEND_STDIN_PROMPT` is `false`, for the same accuracy reason:

```
[verbose] Backend command: codex exec --dangerously-bypass-approvals-and-sandbox --json --model gpt-5.2-codex "<prompt>"
```

For `BACKEND_STDIN_PROMPT=true`, the prompt does not appear in the command line (it is piped), so the current output is correct.

In both cases, the prompt content is truncated in the verbose line if it exceeds 200 characters (append `...`), since the full prompt is already displayed by `--dry-run` and would overwhelm verbose output.

## Extensibility

The `BACKEND_STDIN_PROMPT` variable follows the existing pattern of per-backend well-known variables (`BACKEND_CLI`, `BACKEND_DEFAULT_MODEL`, `BACKEND_JQ_FLAGS`, etc.). Any future backend sets this variable in its `backend_<name>()` function. No changes to `cmd_loop` are needed to add a new backend — the conditional already handles both delivery modes.

## Argument length limits

Passing the prompt as a CLI argument is subject to the OS argument length limit (`ARG_MAX`). On Linux this is typically 2 MB+; on macOS it is 1 MB+. Ralph's prompt templates are well under these limits. If a future prompt approaches this limit, the fix is to make that backend accept stdin (i.e. set `BACKEND_STDIN_PROMPT=true` and adjust the CLI flags), not to add chunking or tempfile indirection.

## Testing

All tests use `--dry-run` or mock commands — no real backend CLIs required.

### New tests

- **Codex dry-run shows prompt as positional argument**: Run `ralph plan -n 1 -b codex --dry-run` and assert the dry-run output includes the prompt text as part of the "Would run:" line (not separately piped).
- **Claude dry-run does not show prompt in command line**: Run `ralph plan -n 1 --dry-run` and assert the "Would run:" line does not contain prompt text (prompt is piped, shown separately).
- **Codex mock execution receives prompt as argument**: Create a mock `codex` script that writes `$@` (its arguments) to a file, run `ralph plan -n 1 -b codex --skip-push`, and assert the captured arguments include the prompt text as the last argument.
- **Claude mock execution receives prompt on stdin**: Create a mock `claude` script that writes stdin to a file, run `ralph plan -n 1 --skip-push`, and assert the captured stdin contains the prompt text.

### Existing tests

All existing tests continue to pass. The claude backend's execution path is unchanged (it still pipes via stdin). The codex backend's `--dry-run` tests may need minor updates to reflect the new "Would run:" format that includes the prompt argument.

## Out of Scope

- Changes to the jq filters or backend CLI flags
- Changes to the pipeline error handling logic
- Support for tempfile-based prompt delivery (not needed given current prompt sizes)
- Changes to the claude backend's stdin-based delivery (it works correctly)
