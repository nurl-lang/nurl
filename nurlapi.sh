#!/usr/bin/env bash
# ============================================================
#  nurlapi.sh — build and run the pure-NURL playground container.
#
#  Stage 1: build the Docker image (compiles the NURL HTTP server
#  in `nurlapi/main.nu` + the NURL compiler + cross-compile
#  toolchains: WASI SDK, mingw-w64, zig).
#  Stage 2: run the container with port 8000 exposed.
#
#  After bring-up:
#    http://localhost:8000/         — playground UI (Monaco editor)
#    http://localhost:8000/health   — JSON liveness probe
#    http://localhost:8000/examples — bundled example listing
#
#  Equivalent to the Python `api/` container but with the entire
#  server written in NURL (`nurlapi/main.nu`); no Python at runtime.
#
#  Flags:
#    --no-cache   force a clean rebuild (don't reuse Docker layers)
#    --port=N     publish on host port N instead of 8000
#    --rm         pass --rm to docker run so the container is
#                 removed on exit (default: stays so logs survive)
#    --detach     run detached (-d) — print container id and exit
#    --build-only build the image, do not run the container
#    --help       show this message
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

IMAGE="nurlapi"
HOST_PORT=8000
NO_CACHE=""
RM_FLAG=""
DETACH_FLAG=""
BUILD_ONLY=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --no-cache)       NO_CACHE="--no-cache" ;;
        --rm)             RM_FLAG="--rm" ;;
        --detach|-d)      DETACH_FLAG="-d" ;;
        --build-only)     BUILD_ONLY=1 ;;
        --port=*)         HOST_PORT="${1#--port=}" ;;
        --help|-h)
            sed -n '2,30p' "$0"
            exit 0
            ;;
        *)
            echo "ERROR: unknown flag '$1' (try --help)" >&2
            exit 2
            ;;
    esac
    shift
done

echo "[nurlapi] building Docker image '$IMAGE'…"
echo "[nurlapi] (first build pulls WASI SDK + zig + builds static libcurl; ~10-15 min)"
docker build $NO_CACHE -t "$IMAGE" -f nurlapi/Dockerfile .
echo "[nurlapi] image built."

if [[ "$BUILD_ONLY" -eq 1 ]]; then
    echo "[nurlapi] --build-only: skipping run."
    exit 0
fi

echo "[nurlapi] starting container on host port $HOST_PORT → container 8000…"
exec docker run $RM_FLAG $DETACH_FLAG -p "${HOST_PORT}:8000" "$IMAGE"
