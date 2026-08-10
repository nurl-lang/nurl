#!/usr/bin/env bash
# ============================================================
#  run_tests.sh — compiler test runner with PER-TEST golden files.
#
#  For every <name>.nu in this directory the runner produces an
#  "actual record" describing the outcome, and compares it byte-for-
#  byte against the golden file compiler/tests/outputs/<name>.txt.
#
#  Record shapes (the golden file holds exactly these lines):
#
#    normal test          should_fail_* / should_*       borrow_* / diag_*
#    ───────────          ─────────────────────────      ─────────────────
#    COMPILE OK           COMPILE FAIL                   COMPILE FAIL
#    LINK OK                                             ERRORS
#    EXIT <n>                                            <diagnostics>
#    OUTPUT
#    <stdout+stderr>
#
#    should_warn_* additionally carry a WARNINGS block between
#    COMPILE OK and LINK OK.
#
#  Why per-test goldens (vs the old monolithic correct.txt):
#    * a drifting test touches ONE file — diffs are surgical and
#      reviewable, never a 5000-line rebaseline.
#    * adding / deleting a test is adding / deleting one golden.
#    * tests run fully in PARALLEL with zero shared mutable state,
#      so the wall-clock cost is (slowest test), not the sum.
#
#  Regression safety net:
#    * a test whose golden is MISSING fails the run (no silent gaps).
#    * a golden with no matching .nu (ORPHAN) fails the run.
#    => the golden set and the test set are kept in exact bijection.
#
#  Usage:
#    run_tests.sh                 # check against goldens (CI mode)
#    run_tests.sh --update        # (re)write goldens from actual
#    run_tests.sh --update NAME…  # update only the named tests
#    NURL_TEST_JOBS=N             # parallelism (default: nproc)
#
#  Exit code: 0 iff every test matches its golden, no failures, no
#  missing goldens and no orphans. 1 otherwise. 2 on setup error.
# ============================================================
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Tests that `$`-import a helper module spell the path repo-root-relative
# (e.g. `$ \`compiler/tests/foo_mod.nu\``). nurlc resolves imports against
# the CWD, so anchor it to the repo root — the runner now works from any
# directory, not only when invoked from root (as build.sh does).
cd "$ROOT_DIR" || { echo "ERROR: cannot cd to $ROOT_DIR" >&2; exit 2; }

NURLC="$ROOT_DIR/build/nurlc"
RUNTIME="$ROOT_DIR/stdlib/runtime.o"
OUTDIR="$SCRIPT_DIR/outputs"
WORKDIR="$ROOT_DIR/build/tests"

UPDATE=0
declare -a ONLY=()
for arg in "$@"; do
    case "$arg" in
        --update) UPDATE=1 ;;
        -*)       echo "unknown flag: $arg" >&2; exit 2 ;;
        *)        ONLY+=("$arg") ;;
    esac
done

if [[ ! -x "$NURLC" ]]; then
    echo "ERROR: nurlc not found at $NURLC — run ./build.sh" >&2
    exit 2
fi
if [[ ! -f "$RUNTIME" ]]; then
    echo "ERROR: runtime.o not found at $RUNTIME" >&2
    exit 2
fi
if [[ "${NURL_SAN:-0}" == "1" ]]; then
    echo "NURL_SAN=1 — use ./compiler/tests/run_san_tests.sh for sanitized runs." >&2
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

# Opaque-pointer capability, asked of the compiler rather than inferred
# from its version string — see the long note in build.sh for why the
# version number lies on macOS. build.sh has already gated the build on
# this; here it only needs to reach the per-test link, since a corpus
# whose every test fails to compile is not a useful diagnosis.
OPAQUE_FLAGS=""
_probe_ll="$WORKDIR/.opaque_probe.ll"
mkdir -p "$WORKDIR"
printf 'declare void @nurl_opaque_probe(i8*, ptr)\n' > "$_probe_ll"
if ! "$CLANG" -c -x ir "$_probe_ll" -o /dev/null >/dev/null 2>&1; then
    OPAQUE_FLAGS="-Xclang -opaque-pointers"
