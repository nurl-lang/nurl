import C.Check
import C.Join
import C.Call
import C.Sub
import C.Prog
import C.A2Expr
import C.A2Rhs
import C.A2Stmt
import C.A2Data

/-! Phase C: nurlc's implementation of the rules, checked. For A1, complete:
C0 the straight-line checker (`C/Check.lean`), C1 `ite` / `while` over
finite contexts (`C/Join.lean`), C2 subsumption by certificate
(`C/Sub.lean`), C3 calls (`C/Call.lean`), C4 whole programs
(`C/Prog.lean`, `C.checked_program_safe`). For A2: C5, its expressions
(`C/A2Expr.lean`); C6, its core right-hand sides with `NoPin` / `DtorSafe`
decided (`C/A2Rhs.lean`); C7, its core statements with `EndOK` decided
(`C/A2Stmt.lean`); C8, its struct and enum right-hand sides (`C/A2Data.lean`). -/
