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
if python3 "$ROOT/tools/ncore/tvdrops.py" "$TMP/none.ll" -v | grep "__nurl_fn.f[: ]" >/dev/null; then
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
# third round of github#2242's review: each edit below validated before
# nv <name> <fn> <.ll> [args]: <fn> must not validate (unsupported, or a
# mismatch): what the edit does is not followed, and nothing is claimed
nv() {
  local n="$1" fn="$2" out; shift 2
  out="$(python3 "$ROOT/tools/ncore/tvdrops.py" "$@" -v)"
  if echo "$out" | grep "$fn[: ]" >/dev/null; then echo "ok: $n not validated"; else echo "FAIL: $n validated"; fail=1; fi
}
# a diamond added at f's join: one side gives a new slot B, the other gives
# it A, clears A's flag with A handed nowhere, then gives it B. The two
# sides meet in states that differ only in A, which is owed: the leaking
# side must not be taken for the other
awk '/define i64 @__nurl_fn.f\(/{m=1} m && /^}/{m=0}
  { if (m && /^  %r13 = alloca i1$/) { print; print "  %ms = alloca %Vec__i64"; print "  %mf = alloca i1"; next }
    if (m && /^end_3:$/) {
      print; print "  br i1 %r16, label %mt, label %me"; print "mt:"
      print "  %mb1 = call %Vec__i64 @__nurl_fn.vec_new__i64()"; print "  store %Vec__i64 %mb1, %Vec__i64* %ms"
      print "  store i1 true, i1* %mf"; print "  br label %mj"; print "me:"
      print "  %ma = call %Vec__i64 @__nurl_fn.vec_new__i64()"; print "  store %Vec__i64 %ma, %Vec__i64* %ms"
      print "  store i1 true, i1* %mf"; print "  store i1 0, i1* %mf"
      print "  %mb2 = call %Vec__i64 @__nurl_fn.vec_new__i64()"; print "  store %Vec__i64 %mb2, %Vec__i64* %ms"
      print "  store i1 true, i1* %mf"; print "  br label %mj"; print "mj:"; next }
    if (m && /^  ret i64 /) { print "  %mfl = load i1, i1* %mf"; print "  call void @__dropif_Vec__i64(i1 %mfl, ptr %ms)" }
    print }' "$TMP/a.ll" > "$TMP/join.ll"
grep -q "^mj:" "$TMP/join.ll" || { echo "FAIL: the join edit did not apply"; fail=1; }
case "$(tv "$TMP/join.ll")" in
  *"mismatch 1") echo "ok: a_leak_on_one_side_of_a_join_taken_for_the_other caught" ;;
  *) echo "FAIL: a_leak_on_one_side_of_a_join_taken_for_the_other not caught"; fail=1 ;; esac
# w's value moved in, and w's flag set to false, not to v's: v's flag is
# cleared first, then v is stored into w, which never owns it (nothing
# releases v). A store into a slot whose flag stays clear is no hand-on
awk '/define i64 @__nurl_fn.f\(/{m=1} m && /^}/{m=0}
  { if (m && /^then_1:/) t = 1
    if (t && m && $0 == "  store i1 0, i1* %r4") next
    if (t && m && /store i1 %r[0-9]+, i1\* %r13/) { print "  store i1 false, i1* %r13"; next }
    print; if (t && m && /= load %Vec__i64, %Vec__i64\* %r3$/ && !c++) print "  store i1 0, i1* %r4" }' "$TMP/a.ll" > "$TMP/dis.ll"
grep -q "store i1 false, i1\* %r13" "$TMP/dis.ll" || { echo "FAIL: the disabled-slot edit did not apply"; fail=1; }
cmut a_value_stored_into_a_slot_whose_flag_stays_clear "$TMP/dis.ll" "$TMP/o.core"
# `= w v` with the store of v into w deleted: w's flag is given v's, but w
# still holds its own (released) value. The flag copy says w owns v; it
# does not hold it
awk '/define i64 @__nurl_fn.f\(/{m=1} m && /^}/{m=0}
  { if (m && /^then_1:/) t = 1; if (t && m && /store %Vec__i64 %r[0-9]+, %Vec__i64\* %r12/ && !c++) next; print }' "$TMP/a.ll" > "$TMP/fcopy.ll"
