#!/usr/bin/env bash
# bump-version.sh — a script step: raise the app's build number past every one the two stores have
# taken, and set the version name it is handed.
#
# Each store refuses a build number it has already taken, so the next one is the largest number either
# store holds, plus one. It is read from `appstore.py state` (the `build` lines, and the build each
# version record carries) and `play.py state` (the `bundles` line, and the versionCodes each track
# serves). The version name is not worked out here: whether a release moves the minor or the patch is a
# judgement, so it arrives as an input.
#
# The two go into the checkout the input names, and nowhere else:
#
#   app/pubspec.yaml            version: <name>+<number>
#   app/lib/about_screen.dart   appVersion = '<name>'   appBuild = '<number>'
#
# Nothing is committed. Run again once written, it writes the same two lines and changes nothing, as
# the number in the checkout is then already the stores' largest plus one.
#
# Takes no arguments. The step names its ways out and ports in Japanese, so the names below are the
# ones written in the code. Inputs, from AMENBO_INPUT's `ins`:
#
#   worktree     the checkout to write in (required)
#   バージョン    the version name, as <major>.<minor>.<patch> (required)
#
# One way out, 完了, which hands on バージョン (the name) and ビルド番号 (the number).
#
# The way out is decided by output.json, never by this script's exit code. Anything it cannot read or
# do — an input missing or malformed, a version name lower than the checkout's, a store whose state
# cannot be read or parsed, a checkout whose number is already past the stores' next one, a line that
# is not where it is expected — ends it with exit code 1, which the step leaves through its error way
# out.
#
# `state` prints the app's and its submissions' identifiers, so its output is parsed here and never
# passed on: only the numbers read from it reach the report. To check the parsing without touching a
# store, BUMP_APPSTORE_STATE and BUMP_PLAY_STATE may each name a file holding what `state` would print,
# which is then read in its place.
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=step-lib.sh source-path=SCRIPTDIR
. "$here/step-lib.sh"

[ "$#" = 0 ] || die "bump-version.sh takes no arguments; its inputs come from AMENBO_INPUT"

