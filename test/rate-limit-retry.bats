#!/usr/bin/env bats

load test_helper

# Mocks `sleep` so retry tests run instantly instead of actually waiting.
# Each call's requested duration is appended to $TEST_DIR/sleep_calls.
mock_sleep() {
    mkdir -p "$TEST_DIR/bin"
    cat > "$TEST_DIR/bin/sleep" <<MOCK
#!/usr/bin/env bash
echo "\$1" >> "$TEST_DIR/sleep_calls"
exit 0
MOCK
    chmod +x "$TEST_DIR/bin/sleep"
}

# --- Rate-limit detection (with a parseable reset time) triggers a retry ---

@test "retries a rate-limit failure with a reset time and succeeds on the next attempt" {
    "$RALPH" init
    mock_sleep
    mkdir -p "$TEST_DIR/bin"
    cat > "$TEST_DIR/bin/claude" <<MOCK
#!/usr/bin/env bash
COUNT_FILE="$TEST_DIR/call_count"
count=0
[[ -f "\$COUNT_FILE" ]] && count=\$(cat "\$COUNT_FILE")
count=\$((count + 1))
echo "\$count" > "\$COUNT_FILE"
if [[ "\$count" -eq 1 ]]; then
    reset_epoch=\$(( \$(date +%s) + 5 ))
    echo "Claude AI usage limit reached|\$reset_epoch" >&2
    exit 1
fi
echo '{"type":"result","result":"done after retry"}'
MOCK
    chmod +x "$TEST_DIR/bin/claude"

    PATH="$TEST_DIR/bin:$PATH" run "$RALPH" build -n 1 --skip-push
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"Rate limited"* ]]
    [[ "$output" == *"attempt 1/5"* ]]
    [[ "$output" == *"done after retry"* ]]
    [[ -f "$TEST_DIR/sleep_calls" ]]
}

@test "detects rate_limit_error on stdout, not just stderr" {
    "$RALPH" init
    mock_sleep
    mkdir -p "$TEST_DIR/bin"
    cat > "$TEST_DIR/bin/claude" <<MOCK
#!/usr/bin/env bash
COUNT_FILE="$TEST_DIR/call_count"
count=0
[[ -f "\$COUNT_FILE" ]] && count=\$(cat "\$COUNT_FILE")
count=\$((count + 1))
echo "\$count" > "\$COUNT_FILE"
if [[ "\$count" -eq 1 ]]; then
    reset_epoch=\$(( \$(date +%s) + 5 ))
    echo "{\"type\":\"error\",\"error\":{\"type\":\"rate_limit_error\",\"message\":\"Please try again later.|\$reset_epoch\"}}"
    exit 1
fi
echo '{"type":"result","result":"done"}'
MOCK
    chmod +x "$TEST_DIR/bin/claude"

    PATH="$TEST_DIR/bin:$PATH" run "$RALPH" build -n 1 --skip-push
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"Rate limited"* ]]
}

# --- No blind exponential backoff: an unparseable reset time fails loudly ---

@test "fails immediately (no retry) when rate-limited but no reset time can be parsed" {
    "$RALPH" init
    mock_sleep
    mkdir -p "$TEST_DIR/bin"
    cat > "$TEST_DIR/bin/claude" <<'MOCK'
#!/usr/bin/env bash
echo "rate limit hit, no reset time given" >&2
exit 1
MOCK
    chmod +x "$TEST_DIR/bin/claude"

    PATH="$TEST_DIR/bin:$PATH" run "$RALPH" build -n 1 --skip-push
    [[ "$status" -eq 1 ]]
    [[ "$output" == *"no reset time could be parsed"* ]]
    [[ ! -f "$TEST_DIR/sleep_calls" ]]
}

# --- Backoff strategy: honours the reported reset time ---

@test "honours a reported reset epoch when computing the wait" {
    "$RALPH" init
    mock_sleep
    mkdir -p "$TEST_DIR/bin"
    cat > "$TEST_DIR/bin/claude" <<MOCK
#!/usr/bin/env bash
COUNT_FILE="$TEST_DIR/call_count"
count=0
[[ -f "\$COUNT_FILE" ]] && count=\$(cat "\$COUNT_FILE")
count=\$((count + 1))
echo "\$count" > "\$COUNT_FILE"
if [[ "\$count" -eq 1 ]]; then
    reset_epoch=\$(( \$(date +%s) + 120 ))
    echo "Claude AI usage limit reached|\$reset_epoch" >&2
    exit 1
fi
echo '{"type":"result","result":"done"}'
MOCK
    chmod +x "$TEST_DIR/bin/claude"

    PATH="$TEST_DIR/bin:$PATH" run "$RALPH" build -n 1 --skip-push
    [[ "$status" -eq 0 ]]
    local waited
    waited=$(sed -n '1p' "$TEST_DIR/sleep_calls")
    # ~120s until reset + 30s buffer, with slack for test execution drift
    [[ "$waited" -ge 130 ]]
    [[ "$waited" -le 170 ]]
}

# --- Exhausting retries still fails, even though every attempt had a valid reset time ---

