import C.Check
import C.Join
import C.Call
import C.Sub
import C.Prog
import C.A2Expr
import C.A2Rhs
import C.A2Stmt
import C.A2Data
import C.A2Chan
import C.A2Pack
import C.A2Call
import C.A2Panic
import C.A2Prog
import C.A3Prog
import C.A2Weaker
import C.Dedup
import C.A2Exit
import C.A2Glue
import C.DedupWitness
import C.Cert
import C.Cert3
import C.Elab

/-! Phase C: nurlc's implementation of the rules, checked. For A1, complete:
C0 the straight-line checker (`C/Check.lean`), C1 `ite` / `while` over
finite contexts (`C/Join.lean`), C2 subsumption by certificate
(`C/Sub.lean`), C3 calls (`C/Call.lean`), C4 whole programs
(`C/Prog.lean`, `C.checked_program_safe`). For A2: C5, its expressions
(`C/A2Expr.lean`); C6, its core right-hand sides with `NoPin` / `DtorSafe`
decided (`C/A2Rhs.lean`); C7, its core statements with `EndOK` decided
(`C/A2Stmt.lean`); C8, its struct and enum right-hand sides (`C/A2Data.lean`); C8c, A3.2's lock and A3.4's channel right-hand sides (`C/A2Chan.lean`); C8p, closure literals that capture nothing by name (`C/A2Pack.lean`); C9, its calls, and the
checker that puts them together, `checkA2` (`C/A2Call.lean`); C10, `CtxWF` / `NameWF` decided and `panic`
(`C/A2Panic.lean`); C7w, `Weaker` decided and joins by weakening (`C/A2Weaker.lean`: an `ite` whose
arms end apart, a loop whose round ends weaker than it began); C7x, `exit` by obligations (`C/A2Exit.lean`); C11, its whole programs (`C/A2Prog.lean`,
`C.checked_program_safe2`). For A3: C12, its claim for a checked program,
spawned functions and globals included (`C/A3Prog.lean`,
`C.checked_claim_made_full`). The checkers keep dependency lists free of
duplicates (C7d, `C/Dedup.lean`, AGORA-988): a push or a call drops the
ones it makes, by one `sub` step, so re-pushing a slice no longer grows the
lists geometrically (`C/DedupWitness.lean`). C13, a program's certificate
(`C/Cert.lean`, AGORA-1019): the checker's verdict on one program as one
boolean (`certOK2B`), and A2's memory safety and leak freedom for it
(`cert_safe`, `cert_leak_end`, `cert_leak_panic`), the theorems a bundle of
`packages/nurl-cert` instantiates with its program's term. C14, a threaded
program's (`C/Cert3.lean`, AGORA-1020): `certOK3B` adds A3's conditions
(the spawned functions, no module global), and `cert3_safe`, `cert3_race`
and `cert3_leak` give A3's claim on every interleaving from the entry.
`C/Elab.lean` (AGORA-1029): the core IR as words (`C.Elab.IR`) and its
reader, in the kernel, the first part of building the term inside it. -/
