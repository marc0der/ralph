#!/usr/bin/env bats

load test_helper

FIXTURE="$BATS_TEST_DIRNAME/fixtures/rate-limit-seven-day.jsonl"
FIXTURE_RESET_EPOCH=1787457600

mock_sleep() {
    mkdir -p "$TEST_DIR/bin"
    cat > "$TEST_DIR/bin/sleep" <<MOCK
#!/usr/bin/env bash
echo "\$1" >> "$TEST_DIR/sleep_calls"
exit 0
MOCK
    chmod +x "$TEST_DIR/bin/sleep"
}

mock_date() {
    local frozen_now="$1" real_date
    real_date=$(command -v date)
    mkdir -p "$TEST_DIR/bin"
    cat > "$TEST_DIR/bin/date" <<MOCK
#!/usr/bin/env bash
if [[ "\$1" == "+%s" ]]; then
    echo "$frozen_now"
    exit 0
fi
exec "$real_date" "\$@"
MOCK
    chmod +x "$TEST_DIR/bin/date"
}

mock_claude_always_rate_limited() {
    local exit_code="${1:-1}"
    mkdir -p "$TEST_DIR/bin"
    cat > "$TEST_DIR/bin/claude" <<MOCK
#!/usr/bin/env bash
cat "$FIXTURE"
exit $exit_code
MOCK
    chmod +x "$TEST_DIR/bin/claude"
}

mock_claude_rate_limited_then() {
    local success_body="$1"
    mkdir -p "$TEST_DIR/bin"
    cat > "$TEST_DIR/bin/claude" <<MOCK
#!/usr/bin/env bash
COUNT_FILE="$TEST_DIR/call_count"
count=0
[[ -f "\$COUNT_FILE" ]] && count=\$(cat "\$COUNT_FILE")
count=\$((count + 1))
echo "\$count" > "\$COUNT_FILE"
if [[ "\$count" -eq 1 ]]; then
    cat "$FIXTURE"
    exit 1
fi
$success_body
MOCK
    chmod +x "$TEST_DIR/bin/claude"
}

@test "retries a rate_limit_event from real backend output and succeeds on the next attempt" {
    "$RALPH" init
    mock_sleep
    mock_date $((FIXTURE_RESET_EPOCH - 120))
    mock_claude_rate_limited_then "echo '{\"type\":\"result\",\"result\":\"done after retry\"}'"

    PATH="$TEST_DIR/bin:$PATH" run "$RALPH" build -n 1 --skip-push
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"Rate limited"* ]]
    [[ "$output" == *"attempt 1/5"* ]]
    [[ "$output" == *"done after retry"* ]]
    [[ -f "$TEST_DIR/sleep_calls" ]]
}

@test "waits until the reported resetsAt plus the buffer" {
    "$RALPH" init
    mock_sleep
    mock_date $((FIXTURE_RESET_EPOCH - 120))
    mock_claude_rate_limited_then "echo '{\"type\":\"result\",\"result\":\"done\"}'"

    PATH="$TEST_DIR/bin:$PATH" run "$RALPH" build -n 1 --skip-push
    [[ "$status" -eq 0 ]]
    [[ "$(sed -n '1p' "$TEST_DIR/sleep_calls")" -eq 150 ]]
}

@test "fails without retrying when the wait to resetsAt exceeds the maximum" {
    "$RALPH" init
    mock_sleep
    mock_date $((FIXTURE_RESET_EPOCH - 21600))
    mock_claude_always_rate_limited 3

    PATH="$TEST_DIR/bin:$PATH" run "$RALPH" build -n 1 --skip-push
    [[ "$status" -eq 3 ]]
    [[ "$output" == *"exceeds maximum allowed wait"* ]]
    [[ ! -f "$TEST_DIR/sleep_calls" ]]
}

@test "a failure carrying no rate_limit_event is not retried" {
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
    [[ "$output" == *"Did not detect a rate limited error"* ]]
    [[ "$output" != *"Rate limited"* ]]
    [[ ! -f "$TEST_DIR/sleep_calls" ]]
}

