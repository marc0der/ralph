# Live Backend Streaming in Verbose Mode

The `plan` and `build` loops report no backend activity while an iteration runs. A real iteration lasts tens of minutes, so the user sees the iteration banner, then silence, then a single block of summary text when the iteration ends. The backends are not at fault: `claude` and `pi` both emit line-buffered JSON events in real time. Ralph discards that timing by capturing the whole stream before it parses anything.

This spec adds live per-event rendering to the loop, gated on the existing `-v` / `--verbose` flag. Without `--verbose`, output stays byte-identical to today.

## Problem

### Command substitution blocks all output

`cmd_loop` captures the backend with command substitution (`ralph:986-1007`):

```bash
backend_output=$(echo "$prompt" | "${BACKEND_CMD[@]}" 2> >(
    ...
)) || backend_exit=$?
```

Bash blocks on `$(...)` until the process exits, so no backend stdout can reach the terminal while the iteration runs. The captured text is then parsed once and printed as one block (`ralph:1025-1039`):

```bash
jq_output=$(echo "$backend_output" | jq "${BACKEND_JQ_FLAGS[@]}" "$BACKEND_JQ_FILTER")
echo "$jq_output"
```

Backend stderr does stream, because it is routed through process substitution rather than captured. That is why a run is not completely silent, but stderr carries startup notices and warnings, not the agent's actions.

### Verbose mode does not help

`--verbose` already promises "raw output", but it prints the raw stream only after the backend has exited (`ralph:1016-1019`):

```bash
if $verbose; then
    echo "[verbose] Raw backend output:" >&2
    echo "$backend_output" >&2
fi
```

So verbose mode adds volume, not immediacy. It cannot be used to watch a run in progress.

### The backends already stream

Both verified backends emit one JSON object per line as work happens. Rendering a live `pi` stream through a candidate filter, with each output line timestamped as it arrived:

```
12:25:38   ---                            (turn_start)
12:25:40   → bash ls -la                  (tool_execution_start)
12:25:40   → bash wc -l *.txt             (tool_execution_start)
12:25:43   The directory contains 5 files with three .txt files…
```

The same for `claude --output-format=stream-json`:

```
12:26:46   → Bash ls -la                  (assistant / tool_use)
12:26:49   There are **7 files** in the current directory…
12:26:49   [result] success · 6s          (result)
```

Event names observed:

- `pi --mode json` — `session`, `agent_start`, `turn_start`, `message_start`, `message_update`, `message_end`, `tool_execution_start`, `tool_execution_update`, `tool_execution_end`, `turn_end`, `agent_end`, `agent_settled`
- `claude --output-format=stream-json` — `system`, `assistant`, `user`, `result`, `rate_limit_event`

`pi` is noisy: a single trivial task produced about 40 events, including eight near-identical `message_update` usage snapshots per assistant message. A live renderer must select events, not echo them.

## Fix

Write the backend stream to a file instead of a shell variable. Under `--verbose`, tee that stream through a per-backend jq filter that renders one short line per interesting event. Without `--verbose`, redirect straight to the file and keep today's behaviour.

### 1. Collapse prompt delivery into a helper

`BACKEND_STDIN_PROMPT` currently forces two near-identical copies of the invocation, each with its own stderr handler (`ralph:988-1007`). Gating live output on `--verbose` would make four. Extract the delivery choice first:

```bash
# Deliver the prompt the way the backend expects and stream stdout to our caller.
run_backend() {
    if [[ "$BACKEND_STDIN_PROMPT" == "true" ]]; then
        printf '%s\n' "$prompt" | "${BACKEND_CMD[@]}"
    else
        "${BACKEND_CMD[@]}" "$prompt"
    fi
}
```

The result is two branches, one per verbosity, instead of today's two per delivery mode. The duplicated stderr handler collapses into a single `stderr_handler` helper used by both.

`printf '%s\n'` deliberately replaces the `echo "$prompt"` at `ralph:989`. This is an intentional in-scope fix, not a slip of the refactor: `echo` consumes a prompt that begins with `-n` or `-e` as its own options, so the bytes the backend reads are not the bytes of the prompt. The Out of Scope entry on prompt streaming concerns *how* the prompt is delivered, not this one-word correctness fix.

