import C.A2Expr

/-!
# C6: A2's core right-hand sides, decided (AGORA-970)

`inferRhs2` computes A2's `RhsT` for the core forms: an integer
expression, a fresh `Vec`, a move or copy of a binding, a borrow, an
element, a view or a slice element (not fresh), and `vec_pop` /
`vec_remove`. A2 adds side conditions that quantify over the whole
context. `NoPin` says no borrowed parameter changes the binding by name,
and `DtorSafe` says no armed destructor views it. Over a supported context
(`Supported2 Γ D`) both are decided by loops over `D` (`noPinB_sound`,
`dtorSafeB_sound`). `inferRhs2_sound` gives `RhsT`. The other A2 forms
(fields, enums, closures, shares, regions) and fresh borrows follow.
-/

namespace C

open A2

/-- `Γ` names nothing outside `D`. -/
def Supported2 (Γ : Ctx) (D : List Var) : Prop := ∀ v, v ∉ D → Γ v = none

theorem mem_of_some2 {Γ : Ctx} {D : List Var} (hs : Supported2 Γ D) {v : Var} {E : Entry}
    (h : Γ v = some E) : v ∈ D := by
  apply Classical.byContradiction; intro hn; rw [hs v hn] at h; cases h

/-- `NoPin Γ x`, decided over the domain. -/
def noPinB (D : List Var) (Γ : Ctx) (x : Var) : Bool :=
  D.all fun p => match Γ p with
    | some E => !(decide (E.mode = .rootb)) || E.vdeps.all (fun d => decide (d.kind.bound = .none) || decide (d.root ≠ x))
    | none => true

