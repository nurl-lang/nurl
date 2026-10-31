import A3.Owned

/-! A3.0 — the downward frame lemma: a step on the shared address space is
a step on the thread's own part of it.

Every check A2's step makes on `alloc` is on an address of a tree an owned
slot holds: `VecOf` is a binding's own node or a node `NodeAt` finds in an
owned tree, `DataAt` searches owned trees, `pop` and `push` read the
binding's own node, and a drop or a `free` releases an owned tree.  A part
those trees avoid (`Avoids`) holds none of these addresses, so taking it
out of `alloc` changes no check.  The addresses a step allocates are past
every address of the part (`FreshFrom`), so allocating commutes with taking
it out.  The result is the full step's without the part: the same bindings,
`nid` and `nv`, and the same statement but for the one store a step keeps,
a `recover` frame's (`Step.letrec`), which remembers the smaller address
space (`GhostRel`). -/

namespace A3
open A2

/-! ### The address space without a part -/

theorem minus_true {a a2 : Nat → Bool} {i : Nat} (h : a i = true) (h2 : a2 i = false) :
    minus a a2 i = true := by
  simp [minus, h, h2]

theorem of_minus_true {a a2 : Nat → Bool} {i : Nat} (h : minus a a2 i = true) : a i = true := by
  simp only [minus, Bool.and_eq_true] at h
  exact h.1

/-- Freeing an address commutes with taking a part out. -/
theorem minus_upd_false (a a2 : Nat → Bool) (k : Nat) :
    minus (upd a k false) a2 = upd (minus a a2) k false := by
  funext i
  by_cases hi : i = k
  · subst hi; simp [minus, upd]
  · simp [minus, upd, hi]

/-- Allocating an address outside the part commutes with taking it out. -/
theorem minus_upd_true {a a2 : Nat → Bool} {k : Nat} (hk : a2 k = false) :
    minus (upd a k true) a2 = upd (minus a a2) k true := by
  funext i
  by_cases hi : i = k
  · subst hi; simp [minus, upd, hk]
  · simp [minus, upd, hi]

/-! ### Each part of a step -/

/-- The vector a binding names is in an owned tree: both of its addresses
    are live on the own part. -/
theorem VecOf.restrict {m : Mem} {x : Var} {t : Ty} {c d : Nat} {es : List Val}
    (h : VecOf m x t c d es) {a2 : Nat → Bool} (hav : Avoids m a2) :
    VecOf { m with alloc := minus m.alloc a2 } x t c d es := by
  obtain ⟨hc, hd, hx⟩ := h
  have ho : OwnedId m c ∧ OwnedId m d := by
    rcases hx with hx | ⟨_, y, u, hy, hs, _⟩
    · exact ⟨OwnedId.of_slot hx (by simp), OwnedId.of_slot hx (by simp)⟩
    · exact ⟨OwnedId.of_slot hy (hs.ids c (by simp)), OwnedId.of_slot hy (hs.ids d (by simp))⟩
  exact ⟨minus_true hc (hav c ho.1), minus_true hd (hav d ho.2), hx⟩

theorem Eval.restrict {m : Mem} {e : Expr} {n : Nat} (h : Eval m e n) {a2 : Nat → Bool}
    (hav : Avoids m a2) : Eval { m with alloc := minus m.alloc a2 } e n := by
  induction h with
  | lit => exact .lit
  | var hx => exact .var hx
  | add _ _ ih1 ih2 => exact .add ih1 ih2
  | lt _ _ ih1 ih2 => exact .lt ih1 ih2
  | len hv => exact .len (VecOf.restrict hv hav)
  | slen hx => exact .slen hx
  | isl hx => exact .isl hx
  | isr hx => exact .isr hx

theorem TakeVal.restrict {m m1 : Mem} {y : Var} {v : Val} (h : TakeVal m y v m1) (a2 : Nat → Bool) :
    TakeVal { m with alloc := minus m.alloc a2 } y v { m1 with alloc := minus m1.alloc a2 } := by
  cases h with
  | own hy => exact .own hy
  | bor hy => exact .bor hy

/-- `r1` is the evaluation `r` on the thread's own part: the same outcome,
    value and ownership, and the store without the addresses of `a2`. -/
def RResDown (a2 : Nat → Bool) : RRes → RRes → Prop
  | .ok v o m, .ok v1 o1 m1 => v1 = v ∧ o1 = o ∧ m1 = { m with alloc := minus m.alloc a2 }
  | .panic, .panic => True
  | _, _ => False

