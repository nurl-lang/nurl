import C.Call

/-!
# C2: subsumption by certificate (AGORA-970)

A1's `sub` rule lets a statement be typed from a weaker context, and lets
it end in one. The checker cannot guess those contexts. A certificate
names them as finite lists (`CtxL`), and the checker verifies `Weaker`
over the finite domain: entry by entry, then `CtxWF`, which says every
dependency's root is a root binding. `checkC` walks the statement and its
certificate together and is proven sound (`checkC_sound`,
`checkedC_memory_safe`). This is the shape phase C's certificate takes:
nurlc writes down the contexts its walk used, and a small, proven checker
checks them.
-/

namespace C

open A1

/-- A context as a finite list, as a certificate carries it. -/
abbrev CtxL := List (Var × Entry)

def CtxL.toCtx (L : CtxL) : Ctx := fun v => (L.find? (fun p => p.1 == v)).map (·.2)

theorem CtxL.supported {L : CtxL} {D : List Var} (h : L.all (fun p => decide (p.1 ∈ D)) = true) :
    Supported L.toCtx D := by
  intro v hv
  unfold CtxL.toCtx
  cases hf : L.find? (fun p => p.1 == v) with
  | none => rfl
  | some p =>
    exfalso
    have hm := List.mem_of_find?_eq_some hf
    have hp := List.find?_some hf
    have : p.1 = v := by simpa using hp
    exact hv (this ▸ of_decide_eq_true (List.all_eq_true.mp h p hm))

def subB (a b : List Dep) : Bool := a.all (fun d => decide (d ∈ b))

theorem subB_sound {a b : List Dep} (h : subB a b = true) : a ⊆ b := fun d hd =>
  of_decide_eq_true (List.all_eq_true.mp h d hd)

