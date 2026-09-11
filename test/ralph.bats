#!/usr/bin/env bats

load test_helper

@test "ralph prints usage with no arguments" {
    run "$RALPH"
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"Usage:"* ]]
}

@test "ralph prints usage with --help" {
    run "$RALPH" --help
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"Usage:"* ]]
}

@test "ralph --help enumerates all supported backends on the -b/--backend line" {
    run "$RALPH" --help
    [[ "$status" -eq 0 ]]
    # Spec (pi-backend.md): the -b/--backend description must list pi alongside
    # the existing claude/codex/copilot backends. Assert all four names appear
    # on the backend-flag line so dropping any one trips this test.
    [[ "$output" == *"--backend NAME"*"claude"*"codex"*"copilot"*"pi"* ]]
}

@test "ralph exits with error for unknown command" {
    run "$RALPH" nonexistent
    [[ "$status" -ne 0 ]]
}

@test "ralph --help names review in the synopsis line" {
    run "$RALPH" --help
    [[ "$status" -eq 0 ]]
    # Spec (review-phase.md section 8): review is a third mode beside plan and
    # build, so the synopsis must offer all three. A synopsis that still reads
    # 'plan|build' leaves the mode undiscoverable from --help alone.
    [[ "$output" == *"ralph <plan|build|review> [options]"* ]]
}

@test "ralph --help lists review in the Modes block" {
    run "$RALPH" --help
    [[ "$status" -eq 0 ]]
    # Spec (review-phase.md section 8) fixes this wording: review audits work
    # already shipped and files what it finds as new plan items, which is what
    # distinguishes it from plan (writes the plan) and build (executes it).
    [[ "$output" == *"review"*"Audit shipped items against the plan, file findings as new plan items"* ]]
}

@test "ralph --help states review's iteration default and convergence behaviour" {
    run "$RALPH" --help
    [[ "$status" -eq 0 ]]
    # Spec (review-phase.md section 8): review caps at PLAN_DEFAULT_CAP like
    # plan, and -n never disables its convergence exit. Users who read only the
    # build half of this description would expect -n to turn the exit off.
    [[ "$output" == *"--iterations N"*"plan and review default: 6"* ]]
    [[ "$output" == *"in plan and review modes it caps"*"never disables"*"convergence exit"* ]]
}

@test "ralph --help states that review never pushes" {
    run "$RALPH" --help
    [[ "$status" -eq 0 ]]
    # Spec (review-phase.md section 8): --skip-push is accepted but inert for
    # review, as it is for plan. Naming only plan implies review might push.
    [[ "$output" == *"--skip-push"*"plan and review"*"never push"* ]]
}