cmp -s "$TMP/a.ll" "$TMP/fcopy.ll" && { echo "FAIL: the flag-copy edit did not apply"; fail=1; }
nv a_flag_copied_into_a_slot_that_does_not_hold_the_value __nurl_fn.f "$TMP/fcopy.ll"
# v's flag cleared, and v put into an aggregate that is thrown away (in
# place of eat's call): an aggregate is a hand-on only where it goes on
awk '/define i64 @__nurl_fn.f\(/{m=1} m && /^}/{m=0}
  { if (m && /^then_1:/) t = 1
    if (t && m && /= call i64 @__nurl_fn.eat\(%Vec__i64 %r[0-9]+\)/ && !c++) {
      r = $0; sub(/.*eat\(%Vec__i64 /, "", r); sub(/\).*/, "", r); res = $1
      print "  %ka = insertvalue { %Vec__i64 } undef, %Vec__i64 " r ", 0"; print "  " res " = add i64 0, 0"; next }
    print }' "$TMP/k.ll" > "$TMP/agg.ll"
grep -q "%ka = insertvalue" "$TMP/agg.ll" || { echo "FAIL: the aggregate edit did not apply"; fail=1; }
case "$(tv "$TMP/agg.ll")" in
  *"mismatch 1") echo "ok: a_cleared_value_moved_into_an_aggregate_thrown_away caught" ;;
  *) echo "FAIL: a_cleared_value_moved_into_an_aggregate_thrown_away not caught"; fail=1 ;; esac
# v stored, before its flag is cleared, to memory elsewhere through a
# `__nurl_cloneif` whose condition the path does not know, and not handed
# to eat: if that was a clone, v leaks; if not, it moved. Not followed
awk '/define i64 @__nurl_fn.f\(/{m=1} m && /^}/{m=0}
  { if (m && /^then_1:/) t = 1
    if (t && m && $0 == "  store i1 0, i1* %r4" && !d++) {
      print "  %kc = call %Vec__i64 @__nurl_cloneif_Vec__i64(i1 %r15, %Vec__i64 %r16)"
      print "  %kp = getelementptr i8, ptr null, i64 0"; print "  store %Vec__i64 %kc, ptr %kp" }
    if (t && m && /= call i64 @__nurl_fn.eat\(%Vec__i64 %r16\)/ && !c++) { print "  " $1 " = add i64 0, 0"; next }
    print }' "$TMP/k.ll" > "$TMP/earlyclone.ll"
grep -q "store %Vec__i64 %kc, ptr %kp" "$TMP/earlyclone.ll" && ! grep -q "eat(%Vec__i64 %r16)" "$TMP/earlyclone.ll" \
  || { echo "FAIL: the early-clone edit did not apply"; fail=1; }
