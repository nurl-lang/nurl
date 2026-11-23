#!/usr/bin/env bash
# selftest.sh: D0's validator must catch what a wrong drop insertion does.
# The LLVM of owner_assigned_on_one_branch.nu validates; four edits of it,
# each a codegen mistake, must each be reported as a mismatch.
set -u
D="$(cd "$(dirname "$0")" && pwd)"; ROOT="$D/../../.."
NURLC="${NURLC:-$ROOT/build/nurlc}"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
"$NURLC" "$D/owner_assigned_on_one_branch.nu" > "$TMP/a.ll" || exit 1
tv() { python3 "$ROOT/tools/ncore/tvdrops.py" "$1" | tail -1; }
fail=0
case "$(tv "$TMP/a.ll")" in *"mismatch 0") ;; *) echo "FAIL: the unedited program does not validate"; fail=1 ;; esac
fn='/define i64 @__nurl_fn.f\(/'
# the flags and drops of f, by their order in the function
mut() {  # mut <name> <awk program over f's lines>
  awk "$fn{m=1} m && /^}/{m=0} {if (m) { $2 } else print}" "$TMP/a.ll" > "$TMP/$1.ll"
  case "$(tv "$TMP/$1.ll")" in *"mismatch 1") echo "ok: $1 caught" ;; *) echo "FAIL: $1 not caught"; fail=1 ;; esac
}
mut no_flag_clear_on_move 'if ($0 ~ /store i1 0, i1\*/ && !c++) next; print'
mut old_value_not_released 'if ($0 ~ /call void @__dropif_/ && !c++) next; print'
mut last_release_missing 'if ($0 ~ /call void @__dropif_/) { n++; if (n==2) next }; print'
mut released_twice 'print; if ($0 ~ /call void @__dropif_/) { n++; if (n==3) { sub(/^/, ""); print "  store i1 1, i1* %r4"; print } }'
exit $fail