fi
rm -f "$_probe_ll"

# Per-feature link flags — resolved once, shared by every worker.
# Programs that don't pull in the matching stdlib module link fine
# either way; these just satisfy the symbols when something does.
feature_libs() {  # sentinel-file  pkg-config-name  fallback-flags
    [[ -f "$ROOT_DIR/stdlib/$1" ]] || return 0
    if command -v pkg-config &>/dev/null && pkg-config --exists "$2" 2>/dev/null; then
        pkg-config --libs "$2"
    else
        printf '%s' "$3"
    fi
}
CURL_LIBS=$(feature_libs runtime.curl    libcurl "-lcurl")
OPENSSL_LIBS=$(feature_libs runtime.openssl openssl "-lssl -lcrypto")
SQLITE3_LIBS=$(feature_libs runtime.sqlite3 sqlite3 "-lsqlite3")
PQ_LIBS=$(feature_libs runtime.pq        libpq   "-lpq")
ZLIB_LIBS=$(feature_libs runtime.z       zlib    "-lz")
ZSTD_LIBS=$(feature_libs runtime.zstd    libzstd "-lzstd")

DL_LIB=""
case "$(uname -s)" in Linux) DL_LIB="-ldl" ;; esac
LINK_LIBS="$(printf '%s' "-lm -lpthread $DL_LIB $CURL_LIBS $OPENSSL_LIBS $SQLITE3_LIBS $PQ_LIBS $ZLIB_LIBS $ZSTD_LIBS" | tr -s ' ' | sed 's/ *$//')"

# Which tests this host can run at all — network, optional native libs,
# platform APIs, helper modules. Shared verbatim with run_san_tests.sh;
# see test_skips.sh for why it does not live here any more.
# shellcheck source=compiler/tests/test_skips.sh
. "$SCRIPT_DIR/test_skips.sh"

MAX_OUT_LINES="${MAX_OUT_LINES:-200}"
# A healthy test finishes in well under a second; the timeout only
# exists to catch a genuine hang. Kept generous so it never fires
# spuriously on a slow process *start* when many parallel clang/LTO
# jobs are saturating the CPU (heavy-link tests pull in
# libcurl/openssl/pq/sqlite, inflating loader cost under contention).
TIMEOUT="${TIMEOUT:-60}"
JOBS="${NURL_TEST_JOBS:-$(nproc 2>/dev/null || echo 4)}"

# `timeout(1)` is coreutils on Linux and base on FreeBSD, but macOS ships
# neither — there it arrives as `gtimeout` with Homebrew coreutils. Resolve
# the name once. With no watchdog at all a hung test would wedge the whole
# runner forever, so say so loudly rather than discovering it as a stalled
# CI job; the run continues, because a corpus that cannot run is worse than
# one that cannot bound a hang.
TIMEOUT_CMD=""
if command -v timeout >/dev/null 2>&1; then TIMEOUT_CMD="timeout"
elif command -v gtimeout >/dev/null 2>&1; then TIMEOUT_CMD="gtimeout"
else
    echo "WARNING: neither timeout nor gtimeout on PATH — tests run unbounded." >&2
    echo "         On macOS: brew install coreutils" >&2
fi

mkdir -p "$OUTDIR" "$WORKDIR"

# Append out_file to dst, capping lines to avoid runaway-output
# golden explosions.
append_capped() {
    local dst="$1" out_file="$2" lines
    lines=$(wc -l < "$out_file")
    if [[ $lines -le $MAX_OUT_LINES ]]; then
        cat "$out_file" >> "$dst"
    else
        head -n "$MAX_OUT_LINES" "$out_file" >> "$dst"
        printf '[... %d more lines truncated ...]\n' "$((lines - MAX_OUT_LINES))" >> "$dst"
    fi
}

