#!/usr/bin/env bats

load test_helper

# resolve_prompt is not directly callable, so we source ralph and call it
# We need to prevent ralph from executing its main dispatch
resolve() {
    (
        export RALPH_CONFIG_DIR
        # Source only the functions by stopping before main dispatch
        eval "$(sed '/^# Main dispatch/,$d' "$RALPH")"
        resolve_prompt "$1"
    )
}

@test "resolve_prompt prefers local PROMPT_<mode>.md" {
    echo "local plan" > PROMPT_plan.md
    run resolve plan
    [[ "$status" -eq 0 ]]
    [[ "$output" == "PROMPT_plan.md" ]]
}

@test "resolve_prompt falls back to installed default" {
    run resolve plan
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"prompts/plan.md" ]]
}

@test "resolve_prompt errors when no prompt found" {
    rm -rf "$RALPH_CONFIG_DIR/prompts"
    run resolve plan
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"no prompt found for mode 'plan'"* ]]
}

@test "resolve_prompt works for build mode" {
    run resolve build
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"prompts/build.md" ]]
}

@test "resolve_prompt local file takes priority over default" {
    echo "local build" > PROMPT_build.md
    run resolve build
    [[ "$status" -eq 0 ]]
    [[ "$output" == "PROMPT_build.md" ]]
}
