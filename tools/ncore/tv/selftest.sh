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
# vok <fn> <.ll> [args]: a positive control: no mismatch in the module, and
# <fn> itself validated (not merely left unsupported)
vok() {
  local fn="$1" out; shift
  out="$(python3 "$ROOT/tools/ncore/tvdrops.py" "$@" -v)"
  case "$(echo "$out" | tail -1)" in *"mismatch 0"*) ;; *) return 1 ;; esac
  ! echo "$out" | grep -q "$fn[: ]"
}
vok __nurl_fn.f "$TMP/a.ll" || { echo "FAIL: the unedited program does not validate"; fail=1; }
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
# `= w v` with w's flag set outright, not handed v's, and v's kept: one
# value in two slots, each released (w's value is v's, not a new one)
mut moved_value_owned_by_both_slots 'if ($0 ~ /store i1 %r[0-9]+, i1\* %r13/) { print "  store i1 true, i1* %r13"; next } if ($0 ~ /store i1 0, i1\* %r4/) next; print'
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
# it right there. Nothing is handed on after it: on the path where `= w v`
# overwrites w, its first value leaks (D2's `new; off`), which D0 itself
# refuses now, and D0b too
awk -v W="$wslot" '/define i64 @__nurl_fn.f\(/{m=1} m && /^}/{m=0}
  { print }
  m && index($0, "* " W) && $1 == "store" && $2 !~ /^i1$/ { s = 1; next }
  m && s && /store i1 true, i1\* %r/ { f = $NF; print "  store i1 0, i1* " f; s = 0 }' "$TMP/a.ll" > "$TMP/handed.ll"
case "$(tv "$TMP/handed.ll")" in
  *"mismatch 1") echo "ok: never_moved_binding_cleared_with_nothing_handed_on caught (D0, a leak)" ;;
  *) echo "FAIL: never_moved_binding_cleared_with_nothing_handed_on not caught by D0"; fail=1 ;; esac
case "$(python3 "$ROOT/tools/ncore/tvdrops.py" "$TMP/handed.ll" --protect "$TMP/protect" | tail -1)" in
  *"mismatch 1") echo "ok: never_moved_binding_cleared_with_nothing_handed_on caught (D0b)" ;;
  *) echo "FAIL: never_moved_binding_cleared_with_nothing_handed_on not caught by D0b"; fail=1 ;; esac
# the same flag cleared where w's value is loaded for `keep w`: a hand-on to
# D0, which has no summary to say keep borrows; D0b refuses it (w is never
# moved), and D0c (keep's summary: a borrow, so w's value leaks)
wflag=$(awk -v W="$wslot" '/define i64 @__nurl_fn.f\(/{m=1} m && /^}/{m=0}
  m && index($0, "* " W) && $1 == "store" && $2 !~ /^i1$/ { s = 1; next }
  m && s && /store i1 true, i1\* %r/ { print $NF; exit }' "$TMP/a.ll")
awk -v W="$wslot" -v F="$wflag" '/define i64 @__nurl_fn.f\(/{m=1} m && /^}/{m=0}
  { print; if (m && index($0, "= load %Vec__i64, %Vec__i64* " W)) print "  store i1 0, i1* " F }' "$TMP/a.ll" > "$TMP/handed2.ll"
cmp -s "$TMP/a.ll" "$TMP/handed2.ll" && { echo "FAIL: the hand-on edit did not apply"; fail=1; }
case "$(tv "$TMP/handed2.ll")" in *"mismatch 0") ;; *) echo "FAIL: D0 refuses a plain hand-on"; fail=1 ;; esac
case "$(python3 "$ROOT/tools/ncore/tvdrops.py" "$TMP/handed2.ll" --protect "$TMP/protect" | tail -1)" in
  *"mismatch 1") echo "ok: never_moved_binding_handed_on caught (D0b)" ;;
  *) echo "FAIL: never_moved_binding_handed_on not caught"; fail=1 ;; esac
