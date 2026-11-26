import C.Elab
import Lean.Data.Json

/-! tools/ncore/elab_parity.sh, step 1: `C.Elab.elabIR` over many core IRs.
The argument is a file of paths, one per line, each a core IR's words as
JSON (`elab_parity_json.py`). Prints `<path> some` or `<path> none` for
each. Run: `cd formal && lake env lean --run ../tools/ncore/elab_parity_run.lean list`. -/

open Lean

def readIR (p : String) : IO C.Elab.IR := do
  let t ← IO.FS.readFile p
  let j ← IO.ofExcept (Json.parse t)
  let ls ← IO.ofExcept j.getArr?
  ls.toList.mapM fun l => do
    let ws ← IO.ofExcept l.getArr?
    ws.toList.mapM fun w => IO.ofExcept w.getStr?

def main (args : List String) : IO Unit := do
  let some list := args.head? | throw (IO.userError "usage: elab_parity_run <list of JSON paths>")
  let paths ← IO.FS.lines list
  for p in paths do
    let ir ← readIR p
    IO.println s!"{p} {if (C.Elab.elabIR ir).isSome then "some" else "none"}"
