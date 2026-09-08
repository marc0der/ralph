#!/usr/bin/env bats

load test_helper

# --- Verbose flag acceptance ---

@test "--verbose flag is accepted without error (build, dry-run)" {
    "$RALPH" init
    run "$RALPH" build --dry-run -n 1 --verbose
    [[ "$status" -eq 0 ]]
}

@test "--verbose flag is accepted without error (plan, dry-run)" {
    "$RALPH" init
    run "$RALPH" plan --dry-run -n 1 --verbose
    [[ "$status" -eq 0 ]]
}

@test "-v shorthand is accepted without error" {
    "$RALPH" init
    run "$RALPH" build --dry-run -n 1 -v
    [[ "$status" -eq 0 ]]
}

# --- Verbose output content ---

@test "--verbose dry-run output includes the backend command line" {
    "$RALPH" init
    run "$RALPH" build --dry-run -n 1 --verbose
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"[dry-run] Would run: claude -p"* ]]
}

# --- Pipeline failure: backend exits non-zero ---

@test "pipeline failure (backend exits non-zero) produces error with iteration and exit code" {
    "$RALPH" init
    # Create a mock backend that exits non-zero
    mkdir -p "$TEST_DIR/bin"
    cat > "$TEST_DIR/bin/claude" <<'MOCK'
#!/usr/bin/env bash
exit 42
MOCK
    chmod +x "$TEST_DIR/bin/claude"

    PATH="$TEST_DIR/bin:$PATH" run "$RALPH" build -n 1 --skip-push
    [[ "$status" -eq 42 ]]
    [[ "$output" == *"backend command failed"* ]]
    [[ "$output" == *"iteration 1"* ]]
    [[ "$output" == *"exit code 42"* ]]
}

@test "pipeline failure error message suggests --verbose and --dry-run" {
    "$RALPH" init
    mkdir -p "$TEST_DIR/bin"
    cat > "$TEST_DIR/bin/claude" <<'MOCK'
#!/usr/bin/env bash
exit 1
MOCK
    chmod +x "$TEST_DIR/bin/claude"

    PATH="$TEST_DIR/bin:$PATH" run "$RALPH" build -n 1 --skip-push
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"--verbose"* ]]
    [[ "$output" == *"--dry-run"* ]]
}

# --- Pipeline failure: jq parse failure ---

@test "jq failure is reported distinctly from a backend failure" {
    "$RALPH" init
    # Create a mock backend that outputs invalid JSON
    mkdir -p "$TEST_DIR/bin"
    cat > "$TEST_DIR/bin/claude" <<'MOCK'
#!/usr/bin/env bash
echo "this is not valid json"
MOCK
    chmod +x "$TEST_DIR/bin/claude"

    PATH="$TEST_DIR/bin:$PATH" run "$RALPH" build -n 1 --skip-push
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"jq parse failure"* ]]
    [[ "$output" != *"backend command failed"* ]]
}

# --- Backend stderr visibility ---

@test "backend stderr remains visible in non-verbose mode" {
    "$RALPH" init
    mkdir -p "$TEST_DIR/bin"
    cat > "$TEST_DIR/bin/claude" <<'MOCK'
#!/usr/bin/env bash
echo "stderr message from backend" >&2
echo '{"type":"result","result":"done"}'
MOCK
    chmod +x "$TEST_DIR/bin/claude"

    PATH="$TEST_DIR/bin:$PATH" run "$RALPH" build -n 1 --skip-push
    [[ "$output" == *"stderr message from backend"* ]]
}

# --- Non-verbose, non-failure: no extra output ---

@test "non-verbose non-failure run produces no extra verbose output" {
    "$RALPH" init
    mkdir -p "$TEST_DIR/bin"
    cat > "$TEST_DIR/bin/claude" <<'MOCK'
#!/usr/bin/env bash
echo '{"type":"result","result":"hello world"}'
MOCK
    chmod +x "$TEST_DIR/bin/claude"

    PATH="$TEST_DIR/bin:$PATH" run "$RALPH" build -n 1 --skip-push
    [[ "$status" -eq 0 ]]
    [[ "$output" != *"[verbose]"* ]]
    [[ "$output" == *"hello world"* ]]
}

# --- Codex jq filter tests ---

@test "codex jq filter extracts agent_message text from realistic JSONL" {
    "$RALPH" init
    mkdir -p "$TEST_DIR/bin"
    cat > "$TEST_DIR/bin/codex" <<'MOCK'
#!/usr/bin/env bash
echo '{"type":"thread.started","thread_id":"thread_abc123"}'
echo '{"type":"turn.started"}'
echo '{"type":"item.completed","item":{"id":"item_0","type":"agent_message","text":"I fixed the bug in main.py"}}'
echo '{"type":"turn.completed","usage":{"input_tokens":100,"cached_input_tokens":50,"output_tokens":200}}'
MOCK
    chmod +x "$TEST_DIR/bin/codex"

    PATH="$TEST_DIR/bin:$PATH" run "$RALPH" build -n 1 -b codex --skip-push
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"I fixed the bug in main.py"* ]]
}

@test "codex jq filter takes last agent_message when multiple exist" {
    "$RALPH" init
    mkdir -p "$TEST_DIR/bin"
    cat > "$TEST_DIR/bin/codex" <<'MOCK'
#!/usr/bin/env bash
echo '{"type":"thread.started","thread_id":"thread_abc123"}'
echo '{"type":"turn.started"}'
echo '{"type":"item.completed","item":{"id":"item_0","type":"agent_message","text":"Starting work on the fix"}}'
echo '{"type":"item.completed","item":{"id":"item_1","type":"agent_message","text":"All done, tests pass"}}'
echo '{"type":"turn.completed","usage":{"input_tokens":100,"cached_input_tokens":50,"output_tokens":200}}'
MOCK
    chmod +x "$TEST_DIR/bin/codex"

    PATH="$TEST_DIR/bin:$PATH" run "$RALPH" build -n 1 -b codex --skip-push
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"All done, tests pass"* ]]
    [[ "$output" != *"Starting work on the fix"* ]]
}

