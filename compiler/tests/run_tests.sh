#!/usr/bin/env bash
# ============================================================
#  run_tests.sh — for every .nu in this directory:
#     1. compile with nurlc (to LLVM IR)
#     2. if compile OK, link with clang + runtime.o
#     3. if link OK, run the binary with a timeout and capture
#        stdout+stderr + exit code
#  A single snapshot file testresults.txt records the full
#  outcome for each test (status, exit code, captured output).
#
#  Compared to correct.txt as baseline:
#   - missing baseline → testresults.txt is copied over as the
#     initial baseline
#   - identical         → print "TESTS PASSED"
#   - different         → print unified diff and exit 1
#
#  Add or remove tests simply by adding/removing .nu files.
#  When the baseline legitimately needs updating: delete
#  correct.txt (or overwrite it with testresults.txt) and
#  commit the new version.
# ============================================================
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

NURLC="$ROOT_DIR/build/nurlc"
RUNTIME="$ROOT_DIR/stdlib/runtime.o"

if [[ ! -x "$NURLC" ]]; then
    echo "ERROR: nurlc not found at $NURLC" >&2
    echo "       Run: ./build.sh" >&2
    exit 2
fi
if [[ ! -f "$RUNTIME" ]]; then
    echo "ERROR: runtime.o not found at $RUNTIME" >&2
    exit 2
fi

# build.sh drops stdlib/runtime.nolto when runtime.o is a plain native
# object (e.g. built by `zig cc` on macOS, which can't LTO) rather than
# LLVM bitcode. Match it at link time: pass -flto only when runtime.o
# actually carries bitcode.
if [[ -f "$ROOT_DIR/stdlib/runtime.nolto" ]]; then
    LTO_FLAG=""
else
    LTO_FLAG="-flto"
fi

# C toolchain driver. NURL_CC (preferred, supports multi-word like
# "zig cc") falls back to the legacy CLANG var, then to plain clang.
# Must match the driver build.sh used for runtime.o so the LTO bitcode
# versions agree at link time.
read -r -a CC <<< "${NURL_CC:-${CLANG:-clang}}"
if ! command -v "${CC[0]}" &>/dev/null; then
    if [[ "${#CC[@]}" -eq 1 && "${CC[0]}" == "clang" ]]; then
        for c in /usr/lib/llvm/bin/clang /usr/local/bin/clang; do
            [ -x "$c" ] && CC=("$c") && break
        done
    fi
    if ! command -v "${CC[0]}" &>/dev/null; then
        echo "ERROR: C driver '${CC[*]}' not found" >&2
        exit 2
    fi
fi

# Link -lcurl when build.sh detected libcurl. Programs that don't import
# stdlib/ext/http.nu link cleanly either way; this just keeps http_basic.nu
# resolvable when NURL_HTTP_TESTS=1 enables it.
CURL_LIBS=""
if [[ -f "$ROOT_DIR/stdlib/runtime.curl" ]]; then
    if command -v pkg-config &>/dev/null && pkg-config --exists libcurl 2>/dev/null; then
        CURL_LIBS=$(pkg-config --libs libcurl)
    else
        CURL_LIBS="-lcurl"
    fi
fi

# Link -lssl -lcrypto when build.sh detected openssl. Same model — the
# TLS symbols compile in unconditionally; without the link flags the
# runtime would fail at link time the first time anything calls them.
OPENSSL_LIBS=""
if [[ -f "$ROOT_DIR/stdlib/runtime.openssl" ]]; then
    if command -v pkg-config &>/dev/null && pkg-config --exists openssl 2>/dev/null; then
        OPENSSL_LIBS=$(pkg-config --libs openssl)
    else
        OPENSSL_LIBS="-lssl -lcrypto"
    fi
fi

# Link -lsqlite3 when build.sh detected libsqlite3. Same model.
SQLITE3_LIBS=""
if [[ -f "$ROOT_DIR/stdlib/runtime.sqlite3" ]]; then
    if command -v pkg-config &>/dev/null && pkg-config --exists sqlite3 2>/dev/null; then
        SQLITE3_LIBS=$(pkg-config --libs sqlite3)
    else
        SQLITE3_LIBS="-lsqlite3"
    fi
fi

# Link -lpq when build.sh detected libpq. Same model.
PQ_LIBS=""
if [[ -f "$ROOT_DIR/stdlib/runtime.pq" ]]; then
    if command -v pkg-config &>/dev/null && pkg-config --exists libpq 2>/dev/null; then
        PQ_LIBS=$(pkg-config --libs libpq)
    else
        PQ_LIBS="-lpq"
    fi
fi