@test "rate-limit wording on stderr alone is not treated as a rate limit" {
    "$RALPH" init
    mock_sleep
    mkdir -p "$TEST_DIR/bin"
    cat > "$TEST_DIR/bin/claude" <<'MOCK'
#!/usr/bin/env bash
echo "Claude AI usage limit reached|9999999999" >&2
exit 1
MOCK
    chmod +x "$TEST_DIR/bin/claude"

    PATH="$TEST_DIR/bin:$PATH" run "$RALPH" build -n 1 --skip-push
    [[ "$status" -eq 1 ]]
    [[ "$output" == *"usage limit reached"* ]]
    [[ "$output" == *"Did not detect a rate limited error"* ]]
    [[ ! -f "$TEST_DIR/sleep_calls" ]]
}

@test "non-JSON backend output fails cleanly without a jq parse error" {
    "$RALPH" init
    mock_sleep
    mkdir -p "$TEST_DIR/bin"
    cat > "$TEST_DIR/bin/claude" <<'MOCK'
#!/usr/bin/env bash
echo "Segmentation fault"
exit 139
MOCK
    chmod +x "$TEST_DIR/bin/claude"

    PATH="$TEST_DIR/bin:$PATH" run "$RALPH" build -n 1 --skip-push
    [[ "$status" -eq 139 ]]
    [[ "$output" == *"Did not detect a rate limited error"* ]]
    [[ "$output" != *"parse error"* ]]
    [[ "$output" != *"jq:"* ]]
    [[ ! -f "$TEST_DIR/sleep_calls" ]]
}

@test "fails after exhausting max-retries when the limit keeps recurring" {
    "$RALPH" init
    mock_sleep
    mock_date $((FIXTURE_RESET_EPOCH - 120))
    mock_claude_always_rate_limited

    PATH="$TEST_DIR/bin:$PATH" run "$RALPH" build -n 1 --skip-push --max-retries-per-iteration 2
    [[ "$status" -eq 1 ]]
    [[ "$output" == *"attempt 1/2"* ]]
    [[ "$output" == *"attempt 2/2"* ]]
    [[ "$output" == *"exhausted 2 retries"* ]]
    [[ "$(wc -l < "$TEST_DIR/sleep_calls")" -eq 2 ]]
}

@test "--no-retry fails immediately on a rate_limit_event" {
    "$RALPH" init
    mock_sleep
    mock_date $((FIXTURE_RESET_EPOCH - 120))
    mock_claude_always_rate_limited

    PATH="$TEST_DIR/bin:$PATH" run "$RALPH" build -n 1 --skip-push --no-retry
    [[ "$status" -eq 1 ]]
    [[ "$output" != *"⏸"* ]]
    [[ "$output" == *"retries are disabled"* ]]
    [[ ! -f "$TEST_DIR/sleep_calls" ]]
}

@test "--max-retries-per-iteration 0 behaves like --no-retry" {
    "$RALPH" init
    mock_sleep
    mock_date $((FIXTURE_RESET_EPOCH - 120))
    mock_claude_always_rate_limited

    PATH="$TEST_DIR/bin:$PATH" run "$RALPH" build -n 1 --skip-push --max-retries-per-iteration 0
    [[ "$status" -eq 1 ]]
    [[ "$output" == *"retries are disabled"* ]]
    [[ ! -f "$TEST_DIR/sleep_calls" ]]
}

@test "a failed-then-retried iteration does not push or advance past the retry" {
    "$RALPH" init
    mock_sleep
    mock_date $((FIXTURE_RESET_EPOCH - 120))
    mock_claude_rate_limited_then "git commit --allow-empty -m 'work done' --quiet
echo '{\"type\":\"result\",\"result\":\"done\"}'"

    PATH="$TEST_DIR/bin:$PATH" run "$RALPH" build -n 1 --skip-push
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"Completed 1 iteration"* ]]
    [[ "$(git log --oneline | wc -l)" -eq 2 ]]
}

@test "prints the raw backend output and hint on a rate-limit failure without --verbose" {
    "$RALPH" init
    mock_sleep
    mock_date $((FIXTURE_RESET_EPOCH - 120))
    mock_claude_always_rate_limited

    PATH="$TEST_DIR/bin:$PATH" run "$RALPH" build -n 1 --skip-push --no-retry
    [[ "$output" == *"Error: backend command failed on iteration 1 (exit code 1)"* ]]
    [[ "$output" == *"Raw backend output:"* ]]
    [[ "$output" == *"rate_limit_event"* ]]
    [[ "$output" == *"Hint: re-run with --dry-run"* ]]
}

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
