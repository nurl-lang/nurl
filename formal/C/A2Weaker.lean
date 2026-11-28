module

public import C.A2Panic
public import A2.Ctx

@[expose] public section

/-!
# C7w: A2's `Weaker` decided; joins by weakening (AGORA-975)

A2's `sub` rule types a statement from a weaker context or lets it end in
one (`Weaker`, entry by entry `EntryWeaker`, then `CtxWF` and `NameWF`).
C7's `ite` joined two arms only where they ended in the same context, so a
binding moved on one path and kept on the other (nurlc's drop flags: the
slot may still own, MEMORY.md §2.4) was refused. Here `Weaker` is decided
over the finite domain (`weaker2B_sound`), and `joinCand` proposes a context
both arms' ends weaken to: an entry the arms disagree on is dead, holds and
reaches what either did, and runs a destructor if either may. The checker
verifies the proposal (`weaker2B` both ways), so the proposal itself needs
no proof; only `joinCand_supported` does.
-/

namespace C

open A2

def subW (a b : List Dep) : Bool := a.all (fun d => decide (d ∈ b))

theorem subW_sound {a b : List Dep} (h : subW a b = true) : a ⊆ b := fun d hd =>
  of_decide_eq_true (List.all_eq_true.mp h d hd)

/-- `EntryWeaker`, decided. -/
def entryWeaker2B (E E' : Entry) : Bool :=
  decide (E'.ty = E.ty) && decide (E'.mode = E.mode) && (!fixedB E || decide (E' = E)) &&
  (!E'.live || (E.live && (E.mode.ownSlot || subW E.path E'.path) && subW E.held E'.held)) &&
  (!E.dtor || (E'.dtor && subW E.held E'.held)) &&
  decide (E'.dbind = E.dbind) &&
  (!E'.dtor || E.dtor || E.dbind) &&
  (!(E.dbind && E.mode.ownSlot && decide (E.ty ≠ .int ∨ E.mode = .rootb)) ||
    (E'.held.all (fun d => d.kind.isName || decide (d ∈ E.held)) &&
     E.held.all (fun d => d.kind.isName || decide (d ∈ E'.held)))) &&
  (!(E'.live && decide (E'.ty ≠ .int) && decide (E'.mode = .bor) && E'.fresh) ||
    (E.fresh && subW E'.path E.path)) &&
  (!(decide (E'.ty ≠ .int) && decide (E'.mode = .bor) && E'.heldFresh) || E.heldFresh)

theorem entryWeaker2B_sound {E E' : Entry} (h : entryWeaker2B E E' = true) : EntryWeaker E E' := by
  simp only [entryWeaker2B, Bool.and_eq_true, Bool.or_eq_true, Bool.not_eq_true', decide_eq_true_eq] at h
  obtain ⟨⟨⟨⟨⟨⟨⟨⟨⟨hty, hm⟩, hfx⟩, hl⟩, hd⟩, hdb⟩, hr⟩, hdh⟩, hfr⟩, hhf⟩ := h
  refine ⟨hty, hm, ?_, ?_, ?_, hdb, ?_, ?_, ?_, ?_⟩
  · intro hf
    rcases hfx with h0 | h0
    · exact absurd hf (fixedB_sound h0)
    · exact h0
  · intro hl'
    rcases hl with h0 | ⟨⟨h1, h2⟩, h3⟩
    · rw [hl'] at h0; cases h0
    · refine ⟨h1, fun ho => ?_, subW_sound h3⟩
      rcases h2 with h2 | h2
      · rw [ho] at h2; cases h2
      · exact subW_sound h2
  · intro hd'
    rcases hd with h0 | ⟨h1, h2⟩
    · rw [hd'] at h0; cases h0
    · exact ⟨h1, subW_sound h2⟩
  · intro hd'
    rcases hr with (h0 | h0) | h0
    · rw [hd'] at h0; cases h0
    · exact Or.inl h0
    · exact Or.inr h0
  · intro hdb' ho hk d hn
    rcases hdh with h0 | ⟨h1, h2⟩
    · simp [hdb', ho, hk] at h0
    · constructor
      · intro hd1
        have := List.all_eq_true.mp h1 d hd1
        simp only [Bool.or_eq_true, hn] at this
        rcases this with h | h
        · cases h
        · exact of_decide_eq_true h
      · intro hd1
        have := List.all_eq_true.mp h2 d hd1
        simp only [Bool.or_eq_true, hn] at this
        rcases this with h | h
        · cases h
        · exact of_decide_eq_true h
  · intro hl' hi hb hf
    rcases hfr with h0 | ⟨h1, h2⟩
    · simp [hl', hi, hb, hf] at h0
    · exact ⟨h1, subW_sound h2⟩
  · intro hi hb hf
    rcases hhf with h0 | h0
    · simp [hi, hb, hf] at h0
    · exact h0

/-- `Weaker Γ Γ'` over the domain, decided. -/
def weaker2B (D : List Var) (Γ Γ' : Ctx) : Bool :=
  (D.all fun v => match Γ v, Γ' v with
    | none, none => true
    | some E, some E' => entryWeaker2B E E'
    | _, _ => false) && ctxWF2B D Γ' && nameWFB D Γ'

theorem weaker2B_sound {D : List Var} {Γ Γ' : Ctx} (hs : Supported2 Γ D) (hs' : Supported2 Γ' D)
    (h : weaker2B D Γ Γ' = true) : Weaker Γ Γ' := by
  simp only [weaker2B, Bool.and_eq_true] at h
  obtain ⟨⟨h1, h2⟩, h3⟩ := h
  refine ⟨fun v => ?_, ctxWF2B_sound hs' h2, nameWFB_sound hs' h3⟩
  by_cases hv : v ∈ D
  · have := List.all_eq_true.mp h1 v hv
    revert this
    cases ha : Γ v <;> cases hb : Γ' v <;> intro this
    · exact ⟨Iff.rfl, fun E E' e1 _ => by cases e1⟩
    · cases this
    · cases this
    · rename_i E E'
      exact ⟨by simp, fun E1 E1' e1 e2 => by
        cases e1; cases e2; exact entryWeaker2B_sound this⟩
  · rw [hs v hv, hs' v hv]
    exact ⟨Iff.rfl, fun E _ e1 _ => by cases e1⟩

/-- `Weaker Γ Γ`, where `Γ` is well formed. -/
theorem weaker_self2 {D : List Var} {Γ : Ctx} (hs : Supported2 Γ D)
    (h1 : ctxWF2B D Γ = true) (h2 : nameWFB D Γ = true) : Weaker Γ Γ :=
  ⟨fun v => ⟨Iff.rfl, fun E E' e1 e2 => by rw [e1] at e2; cases e2; exact EntryWeaker.refl _⟩,
    ctxWF2B_sound hs h1, nameWFB_sound hs h2⟩

/-- `a`, then what of `b` it lacks. -/
def depUnion (a b : List Dep) : List Dep := a ++ b.filter (fun d => !decide (d ∈ a))

/-- Two arms' entries for one binding, joined: live only if both are, what
    either holds or reaches, armed if either is, fresh only if both are on
    one path. -/
def joinE (Ea Eb : Entry) : Entry :=
  { Ea with live := Ea.live && Eb.live, path := depUnion Ea.path Eb.path,
            held := depUnion Ea.held Eb.held, dtor := Ea.dtor || Eb.dtor,
            fresh := Ea.fresh && Eb.fresh && decide (Ea.path = Eb.path),
            heldFresh := Ea.heldFresh && Eb.heldFresh }

/-- A context both arms' ends may weaken to (the checker verifies it). -/
def joinCand (Δa Δb : Ctx) : Ctx := fun v =>
  match Δa v, Δb v with
  | some Ea, some Eb => if Ea = Eb then some Ea else some (joinE Ea Eb)
  | _, _ => Δa v

theorem joinCand_supported {D : List Var} {Δa Δb : Ctx} (ha : Supported2 Δa D) :
    Supported2 (joinCand Δa Δb) D := by
  intro v hv
  have h0 := ha v hv
  simp only [joinCand, h0]

/-- A context read from a finite table: the entry listed for `v`, none for a
    slot the table does not list. -/
def ctxOfList (l : List (Var × Option Entry)) : Ctx := fun v =>
  match l.lookup v with
  | some e => e
  | none => none

theorem lookup_map_none {D : List Var} {f : Var → Option Entry} {v : Var} (h : v ∉ D) :
    (D.map fun w => (w, f w)).lookup v = none := by
  induction D with
  | nil => rfl
  | cons a D ih =>
    have ha : v ≠ a := fun e => h (e ▸ List.mem_cons_self ..)
    have hD : v ∉ D := fun hm => h (List.mem_cons_of_mem _ hm)
    simp only [List.map_cons, List.lookup_cons]
    have : (v == a) = false := by simpa using ha
    rw [this]
    exact ih hD

/-- The join candidate over `D`, as a table: data, built once where the
    join is decided. A checker passes on `ctxOfList` of it, so a later read
    costs one scan of `D` and never replays the arms the join was built from
    (github#2242's review: a chain of joins that each read both arms costs
    2ⁿ reads after `n` joins). It is a `List`, not a `Ctx`, so the compiler
    cannot eta-expand it into a function that rebuilds it on every read. -/
def joinTbl (D : List Var) (Δa Δb : Ctx) : List (Var × Option Entry) :=
  D.map fun v => (v, joinCand Δa Δb v)

theorem joinTbl_supported (D : List Var) (Δa Δb : Ctx) : Supported2 (ctxOfList (joinTbl D Δa Δb)) D := by
  intro v hv
  simp only [ctxOfList, joinTbl, lookup_map_none hv]

end C
