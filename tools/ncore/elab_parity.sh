#!/usr/bin/env bash
# elab_parity.sh: the Lean translation of the scalar subset
# (`C.Elab.elabIR`, formal/C/Elab.lean, AGORA-1029 step 2) against the NURL
# translator (`nurl-cert translate`, packages/nurl-cert/src/tolean.nu), over
# every certify program, every hole probe, and the scalar programs of
# tools/ncore/elab_scalar/ (written for this test: each in the subset, so
# that the rules the certify programs do not reach are compared too). A
# parity test, not a proof.
#
#   tools/ncore/elab_parity.sh [programs.txt]
#
# For each program: its core IR (`nurlc --emit-core`, from the repo root),
# the IR as words (`nurl-cert words`) and the translator's term (`nurl-cert
# translate`). Then:
#   1. One Lean process runs `elabIR` over every program's words
#      (tools/ncore/elab_parity_run.lean; the words are handed over as JSON,
#      `nurl-cert words`'s literal with its escapes rewritten, since Lean
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
# The target: no DIFF, no LAX (every program elabIR answers for matches).
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
if [ -n "${PARITY_DIR:-}" ]; then W="$PARITY_DIR"; mkdir -p "$W"
else W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT; fi
[ -x "$NURLC" ] || { echo "no nurlc at $NURLC"; exit 1; }
[ -x "$CERT" ] || { echo "no nurl-cert at $CERT"; exit 1; }
command -v lake > /dev/null || export PATH="$HOME/.elan/bin:$PATH"

if [ $# -ge 1 ]; then cp "$1" "$W/progs.txt"
else { ls tools/ncore/certify/*.nu; find tools/fuzz/holes -name '*.nu' | sort; ls tools/ncore/elab_scalar/*.nu; } > "$W/progs.txt"; fi
nprog=$(wc -l < "$W/progs.txt")

# 0. Per program k: k.core, k.words (the Lean literal), k.json, k.tl and
#    k.rc (the translator's file and exit status), k.path.
rm -rf "$W/r"; mkdir -p "$W/r"
t0=$(date +%s)
nl -ba -w1 -s' ' "$W/progs.txt" | W="$W" NURLC="$NURLC" CERT="$CERT" ROOT="$ROOT" xargs -P "$JOBS" -L 1 bash -c '
    k="$0"; p="$1"; d="$W/r"
    printf "%s\n" "$p" > "$d/$k.path"
    if ! timeout 120 "$NURLC" --emit-core "$p" > "$d/$k.core" 2> /dev/null; then
        rm -f "$d/$k.core"; touch "$d/$k.nocore"; exit 0; fi
    if ! "$CERT" words "$d/$k.core" > "$d/$k.words" 2> /dev/null \
       || ! python3 "$ROOT/tools/ncore/elab_parity_json.py" "$d/$k.words" > "$d/$k.json"; then
        rm -f "$d/$k.json"; touch "$d/$k.nowords"; exit 0; fi
    "$CERT" translate "$d/$k.core" > "$d/$k.tl" 2> /dev/null; echo $? > "$d/$k.rc"'
t1=$(date +%s)

# 1. elabIR over every program's words, in one process.
ls "$W/r" | grep '\.json$' | sed 's/\.json$//' | sort -n > "$W/ok.txt"
sed "s|^\(.*\)$|$W/r/\1.json|" "$W/ok.txt" > "$W/json.txt"
(cd "$ROOT/formal" && lake env lean --run "$ROOT/tools/ncore/elab_parity_run.lean" "$W/json.txt") > "$W/run.txt" 2>&1
t2=$(date +%s)
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
  | _ => "?expr"
def r : Rhs → String
  | .expr x => s!".expr {e x}"
  | _ => "?rhs"
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
  | _ => "?stmt"
def fn (f : Fn) : String :=
  s!"params := {repr f.params}, resTy := {repr f.resTy}, resOwn := {f.resOwn}, body := {s f.body}, nvars := {f.nvars}"
end Show
EOF
: > "$W/verdicts.txt"
for k in $(awk '$2 == "some" {print $1}' "$W/run.txt" | sed 's|.*/||; s|\.json$||'); do
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
        echo "#eval IO.println (if C.Elab.elabIs ir T.P T.entry then \"match\" else"
        echo "  match C.Elab.elabIR ir with"
        echo "  | some (Q, e) => \"DIFF\\n\" ++ \"\\n\".intercalate (Q.map Show.fn) ++ \"\\nentry \" ++ Show.s e"
        echo "  | none => \"none\")"
        [ "$KERNEL" = 1 ] && echo "theorem same : C.Elab.elabIR ir = some (T.P, T.entry) := C.Elab.elabIs_sound _ _ _ (by decide +kernel)"
    } > "$f"
    out=$(cd "$ROOT/formal" && lake env lean "$f" 2>&1)
    v=$(printf '%s\n' "$out" | head -1)
    if [ "$v" = match ] && [ "$(printf '%s\n' "$out" | wc -l)" = 1 ]; then echo "match $p" >> "$W/verdicts.txt"
    elif [ "$v" = DIFF ]; then { echo "DIFF $p"; printf '%s\n' "$out" | tail -n +2; echo "translator:"; grep 'body :=' "$W/r/$k.tl"; } >> "$W/verdicts.txt"
    else { echo "ERROR $p"; printf '%s\n' "$out" | head -20; } >> "$W/verdicts.txt"; fi
done
t3=$(date +%s)

grep -v '^match ' "$W/verdicts.txt"
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
echo "matched: $(awk '$1 == "match" {print $2}' "$W/verdicts.txt" | tr '\n' ' ')"
echo "time, $JOBS jobs: IR and terms $((t1 - t0)) s, elabIR $((t2 - t1)) s, comparisons $((t3 - t2)) s"
[ "$(count DIFF)" = 0 ] && [ "$(count LAX)" = 0 ] && [ "$(count ERROR)" = 0 ] && [ "$(ls "$W/r" | grep -c '\.nowords$')" = 0 ]
