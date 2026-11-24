import C.A2Prog
import A2.DtorWitness

/-! Body-level tests of the A2 deciders on `A2.DtorWitness`'s program: every
function there has a hand-written typing proof, and `fnOK2B` accepts each
one. Two of them are what github#2242's review found refused:
- `glue` (and `glueV`, `glueS`) takes apart a sink parameter of a
  destructor-wrapped struct, `.dtor 4 (.prod DT .int)`, whose destructor is
  the struct's glue (`unpairTyB`);
- `ofn` (and `ofnV`, `ofnR`) moves an enum payload out of a destructor
  type whose destructor is the enum's glue (`takeOKB`). -/

namespace C
open A2 A2.DtorWitness

example : fnOK2B P 4 glue = true := by decide
example : fnOK2B P 2 ofn = true := by decide
example : fnOK2B P 12 ofnR = true := by decide
example : (List.range P.length).all (fun f => match P[f]? with
    | some fn => fnOK2B P f fn
    | none => false) = true := by decide

end C
