module

public import C.Check
public import C.Join
public import C.Call
public import C.Sub
public import C.Prog
public import C.A2Expr
public import C.A2Rhs
public import C.A2Stmt
public import C.A2Data
public import C.A2Chan
public import C.A2Pack
public import C.A2Call
public import C.A2Panic
public import C.A2Prog
public import C.A3Prog
public import C.A2Weaker
public import C.Dedup
public import C.A2Exit
public import C.A2Glue
public import C.DedupWitness
public import C.Cert
public import C.Cert3
public import C.Elab
public import C.ElabWitness
public import C.Complete
public import C.Complete3
public import C.CompleteWitness
public import C.Caps
public import C.CapsWitness
public import C.ResultWitness
public import C.Caps3

@[expose] public section

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
C15, conditional certificates (`C/Complete.lean`; threaded, `C/Complete3.lean`, AGORA-1015, AGORA-1040): a program
whose translation leaves functions out holds a stub at each (its signature,
callees and `hasThru`); `certOK2BA` checks the rest, and `cert_safe_cond`,
`cert_leak_end_cond` and `cert_leak_panic_cond` give A2's claims for every
completion in which the assumed functions are well-typed (`StmtT.complete`:
typing over the stubs is typing over any completion); `cond_witness_safe`
shows the hypotheses hold for a real program.
C16, what a program can run (`C/Caps.lean`, AGORA-1013): `capsOKB P s L`
checks that the entry and every function of `L` name only functions of `L`
(`A2/Reach.lean`, `A3/Reach.lean`: such a set holds every function a run
names); `caps_runs` and `caps3_runs` give, for the program, that one with
the same functions at the indices of `L` has the same runs and the same
interleavings: a function outside `L` is never entered. `reachB` computes
`L`, the closure of the entry's names.
`C/Elab.lean` (AGORA-1029): the core IR as words (`C.Elab.IR`) and its
reader, in the kernel, the first part of building the term inside it;
step 2, `C.Elab.elabIR`: the term of a scalar program built from those
words, tolean.nu's rules for that subset (`elabIs_sound`, `elab_while`),
widened by steps 4 to 9 to buffers, views, closures (`elab_clo`), structs
(`elab_struct`), options (`elab_opt`), destructor frames (`elab_dtor`:
a type with a `% Drop` of the program's own is A2's `.dtor f u`, its
values bound by `.letd`) and channels (`elab_chan`: a `Channel T` is A2's
lock share of its queue and closed flag, its calls `.lockNew`,
`.lockClone`, `.chanSend`, `.chanRecv`, `.chanClose`). -/
