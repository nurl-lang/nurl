#!/usr/bin/env bash
# Copyright (c) 2026 The NURL Project Developers
# SPDX-License-Identifier: MIT OR Apache-2.0
# Dual-licensed under MIT (LICENSE-MIT) or Apache-2.0 (LICENSE-APACHE) at your option.
# ============================================================
#  build.sh — bootstrap the NURL compiler and run the test
#             suite.  On full success, prints a single line:
#
#                 BUILD SUCCESS & TESTS PASSED
#
#  On any failure, the full build log or test-runner diff is
#  printed so the cause is visible.
#
#  Flags:
#    --no-tests  Skip the test suite at the end (Docker images, CI
#                stages that test elsewhere). Bootstrap fixed point
#                still has to hold or the build fails.
#    --refresh-bootstrap
#                Copy `compiler/nurlc.nu` → `compiler/nurlc_lastgood.nu`
#                and regenerate `compiler/nurlc_lastgood.ll` from it
#                using the EXISTING `build/nurlc`. Required when a
#                grammar / runtime-ABI change leaves the committed
#                bootstrap snapshot unable to compile current nurlc.nu.
#                The build then proceeds normally with the new
#                snapshot. Commit both `.nu` and `.ll` files together.
#    --san       Build runtime.o + every stage binary with
#                AddressSanitizer + UndefinedBehaviorSanitizer. Catches
#                use-after-free, double-free, OOB reads/writes, integer
#                overflow, null deref, etc. that the conservative
#                single-owner / auto-drop model cannot statically rule
#                out. ~3× slower at runtime; off by default. Exports
#                NURL_SAN=1 so run_tests.sh / nurl.sh / tools build
#                scripts pick up the same flags transparently.
#                Use ASAN_OPTIONS=detect_leaks=1 to enable leak checks
#                (off by default because some intentional stdlib globals
#                live until process exit).
# ============================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Wall-clock timers (bash $SECONDS, integer). BUILD_T0 marks the start of
# the whole build; TEST_T0 is set just before the test runner. fmt_dur
# renders seconds as "1m 20s" / "12s" for the summary line.
BUILD_T0=$SECONDS
fmt_dur() {
    local s=$1
    if (( s >= 60 )); then printf '%dm %02ds' $(( s / 60 )) $(( s % 60 ))
    else printf '%ds' "$s"; fi
}

RUN_TESTS=1
SAN=0
REFRESH_BOOTSTRAP=0
while [[ $# -gt 0 ]]; do
    case "$1" in
        --no-tests)          RUN_TESTS=0; shift ;;
        --san)               SAN=1; shift ;;
        --refresh-bootstrap) REFRESH_BOOTSTRAP=1; shift ;;
        *) echo "unknown arg: $1" >&2; exit 2 ;;
    esac
done

# Sanitized builds skip the standard baseline-diff test runner — the
# baseline assumes plain output, and sanitizer reports would balloon
# it. The dedicated runner ./compiler/tests/run_san_tests.sh handles
# the sanitized corpus separately.
if (( SAN == 1 )); then
    RUN_TESTS=0
fi

# Sanitizer toolchain. -fno-omit-frame-pointer keeps stack traces
# readable; -fno-sanitize-recover=all turns soft UBSan diagnostics into
# hard fail-on-detection (so a single overflow exits the test binary
# instead of just printing to stderr); -fsanitize-address-use-after-scope
# catches use-after-scope on stack allocas, which matches NURL's
# closure-captures-stack-alloca pattern that we want to break loudly.
SAN_CFLAGS=""
SAN_LDFLAGS=""
if (( SAN == 1 )); then
    SAN_CFLAGS="-fsanitize=address,undefined -fsanitize-address-use-after-scope -fno-omit-frame-pointer -fno-sanitize-recover=all"
    SAN_LDFLAGS="-fsanitize=address,undefined"
    # LTO and sanitizers are theoretically compatible but in practice
    # clang's combination produces opaque link-time diagnostics for
    # NURL's pattern of cross-module function pointers. Disable LTO in
    # sanitized builds — the runtime/user-code inline win we lose isn't
    # the point of a san run anyway (we're after correctness, not perf).
    NO_LTO_IN_SAN=1
    export NURL_SAN=1
    # Disable LSan during the BUILD itself: nurlc_lastgood.bin / nurlc_self run
    # to completion and exit without freeing their str-pool / sym-arena
    # globals (an intentional process-lifetime allocation strategy).
    # LSan would flag every one as a leak and tank the build with
    # exit-1-on-detect. run_san_tests.sh re-enables leak detection on
    # demand via LSAN_DETECT_LEAKS=1 for the test corpus, where the
    # release-and-cleanup discipline is meaningfully different.
    export ASAN_OPTIONS="detect_leaks=0:abort_on_error=0:halt_on_error=0:print_stacktrace=1"
    export UBSAN_OPTIONS="print_stacktrace=1:halt_on_error=0"
