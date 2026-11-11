#!/usr/bin/env bash
# open-pr.sh — a script step: open the pull request of a worktree's branch against main with
# auto-merge on, or find the one already open, and hand its number on.
#
# It works in the worktree, on the branch checked out there, and does not merge main into it. What it
# does depends on the pull request the branch already has:
#
#   open                 pushes the branch (with --force-with-lease, as an amended commit is a
#                        rewrite) and leaves auto-merge as it was set
#   merged, nothing new  does nothing
#   none, or merged or closed with commits since
#                        folds the branch's commits into one when it carries two or more, merge
#                        commits not counted, reusing the message of the oldest; pushes the branch;
#                        opens the pull request from that commit against main; and turns auto-merge
#                        on with a merge commit
#
# The commits are folded onto the point the branch left main at (`git merge-base`), not onto
# origin/main, so a branch behind main does not take main's newer changes back out.
#
# Usage: open-pr.sh [OWNER/REPO]. The repository is the one given as the argument, else the input
# リポジトリ, else CI_REPO, else the worktree's own as gh sees it. Every `gh` call is pointed at it.
#
# The step names its ways out and ports in Japanese, so the names below are the ones written in the
# code. Inputs, from AMENBO_INPUT's `ins`:
#
#   worktree    the checkout whose branch is opened (required)
#   リポジトリ   OWNER/REPO, when no argument names one
#
# It has one way out, 完了, which hands on PR (the pull request's number); the report carries its URL.
#
# The way out is decided by output.json, never by this script's exit code. Anything it cannot read or
# do — no worktree, a worktree on main or on no branch, uncommitted changes, a branch with nothing to
# open, a command that failed — ends it with exit code 1, which the step leaves through its error way
# out.
#
# Every call goes through `git` and `gh` as PATH finds them, so a fake `gh` first on PATH and a
# throwaway clone whose origin is a local bare repository check the ways out without reaching GitHub.
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=step-lib.sh source-path=SCRIPTDIR
. "$here/step-lib.sh"
# shellcheck source=ci-lib.sh source-path=SCRIPTDIR
. "$here/ci-lib.sh"

[ "$#" -le 1 ] || die "open-pr.sh が受け取る引数はリポジトリ（OWNER/REPO）1つだけです：$*"

worktree=$(input_dir worktree)
root=$(git -C "$worktree" rev-parse --show-toplevel 2>/dev/null) || die "$worktree は git のチェックアウトではありません"
cd "$root"

branch=$(git branch --show-current)
[ -n "$branch" ] || die "worktree $root がどのブランチにもいません"
[ "$branch" != main ] || die "worktree $root は main にいます。main からはプルリクエストを作りません"
[ -z "$(git status --porcelain --untracked-files=no)" ] ||
    die "worktree $root にコミットしていない変更があります。コミットしてから回してください"

# gh reads the repository from the folder it runs in, so it is resolved in the worktree.
resolve_repo "${1:-$(input リポジトリ)}"

git fetch origin -q || die "origin を fetch できませんでした"
git rev-parse -q --verify origin/main >/dev/null || die "worktree $root に origin/main がありません"

opened() { leave 完了 "$(jq -n --arg n "$1" '{"PR": $n}')" "$2"; }

# `gh pr view` fails when the branch has no pull request, which reads here as none.
pr_json=$(gh pr view "$branch" -R "$repo" --json number,state,url 2>/dev/null) || pr_json='{}'
pr=$(jq -r '.number // empty' <<< "$pr_json")
state=$(jq -r '.state // empty' <<< "$pr_json")
pr_url=$(jq -r '.url // empty' <<< "$pr_json")
ahead=$(git rev-list --count origin/main..HEAD)

if [ "$state" = MERGED ] && [ "$ahead" = 0 ]; then
    opened "$pr" "$branch のプルリクエスト $pr はマージ済みで、そのあとのコミットはありません：$pr_url"
fi

if [ "$state" = OPEN ]; then
    git push -q --force-with-lease -u origin "$branch" || die "$branch を push できませんでした"
    opened "$pr" "$branch のプルリクエスト $pr は開いているので、ブランチを push しました：$pr_url"
fi

commits=$(git rev-list --no-merges --count origin/main..HEAD)
[ "$commits" -gt 0 ] || die "$branch には main に無いコミットが無いので、プルリクエストを作れません"

if [ "$commits" -gt 1 ]; then
    oldest=$(git rev-list --no-merges --reverse origin/main..HEAD | head -n 1)
    base=$(git merge-base origin/main HEAD) || die "$branch と origin/main に共通の履歴がありません"
    git reset -q --soft "$base" || die "$branch のコミットをまとめられませんでした"
    git commit -q -C "$oldest" || die "$branch のまとめたコミットをコミットできませんでした"
    echo "$branch のコミット $commits 個を $(git rev-parse --short HEAD) にまとめました" >&2
fi

git push -q --force-with-lease -u origin "$branch" || die "$branch を push できませんでした"
url=$(gh pr create -R "$repo" --fill --base main --head "$branch") || die "$branch のプルリクエストを作れませんでした"
pr=$(sed -nE 's|.*/pull/([0-9]+)$|\1|p' <<< "$url" | tail -n 1)
[ -n "$pr" ] || die "$branch のプルリクエストを作りましたが、番号を読めませんでした：$url"
gh pr merge "$pr" -R "$repo" --merge --auto || die "プルリクエスト $pr を作りましたが、自動マージをオンにできませんでした：$url"

opened "$pr" "$branch のプルリクエスト $pr を作り、自動マージをオンにしました：$url"
