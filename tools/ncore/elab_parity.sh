#!/usr/bin/env bash
# elab_parity.sh: the Lean translation of the subset of numbers, buffers of
# numbers, views, closures, structs, options, destructor frames, channels and
# threads (`C.Elab.elabIR`, `C.Elab.elabIR3`, formal/C/Elab.lean, AGORA-1029
# steps 2 and 4 to 10)
# against the NURL translator (`nurl-cert translate`,
# packages/nurl-cert/src/tolean.nu), over every certify program, every hole
# probe, and the programs of tools/ncore/elab/ (written for this test: each
# in the subset, so that the rules the certify programs do not reach are
# compared too). A parity test, not a proof.
#
#   tools/ncore/elab_parity.sh [programs.txt]
#
# For each program: its core IR (`nurlc --emit-core`, from the repo root),
# the IR as words (`nurl-cert words`) and the translator's term (`nurl-cert
# translate`). Then:
#   1. One Lean process runs `elabIR` over every program's words
#      (tools/ncore/elab_parity_run.lean; the words are handed over as JSON,
#      `nurl-cert words`'s literal, each word its number, since Lean
#      takes ~20 s to elaborate an 8000-line literal).
#   2. Each program `elabIR` answers a term for gets a Lean file of its own:
#      the translator's `P` and `entry` (in a namespace of their own), and
#        match  `elabIR ir = some (P, entry)`, by `C.Elab.elabIs` (sound:
#               `elabIs_sound`), checked by `decide +kernel` over the words
#               as a Lean literal (KERNEL=0: by #eval only)
#        DIFF   elabIR's term is not the translator's: the file prints
#               elabIR's functions in the translator's syntax
#        LAX    the translator refuses the program
#   Every other program is `none` (outside the subset).
#   3. The words leave out a library function whose records Lean's reader
#      reads (words.nu). elabIR also runs on every line of each core IR
#      (`elab_parity_full.py`), and its answer must be the same on both
#      (`progBeq`, `stmtBeq`), for every program.
# The target: no DIFF, no LAX (every program elabIR answers for matches),
# and elabIR the same on the words and on every line.
#
# Env: NURLC (default build/nurlc), NURL_CERT (default build/nurl-cert),
#      JOBS (default nproc), KERNEL (default 1), PARITY_DIR (keep the work
#      there; default a temporary directory, removed).
# Needs formal/ built (`cd formal && lake build C`) and python3 (the JSON
# rewrite only).
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"
NURLC="${NURLC:-$ROOT/build/nurlc}"
CERT="${NURL_CERT:-$ROOT/build/nurl-cert}"
JOBS="${JOBS:-$(nproc 2>/dev/null || echo 4)}"
KERNEL="${KERNEL:-1}"
if [ -n "${PARITY_DIR:-}" ]; then
    mkdir -p "$PARITY_DIR" || exit 1
    W="$(cd "$PARITY_DIR" && pwd)" || exit 1     # absolute: Lean runs in formal/
else W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT; fi
[ -x "$NURLC" ] || { echo "no nurlc at $NURLC"; exit 1; }
[ -x "$CERT" ] || { echo "no nurl-cert at $CERT"; exit 1; }
command -v lake > /dev/null || export PATH="$HOME/.elan/bin:$PATH"

