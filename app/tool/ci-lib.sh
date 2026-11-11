# shellcheck shell=bash
# ci-lib.sh — sourced helpers shared by the script steps that wait on a GitHub Actions run: finding
# the repository, finding the push run of a commit or the run a dispatch started, waiting for a run
# to end, and reading how it ended. Not executable on its own, and sourced after step-lib.sh (it stops
# the step with `die`).
#
# Everything here only reads what GitHub says. Whether a red run is the change's own failure, another
# change's, or a flaky runner is a judgement, so a red run is written down (write_red_run) and handed
# back, never retried here.
#
# The waits are tuned by environment variables, each in seconds unless said otherwise:
#
#   CI_REPO            OWNER/REPO to point `gh` at, when resolve_repo is given none
#   CI_APPEAR_SECONDS  between two looks for a dispatched run to appear (5)
#   CI_APPEAR_LIMIT    looks before giving up on it appearing (60)
#   CI_PUSH_LIMIT      how long to look for a commit's push run before calling it missing (300)
#   CI_POLL_SECONDS    between two reads of a run being waited on (30)
#   CI_MISS_LIMIT      reads in a row that may fail before the wait is called broken (3)
#   CI_RERUN_LIMIT     how long a run may read completed while a job it carries has no conclusion (600)
#   CI_WAIT_LIMIT      how long a run may take before the wait gives up (empty: no limit)
#
# Every call goes through `gh` as PATH finds it, so a fake `gh` put first on PATH checks a step's ways
# out without reaching GitHub.

: "${CI_APPEAR_SECONDS:=5}" "${CI_APPEAR_LIMIT:=60}" "${CI_POLL_SECONDS:=30}" "${CI_MISS_LIMIT:=3}"
: "${CI_RERUN_LIMIT:=600}" "${CI_WAIT_LIMIT:=}" "${CI_PUSH_LIMIT:=300}"

command -v gh >/dev/null || die "gh is not installed, and the step reads GitHub Actions with it"

