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

# Wire up the version-controlled git hooks (idempotent; only in a work-tree
# checkout). The pre-commit hook keeps staged .nu files nurlfmt-canonical.
if [[ -d .githooks ]] && git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    if [[ "$(git config --local core.hooksPath 2>/dev/null || true)" != ".githooks" ]]; then
        git config --local core.hooksPath .githooks 2>/dev/null || true
    fi
fi

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
    #
    # Memory knobs: the instrumented self-compile (stage1/stage2 ir)
    # holds tens of millions of live small allocations (that same
    # process-lifetime str-pool strategy), and default ASan redzones on
    # the larger pool blocks push the stage peak right against the
    # 16 GB GitHub runner — the job then dies as a 143/OOM with no
    # output. max_redzone=16 alone cuts ~1.9 GB off the self-compile
    # peak (measured); the small quarantine + shallow malloc stacks
    # trim the rest of the always-on cost. Error DETECTION is
    # unaffected — only the free-reuse distance and the alloc-stack
    # depth in reports shrink, and run_san_tests.sh (the corpus that
    # actually hunts bugs in small programs) sets its own defaults.
    export ASAN_OPTIONS="detect_leaks=0:abort_on_error=0:halt_on_error=0:print_stacktrace=1:quarantine_size_mb=4:malloc_context_size=2:max_redzone=16"
    export UBSAN_OPTIONS="print_stacktrace=1:halt_on_error=0"
else
    NO_LTO_IN_SAN=0
fi

# Helper that mints the right `-flto` or `-fno-lto` flag depending on
# sanitizer mode. Used in every clang invocation that compiles or links
# runtime.o-consuming code.
if (( NO_LTO_IN_SAN == 1 )); then
    LTO_FLAG=""
    RT_LTO_FLAG=""
else
    LTO_FLAG="-flto"
    # On Linux, runtime.o itself is THIN bitcode: a ThinLTO module carries
    # a summary on top of ordinary bitcode, and GNU ld/gold's LLVMgold
    # plugin consumes it in a full `-flto` link unchanged (measured:
    # identical instruction counts on the bench suite), while a
    # `-flto=thin` link can additionally cache its backend codegen — which
    # is what lets nurl.sh skip re-lowering the runtime on every single
    # build (see the ThinLTO cache section there).
    #
    # NOT on macOS: ld64's libLTO aborts on the thin/full mix ("LLVM
    # ERROR: Unexistent dir" out of the stage0 link), and nurl.sh's
    # cached path is Linux-only anyway — so Darwin keeps the plain
    # full-LTO runtime it always had.
    if [ "$(uname -s)" = "Linux" ]; then
        RT_LTO_FLAG="-flto=thin"
    else
        RT_LTO_FLAG="-flto"
    fi
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
# $CLANG wins when set, so a host whose default clang is unusable (an
# Apple clang that cannot read opaque pointers — see the probe below)
# can be pointed at a real LLVM without editing anything.
CLANG="${CLANG:-clang}"
if ! command -v "$CLANG" &>/dev/null; then
    for candidate in /usr/lib/llvm/bin/clang /usr/local/bin/clang; do
        if [ -x "$candidate" ]; then CLANG="$candidate"; break; fi
    done
    if ! command -v "$CLANG" &>/dev/null; then
        echo "ERROR: clang not found"; exit 1
    fi
fi