else
    NO_LTO_IN_SAN=0
fi

# Helper that mints the right `-flto` or `-fno-lto` flag depending on
# sanitizer mode. Used in every clang invocation that compiles or links
# runtime.o-consuming code.
if (( NO_LTO_IN_SAN == 1 )); then
    LTO_FLAG=""
else
    LTO_FLAG="-flto"
fi

LOG="$(mktemp)"
trap 'rm -f "$LOG"' EXIT

fail() {
    echo "BUILD FAILED: $1"
    echo "===================================================="
    cat "$LOG"
    exit 1
}

log()  { echo "$*" >> "$LOG"; }
step() {
    local label="$1"; shift
    log ""
    log "[$label] $*"
    "$@" >> "$LOG" 2>&1 || fail "$label"
}

# ── Locate clang ─────────────────────────────────────────────
CLANG="clang"
if ! command -v clang &>/dev/null; then
    for candidate in /usr/lib/llvm/bin/clang /usr/local/bin/clang; do
        if [ -x "$candidate" ]; then CLANG="$candidate"; break; fi
    done
    if ! command -v "$CLANG" &>/dev/null; then
        echo "ERROR: clang not found"; exit 1
    fi
fi

mkdir -p build

# ── HTTP transport ───────────────────────────────────────────
# The HTTP client is pure NURL now (stdlib/ext/http_pure.nu over the
# libc TCP socket + the pure TLS stack); no libcurl, no link flag.
rm -f stdlib/runtime.curl
CURL_CFLAGS=""
CURL_LIBS=""

# ── libssl: REMOVED (§8 P4) ──────────────────────────────────
# All TLS — client AND server, handshake + record layer + X.509 — is
# now pure NURL (stdlib/std/tls.nu, tls_server.nu, and the crypto in
# stdlib/std/*). The runtime no longer touches OpenSSL, so the default
# build links neither -lssl nor -lcrypto and NURL_HAVE_OPENSSL is never
# defined. The dead #ifdef NURL_HAVE_OPENSSL blocks in runtime.c are
# retained only as historical reference and compile out unconditionally.
OPENSSL_CFLAGS=""
OPENSSL_LIBS=""
rm -f stdlib/runtime.openssl

# ── libsqlite3 detection ─────────────────────────────────────
# Same pattern as libcurl / openssl. With sqlite3 present, the
# runtime's `nurl_sqlite_*` bridge compiles in; without it, the
# symbols still exist but every call returns SqliteUnsupported and
# the link line skips -lsqlite3.
SQLITE3_CFLAGS=""
SQLITE3_LIBS=""
if pkg-config --exists sqlite3 2>/dev/null; then
    SQLITE3_CFLAGS="-DNURL_HAVE_SQLITE3 $(pkg-config --cflags sqlite3)"
    SQLITE3_LIBS="$(pkg-config --libs sqlite3)"
    echo 1 > stdlib/runtime.sqlite3
    log "[info] sqlite3 detected — SQLite FFI enabled"
else
    rm -f stdlib/runtime.sqlite3
    log "[info] sqlite3 not found — stdlib/ext/sqlite.nu will return SqliteUnsupported"
fi

