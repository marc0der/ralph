bats_require_minimum_version 1.5.0

export RALPH="$BATS_TEST_DIRNAME/../ralph"

# Tests assert ralph's host-side behaviour (e.g. the outside-container warning).
# When tests run inside the devcontainer DEVCONTAINER=true leaks in and silently
# flips that branch — unset it so every test sees the same host-side defaults.
unset DEVCONTAINER

setup() {
    TEST_DIR="$(mktemp -d)"
    cd "$TEST_DIR" || return 1
    git init --quiet
    git config user.email "test@test.com"
    git config user.name "Test"
    git commit --allow-empty -m "initial" --quiet

    export RALPH_CONFIG_DIR="$TEST_DIR/.ralph-config"
    mkdir -p "$RALPH_CONFIG_DIR/templates" "$RALPH_CONFIG_DIR/prompts"
    echo "# Progress" > "$RALPH_CONFIG_DIR/templates/PROGRESS.md"
    # Use the real plan template, not a stub: it carries the '## Items' heading
    # and a column-zero exemplar entry, and item counting depends on both.
    cp "$BATS_TEST_DIRNAME/../templates/IMPLEMENTATION_PLAN.md" \
        "$RALPH_CONFIG_DIR/templates/IMPLEMENTATION_PLAN.md"
    echo "# Plan prompt" > "$RALPH_CONFIG_DIR/prompts/plan.md"
    echo "# Build prompt" > "$RALPH_CONFIG_DIR/prompts/build.md"
    echo "# Review prompt" > "$RALPH_CONFIG_DIR/prompts/review.md"
}

teardown() {
    rm -rf "$TEST_DIR"
}

create_gitignore() {
    printf "%s" "${1:-}" > .gitignore
}

# Helper: mock claude that streams JSONL events with controllable timing and
# exit code. The delays and the sentinel are what make live rendering
# observable: with MOCK_DELAY set the mock does not finish until well after its
# first event, and it announces its own finish by creating $MOCK_SENTINEL, so a
# test can prove a rendered line arrived before the backend exited.
# Knobs (all read at run time, so one mock serves every test):
#   MOCK_DELAY    seconds to sleep between events (default 0)
#   MOCK_SENTINEL path to touch just before exiting (default: none)
#   MOCK_EXIT     exit code (default 0)
create_streaming_backend() {
    mkdir -p "$TEST_DIR/bin"
    cat > "$TEST_DIR/bin/claude" <<'MOCK'
#!/usr/bin/env bash
cat > /dev/null
# Snapshot $TMPDIR from inside the iteration: the per-run stream file only
# exists while the backend runs, so a test cannot see it after the EXIT trap.
[[ -n "${MOCK_TMP_LISTING:-}" ]] && ls -A "${TMPDIR:-/tmp}" > "$MOCK_TMP_LISTING"
echo '{"type":"assistant","message":{"content":[{"type":"tool_use","id":"t1","name":"Bash","input":{"command":"ls -la"}}]}}'
sleep "${MOCK_DELAY:-0}"
echo '{"type":"assistant","message":{"content":[{"type":"text","text":"done here"}]}}'
sleep "${MOCK_DELAY:-0}"
# `result` carries the text too: the claude summary filter reads `.result`, so
# a result event without it renders a bare empty line on the non-verbose path.
echo '{"type":"result","subtype":"success","duration_ms":1234,"duration_api_ms":1000,"num_turns":3,"result":"done here","session_id":"s1","total_cost_usd":0.02,"usage":{"input_tokens":100,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":50}}'
[[ -n "${MOCK_SENTINEL:-}" ]] && : > "$MOCK_SENTINEL"
exit "${MOCK_EXIT:-0}"
MOCK
    chmod +x "$TEST_DIR/bin/claude"
}

# Helper: append one real open item to the plan. `ralph init` scaffolds a plan
# whose only column-zero entry is the exemplar under `## Entry Format`, and
# `plan_items_body` strips that, so an initialised workspace holds zero open
# items — and build hard-stops on a plan with no `- [ ]` line. Every build test
# that wants the loop to actually run must seed a real item first.
seed_open_item() {
    echo "- [ ] **Task**" >> IMPLEMENTATION_PLAN.md
}

# Helper: append one real shipped item to the plan. Review hard-stops unless the
# plan holds at least one `- [x]` item and no `- [ ]` item, so a review or
# lifecycle test that wants phase 5/6 to run must seed a shipped item.
seed_shipped_item() {
    echo "- [x] **Shipped task**" >> IMPLEMENTATION_PLAN.md
}

# Helper: phase-aware, committing mock backend. Unlike create_streaming_backend
# it can move the plan and HEAD, which a lifecycle test needs: build's noop exit
# watches HEAD, and plan/review converge on the plan's hash. It reads the prompt
# on stdin — the config dir gives each mode a distinct body (plan.md/build.md/
# review.md above) — and acts by mode:
#   plan   append one item on the first pass only, so the second pass converges
#   build  tick one open item and commit, moving HEAD
#   review append a finding unless MOCK_REVIEW_NOOP is set, else do nothing
# Knobs (read at run time):
#   MOCK_EXIT         exit code (default 0) — forces a phase to fail
#   MOCK_REVIEW_NOOP  when set, review files nothing (phase 6 then skips)
create_committing_backend() {
    mkdir -p "$TEST_DIR/bin"
    cat > "$TEST_DIR/bin/claude" <<'MOCK'
#!/usr/bin/env bash
prompt=$(cat)
plan=IMPLEMENTATION_PLAN.md
if echo "$prompt" | grep -qi 'plan prompt'; then
    grep -q 'mock-planned-item' "$plan" 2>/dev/null || \
        echo '- [ ] **mock-planned-item**' >> "$plan"
elif echo "$prompt" | grep -qi 'build prompt'; then
    # Tick the first open item, then commit so HEAD moves.
    if grep -q '^- \[ \]' "$plan" 2>/dev/null; then
        sed -i '0,/^- \[ \]/s//- [x]/' "$plan"
    fi
    echo "build $(date +%s%N)" >> mock-build-output.txt
    git add mock-build-output.txt
    git commit -q -m "mock build commit" >/dev/null 2>&1
elif echo "$prompt" | grep -qi 'review prompt'; then
    if [[ -z "${MOCK_REVIEW_NOOP:-}" ]]; then
        echo '- [ ] **mock-review-finding**' >> "$plan"
    fi
fi
echo '{"type":"assistant","message":{"content":[{"type":"text","text":"done here"}]}}'
echo '{"type":"result","subtype":"success","duration_ms":1,"duration_api_ms":1,"num_turns":1,"result":"done here","session_id":"s1","total_cost_usd":0.0,"usage":{"input_tokens":1,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":1}}'
exit "${MOCK_EXIT:-0}"
MOCK
    chmod +x "$TEST_DIR/bin/claude"
}