nv a_value_handed_on_early_as_a_possible_clone __nurl_fn.f "$TMP/earlyclone.ll"
# a second known clone of the element, made and thrown away
awk '/define i64 @__nurl_fn.f\(/{m=1} m && /^}/{m=0}
  { print; if (m && /= call %Vec__i64 @__nurl_cloneif_Vec__i64\(i1 true, /) { l = $0; sub(/%r[0-9]+ = /, "%c2 = ", l); print l } }' "$TMP/e.ll" > "$TMP/clone0.ll"
grep -q "%c2 = call" "$TMP/clone0.ll" || { echo "FAIL: the thrown-away clone edit did not apply"; fail=1; }
cmut a_known_clone_thrown_away "$TMP/clone0.ll" "$TMP/e.core"
# keep's parameter stored into its slot (which only ever holds it, so has
# no flag), loaded back and handed to eat's `sink`
awk '/define i64 @__nurl_fn.keep\(/{m=1} m && /^}/{m=0}
  { if (m && /^  ret /) { print "  %kb = load %Vec__i64, %Vec__i64* %r0"; print "  %kz = call i64 @__nurl_fn.eat(%Vec__i64 %kb)" }
    print }' "$TMP/e.ll" > "$TMP/lents.ll"
cmut a_borrowed_parameter_loaded_from_its_slot_handed_to_a_sink "$TMP/lents.ll" "$TMP/e.core"
# (--journal) b stored into the journal-only temporary in place of the
# `bomb 1` value, registered there, and taken out of the aggregate: b's
# flag is cleared with b handed nowhere. The journal-only slot is no owner
# the frame releases by, and its forget hands nothing on
awk '/define void @__nurl_fn.flat\(/{m=1} m && /^}/{m=0}
  { if (m && /= insertvalue %Two zeroinitializer, %Bomb %r6, 0$/) sub(/%Bomb %r6, 0$/, "%Bomb zeroinitializer, 0")
    if (m && (/^  store %Bomb %r8, ptr %j11$/ || /^  store i1 true, ptr %k11$/ || /push_drop2\(ptr %j11, /)) next
    if (m && $0 == "  store i1 0, i1* %r3") {
      print "  store %Bomb %r6, ptr %j11"; print "  store i1 true, ptr %k11"
      print "  call void @nurl_journal_push_drop2(ptr %j11, ptr %k11, ptr @__jdrop_Bomb)" }
    print }' "$TMP/j.ll" > "$TMP/jalias.ll"
grep -q "store %Bomb %r6, ptr %j11" "$TMP/jalias.ll" || { echo "FAIL: the journal-alias edit did not apply"; fail=1; }
case "$(jv "$TMP/jalias.ll")" in *mismatch*) echo "ok: a_value_cleared_beside_a_journal_only_alias caught" ;;
  *) echo "FAIL: a_value_cleared_beside_a_journal_only_alias not caught"; fail=1 ;; esac
# (--journal) w's flag cleared ahead of late(n), which may panic, and w
# handed to eat after it: on the panic edge no enabled registration holds
# w's value, and eat is never reached
awk -v F="$wflag" '/define void @__nurl_fn.flat\(/{m=1} m && /^}/{m=0}
  { if (m && $0 == "  store i1 0, i1* " F) next
    if (m && index($0, "call %Bomb @__nurl_fn.late(i64 %n)")) print "  store i1 0, i1* " F
    print }' "$TMP/m.ll" > "$TMP/panicowed.ll"
cmp -s "$TMP/m.ll" "$TMP/panicowed.ll" && { echo "FAIL: the panic-edge edit did not apply"; fail=1; }
case "$(python3 "$ROOT/tools/ncore/tvdrops.py" "$TMP/panicowed.ll" --sums "$TMP/m.core" | tail -1)" in
  *"mismatch 0") ;; *) echo "FAIL: D0c alone was expected to miss a_cleared_value_across_a_call_that_may_panic"; fail=1 ;; esac
case "$(mv_ "$TMP/panicowed.ll" | tail -1)" in *"mismatch 1"*) echo "ok: a_cleared_value_across_a_call_that_may_panic caught" ;;
  *) echo "FAIL: a_cleared_value_across_a_call_that_may_panic not caught"; fail=1 ;; esac
# fourth round of github#2242's review: each edit below validated before.
# A function whose only release is by value (`__dropifv_T`), with no drop
# flag: keep releases the parameter it borrows. Such a function is checked,
# not skipped
awk '/define i64 @__nurl_fn.keep\(/{m=1} m && /^}/{m=0}
  { if (m && /^  ret /) print "  call void @__dropifv_Vec__i64(i1 true, %Vec__i64 %v)"; print }' "$TMP/e.ll" > "$TMP/lentv.ll"
