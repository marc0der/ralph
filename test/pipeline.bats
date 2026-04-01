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

@test "codex jq filter handles no agent_message events gracefully" {
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