# ── Can this clang read the IR nurlc emits? ──────────────────
# nurlc emits opaque pointers (`ptr`), the LLVM default since 15, and
# the toolchain has always gated on that by reading the major version out
# of `clang --version`. That gate is wrong on exactly one platform, and
# it is the one macOS users have: `Apple clang version 15.0.0` is NOT
# upstream LLVM 15 — Apple's numbering is its own, and Xcode 15.4's
# clang parses `ptr` only under an explicit flag. So the version check
# passed, the build proceeded, and stage0 died inside LLVM's IR parser
# with "expected type" and a .ll line number — a diagnostic about our
# bootstrap snapshot, for what is actually a toolchain-too-old problem.
#
# Ask the compiler what it can do instead of what it is called: hand it
# a declaration and see. Plain first, then under the cc1 flag that turns
# opaque pointers on for the transitional LLVM releases. A clang that
# can do neither cannot build NURL at all, and says so here rather than
# 200 lines into a build log.
#
# The probe's shape is load-bearing. `declare void @f(ptr)` ALONE parses
# on the very Apple clang this exists to catch, because LLVM 15 picks a
# module's pointer mode from what it sees first — `ptr` first and the
# module is opaque, and all is well. nurlc emits BOTH spellings in one
# module (`declare void @nurl_journal_push_drop(i8*, ptr)` is line 71 of
# the bootstrap snapshot), so `i8*` pins the module to typed mode and the
# `ptr` after it is a parse error. A probe that does not mix them reports
# a capability the real IR does not get. Mirror what nurlc emits.
OPAQUE_FLAGS=""
_probe_ll="$(mktemp -t nurl_probe.XXXXXX)" || _probe_ll="build/.opaque_probe"
printf 'declare void @nurl_opaque_probe(i8*, ptr)\n' > "$_probe_ll"
if ! "$CLANG" -c -x ir "$_probe_ll" -o /dev/null >/dev/null 2>&1; then
    if "$CLANG" -Xclang -opaque-pointers -c -x ir "$_probe_ll" -o /dev/null >/dev/null 2>&1; then
        OPAQUE_FLAGS="-Xclang -opaque-pointers"
    else
        rm -f "$_probe_ll"
        {
            echo "ERROR: $CLANG cannot parse the LLVM IR nurlc emits."
            echo "       nurlc uses opaque pointers (\`ptr\`), the LLVM default since 15."
            echo "       This clang rejects them even with -Xclang -opaque-pointers, so it"
            echo "       predates the feature entirely."
            echo "       Version reported: $("$CLANG" --version 2>/dev/null | head -1)"
            echo ""
            echo "       Note that Apple's version numbers are not upstream LLVM's —"
            echo "       'Apple clang 15' is not LLVM 15. On macOS install a real LLVM:"
            echo "         brew install llvm && export CLANG=\"\$(brew --prefix llvm)/bin/clang\""
            echo "       Elsewhere, install clang 15 or newer and set CLANG=/path/to/clang."
        } >&2
        exit 1
    fi
fi
rm -f "$_probe_ll"

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

# stdlib/ext/compress.nu's zstd_* is pure NURL over stdlib/std/zstd.nu
# now — no libzstd, no link flag, and no sentinel to gate the module on.
rm -f stdlib/runtime.zstd
ZSTD_LIBS=""

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

# ── CUDA driver + NVRTC sentinels (ALWAYS on — stub-backed) ─
# packages/gpu binds the CUDA Driver API (& `cuda` @ cu…) and NVRTC
# (& `nvrtc` @ nvrtc…) directly — NO runtime.c bridge. These are the two
# FFI libs with FALLBACK STUB OBJECTS (stdlib/{cuda,nvrtc}_stubs.o):
# nurl.sh links the real library when the host has it and the stubs when
# it doesn't, so a program referencing cu*/nvrtc* symbols ALWAYS links and
# loads — every stubbed call returns an error and packages/gpu falls back
# to its CPU backend. The compile-time sentinel therefore must not depend
# on the BUILD machine: a release archive assembled on a GPU-less CI
# runner used to ship without runtime.cuda, and the installed nurlc then
# refused to compile gpu-dependent packages on every machine, GPU or not.
# Stub-backed libs get an unconditional sentinel; the probe below is
# informational only (which flavour THIS host would link right now).
echo 1 > stdlib/runtime.cuda
echo 1 > stdlib/runtime.nvrtc
if [ -e /usr/lib/x86_64-linux-gnu/libcuda.so ] || ldconfig -p 2>/dev/null | grep -q 'libcuda\.so '; then
    log "[info] CUDA driver (libcuda) detected — GPU compute runs on the real driver"
else
    log "[info] CUDA driver not found — cu* links against stubs; packages/gpu uses its CPU backend"
fi
if pkg-config --exists nvrtc 2>/dev/null || [ -e /usr/lib/x86_64-linux-gnu/libnvrtc.so ] || ldconfig -p 2>/dev/null | grep -q 'libnvrtc\.so '; then
    log "[info] NVRTC detected — runtime CUDA-C→PTX kernel compilation enabled"
