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
    printf -- '- [x] **Shipped task**\n  Spec: specs/mock.md item 1\n' >> IMPLEMENTATION_PLAN.md
    seed_cycle_base
    run "$RALPH" review --dry-run
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
    printf -- '- [x] **Shipped task**\n  Spec: specs/mock.md item 1\n' > IMPLEMENTATION_PLAN.md
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
    printf -- '- [x] **Shipped task**\n  Spec: specs/mock.md item 1\n- [ ] **Open task**\n' >> IMPLEMENTATION_PLAN.md
    run "$RALPH" review
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"still holds incomplete items"* ]]
    [[ "$output" == *"Run 'ralph build'"* ]]
}

@test "review is not blocked by superseded items" {
    # '- [~]' marks work that was superseded or blocked. It is neither shipped
    # nor open, so it must not gate a review run either way.
    "$RALPH" init
    printf -- '- [x] **Shipped task**\n  Spec: specs/mock.md item 1\n- [~] **Superseded task**\n' >> IMPLEMENTATION_PLAN.md
    seed_cycle_base
    run "$RALPH" review --dry-run
    [[ "$status" -eq 0 ]]
}

@test "review fails without .ralph/cycle-base" {
    # The cycle base bounds the cycle's work. Without it review cannot tell
    # this cycle's changes from the rest of the tree.
    "$RALPH" init
    printf -- '- [x] **Shipped task**\n  Spec: specs/mock.md item 1\n' >> IMPLEMENTATION_PLAN.md
    run "$RALPH" review
    [[ "$status" -ne 0 ]]
    [[ "$output" == *".ralph/cycle-base is missing"* ]]
    [[ "$output" == *"Run 'ralph build' first"* ]]
}

@test "review runs when the only citation is the verification gate" {
    # A plan citing no spec still ships code, and that code gets reviewed.
    # shellcheck disable=SC2016  # the backticks quote a plan citation, not a command substitution
    printf -- '- [x] **Run the gate**\n  Spec: `AGENTS.md verification gate`\n' > IMPLEMENTATION_PLAN.md
    touch PROGRESS.md
    seed_cycle_base
    run "$RALPH" review --dry-run
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"[dry-run] Would run: claude -p"* ]]
}

@test "review derives a backtick citation in a plan with no Items heading" {
    # plan_items_body reads the whole file without the heading, and the awk
    # split treats a backtick as a delimiter, so the bare path survives both.
    # shellcheck disable=SC2016  # the backticks quote a plan citation, not a command substitution
    printf -- '# Implementation Plan\n\n- [x] **Shipped task**\n  Spec: `specs/mock.md` item 1\n' > IMPLEMENTATION_PLAN.md
    touch PROGRESS.md
    seed_cycle_base
    run "$RALPH" review --dry-run
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"[dry-run] Would run: claude -p"* ]]
}

@test "review counts shipped items in a plan with no Items heading" {
    # plan_items_body reads the whole file when '## Items' is absent, so plans
    # predating the heading must still satisfy the shipped-items precondition.
    printf -- '# Implementation Plan\n\n- [x] **Shipped task**\n  Spec: specs/mock.md item 1\n' > IMPLEMENTATION_PLAN.md
    touch PROGRESS.md
    seed_cycle_base
    run "$RALPH" review --dry-run
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"[dry-run] Would run: claude -p"* ]]
}

@test "review rejects -n" {
    # Review audits the cycle in one pass, so an iteration count has no meaning.
    "$RALPH" init
    printf -- '- [x] **Shipped task**\n  Spec: specs/mock.md item 1\n' >> IMPLEMENTATION_PLAN.md
    seed_cycle_base
    run "$RALPH" review -n 3
    [[ "$status" -eq 1 ]]
    [[ "$output" == *"Error: review runs one pass; -n does not apply."* ]]
}

@test "review invokes the backend once whether or not the plan changes" {
    # A pass that files findings changes the plan, yet review must not run a
    # second pass to wait for convergence.
    "$RALPH" init
    printf -- '- [x] **Shipped task**\n  Spec: specs/mock.md item 1\n' >> IMPLEMENTATION_PLAN.md
    mkdir -p "$TEST_DIR/bin"
    cat > "$TEST_DIR/bin/claude" <<MOCK
#!/usr/bin/env bash
cat > /dev/null
echo x >> "$TEST_DIR/calls"
[[ -n "\$FILE_FINDING" ]] && echo "- [ ] **Critical: finding**" >> IMPLEMENTATION_PLAN.md
echo '{"type":"result","result":"reviewing"}'
MOCK
    chmod +x "$TEST_DIR/bin/claude"
    seed_cycle_base

    PATH="$TEST_DIR/bin:$PATH" run "$RALPH" review --skip-push -y
    [[ "$status" -eq 0 ]]
    [[ $(wc -l < "$TEST_DIR/calls") -eq 1 ]]

    rm "$TEST_DIR/calls"
    FILE_FINDING=1 PATH="$TEST_DIR/bin:$PATH" run "$RALPH" review --skip-push -y
    [[ "$status" -eq 0 ]]
    [[ $(wc -l < "$TEST_DIR/calls") -eq 1 ]]
    [[ "$output" == *"Completed 1 iteration"* ]]
}

