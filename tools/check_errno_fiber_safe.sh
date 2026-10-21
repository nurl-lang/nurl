#!/usr/bin/env bash
# ============================================================
#  tools/check_errno_fiber_safe.sh — no errno access in the runtime may
#  survive a fiber park with a stale address.
#
#  errno is a thread-local behind a `const` accessor, so the compiler may
#  compute its address once and reuse it; a fiber that parks in between
#  can resume on another worker thread and read the wrong thread's errno.
#  stdlib/runtime_core.c routes every access through a volatile function
#  pointer (see the comment after its `#include <errno.h>`), which only
#  works if nothing calls the accessor directly. This gate compiles the
#  runtime to optimised LLVM IR and requires that exactly one function —
#  the pointer's target, nurl__errno_addr — calls it. A new header that
#  re-defines errno, an `#undef errno`, or a file compiled ahead of the
#  redefinition fails HERE instead of as a once-a-month EAGAIN misread
#  under load.
#
#  Linux (glibc/musl spell the accessor __errno_location); elsewhere it
#  reports a skip.
#
#  Usage:  tools/check_errno_fiber_safe.sh
#  Exit:   0 clean / skipped · 1 a direct accessor call · 2 setup error
# ============================================================
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CC="${CC:-clang}"
[ "$(uname -s)" = Linux ] || { echo "check_errno_fiber_safe: SKIP (not Linux)"; exit 0; }
command -v "$CC" >/dev/null || { echo "check_errno_fiber_safe: no $CC" >&2; exit 2; }
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

"$CC" -O2 -S -emit-llvm "$ROOT/stdlib/runtime.c" -o "$TMP/rt.ll" 2>"$TMP/cc.err" || {
    echo "check_errno_fiber_safe: stdlib/runtime.c does not compile" >&2
    head -5 "$TMP/cc.err" >&2
    exit 2
}
callers=$(awk '/^define /{ fn = $0; sub(/\(.*/, "", fn); sub(/.*@/, "", fn) }
               /call .*@__errno_location\(/ { print fn }' "$TMP/rt.ll" | sort -u)
bad=$(printf '%s\n' "$callers" | grep -v -x -e nurl__errno_addr -e '' || true)
if [ -n "$bad" ]; then
    echo "check_errno_fiber_safe: these functions read errno through a direct"
    echo "  __errno_location call, whose address the optimiser may reuse across"
    echo "  a fiber park (see stdlib/runtime_core.c after #include <errno.h>):"
    printf '    %s\n' $bad
    exit 1
fi
if [ "$callers" != nurl__errno_addr ]; then
    echo "check_errno_fiber_safe: nurl__errno_addr no longer calls __errno_location" >&2
    echo "  — the errno redirection is gone or renamed; update this gate with it" >&2
    exit 2
fi
echo "check_errno_fiber_safe: OK — every errno access goes through nurl__errno_fn"
