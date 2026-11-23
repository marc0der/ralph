#!/usr/bin/env bats

load test_helper

@test "card_style off a terminal sets width 120 and empty codes" {
    run ralph_fn eval "CARD_DIM=x CARD_BOLD=x CARD_LABEL=x CARD_OFF=x CARD_WIDTH=7
        COLUMNS=60 TERM=xterm card_style 1
        printf '%s|%s|%s|%s|%s' \"\$CARD_WIDTH\" \"\$CARD_DIM\" \"\$CARD_BOLD\" \"\$CARD_LABEL\" \"\$CARD_OFF\""
    [ "$status" -eq 0 ]
    [ "$output" = "120||||" ]
}

@test "card_style ignores COLUMNS off a terminal" {
    run ralph_fn eval "COLUMNS=60 card_style 2; printf '%s' \"\$CARD_WIDTH\""
    [ "$status" -eq 0 ]
    [ "$output" = "120" ]
}

@test "card_fit cuts 130 characters to 119 and an ellipsis" {
    run ralph_fn eval "LC_ALL=C card_style 1
        text=\$(printf 'a%.0s' {1..130})
        LC_ALL=C card_fit \"\$text\""
    [ "$status" -eq 0 ]
    [ "$output" = "$(printf 'a%.0s' {1..119})…" ]
}

@test "card_fit keeps a line of exactly 120 characters" {
    run ralph_fn eval "LC_ALL=C card_style 1
        text=\$(printf 'b%.0s' {1..120})
        LC_ALL=C card_fit \"\$text\""
    [ "$status" -eq 0 ]
    [ "$output" = "$(printf 'b%.0s' {1..120})" ]
}

@test "card_fit counts a multibyte character as one under LC_ALL=C" {
    run ralph_fn eval "LC_ALL=C card_style 1
        text=\$(printf '─%.0s' {1..125})
        LC_ALL=C card_fit \"\$text\""
    [ "$status" -eq 0 ]
    [ "$output" = "$(printf '─%.0s' {1..119})…" ]
}

@test "card_fit follows CARD_WIDTH" {
    run ralph_fn eval "CARD_LOCALE=C.UTF-8 CARD_WIDTH=10; card_fit abcdefghijklmnop"
    [ "$status" -eq 0 ]
    [ "$output" = "abcdefghi…" ]
}

@test "card_style sets CARD_LOCALE to a UTF-8 locale" {
    run ralph_fn eval "LC_ALL=C card_style 1; printf '%s' \"\$CARD_LOCALE\""
    [ "$status" -eq 0 ]
    [[ "$output" == *UTF-8 ]]
}

@test "card_style prints nothing on stderr while probing locales" {
    run --separate-stderr ralph_fn eval "LC_ALL=C card_style 1"
    [ "$status" -eq 0 ]
    [ -z "$stderr" ]
}

@test "truncate_line keeps the three-dot default ellipsis" {
    run ralph_fn truncate_line abcdefghij 6
    [ "$output" = "abc..." ]
}

@test "card_rule pads a short text to 120 characters" {
    run ralph_fn eval "LC_ALL=C card_style 1; LC_ALL=C card_rule ─ '── 1/3 ── claude'"
    [ "$status" -eq 0 ]
    [ "$output" = "── 1/3 ── claude $(printf '─%.0s' {1..103})" ]
    [ "$(printf '%s' "$output" | LC_ALL=C.UTF-8 wc -m)" -eq 120 ]
}

@test "card_rule prints the rule character alone for an empty text" {
    run ralph_fn eval "LC_ALL=C card_style 1; LC_ALL=C card_rule ━ ''"
    [ "$status" -eq 0 ]
    [ "$output" = "$(printf '━%.0s' {1..120})" ]
}

@test "card_rule follows CARD_WIDTH and ends in a space and two rule characters at the limit" {
    run ralph_fn eval "CARD_LOCALE=C.UTF-8 CARD_WIDTH=10; card_rule - abcdefg"
    [ "$status" -eq 0 ]
    [ "$output" = "abcdefg --" ]
}

@test "card_rule cuts a text that leaves no room for two rule characters" {
    run ralph_fn eval "CARD_LOCALE=C.UTF-8 CARD_WIDTH=10; card_rule - abcdefgh"
    [ "$status" -eq 0 ]
    [ "$output" = "abcdefgh …" ]
}

@test "card_rule cuts a text longer than the width" {
    run ralph_fn eval "LC_ALL=C card_style 1; LC_ALL=C card_rule ─ \"\$(printf 'x%.0s' {1..130})\""
    [ "$status" -eq 0 ]
    [ "$output" = "$(printf 'x%.0s' {1..119})…" ]
}

@test "card_rule wraps the line in the dim and off codes" {
    run ralph_fn eval "CARD_LOCALE=C.UTF-8 CARD_WIDTH=6 CARD_DIM='<d>' CARD_OFF='<o>'; card_rule - ab"
    [ "$status" -eq 0 ]
    [ "$output" = "<d>ab ---<o>" ]
}

