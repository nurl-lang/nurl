import C.Cert

/-!
# C14: completions of a program with assumed functions (AGORA-1015)

A certificate for a program whose translation leaves some functions out
(docs/dev/CONDITIONAL_CERTIFICATES.md). `P` holds, at each index of `A`, a
*stub*: the function's signature, with a body `.seq s .panic` whose calls
and `hasThru` are the real body's. `Completes A P P'` says `P'` is a program
that agrees with `P` everywhere but in the bodies at `A`, and whose bodies
there have the same callees and the same `hasThru`.

This file proves that `ThruFn` (A2/Typing.lean) is the same over `P` and any
completion: the only body facts it reads are the ones a completion keeps.
-/

namespace C

open A2

/-- A function's signature: everything but its body and its slot count. -/
def _root_.A2.Fn.sig (f : Fn) : Fn := { f with body := .skip, nvars := 0 }

/-- Two functions with one signature. -/
def SameSig (f f' : Fn) : Prop := f.sig = f'.sig

theorem SameSig.params {f f' : Fn} (h : SameSig f f') : f.params = f'.params :=
  by have := congrArg Fn.params (show f.sig = f'.sig from h); exact this
theorem SameSig.resTy {f f' : Fn} (h : SameSig f f') : f.resTy = f'.resTy :=
  by have := congrArg Fn.resTy (show f.sig = f'.sig from h); exact this
theorem SameSig.resOwn {f f' : Fn} (h : SameSig f f') : f.resOwn = f'.resOwn :=
  by have := congrArg Fn.resOwn (show f.sig = f'.sig from h); exact this
theorem SameSig.lends {f f' : Fn} (h : SameSig f f') : f.lends = f'.lends :=
  by have := congrArg Fn.lends (show f.sig = f'.sig from h); exact this
theorem SameSig.rholds {f f' : Fn} (h : SameSig f f') : f.rholds = f'.rholds :=
  by have := congrArg Fn.rholds (show f.sig = f'.sig from h); exact this
theorem SameSig.outHolds {f f' : Fn} (h : SameSig f f') : f.outHolds = f'.outHolds :=
  by have := congrArg Fn.outHolds (show f.sig = f'.sig from h); exact this

/-- A function of `fn` that reads only its signature takes the same value
    at a function of the same signature. -/
theorem SameSig.eq_with {f f' : Fn} (h : SameSig f f') : f' = { f with body := f'.body, nvars := f'.nvars } := by
  cases f; cases f'
  simp only [SameSig, Fn.sig, Fn.mk.injEq] at h
  obtain ⟨h1, h2, h3, h4, h5, h6, -, -⟩ := h
  subst h1 h2 h3 h4 h5 h6; rfl

theorem callRes_sig {Γ : Ctx} {f f' : Fn} {args : List Var} (h : SameSig f f') :
    callRes Γ f' args = callRes Γ f args := by
  rw [h.eq_with]; cases f; rfl

theorem outHeld_congr {Γ : Ctx} {f f' : Fn} {args : List Var} {i : Nat} (h : f.outHolds = f'.outHolds) :
    outHeld Γ f args i = outHeld Γ f' args i := by
  simp only [outHeld, h]

theorem callPostAux_congr {Γ0 : Ctx} {f f' : Fn} {args : List Var} (h : f.outHolds = f'.outHolds) :
    ∀ (ps : List (PMode × Ty)) (as : List Var) (i : Nat) (Γ : Ctx),
      callPostAux Γ0 f args ps as i Γ = callPostAux Γ0 f' args ps as i Γ := by
  intro ps
  induction ps with
  | nil => intro as i Γ; cases as <;> simp [callPostAux]
  | cons p ps ih =>
    intro as i Γ
    obtain ⟨m, t⟩ := p
    cases as with
    | nil => cases m <;> simp [callPostAux]
    | cons a as =>
      cases m with
      | sink => simp only [callPostAux]; exact ih _ _ _
      | inout b => simp only [callPostAux, outHeld_congr (Γ := Γ0) (args := args) (i := i) h]; exact ih _ _ _
      | inp => simp only [callPostAux]; exact ih _ _ _

theorem callPost_sig {Γ : Ctx} {f f' : Fn} {args : List Var} (h : SameSig f f') :
    callPost Γ f' args = callPost Γ f args := by
  simp only [callPost, h.params, callPostAux_congr (Γ0 := Γ) (args := args) h.outHolds.symm]

/-- The facts about a body that other functions' typing reads: whom it
    calls, and whether it changes elements through a borrow itself. -/
def SameCalls (s s' : Stmt) : Prop :=
  (∀ g, g ∈ s.calls ↔ g ∈ s'.calls) ∧ s.hasThru = s'.hasThru

/-- `P'` completes `P` at the assumed indices `A`. -/
structure Completes (A : List Nat) (P P' : Prog) : Prop where
  len : P'.length = P.length
  keep : ∀ i, i ∉ A → P'[i]? = P[i]?
  stub : ∀ i ∈ A, ∃ f f', P[i]? = some f ∧ P'[i]? = some f' ∧ SameSig f f' ∧
    SameCalls f.body f'.body ∧ ∃ s, f.body = .seq s .panic

/-- At every index, the two programs hold functions with the same callees
    and the same `hasThru` (or neither holds one). -/
theorem Completes.calls_at {A : List Nat} {P P' : Prog} (hc : Completes A P P') (i : Nat) :
    (P[i]? = none ∧ P'[i]? = none) ∨
      ∃ f f', P[i]? = some f ∧ P'[i]? = some f' ∧ SameCalls f.body f'.body := by
  by_cases hA : i ∈ A
  · obtain ⟨f, f', hf, hf', _, hs, _⟩ := hc.stub i hA
    exact Or.inr ⟨f, f', hf, hf', hs⟩
  · have hk := hc.keep i hA
    cases h : P[i]? with
    | none => exact Or.inl ⟨rfl, by rw [hk, h]⟩
    | some f =>
      exact Or.inr ⟨f, f, rfl, by rw [hk, h], fun _ => Iff.rfl, rfl⟩

/-- `ThruFn` carries over from `P` to a completion. -/
theorem ThruFn.complete {A : List Nat} {P P' : Prog} (hc : Completes A P P') :
    ∀ {g : Nat}, ThruFn P g → ThruFn P' g := by
  intro g h
  induction h with
  | @here f fn hf hb =>
    rcases hc.calls_at f with ⟨h0, _⟩ | ⟨f1, f2, h1, h2, hs⟩
    · rw [h0] at hf; cases hf
    · rw [h1] at hf; cases hf
      exact .here h2 (by rw [← hs.2]; exact hb)
  | @call f g' fn hf hg _ ih =>
    rcases hc.calls_at f with ⟨h0, _⟩ | ⟨f1, f2, h1, h2, hs⟩
    · rw [h0] at hf; cases hf
    · rw [h1] at hf; cases hf
      exact .call h2 ((hs.1 g').mp hg) ih

/-- … and back from the completion to `P`. -/
theorem ThruFn.uncomplete {A : List Nat} {P P' : Prog} (hc : Completes A P P') :
    ∀ {g : Nat}, ThruFn P' g → ThruFn P g := by
  intro g h
  induction h with
  | @here f fn hf hb =>
    rcases hc.calls_at f with ⟨_, h0⟩ | ⟨f1, f2, h1, h2, hs⟩
    · rw [h0] at hf; cases hf
    · rw [h2] at hf; cases hf
      exact .here h1 (by rw [hs.2]; exact hb)
  | @call f g' fn hf hg _ ih =>
    rcases hc.calls_at f with ⟨_, h0⟩ | ⟨f1, f2, h1, h2, hs⟩
    · rw [h0] at hf; cases hf
    · rw [h2] at hf; cases hf
      exact .call h1 ((hs.1 g').mpr hg) ih

theorem ThruFn.complete_iff {A : List Nat} {P P' : Prog} (hc : Completes A P P') (g : Nat) :
    ThruFn P' g ↔ ThruFn P g :=
  ⟨ThruFn.uncomplete hc, ThruFn.complete hc⟩

end C

namespace C
open A2

/-- `CallThruOK` over `P` is `CallThruOK` over `P'` for a callee of the same
    signature that calls no more, when `P'` has no more `ThruFn`s. -/
theorem CallThruOK.transfer {P P' : Prog} {Γ : Ctx} {F : List Var} {fn fn' : Fn} {args : List Var}
    (hthru : ∀ g, ThruFn P' g → ThruFn P g) (hs : SameSig fn fn')
    (hcalls : ∀ g ∈ fn'.body.calls, g ∈ fn.body.calls) :
    CallThruOK P Γ F fn args → CallThruOK P' Γ F fn' args := by
  intro h
  obtain ⟨h1, rest⟩ := h
  refine ⟨fun g hg ht => h1 g (hcalls g hg) (hthru g ht), ?_⟩
  rw [← hs.params, callPost_sig hs]
  exact rest

/-- A function of `P` has, at its index in a completion, one of the same
    signature, callees and `hasThru`. -/
theorem Completes.fn_at {A : List Nat} {P P' : Prog} (hc : Completes A P P') {f : Nat} {fn : Fn}
    (hf : P[f]? = some fn) :
    ∃ fn', P'[f]? = some fn' ∧ SameSig fn fn' ∧ SameCalls fn.body fn'.body := by
  rcases hc.calls_at f with ⟨h0, _⟩ | ⟨f1, f2, h1, h2, hs⟩
  · rw [h0] at hf; cases hf
  · rw [h1] at hf; cases hf
    refine ⟨f2, h2, ?_, hs⟩
    by_cases hA : f ∈ A
    · obtain ⟨g1, g2, hg1, hg2, hsig, -⟩ := hc.stub f hA
      rw [h1] at hg1; rw [h2] at hg2; cases hg1; cases hg2; exact hsig
    · have := hc.keep f hA; rw [h1, h2] at this; cases this; rfl

/-- A call typed over `P` is typed over a completion. -/
theorem CallT.complete {A : List Nat} {P P' : Prog} (hc : Completes A P P') {Γ : Ctx} {F : List Var}
    {f : Nat} {args : List Var} {E : Entry} {Γ' : Ctx} :
    CallT P Γ F f args E Γ' → CallT P' Γ F f args E Γ' := by
  intro h
  obtain ⟨fn, hf, hlen, hargs, hnf, hds, hE, hΓ, hthru⟩ := h
  obtain ⟨fn', hf', hs, hsc⟩ := hc.fn_at hf
  refine ⟨fn', hf', ?_⟩
  rw [← hs.params, callRes_sig hs, callPost_sig hs]
  refine ⟨hlen, hargs, hnf, hds, hE, hΓ, fun ht => ?_⟩
  rcases hthru (ThruFn.uncomplete hc ht) with hr | hk
  · exact Or.inl hr
  · exact Or.inr (CallThruOK.transfer (fun _ => ThruFn.uncomplete hc) hs (fun g hg => (hsc.1 g).mpr hg) hk)

/-- A function whose body is no stub's (`.seq _ .panic`) is outside `A`:
    the completion holds the very same function. -/
theorem Completes.same_of_shape {A : List Nat} {P P' : Prog} (hc : Completes A P P') {f : Nat} {fn : Fn}
    (hf : P[f]? = some fn) (hb : ∀ s, fn.body ≠ .seq s .panic) : P'[f]? = some fn := by
  by_cases hA : f ∈ A
  · obtain ⟨g1, _, hg1, _, _, _, s, hs⟩ := hc.stub f hA
    rw [hf] at hg1; cases hg1; exact absurd hs (hb s)
  · rw [hc.keep f hA, hf]

theorem DtorOK.complete {A : List Nat} {P P' : Prog} (hc : Completes A P P') {f : Nat} {t : Ty} :
    DtorOK P f t → DtorOK P' f t := by
  intro ⟨fn, hf, hp, hr, ho, hl, hrh, hoh, hth⟩
  obtain ⟨fn', hf', hs, -⟩ := hc.fn_at hf
  exact ⟨fn', hf', hs.params ▸ hp, hs.resTy ▸ hr, hs.resOwn ▸ ho, hs.lends ▸ hl, hs.rholds ▸ hrh,
    hs.outHolds ▸ hoh, fun h => hth (ThruFn.uncomplete hc h)⟩

theorem GlueOK.complete {A : List Nat} {P P' : Prog} (hc : Completes A P P') {f : Nat} {t : Ty} :
    GlueOK P f t → GlueOK P' f t := by
  intro ⟨fn, a, b, hf, ht, hp, hr, ho, hl, hrh, hoh, hth, x, z, s, hb, hg⟩
  have hf' := hc.same_of_shape hf (by intro s' h; rw [hb] at h; cases h)
  exact ⟨fn, a, b, hf', ht, hp, hr, ho, hl, hrh, hoh, fun h => hth (ThruFn.uncomplete hc h), x, z, s, hb, hg⟩

theorem EnumGlueOK.complete {A : List Nat} {P P' : Prog} (hc : Completes A P P') {f : Nat} {t : Ty} :
    EnumGlueOK P f t → EnumGlueOK P' f t := by
  intro ⟨fn, a, b, sa, sb, hf, ht, hp, hr, ho, hl, hrh, hoh, hth, hb, rest⟩
  have hf' := hc.same_of_shape hf (by intro s' h; rw [hb] at h; cases h)
  exact ⟨fn, a, b, sa, sb, hf', ht, hp, hr, ho, hl, hrh, hoh, fun h => hth (ThruFn.uncomplete hc h), hb, rest⟩

theorem ImplGlueOK.complete {A : List Nat} {P P' : Prog} (hc : Completes A P P') {f : Nat} {t : Ty} {h i : Nat} :
    ImplGlueOK P f t h i → ImplGlueOK P' f t h i := by
  intro ⟨fn, w, r, e, hf, hst, hp, hr, ho, hl, hrh, hoh, hth, hg, hd, hb⟩
  have hf' := hc.same_of_shape hf (by intro s' h; rw [hb] at h; cases h)
  refine ⟨fn, w, r, e, hf', hst, hp, hr, ho, hl, hrh, hoh, fun h => hth (ThruFn.uncomplete hc h), ?_,
    DtorOK.complete hc hd, hb⟩
  rcases hg with hg | hg
  · exact Or.inl (GlueOK.complete hc hg)
  · exact Or.inr (EnumGlueOK.complete hc hg)

theorem ClosureGlueOK.complete {A : List Nat} {P P' : Prog} (hc : Completes A P P') {f : Nat} {t : Ty} :
    ClosureGlueOK P f t → ClosureGlueOK P' f t := by
  intro ⟨fn, ms, j, σ, sig, r, e, hf, ht, hp, hr, ho, hl, hrh, hoh, hth, hj, hσ, hsp, hb⟩
  have hf' := hc.same_of_shape hf (by intro s' h; rw [hb] at h; cases h)
  obtain ⟨sig', hσ', hs, -⟩ := hc.fn_at hσ
  exact ⟨fn, ms, j, σ, sig', r, e, hf', ht, hp, hr, ho, hl, hrh, hoh, fun h => hth (ThruFn.uncomplete hc h),
    hj, hσ', hs.params ▸ hsp, hb⟩

theorem DropFnOK.complete {A : List Nat} {P P' : Prog} (hc : Completes A P P') {f : Nat} {t : Ty} :
    DropFnOK P f t → DropFnOK P' f t := by
  rintro (⟨hd, hh⟩ | hg | ⟨h, i, hi⟩ | he | hcl)
  · exact Or.inl ⟨DtorOK.complete hc hd, hh⟩
  · exact Or.inr (Or.inl (GlueOK.complete hc hg))
  · exact Or.inr (Or.inr (Or.inl ⟨h, i, ImplGlueOK.complete hc hi⟩))
  · exact Or.inr (Or.inr (Or.inr (Or.inl (EnumGlueOK.complete hc he))))
  · exact Or.inr (Or.inr (Or.inr (Or.inr (ClosureGlueOK.complete hc hcl))))

theorem LetdFn.complete {A : List Nat} {P P' : Prog} (hc : Completes A P P') {f : Nat} {t a : Ty}
    {x : Var} {s : Stmt} : LetdFn P f t a x s → LetdFn P' f t a x s := by
  intro ⟨hd, hg⟩
  refine ⟨DropFnOK.complete hc hd, fun g ha hne => ?_⟩
  obtain ⟨i, r, k, hi, hs⟩ := hg g ha hne
  exact ⟨i, r, k, ImplGlueOK.complete hc hi, hs⟩

theorem TakeOK.complete {A : List Nat} {P P' : Prog} (hc : Completes A P P') {Γ : Ctx} {r : Rhs} :
    TakeOK P Γ r → TakeOK P' Γ r :=
  fun h y Ey g u hr hy ht => EnumGlueOK.complete hc (h y Ey g u hr hy ht)

/-- A function of a completion is one of `P`'s, of the same signature. -/
theorem Completes.fn_back {A : List Nat} {P P' : Prog} (hc : Completes A P P') {f : Nat} {fn' : Fn}
    (hf : P'[f]? = some fn') : ∃ fn, P[f]? = some fn ∧ SameSig fn fn' := by
  rcases hc.calls_at f with ⟨_, h0⟩ | ⟨f1, f2, h1, h2, -⟩
  · rw [h0] at hf; cases hf
  · rw [h2] at hf; cases hf
    obtain ⟨g, hg, hs, -⟩ := hc.fn_at h1
    rw [h2] at hg; cases hg; exact ⟨f1, h1, hs⟩

-- One premise of a `StmtT` rule over `P'`, from the same premise over `P`:
-- as it is, or by its transfer lemma (`hc : Completes A P P'`).
set_option hygiene false in
local macro "transfer_premise" : tactic =>
  `(tactic| (try (first
    | assumption
    | (exact CallT.complete hc ‹_›)
    | (exact TakeOK.complete hc ‹_›)
    | (exact LetdFn.complete hc ‹_›)
    | (exact DropFnOK.complete hc ‹_›))))

theorem StmtT.complete {A : List Nat} {P P' : Prog} (hc : Completes A P P') {ξ : Exits} {Γ : Ctx}
    {F : List Var} {s : Stmt} {Δ : Ctx} : StmtT P ξ Γ F s Δ → StmtT P' ξ Γ F s Δ := by
  intro h
  induction h
  case skip => apply StmtT.skip <;> transfer_premise
  case seq => apply StmtT.seq <;> transfer_premise
  case letv => apply StmtT.letv <;> transfer_premise
  case letcall =>
    rename_i hdk _
    apply StmtT.letcall <;> transfer_premise
    exact fun fn' hf' hro hd => by
      obtain ⟨fn, hf, hs⟩ := hc.fn_back hf'
      exact hdk fn hf (hs.resOwn.trans hro) (by rw [hs.resTy]; exact hd)
  case scope => apply StmtT.scope <;> transfer_premise
  case rbind => apply StmtT.rbind <;> transfer_premise
  case frozen => apply StmtT.frozen <;> transfer_premise
  case assign => apply StmtT.assign <;> transfer_premise
  case ite => apply StmtT.ite <;> transfer_premise
  case «while» => apply StmtT.«while» <;> transfer_premise
  case push => apply StmtT.push <;> transfer_premise
  case free => apply StmtT.free <;> transfer_premise
  case sub => apply StmtT.sub <;> transfer_premise
  case panic => apply StmtT.panic <;> transfer_premise
  case letrec =>
    rename_i h1 h2 h3 h4 h5 h6 h7 h8 _ h10 ih
    obtain ⟨fn', hf', hs, -⟩ := hc.fn_at h4
    exact StmtT.letrec h1 h2 h3 hf' (hs.params ▸ h5) (hs.resTy ▸ h6) (hs.resOwn ▸ h7) (CallT.complete hc h8) ih h10
  case unpair =>
    apply StmtT.unpair <;> transfer_premise
    rcases (‹_ ∨ ∃ f, _ ∧ GlueOK P f _›) with h | ⟨f, h1, h2⟩
    · exact Or.inl h
    · exact Or.inr ⟨f, h1, GlueOK.complete hc h2⟩
  case callc =>
    rename_i h1 h2 h3 h4 h5 h6 h7 h8 h9 h10 h11 _ h13 hdk ih
    obtain ⟨sig', hσ', hs, -⟩ := hc.fn_at h7
    exact StmtT.callc h1 h2 h3 h4 h5 h6 hσ' (hs.params ▸ h8) (hs.outHolds ▸ h9) (CallT.complete hc h10) h11 ih h13
      (fun hro hd => hdk (hs.resOwn.trans hro) (by rw [hs.resTy]; exact hd))
  case catchR => apply StmtT.catchR <;> transfer_premise
  case letd =>
    apply StmtT.letd <;> transfer_premise
    obtain ⟨h1, h2⟩ := (‹LetdFn P _ _ _ _ _ ∧ TakeOK P _ _›)
    exact ⟨LetdFn.complete hc h1, TakeOK.complete hc h2⟩
  case withLock => apply StmtT.withLock <;> transfer_premise
  case scopeL => apply StmtT.scopeL <;> transfer_premise
  case insert => apply StmtT.insert <;> transfer_premise
  case withElem => apply StmtT.withElem <;> transfer_premise
  case callcE =>
    rename_i h1 h2 h3 h4 h5 h6 h7 h8 h9 h10 h11 h12 h13 h14 h15 h16 _ h18 h19 hdk ih
    obtain ⟨sig', hσ', hs, -⟩ := hc.fn_at h9
    exact StmtT.callcE h1 h2 h3 h4 h5 h6 h7 h8 hσ' (by rw [← hs.params, ← hs.resOwn]; exact h10)
      (hs.lends ▸ h11) (hs.rholds ▸ h12) (hs.outHolds ▸ h13) h14 h15 (CallT.complete hc h16) ih h18
      (fun h => h19 (ThruFn.uncomplete hc h))
      (fun hro hd => hdk (hs.resOwn.trans hro) (by rw [hs.resTy]; exact hd))
  case scopeD =>
    apply StmtT.scopeD <;> transfer_premise
    obtain ⟨E, t, h1, h2, h3, h4, h5, h6⟩ := (‹∃ E t, _ ∧ _ ∧ _ ∧ _ ∧ DropFnOK P _ t ∧ _›)
    exact ⟨E, t, h1, h2, h3, h4, DropFnOK.complete hc h5, h6⟩
  case editB => apply StmtT.editB <;> transfer_premise
  case editBV => apply StmtT.editBV <;> transfer_premise
  case takeB => apply StmtT.takeB <;> transfer_premise
  case takeBV => apply StmtT.takeBV <;> transfer_premise
  case exit => apply StmtT.exit <;> transfer_premise
  case block => apply StmtT.block <;> transfer_premise
  case loop => apply StmtT.loop <;> transfer_premise

theorem Implements.complete {A : List Nat} {P P' : Prog} (hc : Completes A P P') {f : Nat} {te : Ty}
    {cs : List (Var × PMode × Ty)} {σ : Nat} : Implements P f te cs σ → Implements P' f te cs σ := by
  intro ⟨fn, sig, hf, hσ, hp, hrv, hr, ho, hl, hrh, hoh, hth⟩
  obtain ⟨fn', hf', hs, -⟩ := hc.fn_at hf
  obtain ⟨sig', hσ', hs', -⟩ := hc.fn_at hσ
  have hrecv : sig.recvMode = sig'.recvMode := by simp only [Fn.recvMode, hs'.params]
  refine ⟨fn', sig', hf', hσ', ?_, ?_, ?_, ?_, ?_, ?_, ?_, fun h => ?_⟩
  · rw [← hs.params, ← hs'.params, ← hrecv]; exact hp
  · rw [← hrecv]; exact hrv
  · rw [← hs.resTy, ← hs'.resTy]; exact hr
  · rw [← hs.resOwn, ← hs'.resOwn]; exact ho
  · rw [← hs.lends, ← hs'.lends]; exact hl
  · rw [← hs.rholds, ← hs'.rholds]; exact hrh
  · rw [← hs.outHolds, ← hs'.outHolds]; exact hoh
  · obtain ⟨h1, h2, h3⟩ := hth (ThruFn.uncomplete hc h)
    exact ⟨ThruFn.complete hc h1, h2, hrecv ▸ h3⟩

theorem CodeOK.complete {A : List Nat} {P P' : Prog} (hc : Completes A P P') {fs : List Nat} {te : Ty}
    {ms : List Nat} {cs : List (Var × PMode × Ty)} : CodeOK P fs te ms cs → CodeOK P' fs te ms cs :=
  fun ⟨hl, h⟩ => ⟨hl, fun j f σ hf hσ => Implements.complete hc (h j f σ hf hσ)⟩

theorem Rhs.codeOK.complete {A : List Nat} {P P' : Prog} (hc : Completes A P P') {r : Rhs} :
    r.codeOK P → r.codeOK P' := by
  intro h
  cases r with
  | pack fs te ms q cs => exact CodeOK.complete hc h
  | arcNew t q => exact fun f u hr => DropFnOK.complete hc (h f u hr)
  | lockNew t q => exact fun f u hr => DropFnOK.complete hc (h f u hr)
  | cellNew t q => exact fun f u hr => DropFnOK.complete hc (h f u hr)
  | _ => trivial

theorem Stmt.codesOK.complete {A : List Nat} {P P' : Prog} (hc : Completes A P P') :
    ∀ {s : Stmt}, s.codesOK P → s.codesOK P' := by
  intro s
  induction s <;> intro h <;> simp only [Stmt.codesOK] at h ⊢ <;>
    first
    | trivial
    | exact ⟨‹_ → _› h.1, ‹_ → _› h.2⟩
    | exact ⟨Rhs.codeOK.complete hc h.1, ‹_ → _› h.2⟩
    | exact Rhs.codeOK.complete hc h
    | exact ‹_ → _› h

theorem EnumGlueOK.not_stub {P : Prog} {f : Nat} {u : Ty} {fn : Fn} (hg : EnumGlueOK P f u)
    (hf : P[f]? = some fn) : ∀ s, fn.body ≠ .seq s .panic := by
  obtain ⟨fn0, _, _, _, _, hf0, _, _, _, _, _, _, _, _, hb, _⟩ := hg
  rw [hf] at hf0; cases hf0; intro s h; rw [hb] at h; cases h

theorem ClosureGlueOK.not_stub {P : Prog} {f : Nat} {u : Ty} {fn : Fn} (hg : ClosureGlueOK P f u)
    (hf : P[f]? = some fn) : ∀ s, fn.body ≠ .seq s .panic := by
  obtain ⟨fn0, _, _, _, _, _, _, hf0, _, _, _, _, _, _, _, _, _, _, _, hb⟩ := hg
  rw [hf] at hf0; cases hf0; intro s h; rw [hb] at h; cases h

theorem DtorParamsOK.complete {A : List Nat} {P P' : Prog} (hc : Completes A P P') {fn : Fn} :
    DtorParamsOK P fn → DtorParamsOK P' fn := by
  intro ⟨h1, h2, h3⟩
  refine ⟨fun i hi hs hd => ?_, h2, fun ho hd => ?_⟩
  · obtain ⟨hm, ha⟩ := h1 i hi hs hd
    refine ⟨?_, ha⟩
    rcases hm with hm | ⟨f, u, hf, hg⟩
    · exact Or.inl hm
    · rcases hg with hg | hg
      · exact Or.inr ⟨f, u, hc.same_of_shape hf (EnumGlueOK.not_stub hg hf), Or.inl (EnumGlueOK.complete hc hg)⟩
      · exact Or.inr ⟨f, u, hc.same_of_shape hf (ClosureGlueOK.not_stub hg hf), Or.inr (ClosureGlueOK.complete hc hg)⟩
  · obtain ⟨hasg, g, t, hr, hv, hfn, hd'⟩ := h3 ho hd
    exact ⟨hasg, g, t, hr, hv, hfn, DropFnOK.complete hc hd'⟩

/-- A function typed over `P` is typed over a completion. -/
theorem FnOK.complete {A : List Nat} {P P' : Prog} (hc : Completes A P P') {fn : Fn} :
    FnOK P fn → FnOK P' fn := by
  intro ⟨h1, h2, h3, h4, h5, h6, h7, h8, h9, h10, h11, h12, Δ, hb, rest⟩
  exact ⟨h1, h2, h3, h4, h5, h6, h7, h8, h9, h10, h11, DtorParamsOK.complete hc h12, Δ,
    StmtT.complete hc hb, rest⟩

/-- The assumed functions of a completion are well-typed and keep their
    code invariant: the hypothesis a conditional certificate rests on, one
    ledger row per function. -/
def AssumedOK (A : List Nat) (P' : Prog) : Prop :=
  ∀ i ∈ A, ∃ fn, P'[i]? = some fn ∧ FnOK P' fn ∧ fn.body.codesOK P'

/-- A body of the stub's shape. -/
def _root_.A2.Stmt.isStubB : Stmt → Bool
  | .seq _ .panic => true
  | _ => false

theorem Stmt.isStubB_sound {s : Stmt} (h : s.isStubB = true) : ∃ s', s = .seq s' .panic := by
  cases s with
  | seq a b => cases b <;> simp [Stmt.isStubB] at h ⊢
  | _ => simp [Stmt.isStubB] at h

/-- `progOK2B` but at the assumed indices, where `P` holds a stub. -/
def progOK2BA (P : Prog) (A : List Nat) : Bool :=
  -- (every assumed index names a function: one past the end could never
  -- be completed)
  A.all (fun i => decide (i < P.length)) &&
  (List.range P.length).all fun f => match P[f]? with
    | some fn => if f ∈ A then fn.body.isStubB else fnOK2B P f fn && stmtCodesB P fn.body
    | none => true

theorem progOK2BA_sound {P : Prog} {A : List Nat} (h : progOK2BA P A = true) :
    (∀ i, i ∉ A → ∀ fn, P[i]? = some fn → FnOK P fn ∧ fn.body.codesOK P) ∧
      (∀ i ∈ A, ∀ fn, P[i]? = some fn → ∃ s, fn.body = .seq s .panic) ∧ ∀ i ∈ A, i < P.length := by
  simp only [progOK2BA, Bool.and_eq_true, List.all_eq_true, decide_eq_true_eq] at h
  obtain ⟨hA, h⟩ := h
  have hat : ∀ i fn, P[i]? = some fn →
      (if i ∈ A then fn.body.isStubB else fnOK2B P i fn && stmtCodesB P fn.body) = true := by
    intro i fn hf
    have hlt : i < P.length := by
      rcases Nat.lt_or_ge i P.length with h' | h'
      · exact h'
      · rw [List.getElem?_eq_none h'] at hf; cases hf
    have := h i (List.mem_range.mpr hlt)
    rw [hf] at this; exact this
  refine ⟨fun i hA fn hf => ?_, fun i hA fn hf => ?_, hA⟩
  · have := hat i fn hf
    split at this
    · exact absurd ‹i ∈ A› hA
    · simp only [Bool.and_eq_true] at this
      exact ⟨fnOK2B_sound hf this.1, stmtCodesB_sound this.2⟩
  · have := hat i fn hf
    split at this
    · exact Stmt.isStubB_sound this
    · exact absurd hA ‹i ∉ A›

/-- The checker's verdict on a program with assumed functions `A`. -/
def certOK2BA (P : Prog) (A : List Nat) (s : Stmt) (nv : Nat) : Bool :=
  progOK2BA P A && (checkA2 P s.vars (fun _ => none) [] s).isSome && stmtCodesB P s && s.src &&
    s.vars.all (fun v => decide (v < nv))

/-- A completion of an accepted program is typed. -/
theorem certOK2BA_typed {P P' : Prog} {A : List Nat} {s : Stmt} {nv : Nat}
    (h : certOK2BA P A s nv = true) (hc : Completes A P P') (ha : AssumedOK A P') :
    ProgOK P' ∧ ProgCodes P' ∧ (∃ Δ, StmtT P' .none (fun _ => none) [] s Δ) ∧ s.src = true ∧
      s.codesOK P' ∧ ∀ v ∈ s.vars, v < nv := by
  simp only [certOK2BA, Bool.and_eq_true, List.all_eq_true, decide_eq_true_eq,
    Option.isSome_iff_exists] at h
  obtain ⟨⟨⟨⟨hP, ⟨Δ, hck⟩⟩, hsc⟩, hs⟩, hv⟩ := h
  obtain ⟨hok, -, -⟩ := progOK2BA_sound hP
  obtain ⟨ht, _⟩ := checkA2_sound (ξ := .none) (fun _ _ => rfl) (fun v hv => hv) hck
  have hfn : ∀ fn ∈ P', FnOK P' fn ∧ fn.body.codesOK P' := by
    intro fn hfn
    obtain ⟨i, hlt, hget⟩ := List.mem_iff_getElem.mp hfn
    have hi : P'[i]? = some fn := by rw [List.getElem?_eq_getElem hlt, hget]
    by_cases hA : i ∈ A
    · obtain ⟨fn', hf', hok', hc'⟩ := ha i hA
      rw [hi] at hf'; cases hf'; exact ⟨hok', hc'⟩
    · have hk := hc.keep i hA
      rw [hi] at hk
      obtain ⟨h1, h2⟩ := hok i hA fn hk.symm
      exact ⟨FnOK.complete hc h1, Stmt.codesOK.complete hc h2⟩
  exact ⟨fun fn h => (hfn fn h).1, fun fn h => (hfn fn h).2, ⟨Δ, StmtT.complete hc ht⟩, hs,
    Stmt.codesOK.complete hc (stmtCodesB_sound hsc), fun v h => hv v h⟩

/-- `M.safe`, conditional: every completion of the program in which the
    assumed functions are well-typed never gets stuck. -/
theorem cert_safe_cond {P : Prog} {A : List Nat} {s : Stmt} {nv : Nat} (h : certOK2BA P A s nv = true) :
    ∀ P', Completes A P P' → AssumedOK A P' →
      ∀ m' s', Steps P' (emptyMem nv) s (.ok m' s') → ¬ Stuck P' m' s' := by
  intro P' hc ha
  obtain ⟨hok, hcodes, ⟨_, ht⟩, hs, hsc, hv⟩ := certOK2BA_typed h hc ha
  exact fun _ _ hr => memory_safe hok hcodes ht hs hsc hv hr

/-- `M.leak`, conditional, a finished run. -/
theorem cert_leak_end_cond {P : Prog} {A : List Nat} {s : Stmt} {nv : Nat} (h : certOK2BA P A s nv = true) :
    ∀ P', Completes A P P' → AssumedOK A P' →
      ∀ m', Steps P' (emptyMem nv) s (.ok m' .skip) → ∀ i, m'.alloc i = false := by
  intro P' hc ha
  obtain ⟨hok, hcodes, ⟨_, ht⟩, hs, hsc, hv⟩ := certOK2BA_typed h hc ha
  exact fun _ hr => no_leak_end hok hcodes ht hs hsc hv hr

/-- `M.leak`, conditional, a run ended by an uncaught panic. -/
theorem cert_leak_panic_cond {P : Prog} {A : List Nat} {s : Stmt} {nv : Nat} (h : certOK2BA P A s nv = true) :
    ∀ P', Completes A P P' → AssumedOK A P' →
      ∀ m', Steps P' (emptyMem nv) s (.panic m') → ∀ i, m'.alloc i = false := by
  intro P' hc ha
  obtain ⟨hok, hcodes, ⟨_, ht⟩, hs, hsc, hv⟩ := certOK2BA_typed h hc ha
  exact fun _ hr => no_leak_panic hok hcodes ht hs hsc hv hr

/-! ### A witness: the hypotheses can hold

`@ seven → i { ^ 7 }  @ main → i { ^ ( seven ) }`, with `seven` (index 0)
assumed: `P` holds its stub, the checker accepts, and the real program
(`seven`'s translated body) is a completion in which `seven` is well-typed.
So the conditional claims are not vacuous: the real program is one of the
programs they speak about. -/

/-- `seven`, as the translation makes it. -/
def condWitnessSeven : Fn :=
  { params := [], resTy := .int, resOwn := false, lends := [], rholds := [],
    outHolds := [], body := (.block (.seq (.assign 0 (.expr .any)) (.exit 0))), nvars := 2 }

/-- `seven`'s stub: its signature, no callees, no change through a borrow. -/
def condWitnessStub : Fn := { condWitnessSeven with body := .seq .skip .panic, nvars := 0 }

def condWitnessMain : Fn :=
  { params := [], resTy := .int, resOwn := false, lends := [], rholds := [],
    outHolds := [], body := (.block (.seq (.letcall 1 0 [] (.assign 0 (.expr .any))) (.exit 0))), nvars := 3 }

def condWitnessP : Prog := [condWitnessStub, condWitnessMain]
def condWitnessReal : Prog := [condWitnessSeven, condWitnessMain]
def condWitnessEntry : Stmt := .letcall 0 1 [] .skip

theorem cond_witness_ok : certOK2BA condWitnessP [0] condWitnessEntry 1 = true := by decide +kernel

/-- An assumed index past the program's end is refused: it could never be
    completed. -/
theorem cond_witness_bad_index : certOK2BA condWitnessP [0, 2] condWitnessEntry 1 = false := by
  decide +kernel

theorem cond_witness_completes : Completes [0] condWitnessP condWitnessReal where
  len := rfl
  keep := by
    intro i hi
    match i with
    | 0 => exact absurd (List.mem_singleton_self 0) hi
    | 1 => rfl
    | _ + 2 => rfl
  stub := by
    intro i hi
    rw [List.mem_singleton] at hi; subst hi
    exact ⟨condWitnessStub, condWitnessSeven, rfl, rfl, rfl, ⟨fun _ => by simp [Stmt.calls, condWitnessStub,
      condWitnessSeven], rfl⟩, .skip, rfl⟩

theorem cond_witness_assumed : AssumedOK [0] condWitnessReal := by
  intro i hi
  rw [List.mem_singleton] at hi; subst hi
  refine ⟨condWitnessSeven, rfl, fnOK2B_sound (f := 0) rfl (by decide +kernel),
    stmtCodesB_sound (by decide +kernel)⟩

/-- The real program never gets stuck, by the conditional claim. -/
theorem cond_witness_safe :
    ∀ m' s', Steps condWitnessReal (emptyMem 1) condWitnessEntry (.ok m' s') → ¬ Stuck condWitnessReal m' s' :=
  cert_safe_cond cond_witness_ok _ cond_witness_completes cond_witness_assumed

end C