# ── libpq: removed (§8 P5) ───────────────────────────────────
# PostgreSQL is served by the pure-NURL `psql` package (packages/psql),
# which needs no libpq and no OpenSSL. The former libpq FFI wrapper
# (stdlib/ext/postgres.nu) and its -lpq link were dropped; clean up any
# stale sentinel from an earlier build.
rm -f stdlib/runtime.pq

# ── DEFLATE / gzip / zlib ───────────────────────────────────
# stdlib/ext/compress.nu (zlib_*, gzip_*, raw_deflate/inflate_*) and
# zip/tar are pure NURL over stdlib/std/deflate.nu now — no libz, no link
# flag.
rm -f stdlib/runtime.z
ZLIB_CFLAGS=""
ZLIB_LIBS=""

# ── libzstd detection ──────────────────────────────────────
ZSTD_LIBS=""
if pkg-config --exists libzstd 2>/dev/null; then
    ZSTD_LIBS="$(pkg-config --libs libzstd)"
    echo 1 > stdlib/runtime.zstd
    log "[info] libzstd detected — Zstd FFI enabled"
else
    rm -f stdlib/runtime.zstd
    log "[info] libzstd not found — stdlib/ext/compress.nu's zstd_* will return CompressOther"
fi

# ── libopus detection ──────────────────────────────────────
# pttvoice/opus.nu binds libopus directly (& `opus` @ …, no runtime.c bridge).
# Drop the sentinel the nurlc FFI-lib check looks for; nurl.sh auto-links -lopus
# when the symbols appear. libopus ships no unversioned .so on Debian, so accept
# either pkg-config or the bare soname.
if pkg-config --exists opus 2>/dev/null || [ -e /usr/lib/x86_64-linux-gnu/libopus.so.0 ] || [ -e /usr/lib/libopus.so.0 ]; then
    echo 1 > stdlib/runtime.opus
    log "[info] libopus detected — Opus codec FFI enabled"
else
    rm -f stdlib/runtime.opus
    log "[info] libopus not found — pttvoice audio codec unavailable"
fi

# ── ALSA (libasound) detection ─────────────────────────────
# pttvoice/audio.nu captures/plays PCM via the ALSA snd_pcm_* API.
if pkg-config --exists alsa 2>/dev/null || [ -e /usr/lib/x86_64-linux-gnu/libasound.so.2 ] || [ -e /usr/lib/libasound.so.2 ]; then
    echo 1 > stdlib/runtime.asound
    log "[info] ALSA detected — pttvoice audio I/O enabled"
else
    rm -f stdlib/runtime.asound
    log "[info] ALSA not found — pttvoice audio I/O unavailable"
fi

# ── CUDA driver + NVRTC detection ──────────────────────────
# packages/gpu binds the CUDA Driver API (& `cuda` @ cu…) and NVRTC
# (& `nvrtc` @ nvrtc…) directly — NO runtime.c bridge, so a GPU-less
# build (e.g. MILK-V Duo) never grows a CUDA dependency. Drop the
# sentinels the nurlc FFI-lib check looks for; nurl.sh auto-links
# -lcuda / -lnvrtc only when those symbols actually appear AND the lib
# probes link-able. libcuda ships with the NVIDIA driver (no toolkit
# needed); libnvrtc ships with the CUDA toolkit and is optional — a
# program that embeds pre-compiled PTX needs only -lcuda.
if [ -e /usr/lib/x86_64-linux-gnu/libcuda.so ] || ldconfig -p 2>/dev/null | grep -q 'libcuda\.so '; then
    echo 1 > stdlib/runtime.cuda
    log "[info] CUDA driver (libcuda) detected — GPU compute FFI enabled"
else
    rm -f stdlib/runtime.cuda
    log "[info] CUDA driver not found — packages/gpu unavailable"
fi
if pkg-config --exists nvrtc 2>/dev/null || [ -e /usr/lib/x86_64-linux-gnu/libnvrtc.so ] || ldconfig -p 2>/dev/null | grep -q 'libnvrtc\.so '; then
    echo 1 > stdlib/runtime.nvrtc
    log "[info] NVRTC detected — runtime CUDA-C→PTX kernel compilation enabled"
