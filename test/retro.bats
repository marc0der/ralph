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

# Helper: write a §3-valid learnings file holding one bullet tagged with $1.
write_learnings() {
    mkdir -p .ralph
    printf '# Learnings\n\n## Environment\n- %s (confirmed 2026-11-14)\n\n## Tooling\n\n## Codebase\n\n## Promote to AGENTS.md\n' "$1" > .ralph/learnings.md
}

@test "a successful retro pass leaves learnings.prev.md equal to the old file" {
    create_retro_backend
    seed_progress_entry
    write_learnings "old learning"
    cp .ralph/learnings.md "$TEST_DIR/old.md"
    cat > "$TEST_DIR/pass.sh" <<'PASS'
printf '# Learnings\n\n## Environment\n- new learning (confirmed 2026-11-15)\n\n## Tooling\n\n## Codebase\n\n## Promote to AGENTS.md\n' > .ralph/learnings.md
PASS
    run "$RALPH" retro
    [[ "$status" -eq 0 ]]
    cmp .ralph/learnings.prev.md "$TEST_DIR/old.md"
    grep -q 'new learning' .ralph/learnings.md
}

@test "a first retro pass deletes a stale learnings.prev.md" {
    create_retro_backend
    seed_progress_entry
    mkdir -p .ralph
    echo stale > .ralph/learnings.prev.md
    run "$RALPH" retro
    [[ "$status" -eq 0 ]]
    [[ ! -e .ralph/learnings.prev.md ]]
}

@test "retro --dry-run leaves both learnings files and runs no backup" {
    seed_progress_entry
    write_learnings "old learning"
    echo undo > .ralph/learnings.prev.md
    cp .ralph/learnings.md "$TEST_DIR/old.md"
    TMPDIR="$TEST_DIR/no-such-dir" run "$RALPH" retro --dry-run
    [[ "$status" -eq 0 ]]
    cmp .ralph/learnings.md "$TEST_DIR/old.md"
    [[ "$(cat .ralph/learnings.prev.md)" == "undo" ]]
}

@test "retro backs up through /tmp when TMPDIR is unset" {
    create_retro_backend
    seed_progress_entry
    write_learnings "old learning"
    cp .ralph/learnings.md "$TEST_DIR/old.md"
    unset TMPDIR
    run "$RALPH" retro
    [[ "$status" -eq 0 ]]
    cmp .ralph/learnings.prev.md "$TEST_DIR/old.md"
}

@test "retro fails before the backend when the backup cannot be made" {
    create_retro_backend
    seed_progress_entry
    write_learnings "old learning"
    printf 'touch "%s/backend-ran"\n' "$TEST_DIR" > "$TEST_DIR/pass.sh"
    TMPDIR="$TEST_DIR/no-such-dir" run "$RALPH" retro
    [[ "$status" -eq 1 ]]
    [[ "$output" == *"Error: cannot back up .ralph/learnings.md."* ]]
    [[ ! -e "$TEST_DIR/backend-ran" ]]
}

@test "a retro backend that rewrites the file and exits 1 leaves the old file" {
    create_retro_backend
    seed_progress_entry
    write_learnings "old learning"
    cp .ralph/learnings.md "$TEST_DIR/old.md"
    printf 'echo "# Learnings" > .ralph/learnings.md\n' > "$TEST_DIR/pass.sh"
    MOCK_EXIT=1 run "$RALPH" retro
    [[ "$status" -eq 1 ]]
    cmp .ralph/learnings.md "$TEST_DIR/old.md"
}

@test "a retro backend that writes a first file and exits 1 leaves no file" {
    create_retro_backend
    seed_progress_entry
    [[ ! -e .ralph/learnings.md ]]
    printf 'mkdir -p .ralph && echo "# Learnings" > .ralph/learnings.md\n' > "$TEST_DIR/pass.sh"
    MOCK_EXIT=1 run "$RALPH" retro
    [[ "$status" -eq 1 ]]
    [[ ! -e .ralph/learnings.md ]]
}

@test "an interrupted retro pass restores the old learnings file" {
    create_retro_backend
    seed_progress_entry
    write_learnings "old learning"
    cp .ralph/learnings.md "$TEST_DIR/old.md"
    cat > "$TEST_DIR/pass.sh" <<PASS
echo "# Learnings" > .ralph/learnings.md
touch "$TEST_DIR/edited"
sleep 1
PASS
    local pid status_code=0 waited=0
    "$RALPH" retro > "$TEST_DIR/out" 2>&1 &
    pid=$!
    while [[ ! -f "$TEST_DIR/edited" ]] && (( waited < 100 )); do
        sleep 0.1
        waited=$((waited + 1))
    done
    kill -TERM "$pid"
    wait "$pid" || status_code=$?

    [[ "$status_code" -eq 130 ]]
    grep -q "Interrupted at iteration 1" "$TEST_DIR/out"
    cmp .ralph/learnings.md "$TEST_DIR/old.md"
}
