import C.A2Call

/-!
# C7x: A2's `exit`, decided by obligations (AGORA-970, AGORA-975)

`checkStmt2` is sound for every exit context `ξ` and never looks at it, so it
cannot give `exit n`'s premise `ξ.up n Γ`. `checkX` returns, beside the end
context, the obligations its exits put on `ξ`: a list of `(n, Γ)`, each to
hold as `ξ n Γ`. Its soundness: for every `ξ` meeting them, `StmtT` holds.
A scope's body hands its obligations out through `Exits.under` (the scope's
end is checked at each one, `EndOK`, and the exit goes on from
`exitScope`); a block discharges its own (`n = 0`, the context is the
block's end) and hands the rest out one level up (`Exits.blk`). An `exit`
ends in its own context; a branch that ends in an `exit` takes the other
branch's end when the exit's rule allows it (`exitToB`), as a panicking
branch does. Any statement `checkStmt2` accepts has no obligation.
-/

namespace C

open A2

/-- The obligations an exit puts on the exits context. -/
abbrev Obl := List (Nat × Ctx)

def OblOK (ξ : Exits) (E : Obl) : Prop := ∀ e ∈ E, ξ e.1 e.2

theorem OblOK.append {ξ : Exits} {E1 E2 : Obl} (h : OblOK ξ (E1 ++ E2)) : OblOK ξ E1 ∧ OblOK ξ E2 :=
  ⟨fun e he => h e (List.mem_append_left _ he), fun e he => h e (List.mem_append_right _ he)⟩

/-- Through a scope of `x`: each exit ends `x`'s scope there. -/
def oblUnder (x : Var) (E : Obl) : Obl := E.map fun e => (e.1, exitScope x e.2)

theorem oblUnder_ok {ξ : Exits} {x : Var} {E : Obl} {D : List Var}
    (hE : ∀ e ∈ E, Supported2 e.2 D) (hend : E.all (fun e => endOK2B D e.2 x) = true)
    (h : OblOK ξ (oblUnder x E)) : OblOK (ξ.under x) E := by
  intro e he
  refine ⟨endOK2B_sound (hE e he) (List.all_eq_true.mp hend e he), ?_⟩
  exact h (e.1, exitScope x e.2) (List.mem_map.mpr ⟨e, he, rfl⟩)

/-- Out of a block whose end is `Δ`: an exit of it (`0`) is from `Δ`
    itself; one further out goes one level up. -/
def oblBlkOKB (D : List Var) (Δ : Ctx) (E : Obl) : Bool :=
  E.all fun e => e.1 != 0 || D.all (fun v => e.2 v == Δ v)

def oblBlk (E : Obl) : Obl := E.filterMap fun e => match e.1 with
  | 0 => none
  | n + 1 => some (n, e.2)

theorem oblBlk_ok {ξ : Exits} {Δ : Ctx} {E : Obl} {D : List Var} (hΔ : Supported2 Δ D)
    (hE : ∀ e ∈ E, Supported2 e.2 D) (hb : oblBlkOKB D Δ E = true) (h : OblOK ξ (oblBlk E)) :
    OblOK (ξ.blk Δ) E := by
  intro ⟨n, Γe⟩ he
  cases n with
  | zero =>
    have := List.all_eq_true.mp hb _ he
    simp only [bne_self_eq_false, Bool.false_or] at this
    exact Or.inl (eq_of_agree2 (hE _ he) hΔ this)
  | succ m =>
    exact h (m, Γe) (List.mem_filterMap.mpr ⟨(m + 1, Γe), he, rfl⟩)

/-- An exit from `Γ` may end in `Δ` (`StmtT.exit`'s conditions on the two),
    decided over the domain. -/
def exitToB (D : List Var) (Γ Δ : Ctx) : Bool :=
  ctxWF2B D Δ && nameWFB D Δ && freshOKB D Δ &&
  D.all fun v => (Γ v).isSome == (Δ v).isSome &&
    (match Δ v, Γ v with
     | some E, some E0 => decide (E.mode = E0.mode) && decide (E.ty = E0.ty) &&
         (!fixedB E0 || decide (E = E0)) &&
         -- DKeep
         (!(E.dbind && E.mode.ownSlot && (decide (E.ty ≠ .int) || decide (E.mode = .rootb))) ||
           (E0.dbind && E0.mode.ownSlot && (decide (E0.ty ≠ .int) || decide (E0.mode = .rootb)) &&
             E.vdeps.all fun d => d.kind.isName || decide (d ∈ E0.vdeps))) &&
         -- DStay
         (!(E0.dbind && E0.mode.ownSlot) || (E.dbind && E.mode.ownSlot))
     | none, none => true
     | _, _ => false)

/-- What `exitToB` decides: `StmtT.exit`'s (and `StmtT.loop`'s) conditions
    on the context left from and the one ended in. -/
theorem exitToB_parts {D : List Var} {Γ Δ : Ctx}
    (hs : Supported2 Γ D) (hsΔ : Supported2 Δ D) (h : exitToB D Γ Δ = true) :
    CtxWF Δ ∧ NameWF Δ ∧ (∀ v, (Γ v).isSome = (Δ v).isSome) ∧
      (∀ v E, Δ v = some E → ∃ E0, Γ v = some E0 ∧ E.mode = E0.mode ∧ E.ty = E0.ty ∧ (E0.fixed → E = E0)) ∧
      DKeep Γ Δ [] ∧ DStay Γ Δ [] ∧ (FreshOK Γ → FreshOK Δ) := by
  simp only [exitToB, Bool.and_eq_true, List.all_eq_true] at h
  obtain ⟨⟨⟨hwf, hnw⟩, hfr⟩, hall⟩ := h
  have hv : ∀ v, ((Γ v).isSome == (Δ v).isSome) = true ∧ _ := fun v => by
    by_cases hd : v ∈ D
    · exact hall v hd
    · simp [hs v hd, hsΔ v hd]
  refine ⟨ctxWF2B_sound hsΔ hwf, nameWFB_sound hsΔ hnw, fun v => ?_, fun v E hE => ?_,
    fun v E hE hdb hos hty _ => ?_, fun v E0 hE0 hdb hos _ => ?_, fun _ => freshOKB_sound hsΔ hfr⟩
  · have := (hv v).1; simpa using this
  · have := (hv v).2; rw [hE] at this
    revert this
    cases hΓ : Γ v with
    | none => intro h; cases h
    | some E0 =>
      intro h
      simp only [Bool.and_eq_true, decide_eq_true_eq, Bool.or_eq_true, Bool.not_eq_true'] at h
      obtain ⟨⟨⟨⟨hm, ht⟩, hf⟩, _⟩, _⟩ := h
      refine ⟨E0, rfl, hm, ht, fun hfx => ?_⟩
      rcases hf with h0 | h0
      · exact absurd hfx (fixedB_sound h0)
      · exact h0
  · have := (hv v).2; rw [hE] at this
    revert this
    cases hΓ : Γ v with
    | none => intro h; cases h
    | some E0 =>
      intro h
      simp only [Bool.and_eq_true, decide_eq_true_eq, Bool.or_eq_true, Bool.not_eq_true', List.all_eq_true] at h
      obtain ⟨⟨_, hk⟩, _⟩ := h
      rcases hk with hk | hk
      · exfalso; revert hk; simp [hdb, hos]; rcases hty with h0 | h0 <;> simp [h0]
      · obtain ⟨⟨⟨hd0, ho0⟩, ht0⟩, hvd⟩ := hk
        refine ⟨E0, rfl, hd0, ho0, ?_, fun d hd hn => ?_⟩
        · rcases ht0 with h0 | h0
          · exact Or.inl h0
          · exact Or.inr h0
        · have := hvd d hd; simp [hn] at this; exact this
  · have := (hv v).2
    revert this
    cases hΔv : Δ v with
    | none => rw [hE0]; intro h; cases h
    | some E =>
      rw [hE0]
      intro h
      simp only [Bool.and_eq_true, Bool.or_eq_true, Bool.not_eq_true'] at h
      obtain ⟨_, hst⟩ := h
      rcases hst with h0 | h0
      · exfalso; simp [hdb, hos] at h0
      · exact ⟨E, rfl, h0.1, h0.2⟩

theorem exitToB_sound {P : Prog} {ξ : Exits} {D : List Var} {Γ Δ : Ctx} {F : List Var} {n : Nat}
    (hs : Supported2 Γ D) (hsΔ : Supported2 Δ D) (h : exitToB D Γ Δ = true) (hx : ξ n Γ) :
    StmtT P ξ Γ F (.exit n) Δ := by
  obtain ⟨h1, h2, h3, h4, h5, h6, h7⟩ := exitToB_parts hs hsΔ h
  exact .exit (Or.inl hx) h1 h2 h3 h4 h5 h6 h7

/-- The context a loop ends in, for the block around it: where its first
    exit of that block leaves from, or its own start when it has none. -/
def loopEnd (Γ : Ctx) : Obl → Ctx
  | [] => Γ
  | (0, Γe) :: _ => Γe
  | _ :: E => loopEnd Γ E

theorem loopEnd_supported {Γ : Ctx} {D : List Var} (hs : Supported2 Γ D) :
    ∀ {E : Obl}, (∀ e ∈ E, Supported2 e.2 D) → Supported2 (loopEnd Γ E) D
  | [], _ => hs
  | (0, Γe) :: E, h => h (0, Γe) (List.mem_cons_self ..)
  | (_ + 1, _) :: E, h => loopEnd_supported (E := E) hs (fun e he => h e (List.mem_cons_of_mem _ he))

/-- What `checkX` finds: the end context, the obligations on the exits
    context, and, for a statement that ends in an exit, that exit's depth
    and the context it leaves from (so a branch may end it elsewhere). -/
structure XR where
  Δ : Ctx
  E : Obl
  tail : Option (Nat × Ctx)

def checkX (P : Prog) (R : RhsDec) (C : CallDec) (D : List Var) : Ctx → List Var → Stmt → Option XR
  | Γ, _, .exit n => if exitToB D Γ Γ then some ⟨Γ, [(n, Γ)], some (n, Γ)⟩ else none
  | Γ, F, .seq a b =>
    match checkStmt2 P R C D Γ F (.seq a b) with
    | some Δ => some ⟨Δ, [], none⟩
    | none =>
      if b.src then
        match checkX P R C D Γ F a with
        | some ra =>
          match checkX P R C D ra.Δ F b with
          | some rb => some ⟨rb.Δ, ra.E ++ rb.E, rb.tail⟩
          | none => none
        | none => none
      else none
  | Γ, F, .block s =>
    match checkStmt2 P R C D Γ F (.block s) with
    | some Δ => some ⟨Δ, [], none⟩
    | none =>
      match checkX P R C D Γ F s with
      | some r => if oblBlkOKB D r.Δ r.E then some ⟨r.Δ, oblBlk r.E, none⟩ else none
      | none => none
  | Γ, F, .ite c a b =>
    match checkStmt2 P R C D Γ F (.ite c a b) with
    | some Δ => some ⟨Δ, [], none⟩
    | none =>
      if a.src ∧ b.src ∧ checkExpr2 Γ c then
        match checkX P R C D Γ F a, checkX P R C D Γ F b with
        | some ra, some rb =>
          if D.all (fun v => ra.Δ v == rb.Δ v) then some ⟨ra.Δ, ra.E ++ rb.E, none⟩
          else match ra.tail, rb.tail with
            | some (_, Γe), _ => if exitToB D Γe rb.Δ then some ⟨rb.Δ, ra.E ++ rb.E, none⟩ else none
            | none, some (_, Γe) => if exitToB D Γe ra.Δ then some ⟨ra.Δ, ra.E ++ rb.E, none⟩ else none
            | none, none => none
        | _, _ => none
      else none
  | Γ, F, .letv x r s =>
    match checkStmt2 P R C D Γ F (.letv x r s) with
    | some Δ => some ⟨Δ, [], none⟩
    | none =>
      if s.src ∧ Γ x = none ∧ x ∉ F then
        match R Γ F r with
        | some (E, Γ1) =>
          if decide (E.mode = .own → E.ty.holdsDtor = false) then
            match checkX P R C D (setE Γ1 x E) F s with
            | some rs =>
              if endOK2B D rs.Δ x && rs.E.all (fun e => endOK2B D e.2 x) then
                some ⟨exitScope x rs.Δ, oblUnder x rs.E, none⟩
              else none
            | none => none
          else none
        | none => none
      else none
  | Γ, F, .letcall x f args s =>
    match checkStmt2 P R C D Γ F (.letcall x f args s) with
    | some Δ => some ⟨Δ, [], none⟩
    | none =>
      if s.src ∧ Γ x = none ∧ x ∉ F ∧ dtorHeadB P f x s then
        match C Γ F f args with
        | some (E, Γ1) =>
          match checkX P R C D (setE Γ1 x E) F s with
          | some rs =>
            if endOK2B D rs.Δ x && rs.E.all (fun e => endOK2B D e.2 x) then
              some ⟨exitScope x rs.Δ, oblUnder x rs.E, none⟩
            else none
          | none => none
        | none => none
      else none
  | Γ, F, .loop s =>
    match checkStmt2 P R C D Γ F (.loop s) with
    | some Δ => some ⟨Δ, [], none⟩
    | none =>
      if s.src then
        match checkX P R C D Γ F s with
        | some rs =>
          if D.all (fun v => rs.Δ v == Γ v) && exitToB D Γ (loopEnd Γ rs.E) then
            some ⟨loopEnd Γ rs.E, rs.E, none⟩
          -- (C7w: a round that ends weaker than it started, a binding moved
          -- and given back, or not: the loop runs from the join of both)
          else if weaker2B D Γ (joinCand Γ rs.Δ) then
            match checkX P R C D (joinCand Γ rs.Δ) F s with
            | some rj =>
              if weaker2B D (joinCand Γ rs.Δ) (joinCand Γ rs.Δ) && weaker2B D rj.Δ (joinCand Γ rs.Δ) &&
                  exitToB D (joinCand Γ rs.Δ) (loopEnd (joinCand Γ rs.Δ) rj.E) then
                some ⟨loopEnd (joinCand Γ rs.Δ) rj.E, rj.E, none⟩
              else none
            | none => none
          else none
        | none => none
      else none
  | Γ, F, s =>
    match checkStmt2 P R C D Γ F s with
    | some Δ => some ⟨Δ, [], none⟩
    | none => none

/-- What `checkX` proves of a statement. -/
def XSound (P : Prog) (D : List Var) (Γ : Ctx) (F : List Var) (s : Stmt) (r : XR) : Prop :=
  Supported2 r.Δ D ∧ (∀ e ∈ r.E, Supported2 e.2 D) ∧ (∀ ξ, OblOK ξ r.E → StmtT P ξ Γ F s r.Δ) ∧
    ∀ n Γe, r.tail = some (n, Γe) → Supported2 Γe D ∧ (n, Γe) ∈ r.E ∧
      ∀ Δ', Supported2 Δ' D → exitToB D Γe Δ' = true → ∀ ξ, OblOK ξ r.E → StmtT P ξ Γ F s Δ'

theorem xsound_of_check2 {P : Prog} {R : RhsDec} {C : CallDec} {D : List Var} (hR : R.OK D) (hC : C.OK P D)
    {Γ : Ctx} {F : List Var} {s : Stmt} {Δ : Ctx} (hs : Supported2 Γ D) (hD : ∀ v ∈ s.vars, v ∈ D)
    (h : checkStmt2 P R C D Γ F s = some Δ) : XSound P D Γ F s ⟨Δ, [], none⟩ := by
  refine ⟨(checkStmt2_sound hR hC (ξ := .none) hs hD h).2, fun e he => (by cases he),
    fun ξ _ => (checkStmt2_sound hR hC hs hD h).1, fun n Γe ht => (by cases ht)⟩

theorem checkX_sound {P : Prog} {R : RhsDec} {C : CallDec} {D : List Var} (hR : R.OK D) (hC : C.OK P D) :
    ∀ {s : Stmt} {Γ : Ctx} {F : List Var} {r : XR}, Supported2 Γ D → (∀ v ∈ s.vars, v ∈ D) →
      checkX P R C D Γ F s = some r → XSound P D Γ F s r := by
  intro s
  induction s with
  | exit n =>
    intro Γ F r hs hD h
    simp only [checkX] at h
    split at h
    · rename_i hx
      simp only [Option.some.injEq] at h; subst h
      refine ⟨hs, fun e he => ?_, fun ξ hξ => exitToB_sound hs hs hx (hξ _ (List.mem_singleton_self _)),
        fun n' Γe ht => ?_⟩
      · simp only [List.mem_singleton] at he; subst he; exact hs
      · simp only [Option.some.injEq, Prod.mk.injEq] at ht; obtain ⟨rfl, rfl⟩ := ht
        exact ⟨hs, List.mem_singleton_self _, fun Δ' hΔ' hto ξ hξ =>
          exitToB_sound hs hΔ' hto (hξ _ (List.mem_singleton_self _))⟩
    · cases h
  | seq a b iha ihb =>
    intro Γ F r hs hD h
    simp only [checkX] at h
    split at h
    · rename_i Δ h0
      simp only [Option.some.injEq] at h; subst h
      exact xsound_of_check2 hR hC hs hD h0
    · split at h
      · rename_i hsrc
        split at h
        · rename_i ra hra
          split at h
          · rename_i rb hrb
            simp only [Option.some.injEq] at h; subst h
            obtain ⟨sa, ea, ta, _⟩ := iha hs (fun v hv => hD v (by simp [Stmt.vars, hv])) hra
            obtain ⟨sb, eb, tb, tlb⟩ := ihb sa (fun v hv => hD v (by simp [Stmt.vars, hv])) hrb
            refine ⟨sb, fun e he => ?_, fun ξ hξ => ?_, fun n Γe ht => ?_⟩
            · rcases List.mem_append.mp he with he | he
              · exact ea e he
              · exact eb e he
            · obtain ⟨h1, h2⟩ := OblOK.append hξ
              exact .seq hsrc (ta ξ h1) (tb ξ h2)
            · obtain ⟨hse, hm, hre⟩ := tlb n Γe ht
              refine ⟨hse, List.mem_append_right _ hm, fun Δ' hs' hto ξ hξ => ?_⟩
              obtain ⟨h1, h2⟩ := OblOK.append hξ
              exact .seq hsrc (ta ξ h1) (hre Δ' hs' hto ξ h2)
          · cases h
        · cases h
      · cases h
  | block s ih =>
    intro Γ F r hs hD h
    simp only [checkX] at h
    split at h
    · rename_i Δ h0
      simp only [Option.some.injEq] at h; subst h
      exact xsound_of_check2 hR hC hs hD h0
    · split at h
      · rename_i r0 hr0
        split at h
        · rename_i hb
          simp only [Option.some.injEq] at h; subst h
          obtain ⟨s0, e0, t0, _⟩ := ih hs (fun v hv => hD v (by simp [Stmt.vars, hv])) hr0
          refine ⟨s0, fun e he => ?_, fun ξ hξ => .block (t0 _ (oblBlk_ok s0 e0 hb hξ)), fun n Γe ht => (by cases ht)⟩
          obtain ⟨e', he', hm⟩ := List.mem_filterMap.mp he
          cases hn : e'.1 with
          | zero => simp [hn] at hm
          | succ m =>
            simp only [hn, Option.some.injEq] at hm; subst hm
            exact e0 e' he'
        · cases h
      · cases h
  | ite c a b iha ihb =>
    intro Γ F r hs hD h
    simp only [checkX] at h
    split at h
    · rename_i Δ h0
      simp only [Option.some.injEq] at h; subst h
      exact xsound_of_check2 hR hC hs hD h0
    · split at h
      · rename_i hc
        obtain ⟨ha, hb, hce⟩ := hc
        split at h
        · rename_i ra rb hra hrb
          obtain ⟨sa, ea, ta, tla⟩ := iha hs (fun v hv => hD v (by simp [Stmt.vars, hv])) hra
          obtain ⟨sb, eb, tb, tlb⟩ := ihb hs (fun v hv => hD v (by simp [Stmt.vars, hv])) hrb
          have hE : ∀ e ∈ ra.E ++ rb.E, Supported2 e.2 D := fun e he => by
            rcases List.mem_append.mp he with he | he
            · exact ea e he
            · exact eb e he
          split at h
          · rename_i hag
            simp only [Option.some.injEq] at h; subst h
            have heq := eq_of_agree2 sa sb hag
            refine ⟨sa, hE, fun ξ hξ => ?_, fun n Γe ht => (by cases ht)⟩
            obtain ⟨h1, h2⟩ := OblOK.append hξ
            exact .ite ha hb (checkExpr2_sound hce) (ta ξ h1) (heq ▸ tb ξ h2)
          · split at h
            · rename_i n Γe hta
              split at h
              · rename_i hto
                simp only [Option.some.injEq] at h; subst h
                obtain ⟨hse, _, hre⟩ := tla n Γe hta
                refine ⟨sb, hE, fun ξ hξ => ?_, fun n' Γe' ht => (by cases ht)⟩
                obtain ⟨h1, h2⟩ := OblOK.append hξ
                exact .ite ha hb (checkExpr2_sound hce) (hre rb.Δ sb hto ξ h1) (tb ξ h2)
              · cases h
            · rename_i n Γe hta htb
              split at h
              · rename_i hto
                simp only [Option.some.injEq] at h; subst h
                obtain ⟨hse, _, hre⟩ := tlb n Γe htb
                refine ⟨sa, hE, fun ξ hξ => ?_, fun n' Γe' ht => (by cases ht)⟩
                obtain ⟨h1, h2⟩ := OblOK.append hξ
                exact .ite ha hb (checkExpr2_sound hce) (ta ξ h1) (hre ra.Δ sa hto ξ h2)
              · cases h
            · cases h
        · cases h
      · cases h
  | letv x r s ih =>
    intro Γ F rr hs hD h
    simp only [checkX] at h
    split at h
    · rename_i Δ h0
      simp only [Option.some.injEq] at h; subst h
      exact xsound_of_check2 hR hC hs hD h0
    · split at h
      · rename_i hc
        obtain ⟨hsrc, hx, hF⟩ := hc
        split at h
        · rename_i E Γ1 hr
          split at h
          · rename_i hnd
            split at h
            · rename_i rs hrs
              split at h
              · rename_i he
                simp only [Option.some.injEq] at h; subst h
                simp only [Bool.and_eq_true] at he
                obtain ⟨hend, hendE⟩ := he
                obtain ⟨hrt, hs1⟩ := hR Γ F r E Γ1 hs (fun v hv => hD v (by simp [Stmt.vars, hv])) hr
                obtain ⟨s0, e0, t0, _⟩ := ih (supported2_setE hs1 (hD x (by simp [Stmt.vars])) E)
                  (fun v hv => hD v (by simp [Stmt.vars, hv])) hrs
                refine ⟨supported2_exitScope s0 x, fun e he => ?_, fun ξ hξ => ?_, fun n Γe ht => (by cases ht)⟩
                · obtain ⟨e', he', rfl⟩ := List.mem_map.mp he
                  exact supported2_exitScope (e0 e' he') x
                · exact .letv hsrc hx hF hrt (t0 _ (oblUnder_ok e0 hendE hξ)) (endOK2B_sound s0 hend)
                    (of_decide_eq_true hnd)
              · cases h
            · cases h
          · cases h
        · cases h
      · cases h
  | letcall x f args s ih =>
    intro Γ F rr hs hD h
    simp only [checkX] at h
    split at h
    · rename_i Δ h0
      simp only [Option.some.injEq] at h; subst h
      exact xsound_of_check2 hR hC hs hD h0
    · split at h
      · rename_i hc
        obtain ⟨hsrc, hx, hF, hdk⟩ := hc
        split at h
        · rename_i E Γ1 hcall
          split at h
          · rename_i rs hrs
            split at h
            · rename_i he
              simp only [Option.some.injEq] at h; subst h
              simp only [Bool.and_eq_true] at he
              obtain ⟨hend, hendE⟩ := he
              obtain ⟨hct, hs1⟩ := hC Γ F f args E Γ1 hs (fun a ha => hD a (by simp [Stmt.vars, ha])) hcall
              obtain ⟨s0, e0, t0, _⟩ := ih (supported2_setE hs1 (hD x (by simp [Stmt.vars])) E)
                (fun v hv => hD v (by simp [Stmt.vars, hv])) hrs
              refine ⟨supported2_exitScope s0 x, fun e he => ?_, fun ξ hξ => ?_, fun n Γe ht => (by cases ht)⟩
              · obtain ⟨e', he', rfl⟩ := List.mem_map.mp he
                exact supported2_exitScope (e0 e' he') x
              · exact .letcall hsrc hx hF hct (t0 _ (oblUnder_ok e0 hendE hξ)) (endOK2B_sound s0 hend)
                  (dtorHeadB_sound hdk)
            · cases h
          · cases h
        · cases h
      · cases h
  | loop s ih =>
    intro Γ F r hs hD h
    simp only [checkX] at h
    split at h
    · rename_i Δ h0
      simp only [Option.some.injEq] at h; subst h
      exact xsound_of_check2 hR hC hs hD h0
    · split at h
      · rename_i hsrc
        split at h
        · rename_i rs hrs
          split at h
          · rename_i hc
            simp only [Bool.and_eq_true] at hc
            obtain ⟨hag, hto⟩ := hc
            simp only [Option.some.injEq] at h; subst h
            obtain ⟨s0, e0, t0, _⟩ := ih hs (fun v hv => hD v (by simp [Stmt.vars, hv])) hrs
            have heq := eq_of_agree2 s0 hs hag
            have hsl := loopEnd_supported hs e0
            obtain ⟨h1, h2, h3, h4, h5, h6, h7⟩ := exitToB_parts hs hsl hto
            refine ⟨hsl, e0, fun ξ hξ => ?_, fun n Γe ht => (by cases ht)⟩
            exact .loop hsrc (heq ▸ t0 ξ hξ) h1 h2 h3 h4 h5 h6 h7
          · split at h
            · rename_i hwj
              split at h
              · rename_i rj hrj
                split at h
                · rename_i hc
                  simp only [Bool.and_eq_true] at hc
                  obtain ⟨⟨hjj, hwd⟩, hto⟩ := hc
                  simp only [Option.some.injEq] at h; subst h
                  have sJ := joinCand_supported (Δb := rs.Δ) hs
                  obtain ⟨s0, e0, t0, _⟩ := ih sJ (fun v hv => hD v (by simp [Stmt.vars, hv])) hrj
                  have hsl := loopEnd_supported sJ e0
                  obtain ⟨h1, h2, h3, h4, h5, h6, h7⟩ := exitToB_parts sJ hsl hto
                  refine ⟨hsl, e0, fun ξ hξ => ?_, fun n Γe ht => (by cases ht)⟩
                  exact .sub (weaker2B_sound hs sJ hwj)
                    (.loop hsrc (.sub (weaker2B_sound sJ sJ hjj) (t0 ξ hξ)
                      (Or.inr (weaker2B_sound s0 sJ hwd))) h1 h2 h3 h4 h5 h6 h7)
                    (Or.inl rfl)
                · cases h
              · cases h
            · cases h
        · cases h
      · cases h
  | _ =>
    intro Γ F r hs hD h
    simp only [checkX] at h
    split at h
    · rename_i Δ h0
      simp only [Option.some.injEq] at h; subst h
      exact xsound_of_check2 hR hC hs hD h0
    · cases h

end C