else
    rm -f stdlib/runtime.nvrtc
    log "[info] NVRTC not found — runtime kernel compilation unavailable (embed PTX instead)"
fi

# ── Xlib detection ─────────────────────────────────────────
# Programs that open a real GUI window bind libX11 directly (& `X11` @ X…,
# no runtime.c bridge — e.g. packages/yoloe's window preview). Drop the
# sentinel the nurlc FFI-lib check looks for; nurl.sh auto-links -lX11 only
# when an `@XOpenDisplay` reference appears AND libX11 probes link-able, so a
# headless/server build never grows an X dependency.
if pkg-config --exists x11 2>/dev/null || [ -e /usr/lib/x86_64-linux-gnu/libX11.so ] || ldconfig -p 2>/dev/null | grep -q 'libX11\.so '; then
    echo 1 > stdlib/runtime.X11
    log "[info] libX11 detected — GUI window FFI enabled"
else
    rm -f stdlib/runtime.X11
    log "[info] libX11 not found — GUI window display unavailable (terminal preview still works)"
fi

# ── Build stages ─────────────────────────────────────────────
# `-flto` makes runtime.o emit LLVM bitcode so vec/string/io FFI calls
# inline across the runtime ↔ user-code boundary at link time. The
# matching `-flto` on every clang invocation that consumes runtime.o
# (this script, nurl.sh, compiler/tests/run_tests.sh, tools/*/build.sh)
# triggers the LTO link pipeline.
# Bake the toolchain version into runtime.o so `nurlc --version` /
# `nurlpkg --version` work. tools/version.sh is the single source of truth
# (git describe / CHANGELOG); the generated header is git-ignored and
# rebuilt every run. It lives in runtime.o, not nurlc.nu's IR, so the
# bootstrap fixed point and the committed snapshot never churn on a bump.
printf '#define NURL_VERSION "%s"\n' "$(bash tools/version.sh 2>/dev/null || echo v0.0.0)" > stdlib/nurl_version_gen.h

step "runtime"       bash -c "'$CLANG' -O2 $LTO_FLAG $SAN_CFLAGS $CURL_CFLAGS $OPENSSL_CFLAGS $SQLITE3_CFLAGS $ZLIB_CFLAGS -c stdlib/runtime.c -o stdlib/runtime.o"

# Under `-flto` the `runtime.o` above is LLVM bitcode, which a plain GNU
# `ld` cannot link. The LTO consumers (this script, nurl.sh, the test
# runner) pair it with `-flto` and are fine — but the playground's
# native-build endpoint links user IR with a stock `clang` + `ld` and
# needs a real ELF object. Emit `runtime.native.o` for that path: run
# codegen over the already-built bitcode (cheap — no C front-end re-run)
# so the feature defines stay identical to `runtime.o`. With LTO off
# `runtime.o` is already an ELF object, so just copy it.
if [ -n "$LTO_FLAG" ]; then
    step "runtime-native" "$CLANG" -O2 -c -x ir stdlib/runtime.o -o stdlib/runtime.native.o
else
    step "runtime-native" cp stdlib/runtime.o stdlib/runtime.native.o
fi

# CUDA / NVRTC fallback stubs. Plain ELF objects (no LTO) that nurl.sh links
# in place of -lcuda / -lnvrtc when those libraries are absent, so a program
# referencing packages/gpu still links + loads on a driverless host and falls
# back to the CPU backend. Cheap to always build; only linked when needed.
step "cuda-stubs"    "$CLANG" -O2 -fPIC -c stdlib/cuda_stubs.c  -o stdlib/cuda_stubs.o
step "nvrtc-stubs"   "$CLANG" -O2 -fPIC -c stdlib/nvrtc_stubs.c -o stdlib/nvrtc_stubs.o

