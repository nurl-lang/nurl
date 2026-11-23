#!/usr/bin/env bash
# selftest.sh: D0's validator must catch what a wrong drop insertion does.
# The LLVM of owner_assigned_on_one_branch.nu validates; four edits of it,
# each a codegen mistake, must each be reported as a mismatch.
set -u
D="$(cd "$(dirname "$0")" && pwd)"; ROOT="$(cd "$D/../../.." && pwd)"
NURLC="${NURLC:-$ROOT/build/nurlc}"
cd "$ROOT" || exit 1
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
# every release of f deleted: f must not validate (its owning slots are
# found from their types, not from the drops being checked)
awk "$fn{m=1} m && /^}/{m=0} {if (m && \$0 ~ /call void @__dropif_/) next; print}" "$TMP/a.ll" > "$TMP/none.ll"
if python3 "$ROOT/tools/ncore/tvdrops.py" "$TMP/none.ll" -v | grep -q "__nurl_fn.f[: ]"; then
  echo "ok: all_releases_deleted not validated"
else
  echo "FAIL: all_releases_deleted validated"; fail=1
fi
# D1, the panic journal: flat's registrations, edited
J="$D/bindings_journaled_across_a_call_that_may_panic.nu"
"$NURLC" "$J" > "$TMP/j.ll" || exit 1
"$NURLC" --emit-core "$J" > "$TMP/j.core" || exit 1
jv() { python3 "$ROOT/tools/ncore/tvdrops.py" "$1" --journal --core "$TMP/j.core" "$NURLC" -v | grep "__nurl_fn.flat[: ]"; }
if jv "$TMP/j.ll" | grep -q .; then echo "FAIL: flat does not validate with the journal"; fail=1; fi
jf='/define void @__nurl_fn.flat\(/'
jmut() {  # jmut <name> <awk program over flat's lines>
  awk "$jf{m=1} m && /^}/{m=0} {if (m) { $2 } else print}" "$TMP/j.ll" > "$TMP/$1.ll"
  case "$(jv "$TMP/$1.ll")" in *mismatch*) echo "ok: $1 caught" ;; *) echo "FAIL: $1 not caught"; fail=1 ;; esac
}
jmut registration_missing_before_a_panicking_call 'if ($0 ~ /nurl_journal_push_drop2/ && !c++) next; print'
jmut forget_missing_before_the_return 'if ($0 ~ /nurl_journal_forget_slot\(ptr %r2\)/) next; print'
jmut registered_twice 'print; if ($0 ~ /nurl_journal_push_drop2/ && !c++) print'
exit $fail
