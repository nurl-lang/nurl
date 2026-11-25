#!/usr/bin/env bash
# measure.sh [prog.nu]: docs/dev/TRANSLATION_TRUST.md's two measurements.
# Writes the scratch Lean files under a temporary directory and times each
# with `lake env lean` in formal/: (a) the kernel splitting the core IR text
# (library splitOn; a structural scan), (b) the kernel over the same IR as
# words. Prints each run's result line and its wall time and peak RSS.
set -u
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
PROG="${1:-$ROOT/tools/ncore/certify/vec_push_len.nu}"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
cd "$ROOT" && "${NURLC:-$ROOT/build/nurlc}" --emit-core "$PROG" > "$T/p.core" || exit 1
N=$(grep -c "^fn	" "$T/p.core")
echo "core IR: $(wc -c < "$T/p.core") bytes, $N functions"
python3 - "$T/p.core" "$T" "$N" <<'PY'
import json, sys
core, out, n = open(sys.argv[1]).read(), sys.argv[2], sys.argv[3]
lit = json.dumps(core)
open(f"{out}/A.lean", "w").write(f"""def irText : String := {lit}
def countFn (s : String) : Nat := ((s.splitOn "\\n").filter (fun l => l.startsWith "fn\\t")).length
theorem a : countFn irText = {n} := by decide +kernel
""")
open(f"{out}/A2.lean", "w").write(f"""def irText : String := {lit}
def linesOf : List Char → List Char → List (List Char)
  | [], cur => [cur.reverse]
  | '\\n' :: r, cur => cur.reverse :: linesOf r []
  | c :: r, cur => linesOf r (c :: cur)
def isFn : List Char → Bool
  | 'f' :: 'n' :: '\\t' :: _ => true
  | _ => false
theorem a2 : ((linesOf irText.toList []).filter isFn).length = {n} := by decide +kernel
""")
rows = [l.split("\t") if l.startswith(("fn\t", "v\t", "ty\t", "sum\t")) else l.split()
        for l in core.splitlines() if l.strip()]
data = ",\n  ".join("[" + ", ".join(json.dumps(w) for w in r) + "]" for r in rows)
open(f"{out}/B.lean", "w").write(f"""def irData : List (List String) := [
  {data}]
def countFnB (ls : List (List String)) : Nat := (ls.filter (fun l => l.head? == some "fn")).length
theorem b : countFnB irData = {n} := by decide +kernel
""")
open(f"{out}/E.lean", "w").write("theorem e : True := trivial\n")
PY
cd "$ROOT/formal"
for f in E A A2 B; do
    r=$( { /usr/bin/time -f "%e s, %M KB" lake env lean "$T/$f.lean" 2>&1; } | tail -3 | tr '\n' ' ')
    echo "$f: $r"
done