theorem noPinB_sound {D : List Var} {Γ : Ctx} {x : Var} (hs : Supported2 Γ D) (h : noPinB D Γ x = true) :
    NoPin Γ x := by
  intro p E hE hm d hd hb
  have := List.all_eq_true.mp h p (mem_of_some2 hs hE)
  rw [hE] at this
  simp only [Bool.or_eq_true, Bool.not_eq_true', decide_eq_false_iff_not] at this
  rcases this with h0 | h0
  · exact absurd hm h0
  · have := List.all_eq_true.mp h0 d hd
    simp only [Bool.or_eq_true, decide_eq_true_eq] at this
    rcases this with h1 | h1
    · exact absurd h1 hb
    · exact h1

/-- `DtorSafe Γ e hv x`, decided over the domain. -/
def dtorSafeB (D : List Var) (Γ : Ctx) (e : Eff) (hv : Bool) (x : Var) : Bool :=
  D.all fun v => match Γ v with
    | some E => !E.dtor || !E.mode.ownSlot || !hitsMem e hv x E
    | none => true

theorem dtorSafeB_sound {D : List Var} {Γ : Ctx} {e : Eff} {hv : Bool} {x : Var} (hs : Supported2 Γ D)
    (h : dtorSafeB D Γ e hv x = true) : DtorSafe Γ e hv x := by
  intro v E hE hd ho
  have := List.all_eq_true.mp h v (mem_of_some2 hs hE)
  rw [hE] at this
  simp only [hd, ho, Bool.not_true, Bool.false_or, Bool.not_eq_true'] at this
  exact this

/-- AGORA-374: `NoIdx`, decided over the supported bindings. -/
def noIdxB (D : List Var) (Γ : Ctx) (x : Var) : Bool :=
  D.all fun v => match Γ v with
    | some E => !((E.ty != .int || E.mode == .rootb) && (E.live || (E.dtor && E.mode.ownSlot))) ||
        E.vdeps.all fun d => !(d.root == x) || match d.kind with | .innerAt _ => false | _ => true
    | none => true

theorem noIdxB_sound {D : List Var} {Γ : Ctx} {x : Var} (hs : Supported2 Γ D)
    (h : noIdxB D Γ x = true) : NoIdx Γ x := by
  rintro k ⟨v, E, hE, hn, hl, hd⟩ i rfl
  have := List.all_eq_true.mp h v (mem_of_some2 hs hE)
  rw [hE] at this
  have hg : ((E.ty != .int || E.mode == .rootb) && (E.live || (E.dtor && E.mode.ownSlot))) = true := by
    rcases hn with h1 | h1 <;> rcases hl with h2 | ⟨h2, h3⟩ <;> simp [h1, h2, h3]
  rw [hg] at this
  have := List.all_eq_true.mp (by simpa using this) _ hd
  simp at this

/-- `canDo`, decided. -/
def canDoB2 (m : Mode) (e : Eff) : Bool :=
  match m with
  | .own => true
  | .inout b => decide (e.le b)
  | _ => false

theorem canDoB2_sound {m : Mode} {e : Eff} (h : canDoB2 m e = true) : canDo m e := by
  unfold canDoB2 at h
  split at h
  · exact Or.inl rfl
  · rename_i b; exact Or.inr ⟨b, rfl, of_decide_eq_true h⟩
  · cases h

def liveE2 (Γ : Ctx) (y : Var) : Option Entry :=
  match Γ y with
  | some E => if E.live then some E else none
  | none => none

theorem liveE2_some {Γ : Ctx} {y : Var} {E : Entry} (h : liveE2 Γ y = some E) : Γ y = some E ∧ E.live = true := by
  unfold liveE2 at h
  split at h
  · rename_i E' hE
    split at h
    · rename_i hl; cases h; exact ⟨hE, hl⟩
    · cases h
  · cases h

def vecElem2 : Ty → Option Ty
  | .vec t => some t
  | _ => none

def sliceElem2 : Ty → Option Ty
  | .slice t => some t
  | _ => none

theorem vecElem2_some {ty t : Ty} (h : vecElem2 ty = some t) : ty = .vec t := by
  cases ty <;> simp [vecElem2] at h; subst h; rfl

theorem sliceElem2_some {ty t : Ty} (h : sliceElem2 ty = some t) : ty = .slice t := by
  cases ty <;> simp [sliceElem2] at h; subst h; rfl

/-- A2's `RhsT` for the core forms, computed. -/
def inferRhs2 (D : List Var) (Γ : Ctx) (F : List Var) : Rhs → Option (Entry × Ctx)
  | .expr e => if checkExpr2 Γ e then some (intE, Γ) else none
  | .new t => if (Ty.vec t).ok then some (⟨.vec t, .own, true, [], [], false, false, false, false⟩, Γ) else none
  | .var y => match liveE2 Γ y with
    | some E => match E.mode with
      | .own => if decide (y ∉ F) && noPinB D Γ y && dtorSafeB D Γ .replace false y then
          some (⟨E.ty, .own, true, [], E.held, false, false, false, false⟩,
            setE (kill .replace false y Γ) y { E with live := false, dtor := false })
        else none
      | .rootb => some (⟨E.ty, .bor, true, derive y E .self, E.held, false, false, false, false⟩, Γ)
      | .bor => some ({ E with dtor := false, dbind := false }, Γ)
      | _ => none
    | none => none
  | .borrow y => match liveE2 Γ y with
    | some E => match vecElem2 E.ty with
      | some _ => some (⟨E.ty, .bor, true, derive y E .self, E.held, false, false, false, false⟩, Γ)
      | none => none
    | none => none
  | .at y i => match liveE2 Γ y with
    | some E => match vecElem2 E.ty with
      | some t => if checkExpr2 Γ i then some ({ elemE y E t with fresh := false }, Γ) else none
      | none => none
    | none => none
  | .view y => match liveE2 Γ y with
    | some E => match vecElem2 E.ty with
      | some t => if t.holdsView then none
          else some (⟨.slice t, .bor, true, derive y E .view, E.held, false, false, false, false⟩, Γ)
      | none => none
    | none => none
  | .sat y i => match liveE2 Γ y with
    | some E => match sliceElem2 E.ty with
      | some t => if checkExpr2 Γ i then some ({ elemE y E t with fresh := false }, Γ) else none
      | none => none
    | none => none
  -- AGORA-980: a literal's text handed back as a view, valid with no dependency
  | .slit _ => some (⟨.slice .int, .bor, true, [], [], false, false, false, false⟩, Γ)
  | .pop y => match liveE2 Γ y with
    | some E => match vecElem2 E.ty with
      | some t => if canDoB2 E.mode .drop && decide (y ∉ F) && dtorSafeB D Γ .drop t.holdsView y then
          some (popE y E t, kill .drop t.holdsView y Γ) else none
      | none => none
    | none => none
  | .remove y i => match liveE2 Γ y with
    | some E => match vecElem2 E.ty with
      | some t => if canDoB2 E.mode .drop && decide (y ∉ F) && dtorSafeB D Γ .drop t.holdsView y && checkExpr2 Γ i then
          some (popE y E t, kill .drop t.holdsView y Γ) else none
      | none => none
    | none => none
  | _ => none

theorem inferRhs2_sound {D : List Var} {Γ : Ctx} {F : List Var} {r : Rhs} {E : Entry} {Γ1 : Ctx}
    (hs : Supported2 Γ D) (h : inferRhs2 D Γ F r = some (E, Γ1)) : RhsT Γ F r E Γ1 := by
  cases r with
  | expr e =>
    simp only [inferRhs2] at h; split at h
    · rename_i he; cases h; exact .expr (checkExpr2_sound he)
    · cases h
  | new t =>
    simp only [inferRhs2] at h; split at h
    · rename_i ht; cases h; exact .new ht
    · cases h
  | slit n =>
    simp only [inferRhs2] at h; cases h; exact .slit
  | var y =>
    simp only [inferRhs2] at h
    split at h
    · rename_i E0 hE0
      obtain ⟨hy, hl⟩ := liveE2_some hE0
      split at h
      · rename_i hm
        split at h
        · rename_i hc
          simp only [Bool.and_eq_true, decide_eq_true_eq] at hc
          obtain ⟨⟨hF, hp⟩, hd⟩ := hc
          cases h; exact .moveOwn hy hl hm hF (noPinB_sound hs hp) (dtorSafeB_sound hs hd)
        · cases h
      · rename_i hm; cases h; exact .copyRoot hy hl hm
      · rename_i hm; cases h; exact .copyBor hy hl hm
      · cases h
    · cases h
  | borrow y =>
    simp only [inferRhs2] at h
    split at h
    · rename_i E0 hE0
      obtain ⟨hy, hl⟩ := liveE2_some hE0
      split at h
      · rename_i t ht; cases h
        exact .borrow (f := false) hy hl (vecElem2_some ht) (fun e => by cases e)
      · cases h
    · cases h
  | «at» y i =>
    simp only [inferRhs2] at h
    split at h
    · rename_i E0 hE0
      obtain ⟨hy, hl⟩ := liveE2_some hE0
      split at h
      · rename_i t ht
        split at h
        · rename_i hi; cases h
          exact .at (f := false) hy hl (vecElem2_some ht) (checkExpr2_sound hi) (fun e => by cases e)
        · cases h
      · cases h
    · cases h
  | view y =>
    simp only [inferRhs2] at h
    split at h
    · rename_i E0 hE0
      obtain ⟨hy, hl⟩ := liveE2_some hE0
      split at h
      · rename_i t ht
        split at h
        · cases h
        · rename_i hv; cases h
          exact .view (f := false) (h := false) hy hl (vecElem2_some ht) (by simpa using hv)
            (fun e => by cases e) (fun e => by cases e)
      · cases h
    · cases h
  | sat y i =>
    simp only [inferRhs2] at h
    split at h
    · rename_i E0 hE0
      obtain ⟨hy, hl⟩ := liveE2_some hE0
      split at h
      · rename_i t ht
        split at h
        · rename_i hi; cases h
          exact .sat (f := false) hy hl (sliceElem2_some ht) (checkExpr2_sound hi) (fun e => by cases e)
        · cases h
      · cases h
    · cases h
  | pop y =>
    simp only [inferRhs2] at h
    split at h
    · rename_i E0 hE0
      obtain ⟨hy, hl⟩ := liveE2_some hE0
      split at h
      · rename_i t ht
        split at h
        · rename_i hc
          simp only [Bool.and_eq_true, decide_eq_true_eq] at hc
          obtain ⟨⟨hcd, hF⟩, hd⟩ := hc
          cases h; exact .pop hy hl (vecElem2_some ht) (canDoB2_sound hcd) hF (dtorSafeB_sound hs hd)
        · cases h
      · cases h
    · cases h
  | remove y i =>
    simp only [inferRhs2] at h
    split at h
    · rename_i E0 hE0
      obtain ⟨hy, hl⟩ := liveE2_some hE0
      split at h
      · rename_i t ht
        split at h
        · rename_i hc
          simp only [Bool.and_eq_true, decide_eq_true_eq] at hc
          obtain ⟨⟨⟨hcd, hF⟩, hd⟩, hi⟩ := hc
          cases h
          exact .remove hy hl (vecElem2_some ht) (canDoB2_sound hcd) hF (dtorSafeB_sound hs hd) (checkExpr2_sound hi)
        · cases h
      · cases h
    · cases h
  | _ => simp [inferRhs2] at h

end C
