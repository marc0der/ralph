#!/usr/bin/env bats

# Auto lifecycle suite (specs/012-auto-lifecycle.md §11). auto runs the seven phases
# archive → init → plan → build → review → fix → retro as children of the same
# script, guards each on the plan's disk state, and reports every phase. These
# tests drive it with the phase-aware committing mock (test_helper.bash) so a
# real lifecycle moves the plan and HEAD, and assert flag forwarding by child
# behaviour where §11 says dry-run output cannot see it.

load test_helper

# A run always sees the mock backend on PATH and passes the in-container guard,
# except where a test overrides DEVCONTAINER to exercise the guard itself.
run_auto() {
    PATH="$TEST_DIR/bin:$PATH" DEVCONTAINER=true run "$RALPH" auto -g "the goal" "$@"
}

# Seed the tree so a --resume test enters at a chosen phase without first
# running archive/init: both artifacts, a plan of the requested shape, and a
# state file naming the phase to resume at.
seed_resume_state() {
    local phase="$1"
    cp "$RALPH_CONFIG_DIR/templates/IMPLEMENTATION_PLAN.md" IMPLEMENTATION_PLAN.md
    echo "# progress" > PROGRESS.md
    mkdir -p .ralph
    printf 'phase=%s\nphase_name=x\nchild_exit=1\nfailed_at=x\n' "$phase" > .ralph/auto-state
}

# --- CLI acceptance, help, guard, -n rejection ------------------------------

@test "auto --help lists the mode and its options" {
    # --help is the only place an operator learns that auto exists, what the
    # phases are, and that -n belongs to no phase of it (specs/012-auto-lifecycle.md 9).
    run "$RALPH" auto --help -g "the goal"
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"ralph auto [options]"* ]]
    [[ "$output" == *"archive, init, plan, build, review, fix, retro"* ]]
    [[ "$output" == *"Auto options:"* ]]
    [[ "$output" == *"--resume"* ]]
    [[ "$output" == *"--force"* ]]
    [[ "$output" == *"does not accept -n/--iterations"* ]]
}

@test "auto refuses to run outside a container and names --force" {
    DEVCONTAINER=false run "$RALPH" auto -g "the goal"
    [[ "$status" -eq 1 ]]
    [[ "$output" == *"--force"* ]]
}

@test "auto --force proceeds outside a container and prints one notice" {
    create_committing_backend
    DEVCONTAINER=false PATH="$TEST_DIR/bin:$PATH" run "$RALPH" auto --force --dry-run -g "the goal"
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"running outside a container with --force"* ]]
}

@test "auto proceeds inside a container without --force" {
    create_committing_backend
    run_auto --skip-push --no-metrics
    [[ "$status" -eq 0 ]]
}

@test "auto rejects -n and the message names iterations" {
    DEVCONTAINER=true run "$RALPH" auto -n 5 -g "the goal"
    [[ "$status" -eq 1 ]]
    [[ "$output" == *"iteration"* ]]
}

@test "auto rejects --iterations too" {
    DEVCONTAINER=true run "$RALPH" auto --iterations 5 -g "the goal"
    [[ "$status" -eq 1 ]]
    [[ "$output" == *"iteration"* ]]
}

@test "auto rejects each opposed flag pair" {
    DEVCONTAINER=true run "$RALPH" auto --dry-run -q --verbose -g "the goal"
    [[ "$status" -eq 1 ]]
    [[ "$output" == *"Error: --verbose cannot be combined with --quiet."* ]]
    DEVCONTAINER=true run "$RALPH" auto --dry-run --no-metrics --metrics -g "the goal"
    [[ "$status" -eq 1 ]]
    [[ "$output" == *"Error: --metrics cannot be combined with --no-metrics."* ]]
    DEVCONTAINER=true run "$RALPH" auto --dry-run --skip-push --push -g "the goal"
    [[ "$status" -eq 1 ]]
    [[ "$output" == *"Error: --push cannot be combined with --skip-push."* ]]
}

@test "auto -v exits 1 with the getopt message" {
    DEVCONTAINER=true run "$RALPH" auto -v -g "the goal"
    [[ "$status" -eq 1 ]]
    [[ "$output" == *"ralph auto: invalid option -- 'v'"* ]]
}

@test "auto with no -g exits 1 and names the goal" {
    # The goal is the one input auto cannot derive: phase 3 is plan, which
    # plans against whatever specs/ it resolves when the goal is empty.
    DEVCONTAINER=true run "$RALPH" auto
    [[ "$status" -eq 1 ]]
    [[ "$output" == *"'auto' requires a goal"* ]]
}

@test "auto accepts -y and changes nothing" {
    create_committing_backend
    run_auto -y --skip-push --no-metrics
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"Lifecycle summary"* ]]
}

# --- Full lifecycle and exit codes ------------------------------------------

@test "a lifecycle where every phase ran exits 0" {
    create_committing_backend
    run_auto --skip-push --no-metrics
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"4 build     ran"* ]]
    [[ "$output" == *"5 review    ran"* ]]
    [[ "$output" == *"6 fix       ran"* ]]
}

@test "a lifecycle whose review files nothing skips phase 6 and exits 0" {
    create_committing_backend
    MOCK_REVIEW_NOOP=1 PATH="$TEST_DIR/bin:$PATH" DEVCONTAINER=true run "$RALPH" auto --skip-push --no-metrics -g "the goal"
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"5 review    ran"* ]]
    [[ "$output" == *"6 fix       skipped"* ]]
}

@test "a lifecycle whose fix skips still runs phase 7 after it" {
    create_committing_backend
    MOCK_REVIEW_NOOP=1 PATH="$TEST_DIR/bin:$PATH" DEVCONTAINER=true run "$RALPH" auto --skip-push --no-metrics -g "the goal"
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"6 fix       skipped"* ]]
    [[ "$output" == *"7 retro     ran"* ]]
}