@test "codex jq filter falls back to command transcript when no agent_message" {
    "$RALPH" init
    mkdir -p "$TEST_DIR/bin"
    cat > "$TEST_DIR/bin/codex" <<'MOCK'
#!/usr/bin/env bash
echo '{"type":"thread.started","thread_id":"thread_abc123"}'
echo '{"type":"turn.started"}'
echo '{"type":"item.completed","item":{"id":"item_0","type":"command_execution","status":"completed","command":"rg -n TODO","aggregated_output":"README.md:1:TODO"}}'
echo '{"type":"turn.completed","usage":{"input_tokens":100,"cached_input_tokens":50,"output_tokens":200}}'
MOCK
    chmod +x "$TEST_DIR/bin/codex"

    PATH="$TEST_DIR/bin:$PATH" run "$RALPH" build -n 1 -b codex --skip-push
    [[ "$status" -eq 0 ]]
    [[ "$output" == *'$ rg -n TODO'* ]]
    [[ "$output" == *"README.md:1:TODO"* ]]
}

@test "codex jq filter includes multiple completed commands in transcript" {
    "$RALPH" init
    mkdir -p "$TEST_DIR/bin"
    cat > "$TEST_DIR/bin/codex" <<'MOCK'
#!/usr/bin/env bash
echo '{"type":"thread.started","thread_id":"thread_abc123"}'
echo '{"type":"turn.started"}'
echo '{"type":"item.completed","item":{"id":"item_0","type":"command_execution","status":"completed","command":"rg -n TODO","aggregated_output":"README.md:1:TODO"}}'
echo '{"type":"item.completed","item":{"id":"item_1","type":"command_execution","status":"completed","command":"ls","aggregated_output":"README.md\\nralph"}}'
echo '{"type":"turn.completed","usage":{"input_tokens":100,"cached_input_tokens":50,"output_tokens":200}}'
MOCK
    chmod +x "$TEST_DIR/bin/codex"

    PATH="$TEST_DIR/bin:$PATH" run "$RALPH" build -n 1 -b codex --skip-push
    [[ "$status" -eq 0 ]]
    [[ "$output" == *'$ rg -n TODO'* ]]
    [[ "$output" == *"README.md:1:TODO"* ]]
    [[ "$output" == *'$ ls'* ]]
    [[ "$output" == *"README.md"* ]]
    [[ "$output" == *"ralph"* ]]
}

@test "codex jq filter prefers agent_message over command transcript" {
    "$RALPH" init
    mkdir -p "$TEST_DIR/bin"
    cat > "$TEST_DIR/bin/codex" <<'MOCK'
#!/usr/bin/env bash
echo '{"type":"thread.started","thread_id":"thread_abc123"}'
echo '{"type":"turn.started"}'
echo '{"type":"item.completed","item":{"id":"item_0","type":"command_execution","status":"completed","command":"rg -n TODO","aggregated_output":"README.md:1:TODO"}}'
echo '{"type":"item.completed","item":{"id":"item_1","type":"agent_message","text":"Summary complete"}}'
echo '{"type":"turn.completed","usage":{"input_tokens":100,"cached_input_tokens":50,"output_tokens":200}}'
MOCK
    chmod +x "$TEST_DIR/bin/codex"

    PATH="$TEST_DIR/bin:$PATH" run "$RALPH" build -n 1 -b codex --skip-push
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"Summary complete"* ]]
    [[ "$output" != *'$ rg -n TODO'* ]]
}

@test "codex jq filter returns empty output when no items exist" {
    "$RALPH" init
    mkdir -p "$TEST_DIR/bin"
    cat > "$TEST_DIR/bin/codex" <<'MOCK'
#!/usr/bin/env bash
echo '{"type":"thread.started","thread_id":"thread_abc123"}'
echo '{"type":"turn.started"}'
echo '{"type":"turn.completed","usage":{"input_tokens":100,"cached_input_tokens":50,"output_tokens":200}}'
MOCK
    chmod +x "$TEST_DIR/bin/codex"

    PATH="$TEST_DIR/bin:$PATH" run "$RALPH" build -n 1 -b codex --skip-push
    [[ "$status" -eq 0 ]]
    if echo "$output" | grep -q '^\$ '; then return 1; fi
    [[ "$output" != *"Summary complete"* ]]
}

# --- Copilot jq filter tests ---

@test "copilot jq filter extracts assistant.message content from realistic JSONL" {
    "$RALPH" init
    mkdir -p "$TEST_DIR/bin"
    cat > "$TEST_DIR/bin/copilot" <<'MOCK'
#!/usr/bin/env bash
echo '{"id":"e1","timestamp":"2026-01-01T00:00:00Z","parentId":null,"ephemeral":false,"type":"assistant.turn_start","data":{}}'
echo '{"id":"e2","timestamp":"2026-01-01T00:00:01Z","parentId":null,"ephemeral":true,"type":"assistant.message_delta","data":{"delta":"Fixed "}}'
echo '{"id":"e3","timestamp":"2026-01-01T00:00:02Z","parentId":null,"ephemeral":false,"type":"assistant.message","data":{"messageId":"m1","content":"Fixed the bug in main.py","toolRequests":[],"outputTokens":42,"phase":"response"}}'
echo '{"id":"e4","timestamp":"2026-01-01T00:00:03Z","parentId":null,"ephemeral":false,"type":"assistant.usage","data":{}}'
echo '{"id":"e5","timestamp":"2026-01-01T00:00:04Z","parentId":null,"ephemeral":false,"type":"assistant.turn_end","data":{}}'
MOCK
    chmod +x "$TEST_DIR/bin/copilot"

    PATH="$TEST_DIR/bin:$PATH" run "$RALPH" build -n 1 -b copilot --skip-push
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"Fixed the bug in main.py"* ]]
}

@test "copilot jq filter falls back to tool.execution_complete transcript when no assistant.message" {
    "$RALPH" init
    mkdir -p "$TEST_DIR/bin"
    cat > "$TEST_DIR/bin/copilot" <<'MOCK'
#!/usr/bin/env bash
echo '{"id":"e1","timestamp":"2026-01-01T00:00:00Z","parentId":null,"ephemeral":false,"type":"assistant.turn_start","data":{}}'
echo '{"id":"e2","timestamp":"2026-01-01T00:00:01Z","parentId":null,"ephemeral":false,"type":"tool.execution_start","data":{"toolName":"shell"}}'
echo '{"id":"e3","timestamp":"2026-01-01T00:00:02Z","parentId":null,"ephemeral":false,"type":"tool.execution_complete","data":{"success":true,"result":{"content":"README.md:1:TODO"}}}'
echo '{"id":"e4","timestamp":"2026-01-01T00:00:03Z","parentId":null,"ephemeral":false,"type":"tool.execution_complete","data":{"success":true,"result":{"content":"main.py:42:FIXME"}}}'
echo '{"id":"e5","timestamp":"2026-01-01T00:00:04Z","parentId":null,"ephemeral":false,"type":"session.idle","data":{}}'
MOCK
    chmod +x "$TEST_DIR/bin/copilot"

    PATH="$TEST_DIR/bin:$PATH" run "$RALPH" build -n 1 -b copilot --skip-push
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"README.md:1:TODO"* ]]
    [[ "$output" == *"main.py:42:FIXME"* ]]
}

