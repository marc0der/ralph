#!/usr/bin/env bats

load test_helper

# Change detection for nested git repositories. A build iteration that commits
# only inside a nested repository leaves the workspace HEAD where it was, so
# these tests all measure the verdict indirectly: how many iterations the loop
# ran before the 2-consecutive-noop exit fired.
#
# --dry-run cannot exercise any of this — the whole early-exit block is wrapped
# in `if ! $dry_run` — so every test runs a mock backend.

# Seed a plan with N open items. Build sizes its loop at ceil(N * 1.2), so
# 3 items give 4 iterations: enough room for an early exit to be visible.
seed_items() {
    local i
    for ((i = 1; i <= ${1:-3}; i++)); do
        echo "- [ ] **Task $i**" >> IMPLEMENTATION_PLAN.md
    done
}

# The symlinked-checkout case needs its link target outside the workspace, so
# it makes a second temp directory. Cleaning that needs a teardown, which
# replaces the helper's — so this one removes $TEST_DIR as well.
teardown() {
    rm -rf "$TEST_DIR"
    [[ -n "${LINK_TARGET:-}" ]] && rm -rf "$LINK_TARGET"
    return 0
}

# Create a repository at $1 with one commit. $1 may sit outside the workspace.
init_repo() {
    local path="$1"
    mkdir -p "$path"
    git -C "$path" init --quiet
    git -C "$path" config user.email "nested@test.com"
    git -C "$path" config user.name "Nested"
    git -C "$path" commit --allow-empty -m "nested initial" --quiet
}

# Create a nested repository at $1 with one commit, and gitignore its top
# directory so the workspace repository never sees it.
nested_repo() {
    local path="$1"
    init_repo "$path"
    echo "${path%%/*}/" >> .gitignore
}

# Mock backend that commits into $TARGET_REPO on every iteration and touches
# nothing in the workspace.
create_nested_committing_backend() {
    mkdir -p "$TEST_DIR/bin"
    cat > "$TEST_DIR/bin/claude" <<'MOCK'
#!/usr/bin/env bash
cat > /dev/null
git -C "$TARGET_REPO" commit --allow-empty -m "nested work" --quiet
echo '{"type":"result","result":"done"}'
MOCK
    chmod +x "$TEST_DIR/bin/claude"
}

# Mock backend that changes nothing anywhere.
create_idle_backend() {
    mkdir -p "$TEST_DIR/bin"
    cat > "$TEST_DIR/bin/claude" <<'MOCK'
#!/usr/bin/env bash
cat > /dev/null
echo '{"type":"result","result":"nothing to do"}'
MOCK
    chmod +x "$TEST_DIR/bin/claude"
}

# Mock backend that sources $TEST_DIR/script/<n> on iteration n, using the
# CALL_LOG counter idiom from pipeline.bats. Register snippets with
# on_iteration; an iteration with no snippet does nothing.
create_scripted_backend() {
    mkdir -p "$TEST_DIR/bin" "$TEST_DIR/script"
    cat > "$TEST_DIR/bin/claude" <<MOCK
#!/usr/bin/env bash
cat > /dev/null
CALL_LOG="$TEST_DIR/call_count"
count=0
[[ -f "\$CALL_LOG" ]] && count=\$(cat "\$CALL_LOG")
count=\$((count + 1))
echo "\$count" > "\$CALL_LOG"
[[ -f "$TEST_DIR/script/\$count" ]] && . "$TEST_DIR/script/\$count"
echo '{"type":"result","result":"done"}'
MOCK
    chmod +x "$TEST_DIR/bin/claude"
}

# Register the snippet for iteration $1.
on_iteration() {
    local n="$1"; shift
    printf '%s\n' "$*" > "$TEST_DIR/script/$n"
}

# --- Core detection ---

@test "a commit in a nested repository prevents the 2-noop exit" {
    "$RALPH" init
    seed_items 3
    nested_repo "source/svc"
    create_nested_committing_backend

    TARGET_REPO="source/svc" PATH="$TEST_DIR/bin:$PATH" run "$RALPH" build --skip-push
    [ "$status" -eq 0 ]
    [[ "$output" != *"No changes detected"* ]]
    [[ "$output" == *"Completed 4 iterations"* ]]
}

@test "two iterations that move no repository still exit early" {
    "$RALPH" init
    seed_items 3
    nested_repo "source/svc"
    create_idle_backend

    PATH="$TEST_DIR/bin:$PATH" run "$RALPH" build --skip-push
    [ "$status" -eq 0 ]
    [[ "$output" == *"No changes detected for 2 consecutive iterations"* ]]
    [[ "$output" == *"Completed 2 iterations"* ]]
}

@test "a nested repository that appears counts as a change" {
    "$RALPH" init
    seed_items 3
    echo "source/" >> .gitignore
    create_scripted_backend
    on_iteration 1 "mkdir -p source/late && git -C source/late init --quiet"

    PATH="$TEST_DIR/bin:$PATH" run "$RALPH" build --skip-push
    [ "$status" -eq 0 ]
    # Without detection the run would stop at iteration 2; the appearance
    # resets the counter, so the exit lands one iteration later.
    [[ "$output" == *"No changes detected for 2 consecutive iterations"* ]]
    [[ "$output" == *"Completed 3 iterations"* ]]
}