/-- **Evaluating a right-hand side** on the own part: every address it
    checks is owned, and `new` allocates past the part. -/
theorem EvalR.restrict {m : Mem} {r : Rhs} {res : RRes} (h : EvalR m r res) {a2 : Nat → Bool}
    (hav : Avoids m a2) (hf : FreshFrom a2 m.nid) :
    ∃ res1, EvalR { m with alloc := minus m.alloc a2 } r res1 ∧ RResDown a2 res res1 := by
  cases h with
  | expr he => exact ⟨_, .expr (Eval.restrict he hav), rfl, rfl, rfl⟩
  | @new t =>
    have h1 : EvalR { m with alloc := minus m.alloc a2 } (.new t)
        (.ok (.node t m.nid (m.nid + 1) []) true
          { m with alloc := upd (upd (minus m.alloc a2) m.nid true) (m.nid + 1) true,
                   nid := m.nid + 2 }) := .new
    rw [← minus_upd_true (hf m.nid (Nat.le_refl _)), ← minus_upd_true (hf (m.nid + 1) (by omega))]
      at h1
    exact ⟨_, h1, rfl, rfl, rfl⟩
  | moveOwn hy => exact ⟨_, .moveOwn hy, rfl, rfl, rfl⟩
  | copy hy => exact ⟨_, .copy hy, rfl, rfl, rfl⟩
  | borrowOwn hy => exact ⟨_, .borrowOwn hy, rfl, rfl, rfl⟩
  | borrowBor hy => exact ⟨_, .borrowBor hy, rfl, rfl, rfl⟩
  | «at» hn hv he => exact ⟨_, .at hn (VecOf.restrict hv hav) (Eval.restrict he hav), rfl, rfl, rfl⟩
  | atOOB hv he hn => exact ⟨_, .atOOB (VecOf.restrict hv hav) (Eval.restrict he hav) hn, trivial⟩
  | view hv => exact ⟨_, .view (VecOf.restrict hv hav), rfl, rfl, rfl⟩
  | @sat y i t d o l n c es hn hy he hl hd hda =>
    have ho : OwnedId m d := by
      obtain ⟨x, u, hx, hs, _⟩ := hda
      exact OwnedId.of_slot hx (hs.ids d (by simp))
    exact ⟨_, .sat hn hy (Eval.restrict he hav) hl (minus_true hd (hav d ho)) hda, rfl, rfl, rfl⟩
  | satOOB hy he hn => exact ⟨_, .satOOB hy (Eval.restrict he hav) hn, trivial⟩
  | pop hy hc hd =>
    exact ⟨_, .pop hy (minus_true hc (hav _ (OwnedId.of_slot hy (by simp))))
      (minus_true hd (hav _ (OwnedId.of_slot hy (by simp)))), rfl, rfl, rfl⟩
  | popEmpty hy => exact ⟨_, .popEmpty hy, trivial⟩
  | pair h1 h2 => exact ⟨_, .pair (TakeVal.restrict h1 a2) (TakeVal.restrict h2 a2), rfl, rfl, rfl⟩
  | fst hy => exact ⟨_, .fst hy, rfl, rfl, rfl⟩
  | snd hy => exact ⟨_, .snd hy, rfl, rfl, rfl⟩
  | inl h1 => exact ⟨_, .inl (TakeVal.restrict h1 a2), rfl, rfl, rfl⟩
  | inr h1 => exact ⟨_, .inr (TakeVal.restrict h1 a2), rfl, rfl, rfl⟩
  | getl hy => exact ⟨_, .getl hy, rfl, rfl, rfl⟩
  | getlP hy => exact ⟨_, .getlP hy, trivial⟩
  | getr hy => exact ⟨_, .getr hy, rfl, rfl, rfl⟩
  | getrP hy => exact ⟨_, .getrP hy, trivial⟩
  | takel hy => exact ⟨_, .takel hy, rfl, rfl, rfl⟩
  | takelP hy => exact ⟨_, .takelP hy, trivial⟩
  | taker hy => exact ⟨_, .taker hy, rfl, rfl, rfl⟩
  | takerP hy => exact ⟨_, .takerP hy, trivial⟩
  | pack h1 => exact ⟨_, .pack (TakeVal.restrict h1 a2), rfl, rfl, rfl⟩