@test "fails after exhausting max-retries when the limit keeps recurring with a fresh reset time" {
    "$RALPH" init
    mock_sleep
    mkdir -p "$TEST_DIR/bin"
    cat > "$TEST_DIR/bin/claude" <<'MOCK'
#!/usr/bin/env bash
reset_epoch=$(( $(date +%s) + 5 ))
echo "Claude AI usage limit reached|$reset_epoch" >&2
exit 1
MOCK
    chmod +x "$TEST_DIR/bin/claude"

    PATH="$TEST_DIR/bin:$PATH" run "$RALPH" build -n 1 --skip-push --max-retries-per-iteration 2
    [[ "$status" -eq 1 ]]
    [[ "$output" == *"attempt 1/2"* ]]
    [[ "$output" == *"attempt 2/2"* ]]
    [[ "$output" == *"exhausted 2 retries"* ]]
    [[ "$(wc -l < "$TEST_DIR/sleep_calls")" -eq 2 ]]
}

# --- Never skip a plan item: no jq/push/noop processing on a retried iteration ---

@test "a failed-then-retried iteration does not push or advance past the retry" {
    "$RALPH" init
    mock_sleep
    mkdir -p "$TEST_DIR/bin"
    cat > "$TEST_DIR/bin/claude" <<MOCK
#!/usr/bin/env bash
COUNT_FILE="$TEST_DIR/call_count"
count=0
[[ -f "\$COUNT_FILE" ]] && count=\$(cat "\$COUNT_FILE")
count=\$((count + 1))
echo "\$count" > "\$COUNT_FILE"
if [[ "\$count" -eq 1 ]]; then
    reset_epoch=\$(( \$(date +%s) + 5 ))
    echo "usage limit reached|\$reset_epoch" >&2
    exit 1
fi
git commit --allow-empty -m "work done" --quiet
echo '{"type":"result","result":"done"}'
MOCK
    chmod +x "$TEST_DIR/bin/claude"

    PATH="$TEST_DIR/bin:$PATH" run "$RALPH" build -n 1 --skip-push
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"Completed 1 iteration"* ]]
    # Only one commit exists beyond the initial one — the retried attempt
    # succeeded exactly once, the failed attempt left no trace.
    local commit_count
    commit_count=$(git log --oneline | wc -l)
    [[ "$commit_count" -eq 2 ]]
}

# --- --no-retry / --max-retries-per-iteration 0 disable the mechanism entirely ---

@test "--no-retry fails immediately even on a rate-limit failure with a valid reset time" {
    "$RALPH" init
    mock_sleep
    mkdir -p "$TEST_DIR/bin"
    cat > "$TEST_DIR/bin/claude" <<'MOCK'
#!/usr/bin/env bash
echo "Claude AI usage limit reached|9999999999" >&2
exit 1
MOCK
    chmod +x "$TEST_DIR/bin/claude"

    PATH="$TEST_DIR/bin:$PATH" run "$RALPH" build -n 1 --skip-push --no-retry
    [[ "$status" -eq 1 ]]
    [[ "$output" != *"⏸"* ]]
    [[ "$output" == *"retries are disabled"* ]]
    [[ ! -f "$TEST_DIR/sleep_calls" ]]
}

@test "--max-retries-per-iteration 0 behaves like --no-retry" {
    "$RALPH" init
    mock_sleep
    mkdir -p "$TEST_DIR/bin"
    cat > "$TEST_DIR/bin/claude" <<'MOCK'
#!/usr/bin/env bash
echo "usage limit reached|9999999999" >&2
exit 1
MOCK
    chmod +x "$TEST_DIR/bin/claude"

    PATH="$TEST_DIR/bin:$PATH" run "$RALPH" build -n 1 --skip-push --max-retries-per-iteration 0
    [[ "$status" -eq 1 ]]
    [[ "$output" == *"retries are disabled"* ]]
    [[ ! -f "$TEST_DIR/sleep_calls" ]]
}

# --- Genuine failures are unaffected ---

@test "genuine failure (not rate-limited) fails immediately without retry" {
    "$RALPH" init
    mock_sleep
    mkdir -p "$TEST_DIR/bin"
    cat > "$TEST_DIR/bin/claude" <<'MOCK'
#!/usr/bin/env bash
echo '{"type":"result","subtype":"error_during_execution","is_error":true}'
exit 1
MOCK
    chmod +x "$TEST_DIR/bin/claude"

    PATH="$TEST_DIR/bin:$PATH" run "$RALPH" build -n 1 --skip-push
    [[ "$status" -eq 1 ]]
    [[ "$output" != *"Rate limited"* ]]
    [[ ! -f "$TEST_DIR/sleep_calls" ]]
    # The raw output is now shown on failure even without --verbose.
    [[ "$output" == *"error_during_execution"* ]]
}

# --- Flag validation and help text ---

@test "--max-retries-per-iteration rejects a non-numeric value" {
    "$RALPH" init
    run "$RALPH" build --dry-run -n 1 --max-retries-per-iteration abc
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"--max-retries-per-iteration must be"* ]]
}

@test "help text documents --max-retries-per-iteration and --no-retry" {
    run "$RALPH" --help
    [[ "$output" == *"--max-retries-per-iteration"* ]]
    [[ "$output" == *"--no-retry"* ]]
}
