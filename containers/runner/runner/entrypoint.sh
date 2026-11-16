#!/usr/bin/env bash
# containers/runner/runner/entrypoint.sh — start the inner dockerd, then
# run exactly one job with the just-in-time config the supervisor passed.
#
# Runs as root (dockerd needs it); the runner itself runs as `runner`.
# When the job is done, run.sh exits, and so does the container.
set -euo pipefail

log() { printf '%s [entrypoint] %s\n' "$(date -u +%FT%TZ)" "$*" >&2; }

jit="${RUNNER_JITCONFIG:-}"
unset RUNNER_JITCONFIG
if [ -z "$jit" ]; then
    log "RUNNER_JITCONFIG is empty: this image is started by the supervisor, which passes one"
    exit 2
fi

# cgroup v2 nesting, as moby's hack/dind does it: move every process out of
# the root cgroup and enable the controllers for children, or the inner
# daemon cannot create cgroups for job containers.
if [ -f /sys/fs/cgroup/cgroup.controllers ]; then
    mkdir -p /sys/fs/cgroup/init
    xargs -rn1 < /sys/fs/cgroup/cgroup.procs > /sys/fs/cgroup/init/cgroup.procs 2>/dev/null || :
    sed -e 's/ / +/g' -e 's/^/+/' < /sys/fs/cgroup/cgroup.controllers \
        > /sys/fs/cgroup/cgroup.subtree_control
fi
if [ -d /sys/kernel/security ] && ! mountpoint -q /sys/kernel/security; then
    mount -t securityfs none /sys/kernel/security || :
fi

# Image pulls go through the compose stack's pull-through cache when one is
# configured, so a fresh container does not fetch nurllang/ci from Docker
# Hub on every job.
mkdir -p /etc/docker
if [ -n "${DIND_REGISTRY_MIRROR:-}" ]; then
    host="${DIND_REGISTRY_MIRROR#*://}"
    host="${host%%/*}"
    jq -n --arg m "$DIND_REGISTRY_MIRROR" --arg h "$host" \
        '{"registry-mirrors": [$m], "insecure-registries": [$h]}' > /etc/docker/daemon.json
else
    echo '{}' > /etc/docker/daemon.json
fi

dockerd > /var/log/dockerd.log 2>&1 &
for _ in $(seq 120); do
    docker info > /dev/null 2>&1 && break
    sleep 0.5
done
if ! docker info > /dev/null 2>&1; then
    log "the inner dockerd did not come up; its log:"
    cat /var/log/dockerd.log >&2
    exit 1
fi
chgrp docker /var/run/docker.sock

log "$(cat /etc/nurl-runner-version), docker $(docker version --format '{{.Server.Version}}')"
cd /home/runner/actions-runner
exec setpriv --reuid=runner --regid=runner --init-groups \
    env HOME=/home/runner USER=runner LOGNAME=runner \
    ./run.sh --jitconfig "$jit"
