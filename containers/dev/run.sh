#!/usr/bin/env bash
# Copyright (c) 2026 The NURL Project Developers
# SPDX-License-Identifier: MIT OR Apache-2.0
# ============================================================
#  containers/dev/run.sh — open a shell in the dev container.
#
#  The image (containers/dev/Dockerfile) carries the toolchain;
#  this script carries the *wiring*: which host directories are
#  visible inside, which credentials are forwarded, and what
#  state survives the container being thrown away.
#
#  Usage:
#    ./containers/dev/run.sh                # interactive shell
#    ./containers/dev/run.sh claude         # straight into the agent
#    ./containers/dev/run.sh ./build.sh     # one-shot command
#
#  Flags (before the command):
#    --build          (re)build the image first
#    --rebuild        build with --no-cache
#    --name NAME      container name (default: nurl-dev)
#    --fresh          remove the existing container first
#    --seed-claude    copy the host's ~/.claude credentials in on
#                     first run, so the agent starts logged in
#    --root           run as root inside (package installs etc.)
#
#  What persists across runs (docker named volumes, so `docker rm`
#  does not lose them):
#    nurl-dev-claude   ~/.claude          agent auth + session state
#    nurl-dev-state    ~/.local/state     shell history
#    nurl-dev-cache    ~/.cache           npm/pip/cargo download caches
#    nurl-dev-nurl     ~/.nurl            installed NURL toolchain
#
#  What is NOT baked into the image and is forwarded from the host
#  instead, because it is a secret: the git identity, the gh token,
#  the ssh agent socket.
# ============================================================
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
IMAGE="${NURL_DEV_IMAGE:-nurllang/dev:latest}"
NAME="nurl-dev"
DO_BUILD=0
NO_CACHE=0
FRESH=0
SEED_CLAUDE=0
AS_ROOT=0

usage() { sed -n '4,36p' "${BASH_SOURCE[0]}" | sed 's/^#\{1,\} \{0,1\}//'; }

while [[ $# -gt 0 ]]; do
    case "$1" in
        --build)       DO_BUILD=1; shift ;;
        --rebuild)     DO_BUILD=1; NO_CACHE=1; shift ;;
        --name)        NAME="$2"; shift 2 ;;
        --fresh)       FRESH=1; shift ;;
        --seed-claude) SEED_CLAUDE=1; shift ;;
        --root)        AS_ROOT=1; shift ;;
        --help|-h)     usage; exit 0 ;;
        --)            shift; break ;;
        *)             break ;;
    esac
done

command -v docker >/dev/null 2>&1 || {
    echo "ERROR: docker not found on PATH." >&2
    exit 127
}

if [[ $DO_BUILD -eq 1 ]] || ! docker image inspect "$IMAGE" >/dev/null 2>&1; then
    echo ">> building $IMAGE (this takes a few minutes the first time)"
    build_args=(--build-arg "USER_UID=$(id -u)" --build-arg "USER_GID=$(id -g)")
    [[ $NO_CACHE -eq 1 ]] && build_args+=(--no-cache)
    docker build "${build_args[@]}" -t "$IMAGE" "$REPO_ROOT/containers/dev"
fi