grep -q "__dropifv_Vec__i64(i1 true, %Vec__i64 %v)" "$TMP/lentv.ll" || { echo "FAIL: the by-value release edit did not apply"; fail=1; }
cmut a_borrowed_parameter_released_by_value_with_no_drop_flag "$TMP/lentv.ll" "$TMP/e.core"
# (--journal) b registered in the journal-only temporary in place of the
# `bomb 1` value, and b's flag cleared before late(1): at that call the
# aggregate owes its hand-on, and the registration holds b, one value it
# carries, not the `bomb 1` value it carries too. Not claimed
awk '/define void @__nurl_fn.flat\(/{m=1} m && /^}/{m=0}
  { if (m && $0 == "  store %Bomb %r8, ptr %j11") { print "  store %Bomb %r6, ptr %j11"; next }
    if (m && $0 == "  store i1 0, i1* %r3") next
    if (m && index($0, "call %Bomb @__nurl_fn.late(i64 1)")) print "  store i1 0, i1* %r3"
    print }' "$TMP/j.ll" > "$TMP/jpart.ll"
grep -q "store %Bomb %r6, ptr %j11" "$TMP/jpart.ll" || { echo "FAIL: the partial-registration edit did not apply"; fail=1; }
nv an_aggregate_held_at_a_panic_by_a_registration_of_one_value_it_carries __nurl_fn.flat \
  "$TMP/jpart.ll" --journal --core "$TMP/j.core" "$NURLC"
# e's clone handed to eat's `sink`, then released by value under a flag
# whose value is not known: if it is set, eat's value is released twice.
# Under a flag known false, the release is nothing
awk '/define i64 @__nurl_fn.f\(/{m=1} m && /^}/{m=0}
  { print; if (m && /= call i64 @__nurl_fn.eat\(%Vec__i64 %r[0-9]+\)/) { r = $0; sub(/.*eat\(%Vec__i64 /, "", r); sub(/\).*/, "", r)
      print "  %kg = icmp sgt i64 %n, 5"; print "  call void @__dropifv_Vec__i64(i1 %kg, %Vec__i64 " r ")" } }' "$TMP/e.ll" > "$TMP/givenv.ll"
grep -q "__dropifv_Vec__i64(i1 %kg," "$TMP/givenv.ll" || { echo "FAIL: the guarded release edit did not apply"; fail=1; }
nv a_value_a_sink_took_released_by_value_under_an_unknown_flag __nurl_fn.f "$TMP/givenv.ll" --sums "$TMP/e.core"
sed 's/__dropifv_Vec__i64(i1 %kg,/__dropifv_Vec__i64(i1 false,/' "$TMP/givenv.ll" > "$TMP/givenv0.ll"
vok __nurl_fn.f "$TMP/givenv0.ll" --sums "$TMP/e.core" || { echo "FAIL: a release under a flag known false does not validate"; fail=1; }
# v's flag cleared on f's else side after a by-value release of what a
# `__nurl_cloneif` whose condition is not known returned: if that was a
# clone, v leaks. With the condition known false it is v, released
awk '/define i64 @__nurl_fn.f\(/{m=1} m && /^}/{m=0}
  { print; if (m && /^else_2:$/) {
      print "  %kx = load %Vec__i64, %Vec__i64* %r3"; print "  %kg = icmp sgt i64 %n, 5"
      print "  %kc = call %Vec__i64 @__nurl_cloneif_Vec__i64(i1 %kg, %Vec__i64 %kx)"
      print "  call void @__dropifv_Vec__i64(i1 true, %Vec__i64 %kc)"; print "  store i1 0, i1* %r4" } }' "$TMP/a.ll" > "$TMP/relclone.ll"
