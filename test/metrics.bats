#!/usr/bin/env bats

load test_helper

# Helper: install a mock claude that emits stream-json, commits a file and
# ticks the first incomplete plan item.
create_committing_backend() {
    mkdir -p "$TEST_DIR/bin"
    cat > "$TEST_DIR/bin/claude" <<'MOCK'
#!/usr/bin/env bash
cat > /dev/null
echo '{"type":"assistant","message":{"content":[{"type":"tool_use","id":"t1","name":"Read","input":{}}]}}'
echo '{"type":"assistant","message":{"content":[{"type":"tool_use","id":"t2","name":"Bash","input":{}}]}}'
echo '{"type":"assistant","message":{"content":[{"type":"tool_use","id":"t3","name":"Bash","input":{}}]}}'
echo "work $RANDOM" >> src.txt
git add src.txt >/dev/null 2>&1
git commit -q -m "mock work"
sed -i.bak '1s/- \[ \]/- [x]/' IMPLEMENTATION_PLAN.md 2>/dev/null && rm -f IMPLEMENTATION_PLAN.md.bak
echo '{"type":"result","subtype":"success","duration_ms":8000,"duration_api_ms":6500,"num_turns":12,"result":"Done.","session_id":"s1","total_cost_usd":1.25,"usage":{"input_tokens":2500,"cache_creation_input_tokens":40000,"cache_read_input_tokens":350000,"output_tokens":8200}}'
MOCK
    chmod +x "$TEST_DIR/bin/claude"
}

# Helper: mock claude that emits a result event but changes nothing.
create_noop_backend() {
    mkdir -p "$TEST_DIR/bin"
    cat > "$TEST_DIR/bin/claude" <<'MOCK'
#!/usr/bin/env bash
cat > /dev/null
echo '{"type":"result","subtype":"success","duration_ms":500,"duration_api_ms":400,"num_turns":2,"result":"Nothing to do.","session_id":"s2","total_cost_usd":0.01,"usage":{"input_tokens":10,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":5}}'
MOCK
    chmod +x "$TEST_DIR/bin/claude"
}

