#!/usr/bin/env bash
# merge-and-gate.sh — a script step: bring the latest origin/main into a checkout's branch and, when
# it merges cleanly, run the gate on the result.
#
# origin/main is fetched first, so the branch is checked against main as it stands now, then merged
# with `git merge --no-edit`. A branch that already holds all of origin/main is not merged, and the
# gate is run on it as it is. The gate is the one gate-lib.sh runs (dart format's check and
# `make test`). Nothing is pushed, and nothing is formatted or fixed here: how to resolve a conflict
# and what to change when the gate is red are judgements, so both are handed back.
#
# A conflict is left in place: the merge stays in progress with its conflict markers, so the conflicts
# can be resolved and the merge committed in the checkout as it is. Run again after that, the step
# finds origin/main already merged (unless main has moved again) and goes on to the gate. A clean
# merge that the gate then fails stays committed on the branch.
#
# Takes no arguments. The step names its ways out and ports in Japanese, so the names below are the
# ones written in the code. Inputs, from AMENBO_INPUT's `ins`:
#
#   worktree    the checkout whose branch takes origin/main (required)
#
# Ways out:
#
#   完了        origin/main is in the branch and the gate passed; hands on コミット (the full hash
#               the branch is at)
#   衝突した    the merge stopped on conflicts and is left in progress, and the gate was not run;
#               hands on 衝突したファイル, the file beside output.json naming each conflicted path on a
#               line of its own
#   ゲートが赤  origin/main is in the branch and the gate failed; hands on ゲートの出力, the file
#               beside output.json holding the full output of each failed check
#
# The way out is decided by output.json, never by this script's exit code. Anything it cannot read or
# do — an input missing, a folder that is not a git checkout, a checkout on main or on no branch, one
# with uncommitted changes or a merge already in progress, a fetch that failed, a merge that failed
# for a reason other than a conflict — ends it with exit code 1, which the step leaves through its
# error way out.
#
# GATE_FORMAT and GATE_TEST stand in for the gate's two checks (see gate-lib.sh), to check the ways
# out without waiting for the real gate.
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=step-lib.sh source-path=SCRIPTDIR
. "$here/step-lib.sh"
# shellcheck source=gate-lib.sh source-path=SCRIPTDIR
. "$here/gate-lib.sh"

[ "$#" = 0 ] || die "merge-and-gate.sh は引数を受け取りません。入力は AMENBO_INPUT から読みます：$*"

worktree=$(input_dir worktree)

root=$(git -C "$worktree" rev-parse --show-toplevel 2>/dev/null) || die "$worktree は git のチェックアウトではありません"
cd "$root"

branch=$(git branch --show-current)
[ -n "$branch" ] || die "worktree $root がどのブランチにもいません"
[ "$branch" != main ] || die "worktree $root は main にいます。origin/main は main ではなく、自分のブランチにマージします"
! git rev-parse -q --verify MERGE_HEAD >/dev/null ||
    die "worktree $root ではマージが途中です。先に解決してコミットするか、中止してください"
[ -z "$(git status --porcelain)" ] ||
    die "worktree $root にコミットしていない変更があります。コミットしてから origin/main をマージしてください"

git fetch -q origin main || die "$root に origin の main を fetch できませんでした"
git rev-parse -q --verify origin/main >/dev/null || die "worktree $root にマージする origin/main がありません"
main=$(git rev-parse --short origin/main)

if git merge-base --is-ancestor origin/main HEAD; then
    merged="$branch は origin/main（${main}）を既に含んでいるので、マージしていません"
else
    merge_log=$(mktemp) || die "一時ファイルを作れませんでした"
    if ! git merge -q --no-edit origin/main > "$merge_log" 2>&1; then
        conflicts=$(git diff --name-only --diff-filter=U)
        if [ -z "$conflicts" ]; then
            cat "$merge_log" >&2
            rm -f "$merge_log"
            if git rev-parse -q --verify MERGE_HEAD >/dev/null; then
                git merge --abort || die "${root} の $branch に origin/main（${main}）をマージできず、マージを中止することもできませんでした。git の出力は上にあります"
            fi
            die "${root} の $branch に origin/main（${main}）をマージできませんでしたが、解決する衝突はありません（フックがマージコミットを断ったのかもしれません）。マージは中止しました。git の出力は上にあります"
        fi
        rm -f "$merge_log"
        conflict_list=衝突したファイル.txt
        printf '%s\n' "$conflicts" > "$out_dir/$conflict_list" || die "$out_dir/$conflict_list を書けませんでした"
        count=$(printf '%s\n' "$conflicts" | wc -l | tr -d ' ')
        leave 衝突した "$(jq -n --arg f "$conflict_list" '{"衝突したファイル": $f}')" \
            "${root} の $branch に origin/main（${main}）をマージしたところ、$count 個のファイルが衝突して止まりました。マージは途中のまま残しています。ゲートは回していません。衝突したパスは $conflict_list にあります"
    fi
    rm -f "$merge_log"
    merged="origin/main（${main}）を $branch にマージしました（$(git rev-parse --short HEAD)）"
fi

gate_log=ゲートの出力.txt
if ! run_gate "$root" "$out_dir/$gate_log"; then
    leave ゲートが赤 "$(jq -n --arg f "$gate_log" '{"ゲートの出力": $f}')" \
        "${root} で、${merged}。ゲートが赤でした（${gate_failed}）。落ちたチェックの出力は $gate_log にあります"
fi
rm -f "$out_dir/$gate_log"

leave 完了 "$(jq -n --arg c "$(git rev-parse HEAD)" '{"コミット": $c}')" \
    "${root} で、${merged}。ゲートは通りました"