@test "review exits on the first pass that changes nothing" {
    "$RALPH" init
    printf -- '- [x] **Shipped task**\n  Spec: specs/mock.md item 1\n' >> IMPLEMENTATION_PLAN.md
    mkdir -p "$TEST_DIR/bin"
    # Review iterations never commit, so convergence is measured against the
    # plan artifacts, not HEAD — exactly as in plan mode.
    cat > "$TEST_DIR/bin/claude" <<'MOCK'
#!/usr/bin/env bash
echo '{"type":"result","result":"reviewing"}'
MOCK
    chmod +x "$TEST_DIR/bin/claude"

    seed_cycle_base
    PATH="$TEST_DIR/bin:$PATH" run "$RALPH" review --skip-push
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"Review converged — pass 1 found nothing new"* ]]
    [[ "$output" == *"Audited 1 specs"* ]]
    [[ "$output" == *"Completed 1 iterations"* ]]
}

@test "review counts distinct specs, not shipped items" {
    # The anchor set is the set of cited specs. Three shipped items citing two
    # paths audit two specs, and a nested repo's path stays distinct from the
    # root's even when both file names match.
    "$RALPH" init
    printf -- '- [x] **One**\n  Spec: specs/mock.md item 1\n- [x] **Two**\n  Spec: source/svc/specs/mock.md item 2\n- [x] **Three**\n  Spec: specs/mock.md item 3\n' >> IMPLEMENTATION_PLAN.md
    mkdir -p "$TEST_DIR/bin"
    cat > "$TEST_DIR/bin/claude" <<'MOCK'
#!/usr/bin/env bash
echo '{"type":"result","result":"reviewing"}'
MOCK
    chmod +x "$TEST_DIR/bin/claude"

    seed_cycle_base
    PATH="$TEST_DIR/bin:$PATH" run "$RALPH" review --skip-push
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"Audited 2 specs"* ]]
}

@test "review never pushes even without --skip-push (no remote configured)" {
    # IMPLEMENTATION_PLAN.md and PROGRESS.md are both gitignored, so a review
    # pass produces nothing to push and HEAD cannot move. Only build reaches
    # the push block.
    "$RALPH" init
    printf -- '- [x] **Shipped task**\n  Spec: specs/mock.md item 1\n' >> IMPLEMENTATION_PLAN.md
    mkdir -p "$TEST_DIR/bin"
    cat > "$TEST_DIR/bin/claude" <<'MOCK'
#!/usr/bin/env bash
echo '{"type":"result","result":"reviewing"}'
MOCK
    chmod +x "$TEST_DIR/bin/claude"

    # No 'origin' remote exists; if review attempted a push it would fail.
    seed_cycle_base
    PATH="$TEST_DIR/bin:$PATH" run "$RALPH" review
    [[ "$status" -eq 0 ]]
    [[ "$output" != *"Push failed"* ]]
    [[ "$output" == *"Completed 1 iteration"* ]]
}

@test "review accepts --skip-push as an inert flag" {
    # Spec section 8 keeps the flag surface identical across the three modes,
    # so --skip-push must be accepted rather than rejected, and must not
    # change a review run that never pushes in the first place.
    "$RALPH" init
    printf -- '- [x] **Shipped task**\n  Spec: specs/mock.md item 1\n' >> IMPLEMENTATION_PLAN.md
    mkdir -p "$TEST_DIR/bin"
    cat > "$TEST_DIR/bin/claude" <<'MOCK'
#!/usr/bin/env bash
echo '{"type":"result","result":"reviewing"}'
MOCK
    chmod +x "$TEST_DIR/bin/claude"

    seed_cycle_base
    PATH="$TEST_DIR/bin:$PATH" run "$RALPH" review --skip-push
    [[ "$status" -eq 0 ]]
    [[ "$output" != *"unknown option"* ]]
    [[ "$output" == *"Completed 1 iteration"* ]]
}

