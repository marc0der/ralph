bats_require_minimum_version 1.5.0

export RALPH="$BATS_TEST_DIRNAME/../ralph"

# Tests assert ralph's host-side behaviour (e.g. the outside-container warning).
# When tests run inside the devcontainer DEVCONTAINER=true leaks in and silently
# flips that branch — unset it so every test sees the same host-side defaults.
unset DEVCONTAINER

# Source ralph's functions without its main dispatch, as resolve_prompt.bats does.
ralph_fn() {
    (
        export RALPH_CONFIG_DIR
        eval "$(sed '/^# Main dispatch/,$d' "$RALPH")"
        "$@"
    )
}

setup() {
    # bats leaves stdin attached: ralph's `[[ -t 0 ]]` guard would prompt and block.
    exec </dev/null

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
    echo "# Retro prompt" > "$RALPH_CONFIG_DIR/prompts/retro.md"

    # A backend reached without a test mock is a test bug, not a real API call.
    # Built once per run, not per test: 4 files x 308 tests is measurable.
    GUARD_BIN="${BATS_RUN_TMPDIR:-$TEST_DIR}/guard-bin"
    if [[ ! -x "$GUARD_BIN/claude" ]]; then
        mkdir -p "$GUARD_BIN"
        local cli
        for cli in claude codex copilot pi; do
            printf '#!/usr/bin/env bash\necho "TEST BUG: %s reached an unmocked backend" >&2\nexit 99\n' "$cli" \
                > "$GUARD_BIN/$cli.tmp"
            chmod +x "$GUARD_BIN/$cli.tmp"
            mv "$GUARD_BIN/$cli.tmp" "$GUARD_BIN/$cli"
        done
    fi
    export PATH="$GUARD_BIN:$PATH"
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
# a result event without it renders a bare empty line on the --quiet path.
echo '{"type":"result","subtype":"success","duration_ms":1234,"duration_api_ms":1000,"num_turns":3,"result":"done here","session_id":"s1","total_cost_usd":0.02,"usage":{"input_tokens":100,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":50}}'
[[ -n "${MOCK_SENTINEL:-}" ]] && : > "$MOCK_SENTINEL"
exit "${exit_code:-${MOCK_EXIT:-0}}"
MOCK
    chmod +x "$TEST_DIR/bin/claude"
}

