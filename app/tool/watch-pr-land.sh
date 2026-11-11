#!/usr/bin/env bash
# watch-pr-land.sh — a script step: wait for a pull request to land on main, and say which way out it
# took: merged, in conflict with main, behind main, or red.
#
# It only reads what GitHub says. The merge itself is auto-merge's (open-pr.sh turns it on), so
# nothing here merges, updates the branch, or re-runs a check. Whether a red check is the change's own
# failure or a flaky runner, and how a conflict is resolved, are judgements left to the caller.
#
# Each read takes the pull request's state and merge state (`gh pr view`) and its checks
# (`gh pr checks`), and decides in this order:
#
#   MERGED                       hands on the merge commit
#   CLOSED                       stops the step: it was closed without merging
#   DIRTY, read twice in a row   in conflict with main (GitHub reads DIRTY for a moment while it is
#                                still working the merge state out, so one read is not enough)
#   a check failed or cancelled  red
#   a check still running        waits
#   every check over, BEHIND     behind main: main must be merged in before it can land
#   every check over, otherwise  waits for auto-merge to merge it; without auto-merge on, stops
#
# Usage: watch-pr-land.sh [OWNER/REPO]. The repository is the one given as the argument, else the
# input リポジトリ, else CI_REPO, else the one this script's checkout belongs to as gh sees it.
#
# The step names its ways out and ports in Japanese, so the names below are the ones written in the
# code. Inputs, from AMENBO_INPUT's `ins`:
#
#   PR          the pull request's number (required)
#   リポジトリ   OWNER/REPO, when no argument names one
#
# Ways out:
#
#   完了        merged; hands on コミット, the merge commit's hash
#   衝突        DIRTY; hands on nothing
#   遅れている  BEHIND with every check over and none red; hands on nothing
#   赤          a check failed or was cancelled; hands on 指摘, the file beside output.json holding
#               each such check's name, state and link, and the failed log of the runs they link to
#
# The way out is decided by output.json, never by this script's exit code. Anything it cannot read or
# do — a wrong argument, no PR or one that is not a number, a pull request closed without merging, a
# merged one with no merge commit, reads that keep failing, every check over with auto-merge off, a
# pull request that stays unmerged for LAND_STALL_LIMIT seconds after its checks are over, a wait past
# CI_WAIT_LIMIT — ends it with exit code 1, which the step leaves through its error way out.
#
# Besides the waits ci-lib.sh reads (CI_REPO, CI_POLL_SECONDS, CI_MISS_LIMIT, CI_WAIT_LIMIT), it reads
#
#   LAND_STALL_LIMIT  seconds a pull request may stay unmerged once every check is over (600)
#
# Every call goes through `gh` as PATH finds it, so a fake `gh` first on PATH checks the ways out
# without reaching GitHub.
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=step-lib.sh source-path=SCRIPTDIR
. "$here/step-lib.sh"
# shellcheck source=ci-lib.sh source-path=SCRIPTDIR
. "$here/ci-lib.sh"

: "${LAND_STALL_LIMIT:=600}"

[ "$#" -le 1 ] || die "watch-pr-land.sh が受け取る引数はリポジトリ（OWNER/REPO）1つだけです：$*"

pr=$(input_required PR)
[[ "$pr" =~ ^[0-9]+$ ]] || die "入力の PR が PR の番号ではありません：\"$pr\""

# A script step starts in no particular folder, and gh reads the repository from the one it is in.
cd "$here"
resolve_repo "${1:-$(input リポジトリ)}"

