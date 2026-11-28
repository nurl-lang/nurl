import C.A2Prog
import A3.ClaimFull

/-!
# C12: A3's claim for a checked program (AGORA-970)

A3's claim types programs with A2's rules (`StmtT`, `ProgOK`, `ProgCodes`)
and adds conditions on the program as a whole: the spawned functions'
signatures (`SpawnOK`), the globals' declarations (`DeclsOK`) and their
reads (`ProgGlobs`, `Stmt.globsAt`). Each is decided here, with the spawned
functions given as a list. `checked_claim_made_full` gives A3's claim in
full for a program the checker accepts: every global's `make` and the
program run after them are memory-safe, race-free and leak-free on every
interleaving of their threads, and no read of a global panics.
-/

namespace C

open A2 A3

/-- `SpawnOK`, decided for the spawned functions `sp`: each returns an
    integer and takes only view-free, destructor-free `sink` parameters. -/
def spawnOKB (P : Prog) (sp : List Nat) : Bool :=
  sp.all fun f => match P[f]? with
    | some fn => decide (fn.resTy = .int) &&
        fn.params.all (fun pt => decide (pt.1 = .sink) && !pt.2.holdsView && !pt.2.holdsDtor)
    | none => false

theorem spawnOKB_sound {P : Prog} {sp : List Nat} (h : spawnOKB P sp = true) :
    SpawnOK P (fun f => decide (f ∈ sp)) := by
  intro f hf
  simp only [decide_eq_true_eq] at hf
  have := List.all_eq_true.mp h f hf
  revert this
  cases hP : P[f]? with
  | none => intro h; cases h
  | some fn =>
    intro h
    simp only [Bool.and_eq_true, decide_eq_true_eq, List.all_eq_true, Bool.not_eq_true'] at h
    exact ⟨fn, rfl, h.1, fun pt hpt => ⟨(h.2 pt hpt).1.1, (h.2 pt hpt).1.2, (h.2 pt hpt).2⟩⟩

/-- `DeclsOK`, decided: each global's type synchronises itself, and its
    `make` takes no parameter and hands back an owned value of that type. -/
def declsOKB (P : Prog) (D : List Decl) : Bool :=
  D.all fun d => d.ty.sync && match P[d.make]? with
    | some fn => decide (fn.params = []) && decide (fn.resTy = d.ty) && fn.resOwn
    | none => false

theorem declsOKB_sound {P : Prog} {D : List Decl} (h : declsOKB P D = true) : DeclsOK P D := by
  intro g d hd
  have := List.all_eq_true.mp h d (List.mem_of_getElem? hd)
  simp only [Bool.and_eq_true] at this
  obtain ⟨hs, hm⟩ := this
  refine ⟨hs, ?_⟩
  revert hm
  cases hP : P[d.make]? with
  | none => intro h; cases h
  | some fn =>
    intro h
    simp only [Bool.and_eq_true, decide_eq_true_eq] at h
    exact ⟨fn, rfl, h.1.1, h.1.2, h.2⟩

/-- `Rhs.globAt`, decided: a read of a global is at its declared type. -/
def rhsGlobB (GT : GTy) : Rhs → Bool
  | .glob g t => decide (GT g = some t)
  | _ => true

theorem rhsGlobB_sound {GT : GTy} {r : Rhs} (h : rhsGlobB GT r = true) : r.globAt GT := by
  cases r <;> simp only [rhsGlobB, decide_eq_true_eq] at h <;> simp only [Rhs.globAt] <;>
    first | trivial | exact h

/-- `Stmt.globsAt`, decided. -/
def stmtGlobsB (GT : GTy) : Stmt → Bool
  | .seq a b => stmtGlobsB GT a && stmtGlobsB GT b
  | .letv _ r s => rhsGlobB GT r && stmtGlobsB GT s
  | .letcall _ _ _ s => stmtGlobsB GT s
  | .assign _ r => rhsGlobB GT r
  | .ite _ a b => stmtGlobsB GT a && stmtGlobsB GT b
  | .while _ s => stmtGlobsB GT s
  | .scope _ s => stmtGlobsB GT s
  | .rbind _ s => stmtGlobsB GT s
  | .frozen _ s => stmtGlobsB GT s
  | .letrec _ _ s => stmtGlobsB GT s
  | .catchR _ _ s => stmtGlobsB GT s
  | .unpair _ _ _ s => stmtGlobsB GT s
  | .callc _ _ _ _ _ s => stmtGlobsB GT s
  | .letd _ _ r s => rhsGlobB GT r && stmtGlobsB GT s
  | .scopeD _ _ s => stmtGlobsB GT s
  | .withLock _ _ s => stmtGlobsB GT s
  | .scopeL _ _ _ s => stmtGlobsB GT s
  | .withElem _ _ _ s => stmtGlobsB GT s
  | .callcE _ _ _ _ s => stmtGlobsB GT s
  | .block s => stmtGlobsB GT s
  | .loop s => stmtGlobsB GT s
  | .takeB _ _ _ s => stmtGlobsB GT s
  | .skip | .push _ _ | .free _ | .panic | .edit _ _ _ | .insert _ _ _ | .exit _ => true

theorem stmtGlobsB_sound {GT : GTy} : ∀ {s : Stmt}, stmtGlobsB GT s = true → s.globsAt GT := by
  intro s
  induction s <;> intro h <;> simp only [stmtGlobsB, Bool.and_eq_true] at h <;> simp only [Stmt.globsAt] <;>
    first
    | trivial
    | exact ⟨‹_ → _› h.1, ‹_ → _› h.2⟩
    | exact ⟨rhsGlobB_sound h.1, ‹_ → _› h.2⟩
    | exact rhsGlobB_sound h
    | exact ‹_ → _› h
    | skip

/-- `ProgGlobs`, decided. -/
def progGlobsB (P : Prog) (GT : GTy) : Bool := P.all fun fn => stmtGlobsB GT fn.body

theorem progGlobsB_sound {P : Prog} {GT : GTy} (h : progGlobsB P GT = true) : ProgGlobs P GT :=
  fun fn hfn => stmtGlobsB_sound (List.all_eq_true.mp h fn hfn)

/-- **Phase C for A3, end to end**: for a program the checker accepts
    (`progOK2B`), whose spawned functions `sp` and globals' declarations `D`
    it accepts, with an entry statement it accepts: every global's `make`
    runs memory-safe and race-free, and once every global is made the
    program runs memory-safe, race-free and leak-free on every interleaving
    of its threads, its race freedom adequate for cells, and no read of a
    global ever panics (`A3.claim_made_full`). -/
theorem checked_claim_made_full {P : Prog} {sp : List Nat} {D : List Decl} {s : Stmt} {Δ : Ctx} {nv : Nat}
    (hP : progOK2B P = true) (hSp : spawnOKB P sp = true) (hD : declsOKB P D = true)
    (hPG : progGlobsB P (declTy D) = true)
    (hc : checkA2 P s.vars (fun _ => none) [] s = some Δ) (hsc : stmtCodesB P s = true)
    (hsg : stmtGlobsB (declTy D) s = true) (hs : s.src = true) (hv : ∀ v ∈ s.vars, v < nv) :
    let spawn := fun f => decide (f ∈ sp)
    (∀ i G d, Made P spawn D i G → D[i]? = some d →
      MemorySafe P spawn (Cfg.start G (makeStmt i d) 1) ∧ RaceFree P spawn (Cfg.start G (makeStmt i d) 1) ∧
        CellAdequate P spawn (Cfg.start G (makeStmt i d) 1)) ∧
    ∀ G, Made P spawn D D.length G →
      MemorySafe P spawn (Cfg.start G s nv) ∧ RaceFree P spawn (Cfg.start G s nv) ∧
      NoLeak P spawn (Cfg.start G s nv) ∧ CellAdequate P spawn (Cfg.start G s nv) ∧
      ∀ C, Reach P spawn (Cfg.start G s nv) C →
        ∀ th ∈ C.ths, ∀ g t, NextRhs th.s (.glob g t) → ¬ EvalR (C.view th) (.glob g t) .panic := by
  obtain ⟨hok, hcodes⟩ := progOK2B_sound hP
  obtain ⟨ht, _⟩ := checkA2_sound (ξ := .none) (fun _ _ => rfl) (fun v hv => hv) hc
  exact claim_made_full P _ D s Δ nv hok hcodes (spawnOKB_sound hSp) (declsOKB_sound hD)
    (progGlobsB_sound hPG) ht hs (stmtCodesB_sound hsc) (stmtGlobsB_sound hsg) hv

end C