@test "print_card_rows aligns labels and values in columns" {
    S=$'\x1f'
    run ralph_fn eval "CARD_LOCALE=C.UTF-8 CARD_WIDTH=120
        print_card_rows 'backend${S}claude${S}model${S}opus' 'iterations${S}auto(2)${S}headroom${S}20%' 'config${S}./ralph.yaml (local) [build]'"
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "  backend     claude   model     opus" ]
    [ "${lines[1]}" = "  iterations  auto(2)  headroom  20%" ]
    [ "${lines[2]}" = "  config      ./ralph.yaml (local) [build]" ]
    [ "${#lines[@]}" -eq 3 ]
}

@test "print_card_rows splits a row past the width into one row per pair" {
    S=$'\x1f'
    run ralph_fn eval "CARD_LOCALE=C.UTF-8 CARD_WIDTH=30
        print_card_rows 'backend${S}claude${S}model${S}opus' 'iterations${S}auto(2)${S}headroom${S}20%'"
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "  backend     claude" ]
    [ "${lines[1]}" = "  model       opus" ]
    [ "${lines[2]}" = "  iterations  auto(2)" ]
    [ "${lines[3]}" = "  headroom    20%" ]
    [ "${#lines[@]}" -eq 4 ]
}

@test "print_card_rows splits only the rows that pass the width" {
    S=$'\x1f'
    run ralph_fn eval "CARD_LOCALE=C.UTF-8 CARD_WIDTH=20
        print_card_rows 'a${S}1${S}b${S}long-value-xx' 'a${S}1${S}b${S}2'"
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "  a  1" ]
    [ "${lines[1]}" = "  b  long-value-xx" ]
    [ "${lines[2]}" = "  a  1  b  2" ]
    [ "${#lines[@]}" -eq 3 ]
}

@test "print_card_rows cuts a row that still passes the width, uncoloured" {
    S=$'\x1f'
    run ralph_fn eval "CARD_LOCALE=C.UTF-8 CARD_WIDTH=10 CARD_LABEL='<l>' CARD_OFF='<o>'
        print_card_rows 'ab${S}abcdefghij'"
    [ "$status" -eq 0 ]
    [ "$output" = "  ab  abc…" ]
}

@test "print_card_rows wraps labels in the label and off codes" {
    S=$'\x1f'
    run ralph_fn eval "CARD_LOCALE=C.UTF-8 CARD_WIDTH=40 CARD_LABEL='<l>' CARD_OFF='<o>'
        print_card_rows 'ab${S}cd${S}ef${S}gh'"
    [ "$status" -eq 0 ]
    [ "$output" = "  <l>ab<o>  cd  <l>ef<o>  gh" ]
}

@test "print_card_rows keeps an empty label cell and a trailing empty value" {
    S=$'\x1f'
    run ralph_fn eval "CARD_LOCALE=C.UTF-8 CARD_WIDTH=40
        print_card_rows 'metrics${S}on${S}${S}file.jsonl' 'quiet${S}'"
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "  metrics  on    file.jsonl" ]
    [ "${lines[1]}" = "  quiet    " ]
}

@test "run card prints once per dry run between a titled top rule and a full bottom rule" {
    "$RALPH" init
    seed_open_item
    run --separate-stderr "$RALPH" build --dry-run
    [ "$status" -eq 0 ]
    [ "$(grep -c '^━━ ralph build ━' <<< "$stderr")" -eq 1 ]
    [ "$(grep '^━━ ralph build ━' <<< "$stderr" | wc -m)" -eq 121 ]
    [ "$(grep -c '^━\{120\}$' <<< "$stderr")" -eq 1 ]
}

@test "run card prints the backend row with model and effort" {
    "$RALPH" init
    seed_open_item
    run --separate-stderr "$RALPH" build --dry-run
    [ "$status" -eq 0 ]
    [ "$(card_row backend "$stderr" build)" = "backend claude model opus effort default" ]
    run --separate-stderr "$RALPH" build --dry-run -e high
    [ "$(card_row backend "$stderr" build)" = "backend claude model opus effort high" ]
}

@test "run card prints under --quiet and names the quiet row" {
    "$RALPH" init
    seed_open_item
    run --separate-stderr "$RALPH" build --dry-run
    [ "$(card_row quiet "$stderr" build)" = "quiet off" ]
    run --separate-stderr "$RALPH" build --dry-run -q
    [ "$status" -eq 0 ]
    [ "$(card_row quiet "$stderr" build)" = "quiet on" ]
}

@test "run card prints the branch and prompt rows" {
    "$RALPH" init
    seed_open_item
    run --separate-stderr "$RALPH" build --dry-run
    [ "$status" -eq 0 ]
    [ "$(card_row branch "$stderr" build)" = "branch $(git branch --show-current)" ]
    [ "$(card_row prompt "$stderr" build)" = "prompt $RALPH_CONFIG_DIR/prompts/build.md" ]
}

