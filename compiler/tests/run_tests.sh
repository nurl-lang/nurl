#!/usr/bin/env bash
# ============================================================
#  run_tests.sh — for every .nu in this directory:
#     1. compile with nurlc (to LLVM IR)
#     2. if compile OK, link with clang + runtime.o
#     3. if link OK, run the binary with a timeout and capture
#        stdout+stderr + exit code
#
#  Output (since PURIFY.md Phase 5, 2026-05-23):
#   - success.txt — only the tests whose outcome matched the
#                   expectation (normal tests: COMPILE+LINK+RUN
#                   success; should_fail_*: COMPILE FAIL;
#                   should_warn_* / borrow_*: COMPILE OK with the
#                   captured WARNINGS block).
#   - failures.txt — only the tests whose outcome DIDN'T match,
#                    with the exact compile / link command and
#                    full captured stderr so the cause is visible
#                    at a glance. Empty when everything went well.
#   - correct.txt — snapshot baseline; compared against success.txt
#                   only. Failures don't pollute the baseline diff.
#
#  Exit code:
#   - 0 when success.txt == correct.txt AND failures.txt is empty
#   - 1 on baseline diff OR any unexpected failure
#
#  When the baseline legitimately needs updating: overwrite
#  correct.txt with success.txt and commit the new version.
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

CLANG="${CLANG:-clang}"
if ! command -v "$CLANG" &>/dev/null; then
    for c in /usr/lib/llvm/bin/clang /usr/local/bin/clang; do
        [ -x "$c" ] && CLANG="$c" && break
    done
fi
if ! command -v "$CLANG" &>/dev/null; then
    echo "ERROR: clang not found" >&2
    exit 2
fi

# Per-feature link flags — see header in build.sh for the gating
# sentinels. Programs that don't import the corresponding stdlib
# module link cleanly either way; these just resolve the symbols
# when something does pull them in.
CURL_LIBS=""
if [[ -f "$ROOT_DIR/stdlib/runtime.curl" ]]; then
    if command -v pkg-config &>/dev/null && pkg-config --exists libcurl 2>/dev/null; then
        CURL_LIBS=$(pkg-config --libs libcurl)
    else
        CURL_LIBS="-lcurl"
    fi
fi
OPENSSL_LIBS=""
if [[ -f "$ROOT_DIR/stdlib/runtime.openssl" ]]; then
    if command -v pkg-config &>/dev/null && pkg-config --exists openssl 2>/dev/null; then
        OPENSSL_LIBS=$(pkg-config --libs openssl)
    else
        OPENSSL_LIBS="-lssl -lcrypto"
    fi
fi
SQLITE3_LIBS=""
if [[ -f "$ROOT_DIR/stdlib/runtime.sqlite3" ]]; then
    if command -v pkg-config &>/dev/null && pkg-config --exists sqlite3 2>/dev/null; then
        SQLITE3_LIBS=$(pkg-config --libs sqlite3)
    else
        SQLITE3_LIBS="-lsqlite3"
    fi
fi
PQ_LIBS=""
if [[ -f "$ROOT_DIR/stdlib/runtime.pq" ]]; then
    if command -v pkg-config &>/dev/null && pkg-config --exists libpq 2>/dev/null; then
        PQ_LIBS=$(pkg-config --libs libpq)
    else
        PQ_LIBS="-lpq"
    fi
fi
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

ENABLE_HTTP_TESTS="${NURL_HTTP_TESTS:-0}"
ENABLE_NET_TESTS="${NURL_NET_TESTS:-0}"

if [[ "${NURL_SAN:-0}" == "1" ]]; then
    echo "NURL_SAN=1 set — use ./compiler/tests/run_san_tests.sh for sanitized runs." >&2
    exit 2
fi

SUCCESS="$SCRIPT_DIR/success.txt"
FAILURES="$SCRIPT_DIR/failures.txt"
BASELINE="$SCRIPT_DIR/correct.txt"
WORKDIR="$ROOT_DIR/build/tests"

MAX_OUT_LINES="${MAX_OUT_LINES:-200}"
TIMEOUT="${TIMEOUT:-10}"

: > "$SUCCESS"
: > "$FAILURES"
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

