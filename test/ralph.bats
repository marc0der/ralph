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
    # Spec (one-shot-review.md section 13) fixes this wording: review makes one
    # pass over the cycle's work and files what it finds as new plan items.
    [[ "$output" == *"review"*"Review the cycle's work in one pass and file findings as new plan items"* ]]
}

@test "ralph --help states plan's iteration default and that review rejects -n" {
    run "$RALPH" --help
    [[ "$status" -eq 0 ]]
    # Spec (one-shot-review.md section 13): review runs exactly one pass and
    # rejects -n, so the -n help names plan's default alone and never implies
    # review converges over several passes.
    [[ "$output" == *"--iterations N"*"plan default: 6"* ]]
    [[ "$output" == *"in plan mode it caps"*"never disables"*"convergence exit"* ]]
    [[ "$output" == *"review rejects -n"* ]]
    [[ "$output" != *"plan and review default"* ]]
}

@test "ralph --help states that review never pushes" {
    run "$RALPH" --help
    [[ "$status" -eq 0 ]]
    # Spec (plan-commits-specs.md section 3): plan pushes like build, and
    # --skip-push stays inert for review.
    [[ "$output" == *"--skip-push"*"plan or build iteration (review"*"never pushes)"* ]]
}

@test "ralph --help marks the goal as plan-and-auto only and required" {
    run "$RALPH" --help
    [[ "$status" -eq 0 ]]
    # Spec (meta-repo-hardening.md section 12, "The goal is required"): plan
    # derives its work from the goal and refuses a run without one, and auto
    # forwards the goal to its plan phase. build and review reject -g because
    # their input is IMPLEMENTATION_PLAN.md. A bare "Goal to inject into the
    # prompt template" reads as optional everywhere and invites a bare
    # 'ralph plan', which is the run that wrote a plan in the wrong directory.
    [[ "$output" == *"--goal TEXT"*"plan and auto only; required"* ]]
}

@test "commands without verbose output refuse -q and --quiet" {
    # Spec (verbose-by-default.md section 8): only plan, build, review and auto
    # accept the flag; every other command exits 1 with an error on stderr.
    local command flag
    for command in sandbox init archive clean metrics version; do
        for flag in -q --quiet; do
            run --separate-stderr "$RALPH" "$command" "$flag"
            [[ "$status" -eq 1 ]]
            # shellcheck disable=SC2154  # set by bats `run --separate-stderr`, not by this script
            [[ -n "$stderr" ]]
        done
    done
}

@test "archive, clean, metrics and version name themselves in the --quiet refusal" {
    local command flag
    for command in archive clean metrics version; do
        for flag in -q --quiet; do
            run --separate-stderr "$RALPH" "$command" "$flag"
            [[ "$status" -eq 1 ]]
            [[ "$stderr" == "Error: '$command' does not accept --quiet." ]]
            [[ -z "$output" ]]
        done
    done
}