# Always build canvas.o. With SDL2 headers present we get the real
# native back-end (-DNURL_HAVE_SDL2); otherwise we compile a stub that
# prints a clear diagnostic and exits if the program actually calls
# into the canvas API. A marker file (stdlib/canvas.sdl2) tells nurl.sh
# whether to link -lSDL2 for canvas-using programs.
SDL2_INC=""
if   [ -f /usr/include/SDL2/SDL.h ]; then
    SDL2_INC="/usr/include"
elif pkg-config --exists sdl2 2>/dev/null; then
    # pkg-config gives us "-I/path/include/SDL2"; strip the -I and the
    # trailing /SDL2 so we can pass the parent directory.
    _sdl_cflags=$(pkg-config --cflags-only-I sdl2 | awk '{print $1}')
    SDL2_INC="${_sdl_cflags#-I}"
    SDL2_INC="${SDL2_INC%/SDL2}"
fi
if [ -n "$SDL2_INC" ]; then
    step "canvas"    "$CLANG" -c stdlib/canvas.c -DNURL_HAVE_SDL2 -I"$SDL2_INC" -o stdlib/canvas.o
    echo 1 > stdlib/canvas.sdl2
else
    step "canvas"    "$CLANG" -c stdlib/canvas.c -o stdlib/canvas.o
    rm -f stdlib/canvas.sdl2
    log "[info] libsdl2-dev not found — built canvas.o as a stub (canvas demos will link but abort at runtime)"
fi
# ── --refresh-bootstrap (optional, pre-clean) ────────────────────────
# When a grammar or runtime-ABI change leaves the committed
# `compiler/nurlc_lastgood.ll` unable to compile current nurlc.nu,
# the developer flips the snapshot forward by hand. Requires the
# CURRENT `build/nurlc` to exist (i.e. you've already built once
# before with the previous snapshot still functional).
if (( REFRESH_BOOTSTRAP == 1 )); then
    if [ ! -x build/nurlc ]; then
        echo "ERROR: --refresh-bootstrap requires an existing build/nurlc" >&2
        echo "       (run ./build.sh first to produce one)" >&2
        exit 1
    fi
    log "[refresh] cp compiler/nurlc.nu → compiler/nurlc_lastgood.nu"
    cp compiler/nurlc.nu compiler/nurlc_lastgood.nu
    step "refresh lastgood ir" \
        bash -c "./build/nurlc compiler/nurlc_lastgood.nu > compiler/nurlc_lastgood.ll"
    log "[refresh] $(wc -l < compiler/nurlc_lastgood.ll) lines, $(wc -c < compiler/nurlc_lastgood.ll) bytes"
    log "[refresh] commit BOTH compiler/nurlc_lastgood.nu + .ll together"
fi

step "clean"         rm -f build/nurlc_lastgood.bin \
                          build/nurlc_self.ll build/nurlc_self \
                          build/nurlc_self2.ll build/nurlc_self2 \
                          build/nurlc

# Stage 0: link the committed snapshot IR. No Python anywhere —
# the .ll was produced by a previous nurlc run and lives in the
# repo. clang picks the host triple automatically; the IR carries
# no `target triple` directive so the same .ll boots on
# Linux / macOS / Windows.
# dlopen/dlsym (runtime TLS resolves OpenSSL at runtime via dlopen) live in
# libdl on the glibc < 2.34 floor; link -ldl on Linux only (FreeBSD/macOS
# keep them in libc and have no separate libdl). --as-needed on the link
# drops it when unreferenced.
DL_LIB=""
case "$(uname -s)" in Linux) DL_LIB="-ldl" ;; esac

step "stage0 link"   "$CLANG" -O2 $LTO_FLAG $SAN_LDFLAGS -Wl,--as-needed compiler/nurlc_lastgood.ll stdlib/runtime.o -lm -lpthread $DL_LIB $CURL_LIBS $OPENSSL_LIBS $SQLITE3_LIBS $ZLIB_LIBS $ZSTD_LIBS -o build/nurlc_lastgood.bin