@test "a failed retro writes phase 7 and its child exit to .ralph/auto-state" {
    create_committing_backend
    MOCK_RETRO_EXIT=4 PATH="$TEST_DIR/bin:$PATH" DEVCONTAINER=true run "$RALPH" auto --skip-push --no-metrics -g "the goal"
    [[ "$status" -eq 1 ]]
    [[ "$output" == *"Re-run: "*" auto --resume"* ]]
    grep -q '^phase=7$' .ralph/auto-state
    grep -q '^child_exit=4$' .ralph/auto-state
}

@test "--resume after a failed retro re-runs only the retro" {
    create_committing_backend
    MOCK_RETRO_EXIT=4 PATH="$TEST_DIR/bin:$PATH" DEVCONTAINER=true run "$RALPH" auto --skip-push --no-metrics -g "the goal"
    [[ "$status" -eq 1 ]]
    local head_before
    head_before=$(git rev-parse HEAD)
    run_auto --resume --skip-push --no-metrics
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"Resumed from phase 7"* ]]
    [[ "$output" == *"7 retro     ran"* ]]
    [[ "$output" == *"4 build     skipped — resumed at phase 7"* ]]
    [[ "$(git rev-parse HEAD)" == "$head_before" ]]
    [[ ! -f .ralph/auto-state ]]
}

@test "the report prints the seven numbered phase rows" {
    create_committing_backend
    run_auto --skip-push --no-metrics
    [[ "$output" == *"1 archive"* ]]
    [[ "$output" == *"2 init"* ]]
    [[ "$output" == *"3 plan"* ]]
    [[ "$output" == *"7 retro"* ]]
    [[ "$output" == *"Artifacts: IMPLEMENTATION_PLAN.md and PROGRESS.md"* ]]
}

# --- Guards and skip reasons ------------------------------------------------

@test "phase 5 is skipped when open items remain, naming the count" {
    create_committing_backend
    seed_resume_state 5
    printf -- '- [x] **shipped**\n  Spec: specs/mock.md item 1\n' >> IMPLEMENTATION_PLAN.md
    echo "- [ ] **open**" >> IMPLEMENTATION_PLAN.md
    git add -A -- .; git commit -q -m seed
    run_auto --resume --skip-push --no-metrics
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"5 review    skipped — 1 open items remain"* ]]
}

@test "phase 5 is skipped when the plan holds no shipped item" {
    create_committing_backend
    seed_resume_state 5
    git add -A -- .; git commit -q -m seed
    run_auto --resume --skip-push --no-metrics
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"5 review    skipped — no shipped items"* ]]
}

@test "phase 5 is skipped without a cycle base" {
    # The child's fourth precondition refuses a run with no .ralph/cycle-base.
    # Without the matching guard auto would report a failed lifecycle for a
    # condition it exists to absorb.
    create_committing_backend
    seed_resume_state 5
    printf -- '- [x] **shipped**\n  Spec: specs/mock.md item 1\n' >> IMPLEMENTATION_PLAN.md
    git add -A -- .; git commit -q -m seed
    run_auto --resume --skip-push --no-metrics
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"5 review    skipped — no cycle base"* ]]
}

@test "phase 4 is skipped when the plan holds no open item" {
    create_committing_backend
    seed_resume_state 4
    printf -- '- [x] **shipped**\n  Spec: specs/mock.md item 1\n' >> IMPLEMENTATION_PLAN.md
    git add -A -- .; git commit -q -m seed
    run_auto --resume --skip-push --no-metrics
    [[ "$output" == *"4 build     skipped — no open items"* ]]
}

@test "phase 6 is skipped with 'no plan artifacts' when PROGRESS.md vanishes mid-run" {
    # The 4/6/5 guards read the tree afresh each phase. A build that removes
    # PROGRESS.md leaves phase 6's guard naming plan artifacts, not only the plan.
    create_committing_backend
    # Wrap the mock: after a build commit, drop PROGRESS.md so phase 6 guards out.
    sed -i 's#git commit -q -m "mock build commit" >/dev/null 2>&1#&; rm -f PROGRESS.md#' "$TEST_DIR/bin/claude"
    run_auto --skip-push --no-metrics
    [[ "$output" == *"6 fix       skipped — no plan artifacts"* ]]
}

@test "phase 6 runs ralph fix, which reads the fix section" {
    require_yq_or_skip
    create_committing_backend
    printf 'build:\n  effort: high\nfix:\n  effort: low\n' > ralph.yaml
    run_auto --skip-push --no-metrics
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"6 fix       ran"* ]]
    [[ "$(card_row config "$output" build)" == "config: ./ralph.yaml (local) [build]" ]]
    [[ "$(card_row backend "$output" build)" == *"effort: high" ]]
    [[ "$(card_row config "$output" fix)" == "config: ./ralph.yaml (local) [fix]" ]]
    [[ "$(card_row backend "$output" fix)" == *"effort: low" ]]
}

@test "each phase that runs prints one run card title" {
    create_committing_backend
    run_auto --skip-push --no-metrics
    [[ "$status" -eq 0 ]]
    local section
    for section in plan build review fix retro; do
        [ "$(grep -c "^━━ ralph $section ━" <<< "$output")" -eq 1 ]
    done
}

# --- Abort, not-reached, child exit in the report ---------------------------

@test "a failing phase aborts and reports later phases as not reached" {
    create_committing_backend
    MOCK_EXIT=3 PATH="$TEST_DIR/bin:$PATH" DEVCONTAINER=true run "$RALPH" auto --skip-push --no-metrics -g "the goal"
    [[ "$status" -eq 1 ]]
    [[ "$output" == *"3 plan      failed — exit 3"* ]]
    [[ "$output" == *"4 build     not reached"* ]]
    [[ "$output" == *"5 review    not reached"* ]]
    [[ "$output" == *"7 retro     not reached"* ]]
}

