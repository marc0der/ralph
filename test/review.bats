#!/usr/bin/env bats

load test_helper

# Helper: mock claude that writes REVIEW.md and emits a claude-shaped result
# event, changing nothing else — the contract the review prompt enforces.
create_review_backend() {
    mkdir -p "$TEST_DIR/bin"
    cat > "$TEST_DIR/bin/claude" <<'MOCK'
#!/usr/bin/env bash
cat > /dev/null
printf '# Review\n\nVerdict: mergeable with nits.\n' > REVIEW.md
echo '{"type":"result","subtype":"success","duration_ms":2000,"duration_api_ms":1500,"num_turns":6,"result":"Review written to REVIEW.md.","session_id":"r1","total_cost_usd":0.42,"usage":{"input_tokens":900,"cache_creation_input_tokens":0,"cache_read_input_tokens":12000,"output_tokens":700}}'
MOCK
    chmod +x "$TEST_DIR/bin/claude"
}

latest_metrics_line() {
    # shellcheck disable=SC2012  # newest-by-mtime needs ls; paths are ralph-generated (no odd filenames)
    tail -1 "$(ls -1t .ralph/metrics/*/metrics.jsonl | head -1)"
}

@test "review runs a single iteration by default and writes REVIEW.md" {
    create_review_backend

    # No remote is configured in the test repo, so an attempted push would fail
    # the run — passing status doubles as the review-never-pushes assertion.
    PATH="$TEST_DIR/bin:$PATH" run "$RALPH" review -y
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"Completed 1 iterations."* ]]
    [[ -f "REVIEW.md" ]]
    grep -q "mergeable with nits" REVIEW.md
}

@test "review needs no init artifacts" {
    # Deliberately no 'ralph init': neither IMPLEMENTATION_PLAN.md nor
    # PROGRESS.md exists, which would fail plan/build at the artifact check.
    create_review_backend

    PATH="$TEST_DIR/bin:$PATH" run "$RALPH" review -y
    [[ "$status" -eq 0 ]]
    [[ ! -f "IMPLEMENTATION_PLAN.md" ]]
}

@test "review respects -n override" {
    create_review_backend

    PATH="$TEST_DIR/bin:$PATH" run "$RALPH" review -n 2 -y
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"Completed 2 iterations."* ]]
}

@test "review dry-run shows the prompt and no push" {
    run "$RALPH" review --dry-run
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"# Review prompt"* ]]
    [[ "$output" != *"git push"* ]]
}

@test "project-local PROMPT_review.md overrides the installed default" {
    echo "# Local review override" > PROMPT_review.md

    run "$RALPH" review --dry-run
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"# Local review override"* ]]
    [[ "$output" != *"# Review prompt"* ]]
}

@test "review records metrics with mode=review" {
    create_review_backend

    PATH="$TEST_DIR/bin:$PATH" "$RALPH" review -y

    local line
    line=$(latest_metrics_line)
    [[ $(jq -r '.mode' <<<"$line") == "review" ]]
    [[ $(jq -r '.turns' <<<"$line") == "6" ]]
    [[ $(jq -r '.git.noop' <<<"$line") == "true" ]]
}

@test "init gitignores REVIEW.md and PROMPT_review.md" {
    run "$RALPH" init
    [[ "$status" -eq 0 ]]
    grep -qxF "REVIEW.md" .gitignore
    grep -qxF "PROMPT_review.md" .gitignore
}

@test "init --prompts scaffolds PROMPT_review.md" {
    run "$RALPH" init --prompts
    [[ "$status" -eq 0 ]]
    [[ -f "PROMPT_review.md" ]]
    grep -q "# Review prompt" PROMPT_review.md
}

@test "clean deletes REVIEW.md" {
    echo "# Review" > REVIEW.md
    run "$RALPH" clean
    [[ "$status" -eq 0 ]]
    [[ ! -f "REVIEW.md" ]]
}

@test "archive moves REVIEW.md" {
    echo "# Review" > REVIEW.md
    run "$RALPH" archive
    [[ "$status" -eq 0 ]]
    [[ ! -f "REVIEW.md" ]]
    local archived
    archived=$(find .ralph -name "REVIEW.md" | head -1)
    [[ -n "$archived" ]]
}

@test "usage lists the review mode" {
    run "$RALPH" --help
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"review"* ]]
    [[ "$output" == *"REVIEW.md"* ]]
}
