#!/usr/bin/env bash
# ============================================================
#  unikernel/k8s/build_image.sh — build the unikernel, then wrap it in
#  a container image.
#
#  Usage: unikernel/k8s/build_image.sh [-t repo:tag] [--push]
#
#  The default tag is unqualified on purpose: it stays on the local
#  Docker daemon, which is what `docker run` and `kind load
#  docker-image` want. Pushing anywhere means naming a registry:
#      build_image.sh -t registry.example.com/you/nurl-unikernel-httpd:0.1.0 --push
#
#  Two steps, in order, because the second one has nothing to do with
#  NURL: build_unikernel.sh turns server.nu into a bootable ELF, and
#  docker puts that ELF next to a hypervisor. Skipping the first is how
#  you ship yesterday's guest, so this script always does both.
# ============================================================
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HERE="$ROOT/unikernel/k8s"
TAG="${TAG:-nurl-unikernel-httpd:0.1.0}"
PUSH=""

while [ $# -gt 0 ]; do
    case "$1" in
        -t) TAG="$2"; shift 2 ;;
        --push) PUSH=1; shift ;;
        *) echo "usage: build_image.sh [-t repo:tag] [--push]" >&2; exit 2 ;;
    esac
done

ELF="${NURL_UNIKERNEL_OUT:-$ROOT/build/unikernel}/k8sd.elf"
"$ROOT/unikernel/build_unikernel.sh" "$HERE/server.nu" -o "$ELF"

# A context of exactly the two files that go into the image. The
# repository's .dockerignore excludes build/, and a two-file context
# is also a faster and more truthful build than sending the tree.
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
cp "$ELF" "$STAGE/server.elf"
cp "$HERE/entrypoint.sh" "$STAGE/entrypoint.sh"
chmod 0755 "$STAGE/entrypoint.sh"

docker build --platform linux/amd64 -f "$HERE/Dockerfile" -t "$TAG" "$STAGE"
echo "built $TAG ($(du -h "$ELF" | cut -f1) guest)"

if [ -n "$PUSH" ]; then
    docker push "$TAG"
fi
