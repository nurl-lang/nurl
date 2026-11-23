import C.A2Panic

/-!
# C7: A2's core statements, decided (AGORA-970)

`checkStmt2` computes A2's `StmtT` for `skip`, `seq`, `letv`, `ite`,
`while`, `push`, `free` and `frozen`, whatever the exits `ξ` are. These
rules pass `ξ` on and never look at it. A scope's end asks `EndOK`
(`NoPin`, `DtorSafe` and `DbindSafe`), which is decided over the finite
domain (`endOK2B_sound`). Contexts stay inside the domain as in C1, so
joins are finite comparisons. `checkStmt2_sound` gives `StmtT`. Calls,
`letd`, closures, shares, locks, regions and the exits (`block`, `exit`,
`catchR`) follow.
-/

namespace C

open A2

theorem supported2_kill {Γ : Ctx} {D : List Var} (h : Supported2 Γ D) (e : Eff) (hv : Bool) (x : Var) :
    Supported2 (kill e hv x Γ) D := fun v hv' => by simp [kill, h v hv']

theorem supported2_setE {Γ : Ctx} {D : List Var} (h : Supported2 Γ D) {x : Var} (hx : x ∈ D) (E : Entry) :
    Supported2 (setE Γ x E) D := fun v hv => by
  have : v ≠ x := fun e => hv (e ▸ hx)
  simp [setE, upd, this, h v hv]

theorem supported2_exitScope {Γ : Ctx} {D : List Var} (h : Supported2 Γ D) (x : Var) :
    Supported2 (exitScope x Γ) D := fun v hv => by
  unfold exitScope; simp only [upd]; split
  · rfl
  · exact supported2_kill h .replace false x v hv

theorem eq_of_agree2 {Γ Δ : Ctx} {D : List Var} (h1 : Supported2 Γ D) (h2 : Supported2 Δ D)
    (h : D.all (fun v => Γ v == Δ v) = true) : Γ = Δ := by
  funext v
  by_cases hv : v ∈ D
  · have := List.all_eq_true.mp h v hv; simpa using this
  · rw [h1 v hv, h2 v hv]

theorem inferRhs2_supported {D : List Var} {Γ : Ctx} {F : List Var} {r : Rhs} {E : Entry} {Γ1 : Ctx}
    (hs : Supported2 Γ D) (hD : ∀ v ∈ r.vars, v ∈ D) (h : inferRhs2 D Γ F r = some (E, Γ1)) : Supported2 Γ1 D := by
  cases r with
  | var y =>
    simp only [inferRhs2] at h
    split at h
    · split at h
      · split at h
        · cases h; exact supported2_setE (supported2_kill hs _ _ _) (hD y (by simp [Rhs.vars])) _
        · cases h
      · cases h; exact hs
      · cases h; exact hs
      · cases h
    · cases h
  | pop y =>
    simp only [inferRhs2] at h; split at h <;> (try split at h) <;> (try split at h) <;> cases h
    exact supported2_kill hs _ _ _
  | remove y i =>
    simp only [inferRhs2] at h; split at h <;> (try split at h) <;> (try split at h) <;> cases h
    exact supported2_kill hs _ _ _
  | expr e => simp only [inferRhs2] at h; split at h <;> cases h; exact hs
  | new t => simp only [inferRhs2] at h; split at h <;> cases h; exact hs
  | borrow y =>
    simp only [inferRhs2] at h; split at h
    · split at h
      · cases h; exact hs
      · cases h
    · cases h
  | «at» y i =>
    simp only [inferRhs2] at h; split at h
    · split at h
      · split at h
        · cases h; exact hs
        · cases h
      · cases h
    · cases h
  | view y =>
    simp only [inferRhs2] at h; split at h
    · split at h
      · split at h
        · cases h
        · cases h; exact hs
      · cases h
    · cases h
  | sat y i =>
    simp only [inferRhs2] at h; split at h
    · split at h
      · split at h
        · cases h; exact hs
        · cases h
      · cases h
    · cases h
  | _ => simp [inferRhs2] at h