@test "a nested repository that vanishes counts as a change" {
    "$RALPH" init
    seed_items 3
    nested_repo "source/svc"
    create_scripted_backend
    on_iteration 1 "rm -rf source/svc"

    PATH="$TEST_DIR/bin:$PATH" run "$RALPH" build --skip-push
    [ "$status" -eq 0 ]
    [[ "$output" == *"No changes detected for 2 consecutive iterations"* ]]
    [[ "$output" == *"Completed 3 iterations"* ]]
}

@test "dirty nested files are no change but a later commit is" {
    "$RALPH" init
    seed_items 4
    nested_repo "source/svc"
    create_scripted_backend
    on_iteration 1 "echo one > source/svc/work.txt"
    on_iteration 2 "echo two >> source/svc/work.txt; git -C source/svc add -A; git -C source/svc commit -q -m committed"

    PATH="$TEST_DIR/bin:$PATH" run "$RALPH" build --skip-push
    [ "$status" -eq 0 ]
    # Iteration 1 is a noop (dirty only), 2 is a change, 3 and 4 are noops.
    # A script that watched nothing would stop at iteration 2.
    [[ "$output" == *"No changes detected for 2 consecutive iterations"* ]]
    [[ "$output" == *"Completed 4 iterations"* ]]
}

# --- Discovery bounds ---

@test "a nested repository whose path contains a space is watched" {
    "$RALPH" init
    seed_items 3
    nested_repo "my source/the svc"
    create_nested_committing_backend

    TARGET_REPO="my source/the svc" PATH="$TEST_DIR/bin:$PATH" run "$RALPH" build --skip-push
    [ "$status" -eq 0 ]
    [[ "$output" != *"No changes detected"* ]]
    [[ "$output" == *"Completed 4 iterations"* ]]
}

@test "a repository whose .git is a file is watched" {
    "$RALPH" init
    seed_items 3
    nested_repo "source/main"
    git -C source/main worktree add --quiet -b wt ../tree
    [ -f source/tree/.git ]
    create_nested_committing_backend

    TARGET_REPO="source/tree" PATH="$TEST_DIR/bin:$PATH" run "$RALPH" build --skip-push
    [ "$status" -eq 0 ]
    [[ "$output" != *"No changes detected"* ]]
    [[ "$output" == *"Completed 4 iterations"* ]]
}

@test "depth 6 is watched and depth 7 is not" {
    "$RALPH" init
    seed_items 3
    nested_repo "a/b/c/d/e"
    nested_repo "a/b/c/d/e2/f"
    create_nested_committing_backend

    # Depth 7: ./a/b/c/d/e2/f/.git is beyond -maxdepth 6, so every iteration
    # reads as a noop and the exit fires at 2.
    TARGET_REPO="a/b/c/d/e2/f" PATH="$TEST_DIR/bin:$PATH" run "$RALPH" build --skip-push
    [ "$status" -eq 0 ]
    [[ "$output" == *"Completed 2 iterations"* ]]

    # Depth 6: ./a/b/c/d/e/.git is inside the bound.
    rm -f "$TEST_DIR/call_count"
    TARGET_REPO="a/b/c/d/e" PATH="$TEST_DIR/bin:$PATH" run "$RALPH" build --skip-push
    [ "$status" -eq 0 ]
    [[ "$output" != *"No changes detected"* ]]
    [[ "$output" == *"Completed 4 iterations"* ]]
}

@test "a repository inside a watched repository is watched, and so is the outer one" {
    "$RALPH" init
    seed_items 3
    nested_repo "source/outer"
    nested_repo "source/outer/inner"
    create_nested_committing_backend

    # -prune stops find descending into ./source/outer/.git; it does not prune
    # ./source/outer, so the inner repository is listed too.
    TARGET_REPO="source/outer/inner" PATH="$TEST_DIR/bin:$PATH" run "$RALPH" build --skip-push
    [ "$status" -eq 0 ]
    [[ "$output" != *"No changes detected"* ]]
    [[ "$output" == *"Completed 4 iterations"* ]]

    TARGET_REPO="source/outer" PATH="$TEST_DIR/bin:$PATH" run "$RALPH" build --skip-push
    [ "$status" -eq 0 ]
    [[ "$output" != *"No changes detected"* ]]
    [[ "$output" == *"Completed 4 iterations"* ]]
}

@test "an idle run with a commitless nested repository still exits after two noops" {
    "$RALPH" init
    seed_items 3
    mkdir -p source/empty
    git -C source/empty init --quiet
    echo "source/" >> .gitignore
    create_idle_backend

    PATH="$TEST_DIR/bin:$PATH" run "$RALPH" build --skip-push
    [ "$status" -eq 0 ]
    [[ "$output" == *"No changes detected for 2 consecutive iterations"* ]]
    [[ "$output" == *"Completed 2 iterations"* ]]
}

