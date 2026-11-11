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
# shellcheck source=../step-lib.sh source-path=SCRIPTDIR
. "$here/../step-lib.sh"

[ "$#" = 0 ] || die "bump-version.sh は引数を受け取りません。入力は AMENBO_INPUT から読みます：$*"

worktree=$(input_dir worktree)
name=$(input_required バージョン)
[[ "$name" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "入力のバージョン名が <major>.<minor>.<patch> の形ではありません：\"$name\""

pubspec="$worktree/app/pubspec.yaml"
about="$worktree/app/lib/about_screen.dart"
[ -f "$pubspec" ] || die "${worktree} に app/pubspec.yaml がありません"
[ -f "$about" ] || die "${worktree} に app/lib/about_screen.dart がありません"

# The one line of a file that matches a pattern, or the step stops.
only_line() {
    local found
    found=$(grep -E "$2" "$1" || true)
    [ -n "$found" ] && [ "$(printf '%s\n' "$found" | wc -l | tr -d ' ')" = 1 ] ||
        die "${1} で /$2/ に合う行が1行ではありません"
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
    die "バージョン名 $name が、チェックアウトの ${current_name} より小さいです"

# What one store's `state` prints: the file the override names, or the command itself.
state_of() {
    local store="$1" override="$2" text
    if [ -n "$override" ]; then
        [ -r "$override" ] || die "${store} state の代わりのファイルを読めません：$override"
        cat "$override"
        return
    fi
    command -v uv >/dev/null || die "uv が入っていません。$store state は uv で動かします"
    text=$(uv run --quiet "$here/$store" state) || die "$store state が失敗しました"
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
                [[ "$n" =~ ^[0-9]+$ ]] || die "appstore.py state に、数字でないビルドがあります：\"$n\""
                echo "$n"
                ;;
            "  version "*)
                n=${line##*build=}
                [ "$n" = None ] && continue
                [[ "$n" =~ ^[0-9]+$ ]] || die "appstore.py state に、ビルドが数字でないバージョンがあります：\"$n\""
                echo "$n"
                ;;
        esac
    done
    [ "$seen" = 1 ] || die "appstore.py state の出力に app の行が無いので、出力を読めませんでした"
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
        [[ "$list" =~ ^\[[0-9\'\",\ ]*\]$ ]] || die "play.py state に、読めない versionCode のリストがあります：\"$list\""
        grep -oE '[0-9]+' <<< "$list" || true
    done
    [ "$seen" = 1 ] || die "play.py state の出力に bundles の行が無いので、出力を読めませんでした"
}

# The largest of the numbers on stdin, or nothing.
largest() { sort -n | tail -n 1; }

appstore_state=$(state_of appstore.py "${BUMP_APPSTORE_STATE:-}")
play_state=$(state_of play.py "${BUMP_PLAY_STATE:-}")
appstore_max=$(appstore_numbers <<< "$appstore_state" | largest)
play_max=$(play_numbers <<< "$play_state" | largest)

taken=$(printf '%s\n%s\n' "$appstore_max" "$play_max" | grep -E '^[0-9]+$' | largest || true)
[ -n "$taken" ] || die "どちらのストアにもビルド番号が無いので、次の番号を決められません"
number=$((10#$taken + 1))

[ "$((10#$current_number))" -le "$number" ] ||
    die "チェックアウトのビルド番号 $current_number が、ストアの次の番号 $number をもう越えています"

# Replace the one line matching a pattern in a file, keeping the file itself (and its mode).
replace_line() {
    local file="$1" re="$2" line="$3" written got
    written=$(mktemp) || die "一時ファイルを作れませんでした"
    RE="$re" LINE="$line" awk '$0 ~ ENVIRON["RE"] { print ENVIRON["LINE"]; next } { print }' "$file" > "$written" ||
        die "${file} を書き換えられませんでした"
    cat "$written" > "$file" || die "${file} に書けませんでした"
    rm -f "$written"
    got=$(only_line "$file" "$re") || exit 1
    [ "$got" = "$line" ] || die "書き込んだあとの $file に \"$line\" の行がありません"
}

replace_line "$pubspec" "$pubspec_re" "version: $name+$number"
replace_line "$about" "$app_version_re" "const appVersion = '$name';"
replace_line "$about" "$app_build_re" "const appBuild = '$number';"

leave 完了 "$(jq -n --arg v "$name" --arg b "$number" '{"バージョン": $v, "ビルド番号": $b}')" \
    "${worktree} のバージョンを ${name}+${number} にしました（前は ${current_name}+${current_number}。App Store Connect にある最大のビルド番号は ${appstore_max:-なし}、Play は ${play_max:-なし}）"
