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
    ls -1t .ralph/logs/*/*/metrics.jsonl | head -1
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

@test "a standalone build writes its phase folder under .ralph/logs" {
    "$RALPH" init
    printf -- '- [ ] one\n- [ ] two\n' > IMPLEMENTATION_PLAN.md
    create_committing_backend

    PATH="$TEST_DIR/bin:$PATH" run "$RALPH" build -n 1 --skip-push -y
    [[ "$status" -eq 0 ]]

    local folders=(.ralph/logs/*/build)
    [[ ${#folders[@]} -eq 1 ]]
    [[ -d "${folders[0]}" ]]
    [[ -f "${folders[0]}/metrics.jsonl" ]]
    [[ -f "${folders[0]}/iter-001.stream.jsonl" ]]
    [[ "$output" == *"Metrics recorded: ${folders[0]}/metrics.jsonl"* ]]
}

@test "fix writes its phase folder under fix" {
    "$RALPH" init
    printf -- '- [ ] one\n- [ ] two\n' > IMPLEMENTATION_PLAN.md
    create_committing_backend

    PATH="$TEST_DIR/bin:$PATH" run "$RALPH" fix -n 1 --skip-push -y
    [[ "$status" -eq 0 ]]

    local fixes=(.ralph/logs/*/fix)
    [[ ${#fixes[@]} -eq 1 ]]
    [[ -f "${fixes[0]}/metrics.jsonl" ]]
    local builds=(.ralph/logs/*/build)
    [[ ! -e "${builds[0]}" ]]
}

@test "RALPH_RUN_DIR naming a directory receives the phase folder and no other run is created" {
    "$RALPH" init
    printf -- '- [ ] one\n- [ ] two\n' > IMPLEMENTATION_PLAN.md
    create_committing_backend
    mkdir -p .ralph/logs/given

    RALPH_RUN_DIR=.ralph/logs/given PATH="$TEST_DIR/bin:$PATH" run "$RALPH" build -n 1 --skip-push -y
    [[ "$status" -eq 0 ]]

    [[ -f .ralph/logs/given/build/metrics.jsonl ]]
    [[ -f .ralph/logs/given/build/iter-001.stream.jsonl ]]
    [[ "$(ls .ralph/logs)" == "given" ]]
}

@test "the backend does not see RALPH_RUN_DIR" {
    "$RALPH" init
    printf -- '- [ ] one\n' > IMPLEMENTATION_PLAN.md
    mkdir -p "$TEST_DIR/bin" .ralph/logs/given
    cat > "$TEST_DIR/bin/claude" <<'MOCK'
#!/usr/bin/env bash
cat > /dev/null
echo "${RALPH_RUN_DIR-unset}" > "$TEST_DIR/backend-env"
echo '{"type":"result","subtype":"success","duration_ms":500,"duration_api_ms":400,"num_turns":2,"result":"Nothing to do.","session_id":"s2","total_cost_usd":0.01,"usage":{"input_tokens":10,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":5}}'
MOCK
    chmod +x "$TEST_DIR/bin/claude"

    export TEST_DIR
    RALPH_RUN_DIR=.ralph/logs/given PATH="$TEST_DIR/bin:$PATH" run "$RALPH" build -n 1 --skip-push -y
    [[ "$status" -eq 0 ]]

    [[ "$(cat "$TEST_DIR/backend-env")" == "unset" ]]
}

@test "RALPH_RUN_DIR naming a missing path falls back to one new run" {
    "$RALPH" init
    printf -- '- [ ] one\n- [ ] two\n' > IMPLEMENTATION_PLAN.md
    create_committing_backend

    RALPH_RUN_DIR=.ralph/logs/missing PATH="$TEST_DIR/bin:$PATH" run "$RALPH" build -n 1 --skip-push -y
    [[ "$status" -eq 0 ]]

    [[ ! -e .ralph/logs/missing ]]
    local runs=(.ralph/logs/*)
    [[ ${#runs[@]} -eq 1 ]]
    [[ -f "${runs[0]}/build/metrics.jsonl" ]]
}

@test "a second run into one phase folder continues the record and stream numbers" {
    "$RALPH" init
    printf -- '- [ ] one\n- [ ] two\n' > IMPLEMENTATION_PLAN.md
    create_committing_backend
    mkdir -p .ralph/logs/given

    RALPH_RUN_DIR=.ralph/logs/given PATH="$TEST_DIR/bin:$PATH" run "$RALPH" build -n 1 --skip-push -y
    [[ "$status" -eq 0 ]]
    RALPH_RUN_DIR=.ralph/logs/given PATH="$TEST_DIR/bin:$PATH" run "$RALPH" build -n 1 --skip-push -y
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"ITERATION 1 / 1"* ]]

    [[ "$(jq -r '.iteration' .ralph/logs/given/build/metrics.jsonl | paste -sd,)" == "1,2" ]]
    [[ -f .ralph/logs/given/build/iter-001.stream.jsonl ]]
    [[ -f .ralph/logs/given/build/iter-002.stream.jsonl ]]
}

@test "a lone stream file numbers the next record one past it" {
    "$RALPH" init
    printf -- '- [ ] one\n- [ ] two\n' > IMPLEMENTATION_PLAN.md
    create_committing_backend
    mkdir -p .ralph/logs/given/build
    : > .ralph/logs/given/build/iter-005.stream.jsonl

    RALPH_RUN_DIR=.ralph/logs/given PATH="$TEST_DIR/bin:$PATH" run "$RALPH" build -n 1 --skip-push -y
    [[ "$status" -eq 0 ]]

    [[ "$(jq -r '.iteration' .ralph/logs/given/build/metrics.jsonl)" == "6" ]]
    [[ -f .ralph/logs/given/build/iter-006.stream.jsonl ]]
}

@test "a record above the stream numbers wins, and leading zeros stay decimal" {
    "$RALPH" init
    printf -- '- [ ] one\n- [ ] two\n' > IMPLEMENTATION_PLAN.md
    create_committing_backend
    mkdir -p .ralph/logs/given/build
    echo '{"iteration":12}' > .ralph/logs/given/build/metrics.jsonl
    : > .ralph/logs/given/build/iter-008.stream.jsonl

    RALPH_RUN_DIR=.ralph/logs/given PATH="$TEST_DIR/bin:$PATH" run "$RALPH" build -n 1 --skip-push -y
    [[ "$status" -eq 0 ]]

    [[ "$(jq -r '.iteration' .ralph/logs/given/build/metrics.jsonl | paste -sd,)" == "12,13" ]]
    [[ -f .ralph/logs/given/build/iter-013.stream.jsonl ]]
}

@test "the highest record, not the last, numbers the next record in a folder without stream files" {
    "$RALPH" init
    printf -- '- [ ] one\n- [ ] two\n' > IMPLEMENTATION_PLAN.md
    create_committing_backend
    mkdir -p .ralph/logs/given/build
    printf '%s\n' '{"iteration":3}' '{"iteration":1}' > .ralph/logs/given/build/metrics.jsonl

    RALPH_RUN_DIR=.ralph/logs/given PATH="$TEST_DIR/bin:$PATH" run "$RALPH" build -n 1 --skip-push -y
    [[ "$status" -eq 0 ]]

    [[ "$(jq -r '.iteration' .ralph/logs/given/build/metrics.jsonl | paste -sd,)" == "3,1,4" ]]
    [[ -f .ralph/logs/given/build/iter-004.stream.jsonl ]]
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
    # Plan mode commits only specs, so the noop flag must come from the plan
    # fingerprint rather than from HEAD.
    cat > "$TEST_DIR/bin/claude" <<'MOCK'
#!/usr/bin/env bash
cat > /dev/null
echo "- [ ] **Task one**" >> IMPLEMENTATION_PLAN.md
echo '{"type":"result","subtype":"success","duration_ms":500,"duration_api_ms":400,"num_turns":2,"result":"Planned.","session_id":"s3","total_cost_usd":0.01,"usage":{"input_tokens":10,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":5}}'
MOCK
    chmod +x "$TEST_DIR/bin/claude"

    PATH="$TEST_DIR/bin:$PATH" "$RALPH" plan -n 1 --skip-push -y -g "the goal"

    local line
    line=$(tail -1 "$(latest_metrics_file)")
    [[ $(jq -r '.mode' <<<"$line") == "plan" ]]
    [[ $(jq -r '.git.noop' <<<"$line") == "false" ]]
    [[ $(jq -r '.git.commits' <<<"$line") == "0" ]]
}

@test "plan iteration that changes nothing records noop=true" {
    "$RALPH" init
    create_noop_backend

    PATH="$TEST_DIR/bin:$PATH" "$RALPH" plan -n 1 --skip-push -y -g "the goal"

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
    [[ ! -d ".ralph/logs" ]]
}

@test "dry-run does not create metrics" {
    "$RALPH" init
    printf -- '- [ ] one\n' > IMPLEMENTATION_PLAN.md

    run "$RALPH" build -n 1 --dry-run
    [[ "$status" -eq 0 ]]
    [[ ! -d ".ralph/logs" ]]
}

@test "plan mode records metrics" {
    "$RALPH" init
    printf -- '- [ ] one\n' > IMPLEMENTATION_PLAN.md
    create_noop_backend

    PATH="$TEST_DIR/bin:$PATH" "$RALPH" plan -n 1 -y -g "the goal"

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

@test "ralph metrics with no argument prints the rollup of the newer of two runs" {
    local name phase
    for name in older newer; do
        for phase in plan build; do
            mkdir -p ".ralph/logs/$name/$phase"
            printf '%s\n' '{"iteration":1,"mode":"build","backend":"claude","model":"opus","effort":null,"wall_s":5,"cost_usd":0.5,"tokens":{"output":40},"plan_items_completed":1,"git":{"commits":1,"files_changed":1,"insertions":2,"deletions":0,"noop":false}}' \
                > ".ralph/logs/$name/$phase/metrics.jsonl"
        done
    done
    touch -t 202601010000 .ralph/logs/older/plan/metrics.jsonl .ralph/logs/older/build/metrics.jsonl

    run "$RALPH" metrics
    [[ "$status" -eq 0 ]]
    [[ "$output" == "Run: .ralph/logs/newer"$'\n'* ]]
    [[ "$output" == *"PHASE"*"MODEL/EFFORT"* ]]
    [[ "$output" != *"older"* ]]
}

@test "ralph metrics with no argument picks the newer run without calling ls" {
    local name phase
    for name in a-older b-newer; do
        for phase in plan build; do
            mkdir -p ".ralph/logs/$name/$phase"
            printf '%s\n' '{"iteration":1,"mode":"build","backend":"claude","model":"opus","effort":null,"wall_s":5,"cost_usd":0.5,"tokens":{"output":40},"plan_items_completed":1,"git":{"commits":1,"files_changed":1,"insertions":2,"deletions":0,"noop":false}}' \
                > ".ralph/logs/$name/$phase/metrics.jsonl"
        done
    done
    touch -t 202601010000 .ralph/logs/a-older/plan/metrics.jsonl .ralph/logs/a-older/build/metrics.jsonl
    mkdir -p "$TEST_DIR/ls-shim"
    printf '#!/usr/bin/env bash\nexit 1\n' > "$TEST_DIR/ls-shim/ls"
    chmod +x "$TEST_DIR/ls-shim/ls"

    PATH="$TEST_DIR/ls-shim:$PATH" run "$RALPH" metrics
    [[ "$status" -eq 0 ]]
    [[ "$output" == "Run: .ralph/logs/b-newer"$'\n'* ]]
    [[ "$output" == *"PHASE"*"MODEL/EFFORT"* ]]
    [[ "$output" != *"a-older"* ]]
}

@test "ralph metrics with no argument picks a run by its auto.json, stream files and top-level metrics.jsonl" {
    local name phase signal
    for name in a b; do
        for phase in plan build; do
            mkdir -p ".ralph/logs/$name/$phase"
            printf '%s\n' '{"iteration":1,"mode":"build","backend":"claude","model":"opus","effort":null,"wall_s":5,"cost_usd":0.5,"tokens":{"output":40},"plan_items_completed":1,"git":{"commits":1,"files_changed":1,"insertions":2,"deletions":0,"noop":false}}' \
                > ".ralph/logs/$name/$phase/metrics.jsonl"
        done
    done
    touch -t 202601010000 .ralph/logs/a/plan/metrics.jsonl .ralph/logs/a/build/metrics.jsonl
    touch -t 202602010000 .ralph/logs/b/plan/metrics.jsonl .ralph/logs/b/build/metrics.jsonl

    for signal in auto.json build/iter-002.stream.jsonl iter-001.stream.jsonl metrics.jsonl; do
        printf '%s\n' '{"goal":"g","phases":[{"phase":3,"name":"plan","state":"ran","exit":0},{"phase":4,"name":"build","state":"ran","exit":0}]}' \
            > ".ralph/logs/a/$signal"
        run "$RALPH" metrics
        [[ "$status" -eq 0 ]] || { echo "$signal: exit $status"; false; }
        [[ "$output" == "Run: .ralph/logs/a"* ]] || { echo "$signal: $output"; false; }
        rm ".ralph/logs/a/$signal"
    done
}

@test "ralph metrics with no runs errors helpfully" {
    "$RALPH" init
    run "$RALPH" metrics
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"No metrics found"* ]]
}

@test "a lone old store moves to .ralph/logs" {
    mkdir -p .ralph/metrics/r1
    printf '%s\n' '{"iteration":1}' > .ralph/metrics/r1/metrics.jsonl

    run "$RALPH" metrics
    [[ "$output" == *"Moved .ralph/metrics/ to .ralph/logs/."* ]]
    [[ -f .ralph/logs/r1/metrics.jsonl ]]
    [[ ! -e .ralph/metrics ]]
}

@test "a failed move of the old store warns and keeps it" {
    mkdir -p .ralph/metrics/r1 "$TEST_DIR/bin"
    printf '%s\n' '{"iteration":1}' > .ralph/metrics/r1/metrics.jsonl
    printf '#!/usr/bin/env bash\nexit 1\n' > "$TEST_DIR/bin/mv"
    chmod +x "$TEST_DIR/bin/mv"

    PATH="$TEST_DIR/bin:$PATH" run "$RALPH" metrics
    [[ "$output" == *"Warning: cannot move .ralph/metrics/ to .ralph/logs/."* ]]
    [[ "$output" != *"Moved .ralph/metrics/"* ]]
    [[ -f .ralph/metrics/r1/metrics.jsonl ]]
    [[ ! -e .ralph/logs ]]
}

@test "two stores merge and keep each clash" {
    mkdir -p .ralph/metrics/r1 .ralph/metrics/r2 .ralph/logs/r1
    printf '%s\n' '{"iteration":1,"from":"old"}' > .ralph/metrics/r1/metrics.jsonl
    printf '%s\n' '{"iteration":2}' > .ralph/metrics/r2/metrics.jsonl
    printf '%s\n' '{"iteration":3,"from":"new"}' > .ralph/logs/r1/metrics.jsonl

    run "$RALPH" metrics
    [[ "$output" == *"Warning: kept .ralph/metrics/r1; .ralph/logs/r1 already exists."* ]]
    [[ "$output" != *"kept .ralph/metrics/r2"* ]]
    [[ -f .ralph/logs/r2/metrics.jsonl ]]
    [[ ! -e .ralph/metrics/r2 ]]
    [[ -f .ralph/metrics/r1/metrics.jsonl ]]
    [[ "$(cat .ralph/logs/r1/metrics.jsonl)" == *'"from":"new"'* ]]
}

@test "a merge with no clash removes the emptied old store" {
    mkdir -p .ralph/metrics/r2 .ralph/logs/r1
    printf '%s\n' '{"iteration":2}' > .ralph/metrics/r2/metrics.jsonl
    printf '%s\n' hidden > .ralph/metrics/.hidden

    run "$RALPH" metrics
    [[ "$output" != *"Warning"* ]]
    [[ -f .ralph/logs/r2/metrics.jsonl ]]
    [[ -f .ralph/logs/.hidden ]]
    [[ ! -e .ralph/metrics ]]
}

@test "a merge into a file at .ralph/logs warns for each entry" {
    mkdir -p .ralph/metrics/r1
    printf '%s\n' '{"iteration":1}' > .ralph/metrics/r1/metrics.jsonl
    touch .ralph/logs

    run "$RALPH" metrics
    [[ "$output" == *"Warning: cannot move .ralph/metrics/r1 to .ralph/logs/."* ]]
    [[ -f .ralph/metrics/r1/metrics.jsonl ]]
    [[ -f .ralph/logs ]]
}

@test "an old argument path is read from the new store" {
    mkdir -p .ralph/metrics/r1
    printf '%s\n' '{"iteration":1,"mode":"build","backend":"claude","model":"opus","wall_s":5,"git":{"commits":1,"files_changed":1,"insertions":2,"deletions":0,"noop":false},"plan_items_completed":1}' \
        > .ralph/metrics/r1/metrics.jsonl

    run "$RALPH" metrics .ralph/metrics/r1/metrics.jsonl
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"Run: .ralph/logs/r1/metrics.jsonl"* ]]
    [[ "$output" == *"Totals: 1 iterations"* ]]
}

@test "an old argument path is read in place when the store move failed" {
    mkdir -p .ralph/metrics/r1
    printf '%s\n' '{"iteration":1,"mode":"build","backend":"claude","model":"opus","wall_s":5,"git":{"commits":1,"files_changed":1,"insertions":2,"deletions":0,"noop":false},"plan_items_completed":1}' \
        > .ralph/metrics/r1/metrics.jsonl
    touch .ralph/logs

    run "$RALPH" metrics .ralph/metrics/r1/metrics.jsonl
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"Run: .ralph/metrics/r1/metrics.jsonl"* ]]
    [[ "$output" == *"Totals: 1 iterations"* ]]
}

@test "Repos line sums each repository over every record that names it" {
    mkdir -p .ralph/logs/r1/build
    local base='"mode":"build","backend":"claude","model":"opus","wall_s":5,"plan_items_completed":1'
    {
        printf '%s\n' "{\"iteration\":1,$base,\"git\":{\"commits\":1,\"files_changed\":1,\"insertions\":10,\"deletions\":1,\"noop\":false}}"
        printf '%s\n' "{\"iteration\":2,$base,\"git\":{\"commits\":2,\"files_changed\":1,\"insertions\":20,\"deletions\":3,\"noop\":false,\"repos\":[{\"repo\":\"./svc\",\"commits\":2,\"files_changed\":1,\"insertions\":20,\"deletions\":3}]}}"
        printf '%s\n' "{\"iteration\":3,$base,\"git\":{\"commits\":4,\"files_changed\":2,\"insertions\":70,\"deletions\":9,\"noop\":false,\"repos\":[{\"repo\":\".\",\"commits\":1,\"files_changed\":1,\"insertions\":30,\"deletions\":4},{\"repo\":\"./svc\",\"commits\":3,\"files_changed\":1,\"insertions\":40,\"deletions\":5}]}}"
    } > .ralph/logs/r1/build/metrics.jsonl

    run "$RALPH" metrics .ralph/logs/r1/build/metrics.jsonl
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"Totals: 3 iterations"* ]]
    [[ "$output" == *"Repos: . 1 (+30/-4) · ./svc 5 (+60/-8)"* ]]
}

@test "Repos line is absent when the records name one repository" {
    mkdir -p .ralph/logs/r1/build
    printf '%s\n' '{"iteration":1,"mode":"build","backend":"claude","model":"opus","wall_s":5,"git":{"commits":1,"files_changed":1,"insertions":2,"deletions":0,"noop":false,"repos":[{"repo":".","commits":1,"files_changed":1,"insertions":2,"deletions":0}]},"plan_items_completed":1}' \
        > .ralph/logs/r1/build/metrics.jsonl

    run "$RALPH" metrics .ralph/logs/r1/build/metrics.jsonl
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"Totals: 1 iterations"* ]]
    [[ "$output" != *"Repos:"* ]]
}

@test "a run with two phase folders prints a summed row per phase, plan first, then Totals" {
    mkdir -p .ralph/logs/r1/build .ralph/logs/r1/plan
    local tail='"mode":"build","backend":"claude","plan_items_completed":1'
    local git1='"git":{"commits":1,"files_changed":1,"insertions":2,"deletions":0,"noop":false}'
    local git2='"git":{"commits":2,"files_changed":1,"insertions":2,"deletions":0,"noop":false}'
    {
        printf '%s\n' "{\"iteration\":1,\"model\":\"opus\",\"effort\":\"high\",\"wall_s\":5,\"cost_usd\":1.234,\"tokens\":{\"output\":100},$tail,$git1}"
        printf '%s\n' "{\"iteration\":2,\"model\":\"opus\",\"effort\":\"high\",\"wall_s\":65,\"cost_usd\":2.5,\"tokens\":{\"output\":250},$tail,$git2}"
    } > .ralph/logs/r1/build/metrics.jsonl
    printf '%s\n' "{\"iteration\":1,\"model\":\"sonnet\",\"effort\":null,\"wall_s\":5,\"cost_usd\":0.5,\"tokens\":{\"output\":40},$tail,$git1}" \
        > .ralph/logs/r1/plan/metrics.jsonl

    run "$RALPH" metrics .ralph/logs/r1
    [[ "$status" -eq 0 ]]
    [[ "$output" == "Run: .ralph/logs/r1"* ]]
    local squeezed expected
    squeezed=$(tr -s ' \t' ' ' <<<"$output")
    expected=$'PHASE MODEL/EFFORT ITERS WALL COST OUT_TOK COMMITS EXIT\nplan sonnet/default 1 5s $0.5 40 1 -\nbuild opus/high 2 1m10s $3.73 350 3 -'
    [[ "$squeezed" == *"$expected"* ]]
    [[ "$squeezed" == *"Totals: 3 iterations · wall 1m15s"* ]]
}

@test "a rollup row names the model of the phase's first record" {
    mkdir -p .ralph/logs/r1/build .ralph/logs/r1/plan
    local tail='"mode":"build","backend":"claude","effort":"high","wall_s":5,"plan_items_completed":1'
    local git='"git":{"commits":1,"files_changed":1,"insertions":2,"deletions":0,"noop":false}'
    {
        printf '%s\n' "{\"iteration\":1,\"model\":\"a\",$tail,$git}"
        printf '%s\n' "{\"iteration\":2,\"model\":\"b\",$tail,$git}"
    } > .ralph/logs/r1/build/metrics.jsonl
    printf '%s\n' "{\"iteration\":1,\"model\":\"sonnet\",$tail,$git}" > .ralph/logs/r1/plan/metrics.jsonl

    run "$RALPH" metrics .ralph/logs/r1
    [[ "$status" -eq 0 ]]
    local squeezed
    squeezed=$(tr -s ' \t' ' ' <<<"$output")
    [[ "$squeezed" == *$'\nbuild a/high 2 '* ]]
    [[ "$squeezed" != *"b/high"* ]]
}

@test "an auto run prints the (auto) header, its goal and a row per listed phase" {
    mkdir -p .ralph/logs/r1/plan
    printf '%s\n' '{"iteration":1,"mode":"plan","model":"sonnet","effort":null,"wall_s":5,"cost_usd":0.5,"tokens":{"output":40},"plan_items_completed":1,"git":{"commits":1,"files_changed":1,"insertions":2,"deletions":0,"noop":false}}' \
        > .ralph/logs/r1/plan/metrics.jsonl
    cat > .ralph/logs/r1/auto.json <<'EOF'
{"goal":"ship it","branch":"main","started":"2026-11-23T10:00:00Z","phases":[
 {"phase":1,"name":"archive","state":"ran","exit":0,"started":null,"ended":null},
 {"phase":2,"name":"init","state":"ran","exit":0,"started":null,"ended":null},
 {"phase":3,"name":"plan","state":"ran","exit":0,"started":null,"ended":null},
 {"phase":4,"name":"build","state":"failed — exit 1","exit":1,"started":null,"ended":null},
 {"phase":5,"name":"review","state":"skipped — no open items","exit":null,"started":null,"ended":null}]}
EOF

    run "$RALPH" metrics .ralph/logs/r1
    [[ "$status" -eq 0 ]]
    [[ "$output" == "Run: .ralph/logs/r1 (auto)"$'\n'"Goal: ship it"$'\n'* ]]
    local squeezed expected
    squeezed=$(tr -s ' \t' ' ' <<<"$output")
    expected=$'PHASE MODEL/EFFORT ITERS WALL COST OUT_TOK COMMITS EXIT\nplan sonnet/default 1 5s $0.5 40 1 0\nbuild failed — exit 1 1\nreview skipped — no open items -\n\nTotals: 1 iterations'
    [[ "$squeezed" == *"$expected"* ]]
}

@test "an auto run prints the five-phase rollup" {
    mkdir -p .ralph/logs/r1/plan .ralph/logs/r1/build .ralph/logs/r1/retro
    local tail='"mode":"build","backend":"claude","plan_items_completed":1'
    local nogit='"git":{"commits":0,"files_changed":0,"insertions":0,"deletions":0,"noop":true,"repos":[]}'
    local root='{"repo":".","commits":1,"files_changed":1,"insertions":10,"deletions":1}'
    local svc='{"repo":"./svc","commits":3,"files_changed":2,"insertions":20,"deletions":3}'
    local root2='{"repo":".","commits":2,"files_changed":1,"insertions":5,"deletions":0}'
    printf '%s\n' "{\"iteration\":1,\"model\":\"sonnet\",\"effort\":null,\"wall_s\":5,\"cost_usd\":0.5,\"tokens\":{\"output\":40},$tail,$nogit}" \
        > .ralph/logs/r1/plan/metrics.jsonl
    {
        printf '%s\n' "{\"iteration\":1,\"model\":\"opus\",\"effort\":\"high\",\"wall_s\":5,\"cost_usd\":1.234,\"tokens\":{\"output\":100},$tail,\"git\":{\"commits\":4,\"files_changed\":3,\"insertions\":30,\"deletions\":4,\"noop\":false,\"repos\":[$root,$svc]}}"
        printf '%s\n' "{\"iteration\":2,\"model\":\"opus\",\"effort\":\"high\",\"wall_s\":65,\"cost_usd\":2.5,\"tokens\":{\"output\":250},$tail,\"git\":{\"commits\":2,\"files_changed\":1,\"insertions\":5,\"deletions\":0,\"noop\":false,\"repos\":[$root2]}}"
    } > .ralph/logs/r1/build/metrics.jsonl
    printf '%s\n' "{\"iteration\":1,\"model\":\"sonnet\",\"effort\":\"low\",\"wall_s\":5,\"cost_usd\":0.25,\"tokens\":{\"output\":10},$tail,$nogit}" \
        > .ralph/logs/r1/retro/metrics.jsonl
    cat > .ralph/logs/r1/auto.json <<'EOF'
{"goal":"ship it","branch":"main","started":"2026-11-23T10:00:00Z","phases":[
 {"phase":1,"name":"archive","state":"ran","exit":0,"started":"2026-11-23T10:00:00Z","ended":"2026-11-23T10:00:01Z"},
 {"phase":2,"name":"init","state":"ran","exit":0,"started":"2026-11-23T10:00:01Z","ended":"2026-11-23T10:00:02Z"},
 {"phase":3,"name":"plan","state":"ran","exit":0,"started":"2026-11-23T10:00:02Z","ended":"2026-11-23T10:00:07Z"},
 {"phase":4,"name":"build","state":"ran","exit":0,"started":"2026-11-23T10:00:07Z","ended":"2026-11-23T10:01:17Z"},
 {"phase":5,"name":"review","state":"skipped — no cycle base","exit":null,"started":null,"ended":null},
 {"phase":6,"name":"fix","state":"skipped — no open items","exit":null,"started":null,"ended":null},
 {"phase":7,"name":"retro","state":"failed — exit 1","exit":1,"started":"2026-11-23T10:01:17Z","ended":"2026-11-23T10:01:22Z"}]}
EOF

    run "$RALPH" metrics .ralph/logs/r1
    [[ "$status" -eq 0 ]]
    local squeezed expected
    squeezed=$(tr -s ' \t' ' ' <<<"$output")
    expected=$'PHASE MODEL/EFFORT ITERS WALL COST OUT_TOK COMMITS EXIT\nplan sonnet/default 1 5s $0.5 40 0 0\nbuild opus/high 2 1m10s $3.73 350 6 0\nreview skipped — no cycle base -\nfix skipped — no open items -\nretro sonnet/low 1 5s $0.25 10 0 1\n\nTotals: 4 iterations · wall 1m20s'
    [[ "$squeezed" == *"$expected"* ]]
    [[ "$squeezed" == *"commits 6 (+35/-4)"* ]]
    [[ "$squeezed" == *"Repos: . 3 (+15/-1) · ./svc 3 (+20/-3)"* ]]
}

@test "a rollup row for a phase without a folder fills every cell for BSD column" {
    mkdir -p .ralph/logs/r1/plan
    printf '%s\n' '{"iteration":1,"mode":"plan","model":"sonnet","effort":null,"wall_s":5,"cost_usd":0.5,"tokens":{"output":40},"plan_items_completed":1,"git":{"commits":1,"files_changed":1,"insertions":2,"deletions":0,"noop":false}}' \
        > .ralph/logs/r1/plan/metrics.jsonl
    cat > .ralph/logs/r1/auto.json <<'EOF'
{"goal":"ship it","branch":"main","started":"2026-11-23T10:00:00Z","phases":[
 {"phase":3,"name":"plan","state":"ran","exit":0,"started":null,"ended":null},
 {"phase":4,"name":"build","state":"failed — exit 1","exit":1,"started":null,"ended":null},
 {"phase":5,"name":"review","state":"skipped — no cycle base","exit":null,"started":null,"ended":null}]}
EOF
    mkdir -p "$TEST_DIR/column-shim"
    printf '#!/usr/bin/env bash\nexec cat\n' > "$TEST_DIR/column-shim/column"
    chmod +x "$TEST_DIR/column-shim/column"

    PATH="$TEST_DIR/column-shim:$PATH" run "$RALPH" metrics .ralph/logs/r1
    [[ "$status" -eq 0 ]]
    local table
    table=$(sed -n '/^PHASE/,/^$/p' <<<"$output" | sed '/^$/d')
    [[ $(wc -l <<<"$table") -eq 4 ]]
    [[ "$table" == *$'\nbuild\t'* ]]
    awk -F '\t' 'NF != 8 { exit 1 } { for (i = 1; i <= NF; i++) if ($i == "") exit 1 }' <<<"$table"
}

@test "a phase folder without records prints 0 iterations, dashes and its auto.json exit" {
    mkdir -p .ralph/logs/r1/plan .ralph/logs/r1/build .ralph/logs/r1/retro
    printf '%s\n' '{"iteration":1,"mode":"plan","model":"sonnet","effort":null,"wall_s":5,"cost_usd":0.5,"tokens":{"output":40},"plan_items_completed":1,"git":{"commits":1,"files_changed":1,"insertions":2,"deletions":0,"noop":false}}' \
        > .ralph/logs/r1/plan/metrics.jsonl
    : > .ralph/logs/r1/build/metrics.jsonl
    printf '%s\n' '{"type":"result"}' > .ralph/logs/r1/retro/iter-001.stream.jsonl
    cat > .ralph/logs/r1/auto.json <<'EOF'
{"goal":"ship it","branch":"main","started":"2026-11-23T10:00:00Z","phases":[
 {"phase":3,"name":"plan","state":"ran","exit":0,"started":null,"ended":null},
 {"phase":4,"name":"build","state":"failed — exit 2","exit":2,"started":null,"ended":null},
 {"phase":7,"name":"retro","state":"failed — exit 1","exit":1,"started":null,"ended":null}]}
EOF

    run "$RALPH" metrics .ralph/logs/r1
    [[ "$status" -eq 0 ]]
    local squeezed expected
    squeezed=$(tr -s ' \t' ' ' <<<"$output")
    expected=$'PHASE MODEL/EFFORT ITERS WALL COST OUT_TOK COMMITS EXIT\nplan sonnet/default 1 5s $0.5 40 1 0\nbuild - 0 - - - - 2\nretro - 0 - - - - 1\n\nTotals: 1 iterations'
    [[ "$squeezed" == *"$expected"* ]]
}

@test "an auto run whose plan folder holds only a stream file closes with Totals: 0 iterations" {
    mkdir -p .ralph/logs/r1/plan
    printf '%s\n' '{"type":"result"}' > .ralph/logs/r1/plan/iter-001.stream.jsonl
    cat > .ralph/logs/r1/auto.json <<'EOF'
{"goal":"ship it","branch":"main","started":"2026-11-23T10:00:00Z","phases":[
 {"phase":3,"name":"plan","state":"failed — exit 1","exit":1,"started":null,"ended":null}]}
EOF

    run "$RALPH" metrics .ralph/logs/r1
    [[ "$status" -eq 0 ]]
    local squeezed expected
    squeezed=$(tr -s ' \t' ' ' <<<"$output")
    expected=$'PHASE MODEL/EFFORT ITERS WALL COST OUT_TOK COMMITS EXIT\nplan - 0 - - - - 1\n\nTotals: 0 iterations · wall 0s · api 0s · turns 0 · cost $0'
    [[ "$squeezed" == *"$expected"* ]]
}

@test "a phase prints dashes for COST and OUT_TOK only when no record has a value" {
    mkdir -p .ralph/logs/r1/plan .ralph/logs/r1/build .ralph/logs/r1/review
    local tail='"mode":"build","backend":"claude","plan_items_completed":1'
    local git='"git":{"commits":1,"files_changed":1,"insertions":2,"deletions":0,"noop":false}'
    {
        printf '%s\n' "{\"iteration\":1,\"model\":\"opus\",\"effort\":\"high\",\"wall_s\":5,\"cost_usd\":0.5,\"tokens\":{\"output\":40},$tail,$git}"
        printf '%s\n' "{\"iteration\":2,\"model\":\"opus\",\"effort\":\"high\",\"wall_s\":5,\"cost_usd\":null,\"tokens\":null,$tail,$git}"
    } > .ralph/logs/r1/plan/metrics.jsonl
    {
        printf '%s\n' "{\"iteration\":1,\"model\":\"opus\",\"effort\":\"high\",\"wall_s\":5,\"cost_usd\":null,\"tokens\":null,$tail,$git}"
        printf '%s\n' "{\"iteration\":2,\"model\":\"opus\",\"effort\":\"high\",\"wall_s\":5,$tail,$git}"
    } > .ralph/logs/r1/build/metrics.jsonl
    printf '%s\n' "{\"iteration\":1,\"model\":\"opus\",\"effort\":\"high\",\"wall_s\":5,\"cost_usd\":0,\"tokens\":{\"output\":0},$tail,$git}" \
        > .ralph/logs/r1/review/metrics.jsonl

    run "$RALPH" metrics .ralph/logs/r1
    [[ "$status" -eq 0 ]]
    local squeezed expected
    squeezed=$(tr -s ' \t' ' ' <<<"$output")
    expected=$'PHASE MODEL/EFFORT ITERS WALL COST OUT_TOK COMMITS EXIT\nplan opus/high 2 10s $0.5 40 2 -\nbuild opus/high 2 10s - - 2 -\nreview opus/high 1 5s $0 0 1 -'
    [[ "$squeezed" == *"$expected"* ]]
}

@test "an old run directory with a top-level metrics.jsonl prints its per-iteration table" {
    mkdir -p .ralph/logs/old
    local git='"git":{"commits":1,"files_changed":1,"insertions":2,"deletions":0,"noop":false}'
    {
        printf '%s\n' "{\"iteration\":1,\"mode\":\"build\",\"backend\":\"claude\",\"model\":\"opus\",\"wall_s\":5,\"api_s\":4,\"turns\":3,\"cost_usd\":0.5,\"tokens\":{\"input\":10,\"output\":20,\"cache_read\":30},\"tools\":{\"Read\":2,\"Bash\":1},\"plan_items_completed\":1,$git}"
        printf '%s\n' "{\"iteration\":2,\"mode\":\"build\",\"backend\":\"claude\",\"model\":\"opus\",\"wall_s\":7,\"api_s\":6,\"turns\":5,\"cost_usd\":1.5,\"tokens\":{\"input\":11,\"output\":21,\"cache_read\":31},\"tools\":{\"Edit\":4},\"plan_items_completed\":0,$git}"
    } > .ralph/logs/old/metrics.jsonl

    run "$RALPH" metrics .ralph/logs/old
    [[ "$status" -eq 0 ]]
    local squeezed expected
    squeezed=$(tr -s ' \t' ' ' <<<"$output")
    expected=$'ITER WALL API TURNS COST TOK_IN TOK_OUT CACHE_RD COMMITS +/- PLAN TOP_TOOLS\n1 5s 4s 3 $0.5 10 20 30 1 +2/-0 1 Read:2 Bash:1\n2 7s 6s 5 $1.5 11 21 31 1 +2/-0 0 Edit:4'
    [[ "$squeezed" == *"Run: .ralph/logs/old/metrics.jsonl"* ]]
    [[ "$squeezed" == *"$expected"* ]]
    [[ "$squeezed" == *"Totals: 2 iterations"* ]]
    [[ "$squeezed" != *"PHASE"* ]]
}

@test "a standalone build's run directory prints its build per-iteration table" {
    "$RALPH" init
    printf -- '- [ ] one\n- [ ] two\n' > IMPLEMENTATION_PLAN.md
    create_committing_backend
    PATH="$TEST_DIR/bin:$PATH" "$RALPH" build -n 1 --skip-push -y
    local run_dir
    run_dir=$(dirname "$(dirname "$(latest_metrics_file)")")

    run "$RALPH" metrics "$run_dir"
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"Run: $run_dir/build/metrics.jsonl"* ]]
    [[ "$output" == *"ITER"*"TOP_TOOLS"* ]]
    [[ "$output" == *"Totals: 1 iterations"* ]]
    [[ "$output" != *"PHASE"* ]]
}

@test "a standalone build's phase folder prints the same per-iteration table as its run" {
    "$RALPH" init
    printf -- '- [ ] one\n- [ ] two\n' > IMPLEMENTATION_PLAN.md
    create_committing_backend
    PATH="$TEST_DIR/bin:$PATH" "$RALPH" build -n 1 --skip-push -y
    local phase_dir run_dir
    phase_dir=$(dirname "$(latest_metrics_file)")
    run_dir=$(dirname "$phase_dir")

    run "$RALPH" metrics "$run_dir"
    [[ "$status" -eq 0 ]]
    local from_run="$output"
    run "$RALPH" metrics "$phase_dir"
    [[ "$status" -eq 0 ]]
    [[ "$output" == "$from_run" ]]
    [[ "$output" == *"Totals: 1 iterations"* ]]
}

@test "a build folder with only a stream file prints 0 iterations, with no argument and by path" {
    mkdir -p .ralph/logs/r1/build
    printf '%s\n' '{"type":"result"}' > .ralph/logs/r1/build/iter-001.stream.jsonl

    run "$RALPH" metrics
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"Run: .ralph/logs/r1/build/metrics.jsonl"* ]]
    [[ "$output" == *"Totals: 0 iterations · wall 0s · api 0s · turns 0 · cost \$0"* ]]
    [[ "$output" != *"No metrics found"* ]]

    run "$RALPH" metrics .ralph/logs/r1/build
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"Run: .ralph/logs/r1/build/metrics.jsonl"* ]]
    [[ "$output" == *"Totals: 0 iterations · wall 0s · api 0s · turns 0 · cost \$0"* ]]
}

@test "an empty metrics.jsonl argument prints 0 iterations" {
    mkdir -p .ralph/logs/r1/build
    : > .ralph/logs/r1/build/metrics.jsonl

    run "$RALPH" metrics .ralph/logs/r1/build/metrics.jsonl
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"Totals: 0 iterations · wall 0s · api 0s · turns 0 · cost \$0"* ]]
    [[ "$output" == *"commits 0 (+0/-0) · plan items 0 · noop iterations 0"* ]]
}

@test "a phase folder without records or stream files reports no metrics" {
    mkdir -p .ralph/logs/r1/build

    run "$RALPH" metrics .ralph/logs/r1/build
    [[ "$status" -eq 1 ]]
    [[ "$output" == *"No metrics found"* ]]
}

@test "a build over a lone old store moves it beside the new run" {
    "$RALPH" init
    printf -- '- [ ] one\n' > IMPLEMENTATION_PLAN.md
    create_noop_backend
    mkdir -p .ralph/metrics/r1
    printf '%s\n' '{"iteration":1}' > .ralph/metrics/r1/metrics.jsonl

    PATH="$TEST_DIR/bin:$PATH" run "$RALPH" build -n 1 --skip-push -y
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"Moved .ralph/metrics/ to .ralph/logs/."* ]]
    [[ ! -e .ralph/metrics ]]
    [[ -f .ralph/logs/r1/metrics.jsonl ]]
    local builds=(.ralph/logs/*/build)
    [[ ${#builds[@]} -eq 1 ]]
    [[ -f "${builds[0]}/metrics.jsonl" ]]
}

@test "build --no-metrics leaves a lone old store in place" {
    "$RALPH" init
    printf -- '- [ ] one\n' > IMPLEMENTATION_PLAN.md
    create_noop_backend
    mkdir -p .ralph/metrics/r1
    printf '%s\n' '{"iteration":1}' > .ralph/metrics/r1/metrics.jsonl

    PATH="$TEST_DIR/bin:$PATH" run "$RALPH" build -n 1 --skip-push -y --no-metrics
    [[ "$status" -eq 0 ]]
    [[ "$output" != *"Moved .ralph/metrics/"* ]]
    [[ -f .ralph/metrics/r1/metrics.jsonl ]]
    [[ ! -e .ralph/logs ]]
}

@test "a build over a lone old store whose move fails still writes its record" {
    "$RALPH" init
    printf -- '- [ ] one\n' > IMPLEMENTATION_PLAN.md
    create_noop_backend
    mkdir -p .ralph/metrics/r1
    printf '%s\n' '{"iteration":1}' > .ralph/metrics/r1/metrics.jsonl
    cat > "$TEST_DIR/bin/mv" <<MOCK
#!/usr/bin/env bash
[[ "\$*" == *.ralph/metrics* ]] && exit 1
exec $(command -v mv) "\$@"
MOCK
    chmod +x "$TEST_DIR/bin/mv"

    PATH="$TEST_DIR/bin:$PATH" run "$RALPH" build -n 1 --skip-push -y
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"Warning: cannot move .ralph/metrics/ to .ralph/logs/."* ]]
    [[ -f .ralph/metrics/r1/metrics.jsonl ]]
    local builds=(.ralph/logs/*/build)
    [[ ${#builds[@]} -eq 1 ]]
    [[ $(wc -l < "${builds[0]}/metrics.jsonl") -eq 1 ]]
}

@test "metrics failure does not fail the loop" {
    "$RALPH" init
    printf -- '- [ ] one\n' > IMPLEMENTATION_PLAN.md
    create_noop_backend

    # Uncreatable metrics dir (a file squats on the path — robust even when
    # tests run as root, where chmod-based denial doesn't bite): capture must
    # disable itself with a warning and the loop must still run to completion.
    mkdir -p .ralph
    touch .ralph/logs

    PATH="$TEST_DIR/bin:$PATH" run "$RALPH" build -n 1 --skip-push -y
    rm -f .ralph/logs

    [[ "$status" -eq 0 ]]
    [[ "$output" == *"metrics disabled for this run"* ]]
    [[ "$output" == *"Nothing to do."* ]]
}

# The tee branch is a second, distinct write site for the raw stream: under
# default output the file is written by `tee` inside a pipeline rather than by a
# plain `>` redirect. The metrics reader parses that same file after the
# backend exits, so this pins that a torn or truncated tee write would show up
# as a missing histogram rather than passing silently.
@test "tool histogram is read from the stream file written by default" {
    "$RALPH" init
    printf -- '- [ ] one\n' > IMPLEMENTATION_PLAN.md
    create_streaming_backend

    PATH="$TEST_DIR/bin:$PATH" run "$RALPH" build -n 1 --skip-push
    [[ "$status" -eq 0 ]]

    local line
    line=$(tail -1 "$(latest_metrics_file)")
    # The mock emits exactly one tool_use, for Bash.
    [[ $(jq -r '.tools.Bash' <<<"$line") == "1" ]]
    # Fields from the result event prove the whole record parsed, not just the
    # assistant events the histogram walks.
    [[ $(jq -r '.turns' <<<"$line") == "3" ]]
    [[ $(jq -r '.cost_usd' <<<"$line") == "0.02" ]]
}

# A build iteration that commits only inside a nested repository leaves the
# workspace HEAD where it was. The record still counts that commit, as the one
# entry of git.repos.
@test "a nested-only commit records noop=false with one commit" {
    "$RALPH" init
    printf -- '- [ ] one\n' > IMPLEMENTATION_PLAN.md
    echo "source/" >> .gitignore
    mkdir -p source/svc
    git -C source/svc init --quiet
    git -C source/svc config user.email "nested@test.com"
    git -C source/svc config user.name "Nested"
    git -C source/svc commit --allow-empty -m "nested initial" --quiet

    mkdir -p "$TEST_DIR/bin"
    cat > "$TEST_DIR/bin/claude" <<'MOCK'
#!/usr/bin/env bash
cat > /dev/null
git -C source/svc commit --allow-empty -m "nested work" --quiet
echo '{"type":"result","result":"done"}'
MOCK
    chmod +x "$TEST_DIR/bin/claude"

    PATH="$TEST_DIR/bin:$PATH" "$RALPH" build -n 1 --skip-push -y

    local line
    line=$(tail -1 "$(latest_metrics_file)")
    [[ $(jq -r '.git.noop' <<<"$line") == "false" ]]
    [[ $(jq -r '.git.commits' <<<"$line") == "1" ]]
    [[ $(jq -r '.git.repos | length' <<<"$line") == "1" ]]
    [[ $(jq -r '.git.repos[0].repo' <<<"$line") == "./source/svc" ]]
}

# Discard the setup helper's initial commit so the workspace HEAD is unborn.
reinit_commitless_workspace() {
    rm -rf .git
    git init --quiet
    git config user.email "test@test.com"
    git config user.name "Test"
}

@test "commitless workspace completes an idle build and records two noops" {
    reinit_commitless_workspace
    "$RALPH" init
    printf -- '- [ ] one\n- [ ] two\n' > IMPLEMENTATION_PLAN.md
    create_noop_backend

    PATH="$TEST_DIR/bin:$PATH" run "$RALPH" build --skip-push -y
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"No changes detected"* ]]

    local f
    f=$(latest_metrics_file)
    [[ $(wc -l < "$f") -eq 2 ]]
    [[ $(jq -rs 'map(.git.noop) | join(",")' "$f") == "true,true" ]]
    [[ $(jq -rs 'map(.git.commits) | join(",")' "$f") == "0,0" ]]
}

# The workspace has no commit before the pass, so repo_git_counts counts its
# first commit from the empty tree.
@test "first commit on a commitless workspace records noop=false" {
    reinit_commitless_workspace
    "$RALPH" init
    printf -- '- [ ] one\n' > IMPLEMENTATION_PLAN.md

    mkdir -p "$TEST_DIR/bin"
    cat > "$TEST_DIR/bin/claude" <<'MOCK'
#!/usr/bin/env bash
cat > /dev/null
echo "first" >> src.txt
git add src.txt >/dev/null 2>&1
git commit -q -m "first workspace commit"
echo '{"type":"result","result":"done"}'
MOCK
    chmod +x "$TEST_DIR/bin/claude"

    PATH="$TEST_DIR/bin:$PATH" run "$RALPH" build -n 1 --skip-push -y
    [[ "$status" -eq 0 ]]

    local line
    line=$(tail -1 "$(latest_metrics_file)")
    [[ $(jq -r '.git.noop' <<<"$line") == "false" ]]
    [[ $(jq -r '.git.commits' <<<"$line") == "1" ]]
    [[ $(jq -r '.git.repos | length' <<<"$line") == "1" ]]
    [[ $(jq -r '.git.repos[0].repo' <<<"$line") == "." ]]
}

@test "commits in a nested repository and the workspace sum into one record" {
    "$RALPH" init
    printf -- '- [ ] one\n' > IMPLEMENTATION_PLAN.md
    echo "source/" >> .gitignore
    mkdir -p source/svc
    git -C source/svc init --quiet
    git -C source/svc config user.email "nested@test.com"
    git -C source/svc config user.name "Nested"
    git -C source/svc commit --allow-empty -m "nested initial" --quiet

    mkdir -p "$TEST_DIR/bin"
    cat > "$TEST_DIR/bin/claude" <<'MOCK'
#!/usr/bin/env bash
cat > /dev/null
echo "a" > source/svc/a.txt
git -C source/svc add a.txt
git -C source/svc commit -q -m "nested one"
echo "b" > source/svc/b.txt
git -C source/svc add b.txt
git -C source/svc commit -q -m "nested two"
echo "work" > src.txt
git add src.txt
git commit -q -m "workspace work"
echo '{"type":"result","result":"done"}'
MOCK
    chmod +x "$TEST_DIR/bin/claude"

    PATH="$TEST_DIR/bin:$PATH" "$RALPH" build -n 1 --skip-push -y

    local line
    line=$(tail -1 "$(latest_metrics_file)")
    [[ $(jq -r '.git.commits' <<<"$line") == "3" ]]
    [[ $(jq -r '.git.files_changed' <<<"$line") == "3" ]]
    [[ $(jq -r '.git.insertions' <<<"$line") == "3" ]]
    [[ $(jq -r '.git.repos | length' <<<"$line") == "2" ]]
    [[ $(jq -r '.git.repos | map(.repo) | join(",")' <<<"$line") == ".,./source/svc" ]]
    [[ $(jq -r '.git.repos[] | select(.repo == ".") | .commits' <<<"$line") == "1" ]]
    [[ $(jq -r '.git.repos[] | select(.repo == "./source/svc") | .commits' <<<"$line") == "2" ]]
    [[ $(jq -r '.git.repos[] | select(.repo == "./source/svc") | .files_changed' <<<"$line") == "2" ]]
}

@test "a replaced line counts one insertion and one deletion since the before-SHA" {
    "$RALPH" init
    printf -- '- [ ] one\n' > IMPLEMENTATION_PLAN.md
    printf 'one\ntwo\n' > f.txt
    git add f.txt
    git commit -q -m "two lines"

    mkdir -p "$TEST_DIR/bin"
    cat > "$TEST_DIR/bin/claude" <<'MOCK'
#!/usr/bin/env bash
cat > /dev/null
printf 'one\nTWO\n' > f.txt
git add f.txt
git commit -q -m "replace a line"
echo '{"type":"result","result":"done"}'
MOCK
    chmod +x "$TEST_DIR/bin/claude"

    PATH="$TEST_DIR/bin:$PATH" "$RALPH" build -n 1 --skip-push -y

    local line
    line=$(tail -1 "$(latest_metrics_file)")
    [[ $(jq -c '.git.repos[] | select(.repo == ".") | [.files_changed, .insertions, .deletions]' <<<"$line") == "[1,1,1]" ]]
    [[ $(jq -r '.git.deletions' <<<"$line") == "1" ]]
}

@test "a repository left on an unborn branch drops out of the repos list" {
    "$RALPH" init
    printf -- '- [ ] one\n' > IMPLEMENTATION_PLAN.md
    echo "source/" >> .gitignore
    mkdir -p source/svc
    git -C source/svc init --quiet
    git -C source/svc config user.email "nested@test.com"
    git -C source/svc config user.name "Nested"
    git -C source/svc commit --allow-empty -m "nested initial" --quiet

    mkdir -p "$TEST_DIR/bin"
    cat > "$TEST_DIR/bin/claude" <<'MOCK'
#!/usr/bin/env bash
cat > /dev/null
git -C source/svc checkout -q --orphan fresh
echo '{"type":"result","result":"done"}'
MOCK
    chmod +x "$TEST_DIR/bin/claude"

    PATH="$TEST_DIR/bin:$PATH" "$RALPH" build -n 1 --skip-push -y

    [[ $(git -C source/svc symbolic-ref HEAD) == "refs/heads/fresh" ]]
    local line
    line=$(tail -1 "$(latest_metrics_file)")
    [[ $(jq -r '[.git.repos[] | select(.repo == "./source/svc")] | length' <<<"$line") == "0" ]]
}

@test "a repository created during the pass counts from the empty tree" {
    "$RALPH" init
    printf -- '- [ ] one\n' > IMPLEMENTATION_PLAN.md
    echo "source/" >> .gitignore

    mkdir -p "$TEST_DIR/bin"
    cat > "$TEST_DIR/bin/claude" <<'MOCK'
#!/usr/bin/env bash
cat > /dev/null
mkdir -p source/fresh
git -C source/fresh init --quiet
git -C source/fresh config user.email "nested@test.com"
git -C source/fresh config user.name "Nested"
printf 'one\ntwo\nthree\n' > source/fresh/f.txt
git -C source/fresh add f.txt
git -C source/fresh commit -q -m "first"
echo '{"type":"result","result":"done"}'
MOCK
    chmod +x "$TEST_DIR/bin/claude"

    PATH="$TEST_DIR/bin:$PATH" "$RALPH" build -n 1 --skip-push -y

    local line
    line=$(tail -1 "$(latest_metrics_file)")
    [[ $(jq -r '.git.repos | length' <<<"$line") == "1" ]]
    [[ $(jq -r '.git.repos[0].repo' <<<"$line") == "./source/fresh" ]]
    [[ $(jq -r '.git.repos[0].commits' <<<"$line") == "1" ]]
    [[ $(jq -r '.git.repos[0].files_changed' <<<"$line") == "1" ]]
    [[ $(jq -r '.git.repos[0].insertions' <<<"$line") == "3" ]]
    [[ $(jq -r '.git.insertions' <<<"$line") == "3" ]]
}

@test "a pass that moves no repository records empty repos and zero counts" {
    "$RALPH" init
    printf -- '- [ ] one\n' > IMPLEMENTATION_PLAN.md
    create_noop_backend

    PATH="$TEST_DIR/bin:$PATH" "$RALPH" build -n 1 --skip-push -y

    local line
    line=$(tail -1 "$(latest_metrics_file)")
    [[ $(jq -c '.git.repos' <<<"$line") == "[]" ]]
    [[ $(jq -r '[.git.commits, .git.files_changed, .git.insertions, .git.deletions] | join(",")' <<<"$line") == "0,0,0,0" ]]
}

@test "fix records effort, config and section beside mode" {
    require_yq_or_skip
    "$RALPH" init
    printf -- '- [ ] one\n- [ ] two\n' > IMPLEMENTATION_PLAN.md
    printf 'fix:\n  effort: high\n' > ralph.yaml
    create_committing_backend

    PATH="$TEST_DIR/bin:$PATH" run "$RALPH" fix -n 1 --skip-push -y
    [[ "$status" -eq 0 ]]

    local line
    line=$(tail -1 "$(latest_metrics_file)")
    [[ $(jq -c '{mode, section, effort, config}' <<<"$line") == '{"mode":"build","section":"fix","effort":"high","config":"ralph.yaml"}' ]]
}

@test "metrics record null effort and config without a config file" {
    "$RALPH" init
    printf -- '- [ ] one\n- [ ] two\n' > IMPLEMENTATION_PLAN.md
    create_committing_backend

    PATH="$TEST_DIR/bin:$PATH" run "$RALPH" build -n 1 --skip-push -y
    [[ "$status" -eq 0 ]]

    local line
    line=$(tail -1 "$(latest_metrics_file)")
    [[ $(jq -c '{section, effort, config}' <<<"$line") == '{"section":"build","effort":null,"config":null}' ]]
}

@test "ralph metrics shows effort, config and section in the run summary" {
    require_yq_or_skip
    "$RALPH" init
    printf -- '- [ ] one\n- [ ] two\n' > IMPLEMENTATION_PLAN.md
    printf 'fix:\n  effort: low\n' > ralph.yaml
    create_committing_backend

    PATH="$TEST_DIR/bin:$PATH" "$RALPH" fix -n 1 --skip-push -y

    run "$RALPH" metrics
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"Config: ralph.yaml [fix] backend=claude model=opus effort=low"* ]]
}

@test "ralph metrics reads records that lack effort, config and section" {
    mkdir -p .ralph/logs/old
    printf '%s\n' '{"iteration":1,"mode":"build","backend":"claude","model":"opus","wall_s":5,"git":{"commits":1,"files_changed":1,"insertions":2,"deletions":0,"noop":false},"plan_items_completed":1}' \
        > .ralph/logs/old/metrics.jsonl

    run "$RALPH" metrics .ralph/logs/old/metrics.jsonl
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"1 iterations"* ]]
    [[ "$output" != *"Config:"* ]]
}

@test "ralph metrics shows the built-in source and default effort for null fields" {
    mkdir -p .ralph/logs/builtin
    printf '%s\n' '{"iteration":1,"mode":"build","section":"build","backend":"claude","model":"opus","effort":null,"config":null,"wall_s":5,"git":{"commits":1,"files_changed":1,"insertions":2,"deletions":0,"noop":false},"plan_items_completed":1}' \
        > .ralph/logs/builtin/metrics.jsonl

    run "$RALPH" metrics .ralph/logs/builtin/metrics.jsonl
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"Config: built-in (no config file) [build]"* ]]
    [[ "$output" == *"effort=default"* ]]
}