step "stage1 ir"     bash -c './build/nurlc_lastgood.bin compiler/nurlc.nu > build/nurlc_self.ll'
step "stage1 link"   "$CLANG" -O2 $LTO_FLAG $SAN_LDFLAGS -Wl,--as-needed build/nurlc_self.ll stdlib/runtime.o -lm -lpthread $DL_LIB $CURL_LIBS $OPENSSL_LIBS $SQLITE3_LIBS $ZLIB_LIBS $ZSTD_LIBS -o build/nurlc_self

step "stage2 ir"     bash -c './build/nurlc_self compiler/nurlc.nu > build/nurlc_self2.ll'
step "stage2 link"   "$CLANG" -O2 $LTO_FLAG $SAN_LDFLAGS -Wl,--as-needed build/nurlc_self2.ll stdlib/runtime.o -lm -lpthread $DL_LIB $CURL_LIBS $OPENSSL_LIBS $SQLITE3_LIBS $ZLIB_LIBS $ZSTD_LIBS -o build/nurlc_self2

# Fixed-point: nurlc_self must match nurlc_self2.
if ! cmp -s build/nurlc_self.ll build/nurlc_self2.ll; then
    {
        echo "Fixed point NOT reached — nurlc_self and nurlc_self2 differ."
        echo "Run: diff build/nurlc_self.ll build/nurlc_self2.ll"
    } >> "$LOG"
    fail "bootstrap fixed point"
fi

cp build/nurlc_self2 build/nurlc
ln -sf build/nurlc nurlc 2>/dev/null || cp build/nurlc nurlc

# ── nurlfmt ──────────────────────────────────────────────────
# Build the canonical source formatter on top of the freshly-
# bootstrapped nurlc. Treated as a soft step: failure here logs a
# warning but does not block the build, since the formatter is a
# tooling concern rather than a compiler invariant.
if bash "$SCRIPT_DIR/tools/nurlfmt/build.sh" >> "$LOG" 2>&1; then
    log "[info] nurlfmt built → build/nurlfmt"
    # Spot-check: a handful of representative files must still round-
    # trip through the formatter without changing their LLVM IR. The
    # full-tree gate lives in compiler/tests/nurlfmt_idempotent.sh
    # — run that manually for a complete sweep.
    if bash compiler/tests/nurlfmt_idempotent.sh \
            examples/fizzbuzz.nu examples/calculator.nu \
            stdlib/core/string.nu >> "$LOG" 2>&1; then
        log "[info] nurlfmt round-trip spot-check passed"
    else
        log "[warn] nurlfmt round-trip spot-check FAILED — see log"
    fi
else
    log "[warn] nurlfmt build failed; skipping"
fi

# ── Test suite ───────────────────────────────────────────────
BUILD_SECS=$(( SECONDS - BUILD_T0 ))
if (( RUN_TESTS == 0 )); then
    if (( SAN == 1 )); then
        echo "BUILD SUCCESS (sanitized — run ./compiler/tests/run_san_tests.sh next)"
    else
        echo "BUILD SUCCESS (tests skipped via --no-tests)"
    fi
    echo "Build time: $(fmt_dur "$BUILD_SECS")"
    exit 0
fi

TEST_T0=$SECONDS
TEST_OUT="$(compiler/tests/run_tests.sh 2>&1)"; TEST_RC=$?
TEST_SECS=$(( SECONDS - TEST_T0 ))
if (( TEST_RC == 0 )); then
    echo "BUILD SUCCESS & TESTS PASSED"
    echo "Build time: $(fmt_dur "$BUILD_SECS")  ·  Test time: $(fmt_dur "$TEST_SECS")"
    # NOTE: nurlc_lastgood.{nu,ll} are NOT auto-updated on a
    # successful build. They are the committed bootstrap snapshot
    # and only the explicit `./build.sh --refresh-bootstrap` flag
    # moves them forward (and then BOTH files must be committed
    # together — the .ll is what stage 0 actually consumes).
    exit 0
fi

echo "BUILD DIDN'T FAIL but TESTS FAILED"
echo "Build time: $(fmt_dur "$BUILD_SECS")  ·  Test time: $(fmt_dur "$TEST_SECS")"
echo "===================================================="
echo "$TEST_OUT"
exit 1
