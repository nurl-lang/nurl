#!/usr/bin/env bash
# ============================================================
#  tests/nurlbox_test.sh — differential test suite.
#
#  nurlbox is a clone, so the specification is the original: every case
#  below runs the same command line through `nurlbox` and through the
#  system `busybox`, and the two must agree on stdout and on the exit
#  status. Where busybox is absent the case is skipped rather than
#  guessed at, and the cases with an explicit expectation still run.
#
#  Run from the package dir:  ./tests/nurlbox_test.sh
#  Env: NURL    build driver (defaults to ../../nurl.sh in a checkout)
#       NURLBOX pre-built binary to test instead of building one
#       BUSYBOX  reference binary (default: busybox on $PATH)
# ============================================================
set -u
cd "$(dirname "$0")/.."
PKG="$(pwd)"
REPO_ROOT="$(cd ../.. && pwd)"

if [ -n "${NURL:-}" ]; then :;
elif [ -x "$REPO_ROOT/nurl.sh" ]; then NURL="$REPO_ROOT/nurl.sh"; export NURL_STDLIB="${NURL_STDLIB:-$REPO_ROOT}";
else NURL="nurl"; fi

BUSYBOX="${BUSYBOX:-busybox}"
command -v "$BUSYBOX" >/dev/null 2>&1 && HAVE_BB=1 || HAVE_BB=0

WORK="$(mktemp -d -t nurlbox-test.XXXXXX)"
trap 'rm -rf "$WORK"' EXIT

if [ -n "${NURLBOX:-}" ]; then
    NB="$NURLBOX"
else
    echo "[build] src/main.nu"
    if ! (cd "$REPO_ROOT" && $NURL "$PKG/src/main.nu" "$WORK/nurlbox") >"$WORK/build.log" 2>&1; then
        echo "FAIL: build failed"; tail -30 "$WORK/build.log"; exit 1
    fi
    NB="$WORK/nurlbox"
fi

PASS=0; FAIL=0; SKIP=0
ok()   { PASS=$((PASS+1)); }
bad()  { echo "  FAIL $*"; FAIL=$((FAIL+1)); }

# ── fixtures ────────────────────────────────────────────────────────
FX="$WORK/fx"
mkdir -p "$FX/sub/deep" "$FX/empty"
printf 'alpha\nbravo\ncharlie\ndelta\n'            > "$FX/four.txt"
printf 'one two three\nfour  five\n\n\nsix\n'      > "$FX/words.txt"
printf 'no-final-newline'                          > "$FX/nonl.txt"
printf 'crlf one\r\ncrlf two\r\n'                  > "$FX/crlf.txt"
printf ''                                          > "$FX/empty.txt"
printf 'b\na\nc\na\n'                              > "$FX/dupes.txt"
seq 1 100                                          > "$FX/hundred.txt"
printf 'x\ty\tz\n1\t2\t3\n'                        > "$FX/tabs.txt"
printf 'sub file\n'                                > "$FX/sub/inner.txt"
printf 'deep file\n'                               > "$FX/sub/deep/leaf.txt"
head -c 4096 /dev/urandom                          > "$FX/binary.bin"

# ── the differential driver ─────────────────────────────────────────
#   dt [--stdin FILE] <applet> [args...]
dt() {
    local infile=""
    if [ "$1" = "--stdin" ]; then infile="$2"; shift 2; fi
    local desc="$*"
    if [ "$HAVE_BB" = 0 ]; then SKIP=$((SKIP+1)); return; fi
    local go bo gs bs
    if [ -n "$infile" ]; then
        go="$(cd "$FX" && "$NB" "$@" < "$infile" 2>/dev/null)"; gs=$?
        bo="$(cd "$FX" && "$BUSYBOX" "$@" < "$infile" 2>/dev/null)"; bs=$?
    else
        go="$(cd "$FX" && "$NB" "$@" 2>/dev/null)"; gs=$?
        bo="$(cd "$FX" && "$BUSYBOX" "$@" 2>/dev/null)"; bs=$?
    fi
    if [ "$go" = "$bo" ] && [ "$gs" = "$bs" ]; then
        ok
    else
        bad "$desc"
        if [ "$gs" != "$bs" ]; then echo "    exit: got $gs want $bs"; fi
        if [ "$go" != "$bo" ]; then
            diff <(printf '%s' "$bo" | cat -A) <(printf '%s' "$go" | cat -A) \
                 | head -8 | sed 's/^/    /'
        fi
    fi
}

# Byte-exact variant: compares raw bytes, so a trailing newline or a NUL
# is part of the comparison. `$(...)` strips trailing newlines, which is
# exactly what a `cat` test must not do.
dtb() {
    local infile=""
    if [ "$1" = "--stdin" ]; then infile="$2"; shift 2; fi
    local desc="$*"
    if [ "$HAVE_BB" = 0 ]; then SKIP=$((SKIP+1)); return; fi
    if [ -n "$infile" ]; then
        (cd "$FX" && "$NB" "$@" < "$infile" >"$WORK/g.out" 2>/dev/null); local gs=$?
        (cd "$FX" && "$BUSYBOX" "$@" < "$infile" >"$WORK/b.out" 2>/dev/null); local bs=$?
    else
        (cd "$FX" && "$NB" "$@" >"$WORK/g.out" 2>/dev/null); local gs=$?
        (cd "$FX" && "$BUSYBOX" "$@" >"$WORK/b.out" 2>/dev/null); local bs=$?
    fi
    if cmp -s "$WORK/g.out" "$WORK/b.out" && [ "$gs" = "$bs" ]; then
        ok
    else
        bad "$desc (bytes)"
        [ "$gs" != "$bs" ] && echo "    exit: got $gs want $bs"
        cmp "$WORK/b.out" "$WORK/g.out" 2>&1 | head -3 | sed 's/^/    /'
    fi
}