# D0c: what conservation alone cannot see, checked with the core IR's
# summaries (`--sums`): the edited LLVM still releases each value once
"$NURLC" --emit-core "$D/owner_assigned_on_one_branch.nu" > "$TMP/o.core" || exit 1
cv() { python3 "$ROOT/tools/ncore/tvdrops.py" "$1" --sums "$2" | tail -1; }
cmut() {  # cmut <name> <edited .ll> <core>
  case "$(cv "$2" "$3")" in *"mismatch 1") echo "ok: $1 caught (D0c)" ;; *) echo "FAIL: $1 not caught"; fail=1 ;; esac
}
vok __nurl_fn.f "$TMP/a.ll" --sums "$TMP/o.core" || { echo "FAIL: the unedited program does not validate with --sums"; fail=1; }
# (the hand-on above: keep borrows, so w's value is handed nowhere)
cmut never_moved_binding_cleared_before_a_borrow "$TMP/handed2.ll" "$TMP/o.core"
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
# the same parameter released unconditionally (`__dropif(true, …)`)
awk '/define i64 @__nurl_fn.keep\(/{m=1} m && /^}/{m=0}
  { if (m && /^  ret /) print "  call void @__dropif_Vec__i64(i1 true, ptr %r0)"; print }' "$TMP/a.ll" > "$TMP/lent1.ll"
cmut borrowed_parameter_released_unconditionally "$TMP/lent1.ll" "$TMP/o.core"
# f moves v into eat's `sink` on one branch; the edit keeps v's flag set
# there, so the frame releases what eat took
K="$D/binding_moved_into_a_sink_on_one_branch.nu"
"$NURLC" "$K" > "$TMP/k.ll" || exit 1
"$NURLC" --emit-core "$K" > "$TMP/k.core" || exit 1
vok __nurl_fn.f "$TMP/k.ll" --sums "$TMP/k.core" || { echo "FAIL: the sink program does not validate"; fail=1; }
awk '/define i64 @__nurl_fn.f\(/{m=1} m && /^}/{m=0}
  { if (m && /^then_1:/) t = 1; if (t && m && /store i1 0, i1\*/ && !c++) next; print }' "$TMP/k.ll" > "$TMP/given.ll"
case "$(tv "$TMP/given.ll")" in *"mismatch 0") ;; *) echo "FAIL: D0 alone was expected to miss the sink's double ownership"; fail=1 ;; esac
cmut a_move_released_instead "$TMP/given.ll" "$TMP/k.core"
# v's flag cleared where the frame releases it on the path that does not
# call eat: nothing takes v (D2's `new; off; drop`), a leak conservation
# alone accepted
awk '/define i64 @__nurl_fn.f\(/{m=1} m && /^}/{m=0}
  { if (m && /^end_3:/) e = 1
    if (e && m && /= load i1, i1\* %r[0-9]+$/ && !c++) print "  store i1 0, i1* " $NF
    print }' "$TMP/k.ll" > "$TMP/off.ll"
cmp -s "$TMP/k.ll" "$TMP/off.ll" && { echo "FAIL: the flag-clear edit did not apply"; fail=1; }
case "$(tv "$TMP/off.ll")" in
  *"mismatch 1") echo "ok: flag_cleared_with_nothing_handed_on caught (D0)" ;;
  *) echo "FAIL: flag_cleared_with_nothing_handed_on not caught"; fail=1 ;; esac
