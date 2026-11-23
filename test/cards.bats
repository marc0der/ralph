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
    [[ "$output" == *"── 2/2 ── "*" · "*" ── 2s ── "* ]]
}

@test "headline names the first open item without bold markers" {
    "$RALPH" init
    printf -- '- [ ] **First task**\n- [ ] **Second task**\n' >> IMPLEMENTATION_PLAN.md
    run --separate-stderr "$RALPH" build --dry-run -n 1
    [ "$status" -eq 0 ]
    [[ "$output" == *$'\n▶ next: First task\n'* ]]
    [[ "$output" != *"**"* ]]
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
