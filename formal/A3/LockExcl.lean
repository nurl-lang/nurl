import A3.Reap

/-! A3.2 — Agora #808: **a checked-out lock block and its frame**, over the
configuration's run.

A `withLock` checks its block's payload out (`Step.withLock`: the block is
left `⟨t, .lock, none⟩`) and puts a run-time frame `scopeL k t x s` on its
thread's statement; the frame's end gives the payload back (`Release.put`).
Nothing in a frame records the block's state.  This file ties the two
together on every configuration a run reaches (`LockInv`, preserved by every
`TStep`: a thread's step, its marking sweep and its reaps, a spawn, a failed
spawn):

* every frame's block is a lock block of the frame's type, or gone (the
  sweep removed it), at a key below `nid` (so no new block takes the key);
* a frame whose payload type is not `dtorFree` (it holds a destructor
  value, `Ty.holdsDtor`) has its block checked out (`⟨t, .lock, none⟩`) or
  gone: nothing but the frame's own end fills it (`locked_restore` of such a
  payload is not typed, `RhsT.lockRestore`; every other operation on the
  block waits on `none`), and the marking sweep marks no lock block whose
  payload is out;
* **mutual exclusion** (A3.2): at most one frame of such a block, on one
  thread, once (`reach_lock_excl`).

That a frame's block is never removed while the frame is out (the
check-out's root share outlives the body) is `A3/LockRoot.lean`'s
(`reach_frame_live`), which then discharges the block's state in the
give-back lemmas of `A3.LockDtorWitness` (`reach_scopeL_end_gives_back`,
`reach_scopeL_panic`). -/

namespace A3
open A2

/-! ### The frames a statement is inside of -/