@test "a failing phase exits 1 with the child's exit 3 in the report" {
    create_committing_backend
    MOCK_EXIT=3 PATH="$TEST_DIR/bin:$PATH" DEVCONTAINER=true run "$RALPH" auto --skip-push --no-metrics -g "the goal"
    [[ "$status" -eq 1 ]]
    [[ "$output" == *"exit 3"* ]]
}

@test "a failing phase exits 1 with the child's exit 5 in the report" {
    create_committing_backend
    MOCK_EXIT=5 PATH="$TEST_DIR/bin:$PATH" DEVCONTAINER=true run "$RALPH" auto --skip-push --no-metrics -g "the goal"
    [[ "$status" -eq 1 ]]
    [[ "$output" == *"exit 5"* ]]
}

@test "an abort prints the single re-run command" {
    create_committing_backend
    MOCK_EXIT=3 PATH="$TEST_DIR/bin:$PATH" DEVCONTAINER=true run "$RALPH" auto --skip-push --no-metrics -g "the goal"
    [[ "$output" == *"auto --resume"* ]]
}

# --- Phase-2 template precondition ------------------------------------------

@test "phase 2 fails the lifecycle when the plan template is missing, naming file and templates dir" {
    create_committing_backend
    rm -f "$RALPH_CONFIG_DIR/templates/IMPLEMENTATION_PLAN.md"
    run_auto --skip-push --no-metrics
    [[ "$status" -eq 1 ]]
    [[ "$output" == *"IMPLEMENTATION_PLAN.md"* ]]
    [[ "$output" == *"templates"* ]]
}

# --- State file write and removal -------------------------------------------

@test "a failing phase writes .ralph/auto-state with the 1-based phase and child exit" {
    create_committing_backend
    MOCK_EXIT=3 PATH="$TEST_DIR/bin:$PATH" DEVCONTAINER=true "$RALPH" auto --skip-push --no-metrics -g "the goal" || true
    [[ -f .ralph/auto-state ]]
    grep -q '^phase=3$' .ralph/auto-state
    grep -q '^child_exit=3$' .ralph/auto-state
}

@test "a completed lifecycle removes .ralph/auto-state" {
    create_committing_backend
    run_auto --skip-push --no-metrics
    [[ "$status" -eq 0 ]]
    [[ ! -f .ralph/auto-state ]]
}

@test "a completed lifecycle that skipped phase 6 also removes .ralph/auto-state" {
    create_committing_backend
    MOCK_REVIEW_NOOP=1 PATH="$TEST_DIR/bin:$PATH" DEVCONTAINER=true run "$RALPH" auto --skip-push --no-metrics -g "the goal"
    [[ "$status" -eq 0 ]]
    [[ ! -f .ralph/auto-state ]]
}

# --- Resume -----------------------------------------------------------------

@test "--resume with no state file exits 1 saying nothing to resume" {
    DEVCONTAINER=true run "$RALPH" auto --resume -g "the goal"
    [[ "$status" -eq 1 ]]
    [[ "$output" == *"resume"* ]]
}

@test "--resume with an out-of-range phase exits 1" {
    seed_resume_state 9
    DEVCONTAINER=true run "$RALPH" auto --resume -g "the goal"
    [[ "$status" -eq 1 ]]
    [[ "$output" == *"phase"* ]]
}

@test "--resume with a missing artifact exits 1 and names it" {
    seed_resume_state 4
    rm -f PROGRESS.md
    DEVCONTAINER=true run "$RALPH" auto --resume -g "the goal"
    [[ "$status" -eq 1 ]]
    [[ "$output" == *"PROGRESS.md"* ]]
}

@test "--resume never archives: the plan present before is present after" {
    create_committing_backend
    seed_resume_state 3
    echo "resume-marker" >> IMPLEMENTATION_PLAN.md
    git add -A -- .; git commit -q -m seed
    run_auto --resume --skip-push --no-metrics
    grep -q 'resume-marker' IMPLEMENTATION_PLAN.md
}

@test "--resume re-enters at the recorded phase and reports earlier phases as resumed" {
    create_committing_backend
    seed_resume_state 3
    git add -A -- .; git commit -q -m seed
    run_auto --resume --skip-push --no-metrics
    [[ "$output" == *"1 archive   skipped — resumed at phase 3"* ]]
    [[ "$output" == *"3 plan      ran"* ]]
}

@test "--resume at phase 7 skips the retro over a progress file without entries" {
    create_committing_backend
    seed_resume_state 7
    git add -A -- .; git commit -q -m seed
    run_auto --resume --skip-push --no-metrics
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"7 retro     skipped — no progress entries"* ]]
}

@test "--resume rejects a recorded phase above 7" {
    create_committing_backend
    seed_resume_state 8
    run_auto --resume --skip-push --no-metrics
    [[ "$status" -eq 1 ]]
    [[ "$output" == *"has no valid 'phase' (1-7) to resume."* ]]
}

@test "--resume from phase 1 still enters at phase 3" {
    create_committing_backend
    seed_resume_state 1
    git add -A -- .; git commit -q -m seed
    run_auto --resume --skip-push --no-metrics
    [[ "$output" == *"2 init      skipped — resumed at phase 3"* ]]
    [[ "$output" == *"3 plan      ran"* ]]
}

@test "--resume over a stale cycle base refuses before the plan child" {
    create_committing_backend
    seed_resume_state 1
    seed_shipped_item
    git add -A -- .; git commit -q -m seed
    seed_cycle_base
    run_auto --resume --skip-push --no-metrics
    [[ "$status" -eq 1 ]]
    [[ "$output" == *"built but not archived"* ]]
    [[ "$output" == *"without --resume"* ]]
    [[ "$output" == *"Lifecycle summary"* ]]
    [[ "$output" != *"3 plan      ran"* ]]
    grep -q '^phase=1$' .ralph/auto-state
}

@test "a plain run over a stale cycle base archives it and plans" {
    create_committing_backend
    "$RALPH" init
    seed_shipped_item
    git add -A -- .; git commit -q -m seed
    seed_cycle_base
    run_auto --skip-push --no-metrics
    [[ "$output" == *"3 plan      ran"* ]]
}

