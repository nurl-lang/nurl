#!/usr/bin/env bash
# ============================================================
#  unikernel/k8s/build_static_image.sh — the same server, with the
#  node's kernel underneath it instead of a machine of its own.
#
#  Usage: build_static_image.sh [-t repo:tag] [--push]
#
#  Default tag is unqualified — local daemon only. Name a registry to
#  push:  -t registry.example.com/you/nurl-static-httpd:0.1.0 --push
#
#  `build_image.sh` produces a bootable image and a container that
#  carries a hypervisor to boot it. This produces a static Linux binary
#  and a container that carries nothing else at all. The NURL source is
#  byte-identical; what changes is what answers the socket calls — the
#  pure-NURL TCP stack over virtio-net there, the node's kernel here.
#
#  The link is spelled out rather than delegated to `nurl.sh`, which
#  has no hook for link flags. The cost of that is real and worth
#  knowing: this bypasses nurl.sh's ThinLTO setup and its feature-lib
#  probing, so the binary is a plain -O2 static link.
#
#  GLIBC STATIC + NSS: the link warns about `getaddrinfo`, `getpwuid`
#  and `getgrgid` — those resolve through dlopen'd NSS modules, which a
#  static binary has no loader for. This server calls none of them, so
#  the warning is accurate and harmless HERE; a program that resolves a
#  name would fail at runtime rather than at link time. Building
#  against musl (`zig cc -target x86_64-linux-musl`) removes the trap
#  rather than dodging it, and is the right move if this stops being a
#  proof of concept.
# ============================================================
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HERE="$ROOT/unikernel/k8s"
CC="${CC:-clang}"
TAG="${TAG:-nurl-static-httpd:0.1.0}"
PUSH=""
OUTDIR="${NURL_STATIC_OUT:-$ROOT/build/k8s-static}"

while [ $# -gt 0 ]; do
    case "$1" in
        -t) TAG="$2"; shift 2 ;;
        --push) PUSH=1; shift ;;
        *) echo "usage: build_static_image.sh [-t repo:tag] [--push]" >&2; exit 2 ;;
    esac
done

[ -x "$ROOT/build/nurlc" ] || { echo "build_static_image.sh: no build/nurlc — run ./build.sh" >&2; exit 2; }
mkdir -p "$OUTDIR"

# nurlc writes IR to stdout; the redirect is the output file.
"$ROOT/build/nurlc" "$HERE/server.nu" > "$OUTDIR/server.ll"
# stderr kept: the NSS warnings above are the ones worth reading.
"$CC" -O2 -static -o "$OUTDIR/server.dbg" "$OUTDIR/server.ll" \
      "$ROOT/stdlib/runtime.c" -lm -lpthread
strip -s "$OUTDIR/server.dbg" -o "$OUTDIR/server"

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
cp "$OUTDIR/server" "$STAGE/server"
cp "$HERE/Dockerfile.static" "$STAGE/Dockerfile"

docker build --platform linux/amd64 -t "$TAG" "$STAGE"
echo "built $TAG ($(du -h "$OUTDIR/server" | cut -f1) binary, and the image is that plus nothing)"

[ -n "$PUSH" ] && docker push "$TAG"
exit 0
