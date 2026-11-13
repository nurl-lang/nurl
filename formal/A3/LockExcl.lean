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

So the give-back lemmas of `A3.LockDtorWitness` (`scopeL_typed_end_gives_back`,
`scopeL_typed_panic`) hold of a frame of a reached configuration with the
block's state discharged, given only that the block is still there
(`reach_scopeL_end_gives_back`, `reach_scopeL_panic`).  That a frame's block
is never removed while the frame is out (the check-out's root share outlives
the body) is not proved here: a frame does not record the binding its share
is in. -/

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
    added, its block's payload in before (`some v`) and out after. -/
def FrStep (m m' : Mem) (L L' : List (Nat × Ty)) : Prop :=
  L' <+: L ∨ ∃ k u v, L' = L ++ [(k, u)] ∧ m.blk k = some ⟨u, .lock, some v⟩ ∧ m'.blk k = some ⟨u, .lock, none⟩

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
    simp [Mem.set, upd]
  | scopeLFail _ _ => cases hr; intro _; exact .inl List.prefix_rfl
  | _ => first
    | (cases hr; done)
    | (cases hr; intro _; exact FrStep.nil (by simp [Stmt.lfr, handStmt, handStmtD]))

/-! ### What a step does to a block whose payload is out -/

/-- Block `k` of `m` is out for a frame whose payload is not `dtorFree`: its
    payload checked out, or the block gone, at a key below `nid` (which no
    new block takes). -/
def Out (m : Mem) (k : Nat) : Prop :=
  (m.blk k = none ∧ k < m.nid) ∨ ∃ u, m.blk k = some ⟨u, .lock, none⟩ ∧ u.dtorFree = false

/-- A right-hand side gives back (`locked_restore`) only payloads that are
    `dtorFree` (`RhsT.lockRestore`). -/
def RestoreFree (m : Mem) (r : Rhs) : Prop :=
  ∀ a y o k t ob, r = .lockRestore a y → m.st a = some ⟨o, some (.lk k)⟩ → m.blk k = some ⟨t, .lock, ob⟩ →
    t.dtorFree = true

/-- ... and so do the redexes of a statement's spine. -/
def RF (m : Mem) : Stmt → Prop
  | .seq a _ => RF m a
  | .scope _ s => RF m s
  | .scopeD _ _ s => RF m s
  | .rbind _ s => RF m s
  | .frozen _ s => RF m s
  | .catchR _ _ s => RF m s
  | .scopeL _ _ _ s => RF m s
  | .letv _ r _ => RestoreFree m r
  | .assign _ r => RestoreFree m r
  | .letd _ _ r _ => RestoreFree m r
  | _ => True

theorem rhsT_restoreFree {m : Mem} {Γ : Ctx} (hi : MInv m Γ) {F : List Var} {r : Rhs} {E : Entry}
    {Γ1 : Ctx} (h : RhsT Γ F r E Γ1) : RestoreFree m r := by
  intro a y o k t ob hr ha hk
  subst hr
  cases h with
  | lockRestore hEa hl hty _ _ _ _ hdf =>
    obtain ⟨ob', hk'⟩ := hi.lk_val hEa hl hty ha
    rw [hk] at hk'; cases hk'; exact hdf