@test "a dirty specs/ refuses phase 3 and records it for --resume" {
    create_committing_backend
    mkdir -p specs
    echo "draft" > specs/x.md
    MOCK_REVIEW_NOOP=1 PATH="$TEST_DIR/bin:$PATH" DEVCONTAINER=true run "$RALPH" auto --skip-push --no-metrics -g "the goal"
    [[ "$status" -eq 1 ]]
    [[ "$output" == *"specs/ has uncommitted changes in ."* ]]
    [[ "$output" == *"then run 'ralph auto --resume'"* ]]
    [[ "$output" == *"2 init      ran"* ]]
    run ! grep -q 'mock-planned-item' IMPLEMENTATION_PLAN.md
    grep -q '^phase=3$' .ralph/auto-state
    grep -q '^child_exit=1$' .ralph/auto-state
}

@test "--resume plans once the dirty spec is committed" {
    create_committing_backend
    mkdir -p specs
    echo "draft" > specs/x.md
    MOCK_REVIEW_NOOP=1 PATH="$TEST_DIR/bin:$PATH" DEVCONTAINER=true run "$RALPH" auto --skip-push --no-metrics -g "the goal"
    [[ "$status" -eq 1 ]]
    git add -- specs/x.md; git commit -q -m "docs(specs): add x"
    MOCK_REVIEW_NOOP=1 PATH="$TEST_DIR/bin:$PATH" DEVCONTAINER=true run "$RALPH" auto --resume --skip-push --no-metrics -g "the goal"
    [[ "$status" -eq 0 ]]
    grep -q 'mock-planned-item' IMPLEMENTATION_PLAN.md
}

@test "a detached HEAD refuses phase 3 and records it for --resume" {
    create_committing_backend
    mkdir -p specs
    echo "spec" > specs/x.md
    git add -- specs/x.md; git commit -q -m "docs(specs): add x"
    git checkout -q --detach
    MOCK_REVIEW_NOOP=1 PATH="$TEST_DIR/bin:$PATH" DEVCONTAINER=true run "$RALPH" auto --skip-push --no-metrics -g "the goal"
    [[ "$status" -eq 1 ]]
    [[ "$output" == *"Error: . is on a detached HEAD."* ]]
    [[ "$output" == *"Check out a branch, then run 'ralph auto --resume'."* ]]
    [[ "$output" == *"3 plan      refused — detached HEAD"* ]]
    run ! grep -q 'mock-planned-item' IMPLEMENTATION_PLAN.md
    grep -q '^phase=3$' .ralph/auto-state
    grep -q '^child_exit=1$' .ralph/auto-state
}

@test "--resume plans once the detached workspace checks out a branch" {
    create_committing_backend
    mkdir -p specs
    echo "spec" > specs/x.md
    git add -- specs/x.md; git commit -q -m "docs(specs): add x"
    git checkout -q --detach
    MOCK_REVIEW_NOOP=1 PATH="$TEST_DIR/bin:$PATH" DEVCONTAINER=true run "$RALPH" auto --skip-push --no-metrics -g "the goal"
    [[ "$status" -eq 1 ]]
    git checkout -q -b work
    MOCK_REVIEW_NOOP=1 PATH="$TEST_DIR/bin:$PATH" DEVCONTAINER=true run "$RALPH" auto --resume --skip-push --no-metrics -g "the goal"
    [[ "$status" -eq 0 ]]
    grep -q 'mock-planned-item' IMPLEMENTATION_PLAN.md
}

@test "--resume prints the recorded phase, child exit and manual-repair notice" {
    create_committing_backend
    seed_resume_state 5
    printf -- '- [x] **shipped**\n  Spec: specs/mock.md item 1\n' >> IMPLEMENTATION_PLAN.md
    git add -A -- .; git commit -q -m seed
    run_auto --resume --skip-push --no-metrics
    [[ "$output" == *"Resumed from phase 5"* ]]
    [[ "$output" == *"child exit 1"* ]]
    [[ "$output" == *"manual repair"* ]]
}

# --- Dry run ----------------------------------------------------------------

@test "--dry-run names all seven phases and states guards run at run time" {
    DEVCONTAINER=true run "$RALPH" auto --dry-run -g "the goal"
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"1 archive"* ]]
    [[ "$output" == *"6 fix"* ]]
    [[ "$output" == *"7 retro"* ]]
    [[ "$output" == *"the seven phases in order"* ]]
    [[ "$output" == *"guards are evaluated at run time"* ]]
}

@test "--dry-run shows phase 6 as ralph fix -y" {
    DEVCONTAINER=true run "$RALPH" auto --dry-run -g "the goal"
    [[ "$status" -eq 0 ]]
    [[ "$(grep -E '^ +6 fix' <<< "$output")" == "  6 fix       "*"/ralph fix "*"-y" ]]
}

@test "--dry-run invokes nothing: no artifacts, no metrics, succeeds uninitialised" {
    DEVCONTAINER=true run "$RALPH" auto --dry-run -g "the goal"
    [[ "$status" -eq 0 ]]
    [[ ! -f IMPLEMENTATION_PLAN.md ]]
    [[ ! -d .ralph/logs ]]
}

@test "--dry-run shows -g on the plan row and on no other row" {
    # plan is the only phase whose work comes from the goal, so -g leaves
    # child_flags and joins the plan phase's own command line. -m and -b still
    # reach every loop phase.
    DEVCONTAINER=true run "$RALPH" auto --dry-run -g "the goal" -m "the-model" -b claude
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"3 plan"*"-g the goal"*"-m the-model"*"-b claude"*"-y"* ]]
    [[ "$(grep -c -- '-g the goal' <<< "$output" || true)" -eq 1 ]]
    [[ "$(grep -E '^ +4 build' <<< "$output")" == *"-m the-model"* ]]
    [[ "$(grep -E '^ +4 build' <<< "$output")" != *"-g"* ]]
    [[ "$(grep -E '^ +5 review' <<< "$output")" != *"-g"* ]]
}