@test "copilot jq filter prefers assistant.message over tool transcript" {
    "$RALPH" init
    mkdir -p "$TEST_DIR/bin"
    cat > "$TEST_DIR/bin/copilot" <<'MOCK'
#!/usr/bin/env bash
echo '{"id":"e1","timestamp":"2026-01-01T00:00:00Z","parentId":null,"ephemeral":false,"type":"tool.execution_complete","data":{"success":true,"result":{"content":"README.md:1:TODO"}}}'
echo '{"id":"e2","timestamp":"2026-01-01T00:00:01Z","parentId":null,"ephemeral":false,"type":"assistant.message","data":{"messageId":"m1","content":"Summary complete","toolRequests":[],"outputTokens":12,"phase":"response"}}'
MOCK
    chmod +x "$TEST_DIR/bin/copilot"

    PATH="$TEST_DIR/bin:$PATH" run "$RALPH" build -n 1 -b copilot --skip-push
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"Summary complete"* ]]
    [[ "$output" != *"README.md:1:TODO"* ]]
}

# --- Pi jq filter tests ---

@test "pi jq filter extracts assistant text from agent_end" {
    "$RALPH" init
    mkdir -p "$TEST_DIR/bin"
    cat > "$TEST_DIR/bin/pi" <<'MOCK'
#!/usr/bin/env bash
echo '{"type":"session","version":3,"id":"abc","timestamp":"2026-01-01T00:00:00Z","cwd":"/tmp"}'
echo '{"type":"agent_end","messages":[{"role":"user","content":[{"type":"text","text":"hi"}]},{"role":"assistant","content":[{"type":"text","text":"hello from pi"}]}],"willRetry":false}'
MOCK
    chmod +x "$TEST_DIR/bin/pi"

    PATH="$TEST_DIR/bin:$PATH" run "$RALPH" build -n 1 -b pi --skip-push
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"hello from pi"* ]]
}

@test "pi jq filter takes the last agent_end when auto-retry emits two" {
    "$RALPH" init
    mkdir -p "$TEST_DIR/bin"
    cat > "$TEST_DIR/bin/pi" <<'MOCK'
#!/usr/bin/env bash
echo '{"type":"session","version":3,"id":"abc","timestamp":"2026-01-01T00:00:00Z","cwd":"/tmp"}'
echo '{"type":"agent_end","messages":[{"role":"assistant","content":[{"type":"text","text":"interim"}]}],"willRetry":true}'
echo '{"type":"agent_end","messages":[{"role":"assistant","content":[{"type":"text","text":"final answer"}]}],"willRetry":false}'
MOCK
    chmod +x "$TEST_DIR/bin/pi"

    PATH="$TEST_DIR/bin:$PATH" run "$RALPH" build -n 1 -b pi --skip-push
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"final answer"* ]]
    [[ "$output" != *"interim"* ]]
}

@test "pi jq filter falls back to bash tool transcript when no assistant text" {
    "$RALPH" init
    mkdir -p "$TEST_DIR/bin"
    cat > "$TEST_DIR/bin/pi" <<'MOCK'
#!/usr/bin/env bash
echo '{"type":"session","version":3,"id":"abc","timestamp":"2026-01-01T00:00:00Z","cwd":"/tmp"}'
echo '{"type":"agent_end","messages":[{"role":"assistant","content":[{"type":"toolCall","id":"call1","name":"bash","arguments":{"command":"ls"}}]},{"role":"toolResult","toolCallId":"call1","toolName":"bash","content":[{"type":"text","text":"README.md ralph"}],"isError":false}],"willRetry":false}'
MOCK
    chmod +x "$TEST_DIR/bin/pi"

    PATH="$TEST_DIR/bin:$PATH" run "$RALPH" build -n 1 -b pi --skip-push
    [[ "$status" -eq 0 ]]
    [[ "$output" == *'$ ls'* ]]
    [[ "$output" == *"README.md ralph"* ]]
}

@test "pi jq filter emits empty when no assistant text and no successful tool results" {
    "$RALPH" init
    mkdir -p "$TEST_DIR/bin"
    cat > "$TEST_DIR/bin/pi" <<'MOCK'
#!/usr/bin/env bash
echo '{"type":"session","version":3,"id":"abc","timestamp":"2026-01-01T00:00:00Z","cwd":"/tmp"}'
echo '{"type":"agent_end","messages":[{"role":"assistant","content":[{"type":"toolCall","id":"call1","name":"bash","arguments":{"command":"false"}}]},{"role":"toolResult","toolCallId":"call1","toolName":"bash","content":[{"type":"text","text":"command failed"}],"isError":true}],"willRetry":false}'
MOCK
    chmod +x "$TEST_DIR/bin/pi"

    PATH="$TEST_DIR/bin:$PATH" run "$RALPH" build -n 1 -b pi --skip-push
    [[ "$status" -eq 0 ]]
    if echo "$output" | grep -q '^\$ '; then return 1; fi
    [[ "$output" != *"command failed"* ]]
}

# --- Stdin prompt: codex passes prompt as CLI arg, claude pipes via stdin ---

@test "codex dry-run shows prompt as a positional argument in the command line" {
    "$RALPH" init
    run "$RALPH" build --dry-run -n 1 -b codex
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"[dry-run] Would run: codex exec"*"<prompt>"* ]]
}

@test "claude dry-run does NOT show prompt as a positional argument" {
    "$RALPH" init
    run "$RALPH" build --dry-run -n 1
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"[dry-run] Would run: claude -p"* ]]
    # The dry-run line should NOT contain <prompt> marker
    local dryrun_line
    dryrun_line=$(echo "$output" | grep '\[dry-run\] Would run:')
    [[ "$dryrun_line" != *"<prompt>"* ]]
}

