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

# Helper: run retro and assert it failed on the working-tree check and restored the file.
run_retro_expecting_tree_failure() {
    run "$RALPH" retro
    [[ "$status" -eq 1 ]]
    [[ "$output" == *"Error: retro pass changed files in .; retro may write only .ralph/learnings.md."* ]]
    cmp .ralph/learnings.md "$TEST_DIR/old.md"
}

# Helper: run retro and assert it failed on the artifact check and restored the file.
# $1 is the path the error must name.
run_retro_expecting_artifact_failure() {
    run "$RALPH" retro
    [[ "$status" -eq 1 ]]
    [[ "$output" == *"Error: retro pass changed $1; retro may write only .ralph/learnings.md."* ]]
    cmp .ralph/learnings.md "$TEST_DIR/old.md"
}

# Helper: run retro and assert it failed the format check at line $1 and restored the file.
run_retro_expecting_format_failure() {
    run "$RALPH" retro
    [[ "$status" -eq 1 ]]
    [[ "$output" == *"Error: .ralph/learnings.md line $1: "* ]]
    cmp .ralph/learnings.md "$TEST_DIR/old.md"
}

# Helper: seed a retro-ready workspace with an old learnings file and script the pass as stdin.
setup_format_pass() {
    create_retro_backend
    seed_progress_entry
    write_learnings "old learning"
    cp .ralph/learnings.md "$TEST_DIR/old.md"
    cat > "$TEST_DIR/pass.sh"
}