/-- `EntryWeaker`, decided. -/
def entryWeakerB (E E' : Entry) : Bool :=
  decide (E'.ty = E.ty) && decide (E'.mode = E.mode) && (decide (E.mode ≠ .rootb) || decide (E' = E)) &&
    (!E'.live || (E.live && (E.mode.ownSlot || subB E.path E'.path) && subB E.held E'.held))

theorem entryWeakerB_sound {E E' : Entry} (h : entryWeakerB E E' = true) : EntryWeaker E E' := by
  simp only [entryWeakerB, Bool.and_eq_true, Bool.or_eq_true, decide_eq_true_eq, Bool.not_eq_true'] at h
  obtain ⟨⟨⟨hty, hm⟩, hr⟩, hl⟩ := h
  refine ⟨hty, hm, fun e => hr.resolve_left (fun h' => h' e), fun hl' => ?_⟩
  rcases hl with h0 | ⟨⟨h1, h2⟩, h3⟩
  · rw [hl'] at h0; cases h0
  · refine ⟨h1, fun ho => ?_, subB_sound h3⟩
    rcases h2 with h2 | h2
    · rw [ho] at h2; cases h2
    · exact subB_sound h2

/-- `CtxWF` over the domain, decided. -/
def ctxWFB (D : List Var) (Γ : Ctx) : Bool :=
  D.all fun v => match Γ v with
    | some E => !E.live || !(decide (E.ty ≠ .int ∨ E.mode = .rootb)) ||
        (roots E.vdeps).all fun r => match Γ r with
          | some Er => Er.mode.isRoot
          | none => false
    | none => true

theorem ctxWFB_sound {D : List Var} {Γ : Ctx} (hs : Supported Γ D) (h : ctxWFB D Γ = true) : CtxWF Γ := by
  intro v E hv hl hk r hr
  have hvD : v ∈ D := by
    apply Classical.byContradiction; intro hn; rw [hs v hn] at hv; cases hv
  have := List.all_eq_true.mp h v hvD
  rw [hv] at this
  simp only [Bool.or_eq_true, Bool.not_eq_true', decide_eq_false_iff_not] at this
  rcases this with (h0 | h0) | h0
  · rw [hl] at h0; cases h0
  · exact absurd hk h0
  · have := List.all_eq_true.mp h0 r hr
    split at this
    · rename_i Er hEr; exact ⟨Er, hEr, this⟩
    · cases this

/-- `Weaker Γ Γ'` over the domain, decided. -/
def weakerB (D : List Var) (Γ Γ' : Ctx) : Bool :=
  (D.all fun v => match Γ v, Γ' v with
    | none, none => true
    | some E, some E' => entryWeakerB E E'
    | _, _ => false) && ctxWFB D Γ'

theorem weakerB_sound {D : List Var} {Γ Γ' : Ctx} (hs : Supported Γ D) (hs' : Supported Γ' D)
    (h : weakerB D Γ Γ' = true) : Weaker Γ Γ' := by
  simp only [weakerB, Bool.and_eq_true] at h
  obtain ⟨h1, h2⟩ := h
  refine ⟨fun v => ?_, ctxWFB_sound hs' h2⟩
  by_cases hv : v ∈ D
  · have := List.all_eq_true.mp h1 v hv
    split at this
    · rename_i ha hb; exact ⟨by simp [ha, hb], fun E E' e1 e2 => by rw [ha] at e1; cases e1⟩
    · rename_i E E' ha hb
      exact ⟨by simp [ha, hb], fun E1 E1' e1 e2 => by
        rw [ha] at e1; rw [hb] at e2; cases e1; cases e2; exact entryWeakerB_sound this⟩
    · cases this
  · rw [hs v hv, hs' v hv]; exact ⟨Iff.rfl, fun E _ e => by cases e⟩

/-- A certificate: how the statement was typed, with the contexts its
    subsumption steps used. -/
inductive Cert where
  | plain
  | sub (Γ0 : CtxL) (c : Cert) (Δ : CtxL)
  | seq (a b : Cert)
  | letv (c : Cert)
  | letcall (c : Cert)
  | ite (a b : Cert)
  | while (c : Cert)
  | frozen (c : Cert)

def keysIn (D : List Var) (L : CtxL) : Bool := L.all (fun p => decide (p.1 ∈ D))

/-- The checker with certificates. -/
def checkC (P : Prog) (D : List Var) : Cert → Ctx → List Var → Stmt → Option Ctx
  | .plain, Γ, F, s => checkS D Γ F s
  | .sub L0 c L, Γ, F, s =>
    if keysIn D L0 && keysIn D L && weakerB D Γ L0.toCtx then
      match checkC P D c L0.toCtx F s with
      | some Δ0 => if D.all (fun v => Δ0 v == L.toCtx v) || weakerB D Δ0 L.toCtx then some L.toCtx else none
      | none => none
    else none
  | .seq ca cb, Γ, F, .seq a b =>
    if b.src then (match checkC P D ca Γ F a with
      | some Γ1 => checkC P D cb Γ1 F b
      | none => none) else none
  | .letv c, Γ, F, .letv x r s =>
    if s.src ∧ Γ x = none ∧ x ∉ F then
      match inferRhs Γ F r with
      | some (E, Γ1) => (checkC P D c (setE Γ1 x E) F s).map (exitScope x)
      | none => none
    else none
  | .letcall c, Γ, F, .letcall x f args s =>
    if s.src ∧ Γ x = none ∧ x ∉ F then
      match callB P Γ F f args with
      | some (E, Γ1) => (checkC P D c (setE Γ1 x E) F s).map (exitScope x)
      | none => none
    else none
  | .ite ca cb, Γ, F, .ite c a b =>
    if a.src ∧ b.src ∧ checkExpr Γ c then
      match checkC P D ca Γ F a, checkC P D cb Γ F b with
      | some Δa, some Δb => if D.all (fun v => Δa v == Δb v) then some Δa else none
      | _, _ => none
    else none
  | .while cs, Γ, F, .while c s =>
    if s.src ∧ checkExpr Γ c then
      match checkC P D cs Γ F s with
      | some Δ => if D.all (fun v => Δ v == Γ v) then some Γ else none
      | none => none
    else none
  | .frozen c, Γ, F, .frozen z s => checkC P D c Γ (F ++ z) s
  | _, _, _, _ => none

theorem checkC_sound {P : Prog} {D : List Var} : ∀ (c : Cert) {s : Stmt} {Γ : Ctx} {F : List Var} {Δ : Ctx},
    Supported Γ D → (∀ v ∈ s.vars, v ∈ D) → checkC P D c Γ F s = some Δ → StmtT P Γ F s Δ ∧ Supported Δ D := by
  intro c
  induction c with
  | plain => intro s Γ F Δ hs hD h; exact checkS_sound hs hD h
  | sub L0 c L ih =>
    intro s Γ F Δ hs hD h
    simp only [checkC] at h
    split at h
    · rename_i hc
      simp only [Bool.and_eq_true] at hc
      obtain ⟨⟨hk0, hk⟩, hw⟩ := hc
      have hs0 := CtxL.supported hk0
      have hsL := CtxL.supported hk
      split at h
      · rename_i Δ0 h0
        split at h
        · rename_i hj
          simp only [Option.some.injEq] at h; subst h
          obtain ⟨t0, s0⟩ := ih hs0 hD h0
          refine ⟨.sub (weakerB_sound hs hs0 hw) t0 ?_, hsL⟩
          simp only [Bool.or_eq_true] at hj
          rcases hj with hj | hj
          · exact Or.inl (eq_of_agree s0 hsL hj)
          · exact Or.inr (weakerB_sound s0 hsL hj)
        · cases h
      · cases h
    · cases h
  | seq ca cb iha ihb =>
    intro s Γ F Δ hs hD h
    cases s with
    | seq a b =>
      simp only [checkC] at h
      split at h
      · rename_i hb
        split at h
        · rename_i Γ1 ha
          obtain ⟨ta, sa⟩ := iha hs (fun v hv => hD v (by simp [Stmt.vars, hv])) ha
          obtain ⟨tb, sb⟩ := ihb sa (fun v hv => hD v (by simp [Stmt.vars, hv])) h
          exact ⟨.seq hb ta tb, sb⟩
        · cases h
      · cases h
    | _ => simp [checkC] at h
  | letv c ih =>
    intro s Γ F Δ hs hD h
    cases s with
    | letv x r s =>
      simp only [checkC] at h
      split at h
      · rename_i hc
        obtain ⟨hsrc, hx, hF⟩ := hc
        split at h
        · rename_i E Γ1 hr
          obtain ⟨Δ0, h0, rfl⟩ := Option.map_eq_some_iff.mp h
          have hs1 := inferRhs_supported hs (fun v hv => hD v (by simp [Stmt.vars, hv])) hr
          obtain ⟨t0, s0⟩ := ih (supported_setE hs1 (hD x (by simp [Stmt.vars])) E)
            (fun v hv => hD v (by simp [Stmt.vars, hv])) h0
          exact ⟨.letv hsrc hx hF (inferRhs_sound hr) t0, supported_exitScope s0 x⟩
        · cases h
      · cases h
    | _ => simp [checkC] at h
  | letcall c ih =>
    intro s Γ F Δ hs hD h
    cases s with
    | letcall x f args s =>
      simp only [checkC] at h
      split at h
      · rename_i hc
        obtain ⟨hsrc, hx, hF⟩ := hc
        split at h
        · rename_i E Γ1 hcall
          obtain ⟨Δ0, h0, rfl⟩ := Option.map_eq_some_iff.mp h
          have hct := callB_sound hcall
          have ⟨fn, _, _, _, _, hpost⟩ := hct
          have hs1 : Supported Γ1 D := by
            rw [hpost]; exact callPost_supported hs (fun a ha => hD a (by simp [Stmt.vars, ha]))
          obtain ⟨t0, s0⟩ := ih (supported_setE hs1 (hD x (by simp [Stmt.vars])) E)
            (fun v hv => hD v (by simp [Stmt.vars, hv])) h0
          exact ⟨.letcall hsrc hx hF hct t0, supported_exitScope s0 x⟩
        · cases h
      · cases h
    | _ => simp [checkC] at h
  | ite ca cb iha ihb =>
    intro s Γ F Δ hs hD h
    cases s with
    | ite c a b =>
      simp only [checkC] at h
      split at h
      · rename_i hc
        obtain ⟨ha, hb, hce⟩ := hc
        split at h
        · rename_i Δa Δb hca hcb
          split at h
          · rename_i hag
            simp only [Option.some.injEq] at h; subst h
            obtain ⟨ta, sa⟩ := iha hs (fun v hv => hD v (by simp [Stmt.vars, hv])) hca
            obtain ⟨tb, sb⟩ := ihb hs (fun v hv => hD v (by simp [Stmt.vars, hv])) hcb
            have heq := eq_of_agree sa sb hag
            subst heq
            exact ⟨.ite ha hb (checkExpr_sound hce) ta tb, sa⟩
          · cases h
        · cases h
      · cases h
    | _ => simp [checkC] at h
  | «while» cs ih =>
    intro s Γ F Δ hs hD h
    cases s with
    | «while» c s =>
      simp only [checkC] at h
      split at h
      · rename_i hc
        obtain ⟨hsrc, hce⟩ := hc
        split at h
        · rename_i Δ0 h0
          split at h
          · rename_i hag
            simp only [Option.some.injEq] at h; subst h
            obtain ⟨t0, s0⟩ := ih hs (fun v hv => hD v (by simp [Stmt.vars, hv])) h0
            have heq := eq_of_agree s0 hs hag
            subst heq
            exact ⟨.while hsrc (checkExpr_sound hce) t0, hs⟩
          · cases h
        · cases h
      · cases h
    | _ => simp [checkC] at h
  | frozen c ih =>
    intro s Γ F Δ hs hD h
    cases s with
    | frozen z s =>
      simp only [checkC] at h
      obtain ⟨t0, s0⟩ := ih hs (fun v hv => hD v (by simp [Stmt.vars, hv])) h
      exact ⟨.frozen t0, s0⟩
    | _ => simp [checkC] at h

/-- A program the certificate checker accepts, run from the empty store,
    never gets stuck. -/
theorem checkedC_memory_safe {P : Prog} (hP : ProgOK P) {s : Stmt} {c : Cert} {Δ : Ctx}
    (hc : checkC P s.vars c (fun _ => none) [] s = some Δ) (hs : s.src = true) {nv : Nat}
    (hv : ∀ v ∈ s.vars, v < nv) {m' : Mem} {s' : Stmt} (hr : Steps P (emptyMem nv) s (.ok m' s')) :
    ¬ Stuck P m' s' :=
  memory_safe hP (checkC_sound (P := P) c (fun _ _ => rfl) (fun _ h => h) hc).1 hs hv hr

end C