@test "codex mock backend receives the prompt as a CLI argument (not on stdin)" {
    "$RALPH" init
    mkdir -p "$TEST_DIR/bin"
    local argfile="$TEST_DIR/received_arg.txt"
    # Mock codex that writes its last CLI argument to a file
    cat > "$TEST_DIR/bin/codex" <<MOCK
#!/usr/bin/env bash
# Save last argument (the prompt) to a file for verification
echo "\${@: -1}" > "$argfile"
# Output valid JSONL
echo '{"type":"item.completed","item":{"id":"item_0","type":"agent_message","text":"done"}}'
MOCK
    chmod +x "$TEST_DIR/bin/codex"

    PATH="$TEST_DIR/bin:$PATH" run "$RALPH" build -n 1 -b codex --skip-push
    [[ "$status" -eq 0 ]]
    # Verify the prompt was passed as CLI arg (contains build prompt content)
    [[ -f "$argfile" ]]
    local received_arg
    received_arg=$(<"$argfile")
    [[ -n "$received_arg" ]]
    # The received argument should contain the prompt text (from the build prompt template)
    [[ "$received_arg" == *"Build"* ]] || [[ "$received_arg" == *"build"* ]] || [[ ${#received_arg} -gt 10 ]]
}

@test "claude mock backend receives the prompt on stdin (not as a CLI argument)" {
    "$RALPH" init
    mkdir -p "$TEST_DIR/bin"
    local stdinfile="$TEST_DIR/received_stdin.txt"
    # Mock claude that captures stdin
    cat > "$TEST_DIR/bin/claude" <<MOCK
#!/usr/bin/env bash
# Capture stdin
cat > "$stdinfile"
# Output valid JSON
echo '{"type":"result","result":"done"}'
MOCK
    chmod +x "$TEST_DIR/bin/claude"

    PATH="$TEST_DIR/bin:$PATH" run "$RALPH" build -n 1 --skip-push
    [[ "$status" -eq 0 ]]
    # Verify stdin was received with prompt content
    [[ -f "$stdinfile" ]]
    local received_stdin
    received_stdin=$(<"$stdinfile")
    [[ -n "$received_stdin" ]]
}

# --- Verbose mode: exit codes shown ---

@test "--verbose output includes exit codes after each iteration" {
    "$RALPH" init
    mkdir -p "$TEST_DIR/bin"
    cat > "$TEST_DIR/bin/claude" <<'MOCK'
#!/usr/bin/env bash
echo '{"type":"result","result":"ok"}'
MOCK
    chmod +x "$TEST_DIR/bin/claude"

    PATH="$TEST_DIR/bin:$PATH" run "$RALPH" build -n 1 --skip-push --verbose
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"[verbose] Exit codes"* ]]
    [[ "$output" == *"backend: 0"* ]]
    [[ "$output" == *"jq: 0"* ]]
}

# --- Verbose mode: backend command shown ---

@test "--verbose output includes backend command before execution" {
    "$RALPH" init
    mkdir -p "$TEST_DIR/bin"
    cat > "$TEST_DIR/bin/claude" <<'MOCK'
#!/usr/bin/env bash
echo '{"type":"result","result":"ok"}'
MOCK
    chmod +x "$TEST_DIR/bin/claude"

    PATH="$TEST_DIR/bin:$PATH" run "$RALPH" build -n 1 --skip-push --verbose
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"[verbose] Backend command: claude"* ]]
}

# --- Verbose mode: live stream rendering ---

# Live rendering is the whole point of the tee pipeline: without it a long
# iteration looks idle until the backend exits. Rendered lines go to stderr so
# stdout keeps carrying only the per-iteration summary, which is why every test
# in this section needs --separate-stderr to tell the two apart.

@test "--verbose renders tool calls live on stderr" {
    "$RALPH" init
    create_streaming_backend

    PATH="$TEST_DIR/bin:$PATH" run --separate-stderr "$RALPH" build -n 1 --skip-push --verbose
    [[ "$status" -eq 0 ]]
    [[ "$stderr" == *"→ Bash ls -la"* ]]
}

@test "--verbose renders assistant text live on stderr" {
    "$RALPH" init
    create_streaming_backend

    PATH="$TEST_DIR/bin:$PATH" run --separate-stderr "$RALPH" build -n 1 --skip-push --verbose
    [[ "$status" -eq 0 ]]
    [[ "$stderr" == *"done here"* ]]
}

# The default path must stay quiet. The mock's result event repeats the text as
# `.result`, because that is the field the claude summary filter reads — so this
# also proves the summary survives the live-render branch being skipped.
@test "non-verbose run renders no live lines but still prints the summary" {
    "$RALPH" init
    create_streaming_backend

    PATH="$TEST_DIR/bin:$PATH" run --separate-stderr "$RALPH" build -n 1 --skip-push
    [[ "$status" -eq 0 ]]
    [[ "$output" != *"→ Bash ls -la"* ]]
    [[ "$stderr" != *"→ Bash ls -la"* ]]
    [[ "$output" == *"done here"* ]]
}

# --- Verbose mode: raw stream pointer vs raw dump ---

# Section 7 of the spec gives --verbose two mutually exclusive forms per
# iteration. A stream the run retains and has already rendered live prints as a
# one-line path, because re-printing it would bury the live output. Everything
# else keeps the raw dump. These tests pin which form each case gets, so a
# change to one condition cannot silently collapse both into the same output.

@test "--verbose prints the raw stream path, not the raw JSON body" {
    "$RALPH" init
    create_streaming_backend

    PATH="$TEST_DIR/bin:$PATH" run --separate-stderr "$RALPH" build -n 1 --skip-push --verbose
    [[ "$status" -eq 0 ]]
    [[ "$stderr" == *"[verbose] Raw stream:"* ]]
    [[ "$stderr" == *"iter-001.stream.jsonl"* ]]
    [[ "$stderr" != *"[verbose] Raw backend output:"* ]]
    # The rendered lines carry no JSON punctuation, so a raw event on fd 2 can
    # only have come from a dump the pointer was meant to replace.
    [[ "$stderr" != *'"type":"assistant"'* ]]
}