@test "--dry-run -q shows -q on the plan, build and review rows only" {
    DEVCONTAINER=true run "$RALPH" auto --dry-run -q -g "the goal"
    [[ "$status" -eq 0 ]]
    [[ "$(grep -E '^ +3 plan' <<< "$output")" == *" -q "* ]]
    [[ "$(grep -E '^ +4 build' <<< "$output")" == *" -q "* ]]
    [[ "$(grep -E '^ +5 review' <<< "$output")" == *" -q "* ]]
    [[ "$(grep -E '^ +6 fix' <<< "$output")" == *" -q "* ]]
    [[ "$(grep -E '^ +1 archive' <<< "$output")" != *"-q"* ]]
    [[ "$(grep -E '^ +2 init' <<< "$output")" != *"-q"* ]]
}

@test "--dry-run forwards -e, --verbose, --metrics and --push to the loop rows" {
    DEVCONTAINER=true run "$RALPH" auto --dry-run -e high --verbose --metrics --push -g "the goal"
    [[ "$status" -eq 0 ]]
    local row
    for row in '3 plan' '4 build' '5 review' '6 fix' '7 retro'; do
        [[ "$(grep -E "^ +$row" <<< "$output")" == *" -e high --push --metrics --verbose -y"* ]]
    done
    [[ "$(grep -E '^ +1 archive' <<< "$output")" != *"-e"* ]]
    [[ "$(grep -E '^ +2 init' <<< "$output")" != *"--verbose"* ]]
}

@test "--dry-run forwards no opposed flag when none is given" {
    DEVCONTAINER=true run "$RALPH" auto --dry-run -g "the goal"
    [[ "$status" -eq 0 ]]
    [[ "$output" != *"--verbose"* ]]
    [[ "$output" != *"--metrics"* ]]
    [[ "$output" != *"--push"* ]]
    [[ "$output" != *" -e "* ]]
}

# --- Config validation (specs/019-phase-config.md §7) ---------------------------

@test "--dry-run fails on an invalid ralph.yaml before listing the phases" {
    require_yq_or_skip
    printf 'build:\n  bogus: 1\n' > ralph.yaml
    DEVCONTAINER=true run "$RALPH" auto --dry-run -g g
    [[ "$status" -eq 1 ]]
    [[ "$output" == *"Error: ralph.yaml: build.bogus is not a known key."* ]]
    [[ "$output" != *"1 archive"* ]]
}

@test "auto fails on an invalid ralph.yaml before phase 1 runs" {
    require_yq_or_skip
    create_committing_backend
    printf 'review:\n  iterations: 2\n' > ralph.yaml
    run_auto --skip-push --no-metrics
    [[ "$status" -eq 1 ]]
    [[ "$output" == *"Error: ralph.yaml: review.iterations is not allowed"* ]]
    [[ "$output" != *"Lifecycle summary"* ]]
    [[ ! -f IMPLEMENTATION_PLAN.md ]]
    [[ ! -f .ralph/auto-state ]]
}

@test "auto fails on an invalid central config.yaml" {
    require_yq_or_skip
    printf 'defaults:\n  skip_push: true\n' > "$RALPH_CONFIG_DIR/config.yaml"
    DEVCONTAINER=true run "$RALPH" auto --dry-run -g g
    [[ "$status" -eq 1 ]]
    [[ "$output" == *"defaults.skip_push is not allowed in defaults"* ]]
}

@test "auto needs mikefarah yq when a config file exists" {
    printf 'build:\n  effort: high\n' > ralph.yaml
    create_fake_yq "yq 3.4.1"
    PATH="$TEST_DIR/bin:$PATH" DEVCONTAINER=true run "$RALPH" auto --dry-run -g g
    [[ "$status" -eq 1 ]]
    [[ "$output" == *"needs mikefarah yq v4"* ]]
}

@test "--dry-run lists the phases over a valid ralph.yaml" {
    require_yq_or_skip
    printf 'build:\n  effort: high\n' > ralph.yaml
    DEVCONTAINER=true run "$RALPH" auto --dry-run -g g
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"6 fix"* ]]
}

@test "auto -e high puts -e high on the plan, build, review and fix rows" {
    DEVCONTAINER=true run "$RALPH" auto --dry-run -e high -g g
    [[ "$status" -eq 0 ]]
    local row
    for row in '3 plan' '4 build' '5 review' '6 fix'; do
        [[ "$(grep -E "^ +$row" <<< "$output")" == *" -e high -y"* ]]
    done
}

# --- Flag forwarding by behaviour (§11) -------------------------------------

@test "--no-metrics reaches children: no .ralph/logs directory is created" {
    create_committing_backend
    run_auto --skip-push --no-metrics
    [[ "$status" -eq 0 ]]
    [[ ! -d .ralph/logs ]]
}

@test "auto --no-metrics over a lone old store moves it" {
    create_committing_backend
    mkdir -p .ralph/metrics/r1
    printf '%s\n' '{"iteration":1}' > .ralph/metrics/r1/metrics.jsonl

    run_auto --skip-push --no-metrics
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"Moved .ralph/metrics/ to .ralph/logs/."* ]]
    [[ ! -e .ralph/metrics ]]
    [[ -f .ralph/logs/r1/metrics.jsonl ]]
}

@test "auto --dry-run over a lone old store leaves it in place" {
    mkdir -p .ralph/metrics/r1
    printf '%s\n' '{"iteration":1}' > .ralph/metrics/r1/metrics.jsonl

    run_auto --dry-run
    [[ "$status" -eq 0 ]]
    [[ -f .ralph/metrics/r1/metrics.jsonl ]]
    [[ ! -e .ralph/logs ]]
}

@test "auto without --quiet shows Backend command: lines" {
    create_committing_backend
    run_auto --skip-push --no-metrics
    [[ "$output" == *"Backend command:"* ]]
}

