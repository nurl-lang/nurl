#!/usr/bin/env bash
# selftest.sh: D0's validator must catch what a wrong drop insertion does.
# The LLVM of owner_assigned_on_one_branch.nu validates; edits of it (and of
# the other programs here), each a codegen mistake, must each be reported
# as a mismatch.
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
# D0b: the core IR never moves f's `w`; a codegen that hands it on (its
# flag cleared while it owns) passes D0's conservation, not D0b
"$NURLC" --emit-core "$D/owner_assigned_on_one_branch.nu" > "$TMP/a.core" || exit 1
"$NURLC" --g "$D/owner_assigned_on_one_branch.nu" > "$TMP/a.g.ll" || exit 1
python3 "$ROOT/tools/ncore/tvir.py" "$TMP/a.core" "$TMP/a.g.ll" > "$TMP/protect"
wslot=$(awk '$1 == "__nurl_fn.f" {print $2; exit}' "$TMP/protect")
[ -n "$wslot" ] || { echo "FAIL: D0b found no never-moved binding in f"; fail=1; }
# its flag: the first one set after a store into the slot; the edit clears
# it right there
awk -v W="$wslot" '/define i64 @__nurl_fn.f\(/{m=1} m && /^}/{m=0}
  { print }
  m && index($0, "* " W) && $1 == "store" && $2 !~ /^i1$/ { s = 1; next }
  m && s && /store i1 true, i1\* %r/ { f = $NF; print "  store i1 0, i1* " f; s = 0 }' "$TMP/a.ll" > "$TMP/handed.ll"
case "$(tv "$TMP/handed.ll")" in *"mismatch 0") ;; *) echo "FAIL: D0 refuses a plain hand-on"; fail=1 ;; esac
case "$(python3 "$ROOT/tools/ncore/tvdrops.py" "$TMP/handed.ll" --protect "$TMP/protect" | tail -1)" in
  *"mismatch 1") echo "ok: never_moved_binding_handed_on caught (D0b)" ;;
  *) echo "FAIL: never_moved_binding_handed_on not caught"; fail=1 ;; esac
# D0c: what conservation alone cannot see, checked with the core IR's
# summaries (`--sums`): the edited LLVM still releases each value once
"$NURLC" --emit-core "$D/owner_assigned_on_one_branch.nu" > "$TMP/o.core" || exit 1
cv() { python3 "$ROOT/tools/ncore/tvdrops.py" "$1" --sums "$2" | tail -1; }
cmut() {  # cmut <name> <edited .ll> <core>
  case "$(cv "$2" "$3")" in *"mismatch 1") echo "ok: $1 caught (D0c)" ;; *) echo "FAIL: $1 not caught"; fail=1 ;; esac
}
case "$(cv "$TMP/a.ll" "$TMP/o.core")" in *"mismatch 0") ;; *) echo "FAIL: the unedited program does not validate with --sums"; fail=1 ;; esac
# w's release moved from its scope's end to before w is read
python3 - "$TMP/a.ll" "$TMP/early.ll" <<'PY'
import sys
L = open(sys.argv[1]).read().split("\n")
s = L.index(next(l for l in L if l.startswith("define i64 @__nurl_fn.f(")))
e = next(k for k in range(s, len(L)) if L[k] == "}")
end = next(k for k in range(s, e) if L[k] == "end_3:")
d = next(k for k in range(end, e) if "@__dropif_" in L[k])
pair = [L[d - 1], L[d]]
del L[d - 1:d + 1]
L[end + 1:end + 1] = pair
open(sys.argv[2], "w").write("\n".join(L))
PY
cmut release_moved_to_an_earlier_point "$TMP/early.ll" "$TMP/o.core"
# keep borrows its parameter (no `sink`); the edit gives it a flag and releases it
awk '/define i64 @__nurl_fn.keep\(/{m=1} m && /^}/{m=0}
  { if (m && /= alloca i64/) { print; print "  %xf = alloca i1"; next }
    if (m && /store %Vec__i64 %v,/) { print; print "  store i1 true, i1* %xf"; next }
    if (m && /^  ret /) { print "  %xl = load i1, i1* %xf"; print "  call void @__dropif_Vec__i64(i1 %xl, ptr %r0)" }
    print }' "$TMP/a.ll" > "$TMP/lent.ll"
case "$(tv "$TMP/lent.ll")" in *"mismatch 0") ;; *) echo "FAIL: D0 alone was expected to miss a borrowed parameter's release"; fail=1 ;; esac
cmut borrowed_parameter_released "$TMP/lent.ll" "$TMP/o.core"
# f moves v into eat's `sink` on one branch; the edit keeps v's flag set
# there, so the frame releases what eat took
K="$D/binding_moved_into_a_sink_on_one_branch.nu"
"$NURLC" "$K" > "$TMP/k.ll" || exit 1
"$NURLC" --emit-core "$K" > "$TMP/k.core" || exit 1
case "$(cv "$TMP/k.ll" "$TMP/k.core")" in *"mismatch 0") ;; *) echo "FAIL: the sink program does not validate"; fail=1 ;; esac
awk '/define i64 @__nurl_fn.f\(/{m=1} m && /^}/{m=0}
  { if (m && /^then_1:/) t = 1; if (t && m && /store i1 0, i1\*/ && !c++) next; print }' "$TMP/k.ll" > "$TMP/given.ll"
case "$(tv "$TMP/given.ll")" in *"mismatch 0") ;; *) echo "FAIL: D0 alone was expected to miss the sink's double ownership"; fail=1 ;; esac
cmut a_move_released_instead "$TMP/given.ll" "$TMP/k.core"
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