# codex ships no BACKEND_JQ_LIVE, so nothing rendered live and the dump is the
# only way to see the stream. The mock must not read stdin: codex sets
# BACKEND_STDIN_PROMPT=false, so nothing feeds the pipe and a `cat` would block.
@test "a backend without a live filter keeps the raw dump under --verbose" {
    "$RALPH" init
    mkdir -p "$TEST_DIR/bin"
    cat > "$TEST_DIR/bin/codex" <<'MOCK'
#!/usr/bin/env bash
echo '{"type":"item.completed","item":{"id":"item_0","type":"agent_message","text":"codex done"}}'
MOCK
    chmod +x "$TEST_DIR/bin/codex"

    PATH="$TEST_DIR/bin:$PATH" run --separate-stderr "$RALPH" build -n 1 -b codex --skip-push --verbose
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"codex done"* ]]
    [[ "$stderr" == *"[verbose] Raw backend output:"* ]]
    [[ "$stderr" == *'"type":"item.completed"'* ]]
    [[ "$stderr" != *"[verbose] Raw stream:"* ]]
}

# With metrics off the stream lives in the per-run temp file, which the EXIT
# trap deletes — so a pointer to it would name a file the user cannot open.
@test "--no-metrics --verbose keeps the raw dump and leaves no temp file behind" {
    "$RALPH" init
    create_streaming_backend
    mkdir -p "$TEST_DIR/tmp"

    TMPDIR="$TEST_DIR/tmp" PATH="$TEST_DIR/bin:$PATH" \
        run --separate-stderr "$RALPH" build -n 1 --skip-push --no-metrics --verbose
    [[ "$status" -eq 0 ]]
    [[ "$stderr" == *"[verbose] Raw backend output:"* ]]
    [[ "$stderr" == *'"type":"result"'* ]]
    [[ "$stderr" != *"[verbose] Raw stream:"* ]]
    # mktemp names the stream tmp.XXXXXXXXXX; ralph is the only mktemp caller,
    # so anything left under this private TMPDIR is a leaked stream file.
    [[ -z "$(find "$TEST_DIR/tmp" -maxdepth 1 -name 'tmp.*' -print -quit)" ]]
}

# An unwritable metrics directory degrades the run to the same per-run temp
# file --no-metrics uses, while metrics stay nominally requested. The pointer
# has to follow the file, not the flag: a path under a directory the run never
# created, or one the EXIT trap deletes, is a path the user cannot open.
@test "unwritable metrics keeps the raw dump under --verbose" {
    "$RALPH" init
    create_streaming_backend

    # A file squatting on the path denies the mkdir even when tests run as
    # root, where chmod-based denial does not bite (same idiom as
    # test/metrics.bats "metrics failure does not fail the loop").
    mkdir -p .ralph
    touch .ralph/metrics

    PATH="$TEST_DIR/bin:$PATH" run --separate-stderr "$RALPH" build -n 1 --skip-push --verbose
    rm -f .ralph/metrics

    [[ "$status" -eq 0 ]]
    [[ "$stderr" == *"metrics disabled for this run"* ]]
    [[ "$stderr" != *"[verbose] Raw stream:"* ]]
    [[ "$stderr" == *"[verbose] Raw backend output:"* ]]
    [[ "$stderr" == *'"type":"result"'* ]]
}