else
    log "[info] NVRTC not found — nvrtc* links against stubs (CUDA kernels need embedded PTX or the CPU backend)"
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
# $RT_LTO_FLAG makes runtime.o emit LLVM bitcode (on Linux, thin bitcode
# — see the comment where it is minted) so vec/string/io FFI calls
# inline across the runtime ↔ user-code boundary at link time. A
# matching `-flto` or `-flto=thin` on every clang invocation that
# consumes runtime.o (this script, nurl.sh, compiler/tests/run_tests.sh,
# tools/*/build.sh) triggers the LTO link pipeline.
# Bake the toolchain version into runtime.o so `nurlc --version` /
# `nurlpkg --version` work. tools/version.sh is the single source of truth
# (git describe / CHANGELOG); the generated header is git-ignored and
# rebuilt every run. It lives in runtime.o, not nurlc.nu's IR, so the
# bootstrap fixed point and the committed snapshot never churn on a bump.
printf '#define NURL_VERSION "%s"\n' "$(bash tools/version.sh 2>/dev/null || echo v0.0.0)" > stdlib/nurl_version_gen.h

# stdlib/runtime.c is a thin aggregator (A9 split): it #includes
# stdlib/runtime_core.c (bootstrap core) then stdlib/runtime_ffi.c (stdlib
# FFI shims) into one translation unit, so this stays a single runtime.o.
# A bootstrap/no_std profile compiles stdlib/runtime_core.c on its own.
step "runtime"       bash -c "'$CLANG' -O2 $RT_LTO_FLAG $SAN_CFLAGS $CURL_CFLAGS $OPENSSL_CFLAGS $SQLITE3_CFLAGS $ZLIB_CFLAGS -c stdlib/runtime.c -o stdlib/runtime.o"

# Under `-flto` the `runtime.o` above is LLVM bitcode, which a plain GNU
# `ld` cannot link. The LTO consumers (this script, nurl.sh, the test
# runner) pair it with `-flto` and are fine — but the playground's
# native-build endpoint links user IR with a stock `clang` + `ld` and
# needs a real ELF object. Emit `runtime.native.o` for that path: run
# codegen over the already-built bitcode (cheap — no C front-end re-run)
# so the feature defines stay identical to `runtime.o`. With LTO off
# `runtime.o` is already an ELF object, so just copy it.
if [ -n "$LTO_FLAG" ]; then
    step "runtime-native" "$CLANG" -O2 $OPAQUE_FLAGS -c -x ir stdlib/runtime.o -o stdlib/runtime.native.o
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

step "clean"         bash -c 'rm -f build/nurlc_lastgood.bin \
                          build/nurlc_self.ll build/nurlc_self \
                          build/nurlc_self2.ll build/nurlc_self2 \
                          build/nurlc_self.[0-9]*.ll build/nurlc_self.[0-9]*.o \
                          build/nurlc_self2.[0-9]*.ll build/nurlc_self2.[0-9]*.o \
                          build/nurlc'

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

# `--as-needed` is GNU ld / lld spelling; Apple's ld64 rejects the flag
# outright rather than ignoring it, so a macOS host cannot use the same
# string. ld64's equivalent of "drop the libraries nothing referenced"
# is -dead_strip_dylibs, which prunes LC_LOAD_DYLIB the same way.
AS_NEEDED="-Wl,--as-needed"
case "$(uname -s)" in Darwin) AS_NEEDED="-Wl,-dead_strip_dylibs" ;; esac

# Hand the resolved toolchain down to every script this build drives —
# split_equivalence.sh, the tools/*/build.sh scripts, run_tests.sh. Each
# of them links NURL IR, so each of them needs the same four answers,
# and each used to work them out again (or hardcode them: `clang`,
# `-Wl,--as-needed` and `-ldl` were all literals in split_equivalence.sh
# until macOS CI ran it). Resolve once, export, let the children default
# to the environment. They keep their own fallbacks so they still run
# standalone.
export CLANG OPAQUE_FLAGS AS_NEEDED DL_LIB