cmut flag_cleared_with_nothing_handed_on "$TMP/off.ll" "$TMP/k.core"
# the value handed to eat through a `__nurl_cloneifk` whose key is false:
# the result is v itself, and the frame still releases it
awk '/define i64 @__nurl_fn.f\(/{m=1} m && /^}/{m=0}
  { if (m && /^then_1:/) t = 1; if (t && m && /store i1 0, i1\*/ && !c++) next
    if (t && m && /call i64 @__nurl_fn.eat\(/) {
      print "  %kc = call %Vec__i64 @__nurl_cloneifk_Vec__i64(ptr @.__nurl_sink.0, i1 true, %Vec__i64 %r16)"
      sub(/%Vec__i64 %r16\)/, "%Vec__i64 %kc)") }
    print }' "$TMP/k.ll" > "$TMP/kclone.ll"
grep -q "@.__nurl_sink.0 = private constant i1 false" "$TMP/kclone.ll" && grep -q "eat(%Vec__i64 %kc)" "$TMP/kclone.ll" \
  || { echo "FAIL: the cloneifk edit did not apply"; fail=1; }
cmut a_move_through_a_cloneifk_of_the_value_itself_released_instead "$TMP/kclone.ll" "$TMP/k.core"
# eat takes a constant beside its `sink` (`eat(%Vec__i64 %v, i64 0)`): the
# same mistake, at a call whose every argument must be read
C="$D/binding_moved_into_a_sink_beside_a_constant_argument.nu"
"$NURLC" "$C" > "$TMP/c.ll" || exit 1
"$NURLC" --emit-core "$C" > "$TMP/c.core" || exit 1
grep -q "call i64 @__nurl_fn.eat(%Vec__i64 %r[0-9]*, i64 0)" "$TMP/c.ll" || { echo "FAIL: eat's constant argument is not in the LLVM"; fail=1; }
vok __nurl_fn.f "$TMP/c.ll" --sums "$TMP/c.core" || { echo "FAIL: the constant-argument sink program does not validate"; fail=1; }
awk '/define i64 @__nurl_fn.f\(/{m=1} m && /^}/{m=0}
  { if (m && /^then_1:/) t = 1; if (t && m && /store i1 0, i1\*/ && !c++) next; print }' "$TMP/c.ll" > "$TMP/cgiven.ll"
cmut a_move_beside_a_constant_argument_released_instead "$TMP/cgiven.ll" "$TMP/c.core"
# f hands eat a clone of a Vec's element (`__nurl_cloneif(i1 true, …)`), and
# keep borrows its parameter: the edits hand the clone to eat twice, and
# keep's parameter, as it came (`%v`), to eat
E="$D/element_clone_handed_to_a_sink_beside_a_borrowing_function.nu"
"$NURLC" "$E" > "$TMP/e.ll" || exit 1
"$NURLC" --emit-core "$E" > "$TMP/e.core" || exit 1
grep -q "call %Vec__i64 @__nurl_cloneif_Vec__i64(i1 true," "$TMP/e.ll" || { echo "FAIL: f's known clone is not in the LLVM"; fail=1; }
vok __nurl_fn.f "$TMP/e.ll" --sums "$TMP/e.core" || { echo "FAIL: the clone program does not validate"; fail=1; }
vok __nurl_fn.keep "$TMP/e.ll" --sums "$TMP/e.core" || { echo "FAIL: the clone program's keep does not validate"; fail=1; }
awk '/define i64 @__nurl_fn.f\(/{m=1} m && /^}/{m=0}
  { print; if (m && /= call i64 @__nurl_fn.eat\(%Vec__i64 %r[0-9]+\)/) { l = $0; sub(/%r[0-9]+ = /, "%e2 = ", l); print l } }' "$TMP/e.ll" > "$TMP/clone2.ll"
grep -q "%e2 = call i64 @__nurl_fn.eat" "$TMP/clone2.ll" || { echo "FAIL: the second handover edit did not apply"; fail=1; }
cmut a_known_clone_handed_to_a_sink_twice "$TMP/clone2.ll" "$TMP/e.core"
awk '/define i64 @__nurl_fn.keep\(/{m=1} m && /^}/{m=0}
  { if (m && /^  ret /) print "  %kz = call i64 @__nurl_fn.eat(%Vec__i64 %v)"; print }' "$TMP/e.ll" > "$TMP/lentp.ll"
