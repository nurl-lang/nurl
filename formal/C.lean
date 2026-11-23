import C.Check
import C.Join
import C.Call
import C.Sub
import C.Prog
import C.A2Expr

/-! Phase C: nurlc's implementation of the rules, checked. For A1, complete:
C0 the straight-line checker (`C/Check.lean`), C1 `ite` / `while` over
finite contexts (`C/Join.lean`), C2 subsumption by certificate
(`C/Sub.lean`), C3 calls (`C/Call.lean`), C4 whole programs
(`C/Prog.lean`, `C.checked_program_safe`). For A2: C5, its expressions
(`C/A2Expr.lean`). -/