# Append `out_file` to `dst` with a hard cap on lines (avoid baseline
# explosions on runaway test output).
append_capped() {
    local dst="$1"; local out_file="$2"
    local lines
    lines=$(wc -l < "$out_file")
    if [[ $lines -le $MAX_OUT_LINES ]]; then
        cat "$out_file" >> "$dst"
    else
        head -n "$MAX_OUT_LINES" "$out_file" >> "$dst"
        printf '[... %d more lines truncated ...]\n' \
            "$((lines - MAX_OUT_LINES))" >> "$dst"
    fi
}

# Strip the absolute repo root prefix from paths in `file` in place,
# so output is portable across checkout locations.
strip_root() {
    sed -i "s|$ROOT_DIR/||g" "$1"
}

# Build the link command shared by every test — keep it as a single
# string so the failure record can reproduce it verbatim. The flag
# list mirrors build.sh's per-stage link line. Squash runs of spaces
# (some feature vars expand to empty when the optional lib is absent).
LINK_FLAGS="$(printf '%s' "-O2 -flto -lm -lpthread $CURL_LIBS $OPENSSL_LIBS $SQLITE3_LIBS $PQ_LIBS $ZLIB_LIBS $ZSTD_LIBS" | tr -s ' ' | sed 's/ *$//')"

# Record a successful test (passes the expected outcome) into success.txt.
# Fields written: header + status lines, mirroring the historic
# `testresults.txt` format so correct.txt baselines stay readable.
record_success() {
    local name="$1"
    printf '=== %s ===\n' "$name" >> "$SUCCESS"
    shift
    while [[ $# -gt 0 ]]; do
        echo "$1" >> "$SUCCESS"
        shift
    done
    echo >> "$SUCCESS"
}

# Record a failure into failures.txt — the user-visible format the
# user requested: `[1/2]` and `[2/2]` step lines + the verbatim
# command + the captured stderr. Paths get the repo-root prefix
# stripped so the record is portable / pasteable.
record_failure() {
    local name="$1"; local stage="$2"; local src="$3"
    local ll="$4"; local bin="$5"; local err_file="$6"
    local src_rel="${src#$ROOT_DIR/}"
    local ll_rel="${ll#$ROOT_DIR/}"
    local bin_rel="${bin#$ROOT_DIR/}"
    printf '=== %s ===\n' "$name" >> "$FAILURES"
    case "$stage" in
        compile)
            echo "[1/2] $src_rel → $ll_rel" >> "$FAILURES"
            ;;
        link)
            echo "[1/2] $src_rel → $ll_rel" >> "$FAILURES"
            echo "[2/2] $ll_rel → $bin_rel  ($LINK_FLAGS)" >> "$FAILURES"
            ;;
        run)
            echo "[1/2] $src_rel → $ll_rel" >> "$FAILURES"
            echo "[2/2] $ll_rel → $bin_rel" >> "$FAILURES"
            echo "[run] $bin_rel (exit not as expected)" >> "$FAILURES"
            ;;
        unexpected_compile_ok)
            echo "[1/2] $src_rel → $ll_rel" >> "$FAILURES"
            echo "(expected COMPILE FAIL but compiler accepted the program)" >> "$FAILURES"
            ;;
    esac
    if [[ -s "$err_file" ]]; then
        cat "$err_file" >> "$FAILURES"
    fi
    echo >> "$FAILURES"
}