grep -q "%kc = call %Vec__i64 @__nurl_cloneif_Vec__i64(i1 %kg," "$TMP/relclone.ll" || { echo "FAIL: the possible-clone release edit did not apply"; fail=1; }
nv a_possible_clone_released_by_value_for_the_value_itself __nurl_fn.f "$TMP/relclone.ll" --sums "$TMP/o.core"
sed 's/@__nurl_cloneif_Vec__i64(i1 %kg,/@__nurl_cloneif_Vec__i64(i1 false,/' "$TMP/relclone.ll" > "$TMP/relorig.ll"
vok __nurl_fn.f "$TMP/relorig.ll" --sums "$TMP/o.core" || { echo "FAIL: a by-value release of the value itself does not validate"; fail=1; }
# mk moves two clones of vv's elements into the literal it returns
L="$D/element_clones_moved_into_a_returned_literal.nu"
"$NURLC" "$L" > "$TMP/l.ll" || exit 1
"$NURLC" --emit-core "$L" > "$TMP/l.core" || exit 1
grep -q "= insertvalue %Two %r[0-9]*, %Vec__i64 %r[0-9]*, 1" "$TMP/l.ll" || { echo "FAIL: mk's literal is not in the LLVM"; fail=1; }
vok __nurl_fn.mk "$TMP/l.ll" --sums "$TMP/l.core" || { echo "FAIL: the literal of two clones does not validate"; fail=1; }
lf='/define %Two @__nurl_fn.mk\(/'
# the literal stored into a field of mk's own (unused) %Two slot, and
# not returned: frame-local storage is no hand-on
awk "$lf"'{m=1} m && /^}/{m=0}
  { if (m && /^  ret %Two %r[0-9]+$/) { r = $3; print "  %kp = getelementptr %Two, ptr %r7, i32 0"
      print "  store %Two " r ", ptr %kp"; print "  ret %Two zeroinitializer"; next } print }' "$TMP/l.ll" > "$TMP/lstore.ll"
grep -q "store %Two %r[0-9]*, ptr %kp" "$TMP/lstore.ll" || { echo "FAIL: the frame-store edit did not apply"; fail=1; }
nv a_literal_stored_into_a_field_of_the_frames_own_slot __nurl_fn.mk "$TMP/lstore.ll" --sums "$TMP/l.core"
# the same store through a pointer a call returned, given the frame's own
# slot through a value not traced (a select): the call may hand it back
awk "$lf"'{m=1} m && /^}/{m=0}
  { if (m && /^  ret %Two %r[0-9]+$/) { r = $3; print "  %kp0 = select i1 true, ptr %r7, ptr %r7"; print "  %kp = call ptr @__nurl_fn.id_ptr(ptr %kp0)"
      print "  store %Two " r ", ptr %kp"; print "  ret %Two zeroinitializer"; next } print }' "$TMP/l.ll" > "$TMP/lcall.ll"
grep -q "call ptr @__nurl_fn.id_ptr(ptr %kp0)" "$TMP/lcall.ll" || { echo "FAIL: the call-returned pointer edit did not apply"; fail=1; }
nv a_literal_stored_through_a_pointer_a_call_returned_from_an_untraced_argument __nurl_fn.mk "$TMP/lcall.ll" --sums "$TMP/l.core"
# field 0, which holds the first clone, replaced in the literal returned:
# the result does not carry that clone
awk "$lf"'{m=1} m && /^}/{m=0}
  { if (m && /^  ret %Two %r[0-9]+$/) { print "  %kr = insertvalue %Two " $3 ", %Vec__i64 zeroinitializer, 0"; print "  ret %Two %kr"; next } print }' "$TMP/l.ll" > "$TMP/lrepl.ll"
grep -q "ret %Two %kr" "$TMP/lrepl.ll" || { echo "FAIL: the field-replacement edit did not apply"; fail=1; }
nv a_field_holding_a_clone_replaced_in_the_literal_returned __nurl_fn.mk "$TMP/lrepl.ll" --sums "$TMP/l.core"
# the same replacement with the literal's first field set in a block listed
# after the one that sets its second: a chain read in text order lost it
awk "$lf"'{m=1} m && /^}/{m=0}
  { if (m && /= insertvalue %Two zeroinitializer, %Vec__i64 %r[0-9]+, 0$/) { a = $0; print "  br label %kA"; print "kB:"; next }
    if (m && a != "" && /^  ret %Two %r[0-9]+$/) { print "  %kr = insertvalue %Two " $3 ", %Vec__i64 zeroinitializer, 0"; print "  ret %Two %kr"; print "kA:"; print a; print "  br label %kB"; next } print }' "$TMP/l.ll" > "$TMP/lreord.ll"