# Differential against GNU coreutils instead of busybox. Used where
# busybox simply does not implement the option (`cat -E`, `cat -s`) or
# where it takes a documented shortcut nurlbox declines to copy —
# busybox's `cat -n` appends a newline to a file that did not end in one,
# which rewrites the input. The reference is whichever tool implements
# the behaviour, not always the same tool.
dtg() {
    local infile=""
    if [ "$1" = "--stdin" ]; then infile="$2"; shift 2; fi
    local desc="$*" ref="$1"; shift
    command -v "$ref" >/dev/null 2>&1 || { SKIP=$((SKIP+1)); return; }
    if [ -n "$infile" ]; then
        (cd "$FX" && "$NB" "$ref" "$@" < "$infile" >"$WORK/g.out" 2>/dev/null); local gs=$?
        (cd "$FX" && "$ref" "$@" < "$infile" >"$WORK/b.out" 2>/dev/null); local bs=$?
    else
        (cd "$FX" && "$NB" "$ref" "$@" >"$WORK/g.out" 2>/dev/null); local gs=$?
        (cd "$FX" && "$ref" "$@" >"$WORK/b.out" 2>/dev/null); local bs=$?
    fi
    if cmp -s "$WORK/g.out" "$WORK/b.out" && [ "$gs" = "$bs" ]; then
        ok
    else
        bad "$desc (vs GNU)"
        [ "$gs" != "$bs" ] && echo "    exit: got $gs want $bs"
        cmp "$WORK/b.out" "$WORK/g.out" 2>&1 | head -3 | sed 's/^/    /'
    fi
}

# Compare as a set: both sides sorted before diffing. For output whose
# order is the filesystem's, not the tool's.
dtsort() {
    local desc="$*"
    if [ "$HAVE_BB" = 0 ]; then SKIP=$((SKIP+1)); return; fi
    local go bo gs bs
    go="$(cd "$FX" && "$NB" "$@" 2>/dev/null | sort)"; gs=$?
    bo="$(cd "$FX" && "$BUSYBOX" "$@" 2>/dev/null | sort)"; bs=$?
    if [ "$go" = "$bo" ]; then ok; else
        bad "$desc (set)"
        diff <(printf '%s' "$bo") <(printf '%s' "$go") | head -8 | sed 's/^/    /'
    fi
}

# Differential over a MUTATED tree. The command runs twice, each in its
# own pristine copy of the seed tree, and the two resulting trees are
# compared — names, contents and permission bits. That is the only
# honest way to test `cp` / `mv` / `rm` / `mkdir`: their output is the
# filesystem, not stdout.
seed_tree() {
    local d="$1"
    rm -rf "$d"; mkdir -p "$d/src/sub" "$d/dst" "$d/empty"
    printf 'alpha\n'  > "$d/src/a.txt"
    printf 'bravo\n'  > "$d/src/b.txt"
    printf 'deep\n'   > "$d/src/sub/c.txt"
    ln -s a.txt "$d/src/link"
    chmod 640 "$d/src/b.txt"
}

tree_digest() {
    (cd "$1" && find . | sort && find . -type f | sort | xargs -r md5sum | sed "s| .*/| |" \
     && find . -printf '%m %y %p\n' 2>/dev/null | sort)
}

dtfs() {
    local desc="$*"
    if [ "$HAVE_BB" = 0 ]; then SKIP=$((SKIP+1)); return; fi
    seed_tree "$WORK/ta"; seed_tree "$WORK/tb"
    local go bo gs bs
    go="$(cd "$WORK/ta" && "$NB" "$@" 2>&1)"; gs=$?
    bo="$(cd "$WORK/tb" && "$BUSYBOX" "$@" 2>&1)"; bs=$?
    local gd bd
    gd="$(tree_digest "$WORK/ta")"
    bd="$(tree_digest "$WORK/tb")"
    if [ "$gd" = "$bd" ] && [ "$gs" = "$bs" ]; then
        ok
    else
        bad "$desc (tree)"
        [ "$gs" != "$bs" ] && echo "    exit: got $gs want $bs  (stderr: $go)"
        diff <(printf '%s' "$bd") <(printf '%s' "$gd") | head -8 | sed 's/^/    /'
    fi
}

# Explicit expectation, for behaviour busybox does not have or where the
# reference is unavailable.
expect() {
    local desc="$1" want="$2"; shift 2
    local got; got="$(cd "$FX" && "$NB" "$@" 2>&1)"
    [ "$got" = "$want" ] && ok || bad "$desc (got '$got', want '$want')"
}

. "$PKG/tests/cases.sh"

echo
echo "== nurlbox: PASS=$PASS FAIL=$FAIL SKIP=$SKIP"
[ "$FAIL" = 0 ]