@test "run card titles a fix run with its section" {
    "$RALPH" init
    seed_open_item
    run --separate-stderr "$RALPH" fix --dry-run
    [ "$status" -eq 0 ]
    [ "$(card_row backend "$stderr" fix)" = "backend claude model opus effort default" ]
}

@test "run card names the built-in config source with its section" {
    "$RALPH" init
    seed_open_item
    run --separate-stderr "$RALPH" build --dry-run
    [ "$(card_row config "$stderr" build)" = "config built-in (no config file) [build]" ]
}

@test "run card names the local and central config sources with their section" {
    require_yq_or_skip
    "$RALPH" init
    seed_open_item
    printf 'build:\n  effort: high\n' > "$RALPH_CONFIG_DIR/config.yaml"
    run --separate-stderr "$RALPH" build --dry-run
    [ "$status" -eq 0 ]
    [ "$(card_row config "$stderr" build)" = "config $RALPH_CONFIG_DIR/config.yaml (central) [build]" ]
    printf 'build:\n  quiet: true\n' > ralph.yaml
    run --separate-stderr "$RALPH" build --dry-run
    [ "$status" -eq 0 ]
    [ "$(card_row config "$stderr" build)" = "config ./ralph.yaml (local) [build]" ]
    [ "$(card_row quiet "$stderr" build)" = "quiet on" ]
}

@test "run card prints the iterations row with the build tuning cells" {
    "$RALPH" init
    seed_open_item
    run --separate-stderr "$RALPH" build --dry-run
    [ "$status" -eq 0 ]
    [ "$(card_row iterations "$stderr" build)" = "iterations auto(2) headroom 20% patience 2 push on" ]
}

@test "run card prints a fixed iteration count without auto and with push off" {
    "$RALPH" init
    seed_open_item
    run --separate-stderr "$RALPH" build --dry-run -n 3 --skip-push
    [ "$status" -eq 0 ]
    [ "$(card_row iterations "$stderr" build)" = "iterations 3 headroom 20% patience 2 push off" ]
}

@test "run card prints the build tuning cells in fix" {
    "$RALPH" init
    seed_open_item
    run --separate-stderr "$RALPH" fix --dry-run
    [ "$status" -eq 0 ]
    [ "$(card_row iterations "$stderr" fix)" = "iterations auto(2) headroom 20% patience 2 push on" ]
}

@test "run card prints no tuning cells in plan, review and retro" {
    "$RALPH" init
    run --separate-stderr "$RALPH" plan --dry-run -g "A goal"
    [ "$status" -eq 0 ]
    [ "$(card_row iterations "$stderr" plan)" = "iterations 6" ]
    seed_shipped_item
    seed_cycle_base
    run --separate-stderr "$RALPH" review --dry-run
    [ "$status" -eq 0 ]
    [ "$(card_row iterations "$stderr" review)" = "iterations 1" ]
    seed_progress_entry
    run --separate-stderr "$RALPH" retro --dry-run
    [ "$status" -eq 0 ]
    [ "$(card_row iterations "$stderr" retro)" = "iterations 1" ]
}

@test "run card prints metrics off in a dry run" {
    "$RALPH" init
    seed_open_item
    run --separate-stderr "$RALPH" build --dry-run
    [ "$status" -eq 0 ]
    [ "$(card_row metrics "$stderr" build)" = "metrics off (dry-run)" ]
}

@test "run card prints metrics on with the metrics file" {
    create_streaming_backend
    "$RALPH" init
    seed_open_item
    PATH="$TEST_DIR/bin:$PATH" run --separate-stderr "$RALPH" build -n 1 --skip-push
    [ "$status" -eq 0 ]
    [[ "$(card_row metrics "$stderr" build)" == "metrics on .ralph/metrics/"*"/metrics.jsonl" ]]
}

@test "run card prints metrics off under --no-metrics" {
    create_streaming_backend
    "$RALPH" init
    seed_open_item
    PATH="$TEST_DIR/bin:$PATH" run --separate-stderr "$RALPH" build -n 1 --skip-push --no-metrics
    [ "$status" -eq 0 ]
    [ "$(card_row metrics "$stderr" build)" = "metrics off" ]
}

@test "run card prints the extra args row only when the section sets extra_args" {
    require_yq_or_skip
    "$RALPH" init
    seed_open_item
    run --separate-stderr "$RALPH" build --dry-run
    [ "$status" -eq 0 ]
    [ -z "$(card_row 'extra args' "$stderr" build)" ]
    printf 'build:\n  extra_args: [--foo, bar]\n' > ralph.yaml
    run --separate-stderr "$RALPH" build --dry-run
    [ "$status" -eq 0 ]
    [ "$(card_row 'extra args' "$stderr" build)" = "extra args --foo bar" ]
}

