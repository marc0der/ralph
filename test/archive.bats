#!/usr/bin/env bats

load test_helper

@test "archive moves artifacts to .ralph/<timestamp>/" {
    "$RALPH" init
    run "$RALPH" archive
    [[ "$status" -eq 0 ]]
    [[ ! -f "IMPLEMENTATION_PLAN.md" ]]
    [[ ! -f "PROGRESS.md" ]]
    [[ -d ".ralph" ]]
    # Verify files exist in the archive subdirectory
    local archive_dir
    archive_dir=$(find .ralph -mindepth 1 -maxdepth 1 -type d | head -1)
    [[ -f "${archive_dir}/IMPLEMENTATION_PLAN.md" ]]
    [[ -f "${archive_dir}/PROGRESS.md" ]]
}

@test "archive creates timestamped directory" {
    "$RALPH" init
    "$RALPH" archive
    local dir_count
    dir_count=$(find .ralph -mindepth 1 -maxdepth 1 -type d | wc -l)
    [[ "$dir_count" -eq 1 ]]
    # Directory name should match YYYYMMDD-HHMMSS pattern
    local dir_name
    dir_name=$(basename "$(find .ralph -mindepth 1 -maxdepth 1 -type d)")
    [[ "$dir_name" =~ ^[0-9]{8}-[0-9]{6}$ ]]
}

@test "archive handles nothing to archive" {
    run "$RALPH" archive
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"Nothing to archive."* ]]
}

@test "archive reports moved files" {
    "$RALPH" init
    run "$RALPH" archive
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"Archived: IMPLEMENTATION_PLAN.md"* ]]
    [[ "$output" == *"Archived: PROGRESS.md"* ]]
}

@test "archive moves per-task files to .ralph/<timestamp>/plan/" {
    "$RALPH" init
    printf '# 001. Thing\n' > plan/001-thing.md
    run "$RALPH" archive
    [[ "$status" -eq 0 ]]
    [[ ! -f "plan/001-thing.md" ]]
    local archive_dir
    archive_dir=$(find .ralph -mindepth 1 -maxdepth 1 -type d | head -1)
    [[ -f "${archive_dir}/plan/001-thing.md" ]]
    [[ "$output" == *"Archived: plan/001-thing.md"* ]]
}

# A plan/ holding task files is enough to archive, even with the index gone
@test "archive runs when only per-task files remain" {
    mkdir -p plan
    printf '# 001. Thing\n' > plan/001-thing.md
    run "$RALPH" archive
    [[ "$status" -eq 0 ]]
    [[ "$output" != *"Nothing to archive."* ]]
    [[ ! -f "plan/001-thing.md" ]]
}

@test "archive preserves local prompt templates" {
    "$RALPH" init --prompts
    run "$RALPH" archive
    [[ "$status" -eq 0 ]]
    [[ -f "PROMPT_plan.md" ]]
    [[ -f "PROMPT_build.md" ]]
}