/-- `DbindSafe`, decided over the domain. -/
def dbindSafeB (D : List Var) (Γ : Ctx) (x : Var) : Bool :=
  D.all fun v => match Γ v with
    | some E => !E.dbind || !E.mode.ownSlot || !(decide (E.ty ≠ .int ∨ E.mode = .rootb)) ||
        E.vdeps.all (fun d => d.kind.isName || decide (d.root ≠ x))
    | none => true

theorem dbindSafeB_sound {D : List Var} {Γ : Ctx} {x : Var} (hs : Supported2 Γ D) (h : dbindSafeB D Γ x = true) :
    DbindSafe Γ x := by
  intro v E hE hd ho hk d hdd hn
  have := List.all_eq_true.mp h v (mem_of_some2 hs hE)
  rw [hE] at this
  simp only [hd, ho, Bool.not_true, Bool.false_or, Bool.or_eq_true, Bool.not_eq_true',
    decide_eq_false_iff_not] at this
  rcases this with h0 | h0
  · exact absurd hk h0
  · have := List.all_eq_true.mp h0 d hdd
    simp only [hn, Bool.false_or, decide_eq_true_eq] at this
    exact this

/-- `EndOK`, decided over the domain. -/
def endOK2B (D : List Var) (Γ : Ctx) (x : Var) : Bool :=
  noPinB D Γ x && dtorSafeB D Γ .replace false x && dbindSafeB D Γ x

theorem endOK2B_sound {D : List Var} {Γ : Ctx} {x : Var} (hs : Supported2 Γ D) (h : endOK2B D Γ x = true) :
    EndOK Γ x := by
  simp only [endOK2B, Bool.and_eq_true] at h
  exact ⟨noPinB_sound hs h.1.1, dtorSafeB_sound hs h.1.2, dbindSafeB_sound hs h.2⟩

/-- A2's `PushArg`, computed. -/
def pushArg2 (D : List Var) (Γ : Ctx) (F : List Var) (y : Var) (E : Entry) (t : Ty) : Option (List Dep × Ctx) :=
  if t.owning then
    if decide (E.mode = .own) && decide (y ∉ F) && noPinB D Γ y && dtorSafeB D Γ .replace false y then
      some (E.held, setE (kill .replace false y Γ) y { E with live := false, dtor := false })
    else none
  else match t with
    | .int => some ([], Γ)
    | .slice _ => if decide (E.mode = .bor ∨ E.mode = .rootb) then some (derive y E .self ++ E.held, Γ) else none
    | _ => none

theorem pushArg2_sound {D : List Var} {Γ : Ctx} {F : List Var} {y : Var} {E : Entry} {t : Ty} {Ds : List Dep}
    {Γ1 : Ctx} (hs : Supported2 Γ D) (h : pushArg2 D Γ F y E t = some (Ds, Γ1)) :
    PushArg Γ F y E t Ds Γ1 ∧ (y ∈ D → Supported2 Γ1 D) := by
  unfold pushArg2 at h
  split at h
  · rename_i ho
    split at h
    · rename_i hc
      simp only [Bool.and_eq_true, decide_eq_true_eq] at hc
      obtain ⟨⟨⟨hm, hF⟩, hp⟩, hd⟩ := hc
      cases h
      exact ⟨.move ho hm hF (noPinB_sound hs hp) (dtorSafeB_sound hs hd),
        fun hy => supported2_setE (supported2_kill hs _ _ _) hy _⟩
    · cases h
  · split at h
    · cases h; exact ⟨.int, fun _ => hs⟩
    · split at h
      · rename_i hc; cases h; exact ⟨.slice (of_decide_eq_true hc), fun _ => hs⟩
      · cases h
    · cases h