@test "run card leaves out extra args that -b drops" {
    require_yq_or_skip
    "$RALPH" init
    seed_open_item
    printf 'build:\n  extra_args: [--foo]\n' > ralph.yaml
    run --separate-stderr "$RALPH" build --dry-run -b pi
    [ "$status" -eq 0 ]
    [ -z "$(card_row 'extra args' "$stderr" build)" ]
}

@test "card_row returns the row of the named card only" {
    text=$'━━ ralph plan ━━\n  quiet  off\n━━━━\n━━ ralph build ━━\n  quiet  on\n━━━━'
    run card_row quiet "$text" build
    [ "$output" = "quiet on" ]
    run card_row quiet "$text" plan
    [ "$output" = "quiet off" ]
    run card_row branch "$text" build
    [ -z "$output" ]
}

@test "a dry-run build prints no Mode line and no rule on stdout" {
    "$RALPH" init
    seed_open_item
    run --separate-stderr "$RALPH" build --dry-run
    [ "$status" -eq 0 ]
    [[ "$output" != *"Mode:"* ]]
    [[ "$output" != *"━"* ]]
}

@test "clock_hhmm prints the local time of epoch 0" {
    TZ=UTC run ralph_fn clock_hhmm 0
    [ "$status" -eq 0 ]
    [ "$output" = "00:00" ]
}

@test "clock_hhmm prints the local time of epoch 3660" {
    TZ=UTC run ralph_fn clock_hhmm 3660
    [ "$status" -eq 0 ]
    [ "$output" = "01:01" ]
}

@test "divider counts 1/3, 2/3 and 3/3 across a three-iteration run" {
    "$RALPH" init
    seed_open_item
    run --separate-stderr "$RALPH" build --dry-run -n 3
    [ "$status" -eq 0 ]
    [[ "$output" == *$'\n── 1/3 ── '* ]]
    [[ "$output" == *$'\n── 2/3 ── '* ]]
    [[ "$output" == *$'\n── 3/3 ── '* ]]
    [[ "$output" != *"ITERATION"* ]]
}

@test "divider names backend, model and effort, 0s elapsed and the clock time" {
    "$RALPH" init
    seed_open_item
    run --separate-stderr "$RALPH" build --dry-run -n 1 -m opus -e high
    [ "$status" -eq 0 ]
    divider=$(grep '^── 1/1 ── ' <<< "$output")
    [[ "$divider" =~ ^──\ 1/1\ ──\ claude\ ·\ opus\ ·\ high\ ──\ 0s\ ──\ [0-9]{2}:[0-9]{2}\ ─+$ ]]
}

@test "divider prints default for an unset effort" {
    "$RALPH" init
    seed_open_item
    run --separate-stderr "$RALPH" build --dry-run -n 1 -m opus
    [ "$status" -eq 0 ]
    [[ "$output" == *"── 1/1 ── claude · opus · default ── 0s ── "* ]]
}

@test "divider follows a blank line and is 120 wide off a terminal" {
    "$RALPH" init
    seed_open_item
    "$RALPH" build --dry-run -n 1 > out.txt 2> /dev/null
    [ -z "$(sed -n 1p out.txt)" ]
    [[ "$(sed -n 2p out.txt)" == "── 1/1 ── "* ]]
    [ "$(sed -n 2p out.txt | wc -m)" -eq 121 ]
}

@test "divider shows a nonzero elapsed time on a later iteration" {
    "$RALPH" init
    seed_open_item
    create_streaming_backend
    MOCK_DELAY=1 PATH="$TEST_DIR/bin:$PATH" run --separate-stderr "$RALPH" build -n 2 --skip-push --no-metrics
    [ "$status" -eq 0 ]
    [[ "$output" == *"── 1/2 ── "*" · "*" ── 0s ── "* ]]
    [[ "$output" =~ "── 2/2 ── "[^$'\n']*" ── "([2-9]|[0-9]{2,})"s ── " ]]
}

@test "headline names the first open item without bold markers" {
    "$RALPH" init
    printf -- '- [ ] **First task**\n- [ ] **Second task**\n' >> IMPLEMENTATION_PLAN.md
    run --separate-stderr "$RALPH" build --dry-run -n 1
    [ "$status" -eq 0 ]
    [[ "$output" == *$'\n▶ next: First task\n'* ]]
    [[ "$output" != *"**"* ]]
}

@test "headline keeps bold markers inside the title" {
    "$RALPH" init
    printf -- '- [ ] **Ignore **/tmp paths**\n' >> IMPLEMENTATION_PLAN.md
    run --separate-stderr "$RALPH" build --dry-run -n 1
    [ "$status" -eq 0 ]
    [[ "$output" == *$'\n▶ next: Ignore **/tmp paths\n'* ]]
}

@test "headline never takes its title from the exemplar entry" {
    "$RALPH" init
    printf -- '- [ ] **Real task**\n' >> IMPLEMENTATION_PLAN.md
    run --separate-stderr "$RALPH" build --dry-run -n 1
    [ "$status" -eq 0 ]
    [[ "$output" == *"▶ next: Real task"* ]]
    [[ "$output" != *"Short imperative title"* ]]
}