@test "auto -q reaches children: no Backend command: line appears" {
    create_committing_backend
    run_auto -q --skip-push --no-metrics
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"6 fix       ran"* ]]
    [[ "$output" != *"Backend command:"* ]]
}

@test "--skip-push reaches children: a lifecycle completes in a repo with no remote" {
    create_committing_backend
    run_auto --skip-push --no-metrics
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"6 fix       ran"* ]]
}

# --- Run directory (specs/023-run-logs-and-metrics.md §3) --------------------

@test "a lifecycle with metrics leaves one run folder holding every loop phase" {
    create_committing_backend
    run_auto --skip-push
    [[ "$status" -eq 0 ]]

    local -a runs=(.ralph/logs/*/)
    [[ "${#runs[@]}" -eq 1 ]]
    local phase
    for phase in plan build review fix retro; do
        [[ -f "${runs[0]}$phase/metrics.jsonl" ]]
    done
}

@test "auto warns and runs every phase when it cannot create the run folder" {
    create_committing_backend
    mkdir -p .ralph
    touch .ralph/logs

    run_auto --skip-push
    rm -f .ralph/logs

    [[ "$status" -eq 0 ]]
    [[ "$output" == *"lifecycle metrics disabled"* ]]
    [[ "$output" != *"cannot write"* ]]
    [[ "$output" == *"7 retro     ran"* ]]
}

@test "a failed lifecycle records its run folder in .ralph/auto-state" {
    create_committing_backend
    MOCK_RETRO_EXIT=1 PATH="$TEST_DIR/bin:$PATH" DEVCONTAINER=true run "$RALPH" auto --skip-push -g "the goal"
    [[ "$status" -eq 1 ]]

    local -a runs=(.ralph/logs/*/)
    [[ "${#runs[@]}" -eq 1 ]]
    grep -qx "run=${runs[0]%/}" .ralph/auto-state
}

@test "--resume reuses the recorded run folder and the retro appends to its folder" {
    create_committing_backend
    MOCK_RETRO_EXIT=1 PATH="$TEST_DIR/bin:$PATH" DEVCONTAINER=true run "$RALPH" auto --skip-push -g "the goal"
    [[ "$status" -eq 1 ]]
    local -a before=(.ralph/logs/*/)

    run_auto --resume --skip-push
    [[ "$status" -eq 0 ]]
    [[ "$output" != *"Resumed into a new run directory"* ]]

    local -a runs=(.ralph/logs/*/)
    [[ "${#runs[@]}" -eq 1 ]]
    [[ "${runs[0]}" == "${before[0]}" ]]
    [[ -f "${runs[0]}retro/iter-001.stream.jsonl" ]]
    [[ -f "${runs[0]}retro/iter-002.stream.jsonl" ]]
}

@test "--resume with the recorded run folder gone starts a new one and says so" {
    create_committing_backend
    MOCK_RETRO_EXIT=1 PATH="$TEST_DIR/bin:$PATH" DEVCONTAINER=true run "$RALPH" auto --skip-push -g "the goal"
    [[ "$status" -eq 1 ]]
    local -a before=(.ralph/logs/*/)
    rm -rf "${before[0]}"

    run_auto --resume --skip-push
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"Resumed into a new run directory; earlier phases are not in it."* ]]

    local -a runs=(.ralph/logs/*/)
    [[ "${#runs[@]}" -eq 1 ]]
    [[ "${runs[0]}" != "${before[0]}" ]]
    [[ -f "${runs[0]}retro/iter-001.stream.jsonl" ]]
}

@test "--resume --no-metrics keeps the recorded run in .ralph/auto-state" {
    create_committing_backend
    MOCK_RETRO_EXIT=1 PATH="$TEST_DIR/bin:$PATH" DEVCONTAINER=true run "$RALPH" auto --skip-push -g "the goal"
    [[ "$status" -eq 1 ]]
    local -a before=(.ralph/logs/*/)
    grep -qx "run=${before[0]%/}" .ralph/auto-state

    MOCK_RETRO_EXIT=1 PATH="$TEST_DIR/bin:$PATH" DEVCONTAINER=true run "$RALPH" auto --resume --skip-push --no-metrics -g "the goal"
    [[ "$status" -eq 1 ]]
    grep -qx "run=${before[0]%/}" .ralph/auto-state

    run_auto --resume --skip-push
    [[ "$status" -eq 0 ]]
    [[ "$output" != *"Resumed into a new run directory"* ]]

    local -a runs=(.ralph/logs/*/)
    [[ "${#runs[@]}" -eq 1 ]]
    [[ "${runs[0]}" == "${before[0]}" ]]
}

@test "a resumed dirty specs/ refusal keeps the recorded run" {
    create_committing_backend
    mkdir -p specs
    echo "draft" > specs/x.md
    run_auto --skip-push
    [[ "$status" -eq 1 ]]
    local run_line
    run_line=$(grep '^run=' .ralph/auto-state)
    [[ -n "${run_line#run=}" ]]

    run_auto --resume --skip-push --no-metrics
    [[ "$status" -eq 1 ]]
    grep -qxF "$run_line" .ralph/auto-state
}

@test "a resumed detached HEAD refusal keeps the recorded run" {
    create_committing_backend
    mkdir -p specs
    echo "spec" > specs/x.md
    git add -- specs/x.md; git commit -q -m "docs(specs): add x"
    git checkout -q --detach
    run_auto --skip-push
    [[ "$status" -eq 1 ]]
    local run_line
    run_line=$(grep '^run=' .ralph/auto-state)
    [[ -n "${run_line#run=}" ]]

    run_auto --resume --skip-push --no-metrics
    [[ "$status" -eq 1 ]]
    grep -qxF "$run_line" .ralph/auto-state
}

