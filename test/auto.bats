#!/usr/bin/env bats

# Auto lifecycle suite (specs/auto-lifecycle.md §11). auto runs the six phases
# archive → init → plan → build → review → build as children of the same
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
    run "$RALPH" auto --help -g "the goal"
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"auto"* ]]
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

@test "auto --force prints its notice, not the backend banner" {
    create_committing_backend
    DEVCONTAINER=false PATH="$TEST_DIR/bin:$PATH" run "$RALPH" auto --force --dry-run -g "the goal"
    [[ "$output" != *"Backend:"* ]]
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
    [[ "$output" == *"6 build     ran"* ]]
}

@test "a lifecycle whose review files nothing skips phase 6 and exits 0" {
    create_committing_backend
    MOCK_REVIEW_NOOP=1 PATH="$TEST_DIR/bin:$PATH" DEVCONTAINER=true run "$RALPH" auto --skip-push --no-metrics -g "the goal"
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"5 review    ran"* ]]
    [[ "$output" == *"6 build     skipped"* ]]
}

@test "the report prints the six numbered phase rows" {
    create_committing_backend
    run_auto --skip-push --no-metrics
    [[ "$output" == *"1 archive"* ]]
    [[ "$output" == *"2 init"* ]]
    [[ "$output" == *"3 plan"* ]]
    [[ "$output" == *"Artifacts: IMPLEMENTATION_PLAN.md and PROGRESS.md"* ]]
}

# --- Guards and skip reasons ------------------------------------------------

@test "phase 5 is skipped when open items remain, naming the count" {
    create_committing_backend
    seed_resume_state 5
    echo "- [x] **shipped**" >> IMPLEMENTATION_PLAN.md
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

@test "phase 4 is skipped when the plan holds no open item" {
    create_committing_backend
    seed_resume_state 4
    echo "- [x] **shipped**" >> IMPLEMENTATION_PLAN.md
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
    [[ "$output" == *"6 build     skipped — no plan artifacts"* ]]
}

# --- Abort, not-reached, child exit in the report ---------------------------

@test "a failing phase aborts and reports later phases as not reached" {
    create_committing_backend
    MOCK_EXIT=3 PATH="$TEST_DIR/bin:$PATH" DEVCONTAINER=true run "$RALPH" auto --skip-push --no-metrics -g "the goal"
    [[ "$status" -eq 1 ]]
    [[ "$output" == *"3 plan      failed — exit 3"* ]]
    [[ "$output" == *"4 build     not reached"* ]]
    [[ "$output" == *"5 review    not reached"* ]]
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

@test "--resume from phase 1 still enters at phase 3" {
    create_committing_backend
    seed_resume_state 1
    git add -A -- .; git commit -q -m seed
    run_auto --resume --skip-push --no-metrics
    [[ "$output" == *"2 init      skipped — resumed at phase 3"* ]]
    [[ "$output" == *"3 plan      ran"* ]]
}

@test "--resume prints the recorded phase, child exit and manual-repair notice" {
    create_committing_backend
    seed_resume_state 5
    echo "- [x] **shipped**" >> IMPLEMENTATION_PLAN.md
    git add -A -- .; git commit -q -m seed
    run_auto --resume --skip-push --no-metrics
    [[ "$output" == *"Resumed from phase 5"* ]]
    [[ "$output" == *"child exit 1"* ]]
    [[ "$output" == *"manual repair"* ]]
}

# --- Dry run ----------------------------------------------------------------

@test "--dry-run names all six phases and states guards run at run time" {
    DEVCONTAINER=true run "$RALPH" auto --dry-run -g "the goal"
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"1 archive"* ]]
    [[ "$output" == *"6 build"* ]]
    [[ "$output" == *"guards are evaluated at run time"* ]]
}

@test "--dry-run invokes nothing: no artifacts, no metrics, succeeds uninitialised" {
    DEVCONTAINER=true run "$RALPH" auto --dry-run -g "the goal"
    [[ "$status" -eq 0 ]]
    [[ ! -f IMPLEMENTATION_PLAN.md ]]
    [[ ! -d .ralph/metrics ]]
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

# --- Flag forwarding by behaviour (§11) -------------------------------------

@test "--no-metrics reaches children: no .ralph/metrics directory is created" {
    create_committing_backend
    run_auto --skip-push --no-metrics
    [[ "$status" -eq 0 ]]
    [[ ! -d .ralph/metrics ]]
}

@test "-v reaches children: [verbose] markers appear on the output" {
    create_committing_backend
    run_auto -v --skip-push --no-metrics
    [[ "$output" == *"[verbose]"* ]]
}

@test "--skip-push reaches children: a lifecycle completes in a repo with no remote" {
    create_committing_backend
    run_auto --skip-push --no-metrics
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"6 build     ran"* ]]
}