worktree=$(input_dir worktree)
name=$(input_required バージョン)
[[ "$name" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "the version name in the input is not <major>.<minor>.<patch>: \"$name\""

pubspec="$worktree/app/pubspec.yaml"
about="$worktree/app/lib/about_screen.dart"
[ -f "$pubspec" ] || die "no app/pubspec.yaml in $worktree"
[ -f "$about" ] || die "no app/lib/about_screen.dart in $worktree"

# The one line of a file that matches a pattern, or the step stops.
only_line() {
    local found
    found=$(grep -E "$2" "$1" || true)
    [ -n "$found" ] && [ "$(printf '%s\n' "$found" | wc -l | tr -d ' ')" = 1 ] ||
        die "expected one line matching /$2/ in $1"
    printf '%s\n' "$found"
}

pubspec_re='^version: [0-9]+\.[0-9]+\.[0-9]+\+[0-9]+$'
app_version_re="^const appVersion = '[^']*';$"
app_build_re="^const appBuild = '[^']*';$"

current=$(only_line "$pubspec" "$pubspec_re")
current=${current#version: }
current_name=${current%+*}
current_number=${current#*+}
only_line "$about" "$app_version_re" >/dev/null
only_line "$about" "$app_build_re" >/dev/null

# Whether version name $1 is lower than $2, part by part.
lower_than() {
    local a b i
    IFS=. read -r -a a <<< "$1"
    IFS=. read -r -a b <<< "$2"
    for i in 0 1 2; do
        [ "$((10#${a[i]}))" -lt "$((10#${b[i]}))" ] && return 0
        [ "$((10#${a[i]}))" -gt "$((10#${b[i]}))" ] && return 1
    done
    return 1
}
! lower_than "$name" "$current_name" ||
    die "the version name $name is lower than the checkout's $current_name"

# What one store's `state` prints: the file the override names, or the command itself.
state_of() {
    local store="$1" override="$2" text
    if [ -n "$override" ]; then
        [ -r "$override" ] || die "cannot read the stand-in for $store state: $override"
        cat "$override"
        return
    fi
    command -v uv >/dev/null || die "uv is not installed, and $store state runs with it"
    text=$(uv run --quiet "$here/$store" state) || die "$store state failed"
    printf '%s\n' "$text"
}

# The build numbers App Store Connect holds, one per line.
appstore_numbers() {
    local line n seen=0
    while IFS= read -r line; do
        case "$line" in
            "app "*) seen=1 ;;
            "  build "*)
                n=${line#  build }
                n=${n%%  *}
                [[ "$n" =~ ^[0-9]+$ ]] || die "appstore.py state shows a build that is not a number: \"$n\""
                echo "$n"
                ;;
            "  version "*)
                n=${line##*build=}
                [ "$n" = None ] && continue
                [[ "$n" =~ ^[0-9]+$ ]] || die "appstore.py state shows a version carrying a build that is not a number: \"$n\""
                echo "$n"
                ;;
        esac
    done
    [ "$seen" = 1 ] || die "appstore.py state printed no app line, so its output could not be read"
}

# The versionCodes Play holds, one per line.
play_numbers() {
    local line list seen=0
    while IFS= read -r line; do
        case "$line" in
            "bundles ["*"]")
                seen=1
                list=${line#bundles }
                ;;
            "  "*"]")
                list="[${line##*[}"
                ;;
            *) continue ;;
        esac
        [[ "$list" =~ ^\[[0-9\'\",\ ]*\]$ ]] || die "play.py state shows a list of versionCodes it could not read: \"$list\""
        grep -oE '[0-9]+' <<< "$list" || true
    done
    [ "$seen" = 1 ] || die "play.py state printed no bundles line, so its output could not be read"
}

# The largest of the numbers on stdin, or nothing.
largest() { sort -n | tail -n 1; }

appstore_state=$(state_of appstore.py "${BUMP_APPSTORE_STATE:-}")
play_state=$(state_of play.py "${BUMP_PLAY_STATE:-}")
appstore_max=$(appstore_numbers <<< "$appstore_state" | largest)
play_max=$(play_numbers <<< "$play_state" | largest)

taken=$(printf '%s\n%s\n' "$appstore_max" "$play_max" | grep -E '^[0-9]+$' | largest || true)
[ -n "$taken" ] || die "neither store shows a build number, so there is nothing to count up from"
number=$((10#$taken + 1))

[ "$((10#$current_number))" -le "$number" ] ||
    die "the checkout's build number $current_number is already past the stores' next one, $number"

# Replace the one line matching a pattern in a file, keeping the file itself (and its mode).
replace_line() {
    local file="$1" re="$2" line="$3" written got
    written=$(mktemp) || die "could not make a temporary file"
    RE="$re" LINE="$line" awk '$0 ~ ENVIRON["RE"] { print ENVIRON["LINE"]; next } { print }' "$file" > "$written" ||
        die "could not rewrite $file"
    cat "$written" > "$file" || die "could not write $file"
    rm -f "$written"
    got=$(only_line "$file" "$re") || exit 1
    [ "$got" = "$line" ] || die "$file does not read \"$line\" after writing it"
}

replace_line "$pubspec" "$pubspec_re" "version: $name+$number"
replace_line "$about" "$app_version_re" "const appVersion = '$name';"
replace_line "$about" "$app_build_re" "const appBuild = '$number';"

leave 完了 "$(jq -n --arg v "$name" --arg b "$number" '{"バージョン": $v, "ビルド番号": $b}')" \
    "set the version to $name+$number in $worktree (was $current_name+$current_number; the largest build number App Store Connect holds is ${appstore_max:-none}, Play ${play_max:-none})"