# Helper: shim `mkdir` to report success for a `*/metrics/*` path without creating it.
create_metrics_mkdir_shim() {
    mkdir -p "$TEST_DIR/bin"
    local real_mkdir
    real_mkdir=$(command -v mkdir)
    {
        printf '#!/usr/bin/env bash\nREAL_MKDIR=%q\n' "$real_mkdir"
        cat <<'MOCK'
for arg in "$@"; do
    case "$arg" in */metrics/*) exit 0 ;; esac
done
exec "$REAL_MKDIR" "$@"
MOCK
    } > "$TEST_DIR/bin/mkdir"
    chmod +x "$TEST_DIR/bin/mkdir"
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
    echo "  Spec: specs/mock.md item 1" >> IMPLEMENTATION_PLAN.md
}

# Helper: append one real entry to PROGRESS.md. Retro hard-stops unless the file
# holds a dated entry heading, and the template's exemplar heading never counts.
seed_progress_entry() {
    printf '### [2026-11-14 10:00] — Task\n\n**Summary:** Did a thing.\n' >> PROGRESS.md
}

# Helper: write a cycle base in repo_state format. Review hard-stops without
# .ralph/cycle-base, which build writes, so a review test that skips build seeds it.
seed_cycle_base() {
    mkdir -p .ralph
    printf '. %s\n' "$(git rev-parse -q --verify HEAD || echo -)" > .ralph/cycle-base
}

# Helper: add a bare repository as origin and leave HEAD on a fresh branch.
add_bare_origin() {
    git init --bare --quiet "$TEST_DIR/remote.git"
    git remote add origin "$TEST_DIR/remote.git"
    # A host's global pre-push hook can refuse a push of main or master.
    git checkout --quiet -b push-branch
}

# Helper: phase-aware, committing mock backend. Unlike create_streaming_backend
# it can move the plan and HEAD, which a lifecycle test needs: build's noop exit
# watches HEAD, and plan/review converge on the plan's hash. It reads the prompt
# on stdin — the config dir gives each mode a distinct body (plan.md/build.md/
# review.md above) — and acts by mode:
#   plan   append one item on the first pass only, so the second pass converges
#   build  append a dated PROGRESS.md entry, tick one open item and commit, moving HEAD
#   review append one finding on the first pass only, unless MOCK_REVIEW_NOOP
#   retro  change nothing, so the pass is idle
# Knobs (read at run time):
#   MOCK_EXIT         exit code (default 0) — forces a phase to fail
#   MOCK_REVIEW_NOOP  when set, review files nothing (phase 6 then skips)
#   MOCK_RETRO_EXIT   exit code of the retro pass only, overriding MOCK_EXIT
create_committing_backend() {
    mkdir -p "$TEST_DIR/bin"
    cat > "$TEST_DIR/bin/claude" <<'MOCK'
#!/usr/bin/env bash
prompt=$(cat)
plan=IMPLEMENTATION_PLAN.md
if echo "$prompt" | grep -qi 'plan prompt'; then
    grep -q 'mock-planned-item' "$plan" 2>/dev/null || \
        printf -- '- [ ] **mock-planned-item**\n  Spec: specs/mock.md item 1\n' >> "$plan"
elif echo "$prompt" | grep -qi 'build prompt'; then
    # Retro hard-stops without a dated entry, which init's template never holds.
    printf '### [2026-11-14 10:00] — Mock build\n\n**Summary:** Built.\n' >> PROGRESS.md
    # Tick the first open item, then commit so HEAD moves.
    if grep -q '^- \[ \]' "$plan" 2>/dev/null; then
        sed -i '0,/^- \[ \]/s//- [x]/' "$plan"
    fi
    echo "build $(date +%s%N)" >> mock-build-output.txt
    git add mock-build-output.txt
    git commit -q -m "mock build commit" >/dev/null 2>&1
elif echo "$prompt" | grep -qi 'review prompt'; then
    if [[ -z "${MOCK_REVIEW_NOOP:-}" ]]; then
        grep -q 'mock-review-finding' "$plan" 2>/dev/null || \
            echo '- [ ] **mock-review-finding**' >> "$plan"
    fi
elif echo "$prompt" | grep -qi 'retro prompt'; then
    exit_code="${MOCK_RETRO_EXIT:-}"
fi
echo '{"type":"assistant","message":{"content":[{"type":"text","text":"done here"}]}}'
echo '{"type":"result","subtype":"success","duration_ms":1,"duration_api_ms":1,"num_turns":1,"result":"done here","session_id":"s1","total_cost_usd":0.0,"usage":{"input_tokens":1,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":1}}'
exit "${exit_code:-${MOCK_EXIT:-0}}"
MOCK
    chmod +x "$TEST_DIR/bin/claude"
}

# Helper: build a PATH that hides a specific command. On NixOS and Ubuntu,
# coreutils share a directory, so hiding one command may hide others.
path_without() {
    local cmd="$1"
    echo "$PATH" | tr ':' '\n' | while read -r dir; do
        [[ -x "$dir/$cmd" ]] || printf "%s:" "$dir"
    done
}

# Helper: skip a test that parses a config file when mikefarah yq v4 is absent
# (specs/019-phase-config.md §13).
require_yq_or_skip() {
    local version_line
    version_line=$(yq --version 2>/dev/null) || skip "yq is not on PATH"
    [[ "$version_line" == *mikefarah* && "$version_line" =~ version\ v?4\. ]] \
        || skip "yq on PATH is not mikefarah yq v4: $version_line"
}

# Helper: put a yq on PATH that prints the given version line.
create_fake_yq() {
    mkdir -p "$TEST_DIR/bin"
    printf '#!/usr/bin/env bash\necho "%s"\n' "$1" > "$TEST_DIR/bin/yq"
    chmod +x "$TEST_DIR/bin/yq"
}

# Helper: print the LABEL row of the run card titled TITLE found in TEXT, spaces squeezed.
card_row() {
    local label="$1" text="$2" title="$3"
    awk -v label="$label" -v title="━━ ralph $title " '
        !inside { if (index($0, title) == 1) inside = 1; next }
        substr($0, 1, 1) == "━" { exit }
        substr($0, 3, length(label) + 1) == label ":" {
            gsub(/ +/, " "); sub(/^ /, ""); print; exit
        }' <<< "$text"
}

# Helper: run a command with stdin, stdout and stderr on a pseudo-terminal, as `run` does.
# Sets $status and $output, with the terminal's carriage returns removed.
run_on_tty() {
    [[ "$(script --version 2>/dev/null)" == *util-linux* ]] \
        || skip "script from util-linux is not on PATH"
    script -qefc true /dev/null > /dev/null 2>&1 \
        || skip "script cannot open a pseudo-terminal"
    local wrapper="$BATS_TEST_TMPDIR/tty-wrapper.sh"
    printf '#!/usr/bin/env bash\ncd %q || exit 1\nexec' "$PWD" > "$wrapper"
    printf ' %q' "$@" >> "$wrapper"
    printf '\n' >> "$wrapper"
    chmod +x "$wrapper"
    run script -qefc "$wrapper" /dev/null
    output=${output//$'\r'/}
}

card_line_widths() {
    local LC_ALL=C line char
    while IFS= read -r line; do
        line=$(printf '%s' "$line" | sed $'s/\e\\[[0-9;]*m//g')
        case $line in
            "━"* | "─"* | "▶"* | "  "*) ;;
            *) continue ;;
        esac
        for char in ─ ━ … ▶ ·; do
            line=${line//"$char"/x}
        done
        echo "${#line}"
    done
}