@test "the first commit in a commitless nested repository counts as a change" {
    "$RALPH" init
    seed_items 3
    mkdir -p source/empty
    git -C source/empty init --quiet
    git -C source/empty config user.email "nested@test.com"
    git -C source/empty config user.name "Nested"
    echo "source/" >> .gitignore
    create_scripted_backend
    on_iteration 1 "git -C source/empty commit --allow-empty -q -m first"

    PATH="$TEST_DIR/bin:$PATH" run "$RALPH" build --skip-push
    [ "$status" -eq 0 ]
    [[ "$output" == *"No changes detected for 2 consecutive iterations"* ]]
    [[ "$output" == *"Completed 3 iterations"* ]]
}

@test "an unchanged nested repository beside a moved one still allows the exit" {
    "$RALPH" init
    seed_items 3
    nested_repo "source/moved"
    nested_repo "source/still"
    create_scripted_backend
    on_iteration 1 "git -C source/moved commit --allow-empty -q -m work"

    PATH="$TEST_DIR/bin:$PATH" run "$RALPH" build --skip-push
    [ "$status" -eq 0 ]
    [[ "$output" == *"No changes detected for 2 consecutive iterations"* ]]
    [[ "$output" == *"Completed 3 iterations"* ]]
}

# --- Symlinked checkouts ---

@test "a commit in a repository reached through a symlink prevents the exit" {
    "$RALPH" init
    seed_items 3
    # The realistic symlinked checkout points outside the workspace — that is
    # why it is a symlink — so the target is a sibling temp directory. Without
    # `find -L` the clone is invisible and the run stops at iteration 2.
    LINK_TARGET="$(mktemp -d)"
    init_repo "$LINK_TARGET/svc"
    ln -s "$LINK_TARGET" source
    echo "source/" >> .gitignore
    create_nested_committing_backend

    TARGET_REPO="source/svc" PATH="$TEST_DIR/bin:$PATH" run "$RALPH" build --skip-push
    [ "$status" -eq 0 ]
    [[ "$output" != *"No changes detected"* ]]
    [[ "$output" == *"Completed 4 iterations"* ]]
}

@test "a symlink loop leaves the noop exit intact" {
    "$RALPH" init
    seed_items 3
    nested_repo "source/svc"
    # `self -> .` is a true loop: find reports it on stderr, which repo_state
    # discards, and declines to descend. The listing must stay stable so two
    # idle iterations still read as noops.
    ln -s . self
    create_idle_backend

    PATH="$TEST_DIR/bin:$PATH" run "$RALPH" build --skip-push
    [ "$status" -eq 0 ]
    [[ "$output" == *"No changes detected for 2 consecutive iterations"* ]]
    [[ "$output" == *"Completed 2 iterations"* ]]
}

# --- Flag and mode interactions ---

@test "build -n 3 ignores the noop exit with a nested repository present" {
    "$RALPH" init
    seed_items 3
    nested_repo "source/svc"
    create_idle_backend

    PATH="$TEST_DIR/bin:$PATH" run "$RALPH" build -n 3 --skip-push
    [ "$status" -eq 0 ]
    [[ "$output" != *"No changes detected"* ]]
    [[ "$output" == *"Completed 3 iterations"* ]]
}

@test "build --no-metrics detects a nested commit" {
    "$RALPH" init
    seed_items 3
    nested_repo "source/svc"
    create_nested_committing_backend

    TARGET_REPO="source/svc" PATH="$TEST_DIR/bin:$PATH" run "$RALPH" build --skip-push --no-metrics
    [ "$status" -eq 0 ]
    [[ "$output" != *"No changes detected"* ]]
    [[ "$output" == *"Completed 4 iterations"* ]]
}

@test "build --no-metrics still exits after two noops" {
    "$RALPH" init
    seed_items 3
    nested_repo "source/svc"
    create_idle_backend

    PATH="$TEST_DIR/bin:$PATH" run "$RALPH" build --skip-push --no-metrics
    [ "$status" -eq 0 ]
    [[ "$output" == *"No changes detected for 2 consecutive iterations"* ]]
    [[ "$output" == *"Completed 2 iterations"* ]]
}

@test "plan converges while a nested repository moves" {
    "$RALPH" init
    nested_repo "source/svc"
    create_nested_committing_backend

    TARGET_REPO="source/svc" PATH="$TEST_DIR/bin:$PATH" run "$RALPH" plan --skip-push
    [ "$status" -eq 0 ]
    [[ "$output" == *"Plan converged — pass 1 changed nothing"* ]]
    [[ "$output" == *"Completed 1 iterations"* ]]
}

@test "review converges while a nested repository moves" {
    "$RALPH" init
    printf -- '- [x] **Shipped task**\n' >> IMPLEMENTATION_PLAN.md
    nested_repo "source/svc"
    create_nested_committing_backend

    TARGET_REPO="source/svc" PATH="$TEST_DIR/bin:$PATH" run "$RALPH" review --skip-push
    [ "$status" -eq 0 ]
    [[ "$output" == *"Review converged — pass 1 found nothing new"* ]]
    [[ "$output" == *"Completed 1 iterations"* ]]
}
