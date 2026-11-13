import A3.LockRoot

/-! A3 — Agora #818: **the claim, in full.**

`A3.claim` concludes memory safety, race freedom and no leak.  Its race
freedom counts a step on a cell (`CellOp`) as a cell's race, and `CellOp` asks
a step inside a check-out of the cell's block to hold an owner's share of the
cell: so it is adequate only if no check-out of a cell's block is without one.
`A3.reach_frame_cellOp` (A3/LockRoot.lean, from `A3.reach_shareKind` and
`A3.reach_frame_cell_owner`) proves that of every configuration a typed start
reaches.  This file puts the two together, as the stated claim
(`ClaimFull`: `A3.claim_full`, and from the program's declarations
`A3.claim_made_full`), on the same premises.

They are stated beside `Claim` and `claim_made`, not in their place, because
of where the proofs sit: `A3.reach_frame_cellOp` rests on the frame
invariants of A3/LockExcl.lean and A3/LockRoot.lean, which build on
A3/Reap.lean and so on `A3.claim`, `A3.claim_made` and the witnesses that use
them. -/

namespace A3
open A2

/-- **The A3 claim, in full** (`ClaimFull`): a program A2 types, whose
    spawned functions take only view-free `sink` parameters, run from a start
    holding its module globals (`GlobsOK`), is memory-safe, race-free and
    leak-free on every interleaving of its threads (`A3.claim`), and its race
    freedom is adequate for cells: every check-out of a cell's block is a
    step on the cell (`CellAdequate`, `A3.reach_frame_cellOp`), so every two
    threads changing one cell's state are a `Race`. -/
theorem claim_full : ClaimFull := by
  intro P spawn G s Δ nv hP hPc hSp hG ht hs hsc hv
  obtain ⟨h1, h2, h3⟩ := claim P spawn G s Δ nv hP hPc hSp hG ht hs hsc hv
  exact ⟨h1, h2, h3, fun C hr i t K k u x b hi hK hc =>
    reach_frame_cellOp hP hPc hSp hG ht hs hsc hv hr hi hK hc⟩

/-- **Every `make`'s run is safe, in full**: `made_safe`, and race freedom
    adequate for cells on it (`CellAdequate`). -/
theorem made_safe_full {P : Prog} {spawn : Nat → Bool} (hP : ProgOK P) (hPc : ProgCodes P)
    (hSp : SpawnOK P spawn) {D : List Decl} (hD : DeclsOK P D) {i : Nat} {G : Globs}
    (h : Made P spawn D i G) {d : Decl} (hd : D[i]? = some d) :
    MemorySafe P spawn (Cfg.start G (makeStmt i d) 1) ∧ RaceFree P spawn (Cfg.start G (makeStmt i d) 1) ∧
      CellAdequate P spawn (Cfg.start G (makeStmt i d) 1) := by
  obtain ⟨Δ, ht⟩ := makeStmt_typed hP hD hd
  have hc := claim_full P spawn G (makeStmt i d) Δ 1 hP hPc hSp (made_ok hP hPc hSp hD h).1 ht rfl trivial
    (makeStmt_vars i d)
  exact ⟨hc.1, hc.2.1, hc.2.2.2⟩

/-- **A3.6, the claim from the program's declarations, in full**
    (`A3.claim_made`, with `CellAdequate`): a program A2 types, whose globals
    are declared with `make`s of no parameter and synchronising types
    (`DeclsOK`) and read at their declared types (`ProgGlobs`):
    - every `make`'s run before `main` is memory-safe and race-free, its race
      freedom adequate for cells;
    - once every global is made (`Made`), the program run from that start is
      memory-safe, race-free and leaves only what the globals reach, its race
      freedom adequate for cells (`A3.claim_full`, with `GlobsOK` derived),
      and no thread's read of a global ever panics (`EvalR.globP` is never
      taken). -/
theorem claim_made_full (P : Prog) (spawn : Nat → Bool) (D : List Decl) (s : Stmt) (Δ : Ctx) (nv : Nat)
    (hP : ProgOK P) (hPc : ProgCodes P) (hSp : SpawnOK P spawn) (hD : DeclsOK P D)
    (hPG : ProgGlobs P (declTy D))
    (ht : StmtT P (fun _ => none) [] s Δ) (hs : s.src = true) (hsc : s.codesOK P) (hsg : s.globsAt (declTy D))
    (hv : ∀ v ∈ s.vars, v < nv) :
    (∀ i G d, Made P spawn D i G → D[i]? = some d →
      MemorySafe P spawn (Cfg.start G (makeStmt i d) 1) ∧ RaceFree P spawn (Cfg.start G (makeStmt i d) 1) ∧
        CellAdequate P spawn (Cfg.start G (makeStmt i d) 1)) ∧
    ∀ G, Made P spawn D D.length G →
      MemorySafe P spawn (Cfg.start G s nv) ∧ RaceFree P spawn (Cfg.start G s nv) ∧
      NoLeak P spawn (Cfg.start G s nv) ∧ CellAdequate P spawn (Cfg.start G s nv) ∧
      ∀ C, Reach P spawn (Cfg.start G s nv) C →
        ∀ th ∈ C.ths, ∀ g t, NextRhs th.s (.glob g t) → ¬ EvalR (C.view th) (.glob g t) .panic := by
  refine ⟨fun i G d h hd => made_safe_full hP hPc hSp hD h hd, fun G h => ?_⟩
  obtain ⟨hG, hGa⟩ := made_globsAt hP hPc hSp hD h
  obtain ⟨h1, h2, h3, h4⟩ := claim_full P spawn G s Δ nv hP hPc hSp hG ht hs hsc hv
  exact ⟨h1, h2, h3, h4, fun C hr => Reach.glob_typed hPG hsg hGa hr⟩

end A3