latest_metrics_file() {
    # shellcheck disable=SC2012  # newest-by-mtime needs ls; paths are ralph-generated (no odd filenames)
    ls -1t .ralph/metrics/*/metrics.jsonl | head -1
}

@test "build records one metrics line per iteration" {
    "$RALPH" init
    printf -- '- [ ] one\n- [ ] two\n- [ ] three\n' > IMPLEMENTATION_PLAN.md
    create_committing_backend

    PATH="$TEST_DIR/bin:$PATH" run "$RALPH" build -n 2 --skip-push -y
    [[ "$status" -eq 0 ]]

    local f
    f=$(latest_metrics_file)
    [[ -f "$f" ]]
    [[ $(wc -l < "$f") -eq 2 ]]
}

@test "metrics line contains result-event and git fields" {
    "$RALPH" init
    printf -- '- [ ] one\n- [ ] two\n' > IMPLEMENTATION_PLAN.md
    create_committing_backend

    PATH="$TEST_DIR/bin:$PATH" "$RALPH" build -n 1 --skip-push -y

    local f line
    f=$(latest_metrics_file)
    line=$(tail -1 "$f")
    [[ $(jq -r '.turns' <<<"$line") == "12" ]]
    [[ $(jq -r '.cost_usd' <<<"$line") == "1.25" ]]
    [[ $(jq -r '.tokens.cache_read' <<<"$line") == "350000" ]]
    [[ $(jq -r '.git.commits' <<<"$line") == "1" ]]
    [[ $(jq -r '.git.noop' <<<"$line") == "false" ]]
    [[ $(jq -r '.plan_items_completed' <<<"$line") == "1" ]]
    [[ $(jq -r '.tools.Bash' <<<"$line") == "2" ]]
    [[ $(jq -r '.mode' <<<"$line") == "build" ]]
}

@test "raw stream is retained per iteration" {
    "$RALPH" init
    printf -- '- [ ] one\n- [ ] two\n' > IMPLEMENTATION_PLAN.md
    create_committing_backend

    PATH="$TEST_DIR/bin:$PATH" "$RALPH" build -n 1 --skip-push -y

    local dir
    dir=$(dirname "$(latest_metrics_file)")
    [[ -f "$dir/iter-001.stream.jsonl" ]]
    grep -q '"type":"result"' "$dir/iter-001.stream.jsonl"
}

@test "noop iteration is recorded with noop=true and zero commits" {
    "$RALPH" init
    printf -- '- [ ] one\n' > IMPLEMENTATION_PLAN.md
    create_noop_backend

    PATH="$TEST_DIR/bin:$PATH" "$RALPH" build -n 1 --skip-push -y

    local line
    line=$(tail -1 "$(latest_metrics_file)")
    [[ $(jq -r '.git.noop' <<<"$line") == "true" ]]
    [[ $(jq -r '.git.commits' <<<"$line") == "0" ]]
}

@test "plan iteration that edits the plan records noop=false" {
    "$RALPH" init
    mkdir -p "$TEST_DIR/bin"
    # Plan mode never commits, so the noop flag must come from the plan
    # artifacts rather than from HEAD.
    cat > "$TEST_DIR/bin/claude" <<'MOCK'
#!/usr/bin/env bash
cat > /dev/null
echo "- [ ] **Task one**" >> IMPLEMENTATION_PLAN.md
echo '{"type":"result","subtype":"success","duration_ms":500,"duration_api_ms":400,"num_turns":2,"result":"Planned.","session_id":"s3","total_cost_usd":0.01,"usage":{"input_tokens":10,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":5}}'
MOCK
    chmod +x "$TEST_DIR/bin/claude"

    PATH="$TEST_DIR/bin:$PATH" "$RALPH" plan -n 1 --skip-push -y

    local line
    line=$(tail -1 "$(latest_metrics_file)")
    [[ $(jq -r '.mode' <<<"$line") == "plan" ]]
    [[ $(jq -r '.git.noop' <<<"$line") == "false" ]]
    [[ $(jq -r '.git.commits' <<<"$line") == "0" ]]
}

@test "plan iteration that changes nothing records noop=true" {
    "$RALPH" init
    # One item present: a converging pass against an empty plan is a planning
    # failure and exits before metrics assert anything.
    printf -- '- [ ] **Seeded item** — x. → [001-x.md](plan/001-x.md)\n' >> IMPLEMENTATION_PLAN.md
    create_noop_backend

    PATH="$TEST_DIR/bin:$PATH" "$RALPH" plan -n 1 --skip-push -y

    local line
    line=$(tail -1 "$(latest_metrics_file)")
    [[ $(jq -r '.mode' <<<"$line") == "plan" ]]
    [[ $(jq -r '.git.noop' <<<"$line") == "true" ]]
}

@test "degraded backend output still records a metrics line with nulls" {
    "$RALPH" init
    printf -- '- [ ] one\n' > IMPLEMENTATION_PLAN.md
    mkdir -p "$TEST_DIR/bin"
    cat > "$TEST_DIR/bin/claude" <<'MOCK'
#!/usr/bin/env bash
cat > /dev/null
echo '{"type":"result","result":"bare"}'
MOCK
    chmod +x "$TEST_DIR/bin/claude"

    PATH="$TEST_DIR/bin:$PATH" run "$RALPH" build -n 1 --skip-push -y
    [[ "$status" -eq 0 ]]

    local line
    line=$(tail -1 "$(latest_metrics_file)")
    [[ $(jq -r '.turns' <<<"$line") == "null" ]]
    [[ $(jq -r '.cost_usd' <<<"$line") == "null" ]]
    [[ $(jq -r '.git.commits' <<<"$line") == "0" ]]
}

@test "--no-metrics disables capture" {
    "$RALPH" init
    printf -- '- [ ] one\n' > IMPLEMENTATION_PLAN.md
    create_noop_backend

    PATH="$TEST_DIR/bin:$PATH" run "$RALPH" build -n 1 --skip-push -y --no-metrics
    [[ "$status" -eq 0 ]]
    [[ ! -d ".ralph/metrics" ]]
}

@test "dry-run does not create metrics" {
    "$RALPH" init
    printf -- '- [ ] one\n' > IMPLEMENTATION_PLAN.md

    run "$RALPH" build -n 1 --dry-run
    [[ "$status" -eq 0 ]]
    [[ ! -d ".ralph/metrics" ]]
}

@test "plan mode records metrics" {
    "$RALPH" init
    printf -- '- [ ] one\n' > IMPLEMENTATION_PLAN.md
    create_noop_backend

    PATH="$TEST_DIR/bin:$PATH" "$RALPH" plan -n 1 -y

    local line
    line=$(tail -1 "$(latest_metrics_file)")
    [[ $(jq -r '.mode' <<<"$line") == "plan" ]]
    [[ $(jq -r '.turns' <<<"$line") == "2" ]]
}

@test "loop output includes a per-iteration metrics summary line" {
    "$RALPH" init
    printf -- '- [ ] one\n- [ ] two\n' > IMPLEMENTATION_PLAN.md
    create_committing_backend

    PATH="$TEST_DIR/bin:$PATH" run "$RALPH" build -n 1 --skip-push -y
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"12 turns"* ]]
    [[ "$output" == *"1 commits"* ]]
    [[ "$output" == *"Metrics recorded:"* ]]
}

@test "ralph metrics summarises the latest run" {
    "$RALPH" init
    printf -- '- [ ] one\n- [ ] two\n- [ ] three\n' > IMPLEMENTATION_PLAN.md
    create_committing_backend

    PATH="$TEST_DIR/bin:$PATH" "$RALPH" build -n 2 --skip-push -y

    run "$RALPH" metrics
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"2 iterations"* ]]
    [[ "$output" == *"cost \$2.5"* ]]
    [[ "$output" == *"commits 2"* ]]
}

@test "ralph metrics with no runs errors helpfully" {
    "$RALPH" init
    run "$RALPH" metrics
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"No metrics found"* ]]
}

@test "metrics failure does not fail the loop" {
    "$RALPH" init
    printf -- '- [ ] one\n' > IMPLEMENTATION_PLAN.md
    create_noop_backend

    # Uncreatable metrics dir (a file squats on the path — robust even when
    # tests run as root, where chmod-based denial doesn't bite): capture must
    # disable itself with a warning and the loop must still run to completion.
    mkdir -p .ralph
    touch .ralph/metrics

    PATH="$TEST_DIR/bin:$PATH" run "$RALPH" build -n 1 --skip-push -y
    rm -f .ralph/metrics

    [[ "$status" -eq 0 ]]
    [[ "$output" == *"metrics disabled for this run"* ]]
    [[ "$output" == *"Nothing to do."* ]]
}
