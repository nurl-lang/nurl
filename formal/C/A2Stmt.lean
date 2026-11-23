import C.A2Panic
import C.A2Weaker

/-!
# C7: A2's statements, decided (AGORA-970)

`checkStmt2` computes A2's `StmtT`, whatever the exits `ξ` are, for every
statement form a function body can hold except `exit` (below):

* `skip`, `seq`, `letv`, `letcall`, `letrec`, `assign`, `unpair`, `ite`,
  `while`, `block`, `loop`, `panic`, `frozen`, `scope`, `rbind`, `scopeL`;
* `push`, `insert`, `free`; `withLock`, `withElem`;
* `letd` and `scopeD`, of a destructor type or a `Vec` nest of one;
* `takeB`, `editB` (view-free elements) and `editBV` (elements that hold
  views, closures among them; an `edit false` through a fresh borrow that
  is not held-fresh);
* `callc` and `callcE` (`¬ ThruFn` by a checked-closed set, `noThruB`).

The rules pass `ξ` on and never look at it. A scope's end asks `EndOK`
(`NoPin`, `DtorSafe` and `DbindSafe`), decided over the finite domain
(`endOK2B_sound`). Contexts stay inside the domain as in C1, so joins are
finite comparisons. `checkStmt2_sound` gives `StmtT`.

A `letd`'s or a `scopeD`'s destructor is decided as `DropFnOK`
(`dropFnOKB_sound`): a destructor that takes the value lent, or a struct's,
an enum's, an impl's or a closure's glue (`GlueOK`, `EnumGlueOK`,
`ImplGlueOK`, `ClosureGlueOK`), each one body shape over the glue
signature, with `ThruFn`'s premise from the thru-free set where the value
holds views. A value of another destructor type rebound under its parts'
glue is `LetdFn`'s second case (`letdFnB_sound`).

Out of the checker's domain: `catchR`, a run-time form only (`src = false`,
made by stepping, `recStmt`), whose premise is the heap invariant over a
concrete memory; no function body holds one. `sub` is subsumption, used by
the joins.

`exit n` is not decided here: its premise `ξ.up n Γ` asks the exits `ξ` to
take the context at the exit, and `checkStmt2` is sound for every `ξ`
without looking at it. `C/A2Exit.lean` (`checkX`) decides it, carrying the
exits as obligations on `ξ`, over `checkStmt2`.
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
theorem supported2_exitRoot {Γ : Ctx} {D : List Var} (h : Supported2 Γ D) (p : Var) (Ds : List Dep) :
    Supported2 (exitRoot p Ds Γ) D := fun v hv => by
  unfold exitRoot; simp only [upd]; split <;> simp [h v hv]

/-- `Anchored`, decided: every unbound dependency's root is frozen. -/
def anchoredB (E : Entry) (F : List Var) : Bool :=
  E.vdeps.all fun d => !(decide (d.kind.bound = .none)) || decide (d.root ∈ F)

theorem anchoredB_sound {E : Entry} {F : List Var} (h : anchoredB E F = true) : Anchored E F := by
  intro d hd hb
  simp only [anchoredB, List.all_eq_true] at h
  have := h d hd
  simp only [hb, decide_true, Bool.not_true, Bool.false_or, decide_eq_true_eq] at this
  exact this

/-- `rbind`'s end condition, decided: what the borrowed binding may change
    by name is another root, still bound as a root at the scope's end. -/
def rbindKeptB (Δ : Ctx) (p : Var) (Ds : List Dep) : Bool :=
  Ds.all fun d => decide (d.kind.bound = .none) ||
    (decide (d.root ≠ p) && match Δ d.root with | some Er => Er.mode.isRoot | none => false)

theorem rbindKeptB_sound {Δ : Ctx} {p : Var} {Ds : List Dep} (h : rbindKeptB Δ p Ds = true) :
    ∀ d ∈ Ds, d.kind.bound ≠ .none → d.root ≠ p ∧ ∃ Er, Δ d.root = some Er ∧ Er.mode.isRoot = true := by
  intro d hd hb
  simp only [rbindKeptB, List.all_eq_true] at h
  have := h d hd
  simp only [hb, decide_false, Bool.false_or, Bool.and_eq_true, decide_eq_true_eq] at this
  obtain ⟨h1, h2⟩ := this
  refine ⟨h1, ?_⟩
  revert h2
  cases hΔ : Δ d.root with
  | none => intro h2; cases h2
  | some Er => intro h2; exact ⟨Er, rfl, h2⟩

/-- `KeepOut`, decided over the domain: a name off the spine keeps its
    mode and type (a borrowed root its whole entry), and the end binds only
    names off the spine that were bound before. -/
