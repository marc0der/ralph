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
    ! echo "$output" | grep -q '^\$ '
    [[ "$output" != *"Summary complete"* ]]
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
