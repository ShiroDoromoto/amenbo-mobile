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

[ "$#" = 0 ] || die "merge-and-gate.sh takes no arguments; its inputs come from AMENBO_INPUT"

worktree=$(input_dir worktree)

root=$(git -C "$worktree" rev-parse --show-toplevel 2>/dev/null) || die "$worktree is not in a git checkout"
cd "$root"

branch=$(git branch --show-current)
[ -n "$branch" ] || die "the checkout $root is on no branch"
[ "$branch" != main ] || die "the checkout $root is on main, and origin/main is merged into a branch of its own"
! git rev-parse -q --verify MERGE_HEAD >/dev/null ||
    die "the checkout $root already has a merge in progress; resolve and commit it, or abort it, first"
[ -z "$(git status --porcelain)" ] ||
    die "the checkout $root has uncommitted changes; commit them before merging origin/main"

git fetch -q origin main || die "could not fetch main from origin into $root"
git rev-parse -q --verify origin/main >/dev/null || die "the checkout $root has no origin/main to merge"
main=$(git rev-parse --short origin/main)

if git merge-base --is-ancestor origin/main HEAD; then
    merged="$branch already holds origin/main ($main), so nothing was merged"
else
    merge_log=$(mktemp) || die "could not make a temporary file"
    if ! git merge -q --no-edit origin/main > "$merge_log" 2>&1; then
        conflicts=$(git diff --name-only --diff-filter=U)
        if [ -z "$conflicts" ]; then
            cat "$merge_log" >&2
            rm -f "$merge_log"
            if git rev-parse -q --verify MERGE_HEAD >/dev/null; then
                git merge --abort || die "could not merge origin/main ($main) into $branch in $root, and could not abort the merge either; what git printed is above"
            fi
            die "could not merge origin/main ($main) into $branch in $root, with no conflict to resolve (a hook may have refused the merge commit); the merge was aborted, and what git printed is above"
        fi
        rm -f "$merge_log"
        conflict_list=衝突したファイル.txt
        printf '%s\n' "$conflicts" > "$out_dir/$conflict_list" || die "could not write $out_dir/$conflict_list"
        count=$(printf '%s\n' "$conflicts" | wc -l | tr -d ' ')
        leave 衝突した "$(jq -n --arg f "$conflict_list" '{"衝突したファイル": $f}')" \
            "merging origin/main ($main) into $branch in $root stopped on $count conflicted file(s), and the merge is left in progress; the gate was not run, and the paths are in $conflict_list"
    fi
    rm -f "$merge_log"
    merged="origin/main ($main) was merged into $branch as $(git rev-parse --short HEAD)"
fi

gate_log=ゲートの出力.txt
if ! run_gate "$root" "$out_dir/$gate_log"; then
    leave ゲートが赤 "$(jq -n --arg f "$gate_log" '{"ゲートの出力": $f}')" \
        "$merged in $root, and the gate failed ($gate_failed); the output of each failed check is in $gate_log"
fi
rm -f "$out_dir/$gate_log"

leave 完了 "$(jq -n --arg c "$(git rev-parse HEAD)" '{"コミット": $c}')" \
    "$merged in $root, and the gate passed"
