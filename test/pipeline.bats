#!/usr/bin/env bats

load test_helper

# Give the plan one item so a converging pass is treated as convergence rather
# than as the empty-plan failure. Tests that are about what the fingerprint
# covers, or about flags, need an item present so that check never fires and
# masks what they actually assert.
seed_plan_item() {
    printf -- '- [ ] **Seeded item** — x. → [001-x.md](plan/001-x.md)\n' >> IMPLEMENTATION_PLAN.md
}

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
    # An item to converge on: an empty plan that changes nothing is a planning
    # failure, not convergence (see the empty-plan tests below).
    printf -- '- [ ] **Existing item** — x. → [001-x.md](plan/001-x.md)\n' >> IMPLEMENTATION_PLAN.md
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

# A backend that answers without planning — "the plan looks complete to me" —
# leaves the fingerprint unchanged against an empty plan. That is
# indistinguishable from real convergence by the hash alone, and reporting it as
# success exits 0 with nothing for 'ralph build' to pick up.
@test "plan fails when it converges on an empty plan" {
    "$RALPH" init
    mkdir -p "$TEST_DIR/bin"
    cat > "$TEST_DIR/bin/claude" <<'MOCK'
#!/usr/bin/env bash
echo '{"type":"result","subtype":"success","result":"The plan looks complete to me."}'
MOCK
    chmod +x "$TEST_DIR/bin/claude"

    PATH="$TEST_DIR/bin:$PATH" run "$RALPH" plan --skip-push
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"holds no items"* ]]
    [[ "$output" != *"Plan converged"* ]]
}

# The counterpart: every item shipped is a finished plan, not a failed one, so
# the check counts entries of any marker rather than open ones.
@test "plan converges on a plan whose items are all shipped" {
    "$RALPH" init
    printf -- '- [x] **Shipped** — done. → [001-x.md](plan/001-x.md)\n' >> IMPLEMENTATION_PLAN.md
    mkdir -p "$TEST_DIR/bin"
    cat > "$TEST_DIR/bin/claude" <<'MOCK'
#!/usr/bin/env bash
echo '{"type":"result","result":"no gaps found"}'
MOCK
    chmod +x "$TEST_DIR/bin/claude"

    PATH="$TEST_DIR/bin:$PATH" run "$RALPH" plan --skip-push
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"Plan converged"* ]]
}

# The empty-plan check must not fire when a pass is still doing work: a run that
# writes its first item on pass 2 has to survive pass 1.
@test "plan continues to a later pass that writes the first item" {
    "$RALPH" init
    mkdir -p "$TEST_DIR/bin"
    cat > "$TEST_DIR/bin/claude" <<MOCK
#!/usr/bin/env bash
CALL_LOG="$TEST_DIR/call_count"
count=0
[[ -f "\$CALL_LOG" ]] && count=\$(cat "\$CALL_LOG")
count=\$((count + 1))
echo "\$count" > "\$CALL_LOG"
if [[ "\$count" -eq 1 ]]; then
    mkdir -p specs && echo "# researched" > specs/notes.md
elif [[ "\$count" -eq 2 ]]; then
    echo '- [ ] **First real item** — x. → [001-x.md](plan/001-x.md)' >> IMPLEMENTATION_PLAN.md
fi
echo '{"type":"result","result":"planning"}'
MOCK
    chmod +x "$TEST_DIR/bin/claude"

    PATH="$TEST_DIR/bin:$PATH" run "$RALPH" plan --skip-push
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"Plan converged — pass 3 changed nothing"* ]]
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
    seed_plan_item
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

@test "plan counts a task-file-only edit as progress" {
    "$RALPH" init
    seed_plan_item
    mkdir -p "$TEST_DIR/bin"
    # The index is one line per item, so a pass that refines an item's scope or
    # steps rewrites its plan/ task file and nothing else. Fingerprinting the
    # index alone would read that as convergence and stop the run mid-plan.
    printf -- '- [ ] **A** — do a thing. → [001-a.md](plan/001-a.md)\n' >> IMPLEMENTATION_PLAN.md
    printf '# 001. A\n\n**Status:** Not started\n\n## Scope\n\nOriginal scope.\n' > plan/001-a.md
    cat > "$TEST_DIR/bin/claude" <<MOCK
#!/usr/bin/env bash
CALL_LOG="$TEST_DIR/call_count"
count=0
[[ -f "\$CALL_LOG" ]] && count=\$(cat "\$CALL_LOG")
count=\$((count + 1))
echo "\$count" > "\$CALL_LOG"
if [[ "\$count" -eq 1 ]]; then
    printf '# 001. A\n\n**Status:** Not started\n\n## Scope\n\nRevised scope.\n' > plan/001-a.md
fi
echo '{"type":"result","result":"planning"}'
MOCK
    chmod +x "$TEST_DIR/bin/claude"

    PATH="$TEST_DIR/bin:$PATH" run "$RALPH" plan --skip-push
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"Plan converged — pass 2 changed nothing"* ]]
    [[ "$output" == *"Completed 2 iterations"* ]]
}

@test "plan counts a new task file as progress" {
    "$RALPH" init
    seed_plan_item
    mkdir -p "$TEST_DIR/bin"
    # Names as well as contents: adding a task file must count even before the
    # index entry that links to it lands.
    cat > "$TEST_DIR/bin/claude" <<MOCK
#!/usr/bin/env bash
CALL_LOG="$TEST_DIR/call_count"
count=0
[[ -f "\$CALL_LOG" ]] && count=\$(cat "\$CALL_LOG")
count=\$((count + 1))
echo "\$count" > "\$CALL_LOG"
if [[ "\$count" -eq 1 ]]; then
    mkdir -p plan
    echo '# 002. New' > plan/002-new.md
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
    seed_plan_item
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
    seed_plan_item
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
    seed_plan_item
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
    seed_plan_item
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
