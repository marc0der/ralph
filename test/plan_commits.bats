#!/usr/bin/env bats

load test_helper

# The guard after each plan pass: a pass may create and edit specs, but may not
# commit in any repository, nor delete or move a spec.

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

# Count the commits on HEAD in repository $1 (default: the workspace).
commit_count() {
    git -C "${1:-.}" rev-list --count HEAD
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

@test "a pass that commits a spec fails with the commit error" {
    "$RALPH" init
    create_scripted_backend
    on_iteration 1 'mkdir -p specs && echo "# New" > specs/new.md &&
git add -- specs/new.md && git commit -q -m "docs(specs): record decision"'

    run_plan --skip-push
    [ "$status" -eq 1 ]
    [[ "$output" == *"Error: plan pass 1 committed in .; plan may not commit, Ralph commits its spec changes."* ]]
    [[ "$output" != *"This project has its own PROMPT_plan.md"* ]]
    [[ "$(git log -1 --format=%s)" == "docs(specs): record decision" ]]
}

@test "the commit failure names a project-local PROMPT_plan.md" {
    "$RALPH" init
    echo "# Local plan prompt" > PROMPT_plan.md
    create_scripted_backend
    on_iteration 1 'mkdir -p specs && echo "# New" > specs/new.md &&
git add -- specs/new.md && git commit -q -m "docs(specs): record decision"'

    run_plan --skip-push
    [ "$status" -eq 1 ]
    [[ "$output" == *"Error: plan pass 1 committed in .; plan may not commit, Ralph commits its spec changes."* ]]
    [[ "$output" == *"This project has its own PROMPT_plan.md; remove its commit step, or delete it and run 'ralph init --prompts'."* ]]
}

@test "a pass that commits README.md fails with the commit error and pushes nothing" {
    "$RALPH" init
    add_bare_origin
    create_scripted_backend
    on_iteration 1 'echo "x" > README.md && git add -- README.md && git commit -q -m "docs: readme"'

    run_plan
    [ "$status" -eq 1 ]
    [[ "$output" == *"Error: plan pass 1 committed in .; plan may not commit, Ralph commits its spec changes."* ]]
    [ -z "$(git ls-remote origin)" ]
}

@test "a pass that commits in a nested repository fails with the commit error" {
    "$RALPH" init
    init_repo source/svc
    git -c advice.addEmbeddedRepo=false add -- source/svc
    git commit -q -m "chore: add source/svc"
    create_scripted_backend
    on_iteration 1 'mkdir -p source/svc/specs && echo "# Svc" > source/svc/specs/x.md &&
git -C source/svc add -- specs/x.md && git -C source/svc commit -q -m "docs(specs): add svc spec"'

    run_plan --skip-push
    [ "$status" -eq 1 ]
    [[ "$output" == *"Error: plan pass 1 committed in ./source/svc; plan may not commit, Ralph commits its spec changes."* ]]
}

@test "a pass that makes the first commit in a nested repository fails" {
    "$RALPH" init
    mkdir -p source/empty
    git -C source/empty init --quiet
    git -C source/empty config user.email "nested@test.com"
    git -C source/empty config user.name "Nested"
    echo "source/" >> .gitignore
    git add -- .gitignore
    git commit -q -m "chore: ignore source"
    create_scripted_backend
    on_iteration 1 'mkdir -p source/empty/specs && echo "# Spec" > source/empty/specs/x.md &&
git -C source/empty add -- specs/x.md && git -C source/empty commit -q -m "docs(specs): add spec"'

    run_plan --skip-push
    [ "$status" -eq 1 ]
    [[ "$output" == *"Error: plan pass 1 committed in ./source/empty; plan may not commit, Ralph commits its spec changes."* ]]
}

@test "a pass that deletes a spec fails with the deletion error" {
    "$RALPH" init
    seed_committed_spec
    create_scripted_backend
    on_iteration 1 'rm -- specs/existing.md'

    run_plan --skip-push
    [ "$status" -eq 1 ]
    [[ "$output" == *"Error: plan pass 1 deleted specs/existing.md in .; plan may not delete or move a spec."* ]]
}

@test "a pass that stages a spec deletion fails with the deletion error" {
    "$RALPH" init
    seed_committed_spec
    create_scripted_backend
    on_iteration 1 'git rm -q -- specs/existing.md'

    run_plan --skip-push
    [ "$status" -eq 1 ]
    [[ "$output" == *"Error: plan pass 1 deleted specs/existing.md in .; plan may not delete or move a spec."* ]]
}

@test "a pass that renames a spec fails with the deletion error" {
    "$RALPH" init
    seed_committed_spec
    create_scripted_backend
    on_iteration 1 'git mv -- specs/existing.md specs/moved.md'

    run_plan --skip-push
    [ "$status" -eq 1 ]
    [[ "$output" == *"Error: plan pass 1 deleted specs/existing.md in .; plan may not delete or move a spec."* ]]
}

@test "a pass that deletes a nested spec fails with the deletion error" {
    "$RALPH" init
    init_repo source/svc
    mkdir -p source/svc/specs
    echo "# Svc" > source/svc/specs/x.md
    git -C source/svc add -- specs/x.md
    git -C source/svc commit -q -m "docs(specs): add svc spec"
    echo "source/" >> .gitignore
    git add -- .gitignore
    git commit -q -m "chore: ignore source"
    create_scripted_backend
    on_iteration 1 'rm -- source/svc/specs/x.md'

    run_plan --skip-push
    [ "$status" -eq 1 ]
    [[ "$output" == *"Error: plan pass 1 deleted specs/x.md in ./source/svc; plan may not delete or move a spec."* ]]
}

@test "a pass that creates and edits specs without committing passes" {
    "$RALPH" init
    seed_committed_spec
    create_scripted_backend
    on_iteration 1 'echo "edit" >> specs/existing.md && echo "# New" > specs/new.md'

    run_plan --skip-push
    [ "$status" -eq 0 ]
    [[ "$output" != *"Error: plan pass"* ]]
    [[ "$(git log -1 --format=%s)" == "docs(specs): record plan decisions" ]]
}

@test "a pass that commits nothing passes" {
    "$RALPH" init
    create_scripted_backend

    run_plan --skip-push
    [ "$status" -eq 0 ]
    [[ "$output" != *"Error: plan pass"* ]]
    [[ "$output" == *"Completed 1 iteration"* ]]
}

@test "a run that adds and edits specs ends with one record plan decisions commit" {
    "$RALPH" init
    mkdir -p specs/features
    echo "# Foo" > specs/features/03-foo.md
    git add -- specs/features/03-foo.md
    git commit -q -m "docs(specs): add foo"
    local before
    before=$(commit_count)
    create_scripted_backend
    on_iteration 1 'echo "# New" > specs/new.md && echo "decision" >> specs/features/03-foo.md'

    run_plan --skip-push
    [ "$status" -eq 0 ]
    [ "$(commit_count)" -eq $((before + 1)) ]
    [[ "$(git log -1 --format=%s)" == "docs(specs): record plan decisions" ]]
    [[ "$(git log -1 --format=%b)" == *"- M specs/features/03-foo.md"* ]]
    [[ "$(git log -1 --format=%b)" == *"- A specs/new.md"* ]]
    [ -z "$(git status --porcelain -- specs)" ]
}

@test "a run whose two passes change specs makes one commit" {
    "$RALPH" init
    local before
    before=$(commit_count)
    create_scripted_backend
    on_iteration 1 'mkdir -p specs && echo "# One" > specs/one.md'
    on_iteration 2 'echo "# Two" > specs/two.md'

    run_plan --skip-push
    [ "$status" -eq 0 ]
    [[ "$output" == *"Completed 3 iterations"* ]]
    [ "$(commit_count)" -eq $((before + 1)) ]
    [ "$(git log -1 --format=%b)" == "$(printf -- '- A specs/one.md\n- A specs/two.md')" ]
}

@test "a run with more than three spec changes lists two and the rest as a count" {
    "$RALPH" init
    create_scripted_backend
    on_iteration 1 'mkdir -p specs && touch specs/a.md specs/b.md specs/c.md specs/d.md specs/e.md'

    run_plan --skip-push
    [ "$status" -eq 0 ]
    [ "$(git log -1 --format=%b)" == "$(printf -- '- A specs/a.md\n- A specs/b.md\n- and 3 more')" ]
}

@test "a run that changes no spec makes no commit" {
    "$RALPH" init
    local before
    before=$(commit_count)
    create_scripted_backend
    on_iteration 1 'echo "x" > notes.txt'

    run_plan --skip-push
    [ "$status" -eq 0 ]
    [ "$(commit_count)" -eq "$before" ]
}

@test "a run commits a nested submodule spec and bumps its gitlink" {
    "$RALPH" init
    init_repo source/svc
    git -c advice.addEmbeddedRepo=false add -- source/svc
    git commit -q -m "chore: add source/svc"
    local before nested_before
    before=$(commit_count)
    nested_before=$(commit_count source/svc)
    create_scripted_backend
    on_iteration 1 'mkdir -p source/svc/specs && echo "# Svc" > source/svc/specs/x.md'

    run_plan --skip-push
    [ "$status" -eq 0 ]
    [ "$(commit_count source/svc)" -eq $((nested_before + 1)) ]
    [[ "$(git -C source/svc log -1 --format=%s)" == "docs(specs): record plan decisions" ]]
    [[ "$(git -C source/svc log -1 --format=%b)" == "- A specs/x.md" ]]
    [ "$(commit_count)" -eq $((before + 1)) ]
    [[ "$(git log -1 --format=%s)" == "chore: bump source/svc to $(git -C source/svc rev-parse --short HEAD)" ]]
    [ -z "$(git status --porcelain -- source/svc)" ]
}

@test "a run with an origin commits its spec change and pushes nothing" {
    "$RALPH" init
    add_bare_origin
    create_scripted_backend
    on_iteration 1 'mkdir -p specs && echo "# New" > specs/new.md'

    run_plan
    [ "$status" -eq 0 ]
    [[ "$(git log -1 --format=%s)" == "docs(specs): record plan decisions" ]]
    [[ "$output" != *"No upstream branch found"* ]]
    [ -z "$(git ls-remote origin)" ]
}

@test "a run leaves a staged file outside specs/ uncommitted" {
    "$RALPH" init
    echo "readme" > README.md
    git add -- README.md
    git commit -q -m "docs: add readme"
    create_scripted_backend
    on_iteration 1 'mkdir -p specs && echo "# New" > specs/new.md &&
echo "edit" >> README.md && git add -- README.md'

    run_plan --skip-push
    [ "$status" -eq 0 ]
    [[ "$(git log -1 --format=%s)" == "docs(specs): record plan decisions" ]]
    [ "$(git show --name-only --format= HEAD)" == "specs/new.md" ]
    [ "$(git status --porcelain -- README.md)" == "M  README.md" ]
}

@test "a failing spec commit exits 1 and leaves specs/ dirty" {
    "$RALPH" init
    printf '#!/bin/sh\necho "hook says no" >&2\nexit 1\n' > .git/hooks/pre-commit
    chmod +x .git/hooks/pre-commit
    local before
    before=$(commit_count)
    create_scripted_backend
    on_iteration 1 'mkdir -p specs && echo "# New" > specs/new.md'

    run_plan --skip-push
    [ "$status" -eq 1 ]
    [[ "$output" == *"hook says no"* ]]
    [ "$(commit_count)" -eq "$before" ]
    [ -n "$(git status --porcelain -- specs)" ]
}

@test "a backend that fails after editing a spec still commits it" {
    "$RALPH" init
    local before
    before=$(commit_count)
    create_scripted_backend
    on_iteration 1 'mkdir -p specs && echo "# New" > specs/new.md && exit 1'

    run_plan --skip-push
    [ "$status" -ne 0 ]
    [ "$(commit_count)" -eq $((before + 1)) ]
    [[ "$(git log -1 --format=%s)" == "docs(specs): record plan decisions" ]]
    [ -z "$(git status --porcelain -- specs)" ]
}

@test "a backend that fails after committing commits nothing of its own" {
    "$RALPH" init
    create_scripted_backend
    on_iteration 1 'mkdir -p specs && echo "# New" > specs/new.md &&
git add -- specs/new.md && git commit -q -m "docs(specs): planner commit" &&
echo "# Edit" >> specs/new.md && exit 1'

    run_plan --skip-push
    [ "$status" -eq 1 ]
    [[ "$output" == *"Error: plan pass 1 committed in .; plan may not commit, Ralph commits its spec changes."* ]]
    [[ "$(git log -1 --format=%s)" == "docs(specs): planner commit" ]]
    [ -n "$(git status --porcelain -- specs)" ]
}

@test "a plan run interrupted after editing a spec commits it" {
    "$RALPH" init
    local before pid status_code=0 waited=0
    before=$(commit_count)
    create_scripted_backend
    on_iteration 1 "mkdir -p specs && echo '# New' > specs/new.md && touch '$TEST_DIR/edited' && sleep 1"

    PATH="$TEST_DIR/bin:$PATH" "$RALPH" plan -g "the goal" --skip-push > "$TEST_DIR/out" 2>&1 &
    pid=$!
    while [[ ! -f "$TEST_DIR/edited" ]] && (( waited < 100 )); do
        sleep 0.1
        waited=$((waited + 1))
    done
    kill -TERM "$pid"
    wait "$pid" || status_code=$?

    [ "$status_code" -eq 130 ]
    grep -q "Interrupted at iteration 1" "$TEST_DIR/out"
    [ "$(commit_count)" -eq $((before + 1)) ]
    [[ "$(git log -1 --format=%s)" == "docs(specs): record plan decisions" ]]
    [ -z "$(git status --porcelain -- specs)" ]
}