`stderr_handler` must write exclusively to fd 2, and never to stdout. Its contract is load-bearing rather than cosmetic: `2> >(stderr_handler)` inherits the pipeline's stdout, which under section 3 is the pipe into `tee`. A handler line without `>&2` — a section header, for instance — therefore lands in `$raw_file`, and the non-slurping claude summary filter (`ralph:29`) then parse-errors on it and the iteration dies. Today's inline handlers hold the invariant only by accident, because every one of their lines happens to use `>&2` (`ralph:991-995`, `ralph:1001-1005`).

### 2. Route the stream through a file

Both paths must leave the complete raw stream at `$raw_file`. The final summary filter then reads that file:

```bash
jq_output=$(jq "${BACKEND_JQ_FLAGS[@]}" "$BACKEND_JQ_FILTER" "$raw_file")
```

`$backend_output` is removed. Metrics no longer writes the raw file itself (`ralph:1061-1062`); it consumes the file the loop already produced. All four `BACKEND_JQ_FILTER` values work unchanged on a file, including the three that slurp with `-rs`.

`$raw_file` becomes load-bearing on both paths, so it must exist even when metrics are off:

- Metrics enabled — keep the current path, `$metrics_dir/iter-NNN.stream.jsonl`, so the stream is retained for later analysis, as documented in `README.md`.
- Metrics disabled (`--no-metrics`, or a metrics directory that could not be created) — use one temp file for the whole run: `mktemp` it once before the iteration loop, truncate it with `>` at the start of each iteration, and remove it in a single `EXIT` trap. One file and one trap, registered once, so nothing is orphaned and the trap does not accumulate per iteration.

The `EXIT` trap is new. It sits alongside the `SIGINT`/`SIGTERM` trap already installed in `cmd_loop` (`ralph:929`) rather than replacing it, because that trap exits 130 and must keep doing so. A failing `mktemp` must not abort the run under `set -euo pipefail` (`ralph:2`); it degrades to the same non-fatal fallback the write-failure rule below requires.

A write failure must never abort the iteration. Today metrics writes the raw file under an explicit contract — `printf ... > "$raw_file" 2>/dev/null || true` (`ralph:1062`), documented at `ralph:606` as "A failure here never interrupts the loop". Promoting the file to the summary filter's only input must not repeal that:

- Before invoking the backend, confirm `$raw_file` is writable. If it is not, fall back to a temp file. If that also fails, fall back to today's command-substitution capture into a variable for that iteration.
- A missing or empty `$raw_file` after the backend exits produces its own warning, naming the file. It must not reuse the backend-failure path (`ralph:1009-1013`) or the jq-failure path (`ralph:1025-1039`), because neither failure occurred.

A full disk or a read-only `.ralph/metrics` therefore degrades one iteration's reporting. It never kills a 50-iteration run.

### 3. Live rendering, verbose only

```bash
run_backend 2> >(stderr_handler) \
    | tee "$raw_file" \
    | { jq -rR --unbuffered "$JQ_LIVE_PRELUDE fromjson? // empty | $BACKEND_JQ_LIVE" >&2 2>/dev/null \
        || cat >/dev/null; }
```

Live lines go to stderr, like every other `[verbose]` diagnostic in the loop (`ralph:975`, `981`, `991`, `1018`, `1035`, `1093`). This keeps the current property that `--verbose` adds nothing to stdout, so `ralph build --verbose 2>/dev/null` still yields exactly the iteration summaries. Stdout stays reserved for the summary filter's output.

Five details are mandatory:

- **`--unbuffered`** — without it jq buffers about 64 KB and the output arrives in batches, which defeats the whole change.
- **`-R` with `fromjson?`** — jq aborts on the first parse error in normal mode. Reading raw lines and discarding those that do not parse keeps the renderer alive when a backend writes a non-JSON line to stdout.
- **`2>/dev/null`** — jq's own diagnostics would otherwise interleave with the rendered output.
- **`|| cat >/dev/null`** — if jq dies for any other reason, this keeps draining the pipe. See section 4 for why that matters.
- **`>&2`** — the renderer inherits the pipeline's stdout, so without it the live lines join the summary on stdout. It must precede `2>/dev/null`. Reversed, `>&2` duplicates a descriptor already pointed at `/dev/null` and every rendered line is lost.

### 4. A dying renderer must not kill the run

Putting jq directly in the pipeline makes the live renderer able to destroy the iteration. When jq aborts, `tee` receives SIGPIPE and dies, and the backend dies with it. Feeding a stream whose first line is not JSON, followed by nine valid events:

```
naive     (jq bare in pipeline)          raw file: 1 line,  last = "GARBAGE NOT JSON"
hardened  (-R fromjson? + || cat)        raw file: 10 lines, last = {"msg":"FINAL EVENT"}
```

The naive form lost nine of ten events, the metrics record, and the agent's remaining work. The hardened form skipped the bad line, rendered every later event, and left the raw stream complete. Only the hardened form is acceptable.

This failure mode is the reason for gating on `--verbose`: the non-verbose path is a plain redirect with no consumer that can fail, so a renderer defect can only affect runs that opted in.

### 5. Capture the exit code from `PIPESTATUS`, not after `|| true`

`|| true` silently discards the pipeline's status, because `true` is itself a pipeline and overwrites `PIPESTATUS`. Measured against a backend that exits 42:

```
cmd | tee | jq ... || true ; ${PIPESTATUS[0]}     →  0     WRONG
set +e; cmd | tee | jq ... ; st=("${PIPESTATUS[@]}")  →  42
if cmd | tee | jq ...; then :; fi ; ${PIPESTATUS[0]}  →  42
```

The loop must use the array-capture form, which also works for the non-pipeline branch:

```bash
local backend_exit=0 st=()
set +e
if $verbose && [[ -n "${BACKEND_JQ_LIVE:-}" ]]; then
    run_backend 2> >(stderr_handler) | tee "$raw_file" | { jq ... || cat >/dev/null; }
else
    run_backend 2> >(stderr_handler) > "$raw_file"
fi
st=("${PIPESTATUS[@]}")
set -e
backend_exit=${st[0]}
```

Verified: the verbose branch yields `(42 0 0)` and the plain branch `(42)`, so `${st[0]}` is the backend's status in both cases. The existing error handling at `ralph:1009-1013` is unchanged and keeps reporting the iteration and exit code.

### 6. `BACKEND_JQ_LIVE`

A new per-backend variable, following `BACKEND_JQ_FILTER` and the rest of the well-known set. Its contract:

- It receives one decoded event per invocation.
- It emits zero or more strings, each a single short line for the user.
- It must never assume a field exists. Unknown or uninteresting events produce `empty`. Every filter is checked against this contract before it ships, arithmetic included: a bare `.duration_ms / 1000` raises on a null field, and `2>/dev/null` then hides the reason the line vanished.
- It renders progress only. Metrics, totals and the iteration summary stay where they are.

A shared prelude, prepended by `cmd_loop`, keeps the filters short:

```bash
JQ_LIVE_PRELUDE='
def trim($n): if (. | length) > $n then .[0:$n] + "…" else . end;
def oneline: gsub("\\s+"; " ");
'
```

`backend_claude` — verified against a real stream:

```bash
BACKEND_JQ_LIVE='
if .type == "assistant" then
    (.message.content // [])[]
    | if .type == "tool_use" then
        "  → " + .name + " " + ((.input.command // .input.file_path // .input.path
          // .input.pattern // (.input | tostring)) | oneline | trim(100))
      elif .type == "text" then
        (.text | oneline | trim(300)) | if . == "" then empty else "  " + . end
      else empty end
elif .type == "result" then
    "  [result] " + (.subtype // "?") + " · " + (((.duration_ms // 0) / 1000 | round) | tostring) + "s"
else empty end'
```

`backend_pi` — verified against a real `pi --mode json` stream. The standalone event carries the tool under `toolName` and its input under `args`, flat on the event itself:

```json
{"type":"tool_execution_start","toolCallId":"toolu_01Ca…","toolName":"bash","args":{"command":"ls -la"}}
```

This does not contradict `specs/pi-backend.md:34`, which documents `name` and `arguments.command` — those are the fields of an assistant `toolCall` **content item** inside `agent_end.messages`, a different shape from the standalone execution event. `specs/pi-backend.md:44` speaks only of `tool_execution_end`, which indeed omits `args`; its `_start` sibling carries them, as above. `message_update` falls through to `empty`, which suppresses the usage-snapshot flood:

```bash
BACKEND_JQ_LIVE='
if .type == "tool_execution_start" then
    "  → " + .toolName + " " + ((.args.command // .args.file_path // .args.path
      // .args.pattern // (.args | tostring)) | oneline | trim(100))
elif .type == "message_end" and .message.role == "assistant" then
    ((.message.content // []) | map(select(.type == "text") | .text) | join(" ")
      | oneline | trim(300)) | if . == "" then empty else "  " + . end
elif .type == "turn_start" then "  ---"
else empty end'
```

`backend_codex` and `backend_copilot` — **filters must be confirmed against a captured stream before they ship.** Neither CLI could be authenticated during this investigation, so their event shapes are known only from the existing summary filters, and `specs/codex-jq-filter-fix.md` records what happens when such a filter is written from assumption. A partial `codex exec --json` capture did confirm the wrapper vocabulary `thread.started`, `turn.started`, `error`, `turn.failed`, with per-item events nested under `.item`; the item wrapper's own `.type` is unconfirmed. Until a filter is confirmed, leave `BACKEND_JQ_LIVE` unset for that backend.

An unset or empty `BACKEND_JQ_LIVE` is legal and must degrade cleanly: the loop skips the tee pipeline and takes the plain redirect, so a backend without a live filter behaves exactly as it does today, even under `--verbose`. This keeps the backend-addition contract intact — a new backend needs no live filter to work.

### 7. Replace the verbose raw dump with a pointer

With the stream on disk at a stable path, re-printing it (`ralph:1016-1019`) only buries the live output the user just watched. Replace it:

```
[verbose] Raw stream: .ralph/metrics/<run>/iter-003.stream.jsonl
```

The replacement is conditional. One rule covers both cases: print the pointer only when there is something for the pointer to point at, and otherwise keep today's raw dump (`ralph:1016-1019`) verbatim.

- `BACKEND_JQ_LIVE` set, and metrics enabled — print the pointer. The user has just watched the stream and needs the path, not a second copy.
- `BACKEND_JQ_LIVE` unset or empty — raw dump. Nothing was rendered live, so removing the dump would leave `--verbose` with less than it has today. This is what makes the "exactly as it does today" guarantee in section 6 true for `codex` and `copilot`, which ship with no live filter.
- Metrics disabled (`--no-metrics`, or a metrics directory that could not be created, `ralph:873-875`) — raw dump. The stream lives in the per-run temp file from section 2, which the next iteration truncates and the `EXIT` trap deletes, so its path is useless to the user by the time they read it.

The `--verbose` hint on jq parse failure (`ralph:1029`) changes with it, on the pointer path only: the raw stream is now a file to inspect, not output to re-read.

## Extensibility

`BACKEND_JQ_LIVE` joins the existing well-known variables set by each `backend_<name>` function. Adding a backend still requires only that function plus a `SUPPORTED_BACKENDS` entry, and `cmd_loop` needs no change. The live filter is optional, per section 6.

## Documentation

### README

The options table (`README.md:42-51`) is missing `-v` / `--verbose` entirely, although the flag has shipped. Add it, with the extended meaning:

```
| `-v`, `--verbose`    | Stream backend activity live, and show commands, exit codes and the raw stream path |
```

Add a short subsection after "Loop metrics" explaining that a normal run prints one summary per iteration, and that `--verbose` renders each tool call and assistant message as it happens.

### `ralph --help`

The in-script option list (`ralph:172`) still reads `Show backend commands, raw output, and exit codes`, which section 7 falsifies. Bring it in line with the README entry:

```
  -v, --verbose        Stream backend activity live; show commands, exit codes and the raw stream path
```

### CLAUDE.md and AGENTS.md

The "Core loop flow" list describes step 5 as piping the prompt to the backend and step 6 as parsing with jq. Update both to say the raw stream is written to a file, that the summary filter reads that file, and that `--verbose` additionally tees the stream through a per-backend live filter. Add `BACKEND_JQ_LIVE` to the backend-variables sentence under "Shell scripting conventions".

`AGENTS.md` is a near-identical copy of `CLAUDE.md` and carries the same two passages, at `AGENTS.md:46-47` and `AGENTS.md:92`. Both files take the same edit, so an agent reading either one gets the same description of how the loop consumes backend output.

## Testing

All tests use mock commands. No real backend CLI is required. Because live lines go to stderr and the summary to stdout (section 3), every test that distinguishes the two must invoke `run --separate-stderr`, so `$output` and `$stderr` stay separate rather than merging into `$output`.

### Harness change

