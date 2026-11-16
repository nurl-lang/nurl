# containers/runner/runner/Dockerfile — one ephemeral self-hosted runner.
#
# The supervisor (../supervisor) starts one container of this image per
# job slot, hands it a just-in-time runner config, and throws it away when
# the job is done: every job starts from this image, nothing a job leaves
# behind reaches the next one.
#
# The container runs its own dockerd (Docker-in-Docker, so it is started
# --privileged). ci.yml's heavy jobs run inside `container:
# nurllang/ci:…`, and a runner can only start a job container through a
# Docker daemon it can reach. The job gets that inner daemon's socket — it
# never sees the host's daemon, the supervisor, or the PAT the supervisor
# registers runners with.
#
# Jobs that run on the runner itself (no `container:`) see this image, so
# it carries what those steps assume from GitHub's ubuntu-latest: git, gh,
# curl, jq, python3, build-essential, zstd, sudo. The compiler toolchain
# lives in nurllang/ci, not here.
FROM ubuntu:24.04

ARG DEBIAN_FRONTEND=noninteractive

RUN apt-get update -qq && apt-get install -y --no-install-recommends \
        build-essential \
        ca-certificates \
        curl \
        docker-buildx \
        docker.io \
        file \
        gh \
        git \
        gnupg \
        iproute2 \
        iptables \
        jq \
        lsb-release \
        python3 \
        python3-pip \
        rsync \
        sudo \
        tini \
        unzip \
        wget \
        xz-utils \
        zip \
        zstd \
    && rm -rf /var/lib/apt/lists/*

# The runner user matches GitHub's hosted runner (uid 1001, passwordless
# sudo), so a step's `sudo …` behaves the same. It is in the docker group
# for the inner daemon's socket.
RUN useradd -m -u 1001 -s /bin/bash runner \
    && usermod -aG docker runner \
    && echo 'runner ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/runner \
    && chmod 0440 /etc/sudoers.d/runner

# The runner release. Empty RUNNER_VERSION = the latest release, resolved
# through the releases/latest redirect (no API call, no rate limit). The
# layer is cached: `docker compose build --no-cache runner-image` picks up
# a newer runner. An outdated runner also updates itself when GitHub asks.
ARG RUNNER_VERSION=
RUN set -eux; \
    v="${RUNNER_VERSION}"; \
    if [ -z "$v" ]; then \
        v="$(curl -fsSLI -o /dev/null -w '%{url_effective}' https://github.com/actions/runner/releases/latest)"; \
        v="${v##*/v}"; \
    fi; \
    mkdir -p /home/runner/actions-runner; \
    curl -fsSL "https://github.com/actions/runner/releases/download/v${v}/actions-runner-linux-x64-${v}.tar.gz" \
        | tar -xz -C /home/runner/actions-runner; \
    apt-get update -qq; \
    /home/runner/actions-runner/bin/installdependencies.sh; \
    rm -rf /var/lib/apt/lists/*; \
    chown -R runner:runner /home/runner; \
    echo "actions/runner ${v}" > /etc/nurl-runner-version

COPY entrypoint.sh /usr/local/bin/nurl-runner-entrypoint
RUN chmod 0755 /usr/local/bin/nurl-runner-entrypoint

# The inner daemon's images and containers. Must not be the container's
# overlay root (overlay2 on overlay does not work), so it is a volume —
# anonymous, removed with the container.
VOLUME /var/lib/docker

ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/nurl-runner-entrypoint"]