for src in "${tests[@]}"; do
    name="$(basename "$src" .nu)"
    ll="$WORKDIR/$name.ll"
    bin="$WORKDIR/$name"
    out="$WORKDIR/$name.out"
    err="$WORKDIR/$name.err"
    rm -f "$ll" "$bin" "$out" "$err"

    # Skip helper modules: files imported by other tests via `$`-import
    # have no `main` function. Convention: `*_mod.nu`, `*_helper.nu`,
    # `*_lib.nu`.
    case "$name" in
        *_mod|*_helper|*_lib) continue ;;
    esac

    # Network-dependent HTTP tests are opt-in via NURL_HTTP_TESTS=1.
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
    if [[ ( "$name" == "http_server_seq" \
            || "$name" == "http_server_pipelined" \
            || "$name" == "http_server_limits" \
            || "$name" == "http_server_tls" \
            || "$name" == "http_server_panic" ) \
          && "$ENABLE_NET_TESTS" != "1" ]]; then
        continue
    fi
    if [[ "$name" == net_* && "$name" != "net_basic" \
          && "$ENABLE_NET_TESTS" != "1" ]]; then
        continue
    fi

    # ── borrow_* — borrow violations are now compile errors (BORROW.md
    #               Phase 8 final, 2026-05-25). Each test file contains
    #               one or more positive cases that MUST trip the
    #               checker; the run is expected to fail and the error
    #               text is baselined for regression protection.
    if [[ "$name" == borrow_* ]]; then
        if "$NURLC" "$src" > "$ll" 2>"$err"; then
            record_failure "$name" unexpected_compile_ok "$src" "$ll" "$bin" "$err"
            continue
        fi
        printf '=== %s ===\n' "$name" >> "$SUCCESS"
        echo "COMPILE FAIL" >> "$SUCCESS"
        if [[ -s "$err" ]]; then
            strip_root "$err"
            echo "ERRORS" >> "$SUCCESS"
            append_capped "$SUCCESS" "$err"
        fi
        echo >> "$SUCCESS"
        continue
    fi

    # ── should_fail_* — COMPILE FAIL is the expected outcome ──
    if [[ "$name" == should_fail_* ]]; then
        if "$NURLC" "$src" > "$ll" 2>"$err"; then
            # Expected failure but compiled successfully → unexpected
            record_failure "$name" unexpected_compile_ok "$src" "$ll" "$bin" "$err"
        else
            record_success "$name" "COMPILE FAIL"
        fi
        continue
    fi

    # ── compile ──
    # For should_warn_* the compile stderr is the diagnostic that
    # gets baselined; keep it in $werr so the link step (which reuses
    # $err) can't clobber it.
    werr=""
    if [[ "$name" == should_warn_* ]]; then
        werr="$WORKDIR/$name.werr"
        rm -f "$werr"
        if ! "$NURLC" "$src" > "$ll" 2>"$werr"; then
            record_failure "$name" compile "$src" "$ll" "$bin" "$werr"
            continue
        fi
    else
        if ! "$NURLC" "$src" > "$ll" 2>"$err"; then
            record_failure "$name" compile "$src" "$ll" "$bin" "$err"
            continue
        fi
    fi

    # ── link ──
    # shellcheck disable=SC2086
    if ! "$CLANG" -O2 -flto "$ll" "$RUNTIME" -lm -lpthread $CURL_LIBS $OPENSSL_LIBS $SQLITE3_LIBS $PQ_LIBS $ZLIB_LIBS $ZSTD_LIBS -o "$bin" 2>"$err"; then
        strip_root "$err"
        record_failure "$name" link "$src" "$ll" "$bin" "$err"
        continue
    fi

    # ── run ──
    { ( cd "$WORKDIR" && timeout "${TIMEOUT}s" "./$name" > "$out" 2>&1 ); } 2>/dev/null
    exit_code=$?

    # Write the success record. Inline (rather than via a helper)
    # because the optional WARNINGS body is a multi-line file blob.
    printf '=== %s ===\n' "$name" >> "$SUCCESS"
    echo "COMPILE OK" >> "$SUCCESS"
    if [[ -n "$werr" && -s "$werr" ]]; then
        strip_root "$werr"
        echo "WARNINGS" >> "$SUCCESS"
        append_capped "$SUCCESS" "$werr"
    fi
    echo "LINK OK" >> "$SUCCESS"
    printf 'EXIT %d\n' "$exit_code" >> "$SUCCESS"
    echo "OUTPUT" >> "$SUCCESS"
    append_capped "$SUCCESS" "$out"
    echo >> "$SUCCESS"
done

# ── Report ─────────────────────────────────────────────────────
exit_status=0

if [[ ! -f "$BASELINE" ]]; then
    cp "$SUCCESS" "$BASELINE"
    echo "No baseline found — created correct.txt from current success.txt."
    echo "Review it and commit if it reflects the expected state."
else
    if ! cmp -s "$SUCCESS" "$BASELINE"; then
        echo "TESTS FAILED — success.txt differs from correct.txt:"
        echo
        diff -u "$BASELINE" "$SUCCESS" || true
        echo
        exit_status=1
    fi
fi

if [[ -s "$FAILURES" ]]; then
    n=$(grep -c "^=== " "$FAILURES")
    echo
    echo "=== $n failure(s) recorded in compiler/tests/failures.txt ==="
    cat "$FAILURES"
    exit_status=1
fi

if [[ $exit_status -eq 0 ]]; then
    echo "TESTS PASSED"
fi
exit "$exit_status"