# ── Parallel stage links ─────────────────────────────────────
# Lowering nurlc's own 3.2 MB of IR is ~11 s of single-threaded LLVM,
# and the bootstrap pays it three times. `nurlc --split=N` writes the
# same module as N independent ones (stdout still carries the whole
# thing, so the .ll the fixed-point check compares is unchanged), which
# lets N clangs run at once and ThinLTO put the cross-module inlining
# back. Sanitized builds keep the one-module path: LTO is already off
# there. Stage 0 always does, too — it links the committed snapshot,
# which is one file by definition.
SPLIT_N=0
if [ -z "$SAN_LDFLAGS" ]; then
    SPLIT_N="$(nproc 2>/dev/null || getconf _NPROCESSORS_ONLN 2>/dev/null || echo 4)"
    (( SPLIT_N > 16 )) && SPLIT_N=16
    (( SPLIT_N < 2 )) && SPLIT_N=0
fi

# ── Optimisation level for the throwaway stages ──────────────
# Stages 0 and 1 are scaffolding. Neither binary is shipped, neither is
# benchmarked, and each one does exactly one job before being deleted:
# compile nurlc.nu once. Optimising them is spending link time to make a
# 0.8 s job into a 0.35 s job — the ~7 s of ThinLTO that buys the
# difference costs an order of magnitude more than it saves.
#
# Measured here (12 cores, clang 18, nurlc's own 3.3 MB of IR):
#
#            stage 0 (one module)      stage 1 (split N ways)
#            link    emit    total     link    emit    total
#   -O2      8.07 s  0.35 s  8.42 s    2.36 s  0.35 s  2.71 s
#   -O0      0.79 s  0.77 s  1.56 s    0.33 s  0.78 s  1.11 s
#
# ~8.5 s off every build. The IR each stage emits is byte-identical
# either way — which is the property the bootstrap actually depends on,
# and the fixed-point check below still proves it on every run.
#
# Stage 2 stays -O2: it is copied to build/nurlc, and that one IS the
# compiler this tree ships and benchmarks.
#
# Sanitized builds keep -O2 throughout. There LTO is already off (so the
# link is not the expensive part), the instrumented self-compile is the
# stage that runs closest to the runner's memory and time limits, and
# -O0 would slow the thing that is already slowest.
if [ -n "$SAN_LDFLAGS" ]; then
    BOOT_OPT="-O2"
else
    BOOT_OPT="-O0"
fi

# Does this compiler know how to partition a module? The snapshot that
# builds stage 0 predates the flag whenever the bootstrap is refreshed
# behind a change to it, so ask rather than assume.
split_capable() { [ "$SPLIT_N" -gt 0 ] && "$1" --help 2>/dev/null | grep -q -- '--split='; }

# Emit stage IR, partitioned when the compiler can do it.
stage_ir() {  # stage_ir <compiler> <ir-prefix>
    rm -f "$2".[0-9]*.ll "$2".[0-9]*.o
    if split_capable "$1"; then
        "$1" "--split=$SPLIT_N" "--split-out=$2" compiler/nurlc.nu > "$2.ll"
    else
        "$1" compiler/nurlc.nu > "$2.ll"
    fi
}

# Link stage IR: the parts in parallel if there are any, else the one
# module. `-flto=thin` replaces `-flto` for the split path — runtime.o
# is bitcode and still needs an LTO link either way.
link_stage() {  # link_stage <ir-prefix> <out> <opt-level>
    local pre="$1" out="$2" opt="$3" objs="" pids="" rc=0 p
    if compgen -G "$pre.[0-9]*.ll" > /dev/null; then
        for p in "$pre".[0-9]*.ll; do
            objs="$objs ${p%.ll}.o"
            "$CLANG" "$opt" -flto=thin $OPAQUE_FLAGS -Wno-override-module -c "$p" -o "${p%.ll}.o" &
            pids="$pids $!"
        done
        for p in $pids; do wait "$p" || rc=1; done
        (( rc == 0 )) || return 1
        # shellcheck disable=SC2086
        "$CLANG" "$opt" -flto=thin $OPAQUE_FLAGS -Wno-override-module $AS_NEEDED $objs stdlib/runtime.o \
            -lm -lpthread $DL_LIB $CURL_LIBS $OPENSSL_LIBS $SQLITE3_LIBS $ZLIB_LIBS $ZSTD_LIBS \
            -o "$out" || return 1
        # shellcheck disable=SC2086
        rm -f $objs "$pre".[0-9]*.ll
    else
        # shellcheck disable=SC2086
        "$CLANG" "$opt" $LTO_FLAG $OPAQUE_FLAGS $SAN_LDFLAGS $AS_NEEDED "$pre.ll" stdlib/runtime.o \
            -lm -lpthread $DL_LIB $CURL_LIBS $OPENSSL_LIBS $SQLITE3_LIBS $ZLIB_LIBS $ZSTD_LIBS \
            -o "$out" || return 1
    fi
}