@test "headline names the second item once the agent ticks the first" {
    "$RALPH" init
    printf -- '# Implementation Plan\n\n## Items\n\n- [ ] **First task**\n- [ ] **Second task**\n' > IMPLEMENTATION_PLAN.md
    create_committing_backend
    PATH="$TEST_DIR/bin:$PATH" run --separate-stderr "$RALPH" build -n 2 --skip-push --no-metrics
    [ "$status" -eq 0 ]
    [[ "$output" == *"── 1/2 ── "*$'\n▶ next: First task\n'* ]]
    [[ "$output" == *"── 2/2 ── "*$'\n▶ next: Second task\n'* ]]
}

@test "headline says no open item when the plan holds none at the iteration start" {
    "$RALPH" init
    printf -- '# Implementation Plan\n\n## Items\n\n- [ ] **Only task**\n' > IMPLEMENTATION_PLAN.md
    create_committing_backend
    PATH="$TEST_DIR/bin:$PATH" run --separate-stderr "$RALPH" build -n 2 --skip-push --no-metrics
    [ "$status" -eq 0 ]
    [[ "$output" == *"── 2/2 ── "*$'\n▶ next: no open item\n'* ]]
}

@test "headline says no open item and prints no cat error for a deleted plan" {
    "$RALPH" init
    printf -- '# Implementation Plan\n\n## Items\n\n- [ ] **Only task**\n' > IMPLEMENTATION_PLAN.md
    mkdir -p "$TEST_DIR/bin"
    cat > "$TEST_DIR/bin/claude" <<'MOCK'
#!/usr/bin/env bash
cat > /dev/null
rm -f IMPLEMENTATION_PLAN.md
echo '{"type":"result","subtype":"success","result":"done","usage":{"input_tokens":1,"output_tokens":1}}'
MOCK
    chmod +x "$TEST_DIR/bin/claude"
    PATH="$TEST_DIR/bin:$PATH" run --separate-stderr "$RALPH" build -n 2 --skip-push --no-metrics
    [[ "$output" == *"── 2/2 ── "*$'\n▶ next: no open item\n'* ]]
    [[ "$stderr" != *"cat:"* ]]
}

@test "headline prints under --quiet" {
    "$RALPH" init
    seed_open_item
    run --separate-stderr "$RALPH" build --dry-run --quiet -n 1
    [ "$status" -eq 0 ]
    [[ "$output" == *"▶ next: Task"* ]]
}

@test "headline is cut to the card width with an ellipsis" {
    "$RALPH" init
    printf -- '- [ ] **%s**\n' "$(printf 'w%.0s' {1..150})" >> IMPLEMENTATION_PLAN.md
    "$RALPH" build --dry-run -n 1 > out.txt 2> /dev/null
    line=$(grep '^▶ next: ' out.txt)
    [ "${#line}" -eq 120 ]
    [[ "$line" == *"…" ]]
}

@test "headline in plan names the goal" {
    "$RALPH" init
    run --separate-stderr "$RALPH" plan --dry-run -n 1 -g "Add REST endpoint"
    [ "$status" -eq 0 ]
    [[ "$output" == *$'\n▶ goal: Add REST endpoint\n'* ]]
}

@test "headline in plan folds a goal with a newline into one line" {
    "$RALPH" init
    run --separate-stderr "$RALPH" plan --dry-run -n 1 -g $'a\nb'
    [ "$status" -eq 0 ]
    [[ "$output" == *$'\n▶ goal: a b\n'* ]]
}

@test "headline in plan squeezes each whitespace run to one space" {
    "$RALPH" init
    run --separate-stderr "$RALPH" plan --dry-run -n 1 -g $'a  \t\n\n b'
    [ "$status" -eq 0 ]
    [[ "$output" == *$'\n▶ goal: a b\n'* ]]
}

@test "headline in plan is cut to the card width with an ellipsis" {
    "$RALPH" init
    "$RALPH" plan --dry-run -n 1 -g "$(printf 'g%.0s' {1..150})" > out.txt 2> /dev/null
    line=$(grep '^▶ goal: ' out.txt)
    [ "${#line}" -eq 120 ]
    [[ "$line" == *"…" ]]
}

@test "headline in review counts shipped items and cited specs" {
    "$RALPH" init
    printf -- '- [x] **One**\n  Spec: specs/a.md item 1\n- [x] **Two**\n  Spec: specs/a.md item 2\n- [x] **Three**\n  Spec: specs/b.md §1\n' >> IMPLEMENTATION_PLAN.md
    seed_cycle_base
    run --separate-stderr "$RALPH" review --dry-run
    [ "$status" -eq 0 ]
    [[ "$output" == *$'\n▶ reviewing 3 shipped items against 2 cited specs\n'* ]]
}

@test "headline in review uses the singular for one item and one spec" {
    "$RALPH" init
    seed_shipped_item
    seed_cycle_base
    run --separate-stderr "$RALPH" review --dry-run
    [ "$status" -eq 0 ]
    [[ "$output" == *$'\n▶ reviewing 1 shipped item against 1 cited spec\n'* ]]
}