grep -q "^kA:" "$TMP/lreord.ll" || { echo "FAIL: the reordered-block edit did not apply"; fail=1; }
nv a_field_replaced_through_a_chain_whose_first_field_is_set_in_a_later_listed_block __nurl_fn.mk "$TMP/lreord.ll" --sums "$TMP/l.core"
# the first clone moved into both fields (the second clone not made): one
# value with two owners
awk "$lf"'{m=1} m && /^}/{m=0}
  { if (m && /= call %Vec__i64 @__nurl_cloneif_Vec__i64\(i1 true, /) { c++; if (c == 1) first = $1; else { second = $1; next } }
    if (m && second != "" && index($0, "%Vec__i64 " second ", 1")) sub("%Vec__i64 " second ", 1", "%Vec__i64 " first ", 1")
    print }' "$TMP/l.ll" > "$TMP/ltwice.ll"
[ "$(grep -c "@__nurl_cloneif_Vec__i64(i1 true" "$TMP/ltwice.ll")" = 1 ] || { echo "FAIL: the double-insertion edit did not apply"; fail=1; }
cmut one_clone_moved_into_two_fields "$TMP/ltwice.ll" "$TMP/l.core"
# a diamond before the literal's second field: one side stores the second
# clone into heap memory, the other moves it into an aggregate it stores
# there. The literal then takes it again: on the second side a value moved
# into an aggregate twice. The sides meet in states that differ only in
# what that aggregate, handed on, carries: they must not be merged
awk "$lf"'{m=1} m && /^}/{m=0}
  { if (m && /= call %Vec__i64 @__nurl_cloneif_Vec__i64\(i1 true, /) { c++; if (c == 2) {
      print; r = $1; print "  %kg = icmp eq i8* %r9, null"; print "  %kp = call i8* @nurl_malloc(i64 24)"
      print "  br i1 %kg, label %kt, label %ke"; print "kt:"; print "  store %Vec__i64 " r ", ptr %kp"; print "  br label %kj"
      print "ke:"; print "  %ka = insertvalue { %Vec__i64 } zeroinitializer, %Vec__i64 " r ", 0"
      print "  store { %Vec__i64 } %ka, ptr %kp"; print "  br label %kj"; print "kj:"; next } }
    print }' "$TMP/l.ll" > "$TMP/ljoin.ll"
grep -q "^kj:" "$TMP/ljoin.ll" || { echo "FAIL: the aggregate-join edit did not apply"; fail=1; }
cmut a_value_moved_twice_on_one_side_of_a_join_taken_for_the_other "$TMP/ljoin.ll" "$TMP/l.core"
# a slot of a literal aggregate type (`alloca { i1, %String }`, an option):
# f moves v into eat's `sink` on one branch. Such a slot's releases are
# checked as a named type's: each edit below validated before, when the
# slot was taken for another frame's
P="$D/option_owner_assigned_on_one_branch.nu"
"$NURLC" "$P" > "$TMP/p.ll" || exit 1
"$NURLC" --emit-core "$P" > "$TMP/p.core" || exit 1
grep -q "= alloca { i1, %String }" "$TMP/p.ll" || { echo "FAIL: f's option slot is not in the LLVM"; fail=1; }
vok __nurl_fn.f "$TMP/p.ll" --sums "$TMP/p.core" || { echo "FAIL: the option program does not validate"; fail=1; }
vok __nurl_fn.eat "$TMP/p.ll" --sums "$TMP/p.core" || { echo "FAIL: the option program's eat does not validate"; fail=1; }
pf='/define i64 @__nurl_fn.f\(/'
# v's flag cleared and v handed nowhere (eat's call taken out): a leak
awk "$pf"'{m=1} m && /^}/{m=0} { if (m && /= call i64 @__nurl_fn.eat\(/) { print "  " $1 " = add i64 0, 0"; next } print }' "$TMP/p.ll" > "$TMP/pleak.ll"
cmp -s "$TMP/p.ll" "$TMP/pleak.ll" && { echo "FAIL: the option leak edit did not apply"; fail=1; }
cmut an_option_slot_cleared_with_its_value_handed_nowhere "$TMP/pleak.ll" "$TMP/p.core"
# v released twice at the end
awk "$pf"'{m=1} m && /^}/{m=0} { print; if (m && /call void @__dropif___opt.String\(i1 %r[0-9]+, ptr %r[0-9]+\)/ && !c++) print }' "$TMP/p.ll" > "$TMP/ptwice.ll"
cmp -s "$TMP/p.ll" "$TMP/ptwice.ll" && { echo "FAIL: the option double-release edit did not apply"; fail=1; }
cmut an_option_slot_released_twice "$TMP/ptwice.ll" "$TMP/p.core"
# v's flag kept set where eat takes it: the frame releases what eat took
awk "$pf"'{m=1} m && /^}/{m=0} { if (m && /^then_1:/) t = 1; if (t && m && /store i1 0, i1\*/ && !c++) next; print }' "$TMP/p.ll" > "$TMP/pgiven.ll"
cmp -s "$TMP/p.ll" "$TMP/pgiven.ll" && { echo "FAIL: the option sink edit did not apply"; fail=1; }
cmut an_option_moved_into_a_sink_released_instead "$TMP/pgiven.ll" "$TMP/p.core"
# the option leak again with the slot's type written without spaces
# (`{i1,%String}`): one LLVM type either way, and an owning one
awk "$pf"'{m=1} m && /^}/{m=0} { if (m) gsub(/\{ i1, %String \}/, "{i1,%String}"); print }' "$TMP/pleak.ll" > "$TMP/pcompact.ll"
grep -q "= alloca {i1,%String}" "$TMP/pcompact.ll" || { echo "FAIL: the compact-type edit did not apply"; fail=1; }
cmut an_option_slot_of_a_type_written_without_spaces_left_owning "$TMP/pcompact.ll" "$TMP/p.core"
# every flag store of f made `volatile`: each sets its flag as a plain
# store does, so f still validates
awk "$fn"'{m=1} m && /^}/{m=0} { if (m) sub(/^  store i1 /, "  store volatile i1 "); print }' "$TMP/a.ll" > "$TMP/avol.ll"
grep -q "store volatile i1 " "$TMP/avol.ll" || { echo "FAIL: the volatile-store edit did not apply"; fail=1; }
vok __nurl_fn.f "$TMP/avol.ll" || { echo "FAIL: f with volatile flag stores does not validate"; fail=1; }
# an owning slot of f allocated with a count of two (an array): not read
awk "$fn"'{m=1} m && /^}/{m=0} { if (m && /= alloca %Vec__i64$/ && !c++) sub(/alloca %Vec__i64$/, "alloca %Vec__i64, i32 2"); print }' "$TMP/a.ll" > "$TMP/acount.ll"
grep -q "alloca %Vec__i64, i32 2" "$TMP/acount.ll" || { echo "FAIL: the alloca-count edit did not apply"; fail=1; }
nv an_owning_slot_allocated_with_a_count_of_two __nurl_fn.f "$TMP/acount.ll"
# give moves two clones into a literal and hands it to keep, which takes it:
# a clone it carries released after that releases what keep owns now
G="$D/literal_of_clones_handed_to_a_sink.nu"
"$NURLC" "$G" > "$TMP/g.ll" || exit 1
"$NURLC" --emit-core "$G" > "$TMP/g.core" || exit 1
vok __nurl_fn.give "$TMP/g.ll" --sums "$TMP/g.core" || { echo "FAIL: the literal handed to a sink does not validate"; fail=1; }
awk '/define void @__nurl_fn.give\(/{m=1} m && /^}/{m=0}
  { if (m && /= call %Vec__i64 @__nurl_cloneif_Vec__i64\(i1 true, / && c == "") c = $1
    print
    if (m && /call void @__nurl_fn.keep\(/) print "  call void @__dropifv_Vec__i64(i1 true, %Vec__i64 " c ")" }' "$TMP/g.ll" > "$TMP/grel.ll"
grep -q "call void @__dropifv_Vec__i64(i1 true, %Vec__i64 %r" "$TMP/grel.ll" || { echo "FAIL: the member-release edit did not apply"; fail=1; }
cmut a_clone_released_after_the_literal_carrying_it_was_handed_to_a_sink "$TMP/grel.ll" "$TMP/g.core"
exit $fail
