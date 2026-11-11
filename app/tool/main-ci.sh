#!/usr/bin/env bash
# main-ci.sh — a script step: dispatch ci.yml on main, wait for the run, and say which way out its
# verdict is.
#
# A dispatched run builds every layer (ci.yml turns them all on for a dispatch, as there is no diff to
# filter by), and runs in a concurrency group of its own, so it neither cancels main's push runs nor
# is cancelled by them. The verdict is the `all green` job's, which folds every other job the way the
# workflow's required check does. Nothing is re-run here: whether a red is main's own failure or a
# flaky runner is a judgement, so it is handed back with what the run left.
#
# Takes no arguments and reads no inputs, though AMENBO_INPUT must still name a JSON object. The step
# names its ways out and ports in Japanese, so the names below are the ones written in the code:
#
#   完了        the run is green; hands on nothing, and the report carries the run's URL
#   main が赤   the run is red; hands on 赤の証拠, the file beside output.json holding the run's id and
#               URL, the jobs that failed, and their failed log
#
# The way out is decided by output.json, never by this script's exit code. Anything it cannot read or
# do — a dispatch that failed, a run that never appeared, a wait that broke, a run that ended without a
# verdict — ends it with exit code 1, which the step leaves through its error way out.
#
# The repository is the one this checkout belongs to, as gh sees it, unless CI_REPO names another.
# The waits are tuned as ci-lib.sh says, and a fake `gh` first on PATH stands in for GitHub.
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=step-lib.sh source-path=SCRIPTDIR
. "$here/step-lib.sh"
# shellcheck source=ci-lib.sh source-path=SCRIPTDIR
. "$here/ci-lib.sh"

[ "$#" = 0 ] || die "main-ci.sh takes no arguments; it reads what it needs from the checkout it sits in"

# A script step starts in no particular folder, and gh reads the repository from the one it is in.
cd "$here"
resolve_repo

workflow=ci.yml
stamp=$(now_utc)
gh workflow run "$workflow" -R "$repo" --ref main >&2 || die "could not dispatch $workflow on main in $repo"
id=$(dispatched_run "$workflow" main "$stamp")

watch_run "$id"
url=$(run_url "$id")
verdict=$(run_verdict "all green")
if [ "$verdict" = green ]; then
    leave 完了 '{}' "$workflow on main is green: $url"
fi

evidence=赤の証拠.txt
write_red_run "$id" > "$out_dir/$evidence" || die "could not write $out_dir/$evidence"
leave "main が赤" "$(jq -n --arg f "$evidence" '{"赤の証拠": $f}')" \
    "$workflow on main is red, run $id ($(failed_jobs)): $url; the run's failed log is in $evidence"
