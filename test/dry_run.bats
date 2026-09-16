#!/usr/bin/env bats

load test_helper

@test "build --dry-run prints claude command without executing" {
    "$RALPH" init
    seed_open_item
    run "$RALPH" build --dry-run -n 1
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"[dry-run] Would run: claude -p"* ]]
}

@test "build --dry-run prints push command without executing" {
    "$RALPH" init
    seed_open_item
    run "$RALPH" build --dry-run -n 1
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"[dry-run] Would run: git push"* ]]
}

@test "build --dry-run shows prompt content" {
    "$RALPH" init
    seed_open_item
    run "$RALPH" build --dry-run -n 1
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"[dry-run] Prompt content"* ]]
}

@test "plan --dry-run works" {
    "$RALPH" init
    run "$RALPH" plan --dry-run -n 1 -g "the goal"
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"[dry-run] Would run: claude -p"* ]]
}

@test "plan --dry-run never prints a push command" {
    "$RALPH" init
    run "$RALPH" plan --dry-run -n 1 -g "the goal"
    [[ "$status" -eq 0 ]]
    [[ "$output" != *"Would run: git push"* ]]
}

@test "build --dry-run respects iteration count" {
    "$RALPH" init
    seed_open_item
    run "$RALPH" build --dry-run -n 3
    [[ "$status" -eq 0 ]]
    local count
    count=$(echo "$output" | grep -c "\[dry-run\] Would run: claude")
    [[ "$count" -eq 3 ]]
}

@test "plan --dry-run includes goal in prompt" {
    "$RALPH" init
    run "$RALPH" plan --dry-run -n 1 -g "Add REST endpoint"
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"Add REST endpoint"* ]]
}

# The remaining cases cover the two prompt placeholders. cmd_loop expands
# {{GOAL}} first and {{WORKSPACE}} second, and quotes both replacements; the
# dry run is the only way to read the text ralph hands the backend.

@test "plan --dry-run expands {{WORKSPACE}} to the workspace path" {
    echo "root is {{WORKSPACE}}" > "$RALPH_CONFIG_DIR/prompts/plan.md"
    "$RALPH" init
    run "$RALPH" plan --dry-run -n 1 -g "the goal"
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"root is $TEST_DIR"* ]]
}

@test "plan --dry-run leaves no literal {{WORKSPACE}} behind" {
    echo "root is {{WORKSPACE}}" > "$RALPH_CONFIG_DIR/prompts/plan.md"
    "$RALPH" init
    run "$RALPH" plan --dry-run -n 1 -g "the goal"
    [[ "$status" -eq 0 ]]
    [[ "$output" != *"{{WORKSPACE}}"* ]]
}

@test "plan --dry-run passes a local prompt with no placeholder through unchanged" {
    "$RALPH" init
    echo "local plan prompt, no placeholder" > PROMPT_plan.md
    run "$RALPH" plan --dry-run -n 1 -g "the goal"
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"local plan prompt, no placeholder"* ]]
}

@test "plan --dry-run expands both placeholders in one prompt" {
    printf '%s\n' 'goal: {{GOAL}}' 'root: {{WORKSPACE}}' \
        > "$RALPH_CONFIG_DIR/prompts/plan.md"
    "$RALPH" init
    run "$RALPH" plan --dry-run -n 1 -g "Add REST endpoint"
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"goal: Add REST endpoint"* ]]
    [[ "$output" == *"root: $TEST_DIR"* ]]
}

# {{GOAL}} expands first, so a goal may carry {{WORKSPACE}} and still reach the
# agent as a real path — the documented way to name a spec below the root.
@test "plan --dry-run expands {{WORKSPACE}} carried by the goal" {
    echo 'goal: {{GOAL}}' > "$RALPH_CONFIG_DIR/prompts/plan.md"
    "$RALPH" init
    run "$RALPH" plan --dry-run -n 1 -g 'plan the work in {{WORKSPACE}}/specs/x.md'
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"goal: plan the work in $TEST_DIR/specs/x.md"* ]]
}

# Both replacements are quoted. Unquoted, bash 5.2's patsub_replacement turns a
# literal & in the replacement into the text the pattern matched.
@test "plan --dry-run keeps an ampersand in the workspace path" {
    local workspace="$TEST_DIR/save&load"
    mkdir -p "$workspace"
    cd "$workspace" || return 1
    git init --quiet
    echo "root is {{WORKSPACE}}" > "$RALPH_CONFIG_DIR/prompts/plan.md"
    "$RALPH" init
    run "$RALPH" plan --dry-run -n 1 -g "the goal"
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"root is $workspace"* ]]
}

@test "plan --dry-run keeps an ampersand in the goal" {
    echo 'goal: {{GOAL}}' > "$RALPH_CONFIG_DIR/prompts/plan.md"
    "$RALPH" init
    run "$RALPH" plan --dry-run -n 1 -g 'fix save & load'
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"goal: fix save & load"* ]]
}