@test "an exported RALPH_RUN_DIR gets nothing from auto --no-metrics" {
    create_committing_backend
    local exported="$BATS_TEST_TMPDIR/exported"
    mkdir -p "$exported"
    # shellcheck disable=SC2030
    export RALPH_RUN_DIR="$exported"

    MOCK_RETRO_EXIT=1 PATH="$TEST_DIR/bin:$PATH" DEVCONTAINER=true run "$RALPH" auto --skip-push --no-metrics -g "the goal"
    [[ "$status" -eq 1 ]]

    [[ -z "$(ls -A "$exported")" ]]
    grep -qx 'run=' .ralph/auto-state
}

@test "an exported RALPH_RUN_DIR gets nothing from auto with metrics" {
    create_committing_backend
    local exported="$BATS_TEST_TMPDIR/exported"
    mkdir -p "$exported"
    # shellcheck disable=SC2031
    export RALPH_RUN_DIR="$exported"

    run_auto --skip-push
    [[ "$status" -eq 0 ]]

    local -a runs=(.ralph/logs/*/)
    [[ "${#runs[@]}" -eq 1 ]]
    [[ -z "$(ls -A "$exported")" ]]
}

# --- auto.json (specs/023-run-logs-and-metrics.md §3) ------------------------

@test "a lifecycle writes auto.json listing the seven phases in order" {
    create_committing_backend
    run_auto --skip-push
    [[ "$status" -eq 0 ]]

    local -a runs=(.ralph/logs/*/)
    local json="${runs[0]}auto.json"
    [[ "$(jq -r '.goal' "$json")" == "the goal" ]]
    [[ "$(jq -r '.branch' "$json")" == "$(git branch --show-current)" ]]
    jq -e '.started | test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$")' "$json"
    [[ "$(jq -r '[.phases[] | "\(.phase) \(.name)"] | join(",")' "$json")" \
        == "1 archive,2 init,3 plan,4 build,5 review,6 fix,7 retro" ]]
    [[ "$(jq -r '.phases[2].state' "$json")" == "ran" ]]
    [[ "$(jq -r '[.phases[].state] | unique | join(",")' "$json")" == "ran" ]]
}

@test "auto.json holds the finished phases and the unreached ones while a phase runs" {
    create_committing_backend
    mv "$TEST_DIR/bin/claude" "$TEST_DIR/bin/claude.real"
    cat > "$TEST_DIR/bin/claude" <<MOCK
#!/usr/bin/env bash
prompt=\$(cat)
if echo "\$prompt" | grep -qi 'plan prompt'; then
    cp .ralph/logs/*/auto.json "$BATS_TEST_TMPDIR/during-plan.json"
fi
echo "\$prompt" | "$TEST_DIR/bin/claude.real" "\$@"
MOCK
    chmod +x "$TEST_DIR/bin/claude"

    run_auto --skip-push
    [[ "$status" -eq 0 ]]

    [[ "$(jq -r '[.phases[].state] | join(",")' "$BATS_TEST_TMPDIR/during-plan.json")" \
        == "ran,ran,not reached,not reached,not reached,not reached,not reached" ]]
}

@test "auto.json records the failed phase and the unreached ones after an abort" {
    create_committing_backend
    MOCK_RETRO_EXIT=1 PATH="$TEST_DIR/bin:$PATH" DEVCONTAINER=true run "$RALPH" auto --skip-push -g "the goal"
    [[ "$status" -eq 1 ]]

    local -a runs=(.ralph/logs/*/)
    [[ "$(jq -r '[.phases[].state] | join(",")' "${runs[0]}auto.json")" \
        == "ran,ran,ran,ran,ran,ran,failed — exit 1" ]]
}

@test "auto.json records the reason a phase was skipped" {
    create_committing_backend
    MOCK_REVIEW_NOOP=1 PATH="$TEST_DIR/bin:$PATH" DEVCONTAINER=true run "$RALPH" auto --skip-push -g "the goal"
    [[ "$status" -eq 0 ]]

    local -a runs=(.ralph/logs/*/)
    [[ "$(jq -r '.phases[5] | "\(.name): \(.state)"' "${runs[0]}auto.json")" == "fix: skipped — no open items" ]]
    [[ "$(jq -r '.phases[6].state' "${runs[0]}auto.json")" == "ran" ]]
}

@test "auto.json records a phase 3 refusal over a dirty specs/" {
    create_committing_backend
    mkdir -p specs
    echo "draft" > specs/x.md
    MOCK_REVIEW_NOOP=1 PATH="$TEST_DIR/bin:$PATH" DEVCONTAINER=true run "$RALPH" auto --skip-push -g "the goal"
    [[ "$status" -eq 1 ]]

    local -a runs=(.ralph/logs/*/)
    [[ "$(jq -r '.phases[2] | "\(.name): \(.state)"' "${runs[0]}auto.json")" \
        == "plan: refused — specs/ has uncommitted changes" ]]
}

@test "auto.json records init as ran when its plan template is missing" {
    create_committing_backend
    rm -f "$RALPH_CONFIG_DIR/templates/IMPLEMENTATION_PLAN.md"
    run_auto --skip-push
    [[ "$status" -eq 1 ]]

    local -a runs=(.ralph/logs/*/)
    jq -e '.phases[1] | .name == "init" and .state == "ran" and .exit == 0' "${runs[0]}auto.json"
}

@test "auto.json records the exit and times of each phase that ran, and null for one that did not" {
    create_committing_backend
    mv "$TEST_DIR/bin/claude" "$TEST_DIR/bin/claude.real"
    cat > "$TEST_DIR/bin/claude" <<MOCK
#!/usr/bin/env bash
prompt=\$(cat)
if echo "\$prompt" | grep -qi 'plan prompt'; then
    sleep 1
fi
echo "\$prompt" | "$TEST_DIR/bin/claude.real" "\$@"
MOCK
    chmod +x "$TEST_DIR/bin/claude"
    MOCK_REVIEW_NOOP=1 PATH="$TEST_DIR/bin:$PATH" DEVCONTAINER=true run "$RALPH" auto --skip-push -g "the goal"
    [[ "$status" -eq 0 ]]

    local -a runs=(.ralph/logs/*/)
    local json="${runs[0]}auto.json"
    local stamp='^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$'
    jq -e '.phases[2] | .exit == 0' "$json"
    jq -e --arg stamp "$stamp" '.phases[2] | (.started | test($stamp)) and (.ended | test($stamp))' "$json"
    jq -e '.phases[2] | .started <= .ended' "$json"
    jq -e '.phases[3].started >= .phases[2].ended' "$json"
    [[ "$(jq -r '.phases[5] | "\(.name) \(.state) \(.exit) \(.started) \(.ended)"' "$json")" \
        == "fix skipped — no open items null null null" ]]
}

