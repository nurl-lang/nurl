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
TLS=""

while [ $# -gt 0 ]; do
    case "$1" in
        -t) TAG="$2"; shift 2 ;;
        --push) PUSH=1; shift ;;
        --tls) TLS=1; shift ;;
        *) echo "usage: build_image.sh [-t repo:tag] [--push]" >&2; exit 2 ;;
    esac
done

ELF="${NURL_UNIKERNEL_OUT:-$ROOT/build/unikernel}/k8sd.elf"

# --tls bakes a certificate into the image's read-only filesystem, and
# the guest then serves TLS 1.3 out of `stdlib/std/tls.nu` — pure NURL,
# no libssl, which is why it links into a machine with no operating
# system at all.
#
# The key is P-256 and that is not a preference. Measured in the guest,
# same image, same handshake, only the server key's type differing:
# RSA-2048 costs ~490 ms per handshake, P-256 costs 4-11 ms. Ninety
# times, and it is the difference between a TLS endpoint and a
# demonstration that TLS is possible.
#
# Self-signed and generated per build, so every image has its own
# identity and no private key is ever committed. A deployment that
# needs a real certificate mounts one and points `cert=`/`key=` at it.
FSARG=""
if [ -n "$TLS" ]; then
    command -v openssl >/dev/null 2>&1 || { echo "build_image.sh: --tls needs openssl" >&2; exit 2; }
    TLSDIR="$(mktemp -d)"
    trap 'rm -rf "$TLSDIR"' EXIT
    mkdir -p "$TLSDIR/etc/tls"
    openssl ecparam -name prime256v1 -genkey -noout -out "$TLSDIR/etc/tls/key.pem" 2>/dev/null
    openssl req -x509 -new -key "$TLSDIR/etc/tls/key.pem" -out "$TLSDIR/etc/tls/cert.pem" \
            -days 3650 -subj "/CN=nurl-unikernel" 2>/dev/null
    FSARG="--fs $TLSDIR"
fi

"$ROOT/unikernel/build_unikernel.sh" $FSARG "$HERE/server.nu" -o "$ELF"

# A context of exactly the two files that go into the image. The
# repository's .dockerignore excludes build/, and a two-file context
# is also a faster and more truthful build than sending the tree.
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE" "${TLSDIR:-}"' EXIT
cp "$ELF" "$STAGE/server.elf"
cp "$HERE/entrypoint.sh" "$STAGE/entrypoint.sh"
chmod 0755 "$STAGE/entrypoint.sh"

docker build --platform linux/amd64 -f "$HERE/Dockerfile" -t "$TAG" "$STAGE"
echo "built $TAG ($(du -h "$ELF" | cut -f1) guest)"

if [ -n "$PUSH" ]; then
    docker push "$TAG"
fi
