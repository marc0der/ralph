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
