import A3.Rel

/-! A3.0 — a thread's step on the whole address space.

A step a thread takes on its own part of the address space (`m.alloc`) it
can take on the whole of it (`union m.alloc a2`), when the rest, `a2`,
shares no address with the thread's part and has none at or past `nid`.
Every `alloc` check the step makes still holds; what it frees is the
thread's, so `a2` loses nothing; what it allocates is fresh, so `a2` gains
nothing.  The outcome is the same, with `a2` added to its address space,
and so is the statement, but for the stores `recover` frames remember
(`GhostRel`: the lifted step's remember the larger address space). -/

namespace A3
open A2

/-- The store `m` on the whole address space: `a2` added. -/
def liftMem (a2 : Nat → Bool) (m : Mem) : Mem := { m with alloc := union m.alloc a2 }

theorem union_true {a : Nat → Bool} (a2 : Nat → Bool) {i : Nat} (h : a i = true) :
    union a a2 i = true := by
  simp [union, h]

/-- Two fresh addresses allocated: the union has both, whatever `a2` holds. -/
theorem union_alloc2 (a a2 : Nat → Bool) (n : Nat) :
    union (upd (upd a n true) (n + 1) true) a2 = upd (upd (union a a2) n true) (n + 1) true := by
  funext i
  by_cases h1 : i = n + 1
  · simp [union, upd, h1]
  · by_cases h2 : i = n
    · simp [union, upd, h2]
    · simp [union, upd, h1, h2]

/-- A node's two addresses freed, neither of them in `a2`. -/
theorem union_free2 {a a2 : Nat → Bool} {c d : Nat} (hc : a2 c = false) (hd : a2 d = false) :
    union (upd (upd a c false) d false) a2 = upd (upd (union a a2) c false) d false := by
  funext i
  by_cases h1 : i = d
  · subst h1; simp [union, upd, hd]
  · by_cases h2 : i = c
    · subst h2; simp [union, upd, h1, hc]
    · simp [union, upd, h1, h2]

/-- A buffer moved: its old address, not in `a2`, freed, and a fresh one
    allocated. -/
theorem union_realloc {a a2 : Nat → Bool} {d : Nat} (hd : a2 d = false) (n : Nat) :
    union (upd (upd a d false) n true) a2 = upd (upd (union a a2) d false) n true := by
  funext i
  by_cases h1 : i = n
  · simp [union, upd, h1]
  · by_cases h2 : i = d
    · subst h2; simp [union, upd, h1, hd]
    · simp [union, upd, h1, h2]

theorem VecOf.lift {m : Mem} {x : Var} {t : Ty} {c d : Nat} {es : List Val}
    (h : VecOf m x t c d es) (a2 : Nat → Bool) : VecOf (liftMem a2 m) x t c d es :=
  ⟨union_true a2 h.1, union_true a2 h.2.1, h.2.2⟩

theorem Eval.lift {m : Mem} {e : Expr} {n : Nat} (h : Eval m e n) (a2 : Nat → Bool) :
    Eval (liftMem a2 m) e n := by
  induction h with
  | lit => exact Eval.lit
  | var hx => exact Eval.var hx
  | add _ _ ih1 ih2 => exact Eval.add ih1 ih2
  | lt _ _ ih1 ih2 => exact Eval.lt ih1 ih2
  | len hv => exact Eval.len (VecOf.lift hv a2)
  | slen hx => exact Eval.slen hx
  | isl hx => exact Eval.isl hx
  | isr hx => exact Eval.isr hx

theorem TakeVal.lift {m m1 : Mem} {y : Var} {v : Val} (h : TakeVal m y v m1) (a2 : Nat → Bool) :
    TakeVal (liftMem a2 m) y v (liftMem a2 m1) := by
  cases h with
  | own hy => exact TakeVal.own hy
  | bor hy => exact TakeVal.bor hy

theorem EvalR.lift {m m1 : Mem} {r : Rhs} {v : Val} {o : Bool} (h : EvalR m r (.ok v o m1))
    (a2 : Nat → Bool) : EvalR (liftMem a2 m) r (.ok v o (liftMem a2 m1)) := by
  cases h with
  | expr he => exact EvalR.expr (Eval.lift he a2)
  | new =>
    show EvalR _ _ (.ok _ _
      ⟨union (upd (upd m.alloc m.nid true) (m.nid + 1) true) a2, m.nid + 2, m.nv, m.st, m.blk⟩)
    rw [union_alloc2]
    exact EvalR.new
  | moveOwn hy => exact EvalR.moveOwn hy
  | copy hy => exact EvalR.copy hy
  | borrowOwn hy => exact EvalR.borrowOwn hy
  | borrowBor hy => exact EvalR.borrowBor hy
  | «at» hn hv he => exact EvalR.at hn (VecOf.lift hv a2) (Eval.lift he a2)
  | view hv => exact EvalR.view (VecOf.lift hv a2)
  | sat hn hy he hl hd hda => exact EvalR.sat hn hy (Eval.lift he a2) hl (union_true a2 hd) hda
  | pop hy hc hd => exact EvalR.pop hy (union_true a2 hc) (union_true a2 hd)
  | pair h1 h2 => exact EvalR.pair (TakeVal.lift h1 a2) (TakeVal.lift h2 a2)
  | fst hy => exact EvalR.fst hy
  | snd hy => exact EvalR.snd hy
  | inl h1 => exact EvalR.inl (TakeVal.lift h1 a2)
  | inr h1 => exact EvalR.inr (TakeVal.lift h1 a2)
  | getl hy => exact EvalR.getl hy
  | getr hy => exact EvalR.getr hy
  | takel hy => exact EvalR.takel hy
  | taker hy => exact EvalR.taker hy
  | pack h1 => exact EvalR.pack (TakeVal.lift h1 a2)

theorem EvalR.liftP {m : Mem} {r : Rhs} (h : EvalR m r .panic) (a2 : Nat → Bool) :
    EvalR (liftMem a2 m) r .panic := by
  cases h with
  | atOOB hv he hl => exact EvalR.atOOB (VecOf.lift hv a2) (Eval.lift he a2) hl
  | satOOB hy he hl => exact EvalR.satOOB hy (Eval.lift he a2) hl
  | popEmpty hy => exact EvalR.popEmpty hy
  | getlP hy => exact EvalR.getlP hy
  | getrP hy => exact EvalR.getrP hy
  | takelP hy => exact EvalR.takelP hy
  | takerP hy => exact EvalR.takerP hy

theorem BindParams.lift {m m' : Mem} {ps : List (PMode × Ty)} {as : List Var} {base i : Nat}
    (h : BindParams m ps as base i m') (a2 : Nat → Bool) :
    BindParams (liftMem a2 m) ps as base i (liftMem a2 m') := by
  induction h with
  | nil => exact BindParams.nil
  | inp ha hl _ ih => exact BindParams.inp ha hl ih
  | sink ha _ ih => exact BindParams.sink ha ih
  | inout _ ih => exact BindParams.inout ih

theorem envMem_liftMem (a2 : Nat → Bool) (m : Mem) (env : Val) :
    envMem (liftMem a2 m) env = liftMem a2 (envMem m env) := rfl

mutual
/-- Freeing a tree of the thread's own part frees it in the whole address
    space, and `a2` keeps every address. -/
theorem Frees.lift {a a' : Nat → Bool} {T : Val} (h : Frees a T a') {a2 : Nat → Bool}
    (hd : ∀ i, a i = true → a2 i = false) : Frees (union a a2) T (union a' a2) := by
  match h with
  | .int => exact Frees.int
  | .view => exact Frees.view
  | @Frees.node _ _ _ c d _ hc hdd hl =>
    have hdc : d ≠ c := fun e => by subst e; simp [upd] at hdd
    have had : a d = true := by rw [upd_ne _ _ hdc] at hdd; exact hdd
    have hl' := FreesL.lift hl (a2 := a2) (fun i hi => hd i (by
      by_cases h1 : i = d
      · subst h1; simp [upd] at hi
      · rw [upd_ne _ _ h1] at hi
        by_cases h2 : i = c
        · subst h2; simp [upd] at hi
        · rwa [upd_ne _ _ h2] at hi))
    rw [union_free2 (hd c hc) (hd d had)] at hl'
    exact Frees.node (union_true a2 hc) (by rw [upd_ne _ _ hdc]; exact union_true a2 had) hl'
  | .pair h1 h2 =>
    exact Frees.pair (Frees.lift h1 hd) (Frees.lift h2 (fun i hi => hd i (Frees.le h1 hi)))
  | .inl h1 => exact Frees.inl (Frees.lift h1 hd)
  | .inr h1 => exact Frees.inr (Frees.lift h1 hd)
  | .pkg h1 => exact Frees.pkg (Frees.lift h1 hd)
theorem FreesL.lift {a a' : Nat → Bool} {es : List Val} (h : FreesL a es a') {a2 : Nat → Bool}
    (hd : ∀ i, a i = true → a2 i = false) : FreesL (union a a2) es (union a' a2) := by
  match h with
  | .nil => exact FreesL.nil
  | .cons h1 h2 =>
    exact FreesL.cons (Frees.lift h1 hd) (FreesL.lift h2 (fun i hi => hd i (Frees.le h1 hi)))
end

theorem DropSlot.lift {a a' : Nat → Bool} {sl : Slot} (h : DropSlot a sl a') {a2 : Nat → Bool}
    (hd : ∀ i, a i = true → a2 i = false) : DropSlot (union a a2) sl (union a' a2) := by
  cases h with
  | owned hf => exact DropSlot.owned (Frees.lift hf hd)
  | moved => exact DropSlot.moved
  | borrowed => exact DropSlot.borrowed

/-- `a2` shares no address with a store a step reached: what that store has
    live was live before, or is fresh. -/
theorem Grows.disj {m m1 : Mem} (hg : Grows m m1) {a2 : Nat → Bool}
    (hd : ∀ i, m.alloc i = true → a2 i = false) (hf : FreshFrom a2 m.nid) :
    ∀ i, m1.alloc i = true → a2 i = false := by
  intro i hi
  rcases hg.fresh i hi with h | h
  · exact hd i h
  · exact hf i h

/-- What a step on the thread's part is on the whole address space: the
    same outcome, its store with `a2` added, and for an `ok` step a
    statement equal but for the stores of `recover` frames. -/
def Lifts (P : Prog) (a2 : Nat → Bool) (m : Mem) (s : Stmt) : Res → Prop
  | .ok m' s' => ∃ s'', GhostRel s' s'' ∧ Step P (liftMem a2 m) s (.ok (liftMem a2 m') s'')
  | .panic m' => Step P (liftMem a2 m) s (.panic (liftMem a2 m'))

theorem Step.lifts {P : Prog} {m : Mem} {s : Stmt} {r : Res} (h : Step P m s r) {a2 : Nat → Bool}
    (hd : ∀ i, m.alloc i = true → a2 i = false) (hf : FreshFrom a2 m.nid) : Lifts P a2 m s r := by
  induction h with
  | seqSkip => exact ⟨_, GhostRel.refl _, Step.seqSkip⟩
  | seqL _ ih =>
    obtain ⟨s'', hg, hs⟩ := ih
    exact ⟨_, GhostRel.seq _ hg, Step.seqL hs⟩
  | seqP _ ih => exact Step.seqP ih
  | letv hx he =>
    exact ⟨_, GhostRel.refl _, Step.letv (m := liftMem a2 m) hx (EvalR.lift he a2)⟩
  | letvP he => exact Step.letvP (EvalR.liftP he a2)
  | letcall hfn hx hb =>
    exact ⟨_, GhostRel.refl _, Step.letcall (m := liftMem a2 m) hfn hx (BindParams.lift hb a2)⟩
  | scopeSkip hx hdr =>
    exact ⟨_, GhostRel.refl _, Step.scopeSkip (m := liftMem a2 m) hx (DropSlot.lift hdr hd)⟩
  | scopeIn _ ih =>
    obtain ⟨s'', hg, hs⟩ := ih
    exact ⟨_, GhostRel.scope _ hg, Step.scopeIn hs⟩
  | @scopeP m1 _ _ _ _ hs hx hdr ih =>
    exact Step.scopeP (m1 := liftMem a2 m1) ih hx (DropSlot.lift hdr ((Step.grows hs).disj hd hf))
  | rbindSkip hp => exact ⟨_, GhostRel.refl _, Step.rbindSkip (m := liftMem a2 m) hp⟩
  | rbindIn _ ih =>
    obtain ⟨s'', hg, hs⟩ := ih
    exact ⟨_, GhostRel.rbind _ hg, Step.rbindIn hs⟩
  | @rbindP m1 _ _ _ _ hp ih => exact Step.rbindP (m1 := liftMem a2 m1) ih hp
  | frozenSkip => exact ⟨_, GhostRel.refl _, Step.frozenSkip⟩
  | frozenIn _ ih =>
    obtain ⟨s'', hg, hs⟩ := ih
    exact ⟨_, GhostRel.frozen _ hg, Step.frozenIn hs⟩
  | frozenP _ ih => exact Step.frozenP ih
  | @assign m1 _ _ _ _ _ _ hx he hx1 hdr =>
    exact ⟨_, GhostRel.refl _, Step.assign (m := liftMem a2 m) (m1 := liftMem a2 m1) hx
      (EvalR.lift he a2) hx1 (DropSlot.lift hdr ((EvalR.grows he).disj hd hf))⟩
  | assignP he => exact Step.assignP (EvalR.liftP he a2)
  | iteT he hn => exact ⟨_, GhostRel.refl _, Step.iteT (Eval.lift he a2) hn⟩
  | iteF he => exact ⟨_, GhostRel.refl _, Step.iteF (Eval.lift he a2)⟩
  | «while» => exact ⟨_, GhostRel.refl _, Step.while⟩
  | push ht hx hc hdd =>
    exact ⟨_, GhostRel.refl _,
      Step.push (TakeVal.lift ht a2) hx (union_true a2 hc) (union_true a2 hdd)⟩
  | @pushRealloc m1 x _ v t c d es ht hx hc hdd =>
    have had : a2 d = false := hd d (by rw [← TakeVal.alloc ht]; exact hdd)
    refine ⟨_, GhostRel.refl _, ?_⟩
    show Step P _ _ (.ok (Mem.set ⟨union (upd (upd m1.alloc d false) m1.nid true) a2, m1.nid + 1,
      m1.nv, m1.st, m1.blk⟩ x ⟨true, some (.node t c m1.nid (es ++ [v]))⟩) .skip)
    rw [union_realloc had]
    exact Step.pushRealloc (m1 := liftMem a2 m1) (TakeVal.lift ht a2) hx (union_true a2 hc)
      (union_true a2 hdd)
  | free hx hfr =>
    exact ⟨_, GhostRel.refl _, Step.free (m := liftMem a2 m) hx (Frees.lift hfr hd)⟩
  | panic => exact Step.panic
  | letrec hfn hp hx =>
    refine ⟨_, GhostRel.scope _ (GhostRel.seq _ (GhostRel.catchR _ ?_ ?_ ?_ ?_ (GhostRel.refl _))),
      Step.letrec (m := liftMem a2 m) hfn hp hx⟩
    · rfl
    · rfl
    · rfl
    · exact fun _ h => union_true a2 h
  | catchIn _ ih =>
    obtain ⟨s'', hg, hs⟩ := ih
    exact ⟨_, GhostRel.catchR _ rfl rfl rfl (fun _ h => h) hg, Step.catchIn hs⟩
  | catchSkip => exact ⟨_, GhostRel.refl _, Step.catchSkip⟩
  | unpair hy hx hz hne =>
    exact ⟨_, GhostRel.refl _, Step.unpair (m := liftMem a2 m) hy hx hz hne⟩
  | callc hc hj hfn hx hb =>
    exact ⟨_, GhostRel.refl _, Step.callc (m := liftMem a2 m) hc hj hfn hx (BindParams.lift hb a2)⟩
  | @catchP m1 _ _ _ _ hx ih =>
    exact ⟨_, GhostRel.refl _, Step.catchP (m1 := liftMem a2 m1) ih hx⟩
  | letd hx he =>
    exact ⟨_, GhostRel.refl _, Step.letd (m := liftMem a2 m) hx (EvalR.lift he a2)⟩
  | letdP he => exact Step.letdP (EvalR.liftP he a2)
  | scopeDIn _ ih =>
    obtain ⟨s'', hg, hs⟩ := ih
    exact ⟨_, GhostRel.scopeD _ _ hg, Step.scopeDIn hs⟩
  | scopeDEnd hx => exact ⟨_, GhostRel.refl _, Step.scopeDEnd (m := liftMem a2 m) hx⟩
  | scopeDMoved hx => exact ⟨_, GhostRel.refl _, Step.scopeDMoved (m := liftMem a2 m) hx⟩
  | @scopeDP m1 _ _ _ _ _ hx ih =>
    exact ⟨_, GhostRel.refl _, Step.scopeDP (m1 := liftMem a2 m1) ih hx⟩
  | @scopeDPMoved m1 _ _ _ _ hx ih => exact Step.scopeDPMoved (m1 := liftMem a2 m1) ih hx

/-- A step to a configuration, lifted: its store with `a2` added, its
    statement equal but for the stores of `recover` frames. -/
theorem Step.liftOk {P : Prog} {m m' : Mem} {s s' : Stmt} (h : Step P m s (.ok m' s'))
    {a2 : Nat → Bool} (hd : ∀ i, m.alloc i = true → a2 i = false) (hf : FreshFrom a2 m.nid) :
    ∃ s'', GhostRel s' s'' ∧
      Step P { m with alloc := union m.alloc a2 } s (.ok { m' with alloc := union m'.alloc a2 } s'') :=
  Step.lifts h hd hf

/-- A panic, lifted: the store it unwound to, with `a2` added. -/
theorem Step.liftPanic {P : Prog} {m m' : Mem} {s : Stmt} (h : Step P m s (.panic m'))
    {a2 : Nat → Bool} (hd : ∀ i, m.alloc i = true → a2 i = false) (hf : FreshFrom a2 m.nid) :
    Step P { m with alloc := union m.alloc a2 } s (.panic { m' with alloc := union m'.alloc a2 }) :=
  Step.lifts h hd hf

/-- **The upward frame lemma**: a step a thread takes on its own part of the
    address space it can take on the whole of it. -/
theorem Step.lift {P : Prog} {m : Mem} {s : Stmt} {r : Res} (h : Step P m s r) {a2 : Nat → Bool}
    (hd : ∀ i, m.alloc i = true → a2 i = false) (hf : FreshFrom a2 m.nid) :
    ∃ r', Step P { m with alloc := union m.alloc a2 } s r' := by
  cases r with
  | ok m' s' =>
    obtain ⟨_, _, hs⟩ := Step.liftOk h hd hf
    exact ⟨_, hs⟩
  | panic m' => exact ⟨_, Step.liftPanic h hd hf⟩

end A3
