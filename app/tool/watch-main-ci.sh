#!/usr/bin/env bash
# watch-main-ci.sh — a script step: wait for the CI run a merge into main started, and say which way
# out its verdict is.
#
# The step before it landed a pull request and hands on its merge commit. This looks for the push run
# of the workflow for that commit, waiting up to CI_PUSH_LIMIT seconds for it to appear. When none
# does, it dispatches the workflow on main and waits for that run instead. A dispatch has no input to
# pin the commit, so the dispatched run builds main's tip as it is then, which may be past the merge
# commit; the report says which commit the run built. The verdict is the `all green` job's when the
# run carries it, else the run's own conclusion. Nothing is re-run here: whether a red is the merge's
# own, another merge's or a flaky runner is a judgement, so it is handed back with what the run left.
#
# Usage: watch-main-ci.sh [OWNER/REPO [WORKFLOW]]. The repository is the one given as the first
# argument, else the input リポジトリ, else CI_REPO, else the one this script's checkout belongs to as
# gh sees it. The workflow is its file name under .github/workflows, given as the second argument,
# else the input workflow, else ci.yml. An empty first argument names no repository.
#
# The step names its ways out and ports in Japanese, so the names below are the ones written in the
# code. Inputs, from AMENBO_INPUT's `ins`:
#
#   コミット    the merge commit's hash, 7 to 40 hex digits (required)
#   リポジトリ   OWNER/REPO, when no argument names one
#   workflow    the workflow's file name, when no argument names one
#
# Ways out:
#
#   完了        the run is green; hands on コミット as it came, and the report carries the run's URL and
#               whether it was the push run or a dispatched one
#   main が赤   the run is red; hands on 赤の証拠, the file beside output.json holding the merge commit
#               and the main commit before it, the run's id and URL and the commit it built, the jobs
#               that failed, and their failed log
#
# The way out is decided by output.json, never by this script's exit code. Anything it cannot read or
# do — more than two arguments, no commit or one that is not a hash, a repository or workflow not in
# its form, a commit GitHub does not know, a dispatch that failed, a dispatched run that never
# appeared, a wait that broke, a run that ended without a verdict — ends it with exit code 1, which the
# step leaves through its error way out.
#
# The waits are tuned as ci-lib.sh says (CI_PUSH_LIMIT is how long the push run is looked for), and a
# fake `gh` first on PATH stands in for GitHub.
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=step-lib.sh source-path=SCRIPTDIR
. "$here/step-lib.sh"
# shellcheck source=ci-lib.sh source-path=SCRIPTDIR
. "$here/ci-lib.sh"

[ "$#" -le 2 ] ||
    die "watch-main-ci.sh が受け取る引数はリポジトリ（OWNER/REPO）と workflow の2つまでです：$*"

commit=$(input_required コミット)
[[ "$commit" =~ ^[0-9a-f]{7,40}$ ]] || die "入力のコミットがコミットのハッシュではありません：\"$commit\""

workflow=${2:-$(input workflow)}
workflow=${workflow:-ci.yml}
[[ "$workflow" =~ ^[A-Za-z0-9_.-]+\.ya?ml$ ]] ||
    die "workflow が .github/workflows のファイル名ではありません：\"$workflow\""

# A script step starts in no particular folder, and gh reads the repository from the one it is in.
cd "$here"
resolve_repo "${1:-$(input リポジトリ)}"

# `gh run list --commit` matches the full hash only, so a short one is made full first. The first
# parent is main before the merge, which is what a revert of a red merge needs.
row=$(gh api "repos/$repo/commits/$commit" --jq '"\(.sha) \(.parents[0].sha // "")"') ||
    die "コミット $commit を ${repo} で読めませんでした"
sha=${row%% *}
parent=${row#* }
[[ "$sha" =~ ^[0-9a-f]{40}$ ]] || die "コミット $commit の全桁のハッシュを読めませんでした：\"$row\""

id=$(push_run "$workflow" "$sha")
if [ -n "$id" ]; then
    kind="push の run"
else
    echo "コミット $sha の push の run が無いので、$workflow を main で dispatch します" >&2
    stamp=$(now_utc)
    gh workflow run "$workflow" -R "$repo" --ref main >&2 || die "$workflow を ${repo} の main で dispatch できませんでした"
    id=$(dispatched_run "$workflow" main "$stamp")
    kind="dispatch した run"
fi

watch_run "$id"
url=$(run_url "$id")
built=$(gh run view "$id" -R "$repo" --json headSha --jq .headSha 2>/dev/null) || built=""
built=${built:-（読めませんでした）}
seen="${kind}（run ${id}、組んだコミット ${built}）"

verdict=$(run_verdict "all green")
if [ "$verdict" = green ]; then
    leave 完了 "$(jq -n --arg c "$commit" '{"コミット": $c}')" \
        "コミット $sha の main の $workflow は緑です。見たのは ${seen}：$url"
fi

evidence=赤の証拠.txt
{
    echo "merge commit: $sha"
    echo "main before it: ${parent:-(none)}"
    echo "run kind: $([ "$kind" = "push の run" ] && echo push || echo workflow_dispatch)"
    echo "built commit: $built"
    write_red_run "$id"
} > "$out_dir/$evidence" || die "$out_dir/$evidence を書けませんでした"
leave "main が赤" "$(jq -n --arg f "$evidence" '{"赤の証拠": $f}')" \
    "コミット $sha の main の $workflow は赤です（$(failed_jobs)）。見たのは ${seen}。落ちたログは $evidence にあります：$url"
