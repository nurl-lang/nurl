module

public import C.A2Call

@[expose] public section

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

/-- `Exits.underD`'s clause on the binding at an exit, decided: no borrowed
    parameter, and a `letd`'s if its type holds views. -/
def underDB (Γ : Ctx) (x : Var) : Bool :=
  match Γ x with
  | some E => decide (E.mode ≠ .rootb) && (!E.ty.holdsView || E.dbind)
  | none => true

theorem underDB_sound {Γ : Ctx} {x : Var} (h : underDB Γ x = true) :
    ∀ E, Γ x = some E → E.mode ≠ .rootb ∧ (E.ty.holdsView = true → E.dbind = true) := by
  intro E hE
  simp only [underDB, hE, Bool.and_eq_true, decide_eq_true_eq, Bool.or_eq_true, Bool.not_eq_true'] at h
  obtain ⟨hm, hv⟩ := h
  refine ⟨hm, fun hh => ?_⟩
  rcases hv with hv | hv
  · rw [hh] at hv; cases hv
  · exact hv

/-- Through a destructor frame of `x` (`letd`): as `oblUnder_ok`, with
    `Exits.underD`'s clause on `x` at each exit. -/
theorem oblUnderD_ok {ξ : Exits} {x : Var} {E : Obl} {D : List Var}
    (hE : ∀ e ∈ E, Supported2 e.2 D) (hend : E.all (fun e => endOK2B D e.2 x && underDB e.2 x) = true)
    (h : OblOK ξ (oblUnder x E)) : OblOK (ξ.underD x) E := by
  intro e he
  have := List.all_eq_true.mp hend e he
  simp only [Bool.and_eq_true] at this
  refine ⟨endOK2B_sound (hE e he) this.1, underDB_sound this.2, ?_⟩
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

/-- With no exit of the block's own, the block's exits are its body's, one
    level up, whatever its end. -/
theorem oblBlk_noZero {ξ : Exits} {Δ : Ctx} {E : Obl} (hz : ∀ e ∈ E, e.1 ≠ 0) (h : OblOK ξ (oblBlk E)) :
    OblOK (ξ.blk Δ) E := by
  intro ⟨n, Γe⟩ he
  cases n with
  | zero => exact absurd rfl (hz _ he)
  | succ m => exact h (m, Γe) (List.mem_filterMap.mpr ⟨(m + 1, Γe), he, rfl⟩)

/-- AGORA-980 follow-up: a block's end joined with the contexts its own
    exits (`0`) leave from, as an `ite`'s arms are joined. -/
def blkJoin (Δ : Ctx) : Obl → Ctx
  | [] => Δ
  | (0, Γe) :: E => blkJoin (joinCand Δ Γe) E
  | _ :: E => blkJoin Δ E

theorem blkJoin_supported {D : List Var} {Δ : Ctx} (hΔ : Supported2 Δ D) :
    ∀ {E : Obl}, Supported2 (blkJoin Δ E) D
  | [] => hΔ
  | (0, _) :: E => blkJoin_supported (E := E) (joinCand_supported hΔ)
  | (_ + 1, _) :: E => blkJoin_supported (E := E) hΔ

/-- ... each of its exits reaching an end weaker than its own context
    (`Exits.blk`'s `Weaker`), decided. -/
def oblBlkWkB (D : List Var) (Δ : Ctx) (E : Obl) : Bool :=
  E.all fun e => e.1 != 0 || weaker2B D e.2 Δ

theorem oblBlkWk_ok {ξ : Exits} {Δ : Ctx} {E : Obl} {D : List Var} (hΔ : Supported2 Δ D)
    (hE : ∀ e ∈ E, Supported2 e.2 D) (hb : oblBlkWkB D Δ E = true) (h : OblOK ξ (oblBlk E)) :
    OblOK (ξ.blk Δ) E := by
  intro ⟨n, Γe⟩ he
  cases n with
  | zero =>
    have := List.all_eq_true.mp hb _ he
    simp only [bne_self_eq_false, Bool.false_or] at this
    exact Or.inr (weaker2B_sound (hE _ he) hΔ this)
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

/-- The statement contains an `exit`. `checkStmt2` decides no exit, so it
    refuses every such statement: `checkX` does not ask it first (`pre2`),
    and a binding's body is not scanned once per binding around an exit
    (github#2242's review, A2Exit l.204). -/
def hasExit : Stmt → Bool
  | .exit _ => true
  | .seq a b => hasExit a || hasExit b
  | .ite _ a b => hasExit a || hasExit b
  | .letv _ _ s | .letcall _ _ _ s | .while _ s | .scope _ s | .rbind _ s | .frozen _ s
  | .letrec _ _ s | .catchR _ _ s | .unpair _ _ _ s | .callc _ _ _ _ _ s | .letd _ _ _ s
  | .scopeD _ _ s | .withLock _ _ s | .scopeL _ _ _ s | .withElem _ _ _ s | .callcE _ _ _ _ s
  | .block s | .loop s | .takeB _ _ _ s => hasExit s
  | .skip | .assign _ _ | .push _ _ | .free _ | .panic | .edit _ _ _ | .insert _ _ _ => false

/-- The statement contains a `loop` (whose weakening round is handled by
    `checkX` rather than `checkStmt2`). -/
def hasLoop : Stmt → Bool
  | .loop _ => true
  | .seq a b => hasLoop a || hasLoop b
  | .ite _ a b => hasLoop a || hasLoop b
  | .letv _ _ s | .letcall _ _ _ s | .while _ s | .scope _ s | .rbind _ s | .frozen _ s
  | .letrec _ _ s | .catchR _ _ s | .unpair _ _ _ s | .callc _ _ _ _ _ s | .letd _ _ _ s
  | .scopeD _ _ s | .withLock _ _ s | .scopeL _ _ _ s | .withElem _ _ _ s | .callcE _ _ _ _ s
  | .block s | .takeB _ _ _ s => hasLoop s
  | .exit _ | .skip | .assign _ _ | .push _ _ | .free _ | .panic | .edit _ _ _ | .insert _ _ _ => false

/-- `checkStmt2T` (wrapped to `Ctx`), asked only of a statement with no `exit`:
    `some (some Δ)` means accepted, `some none` means refused (with no `loop`
    needing `checkX`'s weakening round, so `checkX` stops immediately), `none`
    means `checkX` is needed. -/
def pre2T (P : Prog) (RT : RhsTreeDec) (C : CallDec) (D : List Var) (Γ : Ctx) (F : List Var) (s : Stmt) :
    Option (Option Ctx) :=
  if hasExit s then none
  else match checkStmt2T P RT C D (tblOf D Γ) F s with
    | some TΔ => some (some TΔ.get)
    | none => if hasLoop s then none else some none

theorem pre2T_some {P : Prog} {RT : RhsTreeDec} {C : CallDec} {D : List Var} {Γ : Ctx} {F : List Var} {s : Stmt}
    {Δ : Ctx} (h : pre2T P RT C D Γ F s = some (some Δ)) :
    ∃ TΔ, checkStmt2T P RT C D (tblOf D Γ) F s = some TΔ ∧ Δ = TΔ.get := by
  unfold pre2T at h
  split at h
  · cases h
  · split at h
    · rename_i TΔ hT
      simp only [Option.some.injEq] at h
      exact ⟨TΔ, hT, h.symm⟩
    · split at h <;> cases h

/-- What `checkX` finds: the end context, the obligations on the exits
    context, and, for a statement that ends in an exit, that exit's depth
    and the context it leaves from (so a branch may end it elsewhere). -/
structure XR where
  Δ : Ctx
  E : Obl
  tail : Option (Nat × Ctx)

/-- AGORA-994: the exit a block ends in, one level up: its body's, when the
    body ends in an exit further out and has no exit of the block's own. -/
def blkTail (r : XR) : Option (Nat × Ctx) :=
  match r.tail with
  | some (m + 1, Γe) => if r.E.all (fun e => e.1 != 0) then some (m, Γe) else none
  | _ => none

theorem blkTail_some {r : XR} {n : Nat} {Γe : Ctx} (h : blkTail r = some (n, Γe)) :
    r.tail = some (n + 1, Γe) ∧ ∀ e ∈ r.E, e.1 ≠ 0 := by
  unfold blkTail at h
  split at h
  · rename_i m Γ0 ht
    split at h
    · rename_i hall
      simp only [Option.some.injEq, Prod.mk.injEq] at h; obtain ⟨rfl, rfl⟩ := h
      refine ⟨ht, fun e he => ?_⟩
      have := List.all_eq_true.mp hall e he
      simpa using this
    · cases h
  · cases h

def checkXT (P : Prog) (RT : RhsTreeDec) (R : RhsDec) (C : CallDec) (D : List Var) : Ctx → List Var → Stmt → Option XR
  | Γ, _, .exit n => if exitToB D Γ Γ then some ⟨Γ, [(n, Γ)], some (n, Γ)⟩ else none
  | Γ, F, .seq a b =>
    match pre2T P RT C D Γ F (.seq a b) with
    | some (some Δ) => some ⟨Δ, [], none⟩
    | some none => none
    | none =>
      if b.src then
        match checkXT P RT R C D Γ F a with
        | some ra =>
          match checkXT P RT R C D ra.Δ F b with
          | some rb => some ⟨rb.Δ, ra.E ++ rb.E, rb.tail⟩
          | none => none
        | none => none
      else none
  | Γ, F, .block s =>
    match pre2T P RT C D Γ F (.block s) with
    | some (some Δ) => some ⟨Δ, [], none⟩
    | some none => none
    | none =>
      match checkXT P RT R C D Γ F s with
      | some r =>
        if oblBlkOKB D r.Δ r.E then
          -- (AGORA-994: a body with no exit of the block's own that ends in an
          -- exit further out makes the block end in it, one level up)
          some ⟨r.Δ, oblBlk r.E, blkTail r⟩
        -- (AGORA-980 follow-up: an exit of the block from a context the end
        -- may be weakened to, `Exits.blk`: the end joined with the exits',
        -- as an `ite`'s arms are; a `return` from inside a loop beside a
        -- fall-off result)
        else if ctxWF2B D Γ && nameWFB D Γ && weaker2B D r.Δ (blkJoin r.Δ r.E) &&
            oblBlkWkB D (blkJoin r.Δ r.E) r.E then
          some ⟨blkJoin r.Δ r.E, oblBlk r.E, none⟩
        else none
      | none => none
  | Γ, F, .ite c a b =>
    match pre2T P RT C D Γ F (.ite c a b) with
    | some (some Δ) => some ⟨Δ, [], none⟩
    | some none => none
    | none =>
      if a.src ∧ b.src ∧ checkExpr2 Γ c then
        match checkXT P RT R C D Γ F a, checkXT P RT R C D Γ F b with
        | some ra, some rb =>
          if D.all (fun v => ra.Δ v == rb.Δ v) then some ⟨ra.Δ, ra.E ++ rb.E, none⟩
          -- (a direct panic arm first, into the other arm's end, as
          -- checkStmt2's: an exit arm's own obligation stays as it is;
          -- github#2242's review)
          else if isPanic a && panicToB D Γ rb.Δ then some ⟨rb.Δ, ra.E ++ rb.E, none⟩
          else if isPanic b && panicToB D Γ ra.Δ then some ⟨ra.Δ, ra.E ++ rb.E, none⟩
          else match ra.tail, rb.tail with
            -- (both arms end in an exit and the first leaves the innermost
            -- block: that block's end is its context, so the second arm is
            -- retargeted there first, not the first to the second's;
            -- github#2242's review, A2Exit l.193)
            | some (0, Γea), some (_, Γeb) =>
              if exitToB D Γeb ra.Δ then some ⟨ra.Δ, ra.E ++ rb.E, none⟩
              else if exitToB D Γea rb.Δ then some ⟨rb.Δ, ra.E ++ rb.E, none⟩ else none
            | some (_, Γe), _ => if exitToB D Γe rb.Δ then some ⟨rb.Δ, ra.E ++ rb.E, none⟩ else none
            | none, some (_, Γe) => if exitToB D Γe ra.Δ then some ⟨ra.Δ, ra.E ++ rb.E, none⟩ else none
            -- (C7w: the arms' ends joined by weakening, as `checkStmt2`'s)
            | none, none =>
              match joinIte2 D Γ ra.Δ rb.Δ with
              | some J => some ⟨J, ra.E ++ rb.E, none⟩
              | none => none
        | _, _ => none
      else none
  | Γ, F, .letv x r s =>
    match pre2T P RT C D Γ F (.letv x r s) with
    | some (some Δ) => some ⟨Δ, [], none⟩
    | some none => none
    | none =>
      if s.src ∧ Γ x = none ∧ x ∉ F then
        match R Γ F r with
        | some (E, Γ1) =>
          if decide (E.mode = .own → E.ty.holdsDtor = false) then
            match checkXT P RT R C D (setE Γ1 x E) F s with
            | some rs =>
              if rs.E.all (fun e => endOK2B D e.2 x) then
                match exitScopeStep D rs.Δ x with
                | some Δ' => some ⟨Δ', oblUnder x rs.E, none⟩
                | none => none
              else none
            | none => none
          else none
        | none => none
      else none
  | Γ, F, .scope x s =>
    -- (a run-time scope's body may exit: each exit ends `x`'s scope as its
    -- end does; github#2242's review)
    match pre2T P RT C D Γ F (.scope x s) with
    | some (some Δ) => some ⟨Δ, [], none⟩
    | some none => none
    | none =>
      match Γ x with
      | some E =>
        if decide (E.mode ≠ .rootb) && decide (x ∉ F) then
          match checkXT P RT R C D Γ F s with
          | some rs =>
            if endOK2B D rs.Δ x && rs.E.all (fun e => endOK2B D e.2 x) then
              some ⟨exitScope x rs.Δ, oblUnder x rs.E, none⟩
            else none
          | none => none
        else none
      | none => none
  | Γ, F, .letd x f r s =>
    -- (a destructor frame's body may exit: each exit ends `x`'s scope as its
    -- end does, under `Exits.underD`; AGORA-975)
    match pre2T P RT C D Γ F (.letd x f r s) with
    | some (some Δ) => some ⟨Δ, [], none⟩
    | some none => none
    | none =>
      if s.src ∧ Γ x = none ∧ x ∉ F ∧ x ∉ s.assigns then
        match R Γ F r with
        | some (E, Γ1) =>
          match letdTys f E.ty with
          | some (t, τ) =>
            if decide (E.mode = .own) && t.isStruct && !t.hasFn &&
                letdFnB P f t E.ty x s && takeOKB P Γ r then
              match checkXT P RT R C D (setE Γ1 x (Entry.arm { E with ty := τ, held := E.held })) F s with
              | some rs =>
                if endOK2B D rs.Δ x && rs.E.all (fun e => endOK2B D e.2 x && underDB e.2 x) then
                  some ⟨exitScope x rs.Δ, oblUnder x rs.E, none⟩
                else none
              | none => none
            else none
          | none => none
        | none => none
      else none
  | Γ, F, .letcall x f args s =>
    match pre2T P RT C D Γ F (.letcall x f args s) with
    | some (some Δ) => some ⟨Δ, [], none⟩
    | some none => none
    | none =>
      if s.src ∧ Γ x = none ∧ x ∉ F ∧ dtorHeadB P f x s then
        match C Γ F f args with
        | some (E, Γ1) =>
          match checkXT P RT R C D (ctxOfTbl <| settleL2 D (x :: args) (setE Γ1 x E)) F s with
          | some rs =>
            if endOK2B D rs.Δ x && rs.E.all (fun e => endOK2B D e.2 x) then
              some ⟨exitScope x rs.Δ, oblUnder x rs.E, none⟩
            else none
          | none => none
        | none => none
      else none
  | Γ, F, .loop s =>
    match pre2T P RT C D Γ F (.loop s) with
    | some (some Δ) => some ⟨Δ, [], none⟩
    | some none => none
    | none =>
      if s.src then
        match checkXT P RT R C D Γ F s with
        | some rs =>
          if D.all (fun v => rs.Δ v == Γ v) && exitToB D Γ (loopEnd Γ rs.E) then
            some ⟨loopEnd Γ rs.E, rs.E, none⟩
          -- (C7w: a round that ends weaker than it started, a binding moved
          -- and given back, or not: the loop runs from the join of both)
          else if weaker2B D Γ (ctxOfList (joinTbl D Γ rs.Δ)) then
            match checkXT P RT R C D (ctxOfList (joinTbl D Γ rs.Δ)) F s with
            | some rj =>
              if weaker2B D (ctxOfList (joinTbl D Γ rs.Δ)) (ctxOfList (joinTbl D Γ rs.Δ)) && weaker2B D rj.Δ (ctxOfList (joinTbl D Γ rs.Δ)) &&
                  exitToB D (ctxOfList (joinTbl D Γ rs.Δ)) (loopEnd (ctxOfList (joinTbl D Γ rs.Δ)) rj.E) then
                some ⟨loopEnd (ctxOfList (joinTbl D Γ rs.Δ)) rj.E, rj.E, none⟩
              else none
            | none => none
          else none
        | none => none
      else none
  | Γ, F, s =>
    match checkStmt2T P RT C D (tblOf D Γ) F s with
    | some TΔ => some ⟨TΔ.get, [], none⟩
    | none => none

def checkX (P : Prog) (R : RhsDec) (C : CallDec) (D : List Var) : Ctx → List Var → Stmt → Option XR :=
  checkXT P (rhsTreeOf D R) R C D

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

theorem xsound_of_check2T {P : Prog} {RT : RhsTreeDec} {C : CallDec} {D : List Var} (hRT : RT.OK D) (hC : C.OK P D)
    {Γ : Ctx} {F : List Var} {s : Stmt} {TΔ : CtxT Entry} (hs : Supported2 Γ D) (hD : ∀ v ∈ s.vars, v ∈ D)
    (h : checkStmt2T P RT C D (tblOf D Γ) F s = some TΔ) : XSound P D Γ F s ⟨TΔ.get, [], none⟩ := by
  have hself : (tblOf D Γ).get = Γ := ctxOfTbl_self hs
  have hsT : Supported2 (tblOf D Γ).get D := by rwa [hself]
  refine ⟨(checkStmt2T_sound hRT hC (ξ := .none) hsT hD h).2, fun e he => (by cases he),
    fun ξ _ => ?_, fun n Γe ht => (by cases ht)⟩
  have ht := (checkStmt2T_sound hRT hC (ξ := ξ) hsT hD h).1
  rwa [hself] at ht

theorem xsound_of_pre2T {P : Prog} {RT : RhsTreeDec} {C : CallDec} {D : List Var} (hRT : RT.OK D) (hC : C.OK P D)
    {Γ : Ctx} {F : List Var} {s : Stmt} {Δ : Ctx} (hs : Supported2 Γ D) (hD : ∀ v ∈ s.vars, v ∈ D)
    (h : pre2T P RT C D Γ F s = some (some Δ)) : XSound P D Γ F s ⟨Δ, [], none⟩ := by
  obtain ⟨TΔ, hT, rfl⟩ := pre2T_some h
  exact xsound_of_check2T hRT hC hs hD hT

theorem checkXT_sound {P : Prog} {RT : RhsTreeDec} {R : RhsDec} {C : CallDec} {D : List Var}
    (hRT : RT.OK D) (hR : R.OK D) (hC : C.OK P D) :
    ∀ {s : Stmt} {Γ : Ctx} {F : List Var} {r : XR}, Supported2 Γ D → (∀ v ∈ s.vars, v ∈ D) →
      checkXT P RT R C D Γ F s = some r → XSound P D Γ F s r := by
  intro s
  induction s with
  | exit n =>
    intro Γ F r hs hD h
    simp only [checkXT] at h
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
    simp only [checkXT] at h
    split at h
    · rename_i Δ h0
      simp only [Option.some.injEq] at h; subst h
      exact xsound_of_pre2T hRT hC hs hD h0
    · cases h
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
    simp only [checkXT] at h
    split at h
    · rename_i Δ h0
      simp only [Option.some.injEq] at h; subst h
      exact xsound_of_pre2T hRT hC hs hD h0
    · cases h
    · split at h
      · rename_i r0 hr0
        split at h
        · rename_i hb
          simp only [Option.some.injEq] at h; subst h
          obtain ⟨s0, e0, t0, tl0⟩ := ih hs (fun v hv => hD v (by simp [Stmt.vars, hv])) hr0
          refine ⟨s0, fun e he => ?_, fun ξ hξ => .block (t0 _ (oblBlk_ok s0 e0 hb hξ)), fun n Γe ht => ?_⟩
          · obtain ⟨e', he', hm⟩ := List.mem_filterMap.mp he
            cases hn : e'.1 with
            | zero => simp [hn] at hm
            | succ m =>
              simp only [hn, Option.some.injEq] at hm; subst hm
              exact e0 e' he'
          · -- the block ends in its body's exit, one level up
            obtain ⟨ht0, hz⟩ := blkTail_some ht
            obtain ⟨sΓ, hmem, hre⟩ := tl0 (n + 1) Γe ht0
            refine ⟨sΓ, List.mem_filterMap.mpr ⟨(n + 1, Γe), hmem, rfl⟩, fun Δ' hΔ' hto ξ hξ => ?_⟩
            exact .block (hre Δ' hΔ' hto _ (oblBlk_noZero hz hξ))
        · split at h
          · rename_i hj
            simp only [Bool.and_eq_true] at hj
            obtain ⟨⟨⟨h1, h2⟩, h3⟩, h4⟩ := hj
            simp only [Option.some.injEq] at h; subst h
            obtain ⟨s0, e0, t0, _⟩ := ih hs (fun v hv => hD v (by simp [Stmt.vars, hv])) hr0
            have sj := blkJoin_supported (E := r0.E) s0
            have wΓ := weaker_self2 hs h1 h2
            refine ⟨sj, fun e he => ?_, fun ξ hξ =>
              .block (.sub wΓ (t0 _ (oblBlkWk_ok sj e0 h4 hξ)) (Or.inr (weaker2B_sound s0 sj h3))),
              fun n Γe ht => (by cases ht)⟩
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
    simp only [checkXT] at h
    split at h
    · rename_i Δ h0
      simp only [Option.some.injEq] at h; subst h
      exact xsound_of_pre2T hRT hC hs hD h0
    · cases h
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
            · rename_i hp
              simp only [Bool.and_eq_true] at hp
              simp only [Option.some.injEq] at h; subst h
              have hap := isPanic_eq hp.1
              subst hap
              refine ⟨sb, hE, fun ξ hξ => ?_, fun n Γe ht => (by cases ht)⟩
              obtain ⟨_, h2⟩ := OblOK.append hξ
              exact .ite ha hb (checkExpr2_sound hce) (panicToB_sound hs sb hp.2) (tb ξ h2)
            · split at h
              · rename_i _ hp
                simp only [Bool.and_eq_true] at hp
                simp only [Option.some.injEq] at h; subst h
                have hbp := isPanic_eq hp.1
                subst hbp
                refine ⟨sa, hE, fun ξ hξ => ?_, fun n Γe ht => (by cases ht)⟩
                obtain ⟨h1, _⟩ := OblOK.append hξ
                exact .ite ha hb (checkExpr2_sound hce) (ta ξ h1) (panicToB_sound hs sa hp.2)
              · split at h
                · rename_i Γea m Γeb hta htb
                  split at h
                  · rename_i hto
                    simp only [Option.some.injEq] at h; subst h
                    obtain ⟨_, _, hre⟩ := tlb m Γeb htb
                    refine ⟨sa, hE, fun ξ hξ => ?_, fun n' Γe' ht => (by cases ht)⟩
                    obtain ⟨h1, h2⟩ := OblOK.append hξ
                    exact .ite ha hb (checkExpr2_sound hce) (ta ξ h1) (hre ra.Δ sa hto ξ h2)
                  · split at h
                    · rename_i _ hto
                      simp only [Option.some.injEq] at h; subst h
                      obtain ⟨_, _, hre⟩ := tla 0 Γea hta
                      refine ⟨sb, hE, fun ξ hξ => ?_, fun n' Γe' ht => (by cases ht)⟩
                      obtain ⟨h1, h2⟩ := OblOK.append hξ
                      exact .ite ha hb (checkExpr2_sound hce) (hre rb.Δ sb hto ξ h1) (tb ξ h2)
                    · cases h
                · rename_i n Γe hta _
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
                · split at h
                  · rename_i J hj
                    simp only [Option.some.injEq] at h; subst h
                    obtain ⟨sj, wΓ, wa, wb⟩ := joinIte2_sound hs sa sb hj
                    refine ⟨sj, hE, fun ξ hξ => ?_, fun n' Γe' ht => (by cases ht)⟩
                    obtain ⟨k1, k2⟩ := OblOK.append hξ
                    exact .ite ha hb (checkExpr2_sound hce)
                      (.sub wΓ (ta ξ k1) (Or.inr wa))
                      (.sub wΓ (tb ξ k2) (Or.inr wb))
                  · cases h
        · cases h
      · cases h
  | letv x r s ih =>
    intro Γ F rr hs hD h
    simp only [checkXT] at h
    split at h
    · rename_i Δ h0
      simp only [Option.some.injEq] at h; subst h
      exact xsound_of_pre2T hRT hC hs hD h0
    · cases h
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
              · rename_i hendE
                split at h
                · rename_i Δ' hstep
                  simp only [Option.some.injEq] at h; subst h
                  obtain ⟨hrt, hs1⟩ := hR Γ F r E Γ1 hs (fun v hv => hD v (by simp [Stmt.vars, hv])) hr
                  obtain ⟨s0, e0, t0, _⟩ := ih (supported2_setE hs1 (hD x (by simp [Stmt.vars])) E)
                    (fun v hv => hD v (by simp [Stmt.vars, hv])) hrs
                  obtain ⟨hend, rfl⟩ := exitScopeStep_sound s0 hstep
                  refine ⟨supported2_exitScope s0 x, fun e he => ?_, fun ξ hξ => ?_, fun n Γe ht => (by cases ht)⟩
                  · obtain ⟨e', he', rfl⟩ := List.mem_map.mp he
                    exact supported2_exitScope (e0 e' he') x
                  · exact .letv hsrc hx hF hrt (t0 _ (oblUnder_ok e0 hendE hξ)) hend
                      (of_decide_eq_true hnd)
                · cases h
              · cases h
            · cases h
          · cases h
        · cases h
      · cases h
  | scope x s ih =>
    intro Γ F rr hs hD h
    simp only [checkXT] at h
    split at h
    · rename_i Δ h0
      simp only [Option.some.injEq] at h; subst h
      exact xsound_of_pre2T hRT hC hs hD h0
    · cases h
    · split at h
      · rename_i E hE
        split at h
        · rename_i hc
          simp only [Bool.and_eq_true, decide_eq_true_eq] at hc
          split at h
          · rename_i rs hrs
            split at h
            · rename_i he
              simp only [Option.some.injEq] at h; subst h
              simp only [Bool.and_eq_true] at he
              obtain ⟨hend, hendE⟩ := he
              obtain ⟨s0, e0, t0, _⟩ := ih hs (fun v hv => hD v (by simp [Stmt.vars, hv])) hrs
              refine ⟨supported2_exitScope s0 x, fun e he => ?_, fun ξ hξ => ?_, fun n Γe ht => (by cases ht)⟩
              · obtain ⟨e', he', rfl⟩ := List.mem_map.mp he
                exact supported2_exitScope (e0 e' he') x
              · exact .scope ⟨E, hE, hc.1⟩ hc.2 (t0 _ (oblUnder_ok e0 hendE hξ)) (endOK2B_sound s0 hend)
            · cases h
          · cases h
        · cases h
      · cases h
  | letd x f r s ih =>
    intro Γ F rr hs hD h
    simp only [checkXT] at h
    split at h
    · rename_i Δ h0
      simp only [Option.some.injEq] at h; subst h
      exact xsound_of_pre2T hRT hC hs hD h0
    · cases h
    · split at h
      · rename_i hc
        obtain ⟨hsrc, hx, hF, hna⟩ := hc
        split at h
        · rename_i E Γ1 hr
          split at h
          · rename_i t τ hty
            split at h
            · rename_i hc2
              simp only [Bool.and_eq_true, decide_eq_true_eq, Bool.not_eq_true'] at hc2
              obtain ⟨⟨⟨⟨hm, hst⟩, hfn⟩, hdt⟩, htk⟩ := hc2
              split at h
              · rename_i rs hrs
                split at h
                · rename_i he
                  simp only [Option.some.injEq] at h; subst h
                  simp only [Bool.and_eq_true] at he
                  obtain ⟨hend, hendE⟩ := he
                  obtain ⟨hrt, hs1⟩ := hR Γ F r E Γ1 hs (fun v hv => hD v (by simp [Stmt.vars, hv])) hr
                  obtain ⟨s0, e0, t0, _⟩ := ih (supported2_setE hs1 (hD x (by simp [Stmt.vars])) _)
                    (fun v hv => hD v (by simp [Stmt.vars, hv])) hrs
                  refine ⟨supported2_exitScope s0 x, fun e he => ?_, fun ξ hξ => ?_, fun n Γe ht => (by cases ht)⟩
                  · obtain ⟨e', he', rfl⟩ := List.mem_map.mp he
                    exact supported2_exitScope (e0 e' he') x
                  · exact .letd hsrc hx hF hrt hm (letdTys_sound hty) hst hfn
                      ⟨letdFnB_sound hdt, takeOKB_sound htk⟩ (HeldUp.refl Γ1 E)
                      (t0 _ (oblUnderD_ok e0 hendE hξ)) (endOK2B_sound s0 hend) hna
                · cases h
              · cases h
            · cases h
          · cases h
        · cases h
      · cases h
  | letcall x f args s ih =>
    intro Γ F rr hs hD h
    simp only [checkXT] at h
    split at h
    · rename_i Δ h0
      simp only [Option.some.injEq] at h; subst h
      exact xsound_of_pre2T hRT hC hs hD h0
    · cases h
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
              have hs2 := supported2_setE hs1 (hD x (by simp [Stmt.vars])) E
              obtain ⟨s0, e0, t0, _⟩ := ih (settleL2_supported _)
                (fun v hv => hD v (by simp [Stmt.vars, hv])) hrs
              refine ⟨supported2_exitScope s0 x, fun e he => ?_, fun ξ hξ => ?_, fun n Γe ht => (by cases ht)⟩
              · obtain ⟨e', he', rfl⟩ := List.mem_map.mp he
                exact supported2_exitScope (e0 e' he') x
              · exact .letcall hsrc hx hF hct (stmtT_settleIn2 hs2 _ (t0 _ (oblUnder_ok e0 hendE hξ)))
                  (endOK2B_sound s0 hend)
                  (dtorHeadB_sound hdk)
            · cases h
          · cases h
        · cases h
      · cases h
  | loop s ih =>
    intro Γ F r hs hD h
    simp only [checkXT] at h
    split at h
    · rename_i Δ h0
      simp only [Option.some.injEq] at h; subst h
      exact xsound_of_pre2T hRT hC hs hD h0
    · cases h
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
                  have sJ := joinTbl_supported D Γ rs.Δ
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
    simp only [checkXT] at h
    split at h
    · rename_i TΔ h0
      simp only [Option.some.injEq] at h; subst h
      exact xsound_of_check2T hRT hC hs hD h0
    · cases h

theorem checkX_sound {P : Prog} {R : RhsDec} {C : CallDec} {D : List Var} (hR : R.OK D) (hC : C.OK P D) :
    ∀ {s : Stmt} {Γ : Ctx} {F : List Var} {r : XR}, Supported2 Γ D → (∀ v ∈ s.vars, v ∈ D) →
      checkX P R C D Γ F s = some r → XSound P D Γ F s r :=
  checkXT_sound (rhsTreeOf_OK hR) hR hC

end C