# Strip the absolute repo-root prefix so records are checkout-portable.
# Strip the absolute repo root from a captured file so diagnostics compare
# path-stable against the golden. `sed -i` is NOT portable — GNU edits in
# place, but BSD sed (FreeBSD, macOS) requires a backup-suffix argument and
# otherwise mis-parses the script as the suffix (this silently left paths
# unstripped on FreeBSD). Write to a temp file and move it back instead.
strip_root() { sed "s|$ROOT_DIR/||g" "$1" > "$1.sr" && mv -f "$1.sr" "$1"; }

# ── run_one <name> ──────────────────────────────────────────────
#   Produces $WORKDIR/$name.actual (the record) and prints a single
#   verdict token to stdout: PASS | FAIL | MISSING | UPDATED | SKIP.
#   On FAIL it also writes $WORKDIR/$name.diff for the report.
run_one() {
    local name="$1"
    local src="$SCRIPT_DIR/$name.nu"
    local ll="$WORKDIR/$name.ll"
    local bin="$WORKDIR/$name"
    local out="$WORKDIR/$name.out"
    local err="$WORKDIR/$name.err"
    local act="$WORKDIR/$name.actual"
    local gold="$OUTDIR/$name.txt"
    rm -f "$ll" "$bin" "$out" "$err" "$act" "$WORKDIR/$name.diff"

    if [[ -n "$(is_skipped "$name")" ]]; then echo SKIP; return; fi

    # ── borrow_* — violations are compile errors; the diagnostic is
    #               baselined. borrow_strict_* only fire under the
    #               stricter checker flag.
    if [[ "$name" == borrow_* ]]; then
        local flag=""
        [[ "$name" == borrow_strict_* ]] && flag="--strict-borrowck"
        if "$NURLC" $flag "$src" > "$ll" 2>"$err"; then
            { echo "COMPILE OK"; echo "(expected COMPILE FAIL but compiler accepted it)"; } > "$act"
        else
            { echo "COMPILE FAIL"; } > "$act"
            if [[ -s "$err" ]]; then strip_root "$err"; echo "ERRORS" >> "$act"; append_capped "$act" "$err"; fi
        fi
    # ── lint_* — diagnostics that only fire under --lint. Compiles
    #             clean (the program is valid); it is the WARNINGS that
    #             are baselined, so a lint that stops firing, starts
    #             firing somewhere new, or moves its caret is caught.
    elif [[ "$name" == lint_* ]]; then
        if "$NURLC" --lint "$src" > "$ll" 2>"$err"; then
            { echo "COMPILE OK"; } > "$act"
            if [[ -s "$err" ]]; then strip_root "$err"; echo "WARNINGS" >> "$act"; append_capped "$act" "$err"; fi
        else
            { echo "COMPILE FAIL"; echo "(expected COMPILE OK)"; } > "$act"
            if [[ -s "$err" ]]; then strip_root "$err"; append_capped "$act" "$err"; fi
        fi
    # ── arity_strict_* — the n-ary '&'/'|' trap, an error by default
    #                     (--strict-arity is kept as an explicit no-op
    #                     here). The diagnostic text is baselined
    #                     because WHERE it points is the point: it must
    #                     name the `?`, not the `{}` that finally
    #                     revealed the mistake.
    elif [[ "$name" == arity_strict_* ]]; then
        if "$NURLC" --strict-arity "$src" > "$ll" 2>"$err"; then
            { echo "COMPILE OK"; echo "(expected COMPILE FAIL but compiler accepted it)"; } > "$act"
        else
            { echo "COMPILE FAIL"; } > "$act"
            if [[ -s "$err" ]]; then strip_root "$err"; echo "ERRORS" >> "$act"; append_capped "$act" "$err"; fi
        fi
    # ── should_fail_* — COMPILE FAIL is the expected outcome ──
    elif [[ "$name" == should_fail_* ]]; then
        if "$NURLC" "$src" > "$ll" 2>"$err"; then
            { echo "COMPILE OK"; echo "(expected COMPILE FAIL but compiler accepted it)"; } > "$act"
        else
            echo "COMPILE FAIL" > "$act"
        fi
    # ── diag_* — like should_fail_ but the diagnostic TEXT is baselined
    #            (default flags, front-end stderr captured verbatim).
    #            For multi-error / diagnostic-quality regressions where
    #            WHAT was reported matters, not just that compilation
    #            failed.
    elif [[ "$name" == diag_* ]]; then
        if "$NURLC" "$src" > "$ll" 2>"$err"; then
            { echo "COMPILE OK"; echo "(expected COMPILE FAIL but compiler accepted it)"; } > "$act"
        else
            { echo "COMPILE FAIL"; } > "$act"
            if [[ -s "$err" ]]; then strip_root "$err"; echo "ERRORS" >> "$act"; append_capped "$act" "$err"; fi
        fi
    else
        # ── should_warn_* keep the compile diagnostic as WARNINGS ──
        local werr=""
        [[ "$name" == should_warn_* ]] && werr="$WORKDIR/$name.werr" && rm -f "$werr"
        local cerr="${werr:-$err}"
        if ! "$NURLC" "$src" > "$ll" 2>"$cerr"; then
            strip_root "$cerr"
            { echo "COMPILE FAIL"; echo "ERRORS"; } > "$act"; append_capped "$act" "$cerr"
        elif ! "$CLANG" -O2 -flto $OPAQUE_FLAGS "$ll" "$RUNTIME" $LINK_LIBS -o "$bin" 2>"$err"; then
            strip_root "$err"
            { echo "COMPILE OK"; echo "LINK FAIL"; } > "$act"; append_capped "$act" "$err"
        else
            # Each test runs in its OWN scratch dir so relative-path file
            # side effects (a test writing `out.txt`, creating `pkg/`, …)
            # can never collide with a sibling running concurrently. The
            # binary is hard-linked in and invoked as `./$name` so argv[0]
            # stays exactly `./$name` (some tests print it) — a copy-free
            # link, falling back to cp across filesystems.
            local rundir="$WORKDIR/run/$name"
            rm -rf "$rundir"; mkdir -p "$rundir"
            ln "$bin" "$rundir/$name" 2>/dev/null || cp "$bin" "$rundir/$name"
            # -k: plain `timeout` only sends SIGTERM, which a test spinning in
            # a tight loop can ignore indefinitely — such leftovers have been
            # found burning a core each 12 hours after their run. Declaring a
            # hang is not the same as ending it.
            ( cd "$rundir" && $TIMEOUT_CMD ${TIMEOUT_CMD:+-k 5s "${TIMEOUT}s"} "./$name" > "$out" 2>&1 ) 2>/dev/null
            local code=$?
            rm -rf "$rundir"
            { echo "COMPILE OK"; } > "$act"
            if [[ -n "$werr" && -s "$werr" ]]; then
                strip_root "$werr"; echo "WARNINGS" >> "$act"; append_capped "$act" "$werr"
            fi
            { echo "LINK OK"; printf 'EXIT %d\n' "$code"; echo "OUTPUT"; } >> "$act"
            append_capped "$act" "$out"
        fi
    fi

    # Byte-compare AFTER stripping trailing \r — the contract .gitattributes
    # documents ("test goldens are byte-compared after \r-normalisation").
    # Goldens are checked in as LF (`compiler/tests/outputs/*.txt text eol=lf`),
    # but three HTTP tests legitimately EMIT \r\n — they golden HTTP wire
    # output — so a raw cmp can only ever match on a checkout whose goldens
    # still carry CRLF, i.e. exactly the drift that stamped every release
    # binary "-dirty". The Windows runner (run_tests.ps1) already normalises;
    # this makes the posix runner honour the same contract.
    sed 's/\r$//' "$act" > "$act.nrm" && mv -f "$act.nrm" "$act"
    if [[ "$UPDATE" == "1" ]]; then cp "$act" "$gold"; echo UPDATED; return; fi
    if [[ ! -f "$gold" ]]; then echo MISSING; return; fi
    if cmp -s "$act" "$gold"; then echo PASS; else
        diff -u "$gold" "$act" > "$WORKDIR/$name.diff" 2>/dev/null
        echo FAIL
    fi
}
# is_skipped and its helpers are exported by test_skips.sh itself, so a
# runner cannot half-export the predicate set and gate differently in
# the workers than in the parent.
export -f run_one append_capped strip_root
export NURLC RUNTIME OUTDIR WORKDIR SCRIPT_DIR ROOT_DIR CLANG LINK_LIBS TIMEOUT_CMD OPAQUE_FLAGS
export MAX_OUT_LINES TIMEOUT UPDATE

