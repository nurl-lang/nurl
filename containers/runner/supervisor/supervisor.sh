#!/usr/bin/env bash
# containers/runner/supervisor/supervisor.sh — keep RUNNER_SLOTS ephemeral
# self-hosted runners registered to a GitHub organization.
#
# Each slot is one container of the runner image, started with a
# just-in-time (JIT) config from POST /orgs/{org}/actions/runners/
# generate-jitconfig. A JIT runner takes exactly one job and is then
# deregistered by GitHub; its container exits, this loop logs how it ended,
# removes it (and its inner Docker volume), and starts a fresh one.
#
# The PAT is read from GITHUB_PAT_FILE on every call, so rotating it is a
# file write, not a restart. It needs only the organization permission
# "Self-hosted runners: Read and write".
set -uo pipefail

ORG="${GITHUB_ORG:?GITHUB_ORG is required}"
PAT_FILE="${GITHUB_PAT_FILE:-/run/secrets/github_pat}"
SLOTS="${RUNNER_SLOTS:-2}"
PREFIX="${RUNNER_NAME_PREFIX:-selfhosted}"
LABELS="${RUNNER_LABELS:-nurl-selfhosted}"
GROUP="${RUNNER_GROUP_ID:-1}"
IMAGE="${RUNNER_IMAGE:-nurl-runner:local}"
NET="${RUNNER_NETWORK:-nurl-runner}"
MIRROR="${DIND_REGISTRY_MIRROR:-}"
CPUS="${RUNNER_CPUS:-}"
MEMORY="${RUNNER_MEMORY:-}"
API=https://api.github.com

log() { printf '%s %s\n' "$(date -u +%FT%TZ)" "$*"; }
die() { log "FATAL: $*"; exit 1; }
pause() { sleep "$1" & wait $!; }   # interruptible by the TERM trap

# gh_api METHOD PATH [curl args…] — prints the response body; returns
# non-zero (and logs status and body) on a transport or HTTP error.
gh_api() {
    local method=$1 path=$2 out code
    shift 2
    out=$(curl -sS -X "$method" -w '\n%{http_code}' \
        -H "Authorization: Bearer $(tr -d '[:space:]' < "$PAT_FILE")" \
        -H 'Accept: application/vnd.github+json' \
        -H 'X-GitHub-Api-Version: 2022-11-28' \
        "$API$path" "$@") || { log "GitHub $method $path: request failed" >&2; return 1; }
    code=${out##*$'\n'}
    out=${out%$'\n'*}
    if [ "$code" -ge 300 ]; then
        log "GitHub $method $path → HTTP $code: $out" >&2
        return 1
    fi
    printf '%s' "$out"
}

# Every runner of the organization, one JSON object per line.
list_runners() {
    local page=1 out
    while :; do
        out=$(gh_api GET "/orgs/$ORG/actions/runners?per_page=100&page=$page") || return 1
        jq -c '.runners[]' <<< "$out"
        [ "$(jq '.runners | length' <<< "$out")" -lt 100 ] && return 0
        page=$((page + 1))
    done
}

# This supervisor's runners are named PREFIX-SLOT-EPOCH; nothing else is
# touched (other machines' runners, hand-registered ones).
OURS_RE="^${PREFIX}-[0-9]+-[0-9]+\$"

delete_runner() {   # NAME [RUNNERS-JSON-LINES]
    local name=$1 runners=${2:-} id
    [ -n "$runners" ] || runners=$(list_runners) || return 1
    id=$(jq -r --arg n "$name" 'select(.name == $n) | .id' <<< "$runners")
    [ -n "$id" ] || return 0
    gh_api DELETE "/orgs/$ORG/actions/runners/$id" > /dev/null
}

# Registrations of ours that are offline and have no container: left over
# from a crash, a reboot mid-job, or a container removed by hand.
sweep_stale() {
    local live runners id name
    live=$(docker ps -a --filter label=nurl.runner --format '{{.Label "nurl.runner.name"}}')
    runners=$(list_runners) || return 1
    jq -r --arg re "$OURS_RE" 'select((.name | test($re)) and .status == "offline" and (.busy | not)) | "\(.id) \(.name)"' \
        <<< "$runners" | while read -r id name; do
        grep -qxF "$name" <<< "$live" && continue
        gh_api DELETE "/orgs/$ORG/actions/runners/$id" > /dev/null && log "removed stale registration $name"
    done
}

# A slot container that has exited: say how, then remove it with its volume.
reap() {
    local c=$1 state code name
    state=$(docker container inspect -f '{{.State.Status}}' "$c" 2> /dev/null) || return 0
    case $state in exited | dead) ;; *) return 0 ;; esac
    code=$(docker container inspect -f '{{.State.ExitCode}}' "$c")
    name=$(docker container inspect -f '{{index .Config.Labels "nurl.runner.name"}}' "$c")
    if [ "$code" = 0 ]; then
        log "$c: $name finished"
    else
        log "$c: $name exited $code; its last lines:"
        docker logs --tail 40 "$c" 2>&1 | sed 's/^/    /'
        delete_runner "$name" || :
    fi
    docker rm -v "$c" > /dev/null
}

