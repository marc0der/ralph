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

# IMPLEMENTATION_PLAN.md is only an index of one-line entries; each entry links
# to a task file here, so the directory has to exist before 'ralph plan' runs.
@test "init creates plan/ directory for per-task files" {
    run "$RALPH" init
    [[ "$status" -eq 0 ]]
    [[ -d "plan" ]]
}

@test "init does not recreate or overwrite an existing plan/ directory" {
    mkdir -p plan
    echo "# mine" > plan/notes.md
    run "$RALPH" init
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"Skipped: plan/ already exists"* ]]
    grep -q "# mine" plan/notes.md
}

@test "init creates .gitignore when it does not exist" {
    run "$RALPH" init
    [[ "$status" -eq 0 ]]
    [[ -f ".gitignore" ]]
    grep -qxF "IMPLEMENTATION_PLAN.md" .gitignore
    grep -qxF "plan/" .gitignore
    grep -qxF "PROGRESS.md" .gitignore
    grep -qxF ".ralph/" .gitignore
    grep -qxF "PROMPT_plan.md" .gitignore
    grep -qxF "PROMPT_build.md" .gitignore
}

@test "init adds entries to existing .gitignore" {
    create_gitignore "node_modules"
    run "$RALPH" init
    [[ "$status" -eq 0 ]]
    grep -qxF "IMPLEMENTATION_PLAN.md" .gitignore
    grep -qxF "plan/" .gitignore
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
    [[ "$output" == *"Skipped: plan/ already exists"* ]]
    [[ "$output" == *"Skipped: .claude/skills/commit/SKILL.md already exists"* ]]
}

@test "init scaffolds the commit skill into .claude/skills/" {
    run "$RALPH" init
    [[ "$status" -eq 0 ]]
    [[ -f ".claude/skills/commit/SKILL.md" ]]
    grep -q "commit skill" .claude/skills/commit/SKILL.md
}

@test "init does not overwrite an existing commit skill" {
    mkdir -p .claude/skills/commit
    echo "# user's customised skill" > .claude/skills/commit/SKILL.md
    run "$RALPH" init
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"Skipped: .claude/skills/commit/SKILL.md already exists"* ]]
    grep -q "user's customised skill" .claude/skills/commit/SKILL.md
}

@test "init warns when the bundled commit skill is missing from config" {
    rm -rf "$RALPH_CONFIG_DIR/skills"
    run "$RALPH" init
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"Warning: commit skill not found"* ]]
    [[ ! -f ".claude/skills/commit/SKILL.md" ]]
}

@test "init --prompts copies prompt templates" {
    run "$RALPH" init --prompts
    [[ "$status" -eq 0 ]]
    [[ -f "PROMPT_plan.md" ]]
    [[ -f "PROMPT_build.md" ]]
}

@test "init without --prompts does not create prompt files" {
    run "$RALPH" init
    [[ "$status" -eq 0 ]]
    [[ ! -f "PROMPT_plan.md" ]]
    [[ ! -f "PROMPT_build.md" ]]
}