@test "headline in review says no cited specs for an empty anchor set" {
    "$RALPH" init
    printf -- '- [x] **Gate**\n  Spec: CLAUDE.md verification gate\n' >> IMPLEMENTATION_PLAN.md
    seed_cycle_base
    run --separate-stderr "$RALPH" review --dry-run
    [ "$status" -eq 0 ]
    [[ "$output" == *$'\n▶ reviewing 1 shipped item against no cited specs\n'* ]]
}

@test "headline in retro counts entries and learnings on file" {
    "$RALPH" init
    seed_progress_entry
    seed_progress_entry
    mkdir -p .ralph
    printf '# Learnings\n\n## Tooling\n- One (confirmed 2026-11-14)\n- Two (confirmed 2026-11-14)\n\n## Codebase\n- Three (confirmed 2026-11-14)\n' > .ralph/learnings.md
    run --separate-stderr "$RALPH" retro --dry-run
    [ "$status" -eq 0 ]
    [[ "$output" == *$'\n▶ distilling 2 PROGRESS.md entries · 3 learnings on file\n'* ]]
}

@test "headline in retro uses the singular for one entry and one learning" {
    "$RALPH" init
    seed_progress_entry
    mkdir -p .ralph
    printf '# Learnings\n\n## Tooling\n- One (confirmed 2026-11-14)\n' > .ralph/learnings.md
    run --separate-stderr "$RALPH" retro --dry-run
    [ "$status" -eq 0 ]
    [[ "$output" == *$'\n▶ distilling 1 PROGRESS.md entry · 1 learning on file\n'* ]]
}

@test "headline in retro says 0 learnings without a learnings file" {
    "$RALPH" init
    seed_progress_entry
    seed_progress_entry
    run --separate-stderr "$RALPH" retro --dry-run
    [ "$status" -eq 0 ]
    [[ "$output" == *$'\n▶ distilling 2 PROGRESS.md entries · 0 learnings on file\n'* ]]
}

@test "review keeps its Review filed line on the shared spec count" {
    "$RALPH" init
    seed_shipped_item
    seed_cycle_base
    create_streaming_backend
    PATH="$TEST_DIR/bin:$PATH" run --separate-stderr "$RALPH" review --skip-push --no-metrics
    [ "$status" -eq 0 ]
    [[ "$output" == *"Review filed 0 findings. Reviewed 1 specs and "* ]]
}

@test "footer holds the metric figures with metrics on" {
    "$RALPH" init
    seed_open_item
    create_streaming_backend
    PATH="$TEST_DIR/bin:$PATH" run --separate-stderr "$RALPH" build -n 1 --skip-push
    [ "$status" -eq 0 ]
    [[ "$output" == *$'\n── 1/1 done ── '[0-9]*"s wall · 1s api · 3 turns · \$0.02 · 0 commits (+0/-0) · Bash 1 ──"* ]]
    [[ "$output" != *"Metrics: "* ]]
}

@test "footer is one line of exactly 120 characters" {
    "$RALPH" init
    seed_open_item
    create_streaming_backend
    PATH="$TEST_DIR/bin:$PATH" "$RALPH" build -n 1 --skip-push > out.txt 2> /dev/null
    line=$(grep '^── 1/1 done ── ' out.txt)
    [ "${#line}" -eq 120 ]
    [ "$(grep -c 'done ──' out.txt)" -eq 1 ]
}

@test "footer holds the wall time only with --no-metrics" {
    "$RALPH" init
    seed_open_item
    create_streaming_backend
    PATH="$TEST_DIR/bin:$PATH" run --separate-stderr "$RALPH" build -n 1 --skip-push --no-metrics
    [ "$status" -eq 0 ]
    [[ "$output" =~ $'\n── 1/1 done ── '[0-9]+'s wall ──' ]]
    [[ "$output" != *" api"* ]]
}

@test "footer prints under --quiet" {
    "$RALPH" init
    seed_open_item
    create_streaming_backend
    PATH="$TEST_DIR/bin:$PATH" run --separate-stderr "$RALPH" build -n 1 --skip-push --no-metrics --quiet
    [ "$status" -eq 0 ]
    [[ "$output" == *$'\n── 1/1 done ── '* ]]
}

@test "footer closes every iteration of a two-iteration run" {
    "$RALPH" init
    seed_open_item
    create_streaming_backend
    PATH="$TEST_DIR/bin:$PATH" run --separate-stderr "$RALPH" build -n 2 --skip-push --no-metrics
    [ "$status" -eq 0 ]
    [[ "$output" == *$'\n── 1/2 done ── '*$'\n── 2/2 done ── '* ]]
}

@test "footer is absent from a failed iteration" {
    "$RALPH" init
    seed_open_item
    create_streaming_backend
    MOCK_EXIT=3 PATH="$TEST_DIR/bin:$PATH" run --separate-stderr "$RALPH" build -n 1 --skip-push
    [ "$status" -eq 3 ]
    [[ "$output" != *" done ── "* ]]
}