# The programs every default sweep must find in the subset and matching:
# each program written for this test, and the certify programs in the
# subset. (A regression that makes elabIR answer `none` for one, or
# nurlc fail on one, is a failure, not one more program outside the subset.)
EXPECT_CERTIFY="cursor_over_a_vec int_recursion_early_return joins_each_freeing_a_different_vec
    loop_with_continue_and_break moved_on_one_branch_only moved_on_one_branch_then_read_refused
    owner_moved_in_a_loop_without_returning_refused owner_moved_only_on_an_early_return_from_a_loop
    owner_read_after_its_move_in_the_round_before_refused owners_rotated_in_a_loop
    raw_string_given_to_a_sink raw_string_read_after_its_sink_refused raw_strings_literal_and_fresh
    temporary_dropped_in_an_if_arm use_after_move_refused vec_element_read_after_its_move_refused
    vec_elements_read_between_pushes vec_push_len while_loop_summing
    view_taken_after_the_pushes view_kept_across_a_realloc_refused
    view_kept_across_pushes_in_a_loop_refused view_kept_across_a_clear_refused
    view_kept_across_a_reserve_refused string_copied_from_a_view_of_a_freed_string_refused
    string_pushed_its_own_view_refused vec_cleared_then_pushed vec_reserved_then_pushed
    foreach_summing_a_vec vec_pushed_while_iterated_refused raw_strings_held_in_a_vec
    raw_string_held_in_a_vec_past_its_source_refused
    clo_called_in_a_loop clo_called_on_a_moved_vec_refused clo_called_with_a_moved_vec_refused
    clo_changes_a_captured_vec clo_changes_a_captured_vec_under_a_slice_refused
    clo_no_captures_two_arguments clo_number_capture_called
    clo_returned_over_a_parameter_then_called_after_its_free_refused
    clo_returned_owning_a_vec_capture clo_returned_with_a_number_capture
    clo_string_capture_rebound_then_called_refused clo_string_captured_and_read_after
    clo_two_captures_passed_to_a_function
    struct_field_handed_to_a_reader struct_field_read_after_the_struct_moved_refused struct_fields_read
    vec_moved_into_a_struct vec_moved_into_a_struct_then_pushed_refused option_built_and_matched
    destructor_frame_left_by_an_early_return destructor_frame_left_by_an_early_return_after_its_source_moved_refused
    destructor_reads_a_view_of_a_live_source destructor_reads_a_view_of_a_moved_source_refused
    chan_int_sent_and_received chan_string_sent_and_received chan_string_read_after_its_send_refused
    thread_body_reads_a_vec_after_its_move_refused thread_channel_read_after_an_alias_took_it_refused
    thread_sends_on_a_channel_main_receives thread_spawned_with_a_number_capture"

