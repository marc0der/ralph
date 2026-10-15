#!/usr/bin/env bats

load test_helper

@test "init creates PROGRESS.md" {
    run "$RALPH" init
    [[ "$status" -eq 0 ]]
    [[ -f "PROGRESS.md" ]]
}

@test "init creates IMPLEMENTATION_PLAN.md" {
    run "$RALPH" init
    [[ "$status" -eq 0 ]]
    [[ -f "IMPLEMENTATION_PLAN.md" ]]
}

@test "init creates specs/ directory" {
    run "$RALPH" init
    [[ "$status" -eq 0 ]]
    [[ -d "specs" ]]
}

@test "init creates .gitignore when it does not exist" {
    run "$RALPH" init
    [[ "$status" -eq 0 ]]
    [[ -f ".gitignore" ]]
    grep -qxF "IMPLEMENTATION_PLAN.md" .gitignore
    grep -qxF "PROGRESS.md" .gitignore
    grep -qxF ".ralph/" .gitignore
    grep -qxF "PROMPT_plan.md" .gitignore
    grep -qxF "PROMPT_build.md" .gitignore
    grep -qxF "PROMPT_review.md" .gitignore
}

@test "init adds entries to existing .gitignore" {
    create_gitignore "node_modules"
    run "$RALPH" init
    [[ "$status" -eq 0 ]]
    grep -qxF "IMPLEMENTATION_PLAN.md" .gitignore
    grep -qxF "PROGRESS.md" .gitignore
    grep -qxF ".ralph/" .gitignore
    grep -qxF "PROMPT_plan.md" .gitignore
    grep -qxF "PROMPT_build.md" .gitignore
}

@test "init does not duplicate .gitignore entries on second run" {
    create_gitignore "node_modules"
    "$RALPH" init
    "$RALPH" init
    local count
    count=$(grep -cxF "IMPLEMENTATION_PLAN.md" .gitignore)
    [[ "$count" -eq 1 ]]
}

@test "init handles .gitignore without trailing newline" {
    printf "node_modules" > .gitignore
    run "$RALPH" init
    [[ "$status" -eq 0 ]]
    # First gitignore entry should be on its own line, not concatenated
    run ! grep -q "node_modulesIMPLEMENTATION_PLAN.md" .gitignore
    grep -qxF "node_modules" .gitignore
    grep -qxF "IMPLEMENTATION_PLAN.md" .gitignore
}

@test "init is idempotent — second run skips existing artifacts" {
    "$RALPH" init
    run "$RALPH" init
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"Skipped: PROGRESS.md already exists"* ]]
    [[ "$output" == *"Skipped: IMPLEMENTATION_PLAN.md already exists"* ]]
    [[ "$output" == *"Skipped: specs/ already exists"* ]]
}

@test "init --prompts copies prompt templates" {
    run "$RALPH" init --prompts
    [[ "$status" -eq 0 ]]
    [[ -f "PROMPT_plan.md" ]]
    [[ -f "PROMPT_build.md" ]]
    [[ -f "PROMPT_review.md" ]]
}

@test "init without --prompts does not create prompt files" {
    run "$RALPH" init
    [[ "$status" -eq 0 ]]
    [[ ! -f "PROMPT_plan.md" ]]
    [[ ! -f "PROMPT_build.md" ]]
}

@test "init adds ralph.yaml to .gitignore" {
    run "$RALPH" init
    [[ "$status" -eq 0 ]]
    grep -qxF "ralph.yaml" .gitignore
}

@test "init without --config does not create ralph.yaml" {
    echo "defaults: {}" > "$RALPH_CONFIG_DIR/config.yaml"
    run "$RALPH" init
    [[ "$status" -eq 0 ]]
    [[ ! -f "ralph.yaml" ]]
}

@test "init --config copies the central config.yaml to ralph.yaml" {
    echo "build: {backend: codex}" > "$RALPH_CONFIG_DIR/config.yaml"
    run "$RALPH" init --config
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"Created: ralph.yaml"* ]]
    cmp "$RALPH_CONFIG_DIR/config.yaml" ralph.yaml
}

@test "init --config skips an existing ralph.yaml" {
    echo "build: {backend: codex}" > "$RALPH_CONFIG_DIR/config.yaml"
    echo "plan: {backend: pi}" > ralph.yaml
    run "$RALPH" init --config
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"Skipped: ralph.yaml already exists"* ]]
    [[ "$(cat ralph.yaml)" == "plan: {backend: pi}" ]]
}

@test "init --config fails when the central config.yaml is missing" {
    run "$RALPH" init --config
    [[ "$status" -eq 1 ]]
    [[ "$output" == *"Error: ralph config not found at $RALPH_CONFIG_DIR/config.yaml"* ]]
    [[ "$output" == *"Run the installer first: ./install.sh"* ]]
    [[ ! -f "ralph.yaml" ]]
}

@test "init --config --prompts creates ralph.yaml and the prompts in one run" {
    echo "defaults: {}" > "$RALPH_CONFIG_DIR/config.yaml"
    run "$RALPH" init --config --prompts
    [[ "$status" -eq 0 ]]
    [[ -f "ralph.yaml" ]]
    [[ -f "PROMPT_plan.md" ]]
    [[ -f "PROMPT_build.md" ]]
    [[ -f "PROMPT_review.md" ]]
}

@test "the repository .gitignore holds every entry init adds" {
    cp "$BATS_TEST_DIRNAME/../.gitignore" .gitignore
    run "$RALPH" init
    [[ "$status" -eq 0 ]]
    [[ "$output" != *"Added to .gitignore:"* ]]
    cmp .gitignore "$BATS_TEST_DIRNAME/../.gitignore"
}
