module

public import C.A2Panic
public import C.Dedup
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

/-- Entrywise `Weaker` over the domain, decided (without `CtxWF`/`NameWF`). -/
def weakerEntries2B (D : List Var) (Γ Γ' : Ctx) : Bool :=
  D.all fun v => match Γ v, Γ' v with
    | none, none => true
    | some E, some E' => E == E' || entryWeaker2B E E'
    | _, _ => false

theorem weakerEntries2B_sound {D : List Var} {Γ Γ' : Ctx} (hs : Supported2 Γ D) (hs' : Supported2 Γ' D)
    (h : weakerEntries2B D Γ Γ' = true) :
    ∀ v, (Γ v = none ↔ Γ' v = none) ∧ ∀ E E', Γ v = some E → Γ' v = some E' → EntryWeaker E E' := by
  intro v
  by_cases hv : v ∈ D
  · have := List.all_eq_true.mp h v hv
    revert this
    cases ha : Γ v <;> cases hb : Γ' v <;> intro this
    · exact ⟨Iff.rfl, fun E E' e1 _ => by cases e1⟩
    · cases this
    · cases this
    · rename_i E E'
      refine ⟨by simp, fun E1 E1' e1 e2 => ?_⟩
      cases e1; cases e2
      simp only [Bool.or_eq_true, beq_iff_eq] at this
      rcases this with rfl | hw
      · exact EntryWeaker.refl _
      · exact entryWeaker2B_sound hw
  · rw [hs v hv, hs' v hv]
    exact ⟨Iff.rfl, fun E _ e1 _ => by cases e1⟩

/-- `CtxWF` checked by walking a `CtxT` directly (no outer lookups). -/
def ctxWF2BTree (T : CtxT Entry) : Bool :=
  let Γ := T.get
  T.all fun E =>
    (!E.live || !(decide (E.ty ≠ .int ∨ E.mode = .rootb)) || rootsHave Γ (roots E.vdeps)) &&
    (!E.dbind || !E.mode.ownSlot || !(decide (E.ty ≠ .int ∨ E.mode = .rootb)) ||
      rootsHave Γ ((E.vdeps.filter (fun d => !d.kind.isName)).map (·.root))) &&
    (!E.dtor || E.dbind) && (!E.dbind || E.ty.holdsView)

theorem ctxWF2BTree_sound {T : CtxT Entry} (h : ctxWF2BTree T = true) : CtxWF T.get := by
  have get : ∀ v E, T.get v = some E → _ := fun v E hE => CtxT.all_sound h v E hE
  refine ⟨fun v E hE hl hk r hr => ?_, fun v E hE hd ho hk d hd' hn => ?_, fun v E hE hd => ?_, fun v E hE hd => ?_⟩
  · have := get v E hE
    simp only [Bool.and_eq_true, Bool.or_eq_true, Bool.not_eq_true', decide_eq_false_iff_not] at this
    rcases this.1.1.1 with (h0 | h0) | h0
    · rw [hl] at h0; cases h0
    · exact absurd hk h0
    · exact rootsHave_sound h0 r hr
  · have := get v E hE
    simp only [Bool.and_eq_true, Bool.or_eq_true, Bool.not_eq_true', decide_eq_false_iff_not] at this
    rcases this.1.1.2 with ((h0 | h0) | h0) | h0
    · rw [hd] at h0; cases h0
    · rw [ho] at h0; cases h0
    · exact absurd hk h0
    · exact rootsHave_sound h0 d.root (List.mem_map.mpr ⟨d, List.mem_filter.mpr ⟨hd', by simp [hn]⟩, rfl⟩)
  · have := get v E hE
    simp only [Bool.and_eq_true, Bool.or_eq_true, Bool.not_eq_true'] at this
    rcases this.1.2 with h0 | h0
    · rw [hd] at h0; cases h0
    · exact h0
  · have := get v E hE
    simp only [Bool.and_eq_true, Bool.or_eq_true, Bool.not_eq_true'] at this
    rcases this.2 with h0 | h0
    · rw [hd] at h0; cases h0
    · exact h0

/-- `NameWF` checked by walking a `CtxT` directly (no outer lookups). -/
def nameWFBTree (T : CtxT Entry) : Bool :=
  let Γ := T.get
  T.all fun E => !E.live || !(decide (E.ty ≠ .int ∨ E.mode = .rootb)) || depsNamedB Γ E.vdeps

theorem nameWFBTree_sound {T : CtxT Entry} (h : nameWFBTree T = true) : NameWF T.get := by
  intro v E hE hl hk
  have := CtxT.all_sound h v E hE
  simp only [Bool.or_eq_true, Bool.not_eq_true', decide_eq_false_iff_not] at this
  rcases this with (h0 | h0) | h0
  · rw [hl] at h0; cases h0
  · exact absurd hk h0
  · exact depsNamedB_sound h0

/-- `Weaker Γ Γ'` over the domain, decided. -/
def weaker2B (D : List Var) (Γ Γ' : Ctx) : Bool :=
  weakerEntries2B D Γ Γ' && ctxWF2B D Γ' && nameWFB D Γ'

theorem weaker2B_sound {D : List Var} {Γ Γ' : Ctx} (hs : Supported2 Γ D) (hs' : Supported2 Γ' D)
    (h : weaker2B D Γ Γ' = true) : Weaker Γ Γ' := by
  simp only [weaker2B, Bool.and_eq_true] at h
  obtain ⟨⟨h1, h2⟩, h3⟩ := h
  exact ⟨weakerEntries2B_sound hs hs' h1, ctxWF2B_sound hs' h2, nameWFB_sound hs' h3⟩

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

/-- A context read from a finite radix tree. -/
def ctxOfList (T : CtxT Entry) : Ctx := T.get

/-- The join candidate over `D`, as a binary radix tree: built once where the
    join is decided, so every later read takes `O(bit-length of key)` steps
    (bounded by the tree depth) and never replays the arms the join was built
    from. -/
def joinTbl (D : List Var) (Δa Δb : Ctx) : CtxT Entry :=
  tblOf D (joinCand Δa Δb)

theorem joinTbl_supported (D : List Var) (Δa Δb : Ctx) : Supported2 (ctxOfList (joinTbl D Δa Δb)) D :=
  fun _ hv => ctxOfTbl_none (joinCand Δa Δb) hv

/-- Check both arms' weakening into a materialized join tree `T` once (single
    tree build, single `ctxWF2BTree` and `nameWFBTree` pass). -/
def joinCheckAux (D : List Var) (Δa Δb : Ctx) (T : CtxT Entry) : Option Ctx :=
  if ctxWF2BTree T && nameWFBTree T &&
      weakerEntries2B D Δa T.get && weakerEntries2B D Δb T.get then
    some T.get
  else none

/-- Join two arms' end contexts of an `ite` by weakening. -/
def joinIte2 (D : List Var) (Γ Δa Δb : Ctx) : Option Ctx :=
  if ctxWF2B D Γ && nameWFB D Γ then
    joinCheckAux D Δa Δb (joinTbl D Δa Δb)
  else none

theorem joinIte2_sound {D : List Var} {Γ Δa Δb J : Ctx}
    (hs : Supported2 Γ D) (hsa : Supported2 Δa D) (hsb : Supported2 Δb D)
    (h : joinIte2 D Γ Δa Δb = some J) :
    Supported2 J D ∧ Weaker Γ Γ ∧ Weaker Δa J ∧ Weaker Δb J := by
  unfold joinIte2 at h
  split at h
  · rename_i hΓ
    simp only [Bool.and_eq_true] at hΓ
    unfold joinCheckAux at h
    split at h
    · rename_i hJ
      simp only [Option.some.injEq] at h
      subst h
      simp only [Bool.and_eq_true] at hJ
      obtain ⟨⟨⟨hwf, hnw⟩, hwa⟩, hwb⟩ := hJ
      have hsJ : Supported2 (joinTbl D Δa Δb).get D := joinTbl_supported D Δa Δb
      have wfJ : CtxWF (joinTbl D Δa Δb).get := ctxWF2BTree_sound hwf
      have nwJ : NameWF (joinTbl D Δa Δb).get := nameWFBTree_sound hnw
      exact ⟨hsJ, weaker_self2 hs hΓ.1 hΓ.2,
        ⟨weakerEntries2B_sound hsa hsJ hwa, wfJ, nwJ⟩,
        ⟨weakerEntries2B_sound hsb hsJ hwb, wfJ, nwJ⟩⟩
    · cases h
  · cases h

/-- Combined `CtxWF` and `NameWF` checked in a single walk of `T`. -/
def wfTree (T : CtxT Entry) : Bool :=
  let Γ := T.get
  T.all fun E =>
    (!E.live || !(decide (E.ty ≠ .int ∨ E.mode = .rootb)) ||
      (rootsHave Γ (roots E.vdeps) && depsNamedB Γ E.vdeps)) &&
    (!E.dbind || !E.mode.ownSlot || !(decide (E.ty ≠ .int ∨ E.mode = .rootb)) ||
      rootsHave Γ ((E.vdeps.filter (fun d => !d.kind.isName)).map (·.root))) &&
    (!E.dtor || E.dbind) && (!E.dbind || E.ty.holdsView)

theorem wfTree_sound {T : CtxT Entry} (h : wfTree T = true) : CtxWF T.get ∧ NameWF T.get := by
  have get : ∀ v E, T.get v = some E → _ := fun v E hE => CtxT.all_sound h v E hE
  refine ⟨⟨fun v E hE hl hk r hr => ?_, fun v E hE hd ho hk d hd' hn => ?_,
      fun v E hE hd => ?_, fun v E hE hd => ?_⟩, fun v E hE hl hk => ?_⟩
  · have := get v E hE
    simp only [Bool.and_eq_true, Bool.or_eq_true, Bool.not_eq_true', decide_eq_false_iff_not] at this
    rcases this.1.1.1 with (h0 | h0) | h0
    · rw [hl] at h0; cases h0
    · exact absurd hk h0
    · exact rootsHave_sound h0.1 r hr
  · have := get v E hE
    simp only [Bool.and_eq_true, Bool.or_eq_true, Bool.not_eq_true', decide_eq_false_iff_not] at this
    rcases this.1.1.2 with ((h0 | h0) | h0) | h0
    · rw [hd] at h0; cases h0
    · rw [ho] at h0; cases h0
    · exact absurd hk h0
    · exact rootsHave_sound h0 d.root (List.mem_map.mpr ⟨d, List.mem_filter.mpr ⟨hd', by simp [hn]⟩, rfl⟩)
  · have := get v E hE
    simp only [Bool.and_eq_true, Bool.or_eq_true, Bool.not_eq_true'] at this
    rcases this.1.2 with h0 | h0
    · rw [hd] at h0; cases h0
    · exact h0
  · have := get v E hE
    simp only [Bool.and_eq_true, Bool.or_eq_true, Bool.not_eq_true'] at this
    rcases this.2 with h0 | h0
    · rw [hd] at h0; cases h0
    · exact h0
  · have := get v E hE
    simp only [Bool.and_eq_true, Bool.or_eq_true, Bool.not_eq_true', decide_eq_false_iff_not] at this
    rcases this.1.1.1 with (h0 | h0) | h0
    · rw [hl] at h0; cases h0
    · exact absurd hk h0
    · exact depsNamedB_sound h0.2

def joinOptEntry (oa ob : Option Entry) : Option (Option Entry) :=
  match oa, ob with
  | none, none => some none
  | some Ea, some Eb =>
    if Ea == Eb then some (some Ea)
    else
      let Ej := joinE Ea Eb
      if entryWeaker2B Ea Ej && entryWeaker2B Eb Ej then some (some Ej) else none
  | _, _ => none

theorem joinOptEntry_sound {oa ob oj : Option Entry} (h : joinOptEntry oa ob = some oj) :
    ((oa = none ↔ oj = none) ∧ ∀ Ea Ej, oa = some Ea → oj = some Ej → EntryWeaker Ea Ej) ∧
    ((ob = none ↔ oj = none) ∧ ∀ Eb Ej, ob = some Eb → oj = some Ej → EntryWeaker Eb Ej) := by
  unfold joinOptEntry at h
  cases oa <;> cases ob
  · simp only [Option.some.injEq] at h; subst h
    exact ⟨⟨Iff.rfl, fun _ _ h1 _ => by cases h1⟩, ⟨Iff.rfl, fun _ _ h1 _ => by cases h1⟩⟩
  · cases h
  · cases h
  · rename_i Ea Eb
    simp only at h
    split at h
    · rename_i heq
      simp only [beq_iff_eq] at heq; subst heq
      simp only [Option.some.injEq] at h; subst h
      exact ⟨⟨Iff.rfl, fun _ _ h1 h2 => by cases h1; cases h2; exact EntryWeaker.refl _⟩,
             ⟨Iff.rfl, fun _ _ h1 h2 => by cases h1; cases h2; exact EntryWeaker.refl _⟩⟩
    · split at h
      · rename_i hw
        simp only [Bool.and_eq_true] at hw
        simp only [Option.some.injEq] at h; subst h
        exact ⟨⟨by simp, fun _ _ h1 h2 => by cases h1; cases h2; exact entryWeaker2B_sound hw.1⟩,
               ⟨by simp, fun _ _ h1 h2 => by cases h1; cases h2; exact entryWeaker2B_sound hw.2⟩⟩
      · cases h

/-- Simultaneous join and entrywise weakening check on two `CtxT` trees. -/
def joinAndCheckTree : CtxT Entry → CtxT Entry → Option (CtxT Entry)
  | .empty, .empty => some .empty
  | .empty, tb => if tb.allNone then some .empty else none
  | ta, .empty => if ta.allNone then some .empty else none
  | .node va la ra, .node vb lb rb =>
    match joinOptEntry va vb with
    | none => none
    | some vj =>
      match joinAndCheckTree la lb, joinAndCheckTree ra rb with
      | some lj, some rj => some (CtxT.mkNode vj lj rj)
      | _, _ => none

theorem joinAndCheckTree_sound : ∀ {Ta Tb TJ : CtxT Entry},
    joinAndCheckTree Ta Tb = some TJ →
    (∀ v, (Ta.get v = none ↔ TJ.get v = none) ∧
          ∀ Ea Ej, Ta.get v = some Ea → TJ.get v = some Ej → EntryWeaker Ea Ej) ∧
    (∀ v, (Tb.get v = none ↔ TJ.get v = none) ∧
          ∀ Eb Ej, Tb.get v = some Eb → TJ.get v = some Ej → EntryWeaker Eb Ej)
  | .empty, .empty, TJ, h => by
    simp only [joinAndCheckTree, Option.some.injEq] at h; subst h
    exact ⟨fun _ => ⟨Iff.rfl, fun _ _ h1 _ => by cases h1⟩,
           fun _ => ⟨Iff.rfl, fun _ _ h1 _ => by cases h1⟩⟩
  | .empty, .node vb lb rb, TJ, h => by
    simp only [joinAndCheckTree] at h
    split at h
    · rename_i han
      simp only [Option.some.injEq] at h; subst h
      have hnb := CtxT.allNone_sound han
      exact ⟨fun _ => ⟨Iff.rfl, fun _ _ h1 _ => by cases h1⟩,
             fun v => ⟨by rw [hnb v]; rfl, fun _ _ h1 _ => by rw [hnb v] at h1; cases h1⟩⟩
    · cases h
  | .node va la ra, .empty, TJ, h => by
    simp only [joinAndCheckTree] at h
    split at h
    · rename_i han
      simp only [Option.some.injEq] at h; subst h
      have hna := CtxT.allNone_sound han
      exact ⟨fun v => ⟨by rw [hna v]; rfl, fun _ _ h1 _ => by rw [hna v] at h1; cases h1⟩,
             fun _ => ⟨Iff.rfl, fun _ _ h1 _ => by cases h1⟩⟩
    · cases h
  | .node va la ra, .node vb lb rb, TJ, h => by
    simp only [joinAndCheckTree] at h
    split at h
    · cases h
    · rename_i vj hv
      split at h
      · rename_i lj rj hl hr
        simp only [Option.some.injEq] at h; subst h
        obtain ⟨hva, hvb⟩ := joinOptEntry_sound hv
        obtain ⟨hla, hlb⟩ := joinAndCheckTree_sound hl
        obtain ⟨hra, hrb⟩ := joinAndCheckTree_sound hr
        refine ⟨fun v => ?_, fun v => ?_⟩
        · rw [CtxT.get_mkNode]
          unfold CtxT.get
          split
          · exact hva
          · split
            · exact hla _
            · exact hra _
        · rw [CtxT.get_mkNode]
          unfold CtxT.get
          split
          · exact hvb
          · split
            · exact hlb _
            · exact hrb _
      · cases h

/-- Join two `CtxT` arm end-contexts in `O(|T|)` tree walks (no lookups). -/
def joinIte2Tree (T Ta Tb : CtxT Entry) : Option (CtxT Entry) :=
  if wfTree T then
    match joinAndCheckTree Ta Tb with
    | some TJ => if wfTree TJ then some TJ else none
    | none => none
  else none

theorem joinIte2Tree_sound {D : List Var} {T Ta Tb TJ : CtxT Entry}
    (hsa : Supported2 Ta.get D) (h : joinIte2Tree T Ta Tb = some TJ) :
    Supported2 TJ.get D ∧ Weaker T.get T.get ∧ Weaker Ta.get TJ.get ∧ Weaker Tb.get TJ.get := by
  unfold joinIte2Tree at h
  split at h
  · rename_i hT
    split at h
    · rename_i TJ' hJ
      split at h
      · rename_i hwfJ
        simp only [Option.some.injEq] at h; subst h
        obtain ⟨wfT, nwT⟩ := wfTree_sound hT
        obtain ⟨wfJ, nwJ⟩ := wfTree_sound hwfJ
        obtain ⟨wa, wb⟩ := joinAndCheckTree_sound hJ
        have hsJ : Supported2 TJ'.get D := fun v hv => (wa v).1.mp (hsa v hv)
        exact ⟨hsJ, Weaker.refl wfT nwT, ⟨wa, wfJ, nwJ⟩, ⟨wb, wfJ, nwJ⟩⟩
      · cases h
    · cases h
  · cases h

end C