@test "footer is absent from a dry-run iteration" {
    "$RALPH" init
    seed_open_item
    run --separate-stderr "$RALPH" build --dry-run -n 1
    [ "$status" -eq 0 ]
    [[ "$output" != *" done ── "* ]]
}

@test "footer is absent when the push fails" {
    "$RALPH" init
    seed_open_item
    git remote add origin "$TEST_DIR/missing.git"
    git commit -q --allow-empty -m init
    create_streaming_backend
    PATH="$TEST_DIR/bin:$PATH" run --separate-stderr "$RALPH" build -n 1 --no-metrics
    [ "$status" -eq 1 ]
    [[ "$output" != *" done ── "* ]]
}

@test "footer holds the wall time only when the metrics record is not written" {
    "$RALPH" init
    seed_open_item
    create_streaming_backend
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
    PATH="$TEST_DIR/bin:$PATH" run --separate-stderr "$RALPH" build -n 1 --skip-push
    [ "$status" -eq 0 ]
    [[ "$stderr" == *"metrics capture failed for iteration 1"* ]]
    [[ "$output" =~ $'\n── 1/1 done ── '[0-9]+'s wall ──' ]]
    [[ "$output" != *" api"* ]]
}

@test "footer wall time grows with a slow backend" {
    "$RALPH" init
    seed_open_item
    create_streaming_backend
    MOCK_DELAY=1 PATH="$TEST_DIR/bin:$PATH" run --separate-stderr "$RALPH" build -n 1 --skip-push --no-metrics
    [ "$status" -eq 0 ]
    [[ "$output" =~ $'\n── 1/1 done ── '([2-9]|[0-9]{2,})'s wall ──' ]]
}

# A mock claude whose tool names ($1 tools of $2 characters) widen the footer.
create_wide_tool_backend() {
    local count="$1" length="$2"
    create_streaming_backend
    cat > "$TEST_DIR/bin/claude" <<'MOCK'
#!/usr/bin/env bash
cat > /dev/null
for i in $(seq 1 COUNT); do
    name=$(printf "Tool%0LENGTHd" "$i")
    echo '{"type":"assistant","message":{"content":[{"type":"tool_use","id":"t'"$i"'","name":"'"$name"'","input":{}}]}}'
done
echo '{"type":"result","subtype":"success","duration_ms":1234,"duration_api_ms":1000,"num_turns":3,"result":"done here","session_id":"s1","total_cost_usd":0.02,"usage":{"input_tokens":100,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":50}}'
MOCK
    sed -i "s/COUNT/$count/; s/LENGTH/$length/" "$TEST_DIR/bin/claude"
}

@test "footer keeps a tool list that fits the width" {
    "$RALPH" init
    seed_open_item
    create_wide_tool_backend 2 4
    PATH="$TEST_DIR/bin:$PATH" "$RALPH" build -n 1 --skip-push > out.txt 2> /dev/null
    line=$(grep '^── 1/1 done ── ' out.txt)
    [[ "$line" == *" commits (+0/-0) · Tool0001 1, Tool0002 1 ──"* ]]
}

@test "footer drops a tool list that passes the width" {
    "$RALPH" init
    seed_open_item
    create_wide_tool_backend 6 12
    PATH="$TEST_DIR/bin:$PATH" "$RALPH" build -n 1 --skip-push > out.txt 2> /dev/null
    line=$(grep '^── 1/1 done ── ' out.txt)
    [ "${#line}" -eq 120 ]
    [[ "$line" == *" commits (+0/-0) ──"* ]]
    [[ "$line" != *Tool* ]]
}

@test "terminal divider holds an escape code with colour allowed" {
    "$RALPH" init
    seed_open_item
    NO_COLOR='' TERM=xterm run_on_tty "$RALPH" build --dry-run -n 1 -y
    [ "$status" -eq 0 ]
    [[ "$output" == *$'\e[2m── 1/1 ── claude'* ]]
}

@test "terminal run off a terminal prints no escape code on either stream" {
    create_streaming_backend
    "$RALPH" init
    seed_open_item
    NO_COLOR='' TERM=xterm PATH="$TEST_DIR/bin:$PATH" run --separate-stderr "$RALPH" build -n 1 --skip-push
    [ "$status" -eq 0 ]
    [[ "$output" == *"── 1/1 ── "* ]]
    [[ "$output" != *$'\e'* ]]
    [[ "$stderr" == *"━━ ralph build"* ]]
    [[ "$stderr" != *$'\e'* ]]
}

@test "terminal NO_COLOR=1 leaves no escape code on either stream" {
    "$RALPH" init
    seed_open_item
    NO_COLOR=1 TERM=xterm run_on_tty "$RALPH" build --dry-run -n 1 -y
    [ "$status" -eq 0 ]
    [[ "$output" == *"── 1/1 ── claude"* ]]
    [[ "$output" == *"━━ ralph build"* ]]
    [[ "$output" != *$'\e'* ]]
}