# Helper: init the workspace, seed a retro-ready state, and script the pass as $1.
setup_artifact_pass() {
    "$RALPH" init > /dev/null 2>&1
    create_retro_backend
    seed_progress_entry
    write_learnings "old learning"
    cp .ralph/learnings.md "$TEST_DIR/old.md"
    write_learnings_pass "$1"
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

@test "retro --push without an origin remote never attempts a push" {
    create_retro_backend
    seed_progress_entry
    run "$RALPH" retro --push
    [[ "$status" -eq 0 ]]
    [[ "$output" != *"skipping push"* ]]
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

@test "a failed retro pass restores the learnings file at mode 644" {
    setup_format_pass <<'PASS'
printf '# Learnings\n\n## Environment\n- no date here\n\n## Tooling\n\n## Codebase\n\n## Promote to AGENTS.md\n' > .ralph/learnings.md
PASS
    chmod 644 .ralph/learnings.md
    run_retro_expecting_format_failure 4
    [[ "$(find .ralph/learnings.md -perm 644)" == ".ralph/learnings.md" ]]
}

@test "a successful retro pass keeps learnings.prev.md at mode 644" {
    setup_format_pass <<'PASS'
printf '# Learnings\n\n## Environment\n- new learning (confirmed 2026-11-15)\n\n## Tooling\n\n## Codebase\n\n## Promote to AGENTS.md\n' > .ralph/learnings.md
PASS
    chmod 644 .ralph/learnings.md
    run "$RALPH" retro
    [[ "$status" -eq 0 ]]
    [[ "$(find .ralph/learnings.prev.md -perm 644)" == ".ralph/learnings.prev.md" ]]
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
    export BATS_TEST_TMPDIR
    cat > "$TEST_DIR/pass.sh" <<'PASS'
ls -d /tmp/ralph-learnings.* > "$BATS_TEST_TMPDIR/backups" 2>/dev/null
PASS
    unset TMPDIR
    run "$RALPH" retro
    [[ "$status" -eq 0 ]]
    cmp .ralph/learnings.prev.md "$TEST_DIR/old.md"
    [[ -s "$BATS_TEST_TMPDIR/backups" ]]
    [[ -z "$(find . -name 'ralph-learnings.*')" ]]
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

@test "retro fails before the backend when the learnings file is unreadable" {
    [[ "$(id -u)" -ne 0 ]] || skip "root reads a file at mode 000"
    create_retro_backend
    seed_progress_entry
    write_learnings "old learning"
    printf 'touch "%s/backend-ran"\n' "$TEST_DIR" > "$TEST_DIR/pass.sh"
    chmod 000 .ralph/learnings.md
    run "$RALPH" retro
    [[ "$status" -eq 1 ]]
    [[ "$output" == *"Error: cannot back up .ralph/learnings.md."* ]]
    [[ ! -e "$TEST_DIR/backend-ran" ]]
}

@test "retro removes the backup when an artifact under .ralph is unreadable" {
    [[ "$(id -u)" -ne 0 ]] || skip "root reads a file at mode 000"
    create_retro_backend
    seed_progress_entry
    write_learnings "old learning"
    cp .ralph/learnings.md "$TEST_DIR/old.md"
    echo secret > .ralph/unreadable
    chmod 000 .ralph/unreadable
    mkdir "$BATS_TEST_TMPDIR/tmp"
    TMPDIR="$BATS_TEST_TMPDIR/tmp" run "$RALPH" retro
    [[ "$status" -eq 1 ]]
    [[ "$output" == *"Error: cannot read .ralph/unreadable."* ]]
    [[ -z "$(ls -A "$BATS_TEST_TMPDIR/tmp")" ]]
    cmp .ralph/learnings.md "$TEST_DIR/old.md"
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

# Helper: print git.noop of the last metrics record; each test makes one run.
last_retro_noop() {
    cat .ralph/metrics/*/metrics.jsonl | jq -r '.git.noop' | tail -1
}

@test "a retro pass that deletes the learnings file fails and restores it" {
    create_retro_backend
    seed_progress_entry
    write_learnings "old learning"
    cp .ralph/learnings.md "$TEST_DIR/old.md"
    printf 'rm .ralph/learnings.md\n' > "$TEST_DIR/pass.sh"
    run "$RALPH" retro
    [[ "$status" -eq 1 ]]
    [[ "$output" == *"Error: retro pass deleted .ralph/learnings.md."* ]]
    cmp .ralph/learnings.md "$TEST_DIR/old.md"
    [[ "$(last_retro_noop)" == "false" ]]
}

@test "a retro pass that leaves a learnings directory fails and restores the file" {
    create_retro_backend
    seed_progress_entry
    write_learnings "old learning"
    cp .ralph/learnings.md "$TEST_DIR/old.md"
    printf 'rm .ralph/learnings.md\nmkdir .ralph/learnings.md\n' > "$TEST_DIR/pass.sh"
    run "$RALPH" retro
    [[ "$status" -eq 1 ]]
    [[ "$output" == *"Error: .ralph/learnings.md is not a regular file."* ]]
    cmp .ralph/learnings.md "$TEST_DIR/old.md"
    [[ "$(last_retro_noop)" == "false" ]]
}

@test "a retro pass that deletes .ralph fails and restores the learnings file" {
    create_retro_backend
    seed_progress_entry
    write_learnings "old learning"
    cp .ralph/learnings.md "$TEST_DIR/old.md"
    printf 'rm -rf .ralph\n' > "$TEST_DIR/pass.sh"
    run "$RALPH" retro
    [[ "$status" -eq 1 ]]
    [[ "$output" == *"Error: retro pass deleted .ralph/learnings.md."* ]]
    cmp .ralph/learnings.md "$TEST_DIR/old.md"
}

@test "an idle retro pass records git.noop true" {
    create_retro_backend
    seed_progress_entry
    write_learnings "old learning"
    run "$RALPH" retro
    [[ "$status" -eq 0 ]]
    [[ "$(last_retro_noop)" == "true" ]]
}

@test "an idle retro pass without a learnings file records git.noop true" {
    create_retro_backend
    seed_progress_entry
    run "$RALPH" retro
    [[ "$status" -eq 0 ]]
    [[ "$(last_retro_noop)" == "true" ]]
}

@test "a retro pass that rewrites the learnings file records git.noop false" {
    create_retro_backend
    seed_progress_entry
    write_learnings "old learning"
    cat > "$TEST_DIR/pass.sh" <<'PASS'
printf '# Learnings\n\n## Environment\n- extra (confirmed 2026-11-15)\n\n## Tooling\n\n## Codebase\n\n## Promote to AGENTS.md\n' > .ralph/learnings.md
PASS
    run "$RALPH" retro
    [[ "$status" -eq 0 ]]
    [[ "$(last_retro_noop)" == "false" ]]
}

@test "a retro pass that writes a first learnings file records git.noop false" {
    create_retro_backend
    seed_progress_entry
    cat > "$TEST_DIR/pass.sh" <<'PASS'
mkdir -p .ralph
printf '# Learnings\n\n## Environment\n\n## Tooling\n\n## Codebase\n\n## Promote to AGENTS.md\n' > .ralph/learnings.md
PASS
    run "$RALPH" retro
    [[ "$status" -eq 0 ]]
    [[ "$(last_retro_noop)" == "false" ]]
}

# Helper: write a pass that rewrites the learnings file, then runs $1.
write_learnings_pass() {
    {
        printf '%s\n' "printf '# Learnings\\n\\n## Environment\\n\\n## Tooling\\n\\n## Codebase\\n\\n## Promote to AGENTS.md\\n' > .ralph/learnings.md"
        printf '%s\n' "$1"
    } > "$TEST_DIR/pass.sh"
}

@test "a retro pass that commits in the workspace fails and restores the file" {
    create_retro_backend
    seed_progress_entry
    write_learnings "old learning"
    cp .ralph/learnings.md "$TEST_DIR/old.md"
    write_learnings_pass 'git commit -q --allow-empty -m "pass commit"'
    run "$RALPH" retro
    [[ "$status" -eq 1 ]]
    [[ "$output" == *"Error: retro pass committed in .; retro may not commit."* ]]
    cmp .ralph/learnings.md "$TEST_DIR/old.md"
}

@test "a retro pass that commits in a nested repository fails and restores the file" {
    create_retro_backend
    seed_progress_entry
    write_learnings "old learning"
    cp .ralph/learnings.md "$TEST_DIR/old.md"
    git init --quiet source/svc
    git -C source/svc config user.email "nested@test.com"
    git -C source/svc config user.name "Nested"
    git -C source/svc commit --allow-empty -m "nested initial" --quiet
    write_learnings_pass 'git -C source/svc commit -q --allow-empty -m "pass commit"'
    run "$RALPH" retro
    [[ "$status" -eq 1 ]]
    [[ "$output" == *"Error: retro pass committed in ./source/svc; retro may not commit."* ]]
    cmp .ralph/learnings.md "$TEST_DIR/old.md"
}

@test "a retro pass that edits a tracked file fails and restores the file" {
    create_retro_backend
    seed_progress_entry
    write_learnings "old learning"
    cp .ralph/learnings.md "$TEST_DIR/old.md"
    echo one > tracked.txt
    git add tracked.txt
    git commit -q -m "add tracked"
    write_learnings_pass 'echo two > tracked.txt'
    run_retro_expecting_tree_failure
    [[ "$(cat tracked.txt)" == "two" ]]
}

@test "a retro pass that edits an operator-modified file fails and restores the file" {
    create_retro_backend
    seed_progress_entry
    write_learnings "old learning"
    cp .ralph/learnings.md "$TEST_DIR/old.md"
    echo one > tracked.txt
    git add tracked.txt
    git commit -q -m "add tracked"
    echo operator > tracked.txt
    write_learnings_pass 'echo pass >> tracked.txt'
    run_retro_expecting_tree_failure
}

@test "a retro pass that stages an operator-modified file fails and restores the file" {
    create_retro_backend
    seed_progress_entry
    write_learnings "old learning"
    cp .ralph/learnings.md "$TEST_DIR/old.md"
    echo one > tracked.txt
    git add tracked.txt
    git commit -q -m "add tracked"
    echo operator > tracked.txt
    write_learnings_pass 'git add tracked.txt'
    run_retro_expecting_tree_failure
}

@test "a retro pass that creates an untracked file fails and restores the file" {
    create_retro_backend
    seed_progress_entry
    write_learnings "old learning"
    cp .ralph/learnings.md "$TEST_DIR/old.md"
    write_learnings_pass 'echo new > "a b.txt"'
    run_retro_expecting_tree_failure
}

@test "a retro pass that replaces an untracked file with a new file fails and restores the file" {
    create_retro_backend
    seed_progress_entry
    write_learnings "old learning"
    cp .ralph/learnings.md "$TEST_DIR/old.md"
    echo one > "a b.txt"
    write_learnings_pass 'echo one > new.txt; mv -f new.txt "a b.txt"'
    run_retro_expecting_tree_failure
}

@test "a retro pass that deletes an untracked file fails and restores the file" {
    create_retro_backend
    seed_progress_entry
    write_learnings "old learning"
    cp .ralph/learnings.md "$TEST_DIR/old.md"
    echo one > "a b.txt"
    write_learnings_pass 'rm "a b.txt"'
    run_retro_expecting_tree_failure
}

@test "a retro pass that replaces an untracked file with a symlink fails and restores the file" {
    create_retro_backend
    seed_progress_entry
    write_learnings "old learning"
    cp .ralph/learnings.md "$TEST_DIR/old.md"
    echo one > "a b.txt"
    echo notes > notes.md
    write_learnings_pass 'ln -sfn notes.md "a b.txt"'
    run_retro_expecting_tree_failure
}

@test "a retro pass that appends to an untracked file passes the tree check" {
    create_retro_backend
    seed_progress_entry
    write_learnings "old learning"
    echo one > "a b.txt"
    write_learnings_pass 'echo two >> "a b.txt"'
    run "$RALPH" retro
    [[ "$status" -eq 0 ]]
    [[ "$(cat "a b.txt")" == $'one\ntwo' ]]
}

@test "a retro pass that rewrites the target of an untracked symlink passes the tree check" {
    create_retro_backend
    seed_progress_entry
    write_learnings "old learning"
    ln -s .ralph/learnings.md LEARNINGS.md
    write_learnings_pass true
    run "$RALPH" retro
    [[ "$status" -eq 0 ]]
}

@test "a retro pass that repoints an untracked symlink fails and restores the file" {
    create_retro_backend
    seed_progress_entry
    write_learnings "old learning"
    cp .ralph/learnings.md "$TEST_DIR/old.md"
    echo notes > notes.md
    ln -s .ralph/learnings.md LEARNINGS.md
    write_learnings_pass 'ln -sfn notes.md LEARNINGS.md'
    run_retro_expecting_tree_failure
}

@test "a retro pass that edits a nested repository fails and names it" {
    create_retro_backend
    seed_progress_entry
    write_learnings "old learning"
    cp .ralph/learnings.md "$TEST_DIR/old.md"
    git init --quiet source/svc
    git -C source/svc config user.email "nested@test.com"
    git -C source/svc config user.name "Nested"
    git -C source/svc commit --allow-empty -m "nested initial" --quiet
    write_learnings_pass 'echo new > source/svc/file.txt'
    run "$RALPH" retro
    [[ "$status" -eq 1 ]]
    [[ "$output" == *"Error: retro pass changed files in ./source/svc; retro may write only .ralph/learnings.md."* ]]
    cmp .ralph/learnings.md "$TEST_DIR/old.md"
}

@test "a retro pass that edits a nested repository with a space in its path fails and names it" {
    create_retro_backend
    seed_progress_entry
    write_learnings "old learning"
    cp .ralph/learnings.md "$TEST_DIR/old.md"
    git init --quiet "my svc"
    git -C "my svc" config user.email "nested@test.com"
    git -C "my svc" config user.name "Nested"
    git -C "my svc" commit --allow-empty -m "nested initial" --quiet
    write_learnings_pass 'echo new > "my svc/app.txt"'
    run "$RALPH" retro
    [[ "$status" -eq 1 ]]
    [[ "$output" == *"Error: retro pass changed files in ./my svc; retro may write only .ralph/learnings.md."* ]]
    cmp .ralph/learnings.md "$TEST_DIR/old.md"
}

@test "a retro pass that writes only the learnings file passes the tree check" {
    create_retro_backend
    seed_progress_entry
    write_learnings "old learning"
    echo operator > "a b.txt"
    write_learnings_pass true
    run "$RALPH" retro
    [[ "$status" -eq 0 ]]
}

@test "a retro pass that edits PROGRESS.md fails and restores the file" {
    setup_artifact_pass 'echo extra >> PROGRESS.md'
    run_retro_expecting_artifact_failure PROGRESS.md
}

@test "a retro pass that edits IMPLEMENTATION_PLAN.md fails and restores the file" {
    setup_artifact_pass 'echo extra >> IMPLEMENTATION_PLAN.md'
    run_retro_expecting_artifact_failure IMPLEMENTATION_PLAN.md
}

@test "a retro pass that edits a PROMPT file fails and restores the file" {
    setup_artifact_pass 'echo extra >> PROMPT_review.md'
    run_retro_expecting_artifact_failure PROMPT_review.md
}

@test "a retro pass that creates ralph.yaml fails and restores the file" {
    setup_artifact_pass 'echo "defaults: {}" > ralph.yaml'
    run_retro_expecting_artifact_failure ralph.yaml
}

@test "a retro pass that edits .ralph/cycle-base fails and restores the file" {
    setup_artifact_pass 'echo ". -" > .ralph/cycle-base'
    seed_cycle_base
    run_retro_expecting_artifact_failure .ralph/cycle-base
}

@test "a retro pass that edits .ralph/cycle-base through a symlinked .ralph fails" {
    setup_artifact_pass 'echo ". -" > .ralph/cycle-base'
    seed_cycle_base
    mv .ralph "$BATS_TEST_TMPDIR/state"
    ln -s "$BATS_TEST_TMPDIR/state" .ralph
    run_retro_expecting_artifact_failure .ralph/cycle-base
}

@test "a retro pass that edits .ralph/learnings.prev.md fails and restores the file" {
    setup_artifact_pass 'echo extra >> .ralph/learnings.prev.md'
    echo previous > .ralph/learnings.prev.md
    run_retro_expecting_artifact_failure .ralph/learnings.prev.md
}

@test "a retro pass that creates .ralph/extra fails and restores the file" {
    setup_artifact_pass 'echo extra > .ralph/extra'
    run_retro_expecting_artifact_failure .ralph/extra
}

@test "a retro pass that deletes a covered artifact fails and restores the file" {
    setup_artifact_pass 'rm PROGRESS.md'
    run_retro_expecting_artifact_failure PROGRESS.md
}

@test "a retro pass that edits a file in an archived cycle fails and names it" {
    setup_artifact_pass 'echo extra >> .ralph/2026-01-01/PROGRESS.md'
    mkdir -p .ralph/2026-01-01
    echo old > .ralph/2026-01-01/PROGRESS.md
    run_retro_expecting_artifact_failure .ralph/2026-01-01/PROGRESS.md
}

@test "a retro pass that writes only learnings and metrics passes the artifact check" {
    "$RALPH" init > /dev/null 2>&1
    create_retro_backend
    seed_progress_entry
    write_learnings "old learning"
    write_learnings_pass true
    run "$RALPH" retro
    [[ "$status" -eq 0 ]]
    [[ -d .ralph/metrics ]]
}

@test "a retro pass that writes a fifth heading fails the format check at its line" {
    setup_format_pass <<'PASS'
printf '# Learnings\n\n## Environment\n\n## Tooling\n\n## Codebase\n\n## Promote to AGENTS.md\n\n## Extra\n' > .ralph/learnings.md
PASS
    run_retro_expecting_format_failure 11
    [[ "$output" == *'unexpected heading "## Extra"'* ]]
}

@test "a retro pass that writes an undated bullet fails the format check at its line" {
    setup_format_pass <<'PASS'
printf '# Learnings\n\n## Environment\n- no date here\n\n## Tooling\n\n## Codebase\n\n## Promote to AGENTS.md\n' > .ralph/learnings.md
PASS
    run_retro_expecting_format_failure 4
}

@test "a retro pass that writes a bullet above Environment fails the format check" {
    setup_format_pass <<'PASS'
printf '# Learnings\n- early (confirmed 2026-11-14)\n## Environment\n\n## Tooling\n\n## Codebase\n\n## Promote to AGENTS.md\n' > .ralph/learnings.md
PASS
    run_retro_expecting_format_failure 2
    [[ "$output" == *'above "## Environment"'* ]]
    [[ "$(grep -c '^Error:' <<<"$output")" -eq 1 ]]
}

@test "a retro pass that omits the last heading fails the format check after the last line" {
    setup_format_pass <<'PASS'
printf '# Learnings\n\n## Environment\n\n## Tooling\n\n## Codebase\n' > .ralph/learnings.md
PASS
    run_retro_expecting_format_failure 8
    [[ "$output" == *'missing heading "## Promote to AGENTS.md"'* ]]
}

@test "a retro pass that writes headings out of order fails the format check" {
    setup_format_pass <<'PASS'
printf '# Learnings\n\n## Tooling\n\n## Environment\n\n## Codebase\n\n## Promote to AGENTS.md\n' > .ralph/learnings.md
PASS
    run_retro_expecting_format_failure 3
}

@test "a retro pass that writes prose fails the format check at its line" {
    setup_format_pass <<'PASS'
printf '# Learnings\n\n## Environment\nSome prose.\n\n## Tooling\n\n## Codebase\n\n## Promote to AGENTS.md\n' > .ralph/learnings.md
PASS
    run_retro_expecting_format_failure 4
}

@test "an idle retro pass fails when the unchanged file already breaks the format" {
    create_retro_backend
    seed_progress_entry
    mkdir -p .ralph
    printf '# Learnings\n\n## Environment\n\n## Tooling\n\n## Codebase\n\n## Promote to AGENTS.md\n\n## Extra\n' > .ralph/learnings.md
    cp .ralph/learnings.md "$TEST_DIR/old.md"
    run_retro_expecting_format_failure 11
}

@test "a retro pass that writes an empty learnings file fails the format check at line 1" {
    setup_format_pass <<'PASS'
: > .ralph/learnings.md
PASS
    run_retro_expecting_format_failure 1
}

@test "a retro pass that writes a wrong title fails the format check at line 1" {
    setup_format_pass <<'PASS'
printf '# Lessons\n\n## Environment\n\n## Tooling\n\n## Codebase\n\n## Promote to AGENTS.md\n' > .ralph/learnings.md
PASS
    run_retro_expecting_format_failure 1
    [[ "$output" == *'line 1: the first line must be "# Learnings"'* ]]
}

@test "a retro pass that writes a placeholder date fails the format check at its line" {
    setup_format_pass <<'PASS'
printf '# Learnings\n\n## Environment\n- placeholder (confirmed YYYY-MM-DD)\n\n## Tooling\n\n## Codebase\n\n## Promote to AGENTS.md\n' > .ralph/learnings.md
PASS
    run_retro_expecting_format_failure 4
}

@test "a retro pass that writes text after the date fails the format check at its line" {
    setup_format_pass <<'PASS'
printf '# Learnings\n\n## Environment\n\n## Tooling\n- trailing (confirmed 2026-11-14) more\n\n## Codebase\n\n## Promote to AGENTS.md\n' > .ralph/learnings.md
PASS
    run_retro_expecting_format_failure 6
}

# Helper: print a pass script that writes a file whose Environment bullets are $1 lines of $2 words.
bullets_pass() {
    cat <<PASS
words=\$(printf 'w %.0s' \$(seq 1 $2))
{
    printf '# Learnings\n\n## Environment\n'
    for _ in \$(seq 1 $1); do printf -- '- %s(confirmed 2026-11-14)\n' "\$words"; done
    printf '\n## Tooling\n\n## Codebase\n\n## Promote to AGENTS.md\n'
} > .ralph/learnings.md
PASS
}

# Helper: seed a retro-ready workspace with a pass that writes $1 Environment bullets of $2 words.
setup_bullets_pass() {
    setup_format_pass < <(bullets_pass "$1" "$2")
}

@test "a retro pass that writes a 41-word bullet fails the format check at its line" {
    setup_bullets_pass 1 41
    run_retro_expecting_format_failure 4
    [[ "$output" == *"more than 40 words"* ]]
}

@test "a retro pass that writes a 40-word bullet passes the format check" {
    setup_bullets_pass 1 40
    run "$RALPH" retro
    [[ "$status" -eq 0 ]]
}

@test "a retro pass that writes a 31st bullet fails the format check at its line" {
    setup_bullets_pass 31 1
    run_retro_expecting_format_failure 34
    [[ "$output" == *"more than 30 bullets"* ]]
}

@test "a retro pass that writes 30 bullets passes the format check" {
    setup_bullets_pass 30 1
    run "$RALPH" retro
    [[ "$status" -eq 0 ]]
}

@test "a retro pass that writes an untargeted promotion fails the format check at its line" {
    setup_format_pass <<'PASS'
printf '# Learnings\n\n## Environment\n\n## Tooling\n\n## Codebase\n\n## Promote to AGENTS.md\n- no target here (confirmed 2026-11-14)\n' > .ralph/learnings.md
PASS
    run_retro_expecting_format_failure 10
    [[ "$output" == *"promotion bullet must start with"* ]]
}

@test "a retro pass that targets a promotion at a wrong file name fails the format check" {
    setup_format_pass <<'PASS'
printf '# Learnings\n\n## Environment\n\n## Tooling\n\n## Codebase\n\n## Promote to AGENTS.md\n- services/api/README.md: fix it (confirmed 2026-11-14)\n' > .ralph/learnings.md
PASS
    run_retro_expecting_format_failure 10
}

@test "a retro pass that targets a promotion at an absolute path fails the format check" {
    setup_format_pass <<'PASS'
printf '# Learnings\n\n## Environment\n\n## Tooling\n\n## Codebase\n\n## Promote to AGENTS.md\n- /abs/AGENTS.md: fix it (confirmed 2026-11-14)\n' > .ralph/learnings.md
PASS
    run_retro_expecting_format_failure 10
    [[ "$output" == *"relative to the workspace root"* ]]
}

@test "a retro pass that targets a promotion above the workspace root fails the format check" {
    setup_format_pass <<'PASS'
printf '# Learnings\n\n## Environment\n\n## Tooling\n\n## Codebase\n\n## Promote to AGENTS.md\n- ../other/CLAUDE.md: fix it (confirmed 2026-11-14)\n' > .ralph/learnings.md
PASS
    run_retro_expecting_format_failure 10
    [[ "$output" == *"may not leave the workspace root"* ]]
}

@test "a retro pass that writes targeted promotions passes the format check" {
    setup_format_pass <<'PASS'
printf '# Learnings\n\n## Environment\n\n## Tooling\n\n## Codebase\n\n## Promote to AGENTS.md\n- services/api/AGENTS.md: fix it (confirmed 2026-11-14)\n- CLAUDE.md: fix that (confirmed 2026-11-14)\n' > .ralph/learnings.md
PASS
    run "$RALPH" retro
    [[ "$status" -eq 0 ]]
}

@test "a retro pass prints the added, dropped and refreshed counts of a known pair" {
    create_retro_backend
    seed_progress_entry
    mkdir -p .ralph
    printf '# Learnings\n\n## Environment\n- keep me (confirmed 2026-11-01)\n- refresh me (confirmed 2026-11-01)\n\n## Tooling\n- reword me (confirmed 2026-11-01)\n- drop me (confirmed 2026-11-01)\n\n## Codebase\n\n## Promote to AGENTS.md\n' > .ralph/learnings.md
    cat > "$TEST_DIR/pass.sh" <<'PASS'
printf '# Learnings\n\n## Environment\n- keep me (confirmed 2026-11-01)\n- refresh me (confirmed 2026-11-14)\n\n## Tooling\n- reworded me (confirmed 2026-11-14)\n\n## Codebase\n- add me (confirmed 2026-11-14)\n\n## Promote to AGENTS.md\n' > .ralph/learnings.md
PASS
    run --separate-stderr "$RALPH" retro
    [[ "$status" -eq 0 ]]
    [[ "$stderr" == *"Retro kept 4 learnings: 2 added, 2 dropped, 1 refreshed."* ]]
    [[ "$output" != *"Retro kept"* ]]
}

@test "a retro pass counts the same text under another heading as dropped and added" {
    create_retro_backend
    seed_progress_entry
    write_learnings "moving text"
    cat > "$TEST_DIR/pass.sh" <<'PASS'
printf '# Learnings\n\n## Environment\n\n## Tooling\n- moving text (confirmed 2026-11-14)\n\n## Codebase\n\n## Promote to AGENTS.md\n' > .ralph/learnings.md
PASS
    run "$RALPH" retro
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"Retro kept 1 learnings: 1 added, 1 dropped, 0 refreshed."* ]]
}

@test "a first retro pass without an old file counts every bullet as added" {
    create_retro_backend
    seed_progress_entry
    cat > "$TEST_DIR/pass.sh" <<'PASS'
printf '# Learnings\n\n## Environment\n- first (confirmed 2026-11-14)\n\n## Tooling\n- second (confirmed 2026-11-14)\n\n## Codebase\n\n## Promote to AGENTS.md\n' > .ralph/learnings.md
PASS
    run "$RALPH" retro
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"Retro kept 2 learnings: 2 added, 0 dropped, 0 refreshed."* ]]
}

@test "an idle retro pass keeps every bullet and prints no change" {
    create_retro_backend
    seed_progress_entry
    write_learnings "steady"
    run "$RALPH" retro
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"Retro kept 1 learnings: 0 added, 0 dropped, 0 refreshed."* ]]
}

@test "a failed retro pass prints no summary" {
    create_retro_backend
    seed_progress_entry
    write_learnings "steady"
    export MOCK_EXIT=1
    run "$RALPH" retro
    [[ "$status" -eq 1 ]]
    [[ "$output" != *"Retro kept"* ]]
}

@test "a retro pass prints the promotion banner with each target and the count" {
    create_retro_backend
    seed_progress_entry
    cat > "$TEST_DIR/pass.sh" <<'PASS'
printf '# Learnings\n\n## Environment\n\n## Tooling\n\n## Codebase\n\n## Promote to AGENTS.md\n- AGENTS.md: state the JDK command (confirmed 2026-11-14)\n- services/api/AGENTS.md: state the port (confirmed 2026-11-14)\n' > .ralph/learnings.md
PASS
    run --separate-stderr "$RALPH" retro
    [[ "$status" -eq 0 ]]
    rule=$(printf '=%.0s' $(seq 1 64))
    [[ "$stderr" == *"$rule"$'\n'"⚠️  2 learnings belong in a guardrails file. Move them by hand:"* ]]
    [[ "$stderr" == *"⚠️    - AGENTS.md: state the JDK command"$'\n'* ]]
    [[ "$stderr" == *"⚠️    - services/api/AGENTS.md: state the port"$'\n'"$rule"* ]]
    [[ "$stderr" != *"(confirmed 2026-11-14)"$'\n'"$rule"* ]]
    [[ "$output" != *"⚠️"* ]]
    [[ "$(grep -cx '================================================================' <<<"$stderr")" -eq 2 ]]
}

@test "a retro pass counts a tabbed bullet with a new date as refreshed" {
    create_retro_backend
    seed_progress_entry
    mkdir -p .ralph
    printf '# Learnings\n\n## Environment\n- split\there (confirmed 2026-11-01)\n\n## Tooling\n\n## Codebase\n\n## Promote to AGENTS.md\n' > .ralph/learnings.md
    cat > "$TEST_DIR/pass.sh" <<'PASS'
printf '# Learnings\n\n## Environment\n- split\there (confirmed 2026-11-14)\n\n## Tooling\n\n## Codebase\n\n## Promote to AGENTS.md\n' > .ralph/learnings.md
PASS
    run "$RALPH" retro
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"Retro kept 1 learnings: 0 added, 0 dropped, 1 refreshed."* ]]
}

@test "a retro pass prints a tabbed promotion bullet whole in the banner" {
    create_retro_backend
    seed_progress_entry
    cat > "$TEST_DIR/pass.sh" <<'PASS'
printf '# Learnings\n\n## Environment\n\n## Tooling\n\n## Codebase\n\n## Promote to AGENTS.md\n- AGENTS.md: state\tthe port (confirmed 2026-11-14)\n' > .ralph/learnings.md
PASS
    run "$RALPH" retro
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"⚠️    - AGENTS.md: state"$'\t'"the port"$'\n'* ]]
}

@test "a retro pass with an empty promotion section prints no banner" {
    create_retro_backend
    seed_progress_entry
    write_learnings "steady"
    run "$RALPH" retro
    [[ "$status" -eq 0 ]]
    [[ "$output" != *"Move them by hand"* ]]
    rule=$(printf '=%.0s' $(seq 1 64))
    [[ "$output" != *$'\n'"$rule"$'\n'* ]]
}

@test "the retro prompt names the four headings and the dated bullet form" {
    prompt="$BATS_TEST_DIRNAME/../prompts/retro.md"
    for heading in "## Environment" "## Tooling" "## Codebase" "## Promote to AGENTS.md"; do
        grep -qxF "$heading" "$prompt"
    done
    grep -qF "(confirmed YYYY-MM-DD)" "$prompt"
}

@test "the retro prompt writes only the learnings file and never reads the metrics" {
    prompt="$BATS_TEST_DIRNAME/../prompts/retro.md"
    grep -qF "Write \`{{WORKSPACE}}/.ralph/learnings.md\` and no other file" "$prompt"
    grep -qF "Never read \`{{WORKSPACE}}/.ralph/metrics/\`" "$prompt"
}

@test "the retro prompt exemplar passes the format check" {
    create_retro_backend
    seed_progress_entry
    awk '/^```$/ { n++; next } n == 1' "$BATS_TEST_DIRNAME/../prompts/retro.md" > "$TEST_DIR/exemplar.md"
    [[ -s "$TEST_DIR/exemplar.md" ]]
    cat > "$TEST_DIR/pass.sh" <<'PASS'
mkdir -p .ralph
cp "$TEST_DIR/exemplar.md" .ralph/learnings.md
PASS
    run "$RALPH" retro
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"Retro kept 4 learnings: 4 added, 0 dropped, 0 refreshed."* ]]
}

@test "archive and clean keep both learnings files" {
    seed_progress_entry
    write_learnings "kept learning"
    echo "undo" > .ralph/learnings.prev.md
    cp .ralph/learnings.md "$TEST_DIR/learnings.md"
    run "$RALPH" archive
    [[ "$status" -eq 0 ]]
    cmp .ralph/learnings.md "$TEST_DIR/learnings.md"
    [[ "$(cat .ralph/learnings.prev.md)" == "undo" ]]
    [[ -z "$(find .ralph -mindepth 2 -name 'learnings*.md')" ]]
    seed_progress_entry
    run "$RALPH" clean
    [[ "$status" -eq 0 ]]
    cmp .ralph/learnings.md "$TEST_DIR/learnings.md"
    [[ "$(cat .ralph/learnings.prev.md)" == "undo" ]]
}

@test "init creates neither learnings file" {
    run "$RALPH" init --prompts
    [[ "$status" -eq 0 ]]
    [[ ! -e .ralph/learnings.md ]]
    [[ ! -e .ralph/learnings.prev.md ]]
}

@test "install.sh installs the retro prompt" {
    RALPH_BIN_DIR="$TEST_DIR/install-bin" run "$BATS_TEST_DIRNAME/../install.sh"
    [[ "$status" -eq 0 ]]
    cmp "$BATS_TEST_DIRNAME/../prompts/retro.md" "$RALPH_CONFIG_DIR/prompts/retro.md"
}

@test "the repository .gitignore lists the retro prompt once" {
    [[ "$(grep -cxF 'PROMPT_retro.md' "$BATS_TEST_DIRNAME/../.gitignore")" -eq 1 ]]
}

@test "plan, build and review prompts point at the learnings file" {
    local prompt
    for prompt in plan build review; do
        grep -qF '{{WORKSPACE}}/.ralph/learnings.md' "$BATS_TEST_DIRNAME/../prompts/$prompt.md"
    done
}

@test "each learnings bullet follows the progress-log bullet" {
    local prompt
    for prompt in plan build review; do
        grep -A1 '^- \*\*Progress log\*\*' "$BATS_TEST_DIRNAME/../prompts/$prompt.md" | grep -q '^- \*\*Learnings\*\*'
    done
}

@test "each learnings bullet forbids a review finding against the file" {
    local prompt
    for prompt in plan build review; do
        grep '^- \*\*Learnings\*\*' "$BATS_TEST_DIRNAME/../prompts/$prompt.md" | grep -qF 'Never file a review finding against it'
    done
}

@test "the build prompt lists the retro prompt as a loop artifact" {
    grep '\*\*Exclude loop artifacts\*\*' "$BATS_TEST_DIRNAME/../prompts/build.md" | grep -qF "\`PROMPT_retro.md\`"
}

@test "the config template carries a retro section with a sonnet model" {
    awk '/^retro:/ { found = 1; next } /^[a-z]/ { found = 0 } found' "$BATS_TEST_DIRNAME/../templates/config.yaml" > "$TEST_DIR/retro-section.yaml"
    grep -qxF '  # model: sonnet' "$TEST_DIR/retro-section.yaml"
}