def keepOutB (D : List Var) (Γ Δ : Ctx) (sp : List Var) : Bool :=
  D.all (fun v => match Γ v with
    | some E => decide (v ∈ sp) || (match Δ v with
      | some E' => decide (E'.mode = E.mode) && decide (E'.ty = E.ty) &&
          (!(decide (E.mode = .rootb)) || decide (E' = E))
      | none => false)
    | none => true) &&
  D.all (fun v => match Δ v with
    | some _ => decide (v ∉ sp) && (Γ v).isSome
    | none => true)

theorem keepOutB_sound {D : List Var} {Γ Δ : Ctx} {sp : List Var} (hs : Supported2 Γ D)
    (hsΔ : Supported2 Δ D) (h : keepOutB D Γ Δ sp = true) : KeepOut Γ Δ sp := by
  simp only [keepOutB, Bool.and_eq_true, List.all_eq_true] at h
  obtain ⟨h1, h2⟩ := h
  refine ⟨fun v E hE hv => ?_, fun v E' hE' => ?_⟩
  · have := h1 v (mem_of_some2 hs hE)
    rw [hE] at this
    simp only [hv, decide_false, Bool.false_or] at this
    revert this
    cases hΔ : Δ v with
    | none => intro h; cases h
    | some E' =>
      intro h
      simp only [Bool.and_eq_true, Bool.or_eq_true, Bool.not_eq_true', decide_eq_true_eq,
        decide_eq_false_iff_not] at h
      obtain ⟨⟨hm, ht⟩, hr⟩ := h
      exact ⟨E', rfl, hm, ht, fun hb => hr.resolve_left (fun hn => hn hb)⟩
  · have := h2 v (mem_of_some2 hsΔ hE')
    rw [hE'] at this
    simp only [Bool.and_eq_true, decide_eq_true_eq, Option.isSome_iff_exists] at this
    exact ⟨this.1, this.2⟩

/-- `x` is bound and live in `Γ`. -/
def liveAtB (Γ : Ctx) (x : Var) : Bool :=
  match Γ x with | some E => E.live | none => false

theorem liveAtB_sound {Γ : Ctx} {x : Var} (h : liveAtB Γ x = true) : ∃ E, Γ x = some E ∧ E.live = true := by
  unfold liveAtB at h
  revert h
  cases hx : Γ x with
  | none => intro h; cases h
  | some E => intro h; exact ⟨E, rfl, h⟩

def pushB (D : List Var) (Γ : Ctx) (F : List Var) (x y : Var) : Option Ctx :=
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

theorem pushB_sound {P : Prog} {D : List Var} {ξ : Exits} {Γ : Ctx} {F : List Var} {x y : Var} {Δ : Ctx}
    (hs : Supported2 Γ D) (hD : ∀ v ∈ (Stmt.push x y).vars, v ∈ D) (h : pushB D Γ F x y = some Δ) :
    StmtT P ξ Γ F (.push x y) Δ ∧ Supported2 Δ D := by
  simp only [pushB] at h
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

/-- The payload type of a lock or cell type. -/
def lockPay : Ty → Option Ty
  | .lk t => some t
  | .cell t => some t
  | _ => none

theorem lockPay_sound {E : Entry} {t : Ty} (h : lockPay E.ty = some t) : E.lockOf t := by
  unfold Entry.lockOf
  revert h
  cases E.ty <;> simp [lockPay]

/-- A function of the set `S` changes no elements through a borrow and
    calls only functions of `S`. -/
def thruOKFn (P : Prog) (S : List Nat) (f : Nat) : Bool :=
  match P[f]? with
  | some fn => !fn.body.hasThru && fn.body.calls.all fun g => decide (g ∈ S)
  | none => false

/-- `S` is closed: each of its functions is `thruOKFn`. -/
def thruClosedB (P : Prog) (S : List Nat) : Bool := S.all (thruOKFn P S)

/-- A closed set holds no function that changes elements through a borrow,
    directly or through a call (`ThruFn`). -/
theorem thruClosedB_sound {P : Prog} {S : List Nat} (hc : thruClosedB P S = true) :
    ∀ {f : Nat}, ThruFn P f → f ∉ S := by
  intro f ht
  induction ht with
  | here hP hb =>
    intro hf
    simp only [thruClosedB, List.all_eq_true] at hc
    have := hc _ hf
    simp only [thruOKFn, hP, hb, Bool.not_true, Bool.false_and] at this
    cases this
  | call hP hg _ ih =>
    intro hf
    apply ih
    simp only [thruClosedB, List.all_eq_true] at hc
    have := hc _ hf
    simp only [thruOKFn, hP, Bool.and_eq_true, List.all_eq_true, decide_eq_true_eq] at this
    exact this.2 _ hg

/-- The candidate thru-free set: every index, filtered once per function,
    until a round removes nothing (its fixpoint; `thruClosedB` checks the
    result, so where it stops needs no proof). -/
def thruFreeIter (P : Prog) : Nat → List Nat → List Nat
  | 0, S => S
  | n + 1, S => let S' := S.filter (thruOKFn P S); if S'.length = S.length then S else thruFreeIter P n S'

def thruFreeSet (P : Prog) : List Nat := thruFreeIter P P.length (List.range P.length)

/-- `¬ ThruFn P σ`, decided: `σ` is in the thru-free set, and that set is
    closed (checked, so its construction need not be trusted). -/
def noThruB (P : Prog) (σ : Nat) : Bool :=
  decide (σ ∈ thruFreeSet P) && thruClosedB P (thruFreeSet P)

theorem noThruB_sound {P : Prog} {σ : Nat} (h : noThruB P σ = true) : ¬ ThruFn P σ := by
  simp only [noThruB, Bool.and_eq_true, decide_eq_true_eq] at h
  exact fun ht => thruClosedB_sound h.2 ht h.1

/-- `ThruFn P f → t.holdsView = false`, decided: `t` holds no views, or `f`
    is in the closed thru-free set. -/
def thruViewB (P : Prog) (f : Nat) (t : Ty) : Bool := !t.holdsView || noThruB P f

theorem thruViewB_sound {P : Prog} {f : Nat} {t : Ty} (h : thruViewB P f t = true) :
    ThruFn P f → t.holdsView = false := by
  intro ht
  simp only [thruViewB, Bool.or_eq_true, Bool.not_eq_true'] at h
  rcases h with h | h
  · exact h
  · exact absurd ht (noThruB_sound h)

/-- `DtorOK`, decided: the destructor's signature, and `ThruFn`'s premise
    (`thruViewB`: the payload holds no views, or `f` is thru-free). -/
def dtorOKB (P : Prog) (f : Nat) (ty : Ty) : Bool :=
  match P[f]? with
  | some fn => decide (fn.params = [(.inp, ty)]) && decide (fn.resTy = .int) && !fn.resOwn &&
      decide (fn.lends = []) && decide (fn.rholds = []) && decide (fn.outHolds = []) && thruViewB P f ty
  | none => false

theorem dtorOKB_sound {P : Prog} {f : Nat} {ty : Ty} (h : dtorOKB P f ty = true) : DtorOK P f ty := by
  unfold dtorOKB at h
  revert h
  cases hf : P[f]? with
  | none => intro h; cases h
  | some fn =>
    intro h
    simp only [Bool.and_eq_true, decide_eq_true_eq, Bool.not_eq_true'] at h
    obtain ⟨⟨⟨⟨⟨⟨hp, hr⟩, ho⟩, hl⟩, hh⟩, hoh⟩, hv⟩ := h
    exact ⟨fn, hf, hp, hr, ho, hl, hh, hoh, thruViewB_sound hv⟩

/-- A nest of `Vec`s around `f`'s destructor type: its depth and struct. -/
def nestDtor (f : Nat) : Ty → Option (Nat × Ty)
  | .dtor g t => if g = f then some (0, t) else none
  | .vec u => (nestDtor f u).map fun p => (p.1 + 1, p.2)
  | _ => none

theorem nestDtor_sound {f : Nat} {u : Ty} : ∀ {n : Nat} {t : Ty}, nestDtor f u = some (n, t) →
    u = Ty.nest n (.dtor f t) := by
  induction u with
  | dtor g t' _ =>
    intro n t h
    simp only [nestDtor] at h
    split at h
    · rename_i hg; simp only [Option.some.injEq, Prod.mk.injEq] at h; obtain ⟨rfl, rfl⟩ := h; subst hg; rfl
    · cases h
  | vec u ih =>
    intro n t h
    simp only [nestDtor, Option.map_eq_some_iff] at h
    obtain ⟨⟨m, t'⟩, hm, he⟩ := h
    simp only [Prod.mk.injEq] at he; obtain ⟨rfl, rfl⟩ := he
    rw [ih hm]; rfl
  | _ => intro n t h; simp [nestDtor] at h

/-- `letd`'s types, for a value that is the struct itself or of a
    destructor type over it (its struct `t`, the binding's type `.dtor f t`;
    a destructor type other than `f`'s is `LetdFn`'s to allow, `letdFnB`),
    or a `Vec` nest of `f`'s destructor values (bound at its own type). -/
def letdTys (f : Nat) : Ty → Option (Ty × Ty)
  | .dtor _ t => some (t, .dtor f t)
  | .vec u => match nestDtor f u with
    | some (_, t) => some (t, .vec u)
    | none => none
  | a => some (a, .dtor f a)

theorem letdTys_sound {f : Nat} {a t τ : Ty} (h : letdTys f a = some (t, τ)) : LetdTy f t a τ := by
  cases a with
  | dtor g u =>
    simp only [letdTys, Option.some.injEq, Prod.mk.injEq] at h; obtain ⟨rfl, rfl⟩ := h
    exact Or.inl ⟨rfl, Or.inr ⟨g, rfl⟩⟩
  | vec u =>
    simp only [letdTys] at h
    split at h
    · rename_i n t' hn
      simp only [Option.some.injEq, Prod.mk.injEq] at h; obtain ⟨rfl, rfl⟩ := h
      exact Or.inr ⟨n, by rw [nestDtor_sound hn], rfl⟩
    · cases h
  | _ =>
    simp only [letdTys, Option.some.injEq, Prod.mk.injEq] at h; obtain ⟨rfl, rfl⟩ := h
    exact Or.inl ⟨rfl, Or.inl rfl⟩

/-- `DSelf`, decided on `x`'s entry `E`: a destructor binding with its own
    slot depends on itself by no view. -/
def dSelfB (E : Entry) (x : Var) : Bool :=
  !(E.dbind && E.mode.ownSlot && (decide (E.ty ≠ .int) || decide (E.mode = .rootb))) ||
    E.vdeps.all fun d => d.kind.isName || decide (d.root ≠ x)

theorem dSelfB_sound {Γ : Ctx} {x : Var} {E : Entry} (hE : Γ x = some E) (h : dSelfB E x = true) :
    DSelf Γ x := by
  intro E' hE' hdb hos hty d hd hn
  rw [hE] at hE'; cases hE'
  simp only [dSelfB, hdb, hos, Bool.true_and, Bool.or_eq_true, Bool.not_eq_true', List.all_eq_true,
    decide_eq_true_eq] at h
  rcases h with h | h
  · rcases hty with hty | hty
    · simp [hty] at h
    · simp [hty] at h
  · have := h d hd
    simp only [hn, decide_eq_true_eq] at this
    exact this.resolve_left (by simp)

/-- At the end, `x`, if it holds views, is still a destructor binding. -/
def viewDbindB (Δ : Ctx) (x : Var) : Bool :=
  match Δ x with | some E => !E.ty.holdsView || E.dbind | none => true

theorem viewDbindB_sound {Δ : Ctx} {x : Var} (h : viewDbindB Δ x = true) :
    ∀ E, Δ x = some E → E.ty.holdsView = true → E.dbind = true := by
  intro E hE hv
  simp only [viewDbindB, hE, hv, Bool.not_true, Bool.false_or] at h
  exact h

/-- `scopeD`'s struct, for a binding of `f`'s destructor type or a `Vec`
    nest of its values. -/
def scopeDTy (f : Nat) : Ty → Option Ty
  | .dtor g t => if g = f then some t else none
  | .vec u => (nestDtor f u).map (·.2)
  | _ => none

theorem scopeDTy_sound {f : Nat} {a t : Ty} (h : scopeDTy f a = some t) : ScopeDTy f t a := by
  cases a with
  | dtor g u =>
    simp only [scopeDTy] at h
    split at h
    · rename_i hg; simp only [Option.some.injEq] at h; subst hg; subst h; exact Or.inl rfl
    · cases h
  | vec u =>
    simp only [scopeDTy, Option.map_eq_some_iff] at h
    obtain ⟨⟨n, t'⟩, hn, he⟩ := h
    simp only at he; subst he
    exact Or.inr ⟨n, by rw [nestDtor_sound hn]⟩
  | _ => simp [scopeDTy] at h

theorem supported2_killNames {Γ : Ctx} {D : List Var} (h : Supported2 Γ D) (ds : List Dep) :
    Supported2 (killNames ds Γ) D := by
  unfold killNames
  induction ds with
  | nil => exact h
  | cons d ds ih => exact supported2_kill ih _ false _

theorem supported2_killThru {Γ : Ctx} {D : List Var} (h : Supported2 Γ D) (op : Edit) (tx : Ty)
    (P : List Dep) : Supported2 (killThru op tx P Γ) D :=
  supported2_killNames h _

/-- `HeldOK`, decided over the domain: no borrowed root holds a view or a
    handle of `r` that the effect `e` ends. -/
def heldOKB (D : List Var) (Γ : Ctx) (e : Eff) (r : Var) : Bool :=
  D.all fun p => match Γ p with
    | some E => !(decide (E.mode = .rootb)) || E.held.all fun d =>
        !(decide (d.root = r) && (decide (d.kind = .view) || decide (d.kind = .self))) || !(e.kills false d.kind)
    | none => true

theorem heldOKB_sound {D : List Var} {Γ : Ctx} {e : Eff} {r : Var} (hs : Supported2 Γ D)
    (h : heldOKB D Γ e r = true) : HeldOK Γ e r := by
  intro p E hE hm d hd hr hk
  simp only [heldOKB, List.all_eq_true] at h
  have := h p (mem_of_some2 hs hE)
  rw [hE] at this
  simp only [hm, decide_true, Bool.not_true, Bool.false_or, List.all_eq_true] at this
  have := this d hd
  simp only [hr, decide_true, Bool.true_and, Bool.or_eq_true, Bool.not_eq_true'] at this
  rcases hk with hk | hk <;> simp [hk] at this ⊢ <;> exact this

/-- `ThruOKR`, decided: every root the path reaches in memory is not
    frozen, not what is stored, bound, live or a region, allows the change's
    effect there, is viewed by no destructor it ends, is no share, and is
    held by no borrowed root it ends. -/
def thruOKRB (D : List Var) (Γ1 : Ctx) (F : List Var) (op : Edit) (tx : Ty) (Ps : List Dep) : Bool :=
  (memDeps Ps).all fun d => decide (d.root ∉ F) &&
    (match op.stored with | some y => decide (d.root ≠ y) | none => true) &&
    match Γ1 d.root with
    | some Er =>
      (Er.live || decide (Er.mode = .region)) &&
      (canDoB2 Er.mode (op.effAt d.kind (decide (Er.ty = tx)) Er.rvec) ||
        (decide (Er.mode = .region) && !((op.effAt d.kind (decide (Er.ty = tx)) Er.rvec).kills false .view))) &&
      dtorSafeB D Γ1 (op.effAt d.kind (decide (Er.ty = tx)) Er.rvec) false d.root &&
      decide (d.kind ≠ .share) &&
      heldOKB D Γ1 (op.effAt d.kind (decide (Er.ty = tx)) Er.rvec) d.root
    | none => false

theorem thruOKRB_sound {D : List Var} {Γ1 : Ctx} {F : List Var} {op : Edit} {tx : Ty} {Ps : List Dep}
    (hs : Supported2 Γ1 D) (h : thruOKRB D Γ1 F op tx Ps = true) : ThruOKR Γ1 F op tx Ps := by
  intro d hd
  simp only [thruOKRB, List.all_eq_true] at h
  have h := h d hd
  simp only [Bool.and_eq_true, decide_eq_true_eq] at h
  obtain ⟨⟨hF, hst⟩, hr⟩ := h
  refine ⟨hF, fun y hy => by rw [hy] at hst; simpa using hst, ?_⟩
  revert hr
  cases hE : Γ1 d.root with
  | none => intro hr; cases hr
  | some Er =>
    intro hr
    simp only [Bool.and_eq_true, Bool.or_eq_true, decide_eq_true_eq, Bool.not_eq_true'] at hr
    obtain ⟨⟨⟨⟨hl, hc⟩, hds⟩, hsh⟩, hho⟩ := hr
    refine ⟨Er, rfl, hl, ?_, dtorSafeB_sound hs hds, hsh, heldOKB_sound hs hho⟩
    rcases hc with hc | hc
    · exact Or.inl (canDoB2_sound hc)
    · exact Or.inr hc

/-- `EditArg`, decided: a push or an element set stores a live `y` of the
    element type, taken as `PushArg` takes it; a truncation takes an
    expression. -/
def editArgB (D : List Var) (Γ : Ctx) (F : List Var) (t : Ty) : Edit → Option (List Dep × Ctx)
  | .push y =>
    match liveE2 Γ y with
    | some Ey => if Ey.ty = t then pushArg2 D Γ F y Ey t else none
    | none => none
  | .trunc i => if checkExpr2 Γ i then some ([], Γ) else none
  | .set i y =>
    if checkExpr2 Γ i then
      match liveE2 Γ y with
      | some Ey => if Ey.ty = t then pushArg2 D Γ F y Ey t else none
      | none => none
    else none

theorem editArgB_sound {D : List Var} {Γ : Ctx} {F : List Var} {t : Ty} {op : Edit} {Ds : List Dep}
    {Γ1 : Ctx} (hs : Supported2 Γ D) (hD : ∀ v ∈ op.vars, v ∈ D) (h : editArgB D Γ F t op = some (Ds, Γ1)) :
    EditArg Γ F op t Ds Γ1 ∧ Supported2 Γ1 D := by
  cases op with
  | push y =>
    simp only [editArgB] at h
    split at h
    · rename_i Ey hEy
      split at h
      · rename_i hty
        obtain ⟨hy, hyl⟩ := liveE2_some hEy
        obtain ⟨hpa, hsp⟩ := pushArg2_sound hs h
        exact ⟨.push hy hyl hty hpa, hsp (hD y (by simp [Edit.vars]))⟩
      · cases h
    · cases h
  | trunc i =>
    simp only [editArgB] at h
    split at h
    · rename_i hi
      simp only [Option.some.injEq, Prod.mk.injEq] at h; obtain ⟨rfl, rfl⟩ := h
      exact ⟨.trunc (checkExpr2_sound hi), hs⟩
    · cases h
  | set i y =>
    simp only [editArgB] at h
    split at h
    · rename_i hi
      split at h
      · rename_i Ey hEy
        split at h
        · rename_i hty
          obtain ⟨hy, hyl⟩ := liveE2_some hEy
          obtain ⟨hpa, hsp⟩ := pushArg2_sound hs h
          exact ⟨.set (checkExpr2_sound hi) hy hyl hty hpa, hsp (hD y (by simp [Edit.vars]))⟩
        · cases h
      · cases h
    · cases h

/-- What the edit stores is not `x`. -/
def storedNeB (op : Edit) (x : Var) : Bool :=
  match op.stored with | some y => decide (y ≠ x) | none => true

theorem storedNeB_sound {op : Edit} {x : Var} (h : storedNeB op x = true) :
    ∀ y, op.stored = some y → y ≠ x := by
  intro y hy; simp only [storedNeB, hy, decide_eq_true_eq] at h; exact h

def editBB (D : List Var) (Γ : Ctx) (F : List Var) (b : Bool) (x : Var) (op : Edit) : Option Ctx :=
  match Γ x with
  | some Ex =>
    match vecElem2 Ex.ty with
    | some t =>
      if decide (Ex.mode = .bor) && Ex.live && !t.holdsView && decide (x ∉ F) && storedNeB op x &&
          (!op.drops || t.dtorFree) && (b || Ex.fresh) then
        match editArgB D Γ F t op with
        | some (_, Γ1) =>
          match liveE2 Γ1 x with
          | some Ex1 =>
            if thruOKRB D Γ1 F op Ex.ty Ex1.path then some (setE (killThru op Ex.ty Ex1.path Γ1) x Ex1)
            else none
          | none => none
        | none => none
      else none
    | none => none
  | none => none

theorem editBB_sound {P : Prog} {D : List Var} {ξ : Exits} {Γ : Ctx} {F : List Var} {b : Bool} {x : Var}
    {op : Edit} {Δ : Ctx} (hs : Supported2 Γ D) (hD : ∀ v ∈ (Stmt.edit b x op).vars, v ∈ D)
    (h : editBB D Γ F b x op = some Δ) : StmtT P ξ Γ F (.edit b x op) Δ ∧ Supported2 Δ D := by
  simp only [editBB] at h
  split at h
  · rename_i Ex hEx
    split at h
    · rename_i t ht
      split at h
      · rename_i hc
        simp only [Bool.and_eq_true, decide_eq_true_eq, Bool.not_eq_true', Bool.or_eq_true] at hc
        obtain ⟨⟨⟨⟨⟨⟨hm, hl⟩, hv⟩, hxF⟩, hst⟩, hdr⟩, hbf⟩ := hc
        split at h
        · rename_i Ds Γ1 hea
          split at h
          · rename_i Ex1 hEx1
            split at h
            · rename_i hto
              simp only [Option.some.injEq] at h; subst h
              obtain ⟨hargs, hs1⟩ := editArgB_sound hs (fun v hv => hD v (by simp [Stmt.vars, hv])) hea
              obtain ⟨hx1, hx1l⟩ := liveE2_some hEx1
              refine ⟨.editB hEx hm hl (vecElem2_some ht) hv hxF hargs (storedNeB_sound hst) hx1 hx1l
                (thruOKRB_sound hs1 hto) (fun hd => ?_) (fun hb => ?_),
                supported2_setE (supported2_killThru hs1 _ _ _) (hD x (by simp [Stmt.vars])) _⟩
              · rcases hdr with h0 | h0
                · rw [hd] at h0; cases h0
                · exact h0
              · rcases hbf with h0 | h0
                · rw [hb] at h0; cases h0
                · exact h0
            · cases h
          · cases h
        · cases h
      · cases h
    · cases h
  · cases h

theorem supported2_killHv {Γ : Ctx} {D : List Var} (h : Supported2 Γ D) :
    ∀ ks : List (Eff × Bool × Var), Supported2 (killHv ks Γ) D
  | [] => h
  | (_, _, _) :: ks => supported2_kill (supported2_killHv h ks) _ _ _

theorem supported2_holdOn {Γ : Ctx} {D : List Var} (h : Supported2 Γ D) (rs : List Var) (Ds : List Dep) :
    Supported2 (holdOn rs Ds Γ) D := fun v hv => by simp [holdOn, h v hv]

/-- `ThruOK`, decided: `ThruOKR` with every root live and an owner that
    allows the effect. -/
def thruOKB (D : List Var) (Γ1 : Ctx) (F : List Var) (op : Edit) (tx : Ty) (Ps : List Dep) : Bool :=
  (memDeps Ps).all fun d => decide (d.root ∉ F) &&
    (match op.stored with | some y => decide (d.root ≠ y) | none => true) &&
    match Γ1 d.root with
    | some Er =>
      Er.live && canDoB2 Er.mode (op.effAt d.kind (decide (Er.ty = tx)) Er.rvec) &&
      dtorSafeB D Γ1 (op.effAt d.kind (decide (Er.ty = tx)) Er.rvec) false d.root &&
      decide (d.kind ≠ .share) &&
      heldOKB D Γ1 (op.effAt d.kind (decide (Er.ty = tx)) Er.rvec) d.root
    | none => false

theorem thruOKB_sound {D : List Var} {Γ1 : Ctx} {F : List Var} {op : Edit} {tx : Ty} {Ps : List Dep}
    (hs : Supported2 Γ1 D) (h : thruOKB D Γ1 F op tx Ps = true) : ThruOK Γ1 F op tx Ps := by
  intro d hd
  simp only [thruOKB, List.all_eq_true] at h
  have h := h d hd
  simp only [Bool.and_eq_true, decide_eq_true_eq] at h
  obtain ⟨⟨hF, hst⟩, hr⟩ := h
  refine ⟨hF, fun y hy => by rw [hy] at hst; simpa using hst, ?_⟩
  revert hr
  cases hE : Γ1 d.root with
  | none => intro hr; cases hr
  | some Er =>
    intro hr
    simp only [Bool.and_eq_true, decide_eq_true_eq] at hr
    obtain ⟨⟨⟨⟨hl, hc⟩, hds⟩, hsh⟩, hho⟩ := hr
    exact ⟨Er, rfl, hl, canDoB2_sound hc, dtorSafeB_sound hs hds, hsh, heldOKB_sound hs hho⟩

/-- `ThruV`, decided: each memory root of the path is viewed by no
    destructor its effect ends, is no destructor binding, and is not a root
    of what is stored. -/
def thruVB (D : List Var) (Γ1 : Ctx) (op : Edit) (tx : Ty) (Ps Ds : List Dep) : Bool :=
  (memDeps Ps).all fun d =>
    dtorSafeB D Γ1 (op.effAt d.kind (decide ((argE Γ1 d.root).ty = tx)) (argE Γ1 d.root).rvec)
      (argE Γ1 d.root).ty.holdsView d.root &&
    !(argE Γ1 d.root).dbind && decide (d.root ∉ roots Ds)

theorem thruVB_sound {D : List Var} {Γ1 : Ctx} {op : Edit} {tx : Ty} {Ps Ds : List Dep}
    (hs : Supported2 Γ1 D) (h : thruVB D Γ1 op tx Ps Ds = true) : ThruV Γ1 op tx Ps Ds := by
  intro d hd
  simp only [thruVB, List.all_eq_true] at h
  have h := h d hd
  simp only [Bool.and_eq_true, Bool.not_eq_true', decide_eq_true_eq] at h
  exact ⟨dtorSafeB_sound hs h.1.1, h.1.2, h.2⟩

/-- What a closure element stores by name is held by `x` and by every
    memory root of its path whose type holds views. -/
def closureHeldB (Γ1 : Ctx) (Ex1 : Entry) (Ds : List Dep) : Bool :=
  Ds.all fun d => !d.kind.isName || (decide (d ∈ Ex1.held) &&
    (roots (memDeps Ex1.path)).all fun r => !(argE Γ1 r).ty.holdsView || decide (d ∈ (argE Γ1 r).held))

theorem closureHeldB_sound {Γ1 : Ctx} {Ex1 : Entry} {Ds : List Dep} (h : closureHeldB Γ1 Ex1 Ds = true) :
    ∀ d ∈ Ds, d.kind.isName = true → d ∈ Ex1.held ∧ ∀ r ∈ roots (memDeps Ex1.path),
      (argE Γ1 r).ty.holdsView = true → d ∈ (argE Γ1 r).held := by
  intro d hd hn
  have := List.all_eq_true.mp h d hd
  simp only [hn, Bool.not_true, Bool.false_or, Bool.and_eq_true, decide_eq_true_eq, List.all_eq_true] at this
  refine ⟨this.1, fun r hr hv => ?_⟩
  have := this.2 r hr
  simp only [hv, Bool.not_true, Bool.false_or, decide_eq_true_eq] at this
  exact this

/-- `editBV`, decided for an element type that holds views: an element
    with a closure stores only what `x` and its memory roots hold already
    (`closureHeldB`); an `edit false` goes through a fresh borrow that is
    not held-fresh. -/
def editBVB (D : List Var) (Γ : Ctx) (F : List Var) (b : Bool) (x : Var) (op : Edit) : Option Ctx :=
  match Γ x with
  | some Ex =>
    match vecElem2 Ex.ty with
    | some t =>
      if decide (Ex.mode = .bor) && Ex.live && t.holdsView && decide (x ∉ F) && storedNeB op x &&
          (!op.drops || t.dtorFree) && (b || (Ex.fresh && !Ex.heldFresh)) then
        match editArgB D Γ F t op with
        | some (Ds, Γ1) =>
          match liveE2 Γ1 x with
          | some Ex1 =>
            if !(memDeps Ex1.path).isEmpty && thruOKB D Γ1 F op Ex.ty Ex1.path &&
                thruVB D Γ1 op Ex.ty Ex1.path (memDeps Ds) && (!t.hasFn || closureHeldB Γ1 Ex1 Ds) then
              some (setE (holdThru (memDeps Ds) Ex1.path (killThruV op Ex.ty Ex1.path Γ1)) x
                { Ex1 with held := Ex1.held ++ memDeps Ds })
            else none
          | none => none
        | none => none
      else none
    | none => none
  | none => none

theorem editBVB_sound {P : Prog} {D : List Var} {ξ : Exits} {Γ : Ctx} {F : List Var} {b : Bool} {x : Var}
    {op : Edit} {Δ : Ctx} (hs : Supported2 Γ D) (hD : ∀ v ∈ (Stmt.edit b x op).vars, v ∈ D)
    (h : editBVB D Γ F b x op = some Δ) : StmtT P ξ Γ F (.edit b x op) Δ ∧ Supported2 Δ D := by
  simp only [editBVB] at h
  split at h
  · rename_i Ex hEx
    split at h
    · rename_i t ht
      split at h
      · rename_i hc
        simp only [Bool.and_eq_true, decide_eq_true_eq, Bool.not_eq_true', Bool.or_eq_true] at hc
        obtain ⟨⟨⟨⟨⟨⟨hm, hl⟩, hv⟩, hxF⟩, hst⟩, hdr⟩, hb⟩ := hc
        split at h
        · rename_i Ds Γ1 hea
          split at h
          · rename_i Ex1 hEx1
            split at h
            · rename_i hto
              simp only [Bool.and_eq_true, Bool.not_eq_true', List.isEmpty_eq_false_iff, Bool.or_eq_true] at hto
              obtain ⟨⟨⟨hne, hok⟩, hvv⟩, hcl⟩ := hto
              simp only [Option.some.injEq] at h; subst h
              obtain ⟨hargs, hs1⟩ := editArgB_sound hs (fun v hv => hD v (by simp [Stmt.vars, hv])) hea
              obtain ⟨hx1, hx1l⟩ := liveE2_some hEx1
              have hfnc : t.hasFn = false ∨ ∀ d ∈ Ds, d.kind.isName = true →
                  d ∈ Ex1.held ∧ ∀ r ∈ roots (memDeps Ex1.path), (argE Γ1 r).ty.holdsView = true →
                    d ∈ (argE Γ1 r).held := by
                rcases hcl with h0 | h0
                · exact Or.inl h0
                · exact Or.inr (closureHeldB_sound h0)
              refine ⟨.editBV hEx hm hl (vecElem2_some ht) hv hfnc hxF hargs (storedNeB_sound hst) hx1 hx1l
                hne (thruOKB_sound hs1 hok) (thruVB_sound hs1 hvv) (fun hd => ?_) (fun hb' => ?_)
                (fun hb' => ?_),
                supported2_setE (supported2_holdOn (supported2_killHv hs1 _) _ _) (hD x (by simp [Stmt.vars])) _⟩
              · rcases hdr with h0 | h0
                · rw [hd] at h0; cases h0
                · exact h0
              · rcases hb with h0 | ⟨h0, _⟩
                · rw [hb'] at h0; cases h0
                · exact h0
              · rcases hb with h0 | ⟨_, h0⟩
                · rw [hb'] at h0; cases h0
                · exact Or.inl h0
            · cases h
          · cases h
        · cases h
      · cases h
    · cases h
  · cases h

/-- A closure type's method table. -/
def fnTysOf : Ty → Option (List Nat × Cross)
  | .fn ms q => some (ms, q)
  | _ => none

theorem fnTysOf_some {ty : Ty} {ms : List Nat} {q : Cross} (h : fnTysOf ty = some (ms, q)) :
    ty = .fn ms q := by
  cases ty <;> simp [fnTysOf] at h; obtain ⟨rfl, rfl⟩ := h; rfl

/-- What the receiver may change by name is none of the other arguments. -/
def recvApartB (zs : List Var) (Ec : Entry) : Bool :=
  zs.all fun z => Ec.vdeps.all fun d => decide (d.kind.bound = .none) || decide (d.root ≠ z)

theorem recvApartB_sound {zs : List Var} {Ec : Entry} (h : recvApartB zs Ec = true) :
    ∀ z ∈ zs, ∀ d ∈ Ec.vdeps, d.kind.bound ≠ .none → d.root ≠ z := by
  intro z hz d hd hb
  simp only [recvApartB, List.all_eq_true] at h
  have := h z hz d hd
  simp only [Bool.or_eq_true, decide_eq_true_eq] at this
  exact this.resolve_left hb


/-! ### The glue destructors (`DropFnOK`), decided

Each glue is one fixed body shape over a fixed signature, so each is decided
by matching the function's body; the `ThruFn` premise by the thru-free set
where the value holds views (`noThruB`). -/


/-- The signature every glue has: one value of `Ty.dtor f t`, taken owned,
    and a plain integer result. -/
def glueSigB (P : Prog) (f : Nat) (t : Ty) (fn : Fn) : Bool :=
  decide (fn.params = [(.sink, .dtor f t)]) && decide (fn.resTy = .int) && !fn.resOwn &&
    decide (fn.lends = []) && decide (fn.rholds = []) && decide (fn.outHolds = []) && thruViewB P f t

theorem glueSigB_sound {P : Prog} {f : Nat} {t : Ty} {fn : Fn} (h : glueSigB P f t fn = true) :
    fn.params = [(.sink, .dtor f t)] ∧ fn.resTy = .int ∧ fn.resOwn = false ∧ fn.lends = [] ∧
      fn.rholds = [] ∧ fn.outHolds = [] ∧ (ThruFn P f → t.holdsView = false) := by
  simp only [glueSigB, Bool.and_eq_true, decide_eq_true_eq, Bool.not_eq_true'] at h
  obtain ⟨⟨⟨⟨⟨⟨hp, hr⟩, ho⟩, hl⟩, hh⟩, hoh⟩, hv⟩ := h
  exact ⟨hp, hr, ho, hl, hh, hoh, thruViewB_sound hv⟩

/-- A struct's glue: its body takes the value apart first thing, and does
    nothing else (`GlueOK`). -/
def glueOKB (P : Prog) (f : Nat) (t : Ty) : Bool :=
  match P[f]?, prodOf2 t with
  | some fn, some _ =>
    glueSigB P f t fn && (match fn.body with
      | .unpair y _ _ s => decide (y = 0) && s.pureGlue
      | _ => false)
  | _, _ => false

theorem glueOKB_sound {P : Prog} {f : Nat} {t : Ty} (h : glueOKB P f t = true) : GlueOK P f t := by
  unfold glueOKB at h
  split at h
  · rename_i fn ab hf ht
    obtain ⟨a, b⟩ := ab
    simp only [Bool.and_eq_true] at h
    obtain ⟨hs, hb⟩ := h
    obtain ⟨hp, hr, ho, hl, hh, hoh, hv⟩ := glueSigB_sound hs
    split at hb
    · rename_i y x z s hbody
      simp only [Bool.and_eq_true, decide_eq_true_eq] at hb
      obtain ⟨rfl, hg⟩ := hb
      exact ⟨fn, a, b, hf, prodOf2_some ht, hp, hr, ho, hl, hh, hoh, hv, x, z, s, hbody, hg⟩
    · cases hb
  · cases h

/-- The two payloads of an enum type. -/
def sumOf2 : Ty → Option (Ty × Ty)
  | .sum a b => some (a, b)
  | _ => none

theorem sumOf2_some {t a b : Ty} (h : sumOf2 t = some (a, b)) : t = .sum a b := by
  cases t <;> simp [sumOf2] at h; obtain ⟨rfl, rfl⟩ := h; rfl

/-- An enum's arm that moves its payload out to a `letd` first thing
    (`takel 0` for the first variant, `taker 0` for the second). -/
def takesPayB (left : Bool) : Stmt → Bool
  | .letd _ _ (.takel y) _ => left && decide (y = 0)
  | .letd _ _ (.taker y) _ => !left && decide (y = 0)
  | _ => false

theorem takesPayB_left {s : Stmt} (h : takesPayB true s = true) : ∃ y g k, s = .letd y g (.takel 0) k := by
  unfold takesPayB at h
  split at h
  · rename_i y g w k
    simp only [Bool.true_and, decide_eq_true_eq] at h; subst h; exact ⟨y, g, k, rfl⟩
  · simp at h
  · cases h

theorem takesPayB_right {s : Stmt} (h : takesPayB false s = true) : ∃ y g k, s = .letd y g (.taker 0) k := by
  unfold takesPayB at h
  split at h
  · simp at h
  · rename_i y g w k
    simp only [Bool.not_false, Bool.true_and, decide_eq_true_eq] at h; subst h; exact ⟨y, g, k, rfl⟩
  · cases h

/-- An enum's glue: its body matches on the tag, and each arm only moves a
    payload that holds a destructor value out to its `letd` (`EnumGlueOK`). -/
def enumGlueOKB (P : Prog) (f : Nat) (t : Ty) : Bool :=
  match P[f]?, sumOf2 t with
  | some fn, some (a, b) =>
    glueSigB P f t fn && (match fn.body with
      | .ite c sa sb => decide (c = .isl 0) && sa.pureGlue && sb.pureGlue &&
          (!a.holdsDtor || takesPayB true sa) && (!b.holdsDtor || takesPayB false sb)
      | _ => false)
  | _, _ => false

theorem enumGlueOKB_sound {P : Prog} {f : Nat} {t : Ty} (h : enumGlueOKB P f t = true) :
    EnumGlueOK P f t := by
  unfold enumGlueOKB at h
  split at h
  · rename_i fn a b hf ht
    simp only [Bool.and_eq_true] at h
    obtain ⟨hs, hb⟩ := h
    obtain ⟨hp, hr, ho, hl, hh, hoh, hv⟩ := glueSigB_sound hs
    split at hb
    · rename_i c sa sb hbody
      simp only [Bool.and_eq_true, decide_eq_true_eq, Bool.or_eq_true, Bool.not_eq_true'] at hb
      obtain ⟨⟨⟨⟨rfl, hga⟩, hgb⟩, hta⟩, htb⟩ := hb
      refine ⟨fn, a, b, sa, sb, hf, sumOf2_some ht, hp, hr, ho, hl, hh, hoh, hv, hbody, hga, hgb, ?_, ?_⟩
      · intro hd; rcases hta with h0 | h0
        · rw [hd] at h0; cases h0
        · exact takesPayB_left h0
      · intro hd; rcases htb with h0 | h0
        · rw [hd] at h0; cases h0
        · exact takesPayB_right h0
    · cases hb
  · cases h

/-- A struct's or an enum's glue with an impl, for the parts' glue `h` and
    the impl `i` its body names (`ImplGlueOK`). -/
def implGlueAtB (P : Prog) (f : Nat) (t : Ty) (h i : Nat) : Bool :=
  match P[f]? with
  | some fn =>
    t.isStruct && glueSigB P f t fn && (glueOKB P h t || enumGlueOKB P h t) && dtorOKB P i (.dtor h t) &&
      (match fn.body with
        | .letd w h' (.var y) (.letcall _ i' args (.assign v (.expr _))) =>
          decide (h' = h) && decide (y = 0) && decide (i' = i) && decide (args = [w]) && decide (v = 1)
        | _ => false)
  | none => false

theorem implGlueAtB_sound {P : Prog} {f : Nat} {t : Ty} {h i : Nat} (hc : implGlueAtB P f t h i = true) :
    ImplGlueOK P f t h i := by
  unfold implGlueAtB at hc
  split at hc
  · rename_i fn hf
    simp only [Bool.and_eq_true, Bool.or_eq_true] at hc
    obtain ⟨⟨⟨⟨hst, hs⟩, hg⟩, hd⟩, hb⟩ := hc
    obtain ⟨hp, hr, ho, hl, hh, hoh, hv⟩ := glueSigB_sound hs
    split at hb
    · rename_i w h' y r i' args v e hbody
      simp only [Bool.and_eq_true, decide_eq_true_eq] at hb
      obtain ⟨⟨⟨⟨rfl, rfl⟩, rfl⟩, rfl⟩, rfl⟩ := hb
      refine ⟨fn, w, r, e, hf, hst, hp, hr, ho, hl, hh, hoh, hv, ?_, dtorOKB_sound hd, hbody⟩
      rcases hg with hg | hg
      · exact Or.inl (glueOKB_sound hg)
      · exact Or.inr (enumGlueOKB_sound hg)
    · cases hb
  · cases hc

/-- The glue with an impl, its parts' glue and impl read off its body. -/
def implGlueOKB (P : Prog) (f : Nat) (t : Ty) : Bool :=
  match P[f]? with
  | some fn =>
    match fn.body with
    | .letd _ h (.var _) (.letcall _ i _ _) => implGlueAtB P f t h i
    | _ => false
  | none => false

theorem implGlueOKB_sound {P : Prog} {f : Nat} {t : Ty} (hc : implGlueOKB P f t = true) :
    ∃ h i, ImplGlueOK P f t h i := by
  unfold implGlueOKB at hc
  split at hc
  · split at hc
    · exact ⟨_, _, implGlueAtB_sound hc⟩
    · cases hc
  · cases hc

/-- A closure's glue: its body calls the closure's drop method on it, owned,
    first thing, and then only sets its result (`ClosureGlueOK`). -/
def closureGlueOKB (P : Prog) (f : Nat) (t : Ty) : Bool :=
  match P[f]?, t with
  | some fn, .fn ms q =>
    decide (q = .dropd) && glueSigB P f t fn &&
      (match fn.body with
        | .callcE _ c j zs (.assign v (.expr _)) =>
          decide (c = 0) && decide (zs = []) && decide (v = 1) &&
            (match ms[j]? with
              | some σ => (match P[σ]? with
                  | some sig => decide (sig.params = [(.sink, .dtor f t)])
                  | none => false)
              | none => false)
        | _ => false)
  | _, _ => false

theorem closureGlueOKB_sound {P : Prog} {f : Nat} {t : Ty} (hc : closureGlueOKB P f t = true) :
    ClosureGlueOK P f t := by
  unfold closureGlueOKB at hc
  split at hc
  · rename_i fn ms q hf
    simp only [Bool.and_eq_true, decide_eq_true_eq] at hc
    obtain ⟨⟨rfl, hs⟩, hb⟩ := hc
    obtain ⟨hp, hr, ho, hl, hh, hoh, hv⟩ := glueSigB_sound hs
    split at hb
    · rename_i r c j zs v e hbody
      simp only [Bool.and_eq_true, decide_eq_true_eq] at hb
      obtain ⟨⟨⟨rfl, rfl⟩, rfl⟩, hm⟩ := hb
      split at hm
      · rename_i σ hσ
        split at hm
        · rename_i sig hsig
          exact ⟨fn, ms, j, σ, sig, r, e, hf, rfl, hp, hr, ho, hl, hh, hoh, hv, hσ, hsig,
            of_decide_eq_true hm, hbody⟩
        · cases hm
      · cases hm
    · cases hb
  · cases hc

/-- `DropFnOK`, decided: a destructor that takes the value lent (`DtorOK`,
    for a payload that holds no views), or one of the glues. -/
def dropFnOKB (P : Prog) (f : Nat) (t : Ty) : Bool :=
  (dtorOKB P f (.dtor f t) && !t.holdsDtor) || glueOKB P f t || implGlueOKB P f t ||
    enumGlueOKB P f t || closureGlueOKB P f t

theorem dropFnOKB_sound {P : Prog} {f : Nat} {t : Ty} (h : dropFnOKB P f t = true) : DropFnOK P f t := by
  simp only [dropFnOKB, Bool.or_eq_true, Bool.and_eq_true, Bool.not_eq_true'] at h
  rcases h with (((⟨hd, hh⟩ | h) | h) | h) | h
  · exact Or.inl ⟨dtorOKB_sound hd, hh⟩
  · exact Or.inr (Or.inl (glueOKB_sound h))
  · exact Or.inr (Or.inr (Or.inl (implGlueOKB_sound h)))
  · exact Or.inr (Or.inr (Or.inr (Or.inl (enumGlueOKB_sound h))))
  · exact Or.inr (Or.inr (Or.inr (Or.inr (closureGlueOKB_sound h))))

/-- A struct's glue (`unpair` first thing, then only its result) and an
    enum's (a tag match whose arms only set the result), at function 0: the
    deciders accept them, and refuse a struct glue whose body does more. -/
def glueEx (body : Stmt) (t : Ty) : Prog :=
  [{ params := [(.sink, .dtor 0 t)], resTy := .int, resOwn := false, lends := [], rholds := [],
     outHolds := [], body := body, nvars := 4 }]

example : dropFnOKB (glueEx (.unpair 0 1 2 (.assign 1 (.expr (.lit 0)))) (.prod .int .int)) 0 (.prod .int .int) = true := by
  decide
example : dropFnOKB (glueEx (.ite (.isl 0) (.assign 1 (.expr (.lit 0))) .skip) (.sum .int .int)) 0 (.sum .int .int) = true := by
  decide
example : glueOKB (glueEx (.unpair 0 1 2 (.free 1)) (.prod .int .int)) 0 (.prod .int .int) = false := by decide

/-- `LetdFn`, decided: `f` is a destructor or a glue of `t` (`dropFnOKB`),
    and a value of another destructor type `.dtor g t` is rebound under `f`
    only where `g` is the glue with an impl whose parts' glue is `f`, and the
    body calls that impl on the binding next (Agora #616). -/
def letdFnB (P : Prog) (f : Nat) (t a : Ty) (x : Var) (s : Stmt) : Bool :=
  dropFnOKB P f t && (match a with
    | .dtor g _ => decide (g = f) || (match s with
        | .letcall _ i args _ => decide (args = [x]) && implGlueAtB P g t f i
        | _ => false)
    | _ => true)

theorem letdFnB_sound {P : Prog} {f : Nat} {t a : Ty} {x : Var} {s : Stmt} (h : letdFnB P f t a x s = true) :
    LetdFn P f t a x s := by
  simp only [letdFnB, Bool.and_eq_true] at h
  obtain ⟨hd, hm⟩ := h
  refine ⟨dropFnOKB_sound hd, fun g hg hne => ?_⟩
  subst hg
  simp only [Bool.or_eq_true, decide_eq_true_eq] at hm
  rcases hm with hm | hm
  · exact absurd hm hne
  · split at hm
    · rename_i r i args k
      simp only [Bool.and_eq_true, decide_eq_true_eq] at hm
      obtain ⟨rfl, hi⟩ := hm
      exact ⟨i, r, k, implGlueAtB_sound hi, rfl⟩
    · cases hm

/-- `Cross.send.Le q`, decided. -/
def sendLeB (q : Cross) : Bool :=
  decide (Cross.send.rank ≤ q.rank) && decide (Cross.send.drops = q.drops)

theorem sendLeB_sound {q : Cross} (h : sendLeB q = true) : Cross.send.Le q := by
  simp only [sendLeB, Bool.and_eq_true, decide_eq_true_eq] at h; exact h

/-- `callcE`'s receiver: the method takes the environment `inout` at some
    bound (returned), the receiver is the closure itself, at least `send`,
    and the other arguments depend only on bound names; or it takes the
    receiver as its one `sink` argument, a dropping closure with nothing
    held, owned and live, returning nothing owned. -/
def callcEArgB (Γ : Ctx) (Ec : Entry) (ms : List Nat) (q : Cross) (sig : Fn) (zs : List Var) : Option Eff :=
  match sig.params with
  | (.inout b, .fn ms' q') :: _ =>
    if decide (ms' = ms) && decide (q' = q) && decide (Ec.ty = .fn ms q) && sendLeB q &&
        zs.all (fun z => (argE Γ z).vdeps.all fun d => (Γ d.root).isSome) then some b else none
  | [(.sink, t)] =>
    if decide (t = Ec.ty) && zs.isEmpty && Ec.vdeps.isEmpty && decide (Ec.mode = .own) && Ec.live &&
        q.drops && !sig.resOwn then some .none else none
  | _ => none

theorem callcEArgB_sound {Γ : Ctx} {Ec : Entry} {ms : List Nat} {q : Cross} {sig : Fn} {zs : List Var}
    {b : Eff} (h : callcEArgB Γ Ec ms q sig zs = some b) :
    (∃ ps, sig.params = (.inout b, .fn ms q) :: ps ∧ Ec.ty = .fn ms q ∧ Cross.send.Le q ∧
        ∀ z ∈ zs, ∀ d ∈ (argE Γ z).vdeps, (Γ d.root).isSome) ∨
      (sig.params = [(.sink, Ec.ty)] ∧ zs = [] ∧ Ec.vdeps = [] ∧ Ec.mode = .own ∧ Ec.live = true ∧
        q.drops = true ∧ sig.resOwn = false) := by
  unfold callcEArgB at h
  split at h
  · rename_i b0 ms' q' ps hp
    split at h
    · rename_i hc
      simp only [Option.some.injEq] at h; subst h
      simp only [Bool.and_eq_true, decide_eq_true_eq, List.all_eq_true] at hc
      obtain ⟨⟨⟨⟨hm, hq⟩, hty⟩, hle⟩, hz⟩ := hc
      subst hm; subst hq
      exact Or.inl ⟨ps, hp, hty, sendLeB_sound hle, fun z hz' d hd => hz z hz' d hd⟩
    · cases h
  · rename_i t hp
    split at h
    · rename_i hc
      simp only [Bool.and_eq_true, decide_eq_true_eq, List.isEmpty_iff, Bool.not_eq_true'] at hc
      obtain ⟨⟨⟨⟨⟨⟨ht, hzs⟩, hv⟩, hm⟩, hl⟩, hd⟩, ho⟩ := hc
      subst ht
      exact Or.inr ⟨hp, hzs, hv, hm, hl, hd, ho⟩
    · cases h
  · cases h

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
        else if ctxWF2B D Γ && nameWFB D Γ && weaker2B D Δa (joinCand Δa Δb) &&
            weaker2B D Δb (joinCand Δa Δb) then some (joinCand Δa Δb)
        else none
      | _, _ => none
    else none
  | Γ, F, .while c s =>
    if s.src ∧ checkExpr2 Γ c then
      match checkStmt2 P R C D Γ F s with
      | some Δ => if D.all (fun v => Δ v == Γ v) then some Γ else none
      | none => none
    else none
  | Γ, F, .push x y => pushB D Γ F x y
  | Γ, F, .insert x i y => if checkExpr2 Γ i && decide (x ∉ F) then pushB D Γ F x y else none
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
  | Γ, F, .rbind p s =>
    match Γ p with
    | some E =>
      if decide (E.mode = .rootb) && E.live && anchoredB E F && decide (p ∉ F) then
        match checkStmt2 P R C D Γ F s with
        | some Δ => if rbindKeptB Δ p E.vdeps then some (exitRoot p (E.path ++ E.held) Δ) else none
        | none => none
      else none
    | none => none
  | Γ, F, .scopeL _ t x s =>
    match Γ x with
    | some E =>
      if decide (E.mode ≠ .rootb) && decide (E.ty = t) && decide (t ≠ .int → E.mode = .own) &&
          decide (x ∉ F) then
        match checkStmt2 P R C D Γ F s with
        | some Δ =>
          if liveAtB Δ x && endOK2B D Δ x &&
              keepOutB D Γ Δ s.spine && ctxWF2B D Δ && nameWFB D Δ && freshOKB D Δ then
            some (exitScope x Δ)
          else none
        | none => none
      else none
    | none => none
  | Γ, F, .letrec x f s =>
    match P[f]? with
    | some fn =>
      if s.src ∧ Γ x = none ∧ x ∉ F ∧ fn.params = [] ∧ fn.resTy = .int ∧ fn.resOwn = false then
        match C Γ F f [] with
        | some (E, Γ1) =>
          match checkStmt2 P R C D (setE Γ1 x E) F s with
          | some Δ => if endOK2B D Δ x then some (exitScope x Δ) else none
          | none => none
        | none => none
      else none
    | none => none
  | Γ, F, .withLock a x s =>
    match Γ a with
    | some Ea =>
      match lockPay Ea.ty with
      | some t =>
        if s.src ∧ Γ x = none ∧ x ∉ F ∧ Ea.live = true ∧ Ea.mode.isRoot = true ∧ a ∉ s.vars ∧
            (t.holdsDtor = true → x ∉ s.assigns) then
          match checkStmt2 P R C D (setE Γ x (lockE t)) F s with
          | some Δ => if liveAtB Δ x && endOK2B D Δ x then some (exitScope x Δ) else none
          | none => none
        else none
      | none => none
    | none => none
  | Γ, F, .withElem v i x s =>
    match Γ v with
    | some Ev =>
      if s.src ∧ Γ x = none ∧ x ∉ F ∧ Ev.mode = .own ∧ v ∉ s.vars then
        if checkExpr2 Γ i && noPinB D Γ v && dtorSafeB D Γ .replace false v then
          match R (kill .replace false v Γ) F (.pop v) with
          | some (E, Γ1) =>
            if E.ty.dtorFree then
              match checkStmt2 P R C D (setE Γ1 x E) F s with
              | some Δ1 =>
                match pushB D Δ1 F v x with
                | some Δ => if endOK2B D Δ x then some (exitScope x Δ) else none
                | none => none
              | none => none
            else none
          | none => none
        else none
      else none
    | none => none
  | Γ, F, .letd x f r s =>
    if s.src ∧ Γ x = none ∧ x ∉ F ∧ x ∉ s.assigns then
      match R Γ F r with
      | some (E, Γ1) =>
        match letdTys f E.ty with
        | some (t, τ) =>
          if decide (E.mode = .own) && t.isStruct && !t.hasFn &&
              letdFnB P f t E.ty x s && takeOKB Γ r then
            match checkStmt2 P R C D (setE Γ1 x (Entry.arm { E with ty := τ, held := E.held })) F s with
            | some Δ => if endOK2B D Δ x then some (exitScope x Δ) else none
            | none => none
          else none
        | none => none
      | none => none
    else none
  | Γ, F, .scopeD x f s =>
    match Γ x with
    | some E =>
      match scopeDTy f E.ty with
      | some t =>
        if decide (E.mode = .own) && !E.ty.hasFn && dropFnOKB P f t &&
            t.isStruct && decide (x ∉ F) && dSelfB E x then
          match checkStmt2 P R C D Γ F s with
          | some Δ =>
            if endOK2B D Δ x && keepOutB D Γ Δ s.spine && ctxWF2B D Δ && nameWFB D Δ &&
                viewDbindB Δ x && freshOKB D Δ then some (exitScope x Δ) else none
          | none => none
        else none
      | none => none
    | none => none
  | Γ, F, .takeB x i y s =>
    match Γ x with
    | some Ex =>
      match vecElem2 Ex.ty with
      | some t =>
        if s.src ∧ Γ y = none ∧ y ∉ F ∧ Ex.mode = .bor ∧ Ex.live = true ∧ t.holdsView = false ∧ x ∉ F ∧
            (t.holdsDtor = true → y ∈ s.movedFirst ∧ y ∉ s.assigns) then
          if checkExpr2 Γ i && thruOKRB D Γ F (.trunc i) Ex.ty Ex.path then
            match checkStmt2 P R C D (setE (setE (killThru (.trunc i) Ex.ty Ex.path Γ) x Ex) y (compE Ex t)) F s with
            | some Δ => if endOK2B D Δ y then some (exitScope y Δ) else none
            | none => none
          else none
        else none
      | none => none
    | none => none
  | Γ, F, .edit b x op =>
    match editBB D Γ F b x op with
    | some Δ => some Δ
    | none => editBVB D Γ F b x op
  | Γ, F, .callc x c j σ zs k =>
    match Γ c with
    | some Ec =>
      match fnTysOf Ec.ty.undtor with
      | some (ms, _) =>
        match P[σ]? with
        | some sig =>
          if k.src ∧ Γ x = none ∧ x ∉ F ∧ ms[j]? = some σ ∧ sig.params.head? = some (.inp, Ec.ty) ∧
              (∀ o ∈ sig.outHolds, o.2.1 ≠ 0) ∧
              (sig.resOwn = true → sig.resTy.holdsDtor = true → x ∈ k.movedFirst ∧ x ∉ k.assigns) then
            if recvApartB zs Ec then
              match C Γ F σ (c :: zs) with
              | some (E, Γ1) =>
                match checkStmt2 P R C D (setE Γ1 x (recvRes c Ec E)) F k with
                | some Δ => if endOK2B D Δ x then some (exitScope x Δ) else none
                | none => none
              | none => none
            else none
          else none
        | none => none
      | none => none
    | none => none
  | Γ, F, .callcE x c j zs k =>
    match Γ c with
    | some Ec =>
      match fnTysOf Ec.ty.undtor with
      | some (ms, q) =>
        match ms[j]? with
        | some σ =>
          match P[σ]? with
          | some sig =>
            if k.src ∧ Γ x = none ∧ x ∉ F ∧ sig.lends = [] ∧ sig.rholds = [] ∧ sig.outHolds = [] ∧
                (sig.resOwn = true → sig.resTy.holdsDtor = true → x ∈ k.movedFirst ∧ x ∉ k.assigns) then
              if (sendLeB q || q.drops) && canDoB2 Ec.mode .replace && noPinB D Γ c &&
                  dtorSafeB D Γ .replace false c && noThruB P σ then
                match callcEArgB Γ Ec ms q sig zs with
                | some _ =>
                  match C (kill .replace false c Γ) F σ (c :: zs) with
                  | some (E, Γ1) =>
                    match checkStmt2 P R C D (kill .replace false c (setE Γ1 x E)) F k with
                    | some Δ => if endOK2B D Δ x then some (exitScope x Δ) else none
                    | none => none
                  | none => none
                | none => none
              else none
            else none
          | none => none
        | none => none
      | none => none
    | none => none
  | Γ, F, .scope x s =>
    match Γ x with
    | some E =>
      if decide (E.mode ≠ .rootb) && decide (x ∉ F) then
        match checkStmt2 P R C D Γ F s with
        | some Δ => if endOK2B D Δ x then some (exitScope x Δ) else none
        | none => none
      else none
    | none => none
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
    unfold checkStmt2 at h
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
    unfold checkStmt2 at h
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
    unfold checkStmt2 at h
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
    unfold checkStmt2 at h
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
    unfold checkStmt2 at h
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
            · split at h
              · rename_i _ _ hj
                simp only [Bool.and_eq_true] at hj
                obtain ⟨⟨⟨h1, h2⟩, h3⟩, h4⟩ := hj
                simp only [Option.some.injEq] at h; subst h
                have sj := joinCand_supported (Δb := Δb) sa
                have wΓ := weaker_self2 hs h1 h2
                exact ⟨.ite ha hb (checkExpr2_sound hce)
                  (.sub wΓ ta (Or.inr (weaker2B_sound sa sj h3)))
                  (.sub wΓ tb (Or.inr (weaker2B_sound sb sj h4))), sj⟩
              · cases h
      · cases h
    · cases h
  | «while» c s ih =>
    intro ξ Γ F Δ hs hD h
    unfold checkStmt2 at h
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
  | push x y => intro ξ Γ F Δ hs hD h; exact pushB_sound hs hD h
  | insert x i y =>
    intro ξ Γ F Δ hs hD h
    unfold checkStmt2 at h
    split at h
    · rename_i hc
      simp only [Bool.and_eq_true, decide_eq_true_eq] at hc
      obtain ⟨t0, s0⟩ := pushB_sound (P := P) (ξ := .none) hs
        (fun v hv => hD v (by simp [Stmt.vars] at hv ⊢; rcases hv with h | h <;> simp [h])) h
      exact ⟨.insert (checkExpr2_sound hc.1) hc.2 t0, s0⟩
    · cases h
  | free x =>
    intro ξ Γ F Δ hs hD h
    unfold checkStmt2 at h
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
    unfold checkStmt2 at h
    obtain ⟨t0, s0⟩ := ih (ξ := .none) hs (fun v hv => hD v (by simp [Stmt.vars, hv])) h
    exact ⟨.frozen t0 (fun v hv => hv), s0⟩
  | panic =>
    intro ξ Γ F Δ hs hD h
    unfold checkStmt2 at h
    split at h
    · rename_i hc
      simp only [Bool.and_eq_true] at hc
      simp only [Option.some.injEq] at h; subst h
      exact ⟨panic_self hs hc.1 hc.2, hs⟩
    · cases h
  | rbind p s ih =>
    intro ξ Γ F Δ hs hD h
    unfold checkStmt2 at h
    split at h
    · rename_i E hE
      split at h
      · rename_i hc
        simp only [Bool.and_eq_true, decide_eq_true_eq] at hc
        obtain ⟨⟨⟨hm, hl⟩, ha⟩, hpF⟩ := hc
        split at h
        · rename_i Δ0 h0
          split at h
          · rename_i hk
            simp only [Option.some.injEq] at h; subst h
            obtain ⟨t0, s0⟩ := ih (ξ := .none) hs (fun v hv => hD v (by simp [Stmt.vars, hv])) h0
            exact ⟨.rbind hE hm hl (anchoredB_sound ha) hpF t0 (rbindKeptB_sound hk),
              supported2_exitRoot s0 p _⟩
          · cases h
        · cases h
      · cases h
    · cases h
  | scopeL k t x s ih =>
    intro ξ Γ F Δ hs hD h
    unfold checkStmt2 at h
    split at h
    · rename_i E hE
      split at h
      · rename_i hc
        simp only [Bool.and_eq_true, decide_eq_true_eq] at hc
        obtain ⟨⟨⟨hm, ht⟩, hti⟩, hxF⟩ := hc
        split at h
        · rename_i Δ0 h0
          split at h
          · rename_i he
            simp only [Option.some.injEq] at h; subst h
            simp only [Bool.and_eq_true] at he
            obtain ⟨⟨⟨⟨⟨hl, hend⟩, hko⟩, hwf⟩, hnw⟩, hfr⟩ := he
            obtain ⟨t0, s0⟩ := ih (ξ := .none) hs (fun v hv => hD v (by simp [Stmt.vars, hv])) h0
            have hlive := liveAtB_sound hl
            exact ⟨.scopeL ⟨E, hE, hm, ht, hti, hlive⟩ hxF t0 (endOK2B_sound s0 hend)
              (keepOutB_sound hs s0 hko) (ctxWF2B_sound s0 hwf) (nameWFB_sound s0 hnw)
              (freshOKB_sound s0 hfr), supported2_exitScope s0 x⟩
          · cases h
        · cases h
      · cases h
    · cases h
  | letrec x f s ih =>
    intro ξ Γ F Δ hs hD h
    unfold checkStmt2 at h
    split at h
    · rename_i fn hfn
      split at h
      · rename_i hc
        obtain ⟨hsrc, hx, hF, hp, hr, ho⟩ := hc
        split at h
        · rename_i E Γ1 hcall
          split at h
          · rename_i Δ0 h0
            split at h
            · rename_i he
              simp only [Option.some.injEq] at h; subst h
              obtain ⟨hct, hs1⟩ := hC Γ F f [] E Γ1 hs (fun a ha => by simp at ha) hcall
              obtain ⟨t0, s0⟩ := ih (ξ := ξ.under x) (supported2_setE hs1 (hD x (by simp [Stmt.vars])) E)
                (fun v hv => hD v (by simp [Stmt.vars, hv])) h0
              exact ⟨.letrec hsrc hx hF hfn hp hr ho hct t0 (endOK2B_sound s0 he),
                supported2_exitScope s0 x⟩
            · cases h
          · cases h
        · cases h
      · cases h
    · cases h
  | withLock a x s ih =>
    intro ξ Γ F Δ hs hD h
    unfold checkStmt2 at h
    split at h
    · rename_i Ea hEa
      split at h
      · rename_i t ht
        split at h
        · rename_i hc
          obtain ⟨hsrc, hx, hF, hl, hr, ha, hna⟩ := hc
          split at h
          · rename_i Δ0 h0
            split at h
            · rename_i he
              simp only [Option.some.injEq] at h; subst h
              simp only [Bool.and_eq_true] at he
              obtain ⟨t0, s0⟩ := ih (ξ := .none) (supported2_setE hs (hD x (by simp [Stmt.vars])) (lockE t))
                (fun v hv => hD v (by simp [Stmt.vars, hv])) h0
              exact ⟨.withLock hsrc hx hF hEa hl (lockPay_sound ht) t0 (endOK2B_sound s0 he.2) hr ha
                (liveAtB_sound he.1) hna, supported2_exitScope s0 x⟩
            · cases h
          · cases h
        · cases h
      · cases h
    · cases h
  | withElem v i x s ih =>
    intro ξ Γ F Δ hs hD h
    unfold checkStmt2 at h
    split at h
    · rename_i Ev hEv
      split at h
      · rename_i hc
        obtain ⟨hsrc, hx, hF, hm, hvs⟩ := hc
        split at h
        · rename_i hc2
          simp only [Bool.and_eq_true] at hc2
          obtain ⟨⟨hi, hnp⟩, hds⟩ := hc2
          split at h
          · rename_i E Γ1 hpop
            split at h
            · rename_i hdf
              split at h
              · rename_i Δ1 h1
                split at h
                · rename_i Δ0 h0
                  split at h
                  · rename_i he
                    simp only [Option.some.injEq] at h; subst h
                    have hvD : v ∈ D := hD v (by simp [Stmt.vars])
                    have hxD : x ∈ D := hD x (by simp [Stmt.vars])
                    obtain ⟨hrt, hs1⟩ := hR _ F (.pop v) E Γ1 (supported2_kill hs .replace false v)
                      (fun w hw => by simp [Rhs.vars] at hw; subst hw; exact hvD) hpop
                    obtain ⟨t1, s1⟩ := ih (ξ := .none) (supported2_setE hs1 hxD E)
                      (fun w hw => hD w (by simp [Stmt.vars, hw])) h1
                    obtain ⟨t2, s2⟩ := pushB_sound (P := P) (ξ := .none) s1
                      (fun w hw => by simp [Stmt.vars] at hw; rcases hw with hw | hw <;> subst hw <;> assumption) h0
                    exact ⟨.withElem hsrc hx hF hEv hm (checkExpr2_sound hi) (noPinB_sound hs hnp)
                      (dtorSafeB_sound hs hds) hrt t1 t2 (endOK2B_sound s2 he) hvs hdf,
                      supported2_exitScope s2 x⟩
                  · cases h
                · cases h
              · cases h
            · cases h
          · cases h
        · cases h
      · cases h
    · cases h
  | letd x f r s ih =>
    intro ξ Γ F Δ hs hD h
    unfold checkStmt2 at h
    split at h
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
            · rename_i Δ0 h0
              split at h
              · rename_i he
                simp only [Option.some.injEq] at h; subst h
                obtain ⟨hrt, hs1⟩ := hR Γ F r E Γ1 hs (fun v hv => hD v (by simp [Stmt.vars, hv])) hr
                have hlt := letdTys_sound hty
                obtain ⟨t0, s0⟩ := ih (ξ := ξ.underD x)
                  (supported2_setE hs1 (hD x (by simp [Stmt.vars])) _)
                  (fun v hv => hD v (by simp [Stmt.vars, hv])) h0
                exact ⟨.letd hsrc hx hF hrt hm hlt hst hfn
                  ⟨letdFnB_sound hdt, takeOKB_sound htk⟩
                  (HeldUp.refl Γ1 E) t0 (endOK2B_sound s0 he) hna, supported2_exitScope s0 x⟩
              · cases h
            · cases h
          · cases h
        · cases h
      · cases h
    · cases h
  | scopeD x f s ih =>
    intro ξ Γ F Δ hs hD h
    unfold checkStmt2 at h
    split at h
    · rename_i E hE
      split at h
      · rename_i t ht
        split at h
        · rename_i hc
          simp only [Bool.and_eq_true, decide_eq_true_eq, Bool.not_eq_true'] at hc
          obtain ⟨⟨⟨⟨⟨hm, hfn⟩, hdt⟩, hst⟩, hxF⟩, hds⟩ := hc
          split at h
          · rename_i Δ0 h0
            split at h
            · rename_i he
              simp only [Option.some.injEq] at h; subst h
              simp only [Bool.and_eq_true] at he
              obtain ⟨⟨⟨⟨⟨hend, hko⟩, hwf⟩, hnw⟩, hvd⟩, hfr⟩ := he
              obtain ⟨t0, s0⟩ := ih (ξ := ξ.underD x) hs (fun v hv => hD v (by simp [Stmt.vars, hv])) h0
              have hty := scopeDTy_sound ht
              exact ⟨.scopeD ⟨E, t, hE, hm, hty, hfn, dropFnOKB_sound hdt, hst⟩ hxF t0
                (endOK2B_sound s0 hend) (keepOutB_sound hs s0 hko) (ctxWF2B_sound s0 hwf)
                (nameWFB_sound s0 hnw) (viewDbindB_sound hvd) (dSelfB_sound hE hds) (freshOKB_sound s0 hfr),
                supported2_exitScope s0 x⟩
            · cases h
          · cases h
        · cases h
      · cases h
    · cases h
  | takeB x i y s ih =>
    intro ξ Γ F Δ hs hD h
    unfold checkStmt2 at h
    split at h
    · rename_i Ex hEx
      split at h
      · rename_i t ht
        split at h
        · rename_i hc
          obtain ⟨hsrc, hy, hyF, hm, hl, hv, hxF, hdt⟩ := hc
          split at h
          · rename_i hc2
            simp only [Bool.and_eq_true] at hc2
            split at h
            · rename_i Δ0 h0
              split at h
              · rename_i he
                simp only [Option.some.injEq] at h; subst h
                have hxD : x ∈ D := hD x (by simp [Stmt.vars])
                have hyD : y ∈ D := hD y (by simp [Stmt.vars])
                obtain ⟨t0, s0⟩ := ih (ξ := ξ.under y)
                  (supported2_setE (supported2_setE (supported2_killThru hs _ _ _) hxD Ex) hyD _)
                  (fun v hv => hD v (by simp [Stmt.vars, hv])) h0
                exact ⟨.takeB hsrc hy hyF hEx hm hl (vecElem2_some ht) hv hxF (checkExpr2_sound hc2.1)
                  (thruOKRB_sound hs hc2.2) hdt t0 (endOK2B_sound s0 he), supported2_exitScope s0 y⟩
              · cases h
            · cases h
          · cases h
        · cases h
      · cases h
    · cases h
  | edit b x op =>
    intro ξ Γ F Δ hs hD h
    unfold checkStmt2 at h
    split at h
    · rename_i Δ0 h0
      simp only [Option.some.injEq] at h; subst h
      exact editBB_sound hs hD h0
    · exact editBVB_sound hs hD h
  | callc x c j σ zs k ih =>
    intro ξ Γ F Δ hs hD h
    unfold checkStmt2 at h
    split at h
    · rename_i Ec hEc
      split at h
      · rename_i ms q hms
        split at h
        · rename_i sig hsig
          split at h
          · rename_i hc
            obtain ⟨hsrc, hx, hF, hj, hhd, hout, hdk⟩ := hc
            split at h
            · rename_i hap
              split at h
              · rename_i E Γ1 hcall
                split at h
                · rename_i Δ0 h0
                  split at h
                  · rename_i he
                    simp only [Option.some.injEq] at h; subst h
                    obtain ⟨hct, hs1⟩ := hC Γ F σ (c :: zs) E Γ1 hs
                      (fun a ha => hD a (by simp [Stmt.vars] at ha ⊢; rcases ha with ha | ha <;> simp [ha])) hcall
                    obtain ⟨t0, s0⟩ := ih (ξ := ξ.under x) (supported2_setE hs1 (hD x (by simp [Stmt.vars])) _)
                      (fun v hv => hD v (by simp [Stmt.vars, hv])) h0
                    exact ⟨.callc hsrc hx hF hEc (fnTysOf_some hms) hj hsig hhd hout hct (recvApartB_sound hap) t0
                      (endOK2B_sound s0 he) hdk, supported2_exitScope s0 x⟩
                  · cases h
                · cases h
              · cases h
            · cases h
          · cases h
        · cases h
      · cases h
    · cases h
  | callcE x c j zs k ih =>
    intro ξ Γ F Δ hs hD h
    unfold checkStmt2 at h
    split at h
    · rename_i Ec hEc
      split at h
      · rename_i ms q hms
        split at h
        · rename_i σ hj
          split at h
          · rename_i sig hsig
            split at h
            · rename_i hc
              obtain ⟨hsrc, hx, hF, hle, hrh, hoh, hdk⟩ := hc
              split at h
              · rename_i hc2
                simp only [Bool.and_eq_true, Bool.or_eq_true] at hc2
                obtain ⟨⟨⟨⟨hq, hcd⟩, hnp⟩, hds⟩, hnt⟩ := hc2
                split at h
                · rename_i b0 harg
                  split at h
                  · rename_i E Γ1 hcall
                    split at h
                    · rename_i Δ0 h0
                      split at h
                      · rename_i he
                        simp only [Option.some.injEq] at h; subst h
                        have hcD : c ∈ D := hD c (by simp [Stmt.vars])
                        have hxD : x ∈ D := hD x (by simp [Stmt.vars])
                        obtain ⟨hct, hs1⟩ := hC _ F σ (c :: zs) E Γ1 (supported2_kill hs .replace false c)
                          (fun a ha => hD a (by simp [Stmt.vars] at ha ⊢; rcases ha with ha | ha <;> simp [ha])) hcall
                        obtain ⟨t0, s0⟩ := ih (ξ := ξ.under x)
                          (supported2_kill (supported2_setE hs1 hxD E) .replace false c)
                          (fun v hv => hD v (by simp [Stmt.vars, hv])) h0
                        have hq' : Cross.send.Le q ∨ q.drops = true := by
                          rcases hq with hq | hq
                          · exact Or.inl (sendLeB_sound hq)
                          · exact Or.inr hq
                        exact ⟨.callcE (b := b0) hsrc hx hF hEc (fnTysOf_some hms) (canDoB2_sound hcd) hq' hj hsig
                          (callcEArgB_sound harg) hle hrh hoh (noPinB_sound hs hnp) (dtorSafeB_sound hs hds) hct t0
                          (endOK2B_sound s0 he) (noThruB_sound hnt) hdk, supported2_exitScope s0 x⟩
                      · cases h
                    · cases h
                  · cases h
                · cases h
              · cases h
            · cases h
          · cases h
        · cases h
      · cases h
    · cases h
  | scope x s ih =>
    intro ξ Γ F Δ hs hD h
    unfold checkStmt2 at h
    split at h
    · rename_i E hE
      split at h
      · rename_i hc
        simp only [Bool.and_eq_true, decide_eq_true_eq] at hc
        split at h
        · rename_i Δ0 h0
          split at h
          · rename_i he
            simp only [Option.some.injEq] at h; subst h
            obtain ⟨t0, s0⟩ := ih (ξ := ξ.under x) hs (fun v hv => hD v (by simp [Stmt.vars, hv])) h0
            exact ⟨.scope ⟨E, hE, hc.1⟩ hc.2 t0 (endOK2B_sound s0 he), supported2_exitScope s0 x⟩
          · cases h
        · cases h
      · cases h
    · cases h
  | block s ih =>
    intro ξ Γ F Δ hs hD h
    unfold checkStmt2 at h
    obtain ⟨t0, s0⟩ := ih (ξ := ξ.blk Δ) hs (fun v hv => hD v (by simp [Stmt.vars, hv])) h
    exact ⟨.block t0, s0⟩
  | loop s ih =>
    intro ξ Γ F Δ hs hD h
    unfold checkStmt2 at h
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
    unfold checkStmt2 at h
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
