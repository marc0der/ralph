#!/usr/bin/env bats

load test_helper

# The guard after each plan pass: a pass may commit under specs/ and nothing
# else, may not delete or move a spec, and may not leave specs/ dirty.

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

add_bare_origin() {
    git init --bare --quiet "$TEST_DIR/remote.git"
    git remote add origin "$TEST_DIR/remote.git"
}

# Commit specs/existing.md before the plan runs, so a pass can edit, delete or move it.
seed_committed_spec() {
    mkdir -p specs
    echo "# Existing" > specs/existing.md
    git add -- specs/existing.md
    git commit -q -m "docs(specs): add existing"
}

# Create a repository at $1 with one commit, copied from nested_repos.bats.
init_repo() {
    local path="$1"
    mkdir -p "$path"
    git -C "$path" init --quiet
    git -C "$path" config user.email "nested@test.com"
    git -C "$path" config user.name "Nested"
    git -C "$path" commit --allow-empty -m "nested initial" --quiet
}

run_plan() {
    PATH="$TEST_DIR/bin:$PATH" run "$RALPH" plan -g "the goal" "$@"
}

@test "a pass that commits a new spec and a nested spec edit passes and pushes" {
    "$RALPH" init
    mkdir -p specs/features
    echo "# Feature" > specs/features/03-foo.md
    git add -- specs/features/03-foo.md
    git commit -q -m "docs(specs): add feature"
    add_bare_origin
    create_scripted_backend
    on_iteration 1 'echo "# New" > specs/new.md && echo "edit" >> specs/features/03-foo.md &&
git add -- specs/new.md specs/features/03-foo.md && git commit -q -m "docs(specs): record decision"'

    run_plan
    [ "$status" -eq 0 ]
    [[ "$output" != *"Error: plan pass"* ]]
    [[ "$(git ls-remote origin)" == *"$(git rev-parse HEAD)"* ]]
    [[ "$(git log -1 --format=%s)" == "docs(specs): record decision" ]]
}

@test "a pass that commits README.md fails and pushes nothing" {
    "$RALPH" init
    add_bare_origin
    create_scripted_backend
    on_iteration 1 'echo "x" > README.md && git add -- README.md && git commit -q -m "docs: readme"'

    run_plan
    [ "$status" -eq 1 ]
    [[ "$output" == *"Error: plan pass 1 committed README.md in ., which is outside specs/."* ]]
    [ -z "$(git ls-remote origin)" ]
}

@test "a pass that deletes a spec fails with the deletion error" {
    "$RALPH" init
    seed_committed_spec
    create_scripted_backend
    on_iteration 1 'git rm -q -- specs/existing.md && git commit -q -m "docs(specs): drop existing"'

    run_plan --skip-push
    [ "$status" -eq 1 ]
    [[ "$output" == *"Error: plan pass 1 deleted specs/existing.md in .; plan may not delete or move a spec."* ]]
}

@test "a pass that renames a spec fails with the deletion error" {
    "$RALPH" init
    seed_committed_spec
    create_scripted_backend
    on_iteration 1 'git mv -- specs/existing.md specs/moved.md && git commit -q -m "docs(specs): move existing"'

    run_plan --skip-push
    [ "$status" -eq 1 ]
    [[ "$output" == *"Error: plan pass 1 deleted specs/existing.md in .; plan may not delete or move a spec."* ]]
}

@test "a pass that leaves a spec edit uncommitted fails" {
    "$RALPH" init
    seed_committed_spec
    create_scripted_backend
    on_iteration 1 'echo "edit" >> specs/existing.md'

    run_plan --skip-push
    [ "$status" -eq 1 ]
    [[ "$output" == *"Error: plan pass 1 left uncommitted changes under specs/ in .."* ]]
}

@test "the uncommitted failure names a project-local PROMPT_plan.md" {
    "$RALPH" init
    seed_committed_spec
    echo "# Local plan prompt" > PROMPT_plan.md
    create_scripted_backend
    on_iteration 1 'echo "edit" >> specs/existing.md'

    run_plan --skip-push
    [ "$status" -eq 1 ]
    [[ "$output" == *"left uncommitted changes under specs/"* ]]
    [[ "$output" == *"This project has its own PROMPT_plan.md; add the commit step from the installed prompts/plan.md."* ]]
}

@test "the uncommitted failure without a local prompt omits the stale-prompt line" {
    "$RALPH" init
    seed_committed_spec
    create_scripted_backend
    on_iteration 1 'echo "edit" >> specs/existing.md'

    run_plan --skip-push
    [ "$status" -eq 1 ]
    [[ "$output" == *"left uncommitted changes under specs/"* ]]
    [[ "$output" != *"This project has its own PROMPT_plan.md"* ]]
}

@test "a pass that commits nothing passes" {
    "$RALPH" init
    create_scripted_backend

    run_plan --skip-push
    [ "$status" -eq 0 ]
    [[ "$output" != *"Error: plan pass"* ]]
    [[ "$output" == *"Completed 1 iteration"* ]]
}

@test "a pass that commits a nested spec and bumps its gitlink passes" {
    "$RALPH" init
    init_repo source/svc
    git -c advice.addEmbeddedRepo=false add -- source/svc
    git commit -q -m "chore: add source/svc"
    create_scripted_backend
    # shellcheck disable=SC2016 # $(...) expands when the mock sources the snippet
    on_iteration 1 'mkdir -p source/svc/specs && echo "# Svc" > source/svc/specs/x.md &&
git -C source/svc add -- specs/x.md && git -C source/svc commit -q -m "docs(specs): add svc spec" &&
git add -- source/svc && git commit -q -m "chore: bump source/svc to $(git -C source/svc rev-parse --short HEAD)"'

    run_plan --skip-push
    [ "$status" -eq 0 ]
    [[ "$output" != *"Error: plan pass"* ]]
    [[ "$(git log -1 --format=%s)" == "chore: bump source/svc to "* ]]
    [[ "$(git ls-tree HEAD source/svc)" == "160000 commit $(git -C source/svc rev-parse HEAD)"* ]]
}

@test "a pass in a repository with no commits before it checks every commit" {
    "$RALPH" init
    mkdir -p source/empty
    git -C source/empty init --quiet
    git -C source/empty config user.email "nested@test.com"
    git -C source/empty config user.name "Nested"
    echo "source/" >> .gitignore
    git add -- .gitignore
    git commit -q -m "chore: ignore source"
    create_scripted_backend
    on_iteration 1 'echo "x" > source/empty/README.md && git -C source/empty add -- README.md &&
git -C source/empty commit -q -m "docs: readme" &&
mkdir -p source/empty/specs && echo "# Spec" > source/empty/specs/x.md &&
git -C source/empty add -- specs/x.md && git -C source/empty commit -q -m "docs(specs): add spec"'

    run_plan --skip-push
    [ "$status" -eq 1 ]
    [[ "$output" == *"Error: plan pass 1 committed README.md in ./source/empty, which is outside specs/."* ]]
}
