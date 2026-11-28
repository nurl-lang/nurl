module

public import C.A2Pack

@[expose] public section

/-!
# C9: A2's calls, decided (AGORA-970)

`callB2` decides A2's `CallT` for a call with a known callee. Every
argument is live and of its parameter's type. One that moves or may
change is reached by no other argument in memory, a `sink` by nothing at
all, and an `inout` one only by names of its own bound; a replaced one is
not pinned. The closures among the arguments change only what `NamesFree`
allows. No armed destructor views what the call ends (`CallDtorSafe`). The
call's last premise is conditional on the callee changing elements through
a borrow (`ThruFn`, a reachability over the call graph). The checker asks
its conclusion unconditionally (the arguments hold views only of regions),
which is sound. The theorem is `callB2_sound`, and `callPost2_supported`
keeps the context in the domain.
-/

namespace C

open A2

def paramOKB2 : PMode → Ty → Entry → Bool
  | .inp, t, E => decide (E.ty = t)
  | .sink, t, E => decide (E.ty = t) && decide (E.mode = .own) && t.owning
  | .inout b, t, E => decide (E.ty = t) && canDoB2 E.mode b && t.owning

theorem paramOKB2_sound {m : PMode} {t : Ty} {E : Entry} (h : paramOKB2 m t E = true) : paramOK m t E := by
  cases m with
  | inp => simpa [paramOKB2, paramOK] using h
  | sink =>
    simp only [paramOKB2, Bool.and_eq_true, decide_eq_true_eq] at h
    exact ⟨h.1.1, h.1.2, h.2⟩
  | inout b =>
    simp only [paramOKB2, Bool.and_eq_true, decide_eq_true_eq] at h
    exact ⟨h.1.1, canDoB2_sound h.1.2, h.2⟩

/-- An `inout` argument `a` is reached in `ds` only by names of its own bound. -/
def inoutOK (m : PMode) (ds : List Dep) (a : Var) : Bool :=
  match m with
  | .inout b => ds.all fun d => d.root != a || (decide (d.kind.bound = b) && decide (b ≠ .none))
  | _ => true

theorem inoutOK_sound {m : PMode} {ds : List Dep} {a : Var} (h : inoutOK m ds a = true) :
    ∀ b, m = .inout b → ∀ d ∈ ds, d.root = a → d.kind.bound = b ∧ b ≠ .none := by
  intro b hb d hd hr
  subst hb
  have := List.all_eq_true.mp h d hd
  simp only [Bool.or_eq_true, bne_iff_ne, ne_eq, Bool.and_eq_true, decide_eq_true_eq] at this
  rcases this with h0 | h0
  · exact absurd hr h0
  · exact h0

/-- The checks on argument `i`. -/
def argOK2 (D : List Var) (Γ : Ctx) (F : List Var) (fn : Fn) (args : List Var) (i : Nat) : Bool :=
  match fn.params[i]?, Γ (args.getD i 0) with
  | some (m, t), some Ea =>
    Ea.live && paramOKB2 m t Ea &&
      (!m.moves || (decide (args.getD i 0 ∉ F) && decide (args.getD i 0 ∉ roots (memDeps Ea.vdeps)) &&
        decide (m = .sink → args.getD i 0 ∉ roots Ea.vdeps) && inoutOK m Ea.vdeps (args.getD i 0) &&
        (List.range fn.params.length).all fun j => j == i ||
          (decide (args.getD j 0 ≠ args.getD i 0) &&
           decide (args.getD i 0 ∉ roots (memDeps (argE Γ (args.getD j 0)).vdeps)) &&
           decide (m = .sink → args.getD i 0 ∉ roots (argE Γ (args.getD j 0)).vdeps) &&
           inoutOK m (argE Γ (args.getD j 0)).vdeps (args.getD i 0)))) &&
      (!(decide (m = .sink ∨ m = .inout .replace)) || noPinB D Γ (args.getD i 0))
  | _, _ => false