# resolve_repo [OWNER/REPO]: set repo to the repository named, else CI_REPO, else the repository of
# the current folder as gh sees it.
resolve_repo() {
    repo=${1:-${CI_REPO:-}}
    if [ -z "$repo" ]; then
        repo=$(gh repo view --json nameWithOwner --jq .nameWithOwner) ||
            die "no repository: run in a checkout of it, or set CI_REPO=OWNER/REPO"
    fi
    [[ "$repo" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || die "not a repository in the form OWNER/REPO: \"$repo\""
}

# An ISO-8601 UTC stamp, taken before a dispatch, for dispatched_run's not-before.
now_utc() { date -u +%Y-%m-%dT%H:%M:%SZ; }

# dispatched_run <workflow> <ref> <not-before>: print the id of the newest workflow_dispatch run of the
# workflow on the ref created at or after not-before, waiting for it to appear. A dispatch is accepted
# before its run is listed, so a run that is not there yet is looked for again; one that never shows
# up stops the step.
dispatched_run() {
    local workflow="$1" ref="$2" not_before="$3" tries=0 row id created
    while :; do
        row=$(gh run list -R "$repo" --workflow "$workflow" --branch "$ref" --event workflow_dispatch \
            --limit 1 --json databaseId,createdAt --jq '.[0] // empty | "\(.databaseId) \(.createdAt)"') ||
            die "could not list the runs of $workflow on $ref in $repo"
        id=${row%% *}
        created=${row##* }
        if [ -n "$row" ] && [ ! "$created" \< "$not_before" ]; then
            [[ "$id" =~ ^[0-9]+$ ]] || die "the newest run of $workflow on $ref has no id: \"$row\""
            echo "dispatched run of $workflow on $ref: $id (created $created)" >&2
            echo "$id"
            return 0
        fi
        tries=$((tries + 1))
        [ "$tries" -lt "$CI_APPEAR_LIMIT" ] ||
            die "no run of $workflow on $ref appeared in $repo after $((CI_APPEAR_LIMIT * CI_APPEAR_SECONDS))s"
        [ "$tries" = 1 ] && echo "waiting for the dispatched run of $workflow on $ref to appear" >&2
        sleep "$CI_APPEAR_SECONDS"
    done
}

# push_run <workflow> <full sha>: print the id of the newest push run of the workflow for the commit,
# looking again every CI_APPEAR_SECONDS until CI_PUSH_LIMIT has passed. A push is listed a while after
# it lands, so a run that is not there yet is looked for again; when none shows up, print nothing, and
# what to do without one is the caller's.
push_run() {
    local workflow="$1" sha="$2" started=$SECONDS said="" id
    while :; do
        id=$(gh run list -R "$repo" --workflow "$workflow" --commit "$sha" --event push \
            --limit 1 --json databaseId --jq '.[0].databaseId // empty') ||
            die "could not list the push runs of $workflow for $sha in $repo"
        if [ -n "$id" ]; then
            [[ "$id" =~ ^[0-9]+$ ]] || die "the push run of $workflow for $sha has no id: \"$id\""
            echo "push run of $workflow for $sha: $id" >&2
            echo "$id"
            return 0
        fi
        [ $((SECONDS - started)) -lt "$CI_PUSH_LIMIT" ] || {
            echo "no push run of $workflow for $sha appeared in $repo after ${CI_PUSH_LIMIT}s" >&2
            return 0
        }
        [ -n "$said" ] || echo "waiting for the push run of $workflow for $sha to appear" >&2
        said=1
        sleep "$CI_APPEAR_SECONDS"
    done
}

# watch_run <id>: wait until the run is over, and leave what GitHub last said of it in run_state (the
# JSON of `gh run view --json status,conclusion,url,jobs`). Over means completed with every job it
# carries holding a conclusion: right after a re-run, the run still reads completed with the previous
# attempt's conclusion while a job it restarted has none yet, and that window is waited out rather
# than read as a verdict. Reads that keep failing, a re-run window that does not close, and a run
# that outlasts CI_WAIT_LIMIT stop the step.
watch_run() {
    local id="$1" miss=0 started=$SECONDS restart_since="" said="" state status open line
    echo "waiting for run $id in $repo" >&2
    while :; do
        if ! state=$(gh run view "$id" -R "$repo" --json status,conclusion,url,jobs 2>&1); then
            miss=$((miss + 1))
            [ "$miss" -lt "$CI_MISS_LIMIT" ] ||
                die "could not read run $id in $repo $CI_MISS_LIMIT times in a row; the wait is broken: $state"
            sleep "$CI_POLL_SECONDS"
            continue
        fi
        miss=0
        jq -e 'type == "object"' <<< "$state" >/dev/null 2>&1 || die "gh gave no run for $id in $repo: $state"
        status=$(jq -r '.status // ""' <<< "$state")
        open=$(jq '[(.jobs // [])[] | select((.conclusion // "") == "")] | length' <<< "$state")
        line="run $id: $status, $open job(s) without a conclusion"
        [ "$line" = "$said" ] || echo "$line" >&2
        said=$line
        if [ "$status" = completed ]; then
            if [ "$open" = 0 ]; then
                run_state=$state
                return 0
            fi
            [ -n "$restart_since" ] || restart_since=$SECONDS
            [ $((SECONDS - restart_since)) -lt "$CI_RERUN_LIMIT" ] ||
                die "run $id read completed for ${CI_RERUN_LIMIT}s while a job it carries had no conclusion: $(run_url "$id")"
        else
            restart_since=""
        fi
        if [ -n "$CI_WAIT_LIMIT" ] && [ $((SECONDS - started)) -ge "$CI_WAIT_LIMIT" ]; then
            die "run $id was not over after ${CI_WAIT_LIMIT}s: $(run_url "$id")"
        fi
        sleep "$CI_POLL_SECONDS"
    done
}

# run_verdict <job name>: print green or red for the run watch_run waited on. The named job (the
# workflow's aggregate job) decides when the run carries it: success and skipped are green, any other
# conclusion is red. A run without it is decided by its own conclusion. A run with neither stops the
# step, as a run that ended without a verdict.
run_verdict() {
    local job="$1" conclusion
    conclusion=$(jq -r --arg j "$job" '[(.jobs // [])[] | select(.name == $j) | .conclusion][0] // ""' <<< "$run_state")
    [ -n "$conclusion" ] || conclusion=$(jq -r '.conclusion // ""' <<< "$run_state")
    case "$conclusion" in
        "") die "the run ended without a verdict: $(run_url)" ;;
        success | skipped) echo green ;;
        *) echo red ;;
    esac
}

# The URL of the run watch_run waited on, or of the id given before there is one.
run_url() {
    local url=""
    [ -n "${run_state:-}" ] && url=$(jq -r '.url // ""' <<< "$run_state")
    echo "${url:-https://github.com/$repo/actions/runs/${1:-}}"
}

# The jobs of the run watch_run waited on that did not end success, skipped or neutral, joined by ", ".
failed_jobs() {
    jq -r '[(.jobs // [])[] | select(.conclusion != "success" and .conclusion != "skipped" and .conclusion != "neutral")
        | "\(.name) (\(.conclusion))"] | join(", ")' <<< "$run_state"
}

# write_red_run <id>: what a red run leaves to go on, on stdout: its id and URL, the jobs that failed,
# and their failed log. A log that cannot be read is said in its place rather than stopping the step.
write_red_run() {
    local id="$1"
    echo "run: $id"
    echo "url: $(run_url "$id")"
    echo "failed jobs: $(failed_jobs)"
    echo
    gh run view "$id" -R "$repo" --log-failed 2>&1 || echo "(could not read the failed log of run $id)"
}
