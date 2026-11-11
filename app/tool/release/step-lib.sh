# shellcheck shell=bash
# step-lib.sh — sourced helpers shared by the script steps: reading an input and leaving by a way out.
# Not executable on its own.
#
# A script step reads its inputs from the JSON file AMENBO_INPUT names and writes its way out to the
# one AMENBO_OUTPUT names, as {"version":1,"exit":…,"outs":{…},"report":…}. The way out is decided by
# that file, never by the exit code: anything a step cannot read or do ends it with exit code 1, which
# the run leaves through the step's error way out, the reason being the last line on stderr.
#
# A file a step hands on is written beside output.json (in out_dir), and named in its outs by its file
# name alone.

die() { echo "✗ $*" >&2; exit 1; }

command -v jq >/dev/null || die "jq is not installed, and the step reads and writes its JSON with it"

[ -n "${AMENBO_INPUT:-}" ] && [ -n "${AMENBO_OUTPUT:-}" ] ||
    die "run this as a script step: AMENBO_INPUT and AMENBO_OUTPUT are not set"
[ -r "$AMENBO_INPUT" ] || die "cannot read the input file $AMENBO_INPUT"
jq -e 'type == "object"' "$AMENBO_INPUT" >/dev/null 2>&1 || die "the input file $AMENBO_INPUT is not a JSON object"

# shellcheck disable=SC2034 # read by the steps that source this file
out_dir=$(dirname "$AMENBO_OUTPUT")
[ -d "$out_dir" ] && [ -w "$out_dir" ] || die "cannot write beside the output file: $out_dir"

# One input of the step, by its name, or nothing. A string is given as it is; anything else as JSON.
input() { jq -r --arg k "$1" '.ins[$k] // empty | if type == "string" then . else tojson end' "$AMENBO_INPUT"; }

# One input that must be there, or the step stops.
input_required() {
    local value
    value=$(input "$1") || die "could not read \"$1\" from $AMENBO_INPUT"
    [ -n "$value" ] || die "no \"$1\" in the input"
    printf '%s\n' "$value"
}

# The folder an input names, which must exist, or the step stops.
input_dir() {
    local dir
    dir=$(input_required "$1") || exit 1
    [ -d "$dir" ] || die "\"$1\" in the input is not a folder: \"$dir\""
    printf '%s\n' "$dir"
}

# Write output.json and stop: the way out, its outputs as a JSON object, and the report.
leave() {
    jq -n --arg exit "$1" --argjson outs "$2" --arg report "$3" \
        '{version: 1, exit: $exit, outs: $outs, report: $report}' > "$AMENBO_OUTPUT" ||
        die "could not write $AMENBO_OUTPUT"
    exit 0
}