# ── collect the test set ────────────────────────────────────────
shopt -s nullglob
all_tests=("$SCRIPT_DIR"/*.nu)
shopt -u nullglob
if [[ ${#all_tests[@]} -eq 0 ]]; then
    echo "ERROR: no .nu files in $SCRIPT_DIR" >&2; exit 2
fi
declare -a names=()
for src in "${all_tests[@]}"; do names+=("$(basename "$src" .nu)"); done
IFS=$'\n' names=($(printf '%s\n' "${names[@]}" | LC_ALL=C sort)); unset IFS

# When given explicit NAMEs (only with --update), restrict to those.
if [[ ${#ONLY[@]} -gt 0 ]]; then names=("${ONLY[@]}"); fi

# ── run in parallel ─────────────────────────────────────────────
printf '%s\n' "${names[@]}" \
    | xargs -P "$JOBS" -I{} bash -c 'echo "{} $(run_one "{}")"' \
    > "$WORKDIR/.verdicts" 2>/dev/null

# ── aggregate ───────────────────────────────────────────────────
pass=0 fail=0 missing=0 updated=0 skip=0
declare -a failed=() missed=()
while read -r name verdict; do
    case "$verdict" in
        PASS)    ((pass++)) ;;
        UPDATED) ((updated++)) ;;
        SKIP)    ((skip++)) ;;
        FAIL)    ((fail++));    failed+=("$name") ;;
        MISSING) ((missing++)); missed+=("$name") ;;
    esac
done < <(LC_ALL=C sort "$WORKDIR/.verdicts")

# ── orphan goldens (golden with no matching, non-skipped test) ──
declare -a orphans=()
if [[ ${#ONLY[@]} -eq 0 ]]; then
    shopt -s nullglob
    for g in "$OUTDIR"/*.txt; do
        gname="$(basename "$g" .txt)"
        if [[ ! -f "$SCRIPT_DIR/$gname.nu" ]]; then orphans+=("$gname"); fi
    done
    shopt -u nullglob
fi

# ── report ──────────────────────────────────────────────────────
status=0

if [[ "$UPDATE" == "1" ]]; then
    echo "Updated $updated golden(s); skipped $skip."
    [[ ${#orphans[@]} -gt 0 ]] && {
        echo "NOTE: ${#orphans[@]} orphan golden(s) remain (no .nu): ${orphans[*]}"
    }
    exit 0
fi

if [[ $fail -gt 0 ]]; then
    echo "=== $fail test(s) differ from their golden ==="
    for name in "${failed[@]}"; do
        echo; echo "--- $name ---"
        cat "$WORKDIR/$name.diff" 2>/dev/null
    done
    status=1
fi
if [[ $missing -gt 0 ]]; then
    echo
    echo "=== $missing test(s) have NO golden (run: run_tests.sh --update ${missed[*]}) ==="
    printf '  %s\n' "${missed[@]}"
    status=1
fi
if [[ ${#orphans[@]} -gt 0 ]]; then
    echo
    echo "=== ${#orphans[@]} orphan golden(s) — delete or add the .nu ==="
    printf '  %s\n' "${orphans[@]}"
    status=1
fi

echo
echo "PASS $pass · FAIL $fail · MISSING $missing · ORPHAN ${#orphans[@]} · SKIP $skip  (jobs=$JOBS)"
[[ $status -eq 0 ]] && echo "TESTS PASSED" || echo "TESTS FAILED"
exit "$status"