start_slot() {
    local i=$1 c="nurl-runner-slot-$1" name body jit
    name="$PREFIX-$i-$(date +%s)"
    body=$(jq -nc --arg n "$name" --argjson g "$GROUP" --arg l "$LABELS" \
        '{name: $n, runner_group_id: $g, work_folder: "_work",
          labels: ($l | split(",") | map(gsub("^\\s+|\\s+$"; "")) | map(select(length > 0)))}')
    jit=$(gh_api POST "/orgs/$ORG/actions/runners/generate-jitconfig" -d "$body" \
        | jq -er .encoded_jit_config) || return 1
    local args=(run -d --name "$c" --privileged --network "$NET"
        --label nurl.runner=1 --label "nurl.runner.slot=$i" --label "nurl.runner.name=$name"
        -e RUNNER_JITCONFIG="$jit")
    [ -n "$MIRROR" ] && args+=(-e "DIND_REGISTRY_MIRROR=$MIRROR")
    [ -n "$CPUS" ] && args+=(--cpus "$CPUS")
    [ -n "$MEMORY" ] && args+=(--memory "$MEMORY")
    if ! docker "${args[@]}" "$IMAGE" > /dev/null; then
        log "$c: docker run failed; withdrawing the registration $name"
        docker rm -f -v "$c" > /dev/null 2>&1
        delete_runner "$name" || :
        return 1
    fi
    log "$c: $name waiting for a job"
}

# Stop: idle runners go (container and registration); a runner in the
# middle of a job is left to finish it — its container exits on its own and
# the next start of the supervisor removes it.
shutdown() {
    log "stopping"
    local runners c name busy
    runners=$(list_runners) || runners=""
    for c in $(docker ps -a --filter label=nurl.runner --format '{{.Names}}'); do
        name=$(docker container inspect -f '{{index .Config.Labels "nurl.runner.name"}}' "$c" 2> /dev/null) || continue
        busy=$(jq -r --arg n "$name" 'select(.name == $n) | .busy' <<< "$runners")
        if [ "$busy" = true ]; then
            log "$c: $name is running a job; leaving it to finish"
            continue
        fi
        docker rm -f -v "$c" > /dev/null
        [ -n "$runners" ] && { delete_runner "$name" "$runners" || :; }
        log "$c: $name removed"
    done
    exit 0
}

# --- start ------------------------------------------------------------------

[[ $PREFIX =~ ^[A-Za-z0-9_-]+$ ]] || die "RUNNER_NAME_PREFIX '$PREFIX': letters, digits, _ and - only"
[[ $SLOTS =~ ^[0-9]+$ ]] || die "RUNNER_SLOTS '$SLOTS' is not a number"
[ -s "$PAT_FILE" ] || die "no PAT at $PAT_FILE (see containers/runner/README.md)"
docker image inspect "$IMAGE" > /dev/null 2>&1 || die "runner image $IMAGE is not built"
docker network inspect "$NET" > /dev/null 2>&1 || die "network $NET does not exist"

group=$(gh_api GET "/orgs/$ORG/actions/runner-groups/$GROUP") \
    || die "cannot read runner group $GROUP of $ORG — does the PAT have 'Self-hosted runners: Read and write' on $ORG?"
log "org $ORG, runner group '$(jq -r .name <<< "$group")' (id $GROUP), $SLOTS slot(s), labels $LABELS, names $PREFIX-*"
if [ "$(jq -r .allows_public_repositories <<< "$group")" != true ]; then
    log "WARNING: runner group '$(jq -r .name <<< "$group")' does not allow public repositories — jobs of a public repo will never be routed here"
fi

trap shutdown TERM INT

sweep_stale || :
last_sweep=$(date +%s)
backoff=5
while :; do
    for c in $(docker ps -a --filter label=nurl.runner --format '{{.Names}}'); do
        reap "$c"
    done
    for i in $(seq "$SLOTS"); do
        docker container inspect "nurl-runner-slot-$i" > /dev/null 2>&1 && continue
        if start_slot "$i"; then
            backoff=5
        else
            log "slot $i: could not start a runner; next try in ${backoff}s"
            pause "$backoff"
            backoff=$((backoff * 2 > 300 ? 300 : backoff * 2))
        fi
    done
    if [ $(($(date +%s) - last_sweep)) -ge 600 ]; then
        sweep_stale || :
        last_sweep=$(date +%s)
    fi
    pause 5
done