# The command to run inside. Default is a login shell.
if [[ $# -eq 0 ]]; then
    CMD=(bash -l)
else
    CMD=("$@")
fi

if [[ $FRESH -eq 1 ]]; then
    docker rm -f "$NAME" >/dev/null 2>&1 || true
fi

# `docker run -it` without a terminal dies with "the input device is not
# a TTY", which is exactly how this script gets called from another
# script or an agent. Allocate a TTY only when there is one to allocate.
TTY_ARGS=(-i)
[[ -t 0 && -t 1 ]] && TTY_ARGS=(-it)

# An already-running container: attach a second shell to it rather than
# starting a rival one on the same bind mount.
if docker ps --format '{{.Names}}' | grep -qx "$NAME"; then
    echo ">> attaching to running container '$NAME'"
    exec_args=("${TTY_ARGS[@]}" -w /work)
    [[ $AS_ROOT -eq 1 ]] && exec_args+=(-u root)
    exec docker exec "${exec_args[@]}" "$NAME" "${CMD[@]}"
fi
# A stopped leftover of the same name would block `docker run`.
if docker ps -a --format '{{.Names}}' | grep -qx "$NAME"; then
    docker rm -f "$NAME" >/dev/null
fi

# Named volumes for the state that must outlive the container.
for v in claude state cache nurl; do
    docker volume create "nurl-dev-$v" >/dev/null
done

HOME_IN=/home/dev
[[ $AS_ROOT -eq 1 ]] && HOME_IN=/root

args=(
    --name "$NAME"
    --rm
    "${TTY_ARGS[@]}"
    --hostname nurl-dev
    -v "$REPO_ROOT:/work"
    -w /work
    -v "nurl-dev-claude:${HOME_IN}/.claude"
    -v "nurl-dev-state:${HOME_IN}/.local/state"
    -v "nurl-dev-cache:${HOME_IN}/.cache"
    -v "nurl-dev-nurl:${HOME_IN}/.nurl"
)

[[ $AS_ROOT -eq 1 ]] && args+=(-u root)

# ── Credentials, forwarded rather than baked ───────────────────────────

# git identity: read-only, so an accidental `git config --global` inside
# the container cannot rewrite the host's file.
[[ -f "$HOME/.gitconfig" ]] && args+=(-v "$HOME/.gitconfig:${HOME_IN}/.gitconfig:ro")

# gh: a token in the environment is the container-friendly form and beats
# mounting the host's credential store, which gh rewrites in place.
if [[ -n "${GH_TOKEN:-}" ]]; then
    args+=(-e "GH_TOKEN=${GH_TOKEN}")
elif [[ -n "${GITHUB_TOKEN:-}" ]]; then
    args+=(-e "GH_TOKEN=${GITHUB_TOKEN}")
elif command -v gh >/dev/null 2>&1 && tok="$(gh auth token 2>/dev/null)" && [[ -n "$tok" ]]; then
    args+=(-e "GH_TOKEN=${tok}")
fi

# ssh-agent, for git-over-ssh and signed commits. Forwarding the socket
# keeps the private key itself on the host.
if [[ -n "${SSH_AUTH_SOCK:-}" && -S "${SSH_AUTH_SOCK}" ]]; then
    args+=(-v "${SSH_AUTH_SOCK}:/ssh-agent" -e "SSH_AUTH_SOCK=/ssh-agent")
fi
[[ -d "$HOME/.ssh" ]] && args+=(-v "$HOME/.ssh:${HOME_IN}/.ssh:ro")

# An API key in the environment is honoured by Claude Code as-is; a
# subscription login instead lives in the ~/.claude volume.
[[ -n "${ANTHROPIC_API_KEY:-}" ]] && args+=(-e "ANTHROPIC_API_KEY=${ANTHROPIC_API_KEY}")

# --seed-claude mounts the host's credentials at /seed and copies them in
# without clobbering (`cp -n`), so it is a no-op on later runs.
if [[ $SEED_CLAUDE -eq 1 && -d "$HOME/.claude" ]]; then
    echo ">> seeding ~/.claude from the host (existing files are kept)"
    args+=(-v "$HOME/.claude:/seed/.claude:ro")
    printf -v inner '%q ' "${CMD[@]}"
    CMD=(bash -lc "cp -rn /seed/.claude/. \"\$HOME/.claude/\" 2>/dev/null || true; exec ${inner}")
fi

# ── QEMU acceleration ──────────────────────────────────────────────────
# The unikernel boot tests run far faster with KVM. Only offered when the
# host actually exposes /dev/kvm; without it QEMU falls back to TCG and
# everything still works, just slower.
if [[ -r /dev/kvm && -w /dev/kvm ]]; then
    args+=(--device /dev/kvm)
fi

# ptrace, for gdb/strace/valgrind on a build inside the container.
# Narrower than --privileged: it grants the debugger capability and the
# syscall surface those tools need, and nothing else.
args+=(--cap-add=SYS_PTRACE --security-opt seccomp=unconfined)

exec docker run "${args[@]}" "$IMAGE" "${CMD[@]}"
