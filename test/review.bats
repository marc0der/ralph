#!/usr/bin/env bats

load test_helper

# Helper: mock claude that emits a full result event but changes neither the
# plan artifacts nor HEAD, so the pass reads as a converged review.
create_review_noop_backend() {
    mkdir -p "$TEST_DIR/bin"
    cat > "$TEST_DIR/bin/claude" <<'MOCK'
#!/usr/bin/env bash
cat > /dev/null
echo '{"type":"result","subtype":"success","duration_ms":500,"duration_api_ms":400,"num_turns":2,"result":"Nothing to do.","session_id":"s2","total_cost_usd":0.01,"usage":{"input_tokens":10,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":5}}'
MOCK
    chmod +x "$TEST_DIR/bin/claude"
}

latest_metrics_file() {
    # shellcheck disable=SC2012  # newest-by-mtime needs ls; paths are ralph-generated (no odd filenames)
    ls -1t .ralph/metrics/*/metrics.jsonl | head -1
}

@test "review runs against a plan of shipped items" {
    "$RALPH" init
    printf -- '- [x] **Shipped task**\n' >> IMPLEMENTATION_PLAN.md
    run "$RALPH" review --dry-run -n 1
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"[dry-run] Would run: claude -p"* ]]
}

@test "review fails without init artifacts" {
    run "$RALPH" review
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"missing workspace artifacts required for 'review'"* ]]
    [[ "$output" == *"IMPLEMENTATION_PLAN.md"* ]]
    [[ "$output" == *"PROGRESS.md"* ]]
    [[ "$output" == *"Run 'ralph init'"* ]]
}

@test "review fails when only IMPLEMENTATION_PLAN.md is present" {
    # Review reads PROGRESS.md as a claim to verify and writes supersession
    # entries back to it, so the second artifact is a real requirement.
    echo "- [x] **Shipped task**" > IMPLEMENTATION_PLAN.md
    run "$RALPH" review
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"missing workspace artifacts required for 'review'"* ]]
    [[ "$output" == *"PROGRESS.md"* ]]
}

@test "review fails with no shipped items" {
    echo "- [ ] **Open task**" > IMPLEMENTATION_PLAN.md
    touch PROGRESS.md
    run "$RALPH" review
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"no shipped items"* ]]
}

@test "review names .ralph when the plan holds no shipped items" {
    # The anchor set is gitignored and destructible: 'ralph archive' moves the
    # plan away, so advising 'ralph build' would be wrong when the work shipped.
    echo "- [ ] **Open task**" > IMPLEMENTATION_PLAN.md
    touch PROGRESS.md
    run "$RALPH" review
    [[ "$status" -ne 0 ]]
    [[ "$output" == *".ralph/<timestamp>/"* ]]
}

@test "review ignores the Entry Format template entry" {
    # The scaffolded plan carries an example entry at column zero. Counting it
    # as shipped work would send review off to audit the template itself.
    "$RALPH" init
    run "$RALPH" review
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"no shipped items"* ]]
}

@test "review fails while an item is still open" {
    # Review audits finished work. Starting with open items would let it rank
    # its own findings against planning work it never derived.
    "$RALPH" init
    printf -- '- [x] **Shipped task**\n- [ ] **Open task**\n' >> IMPLEMENTATION_PLAN.md
    run "$RALPH" review
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"still holds incomplete items"* ]]
    [[ "$output" == *"Run 'ralph build'"* ]]
}

@test "review is not blocked by superseded items" {
    # '- [~]' marks work that was superseded or blocked. It is neither shipped
    # nor open, so it must not gate a review run either way.
    "$RALPH" init
    printf -- '- [x] **Shipped task**\n- [~] **Superseded task**\n' >> IMPLEMENTATION_PLAN.md
    run "$RALPH" review --dry-run -n 1
    [[ "$status" -eq 0 ]]
}

@test "review gates still fail with no shipped items when -n is passed" {
    # The gates run beside require_init_artifacts, not inside the iteration
    # resolution, so '-n' must not buy a run of empty audit iterations.
    echo "- [ ] **Open task**" > IMPLEMENTATION_PLAN.md
    touch PROGRESS.md
    run "$RALPH" review -n 1
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"no shipped items"* ]]
}

@test "review gates still fail with an open item when -n is passed" {
    "$RALPH" init
    printf -- '- [x] **Shipped task**\n- [ ] **Open task**\n' >> IMPLEMENTATION_PLAN.md
    run "$RALPH" review -n 1
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"still holds incomplete items"* ]]
    [[ "$output" == *"Run 'ralph build'"* ]]
}

@test "review counts shipped items in a plan with no Items heading" {
    # plan_items_body reads the whole file when '## Items' is absent, so plans
    # predating the heading must still satisfy the shipped-items precondition.
    printf -- '# Implementation Plan\n\n- [x] **Shipped task**\n' > IMPLEMENTATION_PLAN.md
    touch PROGRESS.md
    run "$RALPH" review --dry-run -n 1
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"[dry-run] Would run: claude -p"* ]]
}

@test "review defaults to 6 iterations" {
    # Review converges like plan, so it takes the same flat cap instead of
    # sizing itself from the plan the way build does.
    "$RALPH" init
    printf -- '- [x] **Shipped task**\n' >> IMPLEMENTATION_PLAN.md
    run "$RALPH" review --dry-run
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"Max:     6 iterations"* ]]
}

@test "review -n overrides the default cap" {
    "$RALPH" init
    printf -- '- [x] **Shipped task**\n' >> IMPLEMENTATION_PLAN.md
    run "$RALPH" review --dry-run -n 2
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"Max:     2 iterations"* ]]
}

@test "review exits on the first pass that changes nothing" {
    "$RALPH" init
    printf -- '- [x] **Shipped task**\n' >> IMPLEMENTATION_PLAN.md
    mkdir -p "$TEST_DIR/bin"
    # Review iterations never commit, so convergence is measured against the
    # plan artifacts, not HEAD — exactly as in plan mode.
    cat > "$TEST_DIR/bin/claude" <<'MOCK'
#!/usr/bin/env bash
echo '{"type":"result","result":"reviewing"}'
MOCK
    chmod +x "$TEST_DIR/bin/claude"

    PATH="$TEST_DIR/bin:$PATH" run "$RALPH" review --skip-push
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"Review converged — pass 1 found nothing new"* ]]
    [[ "$output" == *"Audited 1 shipped items"* ]]
    [[ "$output" == *"Completed 1 iterations"* ]]
}

@test "review convergence exit still applies when -n is passed" {
    "$RALPH" init
    printf -- '- [x] **Shipped task**\n' >> IMPLEMENTATION_PLAN.md
    mkdir -p "$TEST_DIR/bin"
    # -n caps a review run but must not disable convergence, unlike build mode.
    cat > "$TEST_DIR/bin/claude" <<'MOCK'
#!/usr/bin/env bash
echo '{"type":"result","result":"reviewing"}'
MOCK
    chmod +x "$TEST_DIR/bin/claude"

    PATH="$TEST_DIR/bin:$PATH" run "$RALPH" review -n 12 --skip-push
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"Review converged — pass 1 found nothing new"* ]]
    [[ "$output" == *"Completed 1 iterations"* ]]
}

@test "review continues while passes keep filing findings" {
    "$RALPH" init
    printf -- '- [x] **Shipped one**\n- [x] **Shipped two**\n' >> IMPLEMENTATION_PLAN.md
    mkdir -p "$TEST_DIR/bin"
    # Files a finding on passes 1 and 2, then goes quiet on pass 3. The audited
    # count is ralph's own tally of '- [x]' items, so the findings the pass adds
    # must not inflate it.
    cat > "$TEST_DIR/bin/claude" <<MOCK
#!/usr/bin/env bash
CALL_LOG="$TEST_DIR/call_count"
count=0
[[ -f "\$CALL_LOG" ]] && count=\$(cat "\$CALL_LOG")
count=\$((count + 1))
echo "\$count" > "\$CALL_LOG"
if [[ "\$count" -le 2 ]]; then
    echo "- [ ] **Critical: finding \$count**" >> IMPLEMENTATION_PLAN.md
fi
echo '{"type":"result","result":"reviewing"}'
MOCK
    chmod +x "$TEST_DIR/bin/claude"

    PATH="$TEST_DIR/bin:$PATH" run "$RALPH" review --skip-push
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"Review converged — pass 3 found nothing new"* ]]
    [[ "$output" == *"Audited 2 shipped items"* ]]
    [[ "$output" == *"Completed 3 iterations"* ]]
}

@test "review never pushes even without --skip-push (no remote configured)" {
    # IMPLEMENTATION_PLAN.md and PROGRESS.md are both gitignored, so a review
    # pass produces nothing to push and HEAD cannot move. Only build reaches
    # the push block.
    "$RALPH" init
    printf -- '- [x] **Shipped task**\n' >> IMPLEMENTATION_PLAN.md
    mkdir -p "$TEST_DIR/bin"
    cat > "$TEST_DIR/bin/claude" <<'MOCK'
#!/usr/bin/env bash
echo '{"type":"result","result":"reviewing"}'
MOCK
    chmod +x "$TEST_DIR/bin/claude"

    # No 'origin' remote exists; if review attempted a push it would fail.
    PATH="$TEST_DIR/bin:$PATH" run "$RALPH" review -n 1
    [[ "$status" -eq 0 ]]
    [[ "$output" != *"Push failed"* ]]
    [[ "$output" == *"Completed 1 iteration"* ]]
}

@test "review accepts --skip-push as an inert flag" {
    # Spec section 8 keeps the flag surface identical across the three modes,
    # so --skip-push must be accepted rather than rejected, and must not
    # change a review run that never pushes in the first place.
    "$RALPH" init
    printf -- '- [x] **Shipped task**\n' >> IMPLEMENTATION_PLAN.md
    mkdir -p "$TEST_DIR/bin"
    cat > "$TEST_DIR/bin/claude" <<'MOCK'
#!/usr/bin/env bash
echo '{"type":"result","result":"reviewing"}'
MOCK
    chmod +x "$TEST_DIR/bin/claude"

    PATH="$TEST_DIR/bin:$PATH" run "$RALPH" review -n 1 --skip-push
    [[ "$status" -eq 0 ]]
    [[ "$output" != *"unknown option"* ]]
    [[ "$output" == *"Completed 1 iteration"* ]]
}

@test "review mode records metrics" {
    # Metrics need no schema change for review: the mode is tagged as its own
    # and plan_items_completed is always 0, because review never ticks a
    # checkbox — it only appends findings as new open items.
    "$RALPH" init
    printf -- '- [x] **Shipped task**\n' >> IMPLEMENTATION_PLAN.md
    create_review_noop_backend

    PATH="$TEST_DIR/bin:$PATH" "$RALPH" review -n 1 -y

    local line
    line=$(tail -1 "$(latest_metrics_file)")
    [[ $(jq -r '.mode' <<<"$line") == "review" ]]
    [[ $(jq -r '.turns' <<<"$line") == "2" ]]
    [[ $(jq -r '.plan_items_completed' <<<"$line") == "0" ]]
}

@test "review iteration that changes nothing records noop=true" {
    # Review commits nothing, so HEAD-based noop detection would call every
    # pass a noop. The flag comes from the plan-state fingerprint instead.
    "$RALPH" init
    printf -- '- [x] **Shipped task**\n' >> IMPLEMENTATION_PLAN.md
    create_review_noop_backend

    PATH="$TEST_DIR/bin:$PATH" "$RALPH" review -n 1 --skip-push -y

    local line
    line=$(tail -1 "$(latest_metrics_file)")
    [[ $(jq -r '.mode' <<<"$line") == "review" ]]
    [[ $(jq -r '.git.noop' <<<"$line") == "true" ]]
}
