import C.Elab
import Lean.Data.Json

/-! tools/ncore/elab_parity.sh, step 1: `C.Elab.elabIR` over many core IRs.
The argument is a file of paths, one per line, each a core IR's words as
JSON, each word its number (`elab_parity_json.py`). Prints `<path> some` or `<path> none` for
each, and `FULL <path> same` or `FULL <path> DIFFER` where the program's
full words are beside it (`.full.json`). Run: `cd formal && lake env lean --run ../tools/ncore/elab_parity_run.lean list`. -/

open Lean

def readIR (p : String) : IO C.Elab.IR := do
  let t ← IO.FS.readFile p
  let j ← IO.ofExcept (Json.parse t)
  let ls ← IO.ofExcept j.getArr?
  ls.toList.mapM fun l => do
    let ws ← IO.ofExcept l.getArr?
    ws.toList.mapM fun w => IO.ofExcept w.getNat?

def main (args : List String) : IO Unit := do
  let some list := args.head? | throw (IO.userError "usage: elab_parity_run <list of JSON paths>")
  let paths ← IO.FS.lines list
  for p in paths do
    let ir ← readIR p
    let r := C.Elab.elabIR ir
    IO.println s!"{p} {if r.isSome then "some" else "none"}"
    -- the full words beside it (`k.full.json`, every line): elabIR must
    -- answer the same on both (the words leave out a library function
    -- whose records the reader reads, and the `sum` lines no word names)
    let fp := String.ofList (p.toList.take (p.length - 5)) ++ ".full.json"
    if ← System.FilePath.pathExists fp then
      let same := match r, C.Elab.elabIR (← readIR fp) with
        | none, none => true
        | some (P, e), some (Q, e') => C.Elab.progBeq P Q && C.Elab.stmtBeq e e'
        | _, _ => false
      IO.println s!"FULL {p} {if same then "same" else "DIFFER"}"
