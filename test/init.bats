#!/usr/bin/env bats

load test_helper

@test "init creates PROGRESS.md" {
    run "$RALPH" init
    [[ "$status" -eq 0 ]]
    [[ -f "PROGRESS.md" ]]
}

@test "init creates LEARNINGS.md" {
    run "$RALPH" init
    [[ "$status" -eq 0 ]]
    [[ -f "LEARNINGS.md" ]]
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

@test "init does not touch .gitignore by default" {
    run "$RALPH" init
    [[ "$status" -eq 0 ]]
    [[ ! -f ".gitignore" ]]
    [[ "$output" != *"Added to .gitignore"* ]]
}

@test "init leaves an existing .gitignore untouched by default" {
    create_gitignore "node_modules"
    run "$RALPH" init
    [[ "$status" -eq 0 ]]
    [[ "$(cat .gitignore)" == "node_modules" ]]
}

@test "init --gitignore creates .gitignore when it does not exist" {
    run "$RALPH" init --gitignore
    [[ "$status" -eq 0 ]]
    [[ -f ".gitignore" ]]
    grep -qxF "IMPLEMENTATION_PLAN.md" .gitignore
    grep -qxF "plan/" .gitignore
    grep -qxF "PROGRESS.md" .gitignore
    grep -qxF "LEARNINGS.md" .gitignore
    grep -qxF "REVIEW.md" .gitignore
    grep -qxF ".ralph/" .gitignore
}

@test "init --gitignore never ignores the PROMPT_ files" {
    run "$RALPH" init --gitignore
    [[ "$status" -eq 0 ]]
    run ! grep -q "PROMPT_" .gitignore
}

@test "init --gitignore groups its entries under a section header" {
    create_gitignore "node_modules"
    run "$RALPH" init --gitignore
    [[ "$status" -eq 0 ]]
    grep -qxF "# Ralph loop artifacts" .gitignore
    # The header must precede the entries it labels
    local header_line entry_line
    header_line=$(grep -nxF "# Ralph loop artifacts" .gitignore | cut -d: -f1)
    entry_line=$(grep -nxF "IMPLEMENTATION_PLAN.md" .gitignore | cut -d: -f1)
    [[ "$header_line" -lt "$entry_line" ]]
}

@test "init --gitignore adds entries to an existing .gitignore" {
    create_gitignore "node_modules"
    run "$RALPH" init --gitignore
    [[ "$status" -eq 0 ]]
    grep -qxF "node_modules" .gitignore
    grep -qxF "IMPLEMENTATION_PLAN.md" .gitignore
    grep -qxF "plan/" .gitignore
    grep -qxF "PROGRESS.md" .gitignore
    grep -qxF "LEARNINGS.md" .gitignore
    grep -qxF ".ralph/" .gitignore
}

@test "init --gitignore does not duplicate entries on a second run" {
    create_gitignore "node_modules"
    "$RALPH" init --gitignore
    run "$RALPH" init --gitignore
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"Skipped: .gitignore already ignores the loop artifacts"* ]]
    local count
    count=$(grep -cxF "IMPLEMENTATION_PLAN.md" .gitignore)
    [[ "$count" -eq 1 ]]
    count=$(grep -cxF "# Ralph loop artifacts" .gitignore)
    [[ "$count" -eq 1 ]]
}

@test "init --gitignore handles .gitignore without trailing newline" {
    printf "node_modules" > .gitignore
    run "$RALPH" init --gitignore
    [[ "$status" -eq 0 ]]
    # The header must not be concatenated onto the last existing line
    run ! grep -q "node_modules#" .gitignore
    grep -qxF "node_modules" .gitignore
    grep -qxF "IMPLEMENTATION_PLAN.md" .gitignore
}

@test "init rejects an unknown option" {
    run "$RALPH" init --nope
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"unknown init option"* ]]
}

@test "init is idempotent — second run skips existing artifacts" {
    "$RALPH" init
    run "$RALPH" init
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"Skipped: PROGRESS.md already exists"* ]]
    [[ "$output" == *"Skipped: LEARNINGS.md already exists"* ]]
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
