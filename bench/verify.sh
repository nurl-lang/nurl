#!/usr/bin/env bash
# bench/verify.sh — compile + run one program in every available language
# and assert their stdout is byte-identical. This is the correctness gate
# for the token-efficiency and generation-accuracy corpora (genacc/): a
# token or accuracy comparison only means something if every language
# computes the *same answer*.
#
# The timing suite has its own gate built into `bench/bench.sh`, which
# refuses to time a row whose five implementations disagree. This script
# covers the other direction — the genacc tasks, several of which are
# short string programs that are deliberately not benchmarks.
#
# Usage:  ./bench/verify.sh fib collatz ...   (default: the genacc tasks)
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BENCH="$ROOT/bench"
BUILD="$BENCH/_build"
mkdir -p "$BUILD"

NURLC="$ROOT/build/nurlc"
RUNTIME="$ROOT/stdlib/runtime.o"
CURL_LIBS=""; [[ -f "$ROOT/stdlib/runtime.curl"    ]] && CURL_LIBS="$(pkg-config --libs libcurl 2>/dev/null)"
SSL_LIBS="";  [[ -f "$ROOT/stdlib/runtime.openssl" ]] && SSL_LIBS="$(pkg-config --libs openssl 2>/dev/null)"
SQ_LIBS="";   [[ -f "$ROOT/stdlib/runtime.sqlite3" ]] && SQ_LIBS="$(pkg-config --libs sqlite3 2>/dev/null)"
PQ_LIBS="";   [[ -f "$ROOT/stdlib/runtime.pq"      ]] && PQ_LIBS="$(pkg-config --libs libpq 2>/dev/null)"
Z_LIBS="";    [[ -f "$ROOT/stdlib/runtime.z"       ]] && Z_LIBS="$(pkg-config --libs zlib 2>/dev/null)"
ZSTD_LIBS=""; [[ -f "$ROOT/stdlib/runtime.zstd"    ]] && ZSTD_LIBS="$(pkg-config --libs libzstd 2>/dev/null)"

run_nurl() {
    local n="$1" ll="$BUILD/$1.ll" bin="$BUILD/${1}_nurl"
    ( cd "$ROOT" && "$NURLC" "$BENCH/$n.nu" > "$ll" 2>"$BUILD/$n.nurl.err" ) || { echo "NURL-COMPILE-FAIL"; return 1; }
    clang -O2 -flto "$ll" "$RUNTIME" -lm -lpthread $CURL_LIBS $SSL_LIBS $SQ_LIBS $PQ_LIBS $Z_LIBS $ZSTD_LIBS \
        -o "$bin" 2>"$BUILD/$n.link.err" || { echo "NURL-LINK-FAIL"; return 1; }
    ( cd "$ROOT" && "$bin" )
}
run_py() { python3 "$BENCH/$1.py"; }
run_rs() { rustc -O "$BENCH/$1.rs" -o "$BUILD/${1}_rs" 2>"$BUILD/$1.rs.err" && "$BUILD/${1}_rs"; }
run_js() { node "$BENCH/$1.js"; }

benches=("$@")
if (( ${#benches[@]} == 0 )); then
    # The genacc task list (bench/genacc/tasks.json). Not every .nu file
    # in this directory belongs here: http_server.nu never exits, and
    # stdlib_hotpath.nu has no peers to compare against.
    benches=(fib collatz rot13 matmul quicksort sieve lcg words brackets csv_sum histogram)
fi

fail=0
for b in "${benches[@]}"; do
    declare -A out=()
    [[ -f "$BENCH/$b.nu" ]] && out[NURL]="$(run_nurl "$b")"
    [[ -f "$BENCH/$b.py" ]] && out[Python]="$(run_py "$b")"
    [[ -f "$BENCH/$b.rs" ]] && out[Rust]="$(run_rs "$b")"
    [[ -f "$BENCH/$b.js" ]] && out[Node]="$(run_js "$b")"

    ref=""; reflang=""
    ok=1
    for lang in NURL Python Rust Node; do
        [[ -v out[$lang] ]] || continue
        if [[ -z "$reflang" ]]; then ref="${out[$lang]}"; reflang="$lang"; continue; fi
        if [[ "${out[$lang]}" != "$ref" ]]; then ok=0; fi
    done

    if (( ok )); then
        printf '  %-14s OK   (= %q across %d langs)\n' "$b" "$ref" "${#out[@]}"
    else
        fail=1
        printf '  %-14s MISMATCH\n' "$b"
        for lang in NURL Python Rust Node; do
            [[ -v out[$lang] ]] && printf '      %-8s %q\n' "$lang" "${out[$lang]}"
        done
    fi
    unset out
done
exit $fail