/-- The lock scopes a statement is inside of, with their payload types (its
    spine's `scopeL` frames, outermost first): `Stmt.lkeys` with the types. -/
def _root_.A2.Stmt.lfr : Stmt → List (Nat × Ty)
  | .seq a _ => a.lfr
  | .scope _ s => s.lfr
  | .scopeD _ _ s => s.lfr
  | .rbind _ s => s.lfr
  | .frozen _ s => s.lfr
  | .catchR _ _ s => s.lfr
  | .scopeL k t _ s => (k, t) :: s.lfr
  | _ => []

theorem lfr_fst (s : Stmt) : s.lfr.map Prod.fst = s.lkeys := by
  induction s <;> simp_all [Stmt.lfr, Stmt.lkeys]

/-- Source code is inside no frame. -/
theorem lfr_src {s : Stmt} (h : s.src = true) : s.lfr = [] := by
  induction s with
  | seq a b iha _ => simp only [Stmt.src, Bool.and_eq_true] at h; simp [Stmt.lfr, iha h.1]
  | _ => simp_all [Stmt.src, Stmt.lfr]

theorem lfr_rename (ρ : Var → Var) (s : Stmt) : (s.rename ρ).lfr = s.lfr := by
  induction s <;> simp_all [Stmt.rename, Stmt.lfr]

theorem lfr_wrap (s : Stmt) : ∀ (ps : List (PMode × Ty)) (base i : Nat),
    (wrapParams ps base i s).lfr = s.lfr := by
  intro ps
  induction ps with
  | nil => intro _ _; rfl
  | cons p ps ih =>
    intro base i
    obtain ⟨pm, t⟩ := p
    cases pm <;> simp [wrapParams, Stmt.lfr, ih]

theorem body_src {P : Prog} (hP : ProgOK P) {f : Nat} {fn : Fn} (hf : P[f]? = some fn) :
    fn.body.src = true :=
  (hP fn (List.mem_of_getElem? hf)).1

/-- A call's inside is inside no lock scope. -/
theorem lfr_callIn {fn : Fn} (h : fn.body.src = true) (args : List Var) (base : Nat) (x : Var) :
    (callIn fn args base x).lfr = [] := by
  unfold callIn resFrame
  split <;> simp [Stmt.lfr, lfr_wrap, lfr_rename, lfr_src h]

theorem Redex.lfr_mem {s r : Stmt} {K : Stmt → Stmt} (h : Redex s K r) {k : Nat} {t : Ty} {x : Var}
    {b : Stmt} (hr : r = .scopeL k t x b) : (k, t) ∈ s.lfr := by
  induction h with
  | here => subst hr; simp [Stmt.lfr]
  | seq _ ih => exact ih hr
  | scope _ ih => exact ih hr
  | rbind _ ih => exact ih hr
  | frozen _ ih => exact ih hr
  | catchR _ ih => exact ih hr
  | scopeD _ ih => exact ih hr
  | scopeL _ ih => exact List.mem_cons_of_mem _ (ih hr)

/-- The frames read a statement's frames only through the hole's. -/
theorem Redex.lfr_eq {s r : Stmt} {K : Stmt → Stmt} (h : Redex s K r) {y y' : Stmt}
    (hy : y.lfr = y'.lfr) : (K y).lfr = (K y').lfr := by
  induction h with
  | here => exact hy
  | seq _ ih => exact ih
  | scope _ ih => exact ih
  | rbind _ ih => exact ih
  | frozen _ ih => exact ih
  | catchR _ ih => exact ih
  | scopeD _ ih => exact ih
  | scopeL _ ih => simp only [Stmt.lfr, ih]

/-! ### What the typing says of the code a step brings in -/

section inv
variable {P : Prog} {Γ Δ : Ctx} {F : List Var}

theorem _root_.A2.StmtT.seq_src {a b : Stmt} (ht : StmtT P Γ F (.seq a b) Δ) : b.src = true := by
  generalize hs : Stmt.seq a b = s0 at ht
  induction ht with
  | seq hb _ _ _ _ => cases hs; exact hb
  | sub _ _ _ ih => exact ih hs
  | _ => cases hs

theorem _root_.A2.StmtT.letv_src {x : Var} {r : Rhs} {s : Stmt} (ht : StmtT P Γ F (.letv x r s) Δ) : s.src = true := by
  generalize hs : Stmt.letv x r s = s0 at ht
  induction ht with
  | letv h1 => cases hs; exact h1
  | sub _ _ _ ih => exact ih hs
  | _ => cases hs

theorem _root_.A2.StmtT.ite_src {c : Expr} {a b : Stmt} (ht : StmtT P Γ F (.ite c a b) Δ) :
    a.src = true ∧ b.src = true := by
  generalize hs : Stmt.ite c a b = s0 at ht
  induction ht with
  | ite ha hb => cases hs; exact ⟨ha, hb⟩
  | sub _ _ _ ih => exact ih hs
  | _ => cases hs

theorem _root_.A2.StmtT.withElem_src {v x : Var} {i : Expr} {s : Stmt} (ht : StmtT P Γ F (.withElem v i x s) Δ) :
    s.src = true := by
  generalize hs : Stmt.withElem v i x s = s0 at ht
  induction ht with
  | withElem h1 => cases hs; exact h1
  | sub _ _ _ ih => exact ih hs
  | _ => cases hs

theorem _root_.A2.StmtT.unpair_src {y x z : Var} {s : Stmt} (ht : StmtT P Γ F (.unpair y x z s) Δ) : s.src = true := by
  generalize hs : Stmt.unpair y x z s = s0 at ht
  induction ht with
  | unpair h1 => cases hs; exact h1
  | sub _ _ _ ih => exact ih hs
  | _ => cases hs

theorem _root_.A2.StmtT.letd_src {x : Var} {f : Nat} {r : Rhs} {s : Stmt} (ht : StmtT P Γ F (.letd x f r s) Δ) :
    s.src = true := by
  generalize hs : Stmt.letd x f r s = s0 at ht
  induction ht with
  | letd h1 => cases hs; exact h1
  | sub _ _ _ ih => exact ih hs
  | _ => cases hs

theorem _root_.A2.StmtT.withLock_src {a x : Var} {s : Stmt} (ht : StmtT P Γ F (.withLock a x s) Δ) : s.src = true := by
  generalize hs : Stmt.withLock a x s = s0 at ht
  induction ht with
  | withLock h1 => cases hs; exact h1
  | sub _ _ _ ih => exact ih hs
  | _ => cases hs

end inv

/-- A statement is typed (in some context). -/
def Typed (P : Prog) (s : Stmt) : Prop := ∃ Γ F Δ, StmtT P Γ F s Δ

section down
variable {P : Prog}

theorem Typed.seq {a b : Stmt} (h : Typed P (.seq a b)) : Typed P a := by
  obtain ⟨Γ, F, Δ, ht⟩ := h
  generalize hs : Stmt.seq a b = s0 at ht
  induction ht with
  | seq _ ha _ _ _ => cases hs; exact ⟨_, _, _, ha⟩
  | sub _ _ _ ih => exact ih hs
  | _ => cases hs

theorem Typed.scope {x : Var} {s : Stmt} (h : Typed P (.scope x s)) : Typed P s := by
  obtain ⟨Γ, F, Δ, ht⟩ := h
  generalize hs : Stmt.scope x s = s0 at ht
  induction ht with
  | scope _ _ hb _ _ => cases hs; exact ⟨_, _, _, hb⟩
  | sub _ _ _ ih => exact ih hs
  | _ => cases hs

theorem Typed.rbind {p : Var} {s : Stmt} (h : Typed P (.rbind p s)) : Typed P s := by
  obtain ⟨Γ, F, Δ, ht⟩ := h
  generalize hs : Stmt.rbind p s = s0 at ht
  induction ht with
  | rbind _ _ _ _ _ hb _ _ => cases hs; exact ⟨_, _, _, hb⟩
  | sub _ _ _ ih => exact ih hs
  | _ => cases hs

theorem Typed.frozen {z : List Var} {s : Stmt} (h : Typed P (.frozen z s)) : Typed P s := by
  obtain ⟨Γ, F, Δ, ht⟩ := h
  generalize hs : Stmt.frozen z s = s0 at ht
  induction ht with
  | frozen hb _ _ => cases hs; exact ⟨_, _, _, hb⟩
  | sub _ _ _ ih => exact ih hs
  | _ => cases hs

theorem Typed.catchR {x : Var} {m0 : Mem} {s : Stmt} (h : Typed P (.catchR x m0 s)) : Typed P s := by
  obtain ⟨Γ, F, Δ, ht⟩ := h
  generalize hs : Stmt.catchR x m0 s = s0 at ht
  induction ht with
  | catchR _ hb _ _ _ _ => cases hs; exact ⟨_, _, _, hb⟩
  | sub _ _ _ ih => exact ih hs
  | _ => cases hs

theorem Typed.scopeD {x : Var} {f : Nat} {s : Stmt} (h : Typed P (.scopeD x f s)) : Typed P s := by
  obtain ⟨Γ, F, Δ, ht⟩ := h
  generalize hs : Stmt.scopeD x f s = s0 at ht
  induction ht with
  | scopeD _ _ hb _ _ _ _ _ _ => cases hs; exact ⟨_, _, _, hb⟩
  | sub _ _ _ ih => exact ih hs
  | _ => cases hs

theorem Typed.scopeL {k : Nat} {t : Ty} {x : Var} {s : Stmt} (h : Typed P (.scopeL k t x s)) :
    Typed P s := by
  obtain ⟨Γ, F, Δ, ht⟩ := h
  generalize hs : Stmt.scopeL k t x s = s0 at ht
  induction ht with
  | scopeL _ _ hb _ _ => cases hs; exact ⟨_, _, _, hb⟩
  | sub _ _ _ ih => exact ih hs
  | _ => cases hs

end down

/-! ### What a step does to the frames -/

/-- From frames `L` to `L'`: some of the inner ones left, or a check-out's
    added, its block's payload in before (`some v`) and checked out after
    (`CheckedOut`: out, not taken). -/
def FrStep (m m' : Mem) (L L' : List (Nat × Ty)) : Prop :=
  L' <+: L ∨ ∃ k u v, L' = L ++ [(k, u)] ∧ m.blk k = some ⟨u, .lock, some v⟩ ∧ CheckedOut m' k u

theorem FrStep.cons {m m' : Mem} {L L' : List (Nat × Ty)} (h : FrStep m m' L L') (p : Nat × Ty) :
    FrStep m m' (p :: L) (p :: L') := by
  rcases h with ⟨t, ht⟩ | ⟨k, u, v, rfl, h1, h2⟩
  · exact .inl ⟨t, by simp [← ht]⟩
  · exact .inr ⟨k, u, v, by simp, h1, h2⟩

theorem FrStep.nil {m m' : Mem} {L L' : List (Nat × Ty)} (h : L' = []) : FrStep m m' L L' :=
  .inl (h ▸ List.nil_prefix)

/-- **A step's frames**: a step leaves the frames of its statement, or the
    inner ones of them, and the only one it adds is a check-out's, at the
    end (the innermost), of a block whose payload it takes out.  (The code a
    step brings in, a binding's body, a call's, the rest of a sequence, is
    source, which is inside no frame: the typing says so of the statement's,
    `ProgOK` of a function's.) -/
theorem Step.lfr {P : Prog} (hP : ProgOK P) {m m' : Mem} {s s' : Stmt} (h : Step P m s (.ok m' s'))
    (ht : Typed P s) : FrStep m m' s.lfr s'.lfr := by
  revert ht
  generalize hr : Res.ok m' s' = r at h
  induction h generalizing m' s' with
  | seqL _ ih => cases hr; intro ht; have h1 := ih rfl ht.seq; exact h1
  | scopeIn _ ih => cases hr; intro ht; have h1 := ih rfl ht.scope; exact h1
  | rbindIn _ ih => cases hr; intro ht; have h1 := ih rfl ht.rbind; exact h1
  | frozenIn _ ih => cases hr; intro ht; have h1 := ih rfl ht.frozen; exact h1
  | catchIn _ ih => cases hr; intro ht; have h1 := ih rfl ht.catchR; exact h1
  | scopeDIn _ ih => cases hr; intro ht; have h1 := ih rfl ht.scopeD; exact h1
  | scopeLIn _ ih => cases hr; intro ht; have h1 := ih rfl ht.scopeL; exact h1.cons _
  | seqSkip =>
    cases hr; rintro ⟨_, _, _, ht⟩; exact FrStep.nil (lfr_src ht.seq_src)
  | letv _ _ =>
    cases hr; rintro ⟨_, _, _, ht⟩; exact FrStep.nil (by simp [Stmt.lfr, lfr_src ht.letv_src])
  | iteT _ _ =>
    cases hr; rintro ⟨_, _, _, ht⟩; exact FrStep.nil (lfr_src ht.ite_src.1)
  | iteF _ =>
    cases hr; rintro ⟨_, _, _, ht⟩; exact FrStep.nil (lfr_src ht.ite_src.2)
  | withElem _ _ _ _ _ _ =>
    cases hr; rintro ⟨_, _, _, ht⟩; exact FrStep.nil (by simp [Stmt.lfr, lfr_src ht.withElem_src])
  | unpair _ _ _ _ =>
    cases hr; rintro ⟨_, _, _, ht⟩; exact FrStep.nil (by simp [Stmt.lfr, lfr_src ht.unpair_src])
  | letd _ _ =>
    cases hr; rintro ⟨_, _, _, ht⟩; exact FrStep.nil (by simp [Stmt.lfr, lfr_src ht.letd_src])
  | letcall hf _ _ =>
    cases hr; intro _; exact FrStep.nil (by simp [Stmt.lfr, callStmt, lfr_callIn (body_src hP hf)])
  | letrec hf _ _ =>
    cases hr; intro _; exact FrStep.nil (by simp [Stmt.lfr, recStmt, lfr_callIn (body_src hP hf)])
  | callc _ _ hf _ _ =>
    cases hr; intro _; exact FrStep.nil (by simp [Stmt.lfr, lfr_callIn (body_src hP hf)])
  | @withLock a x s0 k t v _ hk _ _ =>
    cases hr; rintro ⟨_, _, _, ht⟩
    refine .inr ⟨k, t, v, by simp [Stmt.lfr, lfr_src ht.withLock_src], hk, ?_⟩
    simp [CheckedOut, Mem.set, upd]
  | scopeLFail _ _ => cases hr; intro _; exact .inl List.prefix_rfl
  | _ => first
    | (cases hr; done)
    | (cases hr; intro _; exact FrStep.nil (by simp [Stmt.lfr, handStmt, handStmtD]))

/-! ### What a step does to a block whose payload is out -/

/-- Block `k` of `m` is out for a frame: its payload checked out (out, and
    not taken, `CheckedOut`), or the block gone, at a key below `nid` (which
    no new block takes). -/
def Out (m : Mem) (k : Nat) : Prop :=
  (m.blk k = none ∧ k < m.nid) ∨ ∃ u, CheckedOut m k u

theorem TakeVal.blk_eq {m m1 : Mem} {y : Var} {v : Val} (h : TakeVal m y v m1) : m1.blk = m.blk := by
  cases h <;> rfl

theorem BindParams.blk_eq {m m' : Mem} {ps : List (PMode × Ty)} {as : List Var} {base i : Nat}
    (h : BindParams m ps as base i m') : m'.blk = m.blk := by
  induction h with
  | nil => rfl
  | inp _ _ _ ih => exact ih
  | sink _ _ ih => exact ih
  | inout _ ih => exact ih

theorem BindParams.taken_eq {m m' : Mem} {ps : List (PMode × Ty)} {as : List Var} {base i : Nat}
    (h : BindParams m ps as base i m') : m'.taken = m.taken := by
  induction h with
  | nil => rfl
  | inp _ _ _ ih => exact ih
  | sink _ _ ih => exact ih
  | inout _ ih => exact ih

theorem Release.taken_eq {m m' : Mem} {k0 : Nat} {t : Ty} {x : Var} (h : Release m k0 t x m') :
    m'.taken = m.taken := by
  cases h <;> rfl

theorem Out.ne_some {m : Mem} {k : Nat} (h : Out m k) {k0 : Nat} {t : Ty} {p : Val}
    (h0 : m.blk k0 = some ⟨t, .lock, some p⟩) : k ≠ k0 := by
  rintro rfl
  rcases h with ⟨hn, _⟩ | ⟨u, hu, _⟩
  · rw [hn] at h0; cases h0
  · rw [hu] at h0; cases h0

theorem Out.ne_fresh {m : Mem} {k : Nat} (h : Out m k) (h0 : m.blk m.nid = none) : k ≠ m.nid := by
  rintro rfl
  rcases h with ⟨_, hl⟩ | ⟨u, hu, _⟩
  · exact Nat.lt_irrefl _ hl
  · rw [hu] at h0; cases h0

/-- **A right-hand side leaves a block whose payload is out as it was**:
    every operation that writes a lock block asks its payload in, but
    `locked_restore`, which (Agora #810) asks it taken, not checked out; a
    new block's key is fresh. -/
theorem EvalR.stay {m m1 : Mem} {r : Rhs} {v : Val} {o : Bool} (h : EvalR m r (.ok v o m1))
    {k : Nat} (hk : Out m k) : m1.blk k = m.blk k := by
  cases h with
  | arcNew h1 hfr | lockNew h1 hfr _ | cellNew h1 hfr _ | chanSendClosed _ h1 _ _ hfr _ =>
    rw [TakeVal.blk_eq h1, TakeVal.nid_eq h1] at hfr ⊢
    exact upd_ne _ _ (hk.ne_fresh hfr)
  | rwRead _ _ hfr | rwTryRead _ _ hfr => exact upd_ne _ _ (hk.ne_fresh hfr)
  | atomic _ h0 _ _ _ | chanRecv _ h0 _ _ _ _ | chanClose _ h0 _ | lockTake _ h0 _ =>
    exact upd_ne _ _ (hk.ne_some h0)
  | chanSend _ h1 h0 _ _ _ _ =>
    rw [TakeVal.blk_eq h1] at h0 ⊢
    exact upd_ne _ _ (hk.ne_some h0)
  | @lockRestore a y o0 k0 t w m2 ha h1 h0 htk _ =>
    rw [TakeVal.blk_eq h1] at h0 ⊢
    by_cases he : k = k0
    · subst he
      rw [TakeVal.taken h1] at htk
      rcases hk with ⟨hn, _⟩ | ⟨u, _, hu'⟩
      · rw [hn] at h0; cases h0
      · rw [hu'] at htk; cases htk
    · exact upd_ne _ _ he
  | pair h1 h2 => rw [TakeVal.blk_eq h2, TakeVal.blk_eq h1]
  | inl h1 | inr h1 | pack h1 => rw [TakeVal.blk_eq h1]
  | _ => rfl

/-- Agora #810: **a right-hand side leaves a block whose payload is out
    checked out**: only a take marks a block taken, one whose payload is in. -/
theorem EvalR.taken_stay {m m1 : Mem} {r : Rhs} {v : Val} {o : Bool} (h : EvalR m r (.ok v o m1))
    {k : Nat} (hk : Out m k) : m1.taken k = m.taken k := by
  cases h with
  | arcNew h1 _ | lockNew h1 _ _ | cellNew h1 _ _ | chanSendClosed _ h1 _ _ _ _ =>
    exact congrFun (TakeVal.taken h1) k
  | chanSend _ h1 _ _ _ _ _ => exact congrFun (TakeVal.taken h1) k
  | lockRestore _ h1 _ _ _ => exact congrFun (TakeVal.taken h1) k
  | lockTake _ h0 _ => exact upd_ne _ _ (hk.ne_some h0)
  | pair h1 h2 => rw [TakeVal.taken h2, TakeVal.taken h1]
  | inl h1 | inr h1 | pack h1 => rw [TakeVal.taken h1]
  | _ => rfl

/-- A lock scope's end changes no block but its own. -/
theorem Release.stay {m m' : Mem} {k0 : Nat} {t : Ty} {x : Var} (h : Release m k0 t x m') (k : Nat) :
    m'.blk k = m.blk k ∨ (k = k0 ∧ m.blk k = some ⟨t, .lock, none⟩) := by
  cases h with
  | put _ _ hk _ =>
    by_cases he : k = k0
    · subst he; exact .inr ⟨rfl, hk.1⟩
    · exact .inl (upd_ne _ _ he)
  | drop => exact .inl rfl

theorem count_le_of_cons {k k0 : Nat} {L : List Nat} (h : (k0 :: L).count k ≤ 1) (hk : k ∈ L) :
    k ≠ k0 ∧ L.count k ≤ 1 := by
  have hc := List.count_pos_iff.mpr hk
  rw [List.count_cons] at h
  constructor
  · rintro rfl; simp at h; omega
  · split at h <;> omega

/-- **A step leaves a block whose payload is out as it was**, unless the
    block is one of its own lock scopes' (whose end gives a payload back):
    then, its scope there once, the step left that scope. -/
theorem Step.stay {P : Prog} {m : Mem} {s : Stmt} {r : Res} (h : Step P m s r) {k : Nat}
    (hk : Out m k) :
    r.mem.blk k = m.blk k ∨
      (k ∈ s.lkeys ∧ (∃ u, m.blk k = some ⟨u, .lock, none⟩) ∧
        ∀ m' s', r = .ok m' s' → s.lkeys.count k ≤ 1 → k ∉ s'.lkeys) := by
  revert hk
  induction h with
  | seqL _ ih | scopeIn _ ih | rbindIn _ ih | frozenIn _ ih | catchIn _ ih | scopeDIn _ ih =>
    intro hk
    rcases ih hk with h1 | ⟨h1, hs, h2⟩
    · exact .inl h1
    · exact .inr ⟨h1, hs, fun m' s' he hc => by cases he; have h3 := h2 _ _ rfl hc; exact h3⟩
  | seqP _ ih | frozenP _ ih =>
    intro hk
    rcases ih hk with h1 | ⟨h1, hs, _⟩
    · exact .inl h1
    · exact .inr ⟨h1, hs, fun _ _ he => by cases he⟩
  | scopeP _ _ _ ih | rbindP _ _ ih | scopeDPMoved _ _ ih =>
    intro hk
    rcases ih hk with h1 | ⟨h1, hs, _⟩
    · exact .inl h1
    · exact .inr ⟨h1, hs, fun _ _ he => by cases he⟩
  | catchP _ _ ih | scopeDP _ _ _ ih | scopeDPDrain _ _ ih =>
    intro hk
    rcases ih hk with h1 | ⟨h1, hs, _⟩
    · exact .inl h1
    · exact .inr ⟨h1, hs, fun _ _ he _ => by cases he; simp [Stmt.lkeys]⟩
  | @scopeLIn m' k0 t0 x b b' _ ih =>
    intro hk
    rcases ih hk with h1 | ⟨h1, hs, h2⟩
    · exact .inl h1
    · refine .inr ⟨List.mem_cons_of_mem _ h1, hs, fun m'' s'' he hc => ?_⟩
      cases he
      obtain ⟨hne, hc'⟩ := count_le_of_cons hc h1
      have := h2 _ _ rfl hc'
      simp only [Stmt.lkeys, List.mem_cons, not_or]
      exact ⟨hne, this⟩
  | @scopeLP m1 m2 k0 t0 x b _ hrl ih =>
    intro hk
    rcases ih hk with h1 | ⟨h1, hs, _⟩
    · rcases Release.stay hrl k with h0 | ⟨rfl, hs⟩
      · exact .inl (h0.trans h1)
      · exact .inr ⟨List.mem_cons_self, ⟨t0, h1 ▸ hs⟩, fun _ _ he => by cases he⟩
    · rcases Release.stay hrl k with h0 | ⟨rfl, _⟩
      · exact .inr ⟨List.mem_cons_of_mem _ h1, hs, fun _ _ he => by cases he⟩
      · exact .inr ⟨List.mem_cons_self, hs, fun _ _ he => by cases he⟩
  | @scopeLSkip m' k0 t0 x hrl _ =>
    intro _
    rcases Release.stay hrl k with h0 | ⟨rfl, hs⟩
    · exact .inl h0
    · exact .inr ⟨List.mem_cons_self, ⟨t0, hs⟩, fun _ _ he _ => by cases he; simp [Stmt.lkeys]⟩
  | letv _ he | letd _ he =>
    intro hk; exact .inl (EvalR.stay he hk)
  | assign _ he _ _ =>
    intro hk; exact .inl (EvalR.stay he hk)
  | letcall _ _ hb =>
    intro _; exact .inl (congrFun (BindParams.blk_eq hb) k)
  | callc _ _ _ _ hb =>
    intro _; exact .inl (congrFun (BindParams.blk_eq hb) k)
  | push h1 _ _ _ | pushRealloc h1 _ _ _ | insert _ h1 _ _ _ | editPush h1 _ _ | editPushRealloc h1 _ _
  | editSet _ _ h1 _ _ _ | editSetOOB _ h1 _ _ _ =>
    intro _; exact .inl (congrFun (TakeVal.blk_eq h1) k)
  | withLock _ h0 _ _ =>
    intro hk; exact .inl (upd_ne _ _ (hk.ne_some h0))
  | reap _ h0 _ =>
    intro hk
    refine .inl (upd_ne _ _ ?_)
    rintro rfl
    rcases hk with ⟨hn, _⟩ | ⟨u, hu, _⟩
    · rw [hn] at h0; cases h0
    · rw [hu] at h0; cases h0
  | _ => intro _; exact .inl rfl

/-- Agora #810: **a step leaves a block whose payload is out checked out**:
    only a take and a check-out mark a block, and both one whose payload is
    in; a lock scope's end, a sweep and a reap mark none. -/
theorem Step.taken_stay {P : Prog} {m : Mem} {s : Stmt} {r : Res} (h : Step P m s r) {k : Nat}
    (hk : Out m k) : r.mem.taken k = m.taken k := by
  revert hk
  induction h with
  | seqL _ ih | seqP _ ih | scopeIn _ ih | rbindIn _ ih | frozenIn _ ih | frozenP _ ih | catchIn _ ih
    | scopeDIn _ ih | scopeLIn _ ih | scopeP _ _ _ ih | rbindP _ _ ih | scopeDPMoved _ _ ih | catchP _ _ ih
    | scopeDP _ _ _ ih | scopeDPDrain _ _ ih => exact fun hk => ih hk
  | scopeLP _ hrl ih => exact fun hk => (congrFun (Release.taken_eq hrl) k).trans (ih hk)
  | scopeLSkip hrl _ => exact fun _ => congrFun (Release.taken_eq hrl) k
  | letv _ he | letd _ he => exact fun hk => EvalR.taken_stay he hk
  | assign _ he _ _ => exact fun hk => EvalR.taken_stay he hk
  | letcall _ _ hb => exact fun _ => congrFun (BindParams.taken_eq hb) k
  | callc _ _ _ _ hb => exact fun _ => congrFun (BindParams.taken_eq hb) k
  | push h1 _ _ _ | pushRealloc h1 _ _ _ | insert _ h1 _ _ _ | editPush h1 _ _ | editPushRealloc h1 _ _
  | editSet _ _ h1 _ _ _ | editSetOOB _ h1 _ _ _ =>
    exact fun _ => congrFun (TakeVal.taken h1) k
  | withLock _ h0 _ _ => exact fun hk => upd_ne _ _ (hk.ne_some h0)
  | _ => exact fun _ => rfl

/-! ### The invariant -/

/-- The block of a frame of payload type `u`, in the blocks `B` (`T` the
    blocks taken) with `n` the next fresh key: below `n` (no new block takes
    the key), and gone, or a lock block of type `u` whose payload is checked
    out (Agora #810: out, and not taken, `CheckedOut`). -/
def LkOut (B : Nat → Option Blk) (T : Nat → Bool) (n k : Nat) (u : Ty) : Prop :=
  k < n ∧ (B k = none ∨ (B k = some ⟨u, .lock, none⟩ ∧ T k = false))

/-- **Agora #808: the check-outs' invariant.**  Over the threads' statements
    and the shared blocks:
    - `out`: every frame's block is as `LkOut` says;
    - `one`: a frame is the only frame of its block on any thread (A3.2's
      mutual exclusion) ...
    - `nd`: ... and the only one on its own thread.
    (Agora #810: for every payload type; until the model told a taken
    block from a checked-out one, `locked_restore` could refill a
    `dtorFree` payload's checked-out block, and these held only for a
    payload that holds a destructor value.) -/
structure LockInv (C : Cfg) : Prop where
  out : ∀ (i : Nat) (t : Thread), C.ths[i]? = some t → ∀ (k : Nat) (u : Ty), (k, u) ∈ t.s.lfr →
    LkOut C.blk C.taken C.nid k u
  one : ∀ (i j : Nat) (ti tj : Thread) (k : Nat) (u u' : Ty), C.ths[i]? = some ti → C.ths[j]? = some tj →
    (k, u) ∈ ti.s.lfr → (k, u') ∈ tj.s.lfr → i = j
  nd  : ∀ (i : Nat) (t : Thread), C.ths[i]? = some t → ∀ (k : Nat) (u : Ty), (k, u) ∈ t.s.lfr →
    (t.s.lfr.map Prod.fst).count k = 1

/-- The marking sweep keeps a frame's block as `LkOut` says: it removes it,
    or keeps it; it marks no lock block whose payload is out (an orphan to be
    holds its payload, `Cand`). -/
theorem LkOut.sweepD {R : Val → Prop} {B : Nat → Option Blk} {T : Nat → Bool} {n k : Nat} {u : Ty}
    (h : LkOut B T n k u) : LkOut (sweepBlkD R B) T n k u := by
  refine ⟨h.1, ?_⟩
  unfold sweepBlkD
  split
  · exact h.2
  · split
    · next hp =>
      rcases h.2 with hn | ⟨ho, _⟩
      · exact .inl (by rw [hn]; rfl)
      · exfalso
        rcases hp with ⟨⟨⟨n', f, w, p, kd, _, hc⟩, _⟩, _⟩ | ⟨n', f, w, p, hd⟩
        · rw [ho] at hc; cases hc
        · rw [ho] at hd; cases hd
    · exact .inl rfl

theorem LockInv.sweepD {C : Cfg} (h : LockInv C) : LockInv C.sweepD :=
  ⟨fun i t hi k u hm => (h.out i t hi k u hm).sweepD, h.one, h.nd⟩

/-- A frame's block after a step that keeps it, and its mark, as they were. -/
theorem LkOut.step_of {m m' : Mem} {k : Nat} {u : Ty} (h : LkOut m.blk m.taken m.nid k u) (hg : Grows m m')
    (hsame : m'.blk k = m.blk k) (htk : m'.taken k = m.taken k) : LkOut m'.blk m'.taken m'.nid k u := by
  refine ⟨Nat.lt_of_lt_of_le h.1 hg.nid, ?_⟩
  rw [hsame, htk]; exact h.2

/-- ... whose block is out. -/
theorem LkOut.out {m : Mem} {k : Nat} {u : Ty} (h : LkOut m.blk m.taken m.nid k u) : Out m k := by
  rcases h.2 with hn | ⟨ho, ht⟩
  · exact .inl ⟨hn, h.1⟩
  · exact .inr ⟨u, ho, ht⟩

theorem mem_lfr_keys {s : Stmt} {k : Nat} {u : Ty} (h : (k, u) ∈ s.lfr) : k ∈ s.lkeys := by
  rw [← lfr_fst]; exact List.mem_map.mpr ⟨_, h, rfl⟩

theorem keys_lfr {s : Stmt} {k : Nat} (h : k ∈ s.lkeys) : ∃ u, (k, u) ∈ s.lfr := by
  rw [← lfr_fst] at h
  obtain ⟨⟨k', u⟩, hm, he⟩ := List.mem_map.mp h
  cases he; exact ⟨u, hm⟩

/-- **A thread's step keeps the invariant** (before the sweep): a frame of
    another thread keeps its block (the step's own frames are elsewhere), a
    frame the step leaves keeps its own, and a new frame's block the step
    just checked out, a block no frame was on. -/
theorem LockInv.put {P : Prog} (hP : ProgOK P) {C : Cfg} {ps : List (Nat → Bool)} (hc : CParts P C ps)
    (h : LockInv C) {i : Nat} {t : Thread} {m' : Mem} {s' : Stmt} (hi : C.ths[i]? = some t)
    (hst : Step P (C.view t) t.s (.ok m' s')) : LockInv (C.put i m' s') := by
  obtain ⟨a, ha⟩ := part_of hc.len hi
  obtain ⟨hto, _⟩ := hc.ok i t a hi ha
  have hta : TypedAt P (ownView C t a) t.s := TypedAt.of_threadOK hto
  have htyp : Typed P t.s := by obtain ⟨Γ, F, Δ, ht, _⟩ := hta; exact ⟨Γ, F, Δ, ht⟩
  have hbat : BlocksAt C.blk C.nid := hto.blocksAt
  have hE := Step.lfr hP hst htyp
  have hg : Grows (C.view t) m' := Step.grows hst
  have hilen : i < C.ths.length := (List.getElem?_eq_some_iff.mp hi).1
  have hths : ∀ (j : Nat) (tj : Thread), (C.put i m' s').ths[j]? = some tj →
      (j = i ∧ tj = ⟨m'.st, m'.nv, s'⟩) ∨ (j ≠ i ∧ C.ths[j]? = some tj) := by
    intro j tj hj
    simp only [Cfg.put] at hj
    rw [list_set_get hilen] at hj
    by_cases hij : i = j
    · rw [ite_eq_left hij] at hj; cases hj; exact .inl ⟨hij.symm, rfl⟩
    · rw [ite_eq_right hij] at hj; exact .inr ⟨Ne.symm hij, hj⟩
  -- the frames of the stepping thread after the step: old ones, or the new one
  have hnew : ∀ (k : Nat) (u : Ty), (k, u) ∈ s'.lfr → (k, u) ∈ t.s.lfr ∨
      ((∃ v, C.blk k = some ⟨u, .lock, some v⟩) ∧ CheckedOut m' k u) := by
    intro k u hm
    rcases hE with hpre | ⟨k0, u0, v0, he, h1, h2⟩
    · exact .inl (hpre.subset hm)
    · rw [he, List.mem_append, List.mem_singleton] at hm
      rcases hm with hm | hm
      · exact .inl hm
      · cases hm; exact .inr ⟨⟨v0, h1⟩, h2⟩
  -- a frame of thread `i` that the step keeps keeps its block
  have hkeep : ∀ (k : Nat) (u : Ty), (k, u) ∈ t.s.lfr → (k, u) ∈ s'.lfr →
      LkOut m'.blk m'.taken m'.nid k u := by
    intro k u ho hn
    have hout : Out (C.view t) k := (h.out i t hi k u ho).out
    refine (h.out i t hi k u ho).step_of hg ?_ (Step.taken_stay hst hout)
    rcases Step.stay hst hout with h1 | ⟨_, _, h2⟩
    · exact h1
    · exfalso
      have hc1 : t.s.lkeys.count k ≤ 1 := by
        rw [← lfr_fst, h.nd i t hi k u ho]; exact Nat.le_refl _
      exact h2 _ _ rfl hc1 (mem_lfr_keys hn)
  -- a frame of another thread keeps its block
  have hother : ∀ (j : Nat) (tj : Thread) (k : Nat) (u : Ty), j ≠ i → C.ths[j]? = some tj →
      (k, u) ∈ tj.s.lfr → LkOut m'.blk m'.taken m'.nid k u := by
    intro j tj k u hji hj ho
    have hout : Out (C.view t) k := (h.out j tj hj k u ho).out
    refine (h.out j tj hj k u ho).step_of hg ?_ (Step.taken_stay hst hout)
    rcases Step.stay hst hout with h1 | ⟨hk, _, _⟩
    · exact h1
    · exfalso
      obtain ⟨u', hu'⟩ := keys_lfr hk
      exact hji (h.one j i tj t k u u' hj hi ho hu')
  -- a new frame's block was no frame's: its payload was in
  have hfresh : ∀ (j : Nat) (tj : Thread) (k : Nat) (u u' : Ty), C.ths[j]? = some tj →
      (k, u') ∈ tj.s.lfr → (∃ v, C.blk k = some ⟨u, .lock, some v⟩) → False := by
    intro j tj k u u' hj ho ⟨v, hv⟩
    rcases (h.out j tj hj k u' ho).2 with hn | ⟨ho', _⟩
    · rw [hn] at hv; cases hv
    · rw [ho'] at hv; cases hv
  refine ⟨fun j tj hj k u hm => ?_, fun j1 j2 t1 t2 k u u' hj1 hj2 hm1 hm2 => ?_,
    fun j tj hj k u hm => ?_⟩
  · show LkOut m'.blk m'.taken m'.nid k u
    rcases hths j tj hj with ⟨-, rfl⟩ | ⟨hji, hj⟩
    · rcases hnew k u hm with ho | ⟨⟨v, hv⟩, h2⟩
      · exact hkeep k u ho hm
      · exact ⟨Nat.lt_of_lt_of_le (hbat k _ hv).key hg.nid, .inr h2⟩
    · exact hother j tj k u hji hj hm
  · rcases hths j1 t1 hj1 with ⟨e1, rfl⟩ | ⟨hne1, hj1⟩ <;> rcases hths j2 t2 hj2 with ⟨e2, rfl⟩ | ⟨hne2, hj2⟩
    · exact e1.trans e2.symm
    · rcases hnew k u hm1 with ho | ⟨hv, _⟩
      · exact e1.trans (h.one _ _ _ _ k u u' hi hj2 ho hm2)
      · exact (hfresh _ _ k u u' hj2 hm2 hv).elim
    · rcases hnew k u' hm2 with ho | ⟨hv, _⟩
      · exact (h.one _ _ _ _ k u u' hj1 hi hm1 ho).trans e2.symm
      · exact (hfresh _ _ k u' u hj1 hm1 hv).elim
    · exact h.one _ _ _ _ k u u' hj1 hj2 hm1 hm2
  · rcases hths j tj hj with ⟨-, rfl⟩ | ⟨_, hj⟩
    · show (s'.lfr.map Prod.fst).count k = 1
      rcases hE with hpre | ⟨k0, u0, v0, he, h1, _⟩
      · have ho := hpre.subset hm
        have hle : (s'.lfr.map Prod.fst).count k ≤ (t.s.lfr.map Prod.fst).count k :=
          ((hpre.map Prod.fst).sublist).count_le k
        rw [h.nd i t hi k u ho] at hle
        have hpos : 0 < (s'.lfr.map Prod.fst).count k := List.count_pos_iff.mpr (List.mem_map.mpr ⟨_, hm, rfl⟩)
        omega
      · rw [he, List.map_append, List.count_append]
        rw [he, List.mem_append, List.mem_singleton] at hm
        by_cases hk : k = k0
        · subst hk
          -- no old frame was on the block the step checked out
          have h0 : (t.s.lfr.map Prod.fst).count k = 0 := by
            rw [List.count_eq_zero]
            intro hk'
            obtain ⟨⟨k', w⟩, hw, he'⟩ := List.mem_map.mp hk'
            have hw' : (k, w) ∈ t.s.lfr := by simp only at he'; rw [← he']; exact hw
            exact hfresh i t k u0 w hi hw' ⟨v0, h1⟩
          rw [h0]; simp
        · rcases hm with hm | hm
          · rw [h.nd i t hi k u hm]; simp [Ne.symm hk]
          · cases hm; exact absurd rfl hk
    · exact h.nd j tj hj k u hm

/-- ... and so do the sweep that ends it, and the reaps after it. -/
theorem LockInv.settle {P : Prog} (hP : ProgOK P) (hPc : ProgCodes P) {i : Nat} {C C' : Cfg}
    (h : CSettle P i C C') (hc : ∃ ps, CParts P C ps) (hl : LockInv C) : LockInv C' := by
  induction h with
  | done _ => exact hl
  | reap hi hs _ _ ih =>
    obtain ⟨ps, hc⟩ := hc
    exact ih (hc.putD hP hPc (restrictLemma _) hi hs) (hl.put hP hc hi hs).sweepD

/-- A configuration whose blocks and `nid` are as they were, each of whose
    threads is inside the frames of the thread at its index, or of none,
    keeps the invariant. -/
theorem LockInv.of_lfr {C C' : Cfg} (h : LockInv C) (hb : C'.blk = C.blk) (hn : C'.nid = C.nid)
    (htk : C'.taken = C.taken)
    (hths : ∀ (j : Nat) (tj' : Thread), C'.ths[j]? = some tj' →
      tj'.s.lfr = [] ∨ ∃ tj, C.ths[j]? = some tj ∧ tj'.s.lfr = tj.s.lfr) : LockInv C' := by
  refine ⟨fun j tj hj k u hm => ?_, fun j1 j2 t1 t2 k u u' hj1 hj2 hm1 hm2 => ?_,
    fun j tj hj k u hm => ?_⟩
  · rw [hb, hn, htk]
    rcases hths j tj hj with he | ⟨tj0, hj0, he⟩
    · rw [he] at hm; cases hm
    · rw [he] at hm; exact h.out j tj0 hj0 k u hm
  · rcases hths j1 t1 hj1 with he1 | ⟨t10, h10, he1⟩
    · rw [he1] at hm1; cases hm1
    rcases hths j2 t2 hj2 with he2 | ⟨t20, h20, he2⟩
    · rw [he2] at hm2; cases hm2
    rw [he1] at hm1; rw [he2] at hm2
    exact h.one j1 j2 t10 t20 k u u' h10 h20 hm1 hm2
  · rcases hths j tj hj with he | ⟨tj0, hj0, he⟩
    · rw [he] at hm; cases hm
    · rw [he] at hm ⊢; exact h.nd j tj0 hj0 k u hm

/-- **A spawn keeps the invariant**: the spawner's call becomes its result's
    scope, inside the same frames (its continuation is source), and the new
    thread runs a function's body, inside none; no block changes. -/
theorem LockInv.spawn {P : Prog} (hP : ProgOK P) {C : Cfg} {ps : List (Nat → Bool)} (hc : CParts P C ps)
    (h : LockInv C) {i : Nat} {t : Thread} {K : Stmt → Stmt} {x f : Nat} {args : List Var} {k : Stmt}
    {fn : Fn} (hi : C.ths[i]? = some t) (hK : Redex t.s K (.letcall x f args k)) (hf : P[f]? = some fn)
    (st'' : Var → Option Slot) (stn : Var → Option Slot) :
    LockInv { C with ths := C.ths.set i ⟨st'', t.nv, K (.scope x k)⟩ ++
                    [⟨stn, fn.nvars, wrapParams fn.params 0 0 (.scope fn.params.length fn.body)⟩] } := by
  obtain ⟨a, ha⟩ := part_of hc.len hi
  obtain ⟨hto, _⟩ := hc.ok i t a hi ha
  obtain ⟨Γ, F, Δ, ht, hinv, _⟩ := hto
  obtain ⟨Γ', F', Δ', ht', _⟩ := hK.typed Γ F Δ ht hinv
  have hks : k.src = true := by simpa [Stmt.src] using letcall_src ht'
  have hlfr : (K (.scope x k)).lfr = t.s.lfr := by
    rw [hK.eq]; exact hK.lfr_eq (by simp [Stmt.lfr, lfr_src hks])
  have hilen : i < C.ths.length := (List.getElem?_eq_some_iff.mp hi).1
  refine h.of_lfr rfl rfl rfl fun j tj hj => ?_
  simp only at hj
  rw [get_set_append hilen] at hj
  by_cases hjl : j < C.ths.length
  · rw [ite_eq_left hjl] at hj
    by_cases hij : i = j
    · rw [ite_eq_left hij] at hj; cases hj; subst hij; exact .inr ⟨t, hi, hlfr⟩
    · rw [ite_eq_right hij] at hj; exact .inr ⟨tj, hj, rfl⟩
  · rw [ite_eq_right hjl] at hj
    by_cases hje : j = C.ths.length
    · rw [ite_eq_left hje] at hj; cases hj
      exact .inl (by simp [lfr_wrap, Stmt.lfr, lfr_src (body_src hP hf)])
    · rw [ite_eq_right hje] at hj; cases hj

/-- ... and so does a spawn whose crossing check fails: a panic before the
    call, inside the same frames. -/
theorem LockInv.spawnFail {C : Cfg} (h : LockInv C) {i : Nat} {t : Thread} {K : Stmt → Stmt} {x f : Nat}
    {args : List Var} {k : Stmt} (hi : C.ths[i]? = some t) (hK : Redex t.s K (.letcall x f args k)) :
    LockInv { C with ths := C.ths.set i ⟨t.st, t.nv, K (.seq .panic (.letcall x f args k))⟩ } := by
  have hlfr : (K (.seq .panic (.letcall x f args k))).lfr = t.s.lfr := by
    rw [hK.eq]; exact hK.lfr_eq rfl
  have hilen : i < C.ths.length := (List.getElem?_eq_some_iff.mp hi).1
  refine h.of_lfr rfl rfl rfl fun j tj hj => ?_
  simp only at hj
  rw [list_set_get hilen] at hj
  by_cases hij : i = j
  · rw [ite_eq_left hij] at hj; cases hj; subst hij; exact .inr ⟨t, hi, hlfr⟩
  · rw [ite_eq_right hij] at hj; exact .inr ⟨tj, hj, rfl⟩

/-- **Every step of the configuration keeps the invariant**: a thread's
    step, the marking sweep and the reaps after it, a spawn, a failed spawn. -/
theorem LockInv.tstep {P : Prog} {spawn : Nat → Bool} (hP : ProgOK P) (hPc : ProgCodes P) {C C' : Cfg}
    (hc : CInv P C) (h : LockInv C) (hs : TStep P spawn C C') : LockInv C' := by
  obtain ⟨ps, hcp, _⟩ := hc
  cases hs with
  | thread hi _ hst hse =>
    exact LockInv.settle hP hPc hse (hcp.putD hP hPc (restrictLemma _) hi hst) (h.put hP hcp hi hst).sweepD
  | spawn hi hK _ hf _ _ _ => exact h.spawn hP hcp hi hK hf _ _
  | spawnFail hi hK _ _ _ _ _ => exact h.spawnFail hi hK

/-- The start: one thread, of source code, inside no frame. -/
theorem LockInv.start {G : Globs} {s : Stmt} (hs : s.src = true) (nv : Nat) : LockInv (Cfg.start G s nv) := by
  have hnil : ∀ (j : Nat) (t : Thread), (Cfg.start G s nv).ths[j]? = some t → t.s.lfr = [] := by
    intro j t hj
    cases j with
    | zero => simp [Cfg.start] at hj; subst hj; exact lfr_src hs
    | succ j => simp [Cfg.start] at hj
  refine ⟨fun j t hj k u hm => ?_, fun j _ t _ k u _ hj _ hm _ => ?_, fun j t hj k u hm => ?_⟩ <;>
    (rw [hnil _ _ hj] at hm; cases hm)

theorem Reach.snoc {P : Prog} {spawn : Nat → Bool} {C C1 C2 : Cfg} (h : Reach P spawn C C1)
    (hs : TStep P spawn C1 C2) : Reach P spawn C C2 := by
  induction h with
  | refl => exact .step hs .refl
  | step h1 _ ih => exact .step h1 (ih hs)

/-- **Agora #808: every configuration a typed start reaches keeps the
    check-outs' invariant.** -/
theorem reach_lockInv {P : Prog} {spawn : Nat → Bool} {G : Globs} {s : Stmt} {Δ : Ctx} {nv : Nat}
    (hP : ProgOK P) (hPc : ProgCodes P) (hSp : SpawnOK P spawn) (hG : GlobsOK P G)
    (ht : StmtT P (fun _ => none) [] s Δ) (hs : s.src = true) (hsc : s.codesOK P)
    (hv : ∀ v ∈ s.vars, v < nv) {C : Cfg} (hr : Reach P spawn (Cfg.start G s nv) C) : LockInv C := by
  have key : ∀ C1 C2, Reach P spawn C1 C2 → Reach P spawn (Cfg.start G s nv) C1 → LockInv C1 → LockInv C2 := by
    intro C1 C2 h
    induction h with
    | refl => exact fun _ hl => hl
    | step hst _ ih =>
      exact fun h0 hl => ih (h0.snoc hst) (hl.tstep hP hPc (reach_inv hP hPc hSp hG ht hs hsc hv h0).1 hst)
  exact key _ _ hr .refl (LockInv.start hs nv)

/-! ### What a reached configuration's frames say -/

/-- A frame on a statement's spine is one of its frames twice if its body is
    inside another of its block. -/
theorem Redex.count_two {s r : Stmt} {K : Stmt → Stmt} (h : Redex s K r) {k : Nat} {u : Ty} {x : Var}
    {b : Stmt} (hr : r = .scopeL k u x b) (hk : k ∈ b.lkeys) : 2 ≤ (s.lfr.map Prod.fst).count k := by
  induction h with
  | here =>
    subst hr
    have : 0 < (b.lfr.map Prod.fst).count k := List.count_pos_iff.mpr (by rw [lfr_fst]; exact hk)
    simp only [Stmt.lfr, List.map_cons, List.count_cons_self]
    omega
  | seq _ ih => exact ih hr
  | scope _ ih => exact ih hr
  | rbind _ ih => exact ih hr
  | frozen _ ih => exact ih hr
  | catchR _ ih => exact ih hr
  | scopeD _ ih => exact ih hr
  | scopeL _ ih =>
    have := ih hr
    simp only [Stmt.lfr, List.map_cons, List.count_cons]
    omega

/-- **One frame of a block a statement's spine has once**: two decompositions
    of the statement at frames of block `k` are one. -/
theorem Redex.frame_unique {s : Stmt} {K1 K2 : Stmt → Stmt} {k : Nat} {u1 u2 : Ty} {x1 x2 : Var}
    {b1 b2 : Stmt} (h1 : Redex s K1 (.scopeL k u1 x1 b1)) (h2 : Redex s K2 (.scopeL k u2 x2 b2))
    (hc : (s.lfr.map Prod.fst).count k = 1) : K1 = K2 ∧ u1 = u2 ∧ x1 = x2 ∧ b1 = b2 := by
  generalize hr : Stmt.scopeL k u1 x1 b1 = r at h1
  induction h1 generalizing K2 with
  | here =>
    subst hr
    cases h2 with
    | here => exact ⟨rfl, rfl, rfl, rfl⟩
    | scopeL h2' =>
      have := Redex.count_two (s := Stmt.scopeL k u1 x1 b1) Redex.here rfl (mem_lfr_keys (h2'.lfr_mem rfl))
      omega
  | seq _ ih =>
    cases h2 with
    | seq h2' => obtain ⟨e, rest⟩ := ih h2' hc hr; subst e; exact ⟨rfl, rest⟩
  | scope _ ih =>
    cases h2 with
    | scope h2' => obtain ⟨e, rest⟩ := ih h2' hc hr; subst e; exact ⟨rfl, rest⟩
  | rbind _ ih =>
    cases h2 with
    | rbind h2' => obtain ⟨e, rest⟩ := ih h2' hc hr; subst e; exact ⟨rfl, rest⟩
  | frozen _ ih =>
    cases h2 with
    | frozen h2' => obtain ⟨e, rest⟩ := ih h2' hc hr; subst e; exact ⟨rfl, rest⟩
  | catchR _ ih =>
    cases h2 with
    | catchR h2' => obtain ⟨e, rest⟩ := ih h2' hc hr; subst e; exact ⟨rfl, rest⟩
  | scopeD _ ih =>
    cases h2 with
    | scopeD h2' => obtain ⟨e, rest⟩ := ih h2' hc hr; subst e; exact ⟨rfl, rest⟩
  | @scopeL k0 t0 x0 b0 r0 K0 h1' ih =>
    cases h2 with
    | here =>
      have := Redex.count_two (s := Stmt.scopeL k u2 x2 b2) Redex.here rfl (mem_lfr_keys (h1'.lfr_mem hr.symm))
      omega
    | scopeL h2' =>
      have hm : 0 < (b0.lfr.map Prod.fst).count k :=
        List.count_pos_iff.mpr (by rw [lfr_fst]; exact mem_lfr_keys (h1'.lfr_mem hr.symm))
      simp only [Stmt.lfr, List.map_cons, List.count_cons] at hc
      have hc' : (b0.lfr.map Prod.fst).count k = 1 := by split at hc <;> omega
      obtain ⟨e, rest⟩ := ih h2' hc' hr; subst e; exact ⟨rfl, rest⟩

section reach
variable {P : Prog} {spawn : Nat → Bool} {G : Globs} {s0 : Stmt} {Δ0 : Ctx} {nv : Nat}

/-- **A frame's block, in a reached configuration** (Agora #808): the block
    is checked out (`⟨u, .lock, none⟩`, and Agora #810 not taken), or gone,
    at a key below `nid`; for every payload type. -/
theorem reach_frame_out (hP : ProgOK P) (hPc : ProgCodes P) (hSp : SpawnOK P spawn) (hG : GlobsOK P G)
    (ht : StmtT P (fun _ => none) [] s0 Δ0) (hs : s0.src = true) (hsc : s0.codesOK P)
    (hv : ∀ v ∈ s0.vars, v < nv) {C : Cfg} (hr : Reach P spawn (Cfg.start G s0 nv) C)
    {i : Nat} {th : Thread} {K : Stmt → Stmt} {k : Nat} {u : Ty} {x : Var} {b : Stmt}
    (hi : C.ths[i]? = some th) (hK : Redex th.s K (.scopeL k u x b)) :
    k < C.nid ∧ (C.blk k = none ∨ (C.blk k = some ⟨u, .lock, none⟩ ∧ C.taken k = false)) :=
  (reach_lockInv hP hPc hSp hG ht hs hsc hv hr).out i th hi k u (hK.lfr_mem rfl)

/-- **A3.2's mutual exclusion** (Agora #808): in a reached configuration, two
    frames of one block are one frame, of one thread: at most one `scopeL`
    frame of a lock block is out at a time, whatever its payload's type.
    (Agora #810: `locked_restore` fills only a block `locked_take` emptied,
    `Mem.taken`, never one a `withLock` checked out.) -/
theorem reach_lock_excl (hP : ProgOK P) (hPc : ProgCodes P) (hSp : SpawnOK P spawn) (hG : GlobsOK P G)
    (ht : StmtT P (fun _ => none) [] s0 Δ0) (hs : s0.src = true) (hsc : s0.codesOK P)
    (hv : ∀ v ∈ s0.vars, v < nv) {C : Cfg} (hr : Reach P spawn (Cfg.start G s0 nv) C)
    {i j : Nat} {ti tj : Thread} {K1 K2 : Stmt → Stmt} {k : Nat} {u1 u2 : Ty} {x1 x2 : Var} {b1 b2 : Stmt}
    (hi : C.ths[i]? = some ti) (hj : C.ths[j]? = some tj)
    (h1 : Redex ti.s K1 (.scopeL k u1 x1 b1)) (h2 : Redex tj.s K2 (.scopeL k u2 x2 b2)) :
    i = j ∧ K1 = K2 ∧ u1 = u2 ∧ x1 = x2 ∧ b1 = b2 := by
  have hl := reach_lockInv hP hPc hSp hG ht hs hsc hv hr
  have hij := hl.one i j ti tj k u1 u2 hi hj (h1.lfr_mem rfl) (h2.lfr_mem rfl)
  subst hij
  rw [hi] at hj; cases hj
  exact ⟨rfl, Redex.frame_unique h1 h2 (hl.nd i ti hi k u1 (h1.lfr_mem rfl))⟩

/-- `LockDtorWitness.scopeL_typed_panic`, with the frame's invariant over a
    store of the same slots as the one the step runs on. -/
theorem scopeL_typed_panic_of {Γ Δ : Ctx} {F : List Var} {k : Nat} {t : Ty} {x : Var} {s : Stmt}
    {m mo m2 : Mem} (ht : StmtT P Γ F (.scopeL k t x s) Δ) (hi : Inv mo Γ F (.scopeL k t x s))
    (hst0 : mo.st = m.st) (hd : t.holdsDtor = true) (hna : t.hasArc = false) (hvf : t.holdsView = false)
    (h : Step P m (.scopeL k t x s) (.panic m2)) :
    ∃ m1, Step P m s (.panic m1) ∧
      ((∃ v, m1.st x = some ⟨true, some v⟩ ∧ WFv t v ∧
          (CheckedOut m1 k t →
            m2 = ({ m1 with blk := upd m1.blk k (some ⟨t, .lock, some v⟩) }.remove x))) ∨
        (m1.st x = some ⟨true, none⟩ ∧ m2 = m1.remove x)) := by
  cases h with
  | waitPanic hw => exact hw.elim
  | @scopeLP m1 _ _ _ _ _ hs hrl =>
    refine ⟨m1, hs, ?_⟩
    have hxsp : x ∉ s.spine := by
      have := hi.spineNd; simp only [Stmt.spine, List.nodup_cons] at this; exact this.1
    have hst := LockDtorWitness.Step.panic_st hs x hxsp
    obtain ⟨E, hx, hm, hty⟩ := LockDtorWitness.scopeL_entry ht hd
    obtain ⟨sl, hsl, _, hown, hok, _⟩ := hi.slot x E hx
    rw [hst0] at hsl
    rw [hm] at hown hok
    obtain ⟨_, hw, _⟩ := hok rfl
    obtain ⟨o, val⟩ := sl
    simp only at hown; subst hown
    cases val with
    | some v =>
      have hx1 : m1.st x = some ⟨true, some v⟩ := by rw [hst]; exact hsl
      exact .inl ⟨v, hx1, hty ▸ hw v rfl,
        fun hk => LockDtorWitness.release_puts hx1 (hty ▸ hw v rfl) hna hvf hk hrl⟩
    | none =>
      have hx1 : m1.st x = some ⟨true, none⟩ := by rw [hst]; exact hsl
      refine .inr ⟨hx1, ?_⟩
      cases hrl with
      | put hx' _ _ _ => rw [hx1] at hx'; cases hx'
      | drop _ hx' hdr => rw [hx1] at hx'; cases hx'; cases hdr; rfl

end reach

end A3
