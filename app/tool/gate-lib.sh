# shellcheck shell=bash
# gate-lib.sh — sourced helper shared by the script steps that run the gate on a checkout before they
# go on. Not executable on its own.
#
# The gate is the two checks a change has to pass before it is committed, both run at the top of the
# checkout:
#
#   format   cd app && dart format --output=none --set-exit-if-changed .
#   test     make test   (the guards, then the app's tests)
#
# Both are run even when the first one fails, so a red gate names every check that failed at once.
# Neither rewrites the checkout's sources: a file dart format would change is reported, not formatted.
#
# To check a step's ways out without waiting for the real gate, GATE_FORMAT and GATE_TEST may each
# hold a shell command, run in the checkout's top folder in place of that check.

# run_gate <checkout> <log>: run the gate in the checkout. Returns 0 when every check passed and 1 when
# one failed, after writing the full output of each failed check to <log>, under a heading naming it.
# The names of the failed checks are left in gate_failed, space-separated. Anything else that goes
# wrong (a log it cannot write) stops the step.
run_gate() {
    local root="$1" log="$2" name cmd out status
    gate_failed=
    : > "$log" || die "ゲートのログ $log を書けませんでした"
    out=$(mktemp) || die "一時ファイルを作れませんでした"
    for name in format test; do
        case "$name" in
            format) cmd=${GATE_FORMAT:-cd app && dart format --output=none --set-exit-if-changed .} ;;
            test) cmd=${GATE_TEST:-make test} ;;
        esac
        echo "==> ゲート：$name" >&2
        status=0
        (cd "$root" && bash -c "$cmd") > "$out" 2>&1 || status=$?
        [ "$status" = 0 ] && continue
        gate_failed="${gate_failed:+$gate_failed }$name"
        {
            printf '==> %s failed (exit %s): %s\n' "$name" "$status" "$cmd"
            cat "$out"
            printf '\n'
        } >> "$log" || die "ゲートのログ $log を書けませんでした"
    done
    rm -f "$out"
    [ -z "$gate_failed" ]
}
