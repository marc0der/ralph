#!/usr/bin/env bats

load test_helper

# Helper: mock claude that sources $TEST_DIR/pass.sh when present, so each test
# scripts what its retro pass does, and otherwise changes nothing.
create_retro_backend() {
    export TEST_DIR
    mkdir -p "$TEST_DIR/bin"
    cat > "$TEST_DIR/bin/claude" <<'MOCK'
#!/usr/bin/env bash
cat > /dev/null
[[ -f "$TEST_DIR/pass.sh" ]] && source "$TEST_DIR/pass.sh"
echo '{"type":"result","subtype":"success","duration_ms":1,"duration_api_ms":1,"num_turns":1,"result":"done here","session_id":"s1","total_cost_usd":0.0,"usage":{"input_tokens":1,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":1}}'
exit "${MOCK_EXIT:-0}"
MOCK
    chmod +x "$TEST_DIR/bin/claude"
    export PATH="$TEST_DIR/bin:$PATH"
}

@test "retro fails when PROGRESS.md is absent" {
    run "$RALPH" retro --dry-run
    [[ "$status" -eq 1 ]]
    [[ "$output" == *"Error: PROGRESS.md holds no entries; there is nothing to learn from."* ]]
}

@test "retro fails when PROGRESS.md holds only the template exemplar" {
    cp "$BATS_TEST_DIRNAME/../templates/PROGRESS.md" PROGRESS.md
    run "$RALPH" retro --dry-run
    [[ "$status" -eq 1 ]]
    [[ "$output" == *"Error: PROGRESS.md holds no entries; there is nothing to learn from."* ]]
}

@test "retro runs when PROGRESS.md holds one real entry and the plan is absent" {
    create_retro_backend
    seed_progress_entry
    [[ ! -e IMPLEMENTATION_PLAN.md ]]
    run "$RALPH" retro
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"Mode:    retro"* ]]
    [[ "$output" == *"Completed 1 iterations."* ]]
}

@test "retro rejects -n" {
    seed_progress_entry
    run "$RALPH" retro -n 2
    [[ "$status" -eq 1 ]]
    [[ "$output" == *"Error: retro runs one pass; -n does not apply."* ]]
}

@test "retro rejects -g" {
    seed_progress_entry
    run "$RALPH" retro -g "some goal"
    [[ "$status" -eq 1 ]]
    [[ "$output" == *"Error: 'retro' does not accept -g/--goal; the work comes from PROGRESS.md."* ]]
}

@test "retro accepts --skip-push and --push" {
    seed_progress_entry
    run "$RALPH" retro --dry-run --skip-push
    [[ "$status" -eq 0 ]]
    run "$RALPH" retro --dry-run --push
    [[ "$status" -eq 0 ]]
}