theorem RestoreFree.congr {m m' : Mem} {r : Rhs} (h : RestoreFree m r) (hst : m'.st = m.st)
    (hb : m'.blk = m.blk) : RestoreFree m' r := by
  intro a y o k t ob hr ha hk
  exact h a y o k t ob hr (hst ▸ ha) (hb ▸ hk)

theorem RF.congr {m m' : Mem} (hst : m'.st = m.st) (hb : m'.blk = m.blk) : ∀ {s : Stmt}, RF m s → RF m' s := by
  intro s
  induction s with
  | seq _ _ ih _ => exact ih
  | scope _ _ ih => exact ih
  | scopeD _ _ _ ih => exact ih
  | rbind _ _ ih => exact ih
  | frozen _ _ ih => exact ih
  | catchR _ _ _ ih => exact ih
  | scopeL _ _ _ _ ih => exact ih
  | letv _ _ _ _ => exact fun h => RestoreFree.congr h hst hb
  | assign _ _ => exact fun h => RestoreFree.congr h hst hb
  | letd _ _ _ _ _ => exact fun h => RestoreFree.congr h hst hb
  | _ => exact fun _ => trivial

/-- A typed statement's spine restores only `dtorFree` payloads. -/
theorem TypedAt.rf {P : Prog} {m : Mem} : ∀ {s : Stmt}, TypedAt P m s → RF m s := by
  intro s
  induction s with
  | seq _ _ ih _ => exact fun h => ih h.seq
  | scope _ _ ih => exact fun h => ih h.scope
  | scopeD _ _ _ ih => exact fun h => ih h.scopeD
  | rbind _ _ ih => exact fun h => ih h.rbind
  | frozen _ _ ih => exact fun h => ih h.frozen
  | catchR _ _ _ ih => exact fun h => ih h.catchR
  | scopeL _ _ _ _ ih => exact fun h => ih h.scopeL
  | letv x r s _ =>
    intro h
    obtain ⟨Γ, F, Δ, ht, hi⟩ := h
    generalize hs : Stmt.letv x r s = s0 at ht
    induction ht with
    | letv _ _ _ hr _ _ _ => cases hs; exact rhsT_restoreFree hi hr
    | sub hw _ _ ih => exact ih (hi.weaker hw) hs
    | _ => cases hs
  | assign x r =>
    intro h
    obtain ⟨Γ, F, Δ, ht, hi⟩ := h
    generalize hs : Stmt.assign x r = s0 at ht
    induction ht with
    | assign _ _ _ hr _ _ _ _ => cases hs; exact rhsT_restoreFree hi hr
    | sub hw _ _ ih => exact ih (hi.weaker hw) hs
    | _ => cases hs
  | letd x f r s _ =>
    intro h
    obtain ⟨Γ, F, Δ, ht, hi⟩ := h
    generalize hs : Stmt.letd x f r s = s0 at ht
    induction ht with
    | letd _ _ _ hr _ _ _ _ _ _ _ => cases hs; exact rhsT_restoreFree hi hr
    | sub hw _ _ ih => exact ih (hi.weaker hw) hs
    | _ => cases hs
  | _ => exact fun _ => trivial

theorem TakeVal.blk_eq {m m1 : Mem} {y : Var} {v : Val} (h : TakeVal m y v m1) : m1.blk = m.blk := by
  cases h <;> rfl

theorem BindParams.blk_eq {m m' : Mem} {ps : List (PMode × Ty)} {as : List Var} {base i : Nat}
    (h : BindParams m ps as base i m') : m'.blk = m.blk := by
  induction h with
  | nil => rfl
  | inp _ _ _ ih => exact ih
  | sink _ _ ih => exact ih
  | inout _ ih => exact ih

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
    `locked_restore`, which is of a `dtorFree` payload; a new block's key is
    fresh. -/
theorem EvalR.stay {m m1 : Mem} {r : Rhs} {v : Val} {o : Bool} (h : EvalR m r (.ok v o m1))
    (hrf : RestoreFree m r) {k : Nat} (hk : Out m k) : m1.blk k = m.blk k := by
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
  | @lockRestore a y o0 k0 t w m2 ha h1 h0 _ =>
    rw [TakeVal.blk_eq h1] at h0 ⊢
    by_cases he : k = k0
    · subst he
      have hdf := hrf a y o0 k t none rfl ha h0
      rcases hk with ⟨hn, _⟩ | ⟨u, hu, hu'⟩
      · rw [hn] at h0; cases h0
      · rw [hu] at h0; cases h0; rw [hdf] at hu'; cases hu'
    · exact upd_ne _ _ he
  | pair h1 h2 => rw [TakeVal.blk_eq h2, TakeVal.blk_eq h1]
  | inl h1 | inr h1 | pack h1 => rw [TakeVal.blk_eq h1]
  | _ => rfl

/-- A lock scope's end changes no block but its own. -/
theorem Release.stay {m m' : Mem} {k0 : Nat} {t : Ty} {x : Var} (h : Release m k0 t x m') (k : Nat) :
    m'.blk k = m.blk k ∨ (k = k0 ∧ m.blk k = some ⟨t, .lock, none⟩) := by
  cases h with
  | put _ _ hk _ =>
    by_cases he : k = k0
    · subst he; exact .inr ⟨rfl, hk⟩
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
theorem Step.stay {P : Prog} {m : Mem} {s : Stmt} {r : Res} (h : Step P m s r) (hrf : RF m s) {k : Nat}
    (hk : Out m k) :
    r.mem.blk k = m.blk k ∨
      (k ∈ s.lkeys ∧ (∃ u, m.blk k = some ⟨u, .lock, none⟩) ∧
        ∀ m' s', r = .ok m' s' → s.lkeys.count k ≤ 1 → k ∉ s'.lkeys) := by
  revert hrf hk
  induction h with
  | seqL _ ih | scopeIn _ ih | rbindIn _ ih | frozenIn _ ih | catchIn _ ih | scopeDIn _ ih =>
    intro hrf hk
    rcases ih hrf hk with h1 | ⟨h1, hs, h2⟩
    · exact .inl h1
    · exact .inr ⟨h1, hs, fun m' s' he hc => by cases he; have h3 := h2 _ _ rfl hc; exact h3⟩
  | seqP _ ih | frozenP _ ih =>
    intro hrf hk
    rcases ih hrf hk with h1 | ⟨h1, hs, _⟩
    · exact .inl h1
    · exact .inr ⟨h1, hs, fun _ _ he => by cases he⟩
  | scopeP _ _ _ ih | rbindP _ _ ih | scopeDPMoved _ _ ih =>
    intro hrf hk
    rcases ih hrf hk with h1 | ⟨h1, hs, _⟩
    · exact .inl h1
    · exact .inr ⟨h1, hs, fun _ _ he => by cases he⟩
  | catchP _ _ ih | scopeDP _ _ _ ih | scopeDPDrain _ _ ih =>
    intro hrf hk
    rcases ih hrf hk with h1 | ⟨h1, hs, _⟩
    · exact .inl h1
    · exact .inr ⟨h1, hs, fun _ _ he _ => by cases he; simp [Stmt.lkeys]⟩
  | @scopeLIn m' k0 t0 x b b' _ ih =>
    intro hrf hk
    rcases ih hrf hk with h1 | ⟨h1, hs, h2⟩
    · exact .inl h1
    · refine .inr ⟨List.mem_cons_of_mem _ h1, hs, fun m'' s'' he hc => ?_⟩
      cases he
      obtain ⟨hne, hc'⟩ := count_le_of_cons hc h1
      have := h2 _ _ rfl hc'
      simp only [Stmt.lkeys, List.mem_cons, not_or]
      exact ⟨hne, this⟩
  | @scopeLP m1 m2 k0 t0 x b _ hrl ih =>
    intro hrf hk
    rcases ih hrf hk with h1 | ⟨h1, hs, _⟩
    · rcases Release.stay hrl k with h0 | ⟨rfl, hs⟩
      · exact .inl (h0.trans h1)
      · exact .inr ⟨List.mem_cons_self, ⟨t0, h1 ▸ hs⟩, fun _ _ he => by cases he⟩
    · rcases Release.stay hrl k with h0 | ⟨rfl, _⟩
      · exact .inr ⟨List.mem_cons_of_mem _ h1, hs, fun _ _ he => by cases he⟩
      · exact .inr ⟨List.mem_cons_self, hs, fun _ _ he => by cases he⟩
  | @scopeLSkip m' k0 t0 x hrl _ =>
    intro _ _
    rcases Release.stay hrl k with h0 | ⟨rfl, hs⟩
    · exact .inl h0
    · exact .inr ⟨List.mem_cons_self, ⟨t0, hs⟩, fun _ _ he _ => by cases he; simp [Stmt.lkeys]⟩
  | letv _ he | letd _ he =>
    intro hrf hk; exact .inl (EvalR.stay he hrf hk)
  | assign _ he _ _ =>
    intro hrf hk; exact .inl (EvalR.stay he hrf hk)
  | letcall _ _ hb =>
    intro _ _; exact .inl (congrFun (BindParams.blk_eq hb) k)
  | callc _ _ _ _ hb =>
    intro _ _; exact .inl (congrFun (BindParams.blk_eq hb) k)
  | push h1 _ _ _ | pushRealloc h1 _ _ _ | insert _ h1 _ _ _ | editPush h1 _ _ | editPushRealloc h1 _ _
  | editSet _ _ h1 _ _ _ | editSetOOB _ h1 _ _ _ =>
    intro _ _; exact .inl (congrFun (TakeVal.blk_eq h1) k)
  | withLock _ h0 _ _ =>
    intro _ hk; exact .inl (upd_ne _ _ (hk.ne_some h0))
  | reap _ h0 _ =>
    intro _ hk
    refine .inl (upd_ne _ _ ?_)
    rintro rfl
    rcases hk with ⟨hn, _⟩ | ⟨u, hu, _⟩
    · rw [hn] at h0; cases h0
    · rw [hu] at h0; cases h0
  | _ => intro _ _; exact .inl rfl

/-! ### The invariant -/

/-- The block of a frame of payload type `u`, in the blocks `B` with `n` the
    next fresh key: below `n` (no new block takes the key), and gone, or a
    lock block of type `u` whose payload, when `u` is not `dtorFree`, is out. -/
def LkOut (B : Nat → Option Blk) (n k : Nat) (u : Ty) : Prop :=
  k < n ∧ (B k = none ∨ ∃ o, B k = some ⟨u, .lock, o⟩ ∧ (u.dtorFree = false → o = none))

/-- **Agora #808: the check-outs' invariant.**  Over the threads' statements
    and the shared blocks:
    - `out`: every frame's block is as `LkOut` says;
    - `one`: a frame whose payload is not `dtorFree` is the only frame of its
      block on any thread (A3.2's mutual exclusion) ...
    - `nd`: ... and the only one on its own thread. -/
structure LockInv (C : Cfg) : Prop where
  out : ∀ (i : Nat) (t : Thread), C.ths[i]? = some t → ∀ (k : Nat) (u : Ty), (k, u) ∈ t.s.lfr →
    LkOut C.blk C.nid k u
  one : ∀ (i j : Nat) (ti tj : Thread) (k : Nat) (u u' : Ty), C.ths[i]? = some ti → C.ths[j]? = some tj →
    (k, u) ∈ ti.s.lfr → (k, u') ∈ tj.s.lfr → u.dtorFree = false → i = j
  nd  : ∀ (i : Nat) (t : Thread), C.ths[i]? = some t → ∀ (k : Nat) (u : Ty), (k, u) ∈ t.s.lfr →
    u.dtorFree = false → (t.s.lfr.map Prod.fst).count k = 1

theorem nest_dtor_dtorFree (n f : Nat) (w : Ty) : (Ty.nest n (.dtor f w)).dtorFree = false := by
  induction n with
  | zero => rfl
  | succ n ih => simp [Ty.nest, Ty.dtorFree]

/-- The marking sweep keeps a frame's block as `LkOut` says: it removes it,
    or keeps it; it marks no lock block whose payload is out, nor one of a
    `dtorFree` type (an orphan to be holds a destructor value, `Cand`). -/
theorem LkOut.sweepD {R : Val → Prop} {B : Nat → Option Blk} {n k : Nat} {u : Ty} (h : LkOut B n k u) :
    LkOut (sweepBlkD R B) n k u := by
  refine ⟨h.1, ?_⟩
  unfold sweepBlkD
  split
  · exact h.2
  · split
    · next hp =>
      rcases h.2 with hn | ⟨o, ho, hdf⟩
      · exact .inl (by rw [hn]; rfl)
      · exfalso
        rcases hp with ⟨⟨⟨n', f, w, p, kd, _, hc⟩, _⟩, _⟩ | ⟨n', f, w, p, hd⟩
        · rw [ho] at hc; cases hc
          cases hdf (nest_dtor_dtorFree n' f w)
        · rw [ho] at hd; cases hd
    · exact .inl rfl

theorem LockInv.sweepD {C : Cfg} (h : LockInv C) : LockInv C.sweepD :=
  ⟨fun i t hi k u hm => (h.out i t hi k u hm).sweepD, h.one, h.nd⟩

/-- A frame's block after a step that keeps it as it was, or (a frame of a
    `dtorFree` payload, its block there) as a lock block of its type. -/
theorem LkOut.step_of {m m' : Mem} {k : Nat} {u : Ty} (h : LkOut m.blk m.nid k u) (hg : Grows m m')
    (hsame : (u.dtorFree = false ∨ m.blk k = none) → m'.blk k = m.blk k) : LkOut m'.blk m'.nid k u := by
  refine ⟨Nat.lt_of_lt_of_le h.1 hg.nid, ?_⟩
  rcases h.2 with hn | ⟨o, ho, hdf⟩
  · exact .inl ((hsame (.inr hn)).trans hn)
  · cases hu : u.dtorFree with
    | false => exact .inr ⟨o, (hsame (.inl hu)).trans ho, fun _ => hdf hu⟩
    | true =>
      obtain ⟨o', ho'⟩ := BlkLe.lock hg.blk ho
      exact .inr ⟨o', ho', fun h => by cases h⟩

/-- ... whose block, if not `dtorFree` or gone, is out. -/
theorem LkOut.out {m : Mem} {k : Nat} {u : Ty} (h : LkOut m.blk m.nid k u) (hc : u.dtorFree = false ∨ m.blk k = none) :
    Out m k := by
  rcases h.2 with hn | ⟨o, ho, hdf⟩
  · exact .inl ⟨hn, h.1⟩
  · rcases hc with hc | hc
    · exact .inr ⟨u, by rw [ho, hdf hc], hc⟩
    · rw [ho] at hc; cases hc

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
  have hrf : RF (C.view t) t.s := RF.congr (m := ownView C t a) (m' := C.view t) rfl rfl hta.rf
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
      ((∃ v, C.blk k = some ⟨u, .lock, some v⟩) ∧ m'.blk k = some ⟨u, .lock, none⟩) := by
    intro k u hm
    rcases hE with hpre | ⟨k0, u0, v0, he, h1, h2⟩
    · exact .inl (hpre.subset hm)
    · rw [he, List.mem_append, List.mem_singleton] at hm
      rcases hm with hm | hm
      · exact .inl hm
      · cases hm; exact .inr ⟨⟨v0, h1⟩, h2⟩
  -- a frame of thread `i` that the step keeps keeps its block
  have hkeep : ∀ (k : Nat) (u : Ty), (k, u) ∈ t.s.lfr → (k, u) ∈ s'.lfr → LkOut m'.blk m'.nid k u := by
    intro k u ho hn
    refine (h.out i t hi k u ho).step_of hg fun hc => ?_
    rcases Step.stay hst hrf ((h.out i t hi k u ho).out hc) with h1 | ⟨_, ⟨w, hw⟩, h2⟩
    · exact h1
    · exfalso
      have hc1 : t.s.lkeys.count k ≤ 1 := by
        rcases hc with hc | hc
        · rw [← lfr_fst, h.nd i t hi k u ho hc]; exact Nat.le_refl _
        · change C.blk k = none at hc; change C.blk k = _ at hw; rw [hc] at hw; cases hw
      exact h2 _ _ rfl hc1 (mem_lfr_keys hn)
  -- a frame of another thread keeps its block
  have hother : ∀ (j : Nat) (tj : Thread) (k : Nat) (u : Ty), j ≠ i → C.ths[j]? = some tj → (k, u) ∈ tj.s.lfr → LkOut m'.blk m'.nid k u := by
    intro j tj k u hji hj ho
    refine (h.out j tj hj k u ho).step_of hg fun hc => ?_
    rcases Step.stay hst hrf ((h.out j tj hj k u ho).out hc) with h1 | ⟨hk, ⟨w, hw⟩, _⟩
    · exact h1
    · exfalso
      obtain ⟨u', hu'⟩ := keys_lfr hk
      rcases hc with hc | hc
      · exact hji (h.one j i tj t k u u' hj hi ho hu' hc)
      · change C.blk k = none at hc; change C.blk k = _ at hw; rw [hc] at hw; cases hw
  -- a new frame's block was no frame's of payload not `dtorFree`
  have hfresh : ∀ (j : Nat) (tj : Thread) (k : Nat) (u u' : Ty), C.ths[j]? = some tj → (k, u') ∈ tj.s.lfr → (∃ v, C.blk k = some ⟨u, .lock, some v⟩) →
      u = u' ∧ u'.dtorFree = true := by
    intro j tj k u u' hj ho ⟨v, hv⟩
    rcases (h.out j tj hj k u' ho).2 with hn | ⟨o, ho', hdf⟩
    · rw [hn] at hv; cases hv
    · rw [ho'] at hv; cases hv
      cases hd : u.dtorFree with
      | true => exact ⟨rfl, rfl⟩
      | false => cases hdf hd
  refine ⟨fun j tj hj k u hm => ?_, fun j1 j2 t1 t2 k u u' hj1 hj2 hm1 hm2 hdf => ?_,
    fun j tj hj k u hm hdf => ?_⟩
  · show LkOut m'.blk m'.nid k u
    rcases hths j tj hj with ⟨-, rfl⟩ | ⟨hji, hj⟩
    · rcases hnew k u hm with ho | ⟨⟨v, hv⟩, h2⟩
      · exact hkeep k u ho hm
      · exact ⟨Nat.lt_of_lt_of_le (hbat k _ hv).key hg.nid, .inr ⟨none, h2, fun _ => rfl⟩⟩
    · exact hother j tj k u hji hj hm
  · rcases hths j1 t1 hj1 with ⟨e1, rfl⟩ | ⟨hne1, hj1⟩ <;> rcases hths j2 t2 hj2 with ⟨e2, rfl⟩ | ⟨hne2, hj2⟩
    · exact e1.trans e2.symm
    · rcases hnew k u hm1 with ho | ⟨hv, _⟩
      · exact e1.trans (h.one _ _ _ _ k u u' hi hj2 ho hm2 hdf)
      · have := hfresh _ _ k u u' hj2 hm2 hv
        rw [this.1] at hdf; rw [this.2] at hdf; cases hdf
    · rcases hnew k u' hm2 with ho | ⟨hv, _⟩
      · exact (h.one _ _ _ _ k u u' hj1 hi hm1 ho hdf).trans e2.symm
      · have := hfresh _ _ k u' u hj1 hm1 hv
        rw [this.2] at hdf; cases hdf
    · exact h.one _ _ _ _ k u u' hj1 hj2 hm1 hm2 hdf
  · rcases hths j tj hj with ⟨-, rfl⟩ | ⟨_, hj⟩
    · show (s'.lfr.map Prod.fst).count k = 1
      rcases hE with hpre | ⟨k0, u0, v0, he, h1, _⟩
      · have ho := hpre.subset hm
        have hle : (s'.lfr.map Prod.fst).count k ≤ (t.s.lfr.map Prod.fst).count k :=
          ((hpre.map Prod.fst).sublist).count_le k
        rw [h.nd i t hi k u ho hdf] at hle
        have hpos : 0 < (s'.lfr.map Prod.fst).count k := List.count_pos_iff.mpr (List.mem_map.mpr ⟨_, hm, rfl⟩)
        omega
      · rw [he, List.map_append, List.count_append]
        rw [he, List.mem_append, List.mem_singleton] at hm
        by_cases hk : k = k0
        · subst hk
          -- no old frame was on the block the step checked out
          have hu0 : u0.dtorFree = false := by
            rcases hm with hm | hm
            · have := hfresh i t k u0 u hi hm ⟨v0, h1⟩
              rw [this.2] at hdf; cases hdf
            · cases hm; exact hdf
          have h0 : (t.s.lfr.map Prod.fst).count k = 0 := by
            rw [List.count_eq_zero]
            intro hk'
            obtain ⟨⟨k', w⟩, hw, he'⟩ := List.mem_map.mp hk'
            have hw' : (k, w) ∈ t.s.lfr := by simp only at he'; rw [← he']; exact hw
            obtain ⟨e, hd⟩ := hfresh i t k u0 w hi hw' ⟨v0, h1⟩
            rw [← e, hu0] at hd; cases hd
          rw [h0]; simp
        · rcases hm with hm | hm
          · rw [h.nd i t hi k u hm hdf]; simp [Ne.symm hk]
          · cases hm; exact absurd rfl hk
    · exact h.nd j tj hj k u hm hdf

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
    (hths : ∀ (j : Nat) (tj' : Thread), C'.ths[j]? = some tj' →
      tj'.s.lfr = [] ∨ ∃ tj, C.ths[j]? = some tj ∧ tj'.s.lfr = tj.s.lfr) : LockInv C' := by
  refine ⟨fun j tj hj k u hm => ?_, fun j1 j2 t1 t2 k u u' hj1 hj2 hm1 hm2 hdf => ?_,
    fun j tj hj k u hm hdf => ?_⟩
  · rw [hb, hn]
    rcases hths j tj hj with he | ⟨tj0, hj0, he⟩
    · rw [he] at hm; cases hm
    · rw [he] at hm; exact h.out j tj0 hj0 k u hm
  · rcases hths j1 t1 hj1 with he1 | ⟨t10, h10, he1⟩
    · rw [he1] at hm1; cases hm1
    rcases hths j2 t2 hj2 with he2 | ⟨t20, h20, he2⟩
    · rw [he2] at hm2; cases hm2
    rw [he1] at hm1; rw [he2] at hm2
    exact h.one j1 j2 t10 t20 k u u' h10 h20 hm1 hm2 hdf
  · rcases hths j tj hj with he | ⟨tj0, hj0, he⟩
    · rw [he] at hm; cases hm
    · rw [he] at hm ⊢; exact h.nd j tj0 hj0 k u hm hdf

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
  refine h.of_lfr rfl rfl fun j tj hj => ?_
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
  refine h.of_lfr rfl rfl fun j tj hj => ?_
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
  refine ⟨fun j t hj k u hm => ?_, fun j _ t _ k u _ hj _ hm _ _ => ?_, fun j t hj k u hm _ => ?_⟩ <;>
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

theorem dtorFree_of_holdsDtor {t : Ty} (h : t.holdsDtor = true) : t.dtorFree = false := by
  have := Ty.holdsDtor_eq_not_free t
  rw [h] at this
  cases hd : t.dtorFree
  · rfl
  · rw [hd] at this; cases this

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

/-- **A frame's block, in a reached configuration** (Agora #808): for a
    payload that is not `dtorFree` (one that holds a destructor value,
    `holdsDtor`), the block is checked out (`⟨u, .lock, none⟩`), or gone, at
    a key below `nid`. -/
theorem reach_frame_out (hP : ProgOK P) (hPc : ProgCodes P) (hSp : SpawnOK P spawn) (hG : GlobsOK P G)
    (ht : StmtT P (fun _ => none) [] s0 Δ0) (hs : s0.src = true) (hsc : s0.codesOK P)
    (hv : ∀ v ∈ s0.vars, v < nv) {C : Cfg} (hr : Reach P spawn (Cfg.start G s0 nv) C)
    {i : Nat} {th : Thread} {K : Stmt → Stmt} {k : Nat} {u : Ty} {x : Var} {b : Stmt}
    (hi : C.ths[i]? = some th) (hK : Redex th.s K (.scopeL k u x b)) (hu : u.dtorFree = false) :
    k < C.nid ∧ (C.blk k = none ∨ C.blk k = some ⟨u, .lock, none⟩) := by
  obtain ⟨hlt, h | ⟨o, ho, hdf⟩⟩ := (reach_lockInv hP hPc hSp hG ht hs hsc hv hr).out i th hi k u (hK.lfr_mem rfl)
  · exact ⟨hlt, .inl h⟩
  · rw [hdf hu] at ho; exact ⟨hlt, .inr ho⟩

/-- **A3.2's mutual exclusion** (Agora #808): in a reached configuration, two
    frames of one block whose payload is not `dtorFree` (one that holds a
    destructor value) are one frame, of one thread: at most one check-out
    of a block is out at a time. -/
theorem reach_lock_excl (hP : ProgOK P) (hPc : ProgCodes P) (hSp : SpawnOK P spawn) (hG : GlobsOK P G)
    (ht : StmtT P (fun _ => none) [] s0 Δ0) (hs : s0.src = true) (hsc : s0.codesOK P)
    (hv : ∀ v ∈ s0.vars, v < nv) {C : Cfg} (hr : Reach P spawn (Cfg.start G s0 nv) C)
    {i j : Nat} {ti tj : Thread} {K1 K2 : Stmt → Stmt} {k : Nat} {u1 u2 : Ty} {x1 x2 : Var} {b1 b2 : Stmt}
    (hi : C.ths[i]? = some ti) (hj : C.ths[j]? = some tj)
    (h1 : Redex ti.s K1 (.scopeL k u1 x1 b1)) (h2 : Redex tj.s K2 (.scopeL k u2 x2 b2))
    (hu : u1.dtorFree = false) :
    i = j ∧ K1 = K2 ∧ u1 = u2 ∧ x1 = x2 ∧ b1 = b2 := by
  have hl := reach_lockInv hP hPc hSp hG ht hs hsc hv hr
  have hij := hl.one i j ti tj k u1 u2 hi hj (h1.lfr_mem rfl) (h2.lfr_mem rfl) hu
  subst hij
  rw [hi] at hj; cases hj
  exact ⟨rfl, Redex.frame_unique h1 h2 (hl.nd i ti hi k u1 (h1.lfr_mem rfl) hu)⟩

/-- **The check-out's end gives the value back, in a reached configuration**
    (Agora #808): `scopeL_typed_end_gives_back` with the block's state
    discharged by the invariant, given only that the block is still there:
    the frame's typing (the thread's, at the frame) names `x` an owner of a
    `u`, and the block is checked out, so every step of the frame's end is the
    give-back. -/
theorem reach_scopeL_end_gives_back (hP : ProgOK P) (hPc : ProgCodes P) (hSp : SpawnOK P spawn)
    (hG : GlobsOK P G) (ht : StmtT P (fun _ => none) [] s0 Δ0) (hs : s0.src = true) (hsc : s0.codesOK P)
    (hv : ∀ v ∈ s0.vars, v < nv) {C : Cfg} (hr : Reach P spawn (Cfg.start G s0 nv) C)
    {i : Nat} {th : Thread} {K : Stmt → Stmt} {k : Nat} {u : Ty} {x : Var}
    (hi : C.ths[i]? = some th) (hK : Redex th.s K (.scopeL k u x .skip))
    (hd : u.holdsDtor = true) (hna : u.hasArc = false) (hvf : u.holdsView = false)
    (hlive : C.blk k ≠ none) {r : Res} (h : Step P (C.view th) (.scopeL k u x .skip) r) :
    ∃ v, th.st x = some ⟨true, some v⟩ ∧
      r = .ok ({ C.view th with blk := upd C.blk k (some ⟨u, .lock, some v⟩) }.remove x) .skip := by
  obtain ⟨ps, hcp, _⟩ := (reach_inv hP hPc hSp hG ht hs hsc hv hr).1
  obtain ⟨a, ha⟩ := part_of hcp.len hi
  obtain ⟨hto, _⟩ := hcp.ok i th a hi ha
  obtain ⟨Γ, F, Δ, hth, hinv, _⟩ := hto
  obtain ⟨Γ', F', Δ', ht', hinv'⟩ := hK.typed Γ F Δ hth hinv
  obtain ⟨w, hx, hw⟩ := LockDtorWitness.scopeL_end_owns ht' hinv'.toMInv hd
  have hk : (C.view th).blk k = some ⟨u, .lock, none⟩ := by
    rcases (reach_frame_out hP hPc hSp hG ht hs hsc hv hr hi hK (dtorFree_of_holdsDtor hd)).2 with h0 | h0
    · exact absurd h0 hlive
    · exact h0
  have hno : ¬ Orphan (C.view th) := fun ho => Reach.noOrphan hr hG.noOrphan ho
  exact ⟨w, hx, LockDtorWitness.scopeL_end_gives_back (m := C.view th) hx hw hna hvf hk hno h⟩

theorem Redex.rf {s r : Stmt} {K : Stmt → Stmt} (h : Redex s K r) {m : Mem} (hrf : RF m s) : RF m r := by
  induction h with
  | here => exact hrf
  | seq _ ih => exact ih hrf
  | scope _ ih => exact ih hrf
  | rbind _ ih => exact ih hrf
  | frozen _ ih => exact ih hrf
  | catchR _ ih => exact ih hrf
  | scopeD _ ih => exact ih hrf
  | scopeL _ ih => exact ih hrf

/-- `LockDtorWitness.scopeL_typed_panic`, with the frame's invariant over a
    store of the same slots as the one the step runs on. -/
theorem scopeL_typed_panic_of {Γ Δ : Ctx} {F : List Var} {k : Nat} {t : Ty} {x : Var} {s : Stmt}
    {m mo m2 : Mem} (ht : StmtT P Γ F (.scopeL k t x s) Δ) (hi : Inv mo Γ F (.scopeL k t x s))
    (hst0 : mo.st = m.st) (hd : t.holdsDtor = true) (hna : t.hasArc = false) (hvf : t.holdsView = false)
    (h : Step P m (.scopeL k t x s) (.panic m2)) :
    ∃ m1, Step P m s (.panic m1) ∧
      ((∃ v, m1.st x = some ⟨true, some v⟩ ∧ WFv t v ∧
          (m1.blk k = some ⟨t, .lock, none⟩ →
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

/-- **A panic through the check-out gives the value back, in a reached
    configuration** (Agora #808): `scopeL_typed_panic` with the block's state
    discharged (the body's unwinding leaves the block as it was: its frame is
    the block's only one, `Step.stay`), given only that the block is still
    there: at the panic point `x` owns a `u`, given back into the block, or
    nothing, the release freeing nothing. -/
theorem reach_scopeL_panic (hP : ProgOK P) (hPc : ProgCodes P) (hSp : SpawnOK P spawn)
    (hG : GlobsOK P G) (ht : StmtT P (fun _ => none) [] s0 Δ0) (hs : s0.src = true) (hsc : s0.codesOK P)
    (hv : ∀ v ∈ s0.vars, v < nv) {C : Cfg} (hr : Reach P spawn (Cfg.start G s0 nv) C)
    {i : Nat} {th : Thread} {K : Stmt → Stmt} {k : Nat} {u : Ty} {x : Var} {b : Stmt}
    (hi : C.ths[i]? = some th) (hK : Redex th.s K (.scopeL k u x b))
    (hd : u.holdsDtor = true) (hna : u.hasArc = false) (hvf : u.holdsView = false)
    (hlive : C.blk k ≠ none) {m2 : Mem} (h : Step P (C.view th) (.scopeL k u x b) (.panic m2)) :
    ∃ m1, Step P (C.view th) b (.panic m1) ∧
      ((∃ v, m1.st x = some ⟨true, some v⟩ ∧ WFv u v ∧
          m2 = ({ m1 with blk := upd m1.blk k (some ⟨u, .lock, some v⟩) }.remove x)) ∨
        (m1.st x = some ⟨true, none⟩ ∧ m2 = m1.remove x)) := by
  have hl := reach_lockInv hP hPc hSp hG ht hs hsc hv hr
  obtain ⟨ps, hcp, _⟩ := (reach_inv hP hPc hSp hG ht hs hsc hv hr).1
  obtain ⟨a, ha⟩ := part_of hcp.len hi
  obtain ⟨hto, _⟩ := hcp.ok i th a hi ha
  have hrf : RF (C.view th) th.s := RF.congr (m := ownView C th a) (m' := C.view th) rfl rfl
    (TypedAt.of_threadOK hto).rf
  obtain ⟨Γ, F, Δ, hth, hinv, _⟩ := hto
  obtain ⟨Γ', F', Δ', ht', hinv'⟩ := hK.typed Γ F Δ hth hinv
  have hk : (C.view th).blk k = some ⟨u, .lock, none⟩ := by
    rcases (reach_frame_out hP hPc hSp hG ht hs hsc hv hr hi hK (dtorFree_of_holdsDtor hd)).2 with h0 | h0
    · exact absurd h0 hlive
    · exact h0
  obtain ⟨m1, hb, hres⟩ := scopeL_typed_panic_of (m := C.view th) ht' hinv' rfl hd hna hvf h
  -- the body's unwinding leaves the block checked out: the frame is its only one
  have hk1 : m1.blk k = some ⟨u, .lock, none⟩ := by
    have hout : Out (C.view th) k := .inr ⟨u, hk, dtorFree_of_holdsDtor hd⟩
    rcases Step.stay hb (hK.rf hrf) hout with h1 | ⟨hkb, _, _⟩
    · exact h1.trans hk
    · have h2 := hK.count_two rfl hkb
      rw [hl.nd i th hi k u (hK.lfr_mem rfl) (dtorFree_of_holdsDtor hd)] at h2
      omega
  refine ⟨m1, hb, ?_⟩
  rcases hres with ⟨v, hx, hw, hput⟩ | hnone
  · exact .inl ⟨v, hx, hw, hput hk1⟩
  · exact .inr hnone

end reach

end A3