# Link -lz / -lzstd when build.sh detected compression libs.
ZLIB_LIBS=""
if [[ -f "$ROOT_DIR/stdlib/runtime.z" ]]; then
    if command -v pkg-config &>/dev/null && pkg-config --exists zlib 2>/dev/null; then
        ZLIB_LIBS=$(pkg-config --libs zlib)
    else
        ZLIB_LIBS="-lz"
    fi
fi
ZSTD_LIBS=""
if [[ -f "$ROOT_DIR/stdlib/runtime.zstd" ]]; then
    if command -v pkg-config &>/dev/null && pkg-config --exists libzstd 2>/dev/null; then
        ZSTD_LIBS=$(pkg-config --libs libzstd)
    else
        ZSTD_LIBS="-lzstd"
    fi
fi

# HTTP tests require network egress, so they're opt-in. Default skips.
ENABLE_HTTP_TESTS="${NURL_HTTP_TESTS:-0}"

# Live-socket net tests (server listen + loopback round-trip) are opt-in
# via NURL_NET_TESTS=1. The error-path-only `net_basic.nu` runs
# unconditionally; loopback / live tests need the gate.
ENABLE_NET_TESTS="${NURL_NET_TESTS:-0}"

# Sanitizer mode: separate runner (run_san_tests.sh) handles ASan/UBSan
# instrumented runs because the output shape and pass/fail semantics
# differ from the baseline-diff model below.
if [[ "${NURL_SAN:-0}" == "1" ]]; then
    echo "NURL_SAN=1 set — use ./compiler/tests/run_san_tests.sh for sanitized runs." >&2
    exit 2
fi

RESULTS="$SCRIPT_DIR/testresults.txt"
BASELINE="$SCRIPT_DIR/correct.txt"
WORKDIR="$ROOT_DIR/build/tests"

# Cap captured output per-test so a runaway test can't balloon the baseline.
MAX_OUT_LINES="${MAX_OUT_LINES:-200}"
TIMEOUT="${TIMEOUT:-10}"

: > "$RESULTS"
mkdir -p "$WORKDIR"