theorem EvalR.restrict_ok {m m1 : Mem} {r : Rhs} {v : Val} {o : Bool} (h : EvalR m r (.ok v o m1))
    {a2 : Nat → Bool} (hav : Avoids m a2) (hf : FreshFrom a2 m.nid) :
    EvalR { m with alloc := minus m.alloc a2 } r (.ok v o { m1 with alloc := minus m1.alloc a2 }) := by
  obtain ⟨res1, h1, hd⟩ := EvalR.restrict h hav hf
  cases res1 with
  | ok v1 o1 m2 => obtain ⟨rfl, rfl, rfl⟩ := hd; exact h1
  | panic => exact (hd : False).elim

theorem EvalR.restrict_panic {m : Mem} {r : Rhs} (h : EvalR m r .panic) {a2 : Nat → Bool}
    (hav : Avoids m a2) (hf : FreshFrom a2 m.nid) :
    EvalR { m with alloc := minus m.alloc a2 } r .panic := by
  obtain ⟨res1, h1, hd⟩ := EvalR.restrict h hav hf
  cases res1 with
  | ok _ _ _ => exact (hd : False).elim
  | panic => exact h1

/-- Binding parameters reads and writes bindings only. -/
theorem BindParams.restrict {m m' : Mem} {ps : List (PMode × Ty)} {as : List Var} {base i : Nat}
    (h : BindParams m ps as base i m') (a2 : Nat → Bool) :
    BindParams { m with alloc := minus m.alloc a2 } ps as base i
      { m' with alloc := minus m'.alloc a2 } := by
  induction h with
  | nil => exact .nil
  | inp ha hl _ ih => exact .inp ha hl ih
  | sink ha _ ih => exact .sink ha ih
  | inout _ ih => exact .inout ih

mutual
/-- Freeing a tree none of whose addresses is in the part frees it on the
    own part. -/
theorem Frees.restrict {a a' : Nat → Bool} {T : Val} (h : Frees a T a') {a2 : Nat → Bool}
    (hT : ∀ i ∈ T.ids, a2 i = false) : Frees (minus a a2) T (minus a' a2) := by
  match h with
  | .int => exact .int
  | .view => exact .view
  | @Frees.node _ _ _ c d _ hc hd hl =>
    have hdc : d ≠ c := by
      intro e; subst e; simp [upd] at hd
    refine .node (minus_true hc (hT c (by simp))) ?_ ?_
    · rw [upd_ne _ _ hdc] at hd ⊢
      exact minus_true hd (hT d (by simp))
    · have h1 := FreesL.restrict hl (a2 := a2) fun i hi => hT i (by simp [hi])
      rwa [minus_upd_false, minus_upd_false] at h1
  | .pair h1 h2 =>
    exact .pair (Frees.restrict h1 fun i hi => hT i (by simp [hi]))
      (Frees.restrict h2 fun i hi => hT i (by simp [hi]))
  | .inl h1 => exact .inl (Frees.restrict h1 fun i hi => hT i (by simpa using hi))
  | .inr h1 => exact .inr (Frees.restrict h1 fun i hi => hT i (by simpa using hi))
  | .pkg h1 => exact .pkg (Frees.restrict h1 fun i hi => hT i (by simpa using hi))
theorem FreesL.restrict {a a' : Nat → Bool} {es : List Val} (h : FreesL a es a') {a2 : Nat → Bool}
    (hT : ∀ i ∈ idsL es, a2 i = false) : FreesL (minus a a2) es (minus a' a2) := by
  match h with
  | .nil => exact .nil
  | .cons h1 h2 =>
    exact .cons (Frees.restrict h1 fun i hi => hT i (by simp [hi]))
      (FreesL.restrict h2 fun i hi => hT i (by simp [hi]))
end

/-- Dropping a slot of `m`, on the own part: an owned slot's tree is one of
    `m`'s owned trees. -/
theorem DropSlot.restrict {m : Mem} {x : Var} {sl : Slot} {a' : Nat → Bool} (hx : m.st x = some sl)
    (h : DropSlot m.alloc sl a') {a2 : Nat → Bool} (hav : Avoids m a2) :
    DropSlot (minus m.alloc a2) sl (minus a' a2) := by
  cases h with
  | owned hf => exact .owned (Frees.restrict hf fun i hi => hav i (OwnedId.of_slot hx hi))
  | moved => exact .moved
  | borrowed => exact .borrowed

theorem ResDown.ok_inv {a2 : Nat → Bool} {m : Mem} {s : Stmt} {r1 : Res}
    (h : ResDown a2 (.ok m s) r1) :
    ∃ s1, r1 = .ok { m with alloc := minus m.alloc a2 } s1 ∧ GhostRel s1 s := by
  cases r1 with
  | ok m1 s1 => obtain ⟨rfl, hg⟩ := h; exact ⟨s1, rfl, hg⟩
  | panic _ => exact (h : False).elim

theorem ResDown.panic_inv {a2 : Nat → Bool} {m : Mem} {r1 : Res} (h : ResDown a2 (.panic m) r1) :
    r1 = .panic { m with alloc := minus m.alloc a2 } := by
  cases r1 with
  | ok _ _ => exact (h : False).elim
  | panic m1 => exact congrArg Res.panic h

/-! ### A step -/

/-- **The downward frame lemma**: take out of the address space a part that
    the store's owned trees avoid and that holds no fresh address, and a
    step is still a step, to the same result without the part. -/
theorem Step.restrict {P : Prog} {m : Mem} {s : Stmt} {r : Res} (h : Step P m s r) {a2 : Nat → Bool}
    (hav : Avoids m a2) (hb : BorFree m) (hf : FreshFrom a2 m.nid) :
    ∃ r1, Step P { m with alloc := minus m.alloc a2 } s r1 ∧ ResDown a2 r r1 := by
  induction h with
  | seqSkip => exact ⟨_, .seqSkip, rfl, .refl _⟩
  | seqL _ ih =>
    obtain ⟨r1, h1, hd⟩ := ih
    obtain ⟨s1, rfl, hg⟩ := ResDown.ok_inv hd
    exact ⟨_, .seqL h1, rfl, .seq _ hg⟩
  | seqP _ ih =>
    obtain ⟨r1, h1, hd⟩ := ih
    obtain rfl := ResDown.panic_inv hd
    exact ⟨_, .seqP h1, rfl⟩
  | letv hx he => exact ⟨_, .letv hx (EvalR.restrict_ok he hav hf), rfl, .refl _⟩
  | letvP he => exact ⟨_, .letvP (EvalR.restrict_panic he hav hf), rfl⟩
  | letcall hP hx hbp => exact ⟨_, .letcall hP hx (BindParams.restrict hbp a2), rfl, .refl _⟩
  | scopeSkip hx hd => exact ⟨_, .scopeSkip hx (DropSlot.restrict hx hd hav), rfl, .refl _⟩
  | scopeIn _ ih =>
    obtain ⟨r1, h1, hd⟩ := ih
    obtain ⟨s1, rfl, hg⟩ := ResDown.ok_inv hd
    exact ⟨_, .scopeIn h1, rfl, .scope _ hg⟩
  | scopeP hs hx hd ih =>
    obtain ⟨r1, h1, hd'⟩ := ih
    obtain rfl := ResDown.panic_inv hd'
    exact ⟨_, .scopeP h1 hx (DropSlot.restrict hx hd (Step.avoids hs hb hav hf)), rfl⟩
  | rbindSkip hp => exact ⟨_, .rbindSkip hp, rfl, .refl _⟩
  | rbindIn _ ih =>
    obtain ⟨r1, h1, hd⟩ := ih
    obtain ⟨s1, rfl, hg⟩ := ResDown.ok_inv hd
    exact ⟨_, .rbindIn h1, rfl, .rbind _ hg⟩
  | rbindP _ hp ih =>
    obtain ⟨r1, h1, hd⟩ := ih
    obtain rfl := ResDown.panic_inv hd
    exact ⟨_, .rbindP h1 hp, rfl⟩
  | frozenSkip => exact ⟨_, .frozenSkip, rfl, .refl _⟩
  | frozenIn _ ih =>
    obtain ⟨r1, h1, hd⟩ := ih
    obtain ⟨s1, rfl, hg⟩ := ResDown.ok_inv hd
    exact ⟨_, .frozenIn h1, rfl, .frozen _ hg⟩
  | frozenP _ ih =>
    obtain ⟨r1, h1, hd⟩ := ih
    obtain rfl := ResDown.panic_inv hd
    exact ⟨_, .frozenP h1, rfl⟩
  | assign hx he hx1 hd =>
    exact ⟨_, .assign hx (EvalR.restrict_ok he hav hf) hx1
      (DropSlot.restrict hx1 hd (EvalR.avoids he hb hav hf).1), rfl, .refl _⟩
  | assignP he => exact ⟨_, .assignP (EvalR.restrict_panic he hav hf), rfl⟩
  | iteT he hn => exact ⟨_, .iteT (Eval.restrict he hav) hn, rfl, .refl _⟩
  | iteF he => exact ⟨_, .iteF (Eval.restrict he hav), rfl, .refl _⟩
  | «while» => exact ⟨_, .while, rfl, .refl _⟩
  | push ht hx hc hd =>
    have hav1 := (TakeVal.avoids ht hb hav).1
    exact ⟨_, .push (TakeVal.restrict ht a2) hx (minus_true hc (hav1 _ (OwnedId.of_slot hx (by simp))))
      (minus_true hd (hav1 _ (OwnedId.of_slot hx (by simp)))), rfl, .refl _⟩
  | @pushRealloc m1 x y v t c d es ht hx hc hd =>
    have hav1 := (TakeVal.avoids ht hb hav).1
    have h1 : Step P { m with alloc := minus m.alloc a2 } (.push x y)
        (.ok ({ m1 with alloc := upd (upd (minus m1.alloc a2) d false) m1.nid true,
                        nid := m1.nid + 1 }.set x ⟨true, some (.node t c m1.nid (es ++ [v]))⟩) .skip) :=
      .pushRealloc (TakeVal.restrict ht a2) hx (minus_true hc (hav1 _ (OwnedId.of_slot hx (by simp))))
        (minus_true hd (hav1 _ (OwnedId.of_slot hx (by simp))))
    rw [← minus_upd_false m1.alloc a2 d, ← minus_upd_true (hf m1.nid (TakeVal.grows ht).nid)] at h1
    exact ⟨_, h1, rfl, .refl _⟩
  | free hx hfr =>
    exact ⟨_, .free hx (Frees.restrict hfr fun i hi => hav i (OwnedId.of_slot hx hi)), rfl, .refl _⟩
  | panic => exact ⟨_, .panic, rfl⟩
  | letrec hP hps hx =>
    exact ⟨_, .letrec hP hps hx, rfl,
      .scope _ (.seq _ (.catchR _ rfl rfl rfl (fun _ hi => of_minus_true hi) (.refl _)))⟩
  | catchIn _ ih =>
    obtain ⟨r1, h1, hd⟩ := ih
    obtain ⟨s1, rfl, hg⟩ := ResDown.ok_inv hd
    exact ⟨_, .catchIn h1, rfl, .catchR _ rfl rfl rfl (fun _ hi => hi) hg⟩
  | catchSkip => exact ⟨_, .catchSkip, rfl, .refl _⟩
  | unpair hy hx hz hxz => exact ⟨_, .unpair hy hx hz hxz, rfl, .refl _⟩
  | callc hc hj hP hx hbp =>
    exact ⟨_, .callc hc hj hP hx (BindParams.restrict hbp a2), rfl, .refl _⟩
  | catchP _ hx ih =>
    obtain ⟨r1, h1, hd⟩ := ih
    obtain rfl := ResDown.panic_inv hd
    exact ⟨_, .catchP h1 hx, rfl, .refl _⟩
  | letd hx he => exact ⟨_, .letd hx (EvalR.restrict_ok he hav hf), rfl, .refl _⟩
  | letdP he => exact ⟨_, .letdP (EvalR.restrict_panic he hav hf), rfl⟩
  | scopeDIn _ ih =>
    obtain ⟨r1, h1, hd⟩ := ih
    obtain ⟨s1, rfl, hg⟩ := ResDown.ok_inv hd
    exact ⟨_, .scopeDIn h1, rfl, .scopeD _ _ hg⟩
  | scopeDEnd hx => exact ⟨_, .scopeDEnd hx, rfl, .refl _⟩
  | scopeDMoved hx => exact ⟨_, .scopeDMoved hx, rfl, .refl _⟩
  | scopeDP _ hx ih =>
    obtain ⟨r1, h1, hd⟩ := ih
    obtain rfl := ResDown.panic_inv hd
    exact ⟨_, .scopeDP h1 hx, rfl, .refl _⟩
  | scopeDPMoved _ hx ih =>
    obtain ⟨r1, h1, hd⟩ := ih
    obtain rfl := ResDown.panic_inv hd
    exact ⟨_, .scopeDPMoved h1 hx, rfl⟩

end A3
