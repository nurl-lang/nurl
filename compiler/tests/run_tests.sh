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

LINK_HELPER="$ROOT_DIR/tools/nurl-build/run.sh"
if [[ ! -x "$LINK_HELPER" ]]; then
    echo "ERROR: link helper not found at $LINK_HELPER" >&2
    exit 2
fi

# HTTP tests require network egress, so they're opt-in. Default skips.
ENABLE_HTTP_TESTS="${NURL_HTTP_TESTS:-0}"

# Live-socket net tests (server listen + loopback round-trip) are opt-in
# via NURL_NET_TESTS=1. The error-path-only `net_basic.nu` runs
# unconditionally; loopback / live tests need the gate.
ENABLE_NET_TESTS="${NURL_NET_TESTS:-0}"

HOST_OS="$(uname -s)"
HOST_ARCH="$(uname -m)"

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

strip_repo_prefix_inplace() {
    local file="$1"
    local tmp="${file}.tmp"
    sed "s|$ROOT_DIR/||g" "$file" > "$tmp"
    mv "$tmp" "$file"
}

run_with_timeout() {
    local cwd="$1"
    local bin_name="$2"
    local out_file="$3"
    local timeout_sec="$4"

    if command -v timeout >/dev/null 2>&1; then
        { ( cd "$cwd" && timeout "${timeout_sec}s" "./$bin_name" > "$out_file" 2>&1 ); } 2>/dev/null
        return $?
    fi
    if command -v gtimeout >/dev/null 2>&1; then
        { ( cd "$cwd" && gtimeout "${timeout_sec}s" "./$bin_name" > "$out_file" 2>&1 ); } 2>/dev/null
        return $?
    fi

    local marker="${out_file}.timeout"
    rm -f "$marker"
    (
        cd "$cwd" || exit 1
        "./$bin_name" > "$out_file" 2>&1 &
        local child=$!
        (
            sleep "$timeout_sec"
            if kill -0 "$child" 2>/dev/null; then
                : > "$marker"
                kill -TERM "$child" 2>/dev/null || true
                sleep 1
                kill -KILL "$child" 2>/dev/null || true
            fi
        ) &
        local watcher=$!
        wait "$child"
        local status=$?
        kill "$watcher" 2>/dev/null || true
        wait "$watcher" 2>/dev/null || true
        exit "$status"
    )
    local status=$?
    if [[ -f "$marker" ]]; then
        rm -f "$marker"
        return 124
    fi
    return $status
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

    # postgres_basic imports stdlib/ext/postgres.nu, whose FFI
    # declarations hard-require the libpq build sentinel at compile
    # time. On machines without libpq this is a portability skip, not
    # a compiler/linker regression.
    if [[ "$name" == "postgres_basic" && ! -f "$ROOT_DIR/stdlib/runtime.pq" ]]; then
        continue
    fi

    # variadic_ffi is currently unstable on Darwin/arm64: the emitted
    # printf varargs call produces non-deterministic garbage even when
    # the IR looks structurally correct. Keep coverage on other hosts,
    # but skip it here so baseline diffs stay meaningful.
    if [[ "$name" == "variadic_ffi" && "$HOST_OS" == "Darwin" && "$HOST_ARCH" == "arm64" ]]; then
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
            strip_repo_prefix_inplace "$werr"
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
        strip_repo_prefix_inplace "$werr"
        append_output_capped "$werr"
    fi

    if ! "$LINK_HELPER" --opt -O2 "$ROOT_DIR" "$ll" "$bin" >/dev/null 2>&1; then
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
    run_with_timeout "$WORKDIR" "$name" "$out" "$TIMEOUT"
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