# (the list is copied aside first: it may be the work directory's own
# progs.txt from an earlier run)
rm -f "$W/progs.new" "$W/expect.txt"
if [ $# -ge 1 ]; then
    cp "$1" "$W/progs.new" || { echo "elab_parity.sh: can not read the program list $1"; exit 1; }
else
    { ls tools/ncore/certify/*.nu && find tools/fuzz/holes -name '*.nu' | sort && ls tools/ncore/elab/*.nu; } > "$W/progs.new" \
        || { echo "elab_parity.sh: can not list the programs"; exit 1; }
fi
mv -f "$W/progs.new" "$W/progs.txt" || exit 1
{ ls tools/ncore/elab/*.nu; for c in $EXPECT_CERTIFY; do echo "tools/ncore/certify/$c.nu"; done; } > "$W/expect.txt"
nprog=$(grep -c '' "$W/progs.txt")       # records: a last one without its newline counts
[ "$nprog" -gt 0 ] || { echo "elab_parity.sh: no programs"; exit 1; }

# 0. Per program k: k.core, k.words (the Lean literal), k.json, k.tl and
#    k.rc (the translator's file and exit status), k.path.
rm -rf "$W/r"; mkdir -p "$W/r"
t0=$(date +%s)
# (index and path NUL-delimited: a path may hold spaces)
i=0; while IFS= read -r p || [ -n "$p" ]; do i=$((i + 1)); printf '%s\0%s\0' "$i" "$p"; done < "$W/progs.txt" \
  | W="$W" NURLC="$NURLC" CERT="$CERT" ROOT="$ROOT" xargs -0 -n 2 -P "$JOBS" bash -c '
    k="$0"; p="$1"; d="$W/r"
    printf "%s\n" "$p" > "$d/$k.path"
    if ! timeout 120 "$NURLC" --emit-core "$p" > "$d/$k.core" 2> /dev/null; then
        rm -f "$d/$k.core"; touch "$d/$k.nocore"; exit 0; fi
    if ! "$CERT" words "$d/$k.core" > "$d/$k.words" 2> /dev/null \
       || ! python3 "$ROOT/tools/ncore/elab_parity_json.py" "$d/$k.words" > "$d/$k.json"; then
        rm -f "$d/$k.json"; touch "$d/$k.nowords"; exit 0; fi
    python3 "$ROOT/tools/ncore/elab_parity_full.py" "$d/$k.core" > "$d/$k.full.json" || rm -f "$d/$k.full.json"
    "$CERT" translate "$d/$k.core" > "$d/$k.tl" 2> /dev/null; echo $? > "$d/$k.rc"'
t1=$(date +%s)

# 1. elabIR over every program's words, in one process.
ls "$W/r" | grep '^[0-9]*\.json$' | sed 's/\.json$//' | sort -n > "$W/ok.txt"
sed "s|^\(.*\)$|$W/r/\1.json|" "$W/ok.txt" > "$W/json.txt"
(cd "$ROOT/formal" && lake env lean --run "$ROOT/tools/ncore/elab_parity_run.lean" "$W/json.txt") > "$W/run.txt" 2>&1
rrc=$?
t2=$(date +%s)
if [ "$rrc" != 0 ]; then echo "elab_parity_run.lean failed (exit $rrc):"; tail -5 "$W/run.txt"; exit 1; fi
n_run=$(grep -c ' \(some\|none\)$' "$W/run.txt")
if [ "$n_run" != "$(wc -l < "$W/ok.txt")" ]; then
    echo "elab_parity_run.lean answered for $n_run of $(wc -l < "$W/ok.txt") programs:"; tail -5 "$W/run.txt"; exit 1; fi

# 2. Each program elabIR answers for, against the translator's term.
cat > "$W/show.lean" <<'EOF'
namespace Show
open A2
def e : Expr → String
  | .lit n => s!"(.lit {n})"
  | .var x => s!"(.var {x})"
  | .add a b => s!"(.add {e a} {e b})"
  | .lt a b => s!"(.lt {e a} {e b})"
  | .any => ".any"
  | .len x => s!"(.len {x})"
  | .slen x => s!"(.slen {x})"
  | .isl x => s!"(.isl {x})"
  | _ => "?expr"
def r : Rhs → String
  | .expr x => s!".expr {e x}"
  | .new t => s!".new {repr t}"
  | .var y => s!".var {y}"
  | .borrow y => s!".borrow {y}"
  | .at y i => s!".at {y} {e i}"
  | .view y => s!".view {y}"
  | .sat y i => s!".sat {y} {e i}"
  | .pair y z => s!".pair {y} {z}"
  | .fst y => s!".fst {y}"
  | .snd y => s!".snd {y}"
  | .inl y t => s!".inl {y} {repr t}"
  | .inr t y => s!".inr {repr t} {y}"
  | .getr y => s!".getr {y}"
  | .getl y => s!".getl {y}"
  | .pack fs te ms y cs => s!".pack {fs} {repr te} {ms} {y} {repr cs}"
  | _ => "?rhs"
def ed : Edit → String
  | .push y => s!"(.push {y})"
  | .trunc i => s!"(.trunc {e i})"
  | .set i y => s!"(.set {e i} {y})"
def s : Stmt → String
  | .skip => ".skip"
  | .seq a b => s!"(.seq {s a} {s b})"
  | .letv x q b => s!"(.letv {x} ({r q}) {s b})"
  | .letcall x f as b => s!"(.letcall {x} {f} [{", ".intercalate (as.map toString)}] {s b})"
  | .assign x q => s!"(.assign {x} ({r q}))"
  | .ite c a b => s!"(.ite {e c} {s a} {s b})"
  | .block a => s!"(.block {s a})"
  | .exit n => s!"(.exit {n})"
  | .loop a => s!"(.loop {s a})"
  | .push x y => s!"(.push {x} {y})"
  | .free x => s!"(.free {x})"
  | .edit t x o => s!"(.edit {t} {x} {ed o})"
  | .callc x c j σ zs b => s!"(.callc {x} {c} {j} {σ} [{", ".intercalate (zs.map toString)}] {s b})"
  | .letd x f q b => s!"(.letd {x} {f} ({r q}) {s b})"
  | _ => "?stmt"
def fn (f : Fn) : String :=
  s!"params := {repr f.params}, resTy := {repr f.resTy}, resOwn := {f.resOwn}, body := {s f.body}, nvars := {f.nvars}"
end Show
EOF
: > "$W/verdicts.txt"
# (the status is the line's last word; the path before it may hold spaces)
for k in $(sed -n 's|^.*/\([0-9][0-9]*\)\.json some$|\1|p' "$W/run.txt"); do
    p=$(cat "$W/r/$k.path")
    if [ "$(cat "$W/r/$k.rc")" != 0 ]; then
        { echo "LAX $p"; head -2 "$W/r/$k.tl"; } >> "$W/verdicts.txt"; continue; fi
    f="$W/r/$k.lean"
    {
        echo "import C.Elab"; echo "open A2 C"; echo "set_option maxRecDepth 1000000"; echo
        cat "$W/show.lean"; echo
        echo "namespace T"
        sed -e '/^import /d' -e '/^open /d' -e '/^#eval /d' "$W/r/$k.tl"   # the translator's term
        echo "end T"; echo
        cat "$W/r/$k.words"; echo; echo
        if grep -q '^def spawns ' "$W/r/$k.tl"; then
        # (step 10) a program that spawns: elabIR3, its spawn wrappers too
        echo "#eval IO.println (if C.Elab.elabIs3 ir T.P T.spawns T.entry then \"match\" else"
        echo "  match C.Elab.elabIR3 ir with"
        echo "  | some (Q, sq, e) => \"DIFF\\n\" ++ \"\\n\".intercalate (Q.map Show.fn) ++ \"\\nspawns \" ++ toString sq ++ \"\\nentry \" ++ Show.s e"
        echo "  | none => \"none\")"
        [ "$KERNEL" = 1 ] && echo "theorem same : C.Elab.elabIR3 ir = some (T.P, T.spawns, T.entry) := C.Elab.elabIs3_sound _ _ _ _ (by decide +kernel)"
        else
        echo "#eval IO.println (if C.Elab.elabIs ir T.P T.entry then \"match\" else"
        echo "  match C.Elab.elabIR ir with"
        echo "  | some (Q, e) => \"DIFF\\n\" ++ \"\\n\".intercalate (Q.map Show.fn) ++ \"\\nentry \" ++ Show.s e"
        echo "  | none => \"none\")"
        [ "$KERNEL" = 1 ] && echo "theorem same : C.Elab.elabIR ir = some (T.P, T.entry) := C.Elab.elabIs_sound _ _ _ (by decide +kernel)"
        fi
    } > "$f"
    out=$(cd "$ROOT/formal" && lake env lean "$f" 2>&1); lrc=$?
    v=$(printf '%s\n' "$out" | head -1)
    # (a match is Lean's exit status 0 too: the kernel check completed)
    if [ "$v" = match ] && [ "$lrc" = 0 ] && [ "$(printf '%s\n' "$out" | wc -l)" = 1 ]; then echo "match $p" >> "$W/verdicts.txt"
    elif [ "$v" = DIFF ]; then { echo "DIFF $p"; printf '%s\n' "$out" | tail -n +2; echo "translator:"; grep 'body :=' "$W/r/$k.tl"; } >> "$W/verdicts.txt"
    else { echo "ERROR $p"; printf '%s\n' "$out" | head -20; } >> "$W/verdicts.txt"; fi
done
t3=$(date +%s)

grep -v '^match ' "$W/verdicts.txt"
# every expected program that is in the list must match
missing=0
while IFS= read -r e; do
    grep -qFx -- "$e" "$W/progs.txt" || continue
    if ! grep -qFx -- "match $e" "$W/verdicts.txt"; then echo "EXPECTED a match: $e"; missing=$((missing + 1)); fi
done < "$W/expect.txt"
count() { grep -c "^$1 " "$W/verdicts.txt"; }
echo "programs:                     $nprog"
echo "nurlc failed:                 $(ls "$W/r" | grep -c '\.nocore$')"
echo "words failed:                 $(ls "$W/r" | grep -c '\.nowords$')"
echo "core IR read by elabIR:       $(wc -l < "$W/ok.txt")"
echo "  translated by tolean.nu:    $(cat "$W"/r/*.rc | grep -cx 0)"
echo "  elabIR some (the subset):   $(grep -c '^[A-Za-z]* ' "$W/verdicts.txt")"
echo "    match:                    $(count match)$( [ "$KERNEL" = 1 ] && echo ' (each also by decide +kernel)')"
echo "    DIFF:                     $(count DIFF)"
echo "    LAX (translator refuses): $(count LAX)"
echo "    errors:                   $(count ERROR)"
echo "  elabIR none:                $(grep -c ' none$' "$W/run.txt")"
n_full=$(grep -c '^FULL ' "$W/run.txt"); n_fdiff=$(grep -c '^FULL .* DIFFER$' "$W/run.txt")
grep '^FULL .* DIFFER$' "$W/run.txt" | head -5
echo "full words beside the words:  $n_full (elabIR differs on $n_fdiff)"
echo "expected matches missing:     $missing"
echo "matched: $(sed -n 's/^match //p' "$W/verdicts.txt" | tr '\n' ' ')"
echo "time, $JOBS jobs: IR and terms $((t1 - t0)) s, elabIR $((t2 - t1)) s, comparisons $((t3 - t2)) s"
[ "$missing" = 0 ] && [ "$n_fdiff" = 0 ] && [ "$n_full" = "$(wc -l < "$W/ok.txt")" ] && [ "$(count DIFF)" = 0 ] && [ "$(count LAX)" = 0 ] && [ "$(count ERROR)" = 0 ] && [ "$(ls "$W/r" | grep -c '\.nowords$')" = 0 ]
