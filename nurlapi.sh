#!/usr/bin/env bash
# ============================================================
#  nurlapi.sh — build and run the pure-NURL playground container.
#
#  Default flow:
#    Stage 1: build the Docker image (compiles the NURL HTTP server
#    in `nurlapi/main.nu` + the NURL compiler + cross-compile
#    toolchains: WASI SDK, mingw-w64, zig).  ~10-15 min first time,
#    seconds on rebuilds (Docker layer cache).
#    Stage 2: run the container with port 8000 exposed.
#    The image is self-contained — exactly mirrors prod.
#
#  Dev-iteration flow (`bind` subcommand):
#    Stage 1: compile `nurlapi/main.nu` locally with `./nurl.sh`
#             (~30 s, no Docker).
#    Stage 2: run the *existing* `nurlapi` image with the local
#             binary + stdlib + docs + examples + compiler/tests
#             + bootstrap nurlc bind-mounted into the container.
#             Skips the Docker build entirely.
#
#    Requires the image to already exist (run `./nurlapi.sh
#    --build-only` once first). Iterate by editing `.nu` sources
#    and re-running `./nurlapi.sh bind`.
#
#  After bring-up:
#    http://localhost:8000/         — playground UI (Monaco editor)
#    http://localhost:8000/health   — JSON liveness probe
#    http://localhost:8000/examples — bundled example listing
#
#  Equivalent to the Python `api/` container but with the entire
#  server written in NURL (`nurlapi/main.nu`); no Python at runtime.
#
#  Usage:
#    ./nurlapi.sh              # full Docker build + run (prod-mirror)
#    ./nurlapi.sh bind         # fast local-binary + bind-mount run
#    ./nurlapi.sh bind --port=8000
#    ./nurlapi.sh --build-only # build image, no run
#
#  Flags:
#    --no-cache    force a clean rebuild (don't reuse Docker layers)
#    --port=N      publish on host port N instead of 8000
#    --rm          pass --rm to docker run so the container is
#                  removed on exit (default: stays so logs survive)
#    --detach, -d  run detached — print container id and exit
#    --build-only  build the image, do not run the container
#    --name=NAME   docker container name (default: nurlapi)
#    --help, -h    show this message
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

IMAGE="nurllang/nurl"
HOST_PORT=8000
NO_CACHE=""
RM_FLAG=""
DETACH_FLAG=""
BUILD_ONLY=0
MODE="prod"           # prod (full Docker build+run) | bind (local compile + bind-mount run)
CONTAINER_NAME="nurlapi"

# Subcommand: `bind` must be the first positional arg if present.
if [[ "${1-}" == "bind" ]]; then
    MODE="bind"
    shift
fi

while [[ $# -gt 0 ]]; do
    case "$1" in
        --no-cache)       NO_CACHE="--no-cache" ;;
        --rm)             RM_FLAG="--rm" ;;
        --detach|-d)      DETACH_FLAG="-d" ;;
        --build-only)     BUILD_ONLY=1 ;;
        --port=*)         HOST_PORT="${1#--port=}" ;;
        --name=*)         CONTAINER_NAME="${1#--name=}" ;;
        --help|-h)
            sed -n '2,52p' "$0"
            exit 0
            ;;
        *)
            echo "ERROR: unknown flag '$1' (try --help)" >&2
            exit 2
            ;;
    esac
    shift
done

# ── bind mode: compile locally + reuse existing image ──────────────
if [[ "$MODE" == "bind" ]]; then
    if [[ "$BUILD_ONLY" -eq 1 ]]; then
        echo "ERROR: --build-only is meaningless with 'bind' (bind never builds the image)." >&2
        exit 2
    fi
    if ! docker image inspect "$IMAGE" >/dev/null 2>&1; then
        cat >&2 <<EOF
ERROR: image '$IMAGE' not found. Build it once with:
    ./nurlapi.sh --build-only
