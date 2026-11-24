#!/usr/bin/env bash
# tolean_selftest.sh: the translator must fail closed on core IR it cannot
# render faithfully. Each case edits the core IR of a certify program and
# expects `unsupported`.
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
NURLC="${NURLC:-$ROOT/build/nurlc}"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
fail=0
tl() { python3 "$ROOT/tools/ncore/tolean.py" "$1" > /dev/null 2> "$TMP/err"; echo $?; }
"$NURLC" --emit-core "$ROOT/tools/ncore/certify/temporary_dropped_in_an_if_arm.nu" > "$TMP/a.core" || exit 1
[ "$(tl "$TMP/a.core")" = 0 ] || { echo "FAIL: the unedited program does not translate"; fail=1; }
# a read of the arm's temporary after the `if` (its drop is the arm's last
# line, so the rest of the arm's own list is empty; github#2242's review)
awk '/^fn\tmain\t/{m=1} m && /^drop 3$/ && !d {print; print "eval call string_len 1 v4"; d=1; next} {print}' \
  "$TMP/a.core" > "$TMP/b.core"
if [ "$(tl "$TMP/b.core")" = 2 ] && grep -q "read after its drop" "$TMP/err"; then
  echo "ok: read_after_an_arm_drop unsupported"
else
  echo "FAIL: read_after_an_arm_drop not reported"; fail=1
fi
exit $fail