@test "auto.json records the exit and end time of a phase that failed" {
    create_committing_backend
    MOCK_RETRO_EXIT=1 PATH="$TEST_DIR/bin:$PATH" DEVCONTAINER=true run "$RALPH" auto --skip-push -g "the goal"
    [[ "$status" -eq 1 ]]

    local -a runs=(.ralph/logs/*/)
    local json="${runs[0]}auto.json"
    jq -e '.phases[6] | .state == "failed — exit 1" and .exit == 1 and (.started | type == "string") and (.ended | type == "string")' "$json"
    jq -e '[.phases[:6][].exit] | all(. == 0)' "$json"
}

@test "auto.json records an interrupted phase with exit 130" {
    create_committing_backend
    mv "$TEST_DIR/bin/claude" "$TEST_DIR/bin/claude.real"
    cat > "$TEST_DIR/bin/claude" <<MOCK
#!/usr/bin/env bash
prompt=\$(cat)
if echo "\$prompt" | grep -qi 'plan prompt'; then
    touch "$BATS_TEST_TMPDIR/plan-started"
    sleep 1
fi
echo "\$prompt" | "$TEST_DIR/bin/claude.real" "\$@"
MOCK
    chmod +x "$TEST_DIR/bin/claude"

    local pid status_code=0 waited=0
    PATH="$TEST_DIR/bin:$PATH" DEVCONTAINER=true "$RALPH" auto --skip-push -g "the goal" > "$TEST_DIR/out" 2>&1 &
    pid=$!
    while [[ ! -f "$BATS_TEST_TMPDIR/plan-started" ]] && (( waited < 100 )); do
        sleep 0.1
        waited=$((waited + 1))
    done
    kill -TERM "$pid"
    wait "$pid" || status_code=$?

    [[ "$status_code" -eq 130 ]]
    local -a runs=(.ralph/logs/*/)
    jq -e '.phases[2] | .name == "plan" and .state == "interrupted" and .exit == 130' "${runs[0]}auto.json"
}

@test "--resume keeps the first goal, branch, start time and the earlier auto.json entries" {
    create_committing_backend
    MOCK_RETRO_EXIT=1 PATH="$TEST_DIR/bin:$PATH" DEVCONTAINER=true run "$RALPH" auto --skip-push -g "the goal"
    [[ "$status" -eq 1 ]]

    local -a runs=(.ralph/logs/*/)
    local json="${runs[0]}auto.json"
    jq '.goal = "first goal" | .branch = "first-branch" | .started = "2001-02-03T04:05:06Z"' "$json" > "$BATS_TEST_TMPDIR/first.json"
    cp "$BATS_TEST_TMPDIR/first.json" "$json"

    PATH="$TEST_DIR/bin:$PATH" DEVCONTAINER=true run "$RALPH" auto --resume --skip-push -g "second goal"
    [[ "$status" -eq 0 ]]

    [[ "$(jq -r '.goal, .branch, .started' "$json")" == $'first goal\nfirst-branch\n2001-02-03T04:05:06Z' ]]
    [[ "$(jq -c '.phases[:6]' "$json")" == "$(jq -c '.phases[:6]' "$BATS_TEST_TMPDIR/first.json")" ]]
    jq -e '.phases[6] | .name == "retro" and .state == "ran" and .exit == 0' "$json"
}

@test "--resume writes a fresh auto.json over a broken one" {
    create_committing_backend
    MOCK_RETRO_EXIT=1 PATH="$TEST_DIR/bin:$PATH" DEVCONTAINER=true run "$RALPH" auto --skip-push -g "the goal"
    [[ "$status" -eq 1 ]]

    local -a runs=(.ralph/logs/*/)
    local json="${runs[0]}auto.json"
    echo '{"goal": ' > "$json"

    run_auto --resume --skip-push
    [[ "$status" -eq 0 ]]

    [[ "$(jq -r '.goal' "$json")" == "the goal" ]]
    [[ "$(jq -r '[.phases[].phase] | join(",")' "$json")" == "1,2,3,4,5,6,7" ]]
    [[ "$(jq -r '.phases[0].state' "$json")" == "skipped — resumed at phase 7" ]]
    jq -e '.phases[6] | .state == "ran" and .exit == 0' "$json"
}

@test "auto warns once and runs every phase when it cannot write auto.json" {
    create_committing_backend
    printf '#!/usr/bin/env bash\ncase "$*" in *auto.json.*) exit 1 ;; esac\nexec %q "$@"\n' \
        "$(command -v mktemp)" > "$TEST_DIR/bin/mktemp"
    chmod +x "$TEST_DIR/bin/mktemp"

    run_auto --skip-push
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"7 retro     ran"* ]]
    [[ "$(grep -c 'Warning: cannot write .*auto.json; lifecycle metrics disabled' <<<"$output")" -eq 1 ]]

    local -a runs=(.ralph/logs/*/)
    [[ ! -e "${runs[0]}auto.json" ]]
    [[ -f "${runs[0]}retro/metrics.jsonl" ]]
}

@test "--no-metrics writes no auto.json" {
    create_committing_backend
    run_auto --skip-push --no-metrics
    [[ "$status" -eq 0 ]]
    [[ -z "$(find . -name auto.json -not -path './.git/*')" ]]
}
