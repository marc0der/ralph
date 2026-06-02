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

@test "plan runs full iteration count even when no commits occur" {
    "$RALPH" init
    mkdir -p "$TEST_DIR/bin"
    # Plan iterations never commit (IMPLEMENTATION_PLAN.md is gitignored),
    # so noop detection must not apply in plan mode.
    cat > "$TEST_DIR/bin/claude" <<'MOCK'
#!/usr/bin/env bash
echo '{"type":"result","result":"planning"}'
MOCK
    chmod +x "$TEST_DIR/bin/claude"

    PATH="$TEST_DIR/bin:$PATH" run "$RALPH" plan --skip-push
    [[ "$status" -eq 0 ]]
    [[ "$output" != *"No changes detected"* ]]
    [[ "$output" == *"Completed 3 iterations"* ]]
}