A mock that emits timed JSONL and can exit non-zero on demand, so tests can assert immediacy, ordering and exit-code propagation. The delays and the sentinel are what make immediacy observable: the mock does not finish until well after its first event, and it announces its own finish by creating `$MOCK_SENTINEL`.

```bash
#!/usr/bin/env bash
echo '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Bash","input":{"command":"ls -la"}}]}}'
sleep "${MOCK_DELAY:-0}"
echo '{"type":"assistant","message":{"content":[{"type":"text","text":"done here"}]}}'
sleep "${MOCK_DELAY:-0}"
echo '{"type":"result","subtype":"success","duration_ms":1234,"result":"done here"}'
[[ -n "${MOCK_SENTINEL:-}" ]] && : > "$MOCK_SENTINEL"
exit "${MOCK_EXIT:-0}"
```

### New tests

- **Verbose renders tool calls live**: run `ralph build -n 1 --skip-push --verbose` with the mock and assert `$stderr` contains `→ Bash ls -la`.
- **Verbose renders assistant text**: assert `$stderr` contains `done here`.
- **Non-verbose renders no live lines**: same mock without `--verbose`; assert neither `$output` nor `$stderr` contains `→ Bash ls -la`, and that `$output` still carries the iteration summary `done here`. The mock's result event carries `"result":"done here"` for exactly this reason: the claude summary filter is `select(.type == "result") | .result // empty` (`ralph:29`), so a result event without that field renders a bare empty line and the assertion cannot pass.
- **Backend exit code survives the tee pipeline**: `MOCK_EXIT=42` with `--verbose`; assert status 42 and that the error names iteration 1 and exit code 42. This is the regression test for the `PIPESTATUS` trap in section 5.
- **Non-JSON stdout does not truncate the stream**: a mock whose first line is not JSON followed by valid events; with `--verbose`, assert exit 0 and that the raw stream file holds every emitted line.
- **A backend without a live filter still runs under verbose**: unset `BACKEND_JQ_LIVE` for the backend under test; assert the iteration completes, the summary prints, and `--verbose` still emits the raw dump rather than the path pointer, per section 7.
- **Raw stream exists with `--no-metrics`**: assert the run succeeds, leaves no stray temp file behind, and that `--verbose` emits the raw dump rather than a pointer to the deleted temp file.
- **Verbose prints the raw stream path**: assert `$stderr` contains `[verbose] Raw stream:` and not the raw JSON body.
- **Metrics still parse from the file**: with metrics on, assert `metrics.jsonl` records the tool histogram, confirming the metrics reader works against the loop-written file.
- **Live lines arrive before the backend exits**: with `MOCK_DELAY` set to a few seconds and `MOCK_SENTINEL` pointing at a path that does not yet exist, run the loop in the background and poll for `→ Bash ls -la` in the captured stderr. Assert it appears while `$MOCK_SENTINEL` is still absent. This is the only test that distinguishes live rendering from a whole-stream capture rendered at the end, and it is the regression test for `--unbuffered`.
- **Backend stderr stays out of the raw stream**: a mock that writes to stderr as well as stdout; with `--verbose`, assert every line of `$raw_file` parses as JSON. This is the regression test for the `stderr_handler` contract in section 1.

### Existing tests

All existing tests must pass unchanged. `test/pipeline.bats:36` ("pipeline failure ... produces error with iteration and exit code") covers the non-verbose exit path only; the new verbose exit-code test is its counterpart. `test/metrics.bats` exercises the raw-stream file and needs review against the new write site.

## Out of Scope

- Live rendering by default, and any `--quiet` flag to suppress it. Changing the default is a one-line follow-up once the renderer has real mileage.
- A heartbeat during a single long tool call. Nothing renders between `tool_execution_start` and `tool_execution_end`, so a five-minute test suite still looks idle. Rendering `pi`'s `tool_execution_update` partials, or emitting an elapsed-time tick, is a separate change.
- Verbosity levels. One level stays sufficient, as decided in `specs/pipeline-error-handling.md`.
- Coloured output, spinners, or any cursor addressing. Plain lines only, so the output stays readable when redirected to a file.
- Log-to-file or structured logging. The raw stream on disk already serves that need.
- Changes to `BACKEND_JQ_FILTER`, the backend CLI flags, or the metrics schema.
- Streaming the prompt or backend stderr differently. Stderr already streams.
