#!/usr/bin/env bash
# check-and-commit.sh — a script step: run the gate on a checkout's changes and, when it passes, make
# the branch carry them as one commit on top of the point it left origin/main at.
#
# The gate is the one gate-lib.sh runs (dart format's check and `make test`). Nothing is formatted or
# fixed here: what to change when the gate is red, and what the commit message says, are judgements,
# so the message arrives as an input and a red gate is handed back with its output.
#
# When the gate passes, every change in the checkout is staged (`git add -A`, so what .gitignore names
# stays out) and the branch is made to carry one commit: a branch with no commit of its own gets a new
# one; a branch that already has some has them folded with the new changes into one, on the point it
# left origin/main at (`git merge-base`), so fixing a review is the same as amending. The message is
# the one in the input either way. origin/main is read as the checkout last fetched it: nothing is
# fetched, and nothing is pushed.
#
# The commit goes through the repository's hooks: `--no-verify` is never passed. When the commit is
# refused, the branch is put back where it was, the changes are left staged, and the refusal is handed
# back as a way out of its own, as what it asks to change is in the message or the diff.
#
# Takes no arguments. The step names its ways out and ports in Japanese, so the names below are the
# ones written in the code. Inputs, from AMENBO_INPUT's `ins`:
#
#   worktree    the checkout to commit in (required)
#   メッセージ   the commit message (required)
#
# Ways out:
#
#   完了              committed; hands on コミット (the commit's full hash)
#   ゲートが赤         the gate failed and nothing was committed; hands on ゲートの出力, the file
#                     beside output.json holding the full output of each failed check
#   変更が無い         the checkout has no change to commit, so the gate was not run; hands on nothing
#   コミットが断られた  the gate passed and `git commit` failed (a hook refused it); hands on
#                     コミットの出力, the file beside output.json holding what git and the hook printed
#
# The way out is decided by output.json, never by this script's exit code. Anything it cannot read or
# do — an input missing, a folder that is not a git checkout, a checkout on main or on no branch, no
# origin/main to count from, a git command other than the commit that failed — ends it with exit
# code 1, which the step leaves through its error way out.
#
# GATE_FORMAT and GATE_TEST stand in for the gate's two checks (see gate-lib.sh), to check the ways
# out without waiting for the real gate.
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=step-lib.sh source-path=SCRIPTDIR
. "$here/step-lib.sh"
# shellcheck source=gate-lib.sh source-path=SCRIPTDIR
. "$here/gate-lib.sh"

[ "$#" = 0 ] || die "check-and-commit.sh は引数を受け取りません。入力は AMENBO_INPUT から読みます：$*"

worktree=$(input_dir worktree)
message=$(input_required メッセージ)

root=$(git -C "$worktree" rev-parse --show-toplevel 2>/dev/null) || die "$worktree は git のチェックアウトではありません"
cd "$root"

branch=$(git branch --show-current)
[ -n "$branch" ] || die "worktree $root がどのブランチにもいません"
[ "$branch" != main ] || die "worktree $root は main にいます。変更は main ではなく、自分のブランチにコミットします"
git rev-parse -q --verify origin/main >/dev/null || die "worktree $root に origin/main がないので、ブランチのコミットを数えられません"

[ -n "$(git status --porcelain)" ] ||
    leave 変更が無い '{}' "${root} の $branch にはコミットする変更がありません。ゲートは回していません"

gate_log=ゲートの出力.txt
if ! run_gate "$root" "$out_dir/$gate_log"; then
    leave ゲートが赤 "$(jq -n --arg f "$gate_log" '{"ゲートの出力": $f}')" \
        "${root} の $branch でゲートが赤でした（${gate_failed}）。何もコミットしていません。落ちたチェックの出力は $gate_log にあります"
fi
rm -f "$out_dir/$gate_log"

base=$(git merge-base origin/main HEAD) || die "$branch と origin/main に共通の履歴がありません"
head=$(git rev-parse HEAD)
own=$(git rev-list --no-merges --count "$base..HEAD")

git add -A || die "$root の変更をステージできませんでした"
git diff --cached --quiet "$base" &&
    die "$root の変更は、$branch が origin/main から積んだものをすべて打ち消すので、コミットするものが残りません"

[ "$head" = "$base" ] || git reset -q --soft "$base" || die "$branch のコミットをまとめられませんでした"

msg_file=$(mktemp) || die "一時ファイルを作れませんでした"
printf '%s\n' "$message" > "$msg_file"
commit_log=コミットの出力.txt
if ! git commit -q -F "$msg_file" > "$out_dir/$commit_log" 2>&1; then
    rm -f "$msg_file"
    git reset -q --soft "$head" || die "コミットが断られ、$branch を $head に戻すこともできませんでした"
    leave コミットが断られた "$(jq -n --arg f "$commit_log" '{"コミットの出力": $f}')" \
        "ゲートは通りましたが、${root} の $branch で git commit が失敗しました。$branch は $head に戻し、変更はステージしたままです。git の出力は $commit_log にあります"
fi
rm -f "$msg_file" "$out_dir/$commit_log"

sha=$(git rev-parse HEAD)
if [ "$own" = 0 ]; then
    how="新しいコミット1個"
else
    how="積んでいたコミット $own 個と新しい変更を1個にまとめたコミット"
fi
leave 完了 "$(jq -n --arg c "$sha" '{"コミット": $c}')" \
    "ゲートが通り、${root} の $branch は $(git rev-parse --short "$base") の上に、${how}を積みました：$(git rev-parse --short "$sha")"