cmut a_borrowed_parameter_register_handed_to_a_sink "$TMP/lentp.ll" "$TMP/e.core"
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
# b registered under the journal-only temporary's flag, not its own: the
# drain would release b by a flag that does not say whether b owns
jmut registered_with_another_flag 'if ($0 ~ /nurl_journal_push_drop2\(ptr %r2, ptr %r3,/) sub(/ptr %r3,/, "ptr %k11,"); print'
# the calls that may panic made indirect, through a pointer, and b's
# registration deleted: an indirect call may panic as a direct one does
jmut registration_missing_before_an_indirect_call 'if ($0 ~ /nurl_journal_push_drop2\(ptr %r2,/) next
  if ($0 ~ /call %Bomb @__nurl_fn\.(bomb|late)\(i64 1\)/) { n++; print "  %fp" n " = select i1 true, ptr @__nurl_fn.late, ptr @__nurl_fn.bomb"; sub(/@__nurl_fn\.(bomb|late)\(/, "%fp" n "(") }
  print'
# flat moves b into w (`: Bomb w b`), then hands w to eat's `sink`, with
# calls that may panic between: each edit delays a flag's clear past such a
# call, which plain conservation accepts (each value is released once)
M="$D/binding_moved_then_handed_to_a_sink_across_calls_that_may_panic.nu"
"$NURLC" "$M" > "$TMP/m.ll" || exit 1
"$NURLC" --emit-core "$M" > "$TMP/m.core" || exit 1
mv_() { python3 "$ROOT/tools/ncore/tvdrops.py" "$1" --sums "$TMP/m.core" --journal --core "$TMP/m.core" "$NURLC" "${@:2}"; }
vok __nurl_fn.flat "$TMP/m.ll" --sums "$TMP/m.core" --journal --core "$TMP/m.core" "$NURLC" || { echo "FAIL: the moved-binding flat does not validate with the journal"; fail=1; }
mmut() {  # mmut <name> <flag slot> <call to delay its first clear past>
  awk -v F="$2" -v C="$3" '/define void @__nurl_fn.flat\(/{m=1} m && /^}/{m=0}
    { if (m && $0 == "  store i1 0, i1* " F && !c++) { held = $0; next }
      print; if (m && held != "" && index($0, C)) { print held; held = "" } }' "$TMP/m.ll" > "$TMP/$1.ll"
  cmp -s "$TMP/m.ll" "$TMP/$1.ll" && { echo "FAIL: the $1 edit did not apply"; fail=1; }
  case "$(python3 "$ROOT/tools/ncore/tvdrops.py" "$TMP/$1.ll" --sums "$TMP/m.core" | tail -1)" in
    *"mismatch 0") ;; *) echo "FAIL: D0c alone was expected to miss $1"; fail=1 ;; esac
  case "$(mv_ "$TMP/$1.ll" | tail -1)" in *"mismatch 1"*) echo "ok: $1 caught" ;; *) echo "FAIL: $1 not caught"; fail=1 ;; esac
}
# b's flag still set at late(n), after its value moved into w: one
# value registered twice, both enabled
flags=$(awk '/define void @__nurl_fn.flat\(/{m=1} m && /^}/{m=0} m' "$TMP/m.ll" | sed -n 's/.*push_drop2(ptr %r[0-9]*, ptr \(%r[0-9]*\),.*/\1/p')
bflag=$(echo "$flags" | sed -n 1p) wflag=$(echo "$flags" | sed -n 2p)
mmut one_value_journaled_twice_through_a_move "$bflag" "call %Bomb @__nurl_fn.late(i64 %n)"
# w's flag still set at late(0), after eat took its value
mmut journaled_after_a_sink_took_it "$wflag" "call %Bomb @__nurl_fn.late(i64 0)"
exit $fail
