import B.Vec

/-!
# B9: `std/rc.nu`'s `Rc`, `Weak` and the check-out (AGORA-970)

`stdlib/std/rc.nu` keeps an `Rc` in one block,
`[ count ][ weak ][ cc ][ value ]`. Here `weak` counts the `Weak` handles
alone. The `RC_TAKEN` bit of `cc` says the value is checked out: `rc_take`
moved it to its taker, and `rc_restore` puts one back. While it is out,
`rc_get`, `rc_set`, `rc_replace` and `rc_take` through any handle panic
instead of reading a slot with no value in it. The last strong handle
drops the value only when it is there (a taken value is its taker's,
agora #795), and the block is freed once no `Weak` is left.
`weak_upgrade` gives a strong handle only while `count > 0`.

The model runs that code on the provenance heap. An operation's answer is
`none` for a step the heap would refuse (undefined behaviour), a panic, or
a value. With the handles held as two lists, the invariant says each
block a handle names is live, its counts are the handles, and its slot
holds a value exactly when it is not checked out. Proven:

* every operation through a held handle succeeds or panics, and never
  reaches a freed block or reads a slot with no value;
* a read, store, replace or take panics exactly while the value is out;
  otherwise it acts on the value that is there;
* the last strong release drops the value exactly when it is not checked
  out (none dropped twice), and frees the block exactly when no `Weak` is
  left;
* an upgrade succeeds exactly while a strong handle is left.

The collector's hooks (`nurl_cc_dead`, `nurl_cc_possible_root`, a nested
value's `nurl_rc_drop_value`) are the runtime's (B7 proves the criterion
it frees by). Here a block is not in the collector's buffer, which is the
case for a payload that cannot form a cycle.
-/

namespace B

open A1 (upd)

/-- A cell of the block: a count or flag, the value, or the zero bytes a
    take leaves (`mem_take`). -/
inductive SCell (V : Type) where
  | n (k : Nat)
  | val (v : V)
  | hole

variable {V : Type}

/-- What an operation through a handle does: a result, or a panic. -/
inductive Res (α : Type) where
  | ok (a : α)
  | panic

/-- The invariant. Each block a handle names is live, has its four cells,
    counts its handles, and holds a value exactly when not checked out. -/
def SRcInv (h : Heap (SCell V)) (hs ws : List Nat) : Prop :=
  ∀ b, (b ∈ hs ∨ b ∈ ws) → h.live b = true ∧ h.size b = 4 ∧
    h.cell b 0 = some (.n (hs.count b)) ∧ h.cell b 1 = some (.n (ws.count b)) ∧
    (b ∈ hs → (h.cell b 2 = some (.n 0) ∧ ∃ v, h.cell b 3 = some (.val v)) ∨
              (h.cell b 2 = some (.n 1) ∧ h.cell b 3 = some .hole))

/-- The check-out flag of a block a strong handle names. -/
def taken (h : Heap (SCell V)) (p : Nat) : Prop := h.cell p 2 = some (.n 1)

theorem sload {h : Heap (SCell V)} {p i : Nat} {c : SCell V} (hl : h.live p = true) (hs : h.size p = 4)
    (hi : i < 4) (hc : h.cell p i = some c) : h.load p i = some c := by
  simp only [Heap.load, hl, hs, true_and]; rw [ite_eq_left hi]; exact hc

theorem sstore {h : Heap (SCell V)} {p i : Nat} {c : SCell V} (hl : h.live p = true) (hs : h.size p = 4)
    (hi : i < 4) : h.store p i c = some { h with cell := upd h.cell p (upd (h.cell p) i (some c)) } := by
  have hin : h.live p = true ∧ i < h.size p := ⟨hl, by omega⟩
  simp only [Heap.store, hin, and_self, ↓reduceIte]

/-- `rc_get`: the value, or the panic while it is taken. -/
def rcGet (h : Heap (SCell V)) (p : Nat) : Option (Res V) :=
  match h.load p 2 with
  | some (.n t) => if t ≠ 0 then some .panic else
      match h.load p 3 with
      | some (.val v) => some (.ok v)
      | _ => none
  | _ => none

/-- `rc_take`: the value moved out (its slot the zero bytes), the flag set;
    or the panic while it is already taken. -/
def rcTake (h : Heap (SCell V)) (p : Nat) : Option (Res (Heap (SCell V) × V)) :=
  match h.load p 2 with
  | some (.n t) => if t ≠ 0 then some .panic else
      match h.load p 3 with
      | some (.val v) =>
        match h.store p 3 .hole with
        | none => none
        | some h1 => (h1.store p 2 (.n 1)).map fun h2 => .ok (h2, v)
      | _ => none
  | _ => none

/-- `rc_restore`: a value put back, the flag cleared; or the panic when the
    value was not taken. -/
def rcRestore (h : Heap (SCell V)) (p : Nat) (x : V) : Option (Res (Heap (SCell V))) :=
  match h.load p 2 with
  | some (.n t) => if t = 0 then some .panic else
      match h.store p 2 (.n 0) with
      | none => none
      | some h1 => (h1.store p 3 (.val x)).map .ok
  | _ => none

/-- `Rc_drop` (a block not in the collector's buffer): the count down; the
    last drops the value when it is there, and frees the block when no
    `Weak` is left. The answer is the value dropped, if any. -/
def rcDrop (h : Heap (SCell V)) (p : Nat) : Option (Heap (SCell V) × Option V) :=
  match h.load p 0, h.load p 1, h.load p 2, h.load p 3 with
  | some (.n c), some (.n w), some (.n t), some x =>
    match h.store p 0 (.n (c - 1)) with
    | none => none
    | some h1 =>
      if c - 1 = 0 then
        let dv : Option V := if t = 0 then (match x with | .val v => some v | _ => none) else none
        let h2 : Heap (SCell V) := if t = 0 then { h1 with cell := upd h1.cell p (upd (h1.cell p) 3 (some .hole)) } else h1
        if w = 0 then (h2.free p).map fun h3 => (h3, dv) else some (h2, dv)
      else some (h1, none)
  | _, _, _, _ => none

theorem rcGet_ok {h : Heap (SCell V)} {hs ws : List Nat} {p : Nat} (hi : SRcInv h hs ws) (hp : p ∈ hs) :
    (taken h p → rcGet h p = some .panic) ∧ (¬ taken h p → ∃ v, rcGet h p = some (.ok v) ∧ h.cell p 3 = some (.val v)) := by
  obtain ⟨hl, hsz, _, _, hv⟩ := hi p (Or.inl hp)
  rcases hv hp with ⟨h2, v, h3⟩ | ⟨h2, h3⟩
  · refine ⟨fun ht => (by unfold taken at ht; rw [h2] at ht; cases ht), fun _ => ⟨v, ?_, h3⟩⟩
    simp [rcGet, sload hl hsz (by omega) h2, sload hl hsz (by omega) h3]
  · refine ⟨fun _ => by simp [rcGet, sload hl hsz (by omega) h2], fun ht => absurd h2 ht⟩

/-- The take panics while the value is out; otherwise it hands the value to
    the taker and leaves the slot empty and flagged. The invariant holds. -/
theorem rcTake_ok {h : Heap (SCell V)} {hs ws : List Nat} {p : Nat} (hw : h.WF) (hi : SRcInv h hs ws)
    (hp : p ∈ hs) :
    (taken h p → rcTake h p = some .panic) ∧
    (¬ taken h p → ∃ h' v, rcTake h p = some (.ok (h', v)) ∧ h.cell p 3 = some (.val v) ∧
      SRcInv h' hs ws ∧ h'.WF ∧ taken h' p) := by
  obtain ⟨hl, hsz, hc0, hc1, hv⟩ := hi p (Or.inl hp)
  rcases hv hp with ⟨h2, v, h3⟩ | ⟨h2, h3⟩
  · refine ⟨fun ht => (by unfold taken at ht; rw [h2] at ht; cases ht), fun _ => ?_⟩
    let h1 : Heap (SCell V) := { h with cell := upd h.cell p (upd (h.cell p) 3 (some .hole)) }
    have hl1 : h1.live p = true := hl
    have hs1 : h1.size p = 4 := hsz
    refine ⟨{ h1 with cell := upd h1.cell p (upd (h1.cell p) 2 (some (.n 1))) }, v, ?_, h3, ?_, fun b hb => hw b hb, ?_⟩
    · simp only [rcTake, sload hl hsz (by omega) h2, ne_eq, not_true_eq_false, ↓reduceIte,
        sload hl hsz (by omega) h3, sstore hl hsz (by omega : 3 < 4)]
      rw [show ({ h with cell := upd h.cell p (upd (h.cell p) 3 (some .hole)) } : Heap (SCell V)) = h1 from rfl,
        sstore hl1 hs1 (by omega : 2 < 4)]
      rfl
    · intro b hb
      obtain ⟨g1, g2, g3, g4, g5⟩ := hi b hb
      by_cases hbp : b = p
      · subst hbp
        refine ⟨g1, g2, ?_, ?_, fun _ => Or.inr ⟨?_, ?_⟩⟩ <;>
          (show (upd h1.cell b _) b _ = _; simp [h1, upd]) <;> assumption
      · refine ⟨g1, g2, ?_, ?_, fun hm => ?_⟩
        · show (upd h1.cell p _) b 0 = _; simp only [upd, ite_eq_right hbp]
          show (upd h.cell p _) b 0 = _; simp only [upd, ite_eq_right hbp]; exact g3
        · show (upd h1.cell p _) b 1 = _; simp only [upd, ite_eq_right hbp]
          show (upd h.cell p _) b 1 = _; simp only [upd, ite_eq_right hbp]; exact g4
        · have e : ∀ i, (upd h1.cell p (upd (h1.cell p) 2 (some (SCell.n 1)))) b i = h.cell b i := by
            intro i; simp only [upd, ite_eq_right hbp]; show (upd h.cell p _) b i = _; simp only [upd, ite_eq_right hbp]
          show _ ∨ _
          rw [show ({ h1 with cell := upd h1.cell p (upd (h1.cell p) 2 (some (SCell.n 1))) } : Heap (SCell V)).cell b 2
            = h.cell b 2 from e 2,
            show ({ h1 with cell := upd h1.cell p (upd (h1.cell p) 2 (some (SCell.n 1))) } : Heap (SCell V)).cell b 3
            = h.cell b 3 from e 3]
          exact g5 hm
    · show (upd h1.cell p _) p 2 = _; simp [upd]
  · exact ⟨fun _ => by simp [rcTake, sload hl hsz (by omega) h2], fun ht => absurd h2 ht⟩

/-- The restore panics when the value is not out; otherwise the value goes
    back into the slot and the flag is cleared. The invariant holds. -/
theorem rcRestore_ok {h : Heap (SCell V)} {hs ws : List Nat} {p : Nat} (x : V) (hw : h.WF)
    (hi : SRcInv h hs ws) (hp : p ∈ hs) :
    (¬ taken h p → rcRestore h p x = some .panic) ∧
    (taken h p → ∃ h', rcRestore h p x = some (.ok h') ∧ SRcInv h' hs ws ∧ h'.WF ∧ ¬ taken h' p ∧
      h'.cell p 3 = some (.val x)) := by
  obtain ⟨hl, hsz, hc0, hc1, hv⟩ := hi p (Or.inl hp)
  rcases hv hp with ⟨h2, v, h3⟩ | ⟨h2, h3⟩
  · exact ⟨fun _ => by simp [rcRestore, sload hl hsz (by omega) h2], fun ht => (by unfold taken at ht; rw [h2] at ht; cases ht)⟩
  · refine ⟨fun ht => absurd h2 ht, fun _ => ?_⟩
    let h1 : Heap (SCell V) := { h with cell := upd h.cell p (upd (h.cell p) 2 (some (.n 0))) }
    have hl1 : h1.live p = true := hl
    have hs1 : h1.size p = 4 := hsz
    refine ⟨{ h1 with cell := upd h1.cell p (upd (h1.cell p) 3 (some (.val x))) }, ?_, ?_, fun b hb => hw b hb, ?_, ?_⟩
    · simp only [rcRestore, sload hl hsz (by omega) h2]
      rw [ite_eq_right (by decide : ¬ (1:Nat) = 0)]
      simp only [sstore hl hsz (by omega : 2 < 4)]
      rw [show ({ h with cell := upd h.cell p (upd (h.cell p) 2 (some (.n 0))) } : Heap (SCell V)) = h1 from rfl,
        sstore hl1 hs1 (by omega : 3 < 4)]
      rfl
    · intro b hb
      obtain ⟨g1, g2, g3, g4, g5⟩ := hi b hb
      by_cases hbp : b = p
      · subst hbp
        refine ⟨g1, g2, ?_, ?_, fun _ => Or.inl ⟨?_, x, ?_⟩⟩ <;>
          (show (upd h1.cell b _) b _ = _; simp [h1, upd]) <;> assumption
      · have e : ∀ i, (upd h1.cell p (upd (h1.cell p) 3 (some (SCell.val x)))) b i = h.cell b i := by
          intro i; simp only [upd, ite_eq_right hbp]; show (upd h.cell p _) b i = _; simp only [upd, ite_eq_right hbp]
        refine ⟨g1, g2, (e 0).trans g3, (e 1).trans g4, fun hm => ?_⟩
        show _ ∨ _
        rw [show ({ h1 with cell := upd h1.cell p (upd (h1.cell p) 3 (some (SCell.val x))) } : Heap (SCell V)).cell b 2
          = h.cell b 2 from e 2,
          show ({ h1 with cell := upd h1.cell p (upd (h1.cell p) 3 (some (SCell.val x))) } : Heap (SCell V)).cell b 3
          = h.cell b 3 from e 3]
        exact g5 hm
    · unfold taken; show (upd h1.cell p _) p 2 ≠ _; simp [h1, upd]
    · show (upd h1.cell p _) p 3 = _; simp [upd]

/-- Block `p` changed alone keeps the clauses of every other block whose
    handles are the same. -/
theorem srcInv_other {h h' : Heap (SCell V)} {hs ws hs' ws' : List Nat} {p : Nat} (hi : SRcInv h hs ws)
    (hlv : ∀ b, b ≠ p → h'.live b = h.live b) (hsz : ∀ b, b ≠ p → h'.size b = h.size b)
    (hc : ∀ b, b ≠ p → h'.cell b = h.cell b)
    (hhs : ∀ b, b ≠ p → hs'.count b = hs.count b) (hws : ∀ b, b ≠ p → ws'.count b = ws.count b) :
    ∀ b, b ≠ p → (b ∈ hs' ∨ b ∈ ws') → h'.live b = true ∧ h'.size b = 4 ∧
      h'.cell b 0 = some (.n (hs'.count b)) ∧ h'.cell b 1 = some (.n (ws'.count b)) ∧
      (b ∈ hs' → (h'.cell b 2 = some (.n 0) ∧ ∃ v, h'.cell b 3 = some (.val v)) ∨
                 (h'.cell b 2 = some (.n 1) ∧ h'.cell b 3 = some .hole)) := by
  intro b hbp hb
  have hmem : ∀ (l l' : List Nat), l'.count b = l.count b → (b ∈ l' ↔ b ∈ l) := by
    intro l l' e; rw [← List.count_pos_iff, ← List.count_pos_iff, e]
  have e1 := hmem hs hs' (hhs b hbp)
  have e2 := hmem ws ws' (hws b hbp)
  obtain ⟨g1, g2, g3, g4, g5⟩ := hi b (by rcases hb with hb | hb; exact Or.inl (e1.mp hb); exact Or.inr (e2.mp hb))
  refine ⟨by rw [hlv b hbp]; exact g1, by rw [hsz b hbp]; exact g2, by rw [hc b hbp, g3, hhs b hbp],
    by rw [hc b hbp, g4, hws b hbp], fun hm => ?_⟩
  rw [hc b hbp]; exact g5 (e1.mp hm)

/-- `Rc_drop` through a held strong handle succeeds. The value is dropped
    exactly when it was the last strong handle and the value was not
    checked out (a taken value is its taker's), and only the value that
    was there. The block is freed exactly when it was the last strong
    handle and no `Weak` is left. -/
theorem rcDrop_ok {h : Heap (SCell V)} {hs ws : List Nat} {p : Nat} (hw : h.WF) (hi : SRcInv h hs ws)
    (hp : p ∈ hs) :
    ∃ h' dv, rcDrop h p = some (h', dv) ∧ SRcInv h' (hs.erase p) ws ∧ h'.WF ∧
      (dv.isSome ↔ hs.count p = 1 ∧ ¬ taken h p) ∧ (∀ v, dv = some v → h.cell p 3 = some (.val v)) ∧
      (h'.live p = false ↔ hs.count p = 1 ∧ ws.count p = 0) := by
  obtain ⟨hl, hsz, hc0, hc1, hv⟩ := hi p (Or.inl hp)
  have hpos : 0 < hs.count p := List.count_pos_iff.mpr hp
  have herase : ∀ b, b ≠ p → (hs.erase p).count b = hs.count b := fun b hb => List.count_erase_of_ne hb
  have hce : (hs.erase p).count p = hs.count p - 1 := List.count_erase_self
  -- any heap that changes only block `p`, keeping sizes, keeps every other block's clauses
  have hoth : ∀ (g : Heap (SCell V)), (∀ b, b ≠ p → g.live b = h.live b) → g.size = h.size →
      (∀ b, b ≠ p → g.cell b = h.cell b) → ∀ b, b ≠ p → (b ∈ hs.erase p ∨ b ∈ ws) →
      g.live b = true ∧ g.size b = 4 ∧ g.cell b 0 = some (.n ((hs.erase p).count b)) ∧
      g.cell b 1 = some (.n (ws.count b)) ∧
      (b ∈ hs.erase p → (g.cell b 2 = some (.n 0) ∧ ∃ v, g.cell b 3 = some (.val v)) ∨
        (g.cell b 2 = some (.n 1) ∧ g.cell b 3 = some .hole)) :=
    fun g gl gs gc => srcInv_other hi gl (fun b _ => by rw [gs]) gc herase (fun _ _ => rfl)
  have hwf : ∀ (g : Heap (SCell V)), g.nid = h.nid → (∀ b, h.nid ≤ b → g.live b = h.live b ∨ g.live b = false) → g.WF := by
    intro g hn hg b hb
    rw [hn] at hb
    rcases hg b hb with e | e
    · rw [e]; exact hw b hb
    · exact e
  let h1 : Heap (SCell V) := { h with cell := upd h.cell p (upd (h.cell p) 0 (some (.n (hs.count p - 1)))) }
  have h1c : ∀ b, b ≠ p → h1.cell b = h.cell b := fun b hb => by show (upd h.cell p _) b = _; simp [upd, hb]
  have hs0 := sstore (c := SCell.n (hs.count p - 1)) hl hsz (by omega : 0 < 4)
  by_cases hlast : hs.count p = 1
  · have hpe : p ∉ hs.erase p := by intro hm; have := List.count_pos_iff.mpr hm; omega
    have hz : hs.count p - 1 = 0 := by omega
    -- the slot after the drop: empty either way
    obtain ⟨g2, dv, g2l, g2s, g2n, g2c, g2p0, g2p1, hdv1, hdv2, hdrop⟩ : ∃ (g2 : Heap (SCell V)) (dv : Option V),
        g2.live = h.live ∧ g2.size = h.size ∧ g2.nid = h.nid ∧ (∀ b, b ≠ p → g2.cell b = h.cell b) ∧
        g2.cell p 0 = some (.n 0) ∧ g2.cell p 1 = some (.n (ws.count p)) ∧
        (dv.isSome ↔ hs.count p = 1 ∧ ¬ taken h p) ∧ (∀ v, dv = some v → h.cell p 3 = some (.val v)) ∧
        rcDrop h p = (if ws.count p = 0 then (g2.free p).map (fun g3 => (g3, dv)) else some (g2, dv)) := by
      rcases hv hp with ⟨h2, v, h3⟩ | ⟨h2, h3⟩
      · refine ⟨{ h1 with cell := upd h1.cell p (upd (h1.cell p) 3 (some .hole)) }, some v, rfl, rfl, rfl,
          fun b hb => ?_, ?_, ?_, ?_, fun w e => by injection e with e; subst e; exact h3, ?_⟩
        · show (upd h1.cell p _) b = _; simp only [upd, ite_eq_right hb]; exact h1c b hb
        · show (upd h1.cell p _) p 0 = _; simp [h1, upd, hz]
        · show (upd h1.cell p _) p 1 = _; simp [h1, upd, hc1]
        · unfold taken; rw [h2]; simp [hlast]
        · simp only [rcDrop, sload hl hsz (by omega) hc0, sload hl hsz (by omega) hc1, sload hl hsz (by omega) h2,
            sload hl hsz (by omega) h3, hs0, ↓reduceIte]
          rw [ite_eq_left hz]
      · refine ⟨h1, none, rfl, rfl, rfl, h1c, ?_, ?_, ?_, fun w e => (by cases e), ?_⟩
        · show (upd h.cell p _) p 0 = _; simp [upd, hz]
        · show (upd h.cell p _) p 1 = _; simp [upd, hc1]
        · unfold taken; rw [h2]; simp
        · simp only [rcDrop, sload hl hsz (by omega) hc0, sload hl hsz (by omega) hc1, sload hl hsz (by omega) h2,
            sload hl hsz (by omega) h3, hs0]
          rw [ite_eq_left hz]
          rfl
    have hlv2 : g2.live p = true := by rw [g2l]; exact hl
    by_cases hw0 : ws.count p = 0
    · have hpw : p ∉ ws := fun hm => by have := List.count_pos_iff.mpr hm; omega
      rw [ite_eq_left hw0] at hdrop
      let g3 : Heap (SCell V) := { g2 with live := upd g2.live p false }
      refine ⟨g3, dv, ?_, ?_, ?_, hdv1, hdv2, ?_⟩
      · rw [hdrop]; simp only [Heap.free, hlv2, ↓reduceIte, Option.map_some]; rfl
      · intro b hb
        have hbp : b ≠ p := by rintro rfl; rcases hb with hb | hb; exact hpe hb; exact hpw hb
        exact hoth g3 (fun b hb => by show (upd g2.live p false) b = _; simp [upd, hb, g2l]) g2s g2c b hbp hb
      · refine hwf g3 g2n ?_
        intro b _; right; show (upd g2.live p false) b = false
        simp only [upd]; split
        · rfl
        · rw [g2l]; exact hw b (by omega)
      · show (upd g2.live p false) p = false ↔ _; simp [upd, hlast, hw0]
    · rw [ite_eq_right hw0] at hdrop
      refine ⟨g2, dv, hdrop, ?_, ?_, hdv1, hdv2, by rw [hlv2]; simp [hw0]⟩
      · intro b hb
        by_cases hbp : b = p
        · subst hbp
          exact ⟨hlv2, by rw [g2s]; exact hsz, by rw [g2p0, hce, hlast], g2p1, fun hm => absurd hm hpe⟩
        · exact hoth g2 (fun b _ => by rw [g2l]) g2s g2c b hbp hb
      · exact hwf g2 g2n (fun b _ => Or.inl (by rw [g2l]))
  · -- not the last: the count down, nothing else
    have hpe : p ∈ hs.erase p := by apply List.count_pos_iff.mp; rw [hce]; omega
    have hnz : hs.count p - 1 ≠ 0 := by omega
    have heq : rcDrop h p = some (h1, none) := by
      rcases hv hp with ⟨h2, v, h3⟩ | ⟨h2, h3⟩
      · simp only [rcDrop, sload hl hsz (by omega) hc0, sload hl hsz (by omega) hc1, sload hl hsz (by omega) h2,
          sload hl hsz (by omega) h3, hs0]
        rw [ite_eq_right hnz]
      · simp only [rcDrop, sload hl hsz (by omega) hc0, sload hl hsz (by omega) hc1, sload hl hsz (by omega) h2,
          sload hl hsz (by omega) h3, hs0]
        rw [ite_eq_right hnz]
    refine ⟨h1, none, heq, ?_, fun b hb => hw b hb, by simp [hlast], fun v e => (by cases e), by simp [h1, hl, hlast]⟩
    intro b hb
    by_cases hbp : b = p
    · subst hbp
      have e : ∀ i, i ≠ 0 → h1.cell b i = h.cell b i := fun i hi => by
        show (upd h.cell b _) b i = _; simp [upd, hi]
      refine ⟨hl, hsz, by show (upd h.cell b _) b 0 = _; simp [upd, hce], by rw [e 1 (by omega)]; exact hc1,
        fun _ => ?_⟩
      rw [e 2 (by omega), e 3 (by omega)]; exact hv hp
    · exact hoth h1 (fun _ _ => rfl) rfl h1c b hbp hb

/-- `weak_upgrade` through a held `Weak`: a strong handle exactly while one
    is left, the count up by one. Otherwise none, and nothing changes. -/
def rcUpgrade (h : Heap (SCell V)) (p : Nat) : Option (Heap (SCell V) × Bool) :=
  match h.load p 0 with
  | some (.n c) => if c = 0 then some (h, false) else (h.store p 0 (.n (c + 1))).map fun h1 => (h1, true)
  | _ => none

theorem rcUpgrade_ok {h : Heap (SCell V)} {hs ws : List Nat} {p : Nat} (hw : h.WF) (hi : SRcInv h hs ws)
    (hp : p ∈ ws) :
    ∃ h' ok, rcUpgrade h p = some (h', ok) ∧ (ok = true ↔ p ∈ hs) ∧
      SRcInv h' (if ok then p :: hs else hs) ws ∧ h'.WF := by
  obtain ⟨hl, hsz, hc0, hc1, hv⟩ := hi p (Or.inr hp)
  by_cases hph : p ∈ hs
  · have hpos : hs.count p ≠ 0 := by have := List.count_pos_iff.mpr hph; omega
    refine ⟨{ h with cell := upd h.cell p (upd (h.cell p) 0 (some (.n (hs.count p + 1)))) }, true, ?_, by simp [hph],
      ?_, fun b hb => hw b hb⟩
    · simp only [rcUpgrade, sload hl hsz (by omega) hc0, hpos, ↓reduceIte, sstore hl hsz (by omega : 0 < 4),
        Option.map_some]
    · simp only [↓reduceIte]
      intro b hb
      by_cases hbp : b = p
      · subst hbp
        have e : ∀ i, i ≠ 0 → (upd h.cell b (upd (h.cell b) 0 (some (SCell.n (hs.count b + 1))))) b i = h.cell b i :=
          fun i hi => by simp [upd, hi]
        refine ⟨hl, hsz, by show (upd h.cell b _) b 0 = _; simp [upd], ?_, fun _ => ?_⟩
        · show (upd h.cell b _) b 1 = _; rw [e 1 (by omega)]; exact hc1
        · show _ ∨ _
          show ((upd h.cell b _) b 2 = _ ∧ _) ∨ ((upd h.cell b _) b 2 = _ ∧ (upd h.cell b _) b 3 = _)
          rw [e 2 (by omega)]
          rcases hv hph with ⟨g2, v, g3⟩ | ⟨g2, g3⟩
          · exact Or.inl ⟨g2, v, (e 3 (by omega)).trans g3⟩
          · exact Or.inr ⟨g2, (e 3 (by omega)).trans g3⟩
      · exact srcInv_other (h' := { h with cell := upd h.cell p (upd (h.cell p) 0 (some (.n (hs.count p + 1)))) })
          hi (fun _ _ => rfl) (fun _ _ => rfl) (fun b hb => by show (upd h.cell p _) b = _; simp [upd, hb])
          (fun b hb => by rw [List.count_cons]; simp [Ne.symm hb]) (fun _ _ => rfl) b hbp hb
  · have hz : hs.count p = 0 := List.count_eq_zero_of_not_mem hph
    refine ⟨h, false, by simp [rcUpgrade, sload hl hsz (by omega) hc0, hz], by simp [hph], by simpa using hi, hw⟩

/-- `Weak_drop` (a block not in the collector's buffer): weak down by one;
    the block freed when it was the last `Weak` and no strong handle is
    left. -/
def rcWeakDrop (h : Heap (SCell V)) (p : Nat) : Option (Heap (SCell V) × Bool) :=
  match h.load p 0, h.load p 1 with
  | some (.n c), some (.n w) =>
    match h.store p 1 (.n (w - 1)) with
    | none => none
    | some h1 => if w - 1 = 0 ∧ c = 0 then (h1.free p).map fun h2 => (h2, true) else some (h1, false)
  | _, _ => none

theorem rcWeakDrop_ok {h : Heap (SCell V)} {hs ws : List Nat} {p : Nat} (hw : h.WF) (hi : SRcInv h hs ws)
    (hp : p ∈ ws) :
    ∃ h' fr, rcWeakDrop h p = some (h', fr) ∧ SRcInv h' hs (ws.erase p) ∧ h'.WF ∧
      (fr = true ↔ p ∉ hs ∧ p ∉ ws.erase p) := by
  obtain ⟨hl, hsz, hc0, hc1, hv⟩ := hi p (Or.inr hp)
  have hpos : 0 < ws.count p := List.count_pos_iff.mpr hp
  have herase : ∀ b, b ≠ p → (ws.erase p).count b = ws.count b := fun b hb => List.count_erase_of_ne hb
  have hce : (ws.erase p).count p = ws.count p - 1 := List.count_erase_self
  let h1 : Heap (SCell V) := { h with cell := upd h.cell p (upd (h.cell p) 1 (some (.n (ws.count p - 1)))) }
  have h1c : ∀ b, b ≠ p → h1.cell b = h.cell b := fun b hb => by show (upd h.cell p _) b = _; simp [upd, hb]
  have hs1 := sstore (c := SCell.n (ws.count p - 1)) hl hsz (by omega : 1 < 4)
  have hmem : ∀ l : List Nat, p ∉ l ↔ l.count p = 0 := fun l => by
    constructor
    · exact List.count_eq_zero_of_not_mem
    · intro e hm; have := List.count_pos_iff.mpr hm; omega
  by_cases hf : ws.count p - 1 = 0 ∧ hs.count p = 0
  · have hph : p ∉ hs := (hmem hs).mpr hf.2
    have hpe : p ∉ ws.erase p := (hmem _).mpr (by rw [hce]; exact hf.1)
    refine ⟨{ h1 with live := upd h1.live p false }, true, ?_, ?_, ?_, by simp [hph, hpe]⟩
    · simp only [rcWeakDrop, sload hl hsz (by omega) hc0, sload hl hsz (by omega) hc1, hs1]
      rw [ite_eq_left hf]
      simp [Heap.free, h1, hl]
    · intro b hb
      have hbp : b ≠ p := by rintro rfl; rcases hb with hb | hb; exact hph hb; exact hpe hb
      exact srcInv_other (h' := { h1 with live := upd h1.live p false }) hi
        (fun b hb => by show (upd h.live p false) b = _; simp [upd, hb]) (fun _ _ => rfl) h1c (fun _ _ => rfl)
        herase b hbp hb
    · intro b hb; show (upd h.live p false) b = false
      simp only [upd]; split
      · rfl
      · exact hw b hb
  · refine ⟨h1, false, ?_, ?_, fun b hb => hw b hb, ?_⟩
    · simp only [rcWeakDrop, sload hl hsz (by omega) hc0, sload hl hsz (by omega) hc1, hs1]
      rw [ite_eq_right hf]
    · intro b hb
      by_cases hbp : b = p
      · subst hbp
        have e : ∀ i, i ≠ 1 → h1.cell b i = h.cell b i := fun i hi => by
          show (upd h.cell b _) b i = _; simp [upd, hi]
        refine ⟨hl, hsz, by rw [e 0 (by omega)]; exact hc0, by show (upd h.cell b _) b 1 = _; simp [upd, hce],
          fun hm => ?_⟩
        rw [e 2 (by omega), e 3 (by omega)]; exact hv hm
      · exact srcInv_other (h' := h1) hi (fun _ _ => rfl) (fun _ _ => rfl) h1c (fun _ _ => rfl) herase b hbp hb
    · simp only [Bool.false_eq_true, false_iff, not_and, Decidable.not_not]
      intro hph
      apply Classical.byContradiction
      intro hpe
      exact hf ⟨by rw [← hce]; exact (hmem _).mp hpe, (hmem hs).mp hph⟩

end B