# write_red <checks JSON>: what a red pull request leaves to go on, on stdout: each failed or cancelled
# check, then the failed log of every Actions run those checks link to. A log that cannot be read is
# said in its place rather than stopping the step.
write_red() {
    local checks="$1" id
    echo "pull request: $pr_url"
    echo
    echo "failed checks:"
    jq -r '.[] | select(.bucket == "fail" or .bucket == "cancel") | "- \(.name) (\(.bucket)): \(.link // "")"' <<< "$checks"
    for id in $(jq -r '.[] | select(.bucket == "fail" or .bucket == "cancel") | .link // ""
        | capture("/actions/runs/(?<id>[0-9]+)") | .id' <<< "$checks" | sort -u); do
        echo
        echo "== run $id: $(run_url "$id")"
        gh run view "$id" -R "$repo" --log-failed 2>&1 || echo "(could not read the failed log of run $id)"
    done
}

miss=0 dirty=0 started=$SECONDS settled_since="" said=""
pr_url="https://github.com/$repo/pull/$pr"
echo "プルリクエスト ${pr}（${repo}）の着地を待ちます" >&2
while :; do
    if ! view=$(gh pr view "$pr" -R "$repo" --json state,mergeStateStatus,mergeCommit,autoMergeRequest,url 2>&1) ||
        ! jq -e 'type == "object"' <<< "$view" >/dev/null 2>&1; then
        miss=$((miss + 1))
        [ "$miss" -lt "$CI_MISS_LIMIT" ] ||
            die "プルリクエスト ${pr}（${repo}）を $CI_MISS_LIMIT 回続けて読めませんでした：$view"
        sleep "$CI_POLL_SECONDS"
        continue
    fi
    miss=0
    state=$(jq -r '.state // ""' <<< "$view")
    merge_state=$(jq -r '.mergeStateStatus // ""' <<< "$view")
    pr_url=$(jq -r --arg u "$pr_url" '.url // $u' <<< "$view")

    case "$state" in
        MERGED)
            commit=$(jq -r '.mergeCommit.oid // ""' <<< "$view")
            [ -n "$commit" ] || die "プルリクエスト $pr はマージ済みですが、マージコミットを読めませんでした：$pr_url"
            leave 完了 "$(jq -n --arg c "$commit" '{"コミット": $c}')" \
                "プルリクエスト $pr がマージされました。マージコミットは $commit です：$pr_url"
            ;;
        CLOSED) die "プルリクエスト $pr はマージされずに閉じられています：$pr_url" ;;
        OPEN) ;;
        *) die "プルリクエスト $pr の状態を読めませんでした：\"$state\"" ;;
    esac

    if [ "$merge_state" = DIRTY ]; then
        dirty=$((dirty + 1))
        if [ "$dirty" -ge 2 ]; then
            leave 衝突 '{}' "プルリクエスト $pr は main と衝突しています（DIRTY）：$pr_url"
        fi
    else
        dirty=0
    fi

    # `gh pr checks` exits non-zero while a check is pending or has failed, and fails outright while the
    # head has no checks yet, so its exit code is not read: anything that is not a list is no checks.
    checks=$(gh pr checks "$pr" -R "$repo" --json name,bucket,link 2>/dev/null) || true
    jq -e 'type == "array"' <<< "$checks" >/dev/null 2>&1 || checks='[]'
    total=$(jq 'length' <<< "$checks")
    red=$(jq '[.[] | select(.bucket == "fail" or .bucket == "cancel")] | length' <<< "$checks")
    pending=$(jq '[.[] | select(.bucket == "pending")] | length' <<< "$checks")

    line="プルリクエスト ${pr}：${state}・${merge_state}、チェック $total 個（実行中 ${pending}・赤 ${red}）"
    [ "$line" = "$said" ] || echo "$line" >&2
    said=$line

    if [ "$dirty" = 0 ] && [ "$red" -gt 0 ]; then
        evidence=指摘.txt
        write_red "$checks" > "$out_dir/$evidence" || die "$out_dir/$evidence を書けませんでした"
        names=$(jq -r '[.[] | select(.bucket == "fail" or .bucket == "cancel") | .name] | join(", ")' <<< "$checks")
        leave 赤 "$(jq -n --arg f "$evidence" '{"指摘": $f}')" \
            "プルリクエスト $pr のチェックが赤です（${names}）。落ちたログは $evidence にあります：$pr_url"
    fi

    if [ "$dirty" = 0 ] && [ "$total" -gt 0 ] && [ "$pending" = 0 ]; then
        if [ "$merge_state" = BEHIND ]; then
            leave 遅れている '{}' "プルリクエスト $pr のチェックは通りましたが、main より遅れています（BEHIND）：$pr_url"
        fi
        [ "$(jq -r '.autoMergeRequest != null' <<< "$view")" = true ] ||
            die "プルリクエスト $pr のチェックは通りましたが、自動マージがオンになっていません：$pr_url"
        [ -n "$settled_since" ] || settled_since=$SECONDS
        [ $((SECONDS - settled_since)) -lt "$LAND_STALL_LIMIT" ] ||
            die "プルリクエスト $pr はチェックが通ってから ${LAND_STALL_LIMIT} 秒たってもマージされません（${merge_state}）：$pr_url"
    else
        settled_since=""
    fi

    if [ -n "$CI_WAIT_LIMIT" ] && [ $((SECONDS - started)) -ge "$CI_WAIT_LIMIT" ]; then
        die "プルリクエスト $pr は ${CI_WAIT_LIMIT} 秒たっても着地しませんでした：$pr_url"
    fi
    sleep "$CI_POLL_SECONDS"
done
