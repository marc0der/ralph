# Pipeline Error Handling & Verbose Mode

The backend execution pipeline in `cmd_loop` silently exits on failure. Because the script uses `set -euo pipefail`, any error in the backend command or the jq post-processing kills the script with no ralph-level diagnostic. The user sees the loop banner, then nothing.

This spec describes two changes: always-on error handling around the pipeline, and an opt-in verbose mode for deeper diagnostics.

## 1. Pipeline Error Handling (always-on)

When the backend pipeline fails, ralph must catch the failure and report it clearly before exiting. Today the pipeline is:

```
echo "$prompt" | backend_cmd | jq ...
```

A failure anywhere in that pipeline (backend exits non-zero, jq can't parse the output, jq filter produces an error) causes an immediate silent exit.

### Requirements

- On pipeline failure, ralph prints a clear error message to stderr identifying:
  - That the backend command failed (not some other part of ralph)
  - Which iteration the failure occurred on
  - The exit code
- The error message suggests `--dry-run` and `--verbose` as next steps for debugging
- Backend stderr must remain visible to the user (not swallowed or redirected)
- A jq parse failure is distinguishable from a backend failure (they have different causes and different fixes)
- On success, behaviour is unchanged from today

### Non-requirements

- No retries or automatic recovery. Fail fast, fail clearly.
- No changes to the jq filters themselves.

## 2. Verbose Mode (`-v` / `--verbose`)

A new flag for `plan` and `build` that increases diagnostic output. This is for humans debugging a misbehaving run, not for normal operation.

### Flag

`-v` / `--verbose` — accepted alongside existing flags. Not mutually exclusive with `--dry-run` (though combining them is low-value, it should not error).

### Behaviour when `--verbose` is set

- **Before each iteration**: print the exact backend command that will be executed (the full argv, not a summary). This is similar to dry-run's "Would run:" line but the command actually executes.
- **Backend stderr**: backend stderr is already visible today, but verbose mode should label it clearly so it isn't confused with ralph's own output (e.g. prefix or section header).
- **Backend stdout (raw)**: display the raw backend output before jq processing. This helps diagnose jq filter mismatches (backend produced valid JSON, but the filter didn't extract what was expected).
- **After each iteration**: print the exit codes of both the backend command and jq separately, regardless of success or failure.
- **Push output**: when git push runs, show its output (today it is captured and only shown on failure).

### Behaviour when `--verbose` is not set

No change from current behaviour (plus the always-on error handling from section 1).

## Usage Text

The help output gains:

```
  -v, --verbose        Show backend commands, raw output, and exit codes
```

Listed alongside the existing `--dry-run` flag.

## Testing

All tests use `--dry-run` or mock commands — no real backend CLIs required.

- `--verbose` flag is accepted without error
- `--verbose` output includes the backend command line
- `--verbose` output includes exit codes after each iteration
- `-v` is accepted as shorthand for `--verbose`
- Existing dry-run and validation tests continue to pass
- Pipeline failure produces a ralph-level error message naming the iteration and exit code
- Pipeline failure error message suggests `--verbose` and `--dry-run`
- jq failure is reported distinctly from backend failure

## Out of Scope

- Log-to-file or structured logging
- Changes to the backend definitions or jq filters
- Coloured output or progress spinners
- Verbosity levels (single level is sufficient)