# The case above never reaches the degrade path: a failed `mkdir -p` disables
# metrics outright, so the pointer was already off. This one holds metrics
# enabled while the stream file underneath is unwritable — a `mkdir` shim
# reports success for the metrics directory without creating it, which denies
# the write even when tests run as root. Only here does the pointer condition
# have to look at where `raw_file` sits rather than at the metrics flag.
@test "a metrics run degraded to the temp file keeps the raw dump" {
    "$RALPH" init
    create_streaming_backend

    local real_mkdir
    real_mkdir=$(command -v mkdir)
    {
        printf '#!/usr/bin/env bash\nREAL_MKDIR=%q\n' "$real_mkdir"
        cat <<'MOCK'
for arg in "$@"; do
    case "$arg" in */metrics/*) exit 0 ;; esac
done
exec "$REAL_MKDIR" "$@"
MOCK
    } > "$TEST_DIR/bin/mkdir"
    chmod +x "$TEST_DIR/bin/mkdir"

    PATH="$TEST_DIR/bin:$PATH" run --separate-stderr "$RALPH" build -n 1 --skip-push --verbose
    [[ "$status" -eq 0 ]]
    # Metrics stayed enabled: the run still announced its metrics file and only
    # failed when it tried to write into the directory that was never created.
    [[ "$output" == *"Metrics: .ralph/metrics/"* ]]
    [[ "$stderr" == *"metrics capture failed for iteration 1"* ]]
    # The stream fell back to the per-run temp file, which the EXIT trap
    # deletes, so its path must not be offered as something to inspect.
    [[ "$stderr" != *"[verbose] Raw stream:"* ]]
    [[ "$stderr" == *"[verbose] Raw backend output:"* ]]
    [[ "$stderr" == *'"type":"result"'* ]]
    # The degrade is a decision, not a fault, so it must be silent apart from
    # ralph's own metrics warning. Bash applies redirections left to right, so
    # the writability probe used to open the file before 2>/dev/null could
    # cover it, and leaked `.../iter-001.stream.jsonl: No such file or
    # directory` on to stderr — a shell error naming a file ralph deliberately
    # stopped using, with no ralph prefix to tell the user it was handled.
    [[ "$stderr" != *"No such file or directory"* ]]
}

# The renderer swallows jq's diagnostics with 2>/dev/null and drains the pipe
# with `|| cat`, so a filter that never compiled looks exactly like one that
# rendered every event: exit 0, no output. Combined with the pointer, that made
# --verbose print *less* than it did before live rendering existed — a single
# `[verbose] Raw stream:` line and nothing else. The drain now ends in `false`
# so ${st[2]} carries the renderer's verdict, and a dead renderer gives the
# dump back. A jq shim that fails only for the -rR call stands in for the real
# causes: a typo in a future BACKEND_JQ_LIVE, or a jq built without Oniguruma,
# where the filters' `gsub` is absent.
@test "a broken live filter falls back to the raw dump" {
    "$RALPH" init
    create_streaming_backend

    local real_jq
    real_jq=$(command -v jq)
    {
        printf '#!/usr/bin/env bash\nREAL_JQ=%q\n' "$real_jq"
        cat <<'MOCK'
for arg in "$@"; do
    case "$arg" in -rR) exit 3 ;; esac
done
exec "$REAL_JQ" "$@"
MOCK
    } > "$TEST_DIR/bin/jq"
    chmod +x "$TEST_DIR/bin/jq"

    PATH="$TEST_DIR/bin:$PATH" run --separate-stderr "$RALPH" build -n 1 --skip-push --verbose
    # The renderer is not the backend: its failure must not end the iteration.
    [[ "$status" -eq 0 ]]
    [[ "$stderr" == *"live rendering failed on iteration 1"* ]]
    [[ "$stderr" != *"[verbose] Raw stream:"* ]]
    [[ "$stderr" == *"[verbose] Raw backend output:"* ]]
    [[ "$stderr" == *'"type":"result"'* ]]
    # Nothing rendered, so the dump is the only copy the user gets.
    [[ "$stderr" != *"→ Bash ls -la"* ]]
    # The summary filter runs through the real jq, so the iteration still
    # reports its result.
    [[ "$output" == *"done here"* ]]
}

# `ralph init` gitignores .ralph, so an agent that tidies with `git clean -xfd`
# — or that removes .ralph itself — takes the stream file with it while the
# iteration is still running. The write survives (the fd outlives the unlink),
# but every later read by path fails. Under `set -euo pipefail` the unguarded
# `cat` in the verbose dump killed the run outright, with cat's own message as
# the only diagnostic and no further iterations. Both reads of the path are now
# guarded, so a local file fault degrades one iteration instead of the run.
@test "a removed stream file does not stop the loop under --verbose" {
    "$RALPH" init
    mkdir -p "$TEST_DIR/bin"
    # codex ships no live filter, so this takes the raw-dump branch — the one
    # that reads the file back. BACKEND_STDIN_PROMPT=false for codex, so the
    # mock must not read stdin or it would block.
    cat > "$TEST_DIR/bin/codex" <<'MOCK'
#!/usr/bin/env bash
echo '{"type":"item.completed","item":{"id":"item_0","type":"agent_message","text":"codex done"}}'
rm -rf .ralph/metrics
MOCK
    chmod +x "$TEST_DIR/bin/codex"

    PATH="$TEST_DIR/bin:$PATH" run --separate-stderr "$RALPH" build -n 2 -b codex --skip-push --verbose
    [[ "$status" -eq 0 ]]
    # Reaching iteration 2 is the whole point: before the guards the run ended
    # inside iteration 1.
    [[ "$output" == *"ITERATION 2 / 2"* ]]
    [[ "$stderr" == *"[verbose] Raw stream unavailable:"* ]]
    [[ "$stderr" == *"iter-001.stream.jsonl"* ]]
    # cat's own complaint is the diagnostic the guard replaces; the loop's
    # warning names the file instead.
    [[ "$stderr" == *"is missing or empty after iteration 1"* ]]
    run ! grep -q 'cat:.*No such file or directory' <<<"$stderr"
}

# --- Verbose mode: exit codes and stderr isolation ---

# The tee pipeline puts two more processes between the backend and the shell,
# so a plain `$?` would report the renderer's status instead of the backend's.
# These two tests pin the contracts that arrangement puts at risk: the backend
# exit code must still reach the caller through PIPESTATUS (spec section 5),
# and backend stderr must stay out of the raw stream file that the summary
# filter and the metrics reader both parse (spec section 1). The non-verbose
# counterpart of the first test is "pipeline failure (backend exits non-zero)"
# above, which never enters the tee branch.

@test "backend exit code survives the tee pipeline under --verbose" {
    "$RALPH" init
    create_streaming_backend

    MOCK_EXIT=42 PATH="$TEST_DIR/bin:$PATH" \
        run --separate-stderr "$RALPH" build -n 1 --skip-push --verbose
    [[ "$status" -eq 42 ]]
    # The rendered line proves the run went through the tee branch, so the
    # status below is PIPESTATUS[0] and not a plain command's exit code.
    [[ "$stderr" == *"→ Bash ls -la"* ]]
    [[ "$stderr" == *"backend command failed"* ]]
    [[ "$stderr" == *"iteration 1"* ]]
    [[ "$stderr" == *"exit code 42"* ]]
}

# Wrap the helper's mock so the backend writes to stderr as well as emitting
# events on stdout. Both descriptors feed the same tee pipeline, so a
# stderr_handler line sent to fd 1 would land in the stream file that the
# summary filter and the metrics reader parse.
#
# The mock writes two kinds of noise, because they fail differently. Prose
# leaks loudly: it aborts the summary filter, which cannot parse it. A
# well-formed event leaks silently, and is the real hazard — it would be
# adopted as the iteration result, so only reading the stream file catches it.
@test "backend stderr stays out of the raw stream under --verbose" {
    "$RALPH" init
    create_streaming_backend
    mv "$TEST_DIR/bin/claude" "$TEST_DIR/bin/streaming-events"
    cat > "$TEST_DIR/bin/claude" <<'MOCK'
#!/usr/bin/env bash
echo 'backend warning: refreshing credentials' >&2
"$(dirname "$0")/streaming-events"
status=$?
echo '{"type":"result","subtype":"success","result":"stderr leaked"}' >&2
exit "$status"
MOCK
    chmod +x "$TEST_DIR/bin/claude"

    PATH="$TEST_DIR/bin:$PATH" run --separate-stderr "$RALPH" build -n 1 --skip-push --verbose
    [[ "$status" -eq 0 ]]
    # The noise still reached the user, so this is about routing rather than
    # about stderr being swallowed.
    [[ "$stderr" == *"refreshing credentials"* ]]
    # The summary comes from the backend's own result event, not the stderr one.
    [[ "$output" == *"done here"* ]]
    [[ "$output" != *"stderr leaked"* ]]

    local stream
    stream=$(find .ralph/metrics -name 'iter-001.stream.jsonl' -print -quit)
    [[ -n "$stream" ]]
    # `run !` and not a bare `!`: in bats a bare `!` cannot fail a test, so
    # both of these would be inert (SC2314).
    run ! grep -q 'refreshing credentials' "$stream"
    run ! grep -q 'stderr leaked' "$stream"
    # Count the lines too: dropping an event would satisfy every assertion
    # above, and only three events were ever written to stdout.
    [[ $(wc -l < "$stream") -eq 3 ]]

    local line
    while IFS= read -r line; do
        jq -e . >/dev/null <<<"$line" \
            || { echo "unparseable stream line: $line" >&2; return 1; }
    done < "$stream"
}

# --- Stream write failures ---

# A disk that fills mid-run, a quota, or an .ralph directory the agent under
# test removes all fail the same way: the write to the stream file fails while
# the backend is still producing. With the backend's own stdout redirected at
# the file the backend is the failing writer, so it dies of SIGXFSZ and the
# loop reports `backend command failed (exit code 153)` — a local disk fault
# dressed up as a backend fault, and the run is over. Routing through tee moves
# the failure off the backend: tee absorbs it, keeps draining so the backend
# reaches its own end, and reports it in ${st[1]}.
#
# `ulimit -f 8` stands in for the full disk (8 blocks of 1024 = 8192 bytes).
# The mock emits fifty padded events, well past that, so tee's copy stops
# mid-line while the backend still exits 0.
@test "a stream write failure leaves the loop running" {
    "$RALPH" init
    mkdir -p "$TEST_DIR/bin"
    cat > "$TEST_DIR/bin/claude" <<'MOCK'
#!/usr/bin/env bash
cat > /dev/null
# ~260 bytes per line, so fifty of them overrun an 8192-byte limit around
# event 31 and leave a partial line as the last thing tee wrote.
pad=$(printf 'x%.0s' $(seq 1 200))
for i in $(seq 1 50); do
    printf '{"type":"assistant","message":{"content":[{"type":"text","text":"%s"}]}}\n' "$pad"
done
echo '{"type":"result","subtype":"success","result":"done here"}'
MOCK
    chmod +x "$TEST_DIR/bin/claude"

    # `ulimit -c 0` keeps the SIGXFSZ core out of the test directory; it
    # changes nothing about the write failure itself.
    # shellcheck disable=SC2016  # $0 is the inner shell's argv[0], set below
    run --separate-stderr env "PATH=$TEST_DIR/bin:$PATH" \
        bash -c 'ulimit -c 0; ulimit -f 8; exec "$0" build -n 1 --skip-push --no-metrics' "$RALPH"

    [[ "$status" -eq 0 ]]
    [[ "$stderr" == *"raw backend stream write failed on iteration 1"* ]]
    # The backend reached its own end, so nothing may be blamed on it.
    [[ "$stderr" != *"backend command failed"* ]]
    # The truncated tail costs the summary, and that must degrade too: the
    # non-slurping claude filter aborts on the partial last line, and before
    # this change that parse error exited the run with jq's own status.
    [[ "$stderr" == *"summary parse failed on iteration 1"* ]]
    [[ "$stderr" != *"jq parse failure"* ]]
    [[ "$output" == *"ITERATION 1 / 1"* ]]
}

# --- Verbose mode: live immediacy ---

# The only test that can tell live rendering from a whole-stream capture
# rendered at the end. Every other verbose test passes either way, because the
# rendered lines are all present on stderr by the time `run` returns. Here the
# mock sleeps between events and touches $MOCK_SENTINEL just before it exits,
# so a rendered line observed while the sentinel is still absent proves jq
# emitted it mid-run. This is the regression test for jq's --unbuffered flag:
# without it jq buffers its output and nothing reaches stderr until the pipe
# closes.
@test "live lines arrive on stderr before the backend exits" {
    "$RALPH" init
    create_streaming_backend

    local err="$TEST_DIR/live.err"
    local sentinel="$TEST_DIR/mock-finished"
    : > "$err"
    [[ ! -e "$sentinel" ]]

    MOCK_DELAY=3 MOCK_SENTINEL="$sentinel" PATH="$TEST_DIR/bin:$PATH" \
        "$RALPH" build -n 1 --skip-push --verbose >/dev/null 2>"$err" &
    local pid=$!

    # Poll for up to 10s — the mock needs ~6s to finish, so a renderer that
    # only flushes at exit still gets caught by the sentinel assertion below
    # rather than by this timeout.
    local seen=false waited=0
    while [[ "$waited" -lt 100 ]]; do
        if grep -qF -- '→ Bash ls -la' "$err"; then
            seen=true
            break
        fi
        sleep 0.1
        waited=$((waited + 1))
    done

    [[ "$seen" == true ]]
    [[ ! -e "$sentinel" ]]

    local exit_code=0
    wait "$pid" || exit_code=$?
    [[ "$exit_code" -eq 0 ]]
    [[ -e "$sentinel" ]]
}

# --- Noop early exit ---

@test "build exits early after 2 consecutive noops" {
    "$RALPH" init
    # 5 items = 6 calculated iterations (with 20% headroom)
    for i in 1 2 3 4 5; do
        echo "- [ ] **Task $i**" >> IMPLEMENTATION_PLAN.md
    done
    mkdir -p "$TEST_DIR/bin"
    # Mock backend that succeeds but never commits
    cat > "$TEST_DIR/bin/claude" <<'MOCK'
#!/usr/bin/env bash
echo '{"type":"result","result":"nothing to do"}'
MOCK
    chmod +x "$TEST_DIR/bin/claude"

    PATH="$TEST_DIR/bin:$PATH" run "$RALPH" build --skip-push
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"No changes detected for 2 consecutive iterations"* ]]
    [[ "$output" == *"Completed 2 iterations"* ]]
}

@test "noop counter resets when a commit occurs" {
    "$RALPH" init
    # 3 items = 4 calculated iterations
    for i in 1 2 3; do
        echo "- [ ] **Task $i**" >> IMPLEMENTATION_PLAN.md
    done
    mkdir -p "$TEST_DIR/bin"
    # Mock backend: noop on iteration 1, commit on iteration 2, noop on 3 and 4
    cat > "$TEST_DIR/bin/claude" <<MOCK
#!/usr/bin/env bash
CALL_LOG="$TEST_DIR/call_count"
count=0
[[ -f "\$CALL_LOG" ]] && count=\$(cat "\$CALL_LOG")
count=\$((count + 1))
echo "\$count" > "\$CALL_LOG"
if [[ "\$count" -eq 2 ]]; then
    git commit --allow-empty -m "work done" --quiet
fi
echo '{"type":"result","result":"done"}'
MOCK
    chmod +x "$TEST_DIR/bin/claude"

    PATH="$TEST_DIR/bin:$PATH" run "$RALPH" build --skip-push
    [[ "$status" -eq 0 ]]
    # Should run: noop(1), commit(2), noop(3), noop(4)=early exit
    [[ "$output" == *"No changes detected for 2 consecutive iterations"* ]]
    [[ "$output" == *"ITERATION 4"* ]]
}

@test "noop detection is disabled when -n is passed" {
    "$RALPH" init
    echo "- [ ] **Task one**" > IMPLEMENTATION_PLAN.md
    mkdir -p "$TEST_DIR/bin"
    # Mock backend that succeeds but never commits
    cat > "$TEST_DIR/bin/claude" <<'MOCK'
#!/usr/bin/env bash
echo '{"type":"result","result":"nothing to do"}'
MOCK
    chmod +x "$TEST_DIR/bin/claude"

    PATH="$TEST_DIR/bin:$PATH" run "$RALPH" build -n 3 --skip-push
    [[ "$status" -eq 0 ]]
    [[ "$output" != *"No changes detected"* ]]
    [[ "$output" == *"Completed 3 iterations"* ]]
}

@test "plan exits on the first pass that changes nothing" {
    "$RALPH" init
    mkdir -p "$TEST_DIR/bin"
    # Plan iterations never commit (IMPLEMENTATION_PLAN.md is gitignored), so
    # convergence is measured against the plan artifacts, not HEAD.
    cat > "$TEST_DIR/bin/claude" <<'MOCK'
#!/usr/bin/env bash
echo '{"type":"result","result":"planning"}'
MOCK
    chmod +x "$TEST_DIR/bin/claude"

    PATH="$TEST_DIR/bin:$PATH" run "$RALPH" plan --skip-push
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"Plan converged — pass 1 changed nothing"* ]]
    [[ "$output" == *"Completed 1 iterations"* ]]
}

@test "plan continues while passes keep changing the plan" {
    "$RALPH" init
    mkdir -p "$TEST_DIR/bin"
    # Appends an item on passes 1 and 2, then goes quiet on pass 3.
    cat > "$TEST_DIR/bin/claude" <<MOCK
#!/usr/bin/env bash
CALL_LOG="$TEST_DIR/call_count"
count=0
[[ -f "\$CALL_LOG" ]] && count=\$(cat "\$CALL_LOG")
count=\$((count + 1))
echo "\$count" > "\$CALL_LOG"
if [[ "\$count" -le 2 ]]; then
    echo "- [ ] **Task \$count**" >> IMPLEMENTATION_PLAN.md
fi
echo '{"type":"result","result":"planning"}'
MOCK
    chmod +x "$TEST_DIR/bin/claude"

    PATH="$TEST_DIR/bin:$PATH" run "$RALPH" plan --skip-push
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"Plan converged — pass 3 changed nothing"* ]]
    [[ "$output" == *"Completed 3 iterations"* ]]
}

@test "plan counts a spec-only edit as progress" {
    "$RALPH" init
    mkdir -p "$TEST_DIR/bin"
    # Touches nothing but specs/ on pass 1. The plan file is unchanged, so this
    # only continues if specs/ is part of the convergence fingerprint.
    cat > "$TEST_DIR/bin/claude" <<MOCK
#!/usr/bin/env bash
CALL_LOG="$TEST_DIR/call_count"
count=0
[[ -f "\$CALL_LOG" ]] && count=\$(cat "\$CALL_LOG")
count=\$((count + 1))
echo "\$count" > "\$CALL_LOG"
if [[ "\$count" -eq 1 ]]; then
    mkdir -p specs
    echo "# New spec" > specs/new-thing.md
fi
echo '{"type":"result","result":"planning"}'
MOCK
    chmod +x "$TEST_DIR/bin/claude"

    PATH="$TEST_DIR/bin:$PATH" run "$RALPH" plan --skip-push
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"Plan converged — pass 2 changed nothing"* ]]
    [[ "$output" == *"Completed 2 iterations"* ]]
}

@test "plan counts an edit to a symlinked spec as progress" {
    "$RALPH" init
    mkdir -p "$TEST_DIR/bin" "$TEST_DIR/external"
    echo "# external spec" > "$TEST_DIR/external/linked.md"
    ln -s "$TEST_DIR/external/linked.md" specs/linked.md
    # find without -L skips symlinks, which would make edits here invisible and
    # let the loop declare convergence while work is still landing.
    cat > "$TEST_DIR/bin/claude" <<MOCK
#!/usr/bin/env bash
CALL_LOG="$TEST_DIR/call_count"
count=0
[[ -f "\$CALL_LOG" ]] && count=\$(cat "\$CALL_LOG")
count=\$((count + 1))
echo "\$count" > "\$CALL_LOG"
if [[ "\$count" -eq 1 ]]; then
    echo "edited on pass 1" >> "$TEST_DIR/external/linked.md"
fi
echo '{"type":"result","result":"planning"}'
MOCK
    chmod +x "$TEST_DIR/bin/claude"

    PATH="$TEST_DIR/bin:$PATH" run "$RALPH" plan --skip-push
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"Plan converged — pass 2 changed nothing"* ]]
}

@test "plan survives an unreadable spec file" {
    [[ "$EUID" -ne 0 ]] || skip "root bypasses file permissions"
    "$RALPH" init
    mkdir -p "$TEST_DIR/bin"
    # A spec the loop cannot read must not abort the run under set -e/pipefail.
    echo "# secret" > specs/unreadable.md
    chmod 000 specs/unreadable.md
    cat > "$TEST_DIR/bin/claude" <<'MOCK'
#!/usr/bin/env bash
echo '{"type":"result","result":"planning"}'
MOCK
    chmod +x "$TEST_DIR/bin/claude"

    PATH="$TEST_DIR/bin:$PATH" run "$RALPH" plan --skip-push
    chmod 644 specs/unreadable.md
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"Plan converged"* ]]
}

@test "plan convergence exit still applies when -n is passed" {
    "$RALPH" init
    mkdir -p "$TEST_DIR/bin"
    # -n caps a plan run but must not disable convergence, unlike build mode.
    cat > "$TEST_DIR/bin/claude" <<'MOCK'
#!/usr/bin/env bash
echo '{"type":"result","result":"planning"}'
MOCK
    chmod +x "$TEST_DIR/bin/claude"

    PATH="$TEST_DIR/bin:$PATH" run "$RALPH" plan -n 12 --skip-push
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"Plan converged — pass 1 changed nothing"* ]]
    [[ "$output" == *"Completed 1 iterations"* ]]
}

@test "plan never pushes even without --skip-push (no remote configured)" {
    "$RALPH" init
    mkdir -p "$TEST_DIR/bin"
    cat > "$TEST_DIR/bin/claude" <<'MOCK'
#!/usr/bin/env bash
echo '{"type":"result","result":"planning"}'
MOCK
    chmod +x "$TEST_DIR/bin/claude"

    # No 'origin' remote exists; if plan attempted a push it would fail.
    PATH="$TEST_DIR/bin:$PATH" run "$RALPH" plan -n 1
    [[ "$status" -eq 0 ]]
    [[ "$output" != *"Push failed"* ]]
    [[ "$output" == *"Completed 1 iteration"* ]]
}