then re-run './nurlapi.sh bind' to iterate fast.
EOF
        exit 1
    fi
    if [[ ! -x "$SCRIPT_DIR/build/nurlc" ]]; then
        echo "ERROR: build/nurlc missing — run ./build.sh first." >&2
        exit 1
    fi

    LOCAL_BIN="$SCRIPT_DIR/build/nurlapi.bind"
    echo "[nurlapi/bind] compiling nurlapi/main.nu → $LOCAL_BIN…"
    "$SCRIPT_DIR/nurl.sh" "$SCRIPT_DIR/nurlapi/main.nu" "$LOCAL_BIN"

    # Rebuild stdlib/runtime.wasm.o from the host's stdlib/runtime.c when
    # it's newer than the cached object. The Docker image bakes a
    # runtime.wasm.o, but it freezes the runtime.c shipped at build time;
    # local edits to stdlib/runtime.c (new C stubs, WASI fixes, etc) need
    # to flow in to avoid `wasm-ld: undefined symbol: nurl_*` at link
    # time. We compile inside a throwaway container that already has
    # wasi-sdk so the host doesn't need its own toolchain.
    RUNTIME_C="$SCRIPT_DIR/stdlib/runtime.c"
    RUNTIME_WASM="$SCRIPT_DIR/stdlib/runtime.wasm.o.bind"
    if [[ "$RUNTIME_C" -nt "$RUNTIME_WASM" ]]; then
        echo "[nurlapi/bind] rebuilding stdlib/runtime.wasm.o (wasi target)…"
        docker run --rm \
            -v "$RUNTIME_C:/src/runtime.c:ro" \
            -v "$SCRIPT_DIR/stdlib:/dst" \
            --entrypoint /opt/wasi-sdk/bin/clang \
            "$IMAGE" \
            --target=wasm32-wasi -O2 -c /src/runtime.c -o /dst/runtime.wasm.o.bind
    fi

    # Stop any previous bind-mode container with the same name.
    if docker ps -a --format '{{.Names}}' | grep -qx "$CONTAINER_NAME"; then
        echo "[nurlapi/bind] removing previous container '$CONTAINER_NAME'…"
        docker rm -f "$CONTAINER_NAME" >/dev/null
    fi

    echo "[nurlapi/bind] starting '$CONTAINER_NAME' on host port $HOST_PORT → container 8000"
    echo "[nurlapi/bind] bind-mounts: binary, static, stdlib, examples, tests, docs, build/nurlc"

    # Build a single `docker run` invocation. Each source we want hot-
    # reloadable becomes a :ro bind mount over the path the image
    # already populates from /src.
    exec docker run \
        --name "$CONTAINER_NAME" \
        $RM_FLAG ${DETACH_FLAG:-} \
        -p "${HOST_PORT}:8000" \
        -v "$LOCAL_BIN:/app/nurlapi:ro" \
        -v "$SCRIPT_DIR/nurlapi/static:/app/static:ro" \
        -v "$SCRIPT_DIR/build/nurlc:/opt/nurl/build/nurlc:ro" \
        -v "$SCRIPT_DIR/stdlib/core:/opt/nurl/stdlib/core:ro" \
        -v "$SCRIPT_DIR/stdlib/std:/opt/nurl/stdlib/std:ro" \
        -v "$SCRIPT_DIR/stdlib/ext:/opt/nurl/stdlib/ext:ro" \
        -v "$RUNTIME_WASM:/opt/nurl/stdlib/runtime.wasm.o:ro" \
        -v "$SCRIPT_DIR/examples:/opt/nurl/examples:ro" \
        -v "$SCRIPT_DIR/compiler/tests:/opt/nurl/compiler/tests:ro" \
        -v "$SCRIPT_DIR/README.md:/opt/nurl/README.md:ro" \
        -v "$SCRIPT_DIR/ROADMAP.md:/opt/nurl/ROADMAP.md:ro" \
        -v "$SCRIPT_DIR/docs/GOTCHAS.md:/opt/nurl/docs/GOTCHAS.md:ro" \
        -v "$SCRIPT_DIR/LICENSE-MIT:/opt/nurl/LICENSE-MIT:ro" \
        -v "$SCRIPT_DIR/LICENSE-APACHE:/opt/nurl/LICENSE-APACHE:ro" \
        -v "$SCRIPT_DIR/NOTICE:/opt/nurl/NOTICE:ro" \
        -v "$SCRIPT_DIR/spec:/opt/nurl/spec:ro" \
        "$IMAGE"
fi

# ── prod mode (default): full Docker build + run ────────────────────
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