shopt -s nullglob
tests=("$SCRIPT_DIR"/*.nu)
shopt -u nullglob

if [[ ${#tests[@]} -eq 0 ]]; then
    echo "ERROR: no .nu files found in $SCRIPT_DIR" >&2
    exit 2
fi

IFS=$'\n' tests=($(printf '%s\n' "${tests[@]}" | LC_ALL=C sort))
unset IFS

append_output_capped() {
    local out_file="$1"
    local lines
    lines=$(wc -l < "$out_file")
    if [[ $lines -le $MAX_OUT_LINES ]]; then
        cat "$out_file" >> "$RESULTS"
    else
        head -n "$MAX_OUT_LINES" "$out_file" >> "$RESULTS"
        printf '[... %d more lines truncated ...]\n' \
            "$((lines - MAX_OUT_LINES))" >> "$RESULTS"
    fi
}

for src in "${tests[@]}"; do
    name="$(basename "$src" .nu)"
    ll="$WORKDIR/$name.ll"
    bin="$WORKDIR/$name"
    out="$WORKDIR/$name.out"
    rm -f "$ll" "$bin" "$out"

    # Skip helper modules: files imported by other tests via `$`-import
    # have no `main` function, so the test framework would record them
    # as `COMPILE OK / LINK FAIL` (no `main` symbol). They are not real
    # test cases — only here to satisfy import paths. Convention:
    # `*_mod.nu`, `*_helper.nu`, `*_lib.nu`.
    case "$name" in
        *_mod|*_helper|*_lib) continue ;;
    esac

    # Network-dependent HTTP tests are opt-in via NURL_HTTP_TESTS=1.
    # Exemptions:
    #   * `http_request_parser` / `http_response_builder` /
    #     `http_router` — pure parser/builder/router, no socket;
    #     run unconditionally.
    #   * `http_server_seq` — opens a loopback listener (no remote
    #     net), so gated by NURL_NET_TESTS=1 alongside the live TCP
    #     tests rather than by NURL_HTTP_TESTS.
    if [[ "$name" == http_* \
          && "$name" != "http_request_parser" \
          && "$name" != "http_response_builder" \
          && "$name" != "http_router" \
          && "$name" != "http_extras" \
          && "$name" != "http_middleware" \
          && "$name" != "http_form" \
          && "$name" != "http_multipart" \
          && "$name" != "http_proxy" \
          && "$name" != "http_server_seq" \
          && "$name" != "http_server_pipelined" \
          && "$name" != "http_server_limits" \
          && "$name" != "http_server_tls" \
          && "$name" != "http_server_panic" \
          && "$ENABLE_HTTP_TESTS" != "1" ]]; then
        continue
    fi

    # Live-socket http_server tests gated by NURL_NET_TESTS=1 — same
    # treatment as net_loopback. Skip when the gate is off.
    if [[ ( "$name" == "http_server_seq" \
            || "$name" == "http_server_pipelined" \
            || "$name" == "http_server_limits" \
            || "$name" == "http_server_tls" \
            || "$name" == "http_server_panic" ) \
          && "$ENABLE_NET_TESTS" != "1" ]]; then
        continue
    fi

    # Live TCP loopback test (net_loopback.nu) is opt-in via
    # NURL_NET_TESTS=1. The error-path `net_basic.nu` is exempt — it
    # never opens a real socket.
    if [[ "$name" == net_* && "$name" != "net_basic" \
          && "$ENABLE_NET_TESTS" != "1" ]]; then
        continue
    fi

    printf '=== %s ===\n' "$name" >> "$RESULTS"

    # `should_warn_*` tests intentionally trip a compiler diagnostic
    # that is non-fatal (warning, not error). For those, capture the
    # compile stderr into a WARNINGS block so the baseline records the
    # exact diagnostic text; for everything else, compile stderr is
    # dropped to keep results deterministic across machines whose tool
    # versions vary.
    werr=""
    # `borrow_*` tests exercise the --borrowck analysis pass (BORROW.md).
    # They are compiled WITH --borrowck, their diagnostic is captured
    # into the baseline, and they are compile-only — a use-after-move
    # demo must not actually run (the run would be a real fault).
    if [[ "$name" == borrow_* ]]; then
        werr="$WORKDIR/$name.werr"
        if ! "$NURLC" --borrowck "$src" > "$ll" 2>"$werr"; then
            echo "COMPILE FAIL" >> "$RESULTS"
            echo >> "$RESULTS"
            continue
        fi
        echo "COMPILE OK" >> "$RESULTS"
        if [[ -s "$werr" ]]; then
            echo "WARNINGS" >> "$RESULTS"
            sed -i "s|$ROOT_DIR/||g" "$werr"
            append_output_capped "$werr"
        fi
        echo >> "$RESULTS"
        continue
    fi
    if [[ "$name" == should_warn_* ]]; then
        werr="$WORKDIR/$name.werr"
        if ! "$NURLC" "$src" > "$ll" 2>"$werr"; then
            echo "COMPILE FAIL" >> "$RESULTS"
            echo >> "$RESULTS"
            continue
        fi
    else
        if ! "$NURLC" "$src" > "$ll" 2>/dev/null; then
            echo "COMPILE FAIL" >> "$RESULTS"
            echo >> "$RESULTS"
            continue
        fi
    fi
    echo "COMPILE OK" >> "$RESULTS"
    if [[ -n "$werr" && -s "$werr" ]]; then
        echo "WARNINGS" >> "$RESULTS"
        # Strip the absolute repo prefix from warning paths so the
        # baseline is machine-portable. Anything before
        # `compiler/tests/…` becomes a relative path.
        sed -i "s|$ROOT_DIR/||g" "$werr"
        append_output_capped "$werr"
    fi

    # shellcheck disable=SC2086
    # `-flto` matches build.sh: runtime.o ships as LLVM bitcode and the
    # link-time LTO pipeline inlines runtime symbols into the test binary.
    if ! "${CC[@]}" -O2 $LTO_FLAG "$ll" "$RUNTIME" -lm -lpthread $CURL_LIBS $OPENSSL_LIBS $SQLITE3_LIBS $PQ_LIBS $ZLIB_LIBS $ZSTD_LIBS -o "$bin" 2>/dev/null; then
        echo "LINK FAIL" >> "$RESULTS"
        echo >> "$RESULTS"
        continue
    fi
    echo "LINK OK" >> "$RESULTS"

    # Run with cwd = WORKDIR and argv[0] = "./name" so argv-sensitive
    # tests produce the same output regardless of the absolute path
    # where the repo lives.  Braces + 2>/dev/null silence bash's own
    # "Aborted" / "Segmentation fault" job-status message when the
    # binary dies by signal; the binary's stderr is already merged
    # into $out via 2>&1.
    { ( cd "$WORKDIR" && timeout "${TIMEOUT}s" "./$name" > "$out" 2>&1 ); } 2>/dev/null
    exit_code=$?
    printf 'EXIT %d\n' "$exit_code" >> "$RESULTS"
    echo "OUTPUT" >> "$RESULTS"
    append_output_capped "$out"
    echo >> "$RESULTS"
done

if [[ ! -f "$BASELINE" ]]; then
    cp "$RESULTS" "$BASELINE"
    echo "No baseline found — created correct.txt from current results."
    echo "Review it and commit if it reflects the expected state."
    exit 0
fi

if cmp -s "$RESULTS" "$BASELINE"; then
    echo "TESTS PASSED"
    exit 0
fi

echo "TESTS FAILED — testresults.txt differs from correct.txt:"
echo
diff -u "$BASELINE" "$RESULTS" || true
exit 1