def subB2 (a b : List Dep) : Bool := a.all (fun d => decide (d ∈ b))

theorem subB2_sound {a b : List Dep} (h : subB2 a b = true) : a ⊆ b := fun d hd =>
  of_decide_eq_true (List.all_eq_true.mp h d hd)

/-- A decider for right-hand sides, and one for calls: the statement
    checker takes them as parameters, so C6's, C8's and C9's plug in. -/
abbrev RhsDec := Ctx → List Var → Rhs → Option (Entry × Ctx)
abbrev CallDec := Ctx → List Var → Nat → List Var → Option (Entry × Ctx)

/-- The decider's contract: sound and keeping the domain. -/
def RhsDec.OK (D : List Var) (R : RhsDec) : Prop :=
  ∀ Γ F r E Γ1, Supported2 Γ D → (∀ v ∈ r.vars, v ∈ D) → R Γ F r = some (E, Γ1) →
    RhsT Γ F r E Γ1 ∧ Supported2 Γ1 D

def CallDec.OK (P : Prog) (D : List Var) (C : CallDec) : Prop :=
  ∀ Γ F f args E Γ1, Supported2 Γ D → (∀ a ∈ args, a ∈ D) → C Γ F f args = some (E, Γ1) →
    CallT P Γ F f args E Γ1 ∧ Supported2 Γ1 D

theorem inferRhs2_OK (D : List Var) : RhsDec.OK D (inferRhs2 D) :=
  fun _ _ _ _ _ hs hD h => ⟨inferRhs2_sound hs h, inferRhs2_supported hs hD h⟩

/-- `letcall`'s destructor premise: a call handing back an owned value of a
    destructor type binds it to a `letd` first thing, and assigns it nothing. -/
def dtorHeadB (P : Prog) (f : Nat) (x : Var) (s : Stmt) : Bool :=
  match P[f]? with
  | some fn => !(fn.resOwn && fn.resTy.holdsDtor) || (decide (x ∈ s.movedFirst) && decide (x ∉ s.assigns))
  | none => true

theorem dtorHeadB_sound {P : Prog} {f : Nat} {x : Var} {s : Stmt} (h : dtorHeadB P f x s = true) :
    ∀ fn, P[f]? = some fn → fn.resOwn = true → fn.resTy.holdsDtor = true → x ∈ s.movedFirst ∧ x ∉ s.assigns := by
  intro fn hf ho hd
  unfold dtorHeadB at h
  rw [hf] at h
  simp only [ho, hd, Bool.and_self, Bool.not_true, Bool.false_or, Bool.and_eq_true, decide_eq_true_eq] at h
  exact h

def prodOf2 : Ty → Option (Ty × Ty)
  | .prod a b => some (a, b)
  | _ => none

theorem prodOf2_some {t a b : Ty} (h : prodOf2 t = some (a, b)) : t = .prod a b := by
  cases t <;> simp [prodOf2] at h; obtain ⟨rfl, rfl⟩ := h; rfl

def isPanic : Stmt → Bool
  | .panic => true
  | _ => false

theorem isPanic_eq {s : Stmt} (h : isPanic s = true) : s = .panic := by
  cases s <;> simp_all [isPanic]