/-- `HeldAnch`, decided. -/
def heldAnchB (E : Entry) (d : Dep) : Bool :=
  decide (d ∉ E.path) && decide (d ∈ E.held) && (match E.ty with | .vec _ => true | _ => false) &&
    decide (d.kind = .view ∨ d.kind = .self)

theorem heldAnchB_of {E : Entry} {d : Dep} (h : HeldAnch E d) : heldAnchB E d = true := by
  obtain ⟨h1, h2, ⟨t, ht⟩, h4⟩ := h
  simp [heldAnchB, h1, h2, ht, h4]

/-- `NamesFree`, decided (its AGORA-937 B3 clause over the domain). -/
def namesFreeB (D : List Var) (Γ : Ctx) (F : List Var) (ps : List (PMode × Ty)) (args : List Var) : Bool :=
  (mutNames Γ args).all fun d =>
    canDoB2 (argE Γ d.root).mode d.kind.bound &&
    (match (argE Γ d.root).ty with | .vec s => !s.holdsView | _ => false) &&
    decide (d.root ∉ F) &&
    (decide (d.root ∉ args) || (List.range args.length).any fun i =>
      decide (args[i]? = some d.root) &&
        (match ps[i]? with | some (m, _) => decide (m = .inout d.kind.bound) | none => false)) &&
    (args.all fun a => !(decide ((argE Γ a).ty ≠ .int ∨ (argE Γ a).mode = .rootb)) ||
      (argE Γ a).vdeps.all fun d' => d'.root != d.root || decide (d'.kind.bound = d.kind.bound)) &&
    D.all fun p => match Γ p with
      | some Ep => !(decide (Ep.mode = .rootb)) || Ep.vdeps.all fun d' =>
          d'.root != d.root || !heldAnchB Ep d' || !(d.kind.bound.kills false d'.kind)
      | none => true

theorem namesFreeB_sound {D : List Var} {Γ : Ctx} {F : List Var} {ps : List (PMode × Ty)} {args : List Var}
    (hs : Supported2 Γ D) (h : namesFreeB D Γ F ps args = true) : NamesFree Γ F ps args := by
  intro d hd
  have := List.all_eq_true.mp h d hd
  simp only [Bool.and_eq_true, decide_eq_true_eq, Bool.or_eq_true, List.any_eq_true] at this
  obtain ⟨⟨⟨⟨⟨hc, hv⟩, hF⟩, hin⟩, hall⟩, hanch⟩ := this
  refine ⟨canDoB2_sound hc, ?_, hF, ?_, fun a ha hk d' hd' hr => ?_, fun p Ep hEp hm d' hd' hr hh => ?_⟩
  · revert hv
    cases hty : (argE Γ d.root).ty with
    | vec s => intro hv; exact ⟨s, rfl, by simpa using hv⟩
    | _ => intro hv; simp at hv
  · rcases hin with h0 | ⟨i, _, hi, hm⟩
    · exact Or.inl h0
    · refine Or.inr ⟨i, ?_⟩
      revert hm
      cases hp : ps[i]? with
      | none => intro hm; simp at hm
      | some p =>
        obtain ⟨m, t⟩ := p
        intro hm
        simp only [decide_eq_true_eq] at hm
        exact ⟨t, hi, by rw [hm]⟩
  · have := List.all_eq_true.mp hall a ha
    simp only [Bool.or_eq_true, Bool.not_eq_true', decide_eq_false_iff_not] at this
    rcases this with h0 | h0
    · exact absurd hk h0
    · have := List.all_eq_true.mp h0 d' hd'
      simp only [Bool.or_eq_true, bne_iff_ne, ne_eq, decide_eq_true_eq] at this
      rcases this with h1 | h1
      · exact absurd hr h1
      · exact h1
  · have := List.all_eq_true.mp hanch p (mem_of_some2 hs hEp)
    rw [hEp] at this
    simp only [Bool.or_eq_true, Bool.not_eq_true', decide_eq_false_iff_not] at this
    rcases this with h0 | h0
    · exact absurd hm h0
    · have := List.all_eq_true.mp h0 d' hd'
      simp only [Bool.or_eq_true, bne_iff_ne, ne_eq, Bool.not_eq_true'] at this
      rcases this with (h1 | h1) | h1
      · exact absurd hr h1
      · rw [heldAnchB_of hh] at h1; cases h1
      · exact h1

/-- `CallDtorSafe`, decided over the domain. -/
def callDtorSafeB (D : List Var) (Γ : Ctx) (ps : List (PMode × Ty)) (args : List Var) : Bool :=
  ((List.range ps.length).all fun i => match ps[i]? with
    | some (.sink, _) => dtorSafeB D Γ .replace false (args.getD i 0)
    | some (.inout b, t) => dtorSafeB D Γ b t.elem.holdsView (args.getD i 0) &&
        (match Γ (args.getD i 0) with | some Ea => !Ea.dbind | none => true)
    | _ => true) &&
  (mutNames Γ args).all fun d => dtorSafeB D Γ d.kind.bound false d.root

theorem callDtorSafeB_sound {D : List Var} {Γ : Ctx} {ps : List (PMode × Ty)} {args : List Var}
    (hs : Supported2 Γ D) (h : callDtorSafeB D Γ ps args = true) : CallDtorSafe Γ ps args := by
  simp only [callDtorSafeB, Bool.and_eq_true] at h
  obtain ⟨h1, h2⟩ := h
  have key : ∀ i (hi : i < ps.length), _ := fun i (hi : i < ps.length) => by
    have := List.all_eq_true.mp h1 i (List.mem_range.mpr hi)
    rw [List.getElem?_eq_getElem hi] at this
    exact this
  refine ⟨fun i hi => ⟨fun hm => ?_, fun b hm => ?_⟩, fun d hd => dtorSafeB_sound hs (List.all_eq_true.mp h2 d hd),
    fun i hi b hm Ea hEa => ?_⟩
  · have := key i hi
    have hp : ps[i] = (.sink, ps[i].2) := by rw [← hm]
    rw [hp] at this; exact dtorSafeB_sound hs this
  · have := key i hi
    have hp : ps[i] = (.inout b, ps[i].2) := by rw [← hm]
    rw [hp] at this
    simp only [Bool.and_eq_true] at this
    exact dtorSafeB_sound hs this.1
  · have := key i hi
    have hp : ps[i] = (.inout b, ps[i].2) := by rw [← hm]
    rw [hp] at this
    simp only [Bool.and_eq_true, hEa, Bool.not_eq_true'] at this
    exact this.2

/-- The region premise, asked unconditionally. -/
def regionsB (Γ : Ctx) (args : List Var) : Bool :=
  (callR Γ args).all fun r => match Γ r with
    | some E => decide (E.mode = .region)
    | none => false

theorem regionsB_sound {Γ : Ctx} {args : List Var} (h : regionsB Γ args = true) :
    ∀ r ∈ callR Γ args, ∃ E, Γ r = some E ∧ E.mode = .region := by
  intro r hr
  have := List.all_eq_true.mp h r hr
  revert this
  cases hE : Γ r with
  | none => intro h; cases h
  | some E => intro h; exact ⟨E, rfl, of_decide_eq_true h⟩

/-- A2's `CallT`, decided: the result entry and the context after. Sound,
    not complete: for a through-changing callee it checks only the
    regions-only branch of the `ThruFn` premise, not route U's `CallThruOK`.
    So it refuses `( f1 vv )` in `HeldViewThruWitness.K2`, which `call_ok`
    types. The rejection is conservative on purpose. -/
def callB2 (P : Prog) (D : List Var) (Γ : Ctx) (F : List Var) (f : Nat) (args : List Var) : Option (Entry × Ctx) :=
  match P[f]? with
  | some fn =>
    if args.length = fn.params.length ∧ (List.range fn.params.length).all (argOK2 D Γ F fn args) ∧
        namesFreeB D Γ F fn.params args ∧ callDtorSafeB D Γ fn.params args ∧
        -- (CallT asks the region premise of a through-changing callee only:
        -- one in the thru-free set, `noThruB`, needs none)
        (noThruB P f || regionsB Γ args) then
      some (callRes Γ fn args, callPost Γ fn args)
    else none
  | none => none

theorem callB2_sound {P : Prog} {D : List Var} {Γ : Ctx} {F : List Var} {f : Nat} {args : List Var}
    {E : Entry} {Γ' : Ctx} (hs : Supported2 Γ D) (h : callB2 P D Γ F f args = some (E, Γ')) :
    CallT P Γ F f args E Γ' ∧ ∃ fn, P[f]? = some fn ∧ Γ' = callPost Γ fn args := by
  unfold callB2 at h
  split at h
  · rename_i fn hfn
    split at h
    · rename_i hc
      obtain ⟨hlen, hall, hnf, hcd, hrg⟩ := hc
      simp only [Option.some.injEq, Prod.mk.injEq] at h
      obtain ⟨rfl, rfl⟩ := h
      refine ⟨⟨fn, hfn, hlen, fun i hi => ?_, namesFreeB_sound hs hnf, callDtorSafeB_sound hs hcd, rfl, rfl,
        fun ht => (by
          simp only [Bool.or_eq_true] at hrg
          rcases hrg with h0 | h0
          · exact absurd ht (noThruB_sound h0)
          · exact Or.inl (regionsB_sound h0))⟩, fn, hfn, rfl⟩
      have ha := List.all_eq_true.mp hall i (List.mem_range.mpr hi)
      unfold argOK2 at ha
      rw [List.getElem?_eq_getElem hi] at ha
      split at ha
      · rename_i m t Ea hp hEa
        simp only [Option.some.injEq] at hp
        simp only [Bool.and_eq_true, Bool.or_eq_true, Bool.not_eq_true', decide_eq_false_iff_not,
          decide_eq_true_eq] at ha
        obtain ⟨⟨⟨hl, hpo⟩, hmv⟩, hpin⟩ := ha
        refine ⟨Ea, hEa, hl, by rw [hp]; exact paramOKB2_sound hpo, fun hm => ?_, fun hsr => ?_⟩
        · rw [hp] at hm
          rcases hmv with hmv | ⟨⟨⟨⟨hF, hr⟩, hsk⟩, hio⟩, hj⟩
          · simp only at hm; rw [hm] at hmv; cases hmv
          · refine ⟨hF, hr, by rw [hp]; exact hsk, by rw [hp]; exact inoutOK_sound hio, fun j hj' hne => ?_⟩
            have := List.all_eq_true.mp hj j (List.mem_range.mpr hj')
            simp only [Bool.or_eq_true, beq_iff_eq, Bool.and_eq_true, decide_eq_true_eq] at this
            rcases this with e | ⟨⟨⟨h1, h2⟩, h3⟩, h4⟩
            · exact absurd e hne
            · exact ⟨h1, h2, by rw [hp]; exact h3, by rw [hp]; exact inoutOK_sound h4⟩
        · rw [hp] at hsr
          rcases hpin with h0 | h0
          · exact absurd hsr h0
          · exact noPinB_sound hs h0
      · cases ha
    · cases h
  · cases h

theorem callPostAux2_supported {Γ0 : Ctx} {fn : Fn} {args : List Var} {D : List Var} :
    ∀ (ps : List (PMode × Ty)) (as : List Var) (i : Nat) (Γ : Ctx), Supported2 Γ D → (∀ a ∈ as, a ∈ D) →
      Supported2 (callPostAux Γ0 fn args ps as i Γ) D := by
  intro ps
  induction ps with
  | nil => intro as i Γ hs _; cases as <;> simpa [callPostAux] using hs
  | cons p ps ih =>
    intro as i Γ hs hD
    cases as with
    | nil => obtain ⟨m, t⟩ := p; cases m <;> simpa [callPostAux] using hs
    | cons a as =>
      obtain ⟨m, t⟩ := p
      cases m with
      | inp => exact ih as (i + 1) Γ hs (fun x hx => hD x (by simp [hx]))
      | sink =>
        exact ih as (i + 1) _ (supported2_setE (supported2_kill hs _ _ _) (hD a (by simp)) _)
          (fun x hx => hD x (by simp [hx]))
      | inout b =>
        exact ih as (i + 1) _ (supported2_setE (supported2_kill hs _ _ _) (hD a (by simp)) _)
          (fun x hx => hD x (by simp [hx]))

theorem killNames_supported {D : List Var} : ∀ (ds : List Dep) (Γ : Ctx), Supported2 Γ D →
    Supported2 (killNames ds Γ) D := by
  intro ds
  induction ds with
  | nil => intro Γ hs; exact hs
  | cons d ds ih => intro Γ hs; exact supported2_kill (ih Γ hs) _ _ _

theorem callPost2_supported {Γ : Ctx} {fn : Fn} {args D : List Var} (hs : Supported2 Γ D)
    (hD : ∀ a ∈ args, a ∈ D) : Supported2 (callPost Γ fn args) D :=
  killNames_supported _ _ (callPostAux2_supported fn.params args 0 Γ hs hD)

/-! ### The statement checker with data forms and calls -/

theorem inferRhs2d_OK (D : List Var) : RhsDec.OK D (inferRhs2d D) :=
  fun _ _ _ _ _ hs hD h => inferRhs2d_ok hs hD h

/-- …and with A3.2's lock and A3.4's channel forms (C8c, `chanRhs`). -/
theorem inferRhs2c_OK (D : List Var) : RhsDec.OK D (inferRhs2c D) :=
  fun _ _ _ _ _ hs hD h => inferRhs2c_ok hs hD h

/-- …and with closure literals that capture nothing by name (C8p, `packRhs`). -/
theorem inferRhs2p_OK (P : Prog) (D : List Var) : RhsDec.OK D (inferRhs2p P D) :=
  fun _ _ _ _ _ hs hD h => inferRhs2p_ok hs hD h

theorem callB2_OK (P : Prog) (D : List Var) : CallDec.OK P D (callB2 P D) := by
  intro Γ F f args E Γ1 hs hD h
  obtain ⟨hct, fn, _, hpost⟩ := callB2_sound hs h
  exact ⟨hct, by rw [hpost]; exact callPost2_supported hs hD⟩

/-- A2's checker so far: core, data, lock, channel and closure right-hand sides,
    calls, and the core statements, sound for any exits. -/
def checkA2 (P : Prog) (D : List Var) (Γ : Ctx) (F : List Var) (s : Stmt) : Option Ctx :=
  (checkStmt2T P (rhsTreeFast D (inferRhs2p P D)) (callB2 P D) D (tblOf D Γ) F s).map CtxT.get

theorem checkA2_sound {P : Prog} {D : List Var} {s : Stmt} {ξ : Exits} {Γ : Ctx} {F : List Var} {Δ : Ctx}
    (hs : Supported2 Γ D) (hD : ∀ v ∈ s.vars, v ∈ D) (h : checkA2 P D Γ F s = some Δ) :
    StmtT P ξ Γ F s Δ ∧ Supported2 Δ D := by
  unfold checkA2 at h
  cases ht : checkStmt2T P (rhsTreeFast D (inferRhs2p P D)) (callB2 P D) D (tblOf D Γ) F s with
  | none => rw [ht] at h; cases h
  | some TΔ =>
    rw [ht] at h; simp only [Option.map_some, Option.some.injEq] at h; subst h
    have hself : (tblOf D Γ).get = Γ := ctxOfTbl_self hs
    obtain ⟨h1, h2⟩ := checkStmt2T_sound (rhsTreeFast_OK (inferRhs2p_OK P D)) (callB2_OK P D)
      (by rwa [hself]) hD ht
    rw [hself] at h1
    exact ⟨h1, h2⟩

end C