# Stage 0 is the one link that cannot be split — the committed snapshot
# is a single file by definition — so it is also the one that gains most
# from $BOOT_OPT: 8.4 s to 1.6 s, link and emit together.
step "stage0 link"   "$CLANG" $BOOT_OPT $LTO_FLAG $OPAQUE_FLAGS $SAN_LDFLAGS $AS_NEEDED compiler/nurlc_lastgood.ll stdlib/runtime.o -lm -lpthread $DL_LIB $CURL_LIBS $OPENSSL_LIBS $SQLITE3_LIBS $ZLIB_LIBS $ZSTD_LIBS -o build/nurlc_lastgood.bin

# Stage 1 is a throwaway: its only job is to emit stage 2's IR, and it
# is rebuilt on every single build. Split it, and do not optimise it.
# The split stays even at -O0: it is the cheaper link of the two (N
# clangs beat one), and it is what keeps `nurlc --split` on the path
# every build walks, not just the ones that run the test suite.
step "stage1 ir"     stage_ir ./build/nurlc_lastgood.bin build/nurlc_self
step "stage1 link"   link_stage build/nurlc_self build/nurlc_self "$BOOT_OPT"

# Stage 2 is NOT. It is copied to build/nurlc and is the compiler this
# tree ships and benchmarks, and partitioning costs a measured 3.4% of
# retired instructions (see "Partitioned emission" in compiler/nurlc.nu).
# The rule is the same one nurl.sh applies to your program, pointed the
# other way: split what you rebuild constantly, not what you ship once.
step "stage2 ir"     bash -c './build/nurlc_self compiler/nurlc.nu > build/nurlc_self2.ll'
step "stage2 link"   link_stage build/nurlc_self2 build/nurlc_self2 -O2

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

# ── Partitioned emission ─────────────────────────────────────
# The stage links above already ran through `nurlc --split`, so a
# partition that does not parse or link has failed the build by now —
# that much holds even under --no-tests. What it does NOT cover is the
# partition being wrong in a way the linker accepts, so this rebuilds a
# structurally varied corpus both ways and compares the programs. It is
# a test (it rebuilds a corpus and costs ~7 s), so it goes with the
# tests: the Docker image asks for --no-tests precisely because CI runs
# them elsewhere, and this is one of them.
if (( RUN_TESTS == 1 )); then
    step "split equivalence" bash compiler/tests/split_equivalence.sh
    # The `simd` prefix, checked where a behavioural test cannot look:
    # that two clones exist, that only the wide one carries feature
    # bits, that the dispatcher owns the undecorated symbol, and that
    # the wide clone really lowers to ymm. simd_dispatch.nu proves the
    # answers are right; nothing in it can notice the wide clone
    # silently disappearing, which is the regression that costs 1.7x.
    step "simd dispatch IR" bash compiler/tests/simd_dispatch_ir.sh
fi

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

# ── nurlpkg ──────────────────────────────────────────────────
# The package manager, same soft-step treatment as nurlfmt. It used to be
# built only by .github/workflows/release.yml, so a developer's build/nurlpkg
# was whatever they last built by hand — while ./build.sh handed them a fresh
# nurlc and let them believe the whole toolchain was current. That went wrong
# in exactly the way you would expect: a months-old nurlpkg predating
# `publish --dry-run` silently ignored the flag (its unknown-flag rejection
# came later too) and published for real. Building it here keeps the local
# toolchain internally consistent.
if bash "$SCRIPT_DIR/tools/nurlpkg/build.sh" >> "$LOG" 2>&1; then
    log "[info] nurlpkg built → build/nurlpkg"
else
    log "[warn] nurlpkg build failed; skipping"
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