@test "review mode records metrics" {
    # Metrics need no schema change for review: the mode is tagged as its own
    # and plan_items_completed is always 0, because review never ticks a
    # checkbox — it only appends findings as new open items.
    "$RALPH" init
    printf -- '- [x] **Shipped task**\n  Spec: specs/mock.md item 1\n' >> IMPLEMENTATION_PLAN.md
    create_review_noop_backend

    seed_cycle_base
    PATH="$TEST_DIR/bin:$PATH" "$RALPH" review -y

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
    printf -- '- [x] **Shipped task**\n  Spec: specs/mock.md item 1\n' >> IMPLEMENTATION_PLAN.md
    create_review_noop_backend

    seed_cycle_base
    PATH="$TEST_DIR/bin:$PATH" "$RALPH" review --skip-push -y

    local line
    line=$(tail -1 "$(latest_metrics_file)")
    [[ $(jq -r '.mode' <<<"$line") == "review" ]]
    [[ $(jq -r '.git.noop' <<<"$line") == "true" ]]
}

@test "review fails when a pass un-ticks a shipped item" {
    # '[x]' records that the work was committed. Un-ticking hides that a defect
    # escaped and lets the item oscillate between '[ ]' and '[x]' across review
    # and build runs, so the loop stops instead of auditing a corrupted plan.
    "$RALPH" init
    printf -- '- [x] **Shipped one**\n  Spec: specs/mock.md item 1\n- [x] **Shipped two**\n  Spec: specs/mock.md item 1\n' >> IMPLEMENTATION_PLAN.md
    mkdir -p "$TEST_DIR/bin"
    cat > "$TEST_DIR/bin/claude" <<'MOCK'
#!/usr/bin/env bash
cat > /dev/null
sed -i '0,/^- \[x\] \*\*Shipped two\*\*$/s//- [ ] **Shipped two**/' IMPLEMENTATION_PLAN.md
echo '{"type":"result","result":"reviewing"}'
MOCK
    chmod +x "$TEST_DIR/bin/claude"

    seed_cycle_base
    PATH="$TEST_DIR/bin:$PATH" run "$RALPH" review --skip-push
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"review reduced the shipped item count from 2 to 1"* ]]
    [[ "$output" == *"Restore IMPLEMENTATION_PLAN.md"* ]]
    [[ "$output" != *"Completed"* ]]
}

@test "build writes .ralph/cycle-base as the repo_state listing" {
    # Review bounds the cycle's work by this base, so it must be the HEAD of
    # every repository before build's first commit (specs/one-shot-review.md §3).
    "$RALPH" init
    printf -- '- [ ] **Open task**\n  Spec: specs/mock.md item 1\n' >> IMPLEMENTATION_PLAN.md
    git init --quiet nested
    local head
    head=$(git rev-parse HEAD)
    create_review_noop_backend
    PATH="$TEST_DIR/bin:$PATH" run "$RALPH" build -n 1 --skip-push -y
    [[ "$status" -eq 0 ]]
    [[ "$(cat .ralph/cycle-base)" == ". $head"$'\n'"./nested -" ]]
}

@test "build keeps an existing .ralph/cycle-base" {
    # A second build in the same cycle must not move the base past the first
    # build's commits, or review would miss them.
    "$RALPH" init
    printf -- '- [ ] **Open task**\n  Spec: specs/mock.md item 1\n' >> IMPLEMENTATION_PLAN.md
    mkdir -p .ralph
    echo ". earlier" > .ralph/cycle-base
    create_review_noop_backend
    PATH="$TEST_DIR/bin:$PATH" run "$RALPH" build -n 1 --skip-push -y
    [[ "$status" -eq 0 ]]
    [[ "$(cat .ralph/cycle-base)" == ". earlier" ]]
}

@test "build --dry-run leaves .ralph/cycle-base absent" {
    "$RALPH" init
    printf -- '- [ ] **Open task**\n  Spec: specs/mock.md item 1\n' >> IMPLEMENTATION_PLAN.md
    run "$RALPH" build --dry-run -n 1
    [[ "$status" -eq 0 ]]
    [[ ! -e .ralph/cycle-base ]]
}

@test "archive moves .ralph/cycle-base into the timestamped directory" {
    # The base belongs to the cycle whose plan is archived with it (specs/one-shot-review.md §3).
    "$RALPH" init
    mkdir -p .ralph
    echo ". abc123" > .ralph/cycle-base
    run "$RALPH" archive
    [[ "$status" -eq 0 ]]
    [[ ! -e .ralph/cycle-base ]]
    local archive_dir
    archive_dir=$(find .ralph -mindepth 1 -maxdepth 1 -type d | head -1)
    [[ "$(cat "$archive_dir/cycle-base")" == ". abc123" ]]
    [[ "$output" == *"Archived: .ralph/cycle-base -> $archive_dir/cycle-base"* ]]
}

@test "clean deletes .ralph/cycle-base" {
    mkdir -p .ralph
    echo ". abc123" > .ralph/cycle-base
    run "$RALPH" clean
    [[ "$status" -eq 0 ]]
    [[ ! -e .ralph/cycle-base ]]
    [[ "$output" == *"Deleted: .ralph/cycle-base"* ]]
}