@test "terminal TERM=dumb leaves no escape code on either stream" {
    "$RALPH" init
    seed_open_item
    NO_COLOR='' TERM=dumb run_on_tty "$RALPH" build --dry-run -n 1 -y
    [ "$status" -eq 0 ]
    [[ "$output" == *"── 1/1 ── claude"* ]]
    [[ "$output" == *"━━ ralph build"* ]]
    [[ "$output" != *$'\e'* ]]
}

@test "terminal stdout keeps colour when stderr is a file" {
    create_streaming_backend
    "$RALPH" init
    seed_open_item
    NO_COLOR='' TERM=xterm PATH="$TEST_DIR/bin:$PATH" run_on_tty bash -c \
        "$(printf '%q' "$RALPH") build -n 1 -y --skip-push 2> stderr.txt"
    [ "$status" -eq 0 ]
    [[ "$output" == *$'\e[2m── 1/1 ── claude'* ]]
    [[ "$output" == *$'\e[2m── 1/1 done ── '* ]]
    [[ "$output" != *"━━ ralph build"* ]]
    grep -q '━━ ralph build' stderr.txt
    [[ "$(<stderr.txt)" != *$'\e'* ]]
}

# Run ralph on a terminal of the first argument's columns, with COLUMNS set to the second or unset.
run_ralph_at_width() {
    local cols="$1" columns="$2"
    shift 2
    local cmd
    cmd="stty cols $cols; $(printf '%q ' "$RALPH" "$@")"
    if [[ -n $columns ]]; then
        NO_COLOR='' TERM=xterm COLUMNS=$columns run_on_tty bash -c "$cmd"
    else
        NO_COLOR='' TERM=xterm run_on_tty env -u COLUMNS bash -c "$cmd"
    fi
}

@test "terminal width COLUMNS=60 keeps every card line within 60" {
    "$RALPH" init
    seed_open_item
    run_ralph_at_width 120 60 build --dry-run -n 1 -y
    [ "$status" -eq 0 ]
    mapfile -t widths < <(card_line_widths <<< "$output")
    [ "${#widths[@]}" -ge 5 ]
    [ "$(printf '%s\n' "${widths[@]}" | sort -n | tail -1)" -eq 60 ]
}

@test "terminal width COLUMNS=60 beats a 70-column terminal" {
    "$RALPH" init
    seed_open_item
    run_ralph_at_width 70 60 build --dry-run -n 1 -y
    [ "$status" -eq 0 ]
    mapfile -t widths < <(card_line_widths <<< "$output")
    [ "${#widths[@]}" -ge 5 ]
    [ "$(printf '%s\n' "${widths[@]}" | sort -n | tail -1)" -eq 60 ]
}

@test "terminal width without COLUMNS follows a 70-column terminal" {
    "$RALPH" init
    seed_open_item
    run_ralph_at_width 70 '' build --dry-run -n 1 -y
    [ "$status" -eq 0 ]
    [ "$(card_line_widths < <(grep '^.\[2m── 1/1 ── ' <<< "$output"))" -eq 70 ]
}

@test "terminal width without COLUMNS is 120 on a 0-column terminal" {
    "$RALPH" init
    seed_open_item
    run_ralph_at_width 0 '' build --dry-run -n 1 -y
    [ "$status" -eq 0 ]
    [ "$(card_line_widths < <(grep '^.\[2m── 1/1 ── ' <<< "$output"))" -eq 120 ]
}

@test "terminal width COLUMNS=200 caps the divider at 120" {
    "$RALPH" init
    seed_open_item
    run_ralph_at_width 80 200 build --dry-run -n 1 -y
    [ "$status" -eq 0 ]
    [ "$(card_line_widths < <(grep '^.\[2m── 1/1 ── ' <<< "$output"))" -eq 120 ]
}

@test "terminal width cuts a footer longer than 40 columns to 40, ending in an ellipsis" {
    "$RALPH" init
    seed_open_item
    create_streaming_backend
    PATH="$TEST_DIR/bin:$PATH" run_ralph_at_width 120 40 build -n 1 -y --skip-push
    [ "$status" -eq 0 ]
    footer=$(grep '── 1/1 done ──' <<< "$output" | sed $'s/\e\\[[0-9;]*m//g')
    [ "$(card_line_widths <<< "$footer")" -eq 40 ]
    [[ "$footer" == *… ]]
}

@test "a dry-run build under an uninstalled locale warns about setlocale at most once" {
    "$RALPH" init
    printf -- '- [ ] **Real task**\n' >> IMPLEMENTATION_PLAN.md
    run --separate-stderr env LC_ALL=xx_YY.UTF-8 "$RALPH" build --dry-run -n 1
    [ "$status" -eq 0 ]
    [ "$(grep -c setlocale <<< "$stderr")" -le 1 ]
}