/-- `TakeOK`, asked strictly: a payload taken out of an enum of a
    destructor type is refused (its glue's check is the next step). -/
def takeOKB (Γ : Ctx) (r : Rhs) : Bool :=
  match r with
  | .takel y | .taker y => match Γ y with
    | some Ey => (match Ey.ty with | .dtor _ _ => false | _ => true)
    | none => true
  | _ => true

theorem takeOKB_sound {P : Prog} {Γ : Ctx} {r : Rhs} (h : takeOKB Γ r = true) : TakeOK P Γ r := by
  intro y Ey g u hr hEy hty
  exfalso
  rcases hr with rfl | rfl <;> simp [takeOKB, hEy, hty] at h

/-- The modes an assignment may join. -/
def assignModes2 (Ex E : Entry) : Bool :=
  decide (Ex.mode = .own ∧ E.mode = .own ∨ Ex.mode = .inout .replace ∧ E.mode = .own ∨
    Ex.mode = .bor ∧ E.mode = .bor)

/-- A2's `StmtT` for the core statements and calls, computed. -/
def checkStmt2 (P : Prog) (R : RhsDec) (C : CallDec) (D : List Var) : Ctx → List Var → Stmt → Option Ctx
  | Γ, _, .skip => some Γ
  | Γ, F, .seq a b =>
    if b.src then (match checkStmt2 P R C D Γ F a with
      | some Γ1 => checkStmt2 P R C D Γ1 F b
      | none => none) else none
  | Γ, F, .letv x r s =>
    if s.src ∧ Γ x = none ∧ x ∉ F then
      match R Γ F r with
      | some (E, Γ1) =>
        if decide (E.mode = .own → E.ty.holdsDtor = false) then
          match checkStmt2 P R C D (setE Γ1 x E) F s with
          | some Δ => if endOK2B D Δ x then some (exitScope x Δ) else none
          | none => none
        else none
      | none => none
    else none
  | Γ, F, .letcall x f args s =>
    if s.src ∧ Γ x = none ∧ x ∉ F ∧ dtorHeadB P f x s then
      match C Γ F f args with
      | some (E, Γ1) =>
        match checkStmt2 P R C D (setE Γ1 x E) F s with
        | some Δ => if endOK2B D Δ x then some (exitScope x Δ) else none
        | none => none
      | none => none
    else none
  | Γ, F, .assign x r =>
    match Γ x with
    | some Ex =>
      if x ∈ F then none else
      match R Γ F r with
      | some (E, Γ1) =>
        if assignModes2 Ex E && decide (E.ty = Ex.ty) && decide (x ∉ roots E.vdeps) && (Γ1 x).isSome &&
            noPinB D Γ x && dtorSafeB D Γ1 .replace false x && !Ex.dbind && takeOKB Γ r then
          some (setE (kill .replace false x Γ1) x { E with mode := Ex.mode })
        else none
      | none => none
    | none => none
  | Γ, F, .ite c a b =>
    if a.src ∧ b.src ∧ checkExpr2 Γ c then
      match checkStmt2 P R C D Γ F a, checkStmt2 P R C D Γ F b with
      | some Δa, some Δb =>
        if D.all (fun v => Δa v == Δb v) then some Δa
        else if isPanic a && panicToB D Γ Δb then some Δb
        else if isPanic b && panicToB D Γ Δa then some Δa
        else none
      | _, _ => none
    else none
  | Γ, F, .while c s =>
    if s.src ∧ checkExpr2 Γ c then
      match checkStmt2 P R C D Γ F s with
      | some Δ => if D.all (fun v => Δ v == Γ v) then some Γ else none
      | none => none
    else none
  | Γ, F, .push x y =>
    match liveE2 Γ x, liveE2 Γ y with
    | some Ex, some Ey =>
      match vecElem2 Ex.ty with
      | some t =>
        if canDoB2 Ex.mode .realloc ∧ x ∉ F ∧ Ey.ty = t ∧ y ≠ x then
          match pushArg2 D Γ F y Ey t with
          | some (Ds, Γ1) =>
            if x ∈ roots Ds then none else
            match liveE2 Γ1 x with
            | some Ex1 =>
              if dtorSafeB D Γ1 .realloc t.holdsView x && (!Ex1.dbind || subB2 (ownHeld true t Ds) Ex1.held) then
                some (setE (kill .realloc t.holdsView x Γ1) x { Ex1 with held := Ex1.held ++ ownHeld true t Ds })
              else none
            | none => none
          | none => none
        else none
      | none => none
    | _, _ => none
  | Γ, F, .free x =>
    match liveE2 Γ x with
    | some E =>
      match vecElem2 E.ty with
      | some t =>
        if decide (E.mode = .own) && decide (x ∉ F) && endOK2B D Γ x && t.dtorFree then
          some (setE (kill .replace false x Γ) x { E with live := false, dtor := false })
        else none
      | none => none
    | none => none
  | Γ, F, .frozen z s => checkStmt2 P R C D Γ (F ++ z) s
  | Γ, _, .panic => if ctxWF2B D Γ && nameWFB D Γ then some Γ else none
  | Γ, F, .block s => checkStmt2 P R C D Γ F s
  | Γ, F, .loop s =>
    if s.src then
      match checkStmt2 P R C D Γ F s with
      | some Δ => if D.all (fun v => Δ v == Γ v) && panicToB D Γ Γ then some Γ else none
      | none => none
    else none
  | Γ, F, .unpair y x z s =>
    match Γ y with
    | some E =>
      match prodOf2 E.ty with
      | some (a, b) =>
        if s.src && E.live && canDoB2 E.mode .replace && decide (y ∉ F) && decide (Γ x = none) &&
            decide (Γ z = none) && decide (x ≠ z) && decide (x ∉ F) && decide (z ∉ F) &&
            noPinB D Γ y && dtorSafeB D Γ .replace false y &&
            (!a.holdsDtor || (decide (x ∈ s.movedFirst) && decide (x ∉ s.assigns))) &&
            (!b.holdsDtor || (decide (z ∈ s.movedFirst) && decide (z ∉ s.assigns))) then
          match checkStmt2 P R C D (setE (setE (setE (kill .replace false y Γ) y { E with live := false, dtor := false })
              x (compE E a)) z (compE E b)) F s with
          | some Δ => if endOK2B D Δ z && endOK2B D (exitScope z Δ) x then some (exitScope x (exitScope z Δ)) else none
          | none => none
        else none
      | none => none
    | none => none
  | _, _, _ => none

theorem checkStmt2_sound {P : Prog} {R : RhsDec} {C : CallDec} {D : List Var} (hR : R.OK D) (hC : C.OK P D) :
    ∀ {s : Stmt} {ξ : Exits} {Γ : Ctx} {F : List Var} {Δ : Ctx},
    Supported2 Γ D → (∀ v ∈ s.vars, v ∈ D) → checkStmt2 P R C D Γ F s = some Δ →
      StmtT P ξ Γ F s Δ ∧ Supported2 Δ D := by
  intro s
  induction s with
  | skip => intro ξ Γ F Δ hs hD h; simp [checkStmt2] at h; subst h; exact ⟨.skip, hs⟩
  | seq a b iha ihb =>
    intro ξ Γ F Δ hs hD h
    simp only [checkStmt2] at h
    split at h
    · rename_i hb
      split at h
      · rename_i Γ1 ha
        obtain ⟨ta, sa⟩ := iha (ξ := ξ) hs (fun v hv => hD v (by simp [Stmt.vars, hv])) ha
        obtain ⟨tb, sb⟩ := ihb (ξ := ξ) sa (fun v hv => hD v (by simp [Stmt.vars, hv])) h
        exact ⟨.seq hb ta tb, sb⟩
      · cases h
    · cases h
  | letv x r s ih =>
    intro ξ Γ F Δ hs hD h
    simp only [checkStmt2] at h
    split at h
    · rename_i hc
      obtain ⟨hsrc, hx, hF⟩ := hc
      split at h
      · rename_i E Γ1 hr
        split at h
        · rename_i hnd
          split at h
          · rename_i Δ0 h0
            split at h
            · rename_i he
              simp only [Option.some.injEq] at h; subst h
              obtain ⟨hrt, hs1⟩ := hR Γ F r E Γ1 hs (fun v hv => hD v (by simp [Stmt.vars, hv])) hr
              obtain ⟨t0, s0⟩ := ih (ξ := ξ.under x) (supported2_setE hs1 (hD x (by simp [Stmt.vars])) E)
                (fun v hv => hD v (by simp [Stmt.vars, hv])) h0
              exact ⟨.letv hsrc hx hF hrt t0 (endOK2B_sound s0 he) (of_decide_eq_true hnd),
                supported2_exitScope s0 x⟩
            · cases h
          · cases h
        · cases h
      · cases h
    · cases h
  | letcall x f args s ih =>
    intro ξ Γ F Δ hs hD h
    simp only [checkStmt2] at h
    split at h
    · rename_i hc
      obtain ⟨hsrc, hx, hF, hdk⟩ := hc
      split at h
      · rename_i E Γ1 hcall
        split at h
        · rename_i Δ0 h0
          split at h
          · rename_i he
            simp only [Option.some.injEq] at h; subst h
            obtain ⟨hct, hs1⟩ := hC Γ F f args E Γ1 hs (fun a ha => hD a (by simp [Stmt.vars, ha])) hcall
            obtain ⟨t0, s0⟩ := ih (ξ := ξ.under x) (supported2_setE hs1 (hD x (by simp [Stmt.vars])) E)
              (fun v hv => hD v (by simp [Stmt.vars, hv])) h0
            exact ⟨.letcall hsrc hx hF hct t0 (endOK2B_sound s0 he) (dtorHeadB_sound hdk),
              supported2_exitScope s0 x⟩
          · cases h
        · cases h
      · cases h
    · cases h
  | assign x r =>
    intro ξ Γ F Δ hs hD h
    simp only [checkStmt2] at h
    split at h
    · rename_i Ex hx
      split at h
      · cases h
      · rename_i hF
        split at h
        · rename_i E Γ1 hr
          split at h
          · rename_i hc
            simp only [Bool.and_eq_true, decide_eq_true_eq, Bool.not_eq_true'] at hc
            obtain ⟨⟨⟨⟨⟨⟨⟨hm, hty⟩, hroot⟩, hsome⟩, hp⟩, hd⟩, hdb⟩, htk⟩ := hc
            simp only [Option.some.injEq] at h; subst h
            obtain ⟨hrt, hs1⟩ := hR Γ F r E Γ1 hs (fun v hv => hD v (by simp [Stmt.vars, hv])) hr
            exact ⟨.assign hx hF (of_decide_eq_true hm) hrt hty hroot hsome (noPinB_sound hs hp)
              (dtorSafeB_sound hs1 hd) hdb (takeOKB_sound htk),
              supported2_setE (supported2_kill hs1 _ _ _) (hD x (by simp [Stmt.vars])) _⟩
          · cases h
        · cases h
    · cases h
  | ite c a b iha ihb =>
    intro ξ Γ F Δ hs hD h
    simp only [checkStmt2] at h
    split at h
    · rename_i hc
      obtain ⟨ha, hb, hce⟩ := hc
      split at h
      · rename_i Δa Δb hca hcb
        obtain ⟨ta, sa⟩ := iha (ξ := ξ) hs (fun v hv => hD v (by simp [Stmt.vars, hv])) hca
        obtain ⟨tb, sb⟩ := ihb (ξ := ξ) hs (fun v hv => hD v (by simp [Stmt.vars, hv])) hcb
        split at h
        · rename_i hag
          simp only [Option.some.injEq] at h; subst h
          have heq := eq_of_agree2 sa sb hag
          subst heq
          exact ⟨.ite ha hb (checkExpr2_sound hce) ta tb, sa⟩
        · split at h
          · rename_i hp
            simp only [Bool.and_eq_true] at hp
            simp only [Option.some.injEq] at h; subst h
            have hap := isPanic_eq hp.1
            subst hap
            exact ⟨.ite ha hb (checkExpr2_sound hce) (panicToB_sound hs sb hp.2) tb, sb⟩
          · split at h
            · rename_i _ hp
              simp only [Bool.and_eq_true] at hp
              simp only [Option.some.injEq] at h; subst h
              have hbp := isPanic_eq hp.1
              subst hbp
              exact ⟨.ite ha hb (checkExpr2_sound hce) ta (panicToB_sound hs sa hp.2), sa⟩
            · cases h
      · cases h
    · cases h
  | «while» c s ih =>
    intro ξ Γ F Δ hs hD h
    simp only [checkStmt2] at h
    split at h
    · rename_i hc
      obtain ⟨hsrc, hce⟩ := hc
      split at h
      · rename_i Δ0 h0
        split at h
        · rename_i hag
          simp only [Option.some.injEq] at h; subst h
          obtain ⟨t0, s0⟩ := ih (ξ := ξ) hs (fun v hv => hD v (by simp [Stmt.vars, hv])) h0
          have heq := eq_of_agree2 s0 hs hag
          subst heq
          exact ⟨.while hsrc (checkExpr2_sound hce) t0, hs⟩
        · cases h
      · cases h
    · cases h
  | push x y =>
    intro ξ Γ F Δ hs hD h
    simp only [checkStmt2] at h
    split at h
    · rename_i Ex Ey hEx hEy
      obtain ⟨hx, hxl⟩ := liveE2_some hEx
      obtain ⟨hy, hyl⟩ := liveE2_some hEy
      split at h
      · rename_i t ht
        split at h
        · rename_i hc
          obtain ⟨hcd, hF, hty, hne⟩ := hc
          split at h
          · rename_i Ds Γ1 hpa
            obtain ⟨hpa', hs1⟩ := pushArg2_sound hs hpa
            have hs1' := hs1 (hD y (by simp [Stmt.vars]))
            split at h
            · cases h
            · rename_i hroot
              split at h
              · rename_i Ex1 hEx1
                obtain ⟨hx1, hx1l⟩ := liveE2_some hEx1
                split at h
                · rename_i hc2
                  simp only [Bool.and_eq_true, Bool.or_eq_true, Bool.not_eq_true'] at hc2
                  obtain ⟨hds, hdb⟩ := hc2
                  simp only [Option.some.injEq] at h; subst h
                  refine ⟨.push hx hxl (vecElem2_some ht) (canDoB2_sound hcd) hF hy hyl hty hne hpa' hroot hx1 hx1l
                    (dtorSafeB_sound hs1' hds) (fun hdb' => ?_), supported2_setE (supported2_kill hs1' _ _ _)
                    (hD x (by simp [Stmt.vars])) _⟩
                  rcases hdb with h0 | h0
                  · rw [hdb'] at h0; cases h0
                  · exact subB2_sound h0
                · cases h
              · cases h
          · cases h
        · cases h
      · cases h
    · cases h
  | free x =>
    intro ξ Γ F Δ hs hD h
    simp only [checkStmt2] at h
    split at h
    · rename_i E hE
      obtain ⟨hx, hl⟩ := liveE2_some hE
      split at h
      · rename_i t ht
        split at h
        · rename_i hc
          simp only [Bool.and_eq_true, decide_eq_true_eq] at hc
          obtain ⟨⟨⟨hm, hF⟩, he⟩, hdf⟩ := hc
          simp only [Option.some.injEq] at h; subst h
          exact ⟨.free hx hl hm (vecElem2_some ht) hF (endOK2B_sound hs he) hdf,
            supported2_setE (supported2_kill hs _ _ _) (hD x (by simp [Stmt.vars])) _⟩
        · cases h
      · cases h
    · cases h
  | frozen z s ih =>
    intro ξ Γ F Δ hs hD h
    simp only [checkStmt2] at h
    obtain ⟨t0, s0⟩ := ih (ξ := .none) hs (fun v hv => hD v (by simp [Stmt.vars, hv])) h
    exact ⟨.frozen t0 (fun v hv => hv), s0⟩
  | panic =>
    intro ξ Γ F Δ hs hD h
    simp only [checkStmt2] at h
    split at h
    · rename_i hc
      simp only [Bool.and_eq_true] at hc
      simp only [Option.some.injEq] at h; subst h
      exact ⟨panic_self hs hc.1 hc.2, hs⟩
    · cases h
  | block s ih =>
    intro ξ Γ F Δ hs hD h
    simp only [checkStmt2] at h
    obtain ⟨t0, s0⟩ := ih (ξ := ξ.blk Δ) hs (fun v hv => hD v (by simp [Stmt.vars, hv])) h
    exact ⟨.block t0, s0⟩
  | loop s ih =>
    intro ξ Γ F Δ hs hD h
    simp only [checkStmt2] at h
    split at h
    · rename_i hsrc
      split at h
      · rename_i Δ0 h0
        split at h
        · rename_i hc
          simp only [Bool.and_eq_true] at hc
          simp only [Option.some.injEq] at h; subst h
          obtain ⟨t0, s0⟩ := ih (ξ := ξ) hs (fun v hv => hD v (by simp [Stmt.vars, hv])) h0
          have heq := eq_of_agree2 s0 hs hc.1
          subst heq
          obtain ⟨p1, p2, p3, p4, p5, p6, p7⟩ := panicToB_prem s0 s0 hc.2
          exact ⟨.loop hsrc t0 p1 p2 p3 p4 p5 p6 p7, s0⟩
        · cases h
      · cases h
    · cases h
  | unpair y x z s ih =>
    intro ξ Γ F Δ hs hD h
    simp only [checkStmt2] at h
    split at h
    · rename_i E hE
      split at h
      · rename_i a b hp
        split at h
        · rename_i hc
          simp only [Bool.and_eq_true, decide_eq_true_eq, Bool.or_eq_true, Bool.not_eq_true'] at hc
          obtain ⟨⟨⟨⟨⟨⟨⟨⟨⟨⟨⟨⟨hsrc, hl⟩, hcd⟩, hyF⟩, hx⟩, hz⟩, hxz⟩, hxF⟩, hzF⟩, hp1⟩, hd1⟩, hdx⟩, hdz⟩ := hc
          split at h
          · rename_i Δ0 h0
            split at h
            · rename_i he
              simp only [Bool.and_eq_true] at he
              simp only [Option.some.injEq] at h; subst h
              have hyD : y ∈ D := hD y (by simp [Stmt.vars])
              have hxD : x ∈ D := hD x (by simp [Stmt.vars])
              have hzD : z ∈ D := hD z (by simp [Stmt.vars])
              have hs1 := supported2_setE (supported2_setE (supported2_setE (supported2_kill hs .replace false y) hyD
                { E with live := false, dtor := false }) hxD (compE E a)) hzD (compE E b)
              obtain ⟨t0, s0⟩ := ih (ξ := (ξ.under x).under z) hs1 (fun v hv => hD v (by simp [Stmt.vars, hv])) h0
              refine ⟨.unpair hsrc hE hl (canDoB2_sound hcd) (Or.inl (prodOf2_some hp)) hyF hx hz hxz hxF hzF t0
                (noPinB_sound hs hp1) (dtorSafeB_sound hs hd1) (endOK2B_sound s0 he.1)
                (endOK2B_sound (supported2_exitScope s0 z) he.2) (fun hh => ?_) (fun hh => ?_),
                supported2_exitScope (supported2_exitScope s0 z) x⟩
              · rcases hdx with h0 | h0
                · rw [hh] at h0; cases h0
                · exact h0
              · rcases hdz with h0 | h0
                · rw [hh] at h0; cases h0
                · exact h0
            · cases h
          · cases h
        · cases h
      · cases h
    · cases h
  | _ => intro ξ Γ F Δ hs hD h; simp [checkStmt2] at h

end C
