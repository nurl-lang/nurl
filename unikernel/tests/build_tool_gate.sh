#!/usr/bin/env bash
# ============================================================
#  unikernel/tests/build_tool_gate.sh — build_unikernel.sh is a TOOL,
#  not a repo-rooted script. The properties U0 bought, each asserted:
#
#    1. builds from a foreign cwd, with the source outside the repo,
#       stdlib imports resolving via the script's own NURL_STDLIB
#       default (this exact shape failed silently before U0);
#    2. never writes the repo when --out-dir and the cache point
#       elsewhere (the repo could be mounted read-only);
#    3. two concurrent builds of the same program produce
#       byte-identical ELFs (shared cold cache, separate out-dirs);
#    4. a program that does not compile fails LOUDLY — non-zero exit
#       and the compiler's message on stderr, not a bare exit 3.
#
#  Usage: build_tool_gate.sh        (exit 0 = all hold)
# ============================================================
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BUILD="$ROOT/unikernel/build_unikernel.sh"

if [ ! -x "$ROOT/build/nurlc" ]; then
    echo "build_tool_gate: SKIP (no build/nurlc — run ./build.sh first)"
    exit 0
fi

T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
fail=0
say() { echo "build_tool_gate: $*"; }

# A program whose stdlib import only resolves if the SCRIPT supplies
# NURL_STDLIB — the source lives outside the repo and so does the cwd.
cat > "$T/prog.nu" <<'EOF'
$ `stdlib/std/time.nu`

@ main → i {
    : i t ( now_ms )
    ? >= t 0 { ( nurl_println `ok` ) } {}
    ^ 0
}
EOF

# 1 + 2: foreign cwd, everything outside the repo, repo untouched.
marker="$T/marker"; touch "$marker"; sleep 1
if ! ( cd "$T" && env -u NURL_STDLIB NURL_UNIKERNEL_CACHE="$T/cache" \
        "$BUILD" "$T/prog.nu" --out-dir "$T/out1" >/dev/null 2>"$T/err1" ); then
    say "FAIL: foreign-cwd build failed:"; sed 's/^/  /' "$T/err1"; fail=1
fi
wrote=$(find "$ROOT" -newer "$marker" -not -path "$ROOT/.git/*" 2>/dev/null | head -3)
if [ -n "$wrote" ]; then
    say "FAIL: the build wrote into the repo:"; printf '  %s\n' $wrote; fail=1
fi

# 3: concurrent, cold shared cache, byte-identical images.
rm -rf "$T/cache2" "$T/out2" "$T/out3"
( env -u NURL_STDLIB NURL_UNIKERNEL_CACHE="$T/cache2" \
    "$BUILD" "$T/prog.nu" --out-dir "$T/out2" >/dev/null 2>&1 ) &
( env -u NURL_STDLIB NURL_UNIKERNEL_CACHE="$T/cache2" \
    "$BUILD" "$T/prog.nu" --out-dir "$T/out3" >/dev/null 2>&1 ) &
wait
if ! cmp -s "$T/out2/prog.elf" "$T/out3/prog.elf"; then
    say "FAIL: concurrent builds differ (or one did not finish)"; fail=1
fi

# 4: a broken program fails loudly.
printf '@ main → i {\n    ( nurl_println nope )\n    ^ 0\n}\n' > "$T/broken.nu"
if env NURL_UNIKERNEL_CACHE="$T/cache" \
        "$BUILD" "$T/broken.nu" --out-dir "$T/outb" >/dev/null 2>"$T/errb"; then
    say "FAIL: a broken program built successfully"; fail=1
elif ! grep -q "nurlc failed" "$T/errb"; then
    say "FAIL: the failure said nothing (stderr below):"
    sed 's/^/  /' "$T/errb"; fail=1
fi

if [ "$fail" = 0 ]; then
    echo "build_tool_gate: all four tool properties hold"
fi
exit $fail
