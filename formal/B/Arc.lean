module

public import B.Rc

@[expose] public section

/-!
# B5: `Arc` and `ArcWeak` (AGORA-970)

`stdlib/std/arc.nu` keeps an `Arc` in one block, `[ count ][ weak ][ value ]`.
`count` is the number of strong handles. `weak` is the number of `ArcWeak`
handles, plus one held by the strong handles together. The last strong
handle drops the value and gives up that one, and whoever takes `weak` to
zero frees the block. `nurl_arc_release` answers 0 when other strong
handles remain, 1 for the last strong handle while a `Weak` names the
block, and 2 for the only owner of a block no `Weak` names, which then
frees it at once. `arc_weak_upgrade` takes a strong handle only while
`count > 0` (`nurl_atomic_i64_inc_if_live`).

The model runs that code on the provenance heap, one operation at a time.
That is what the atomic read-modify-writes are to the thread doing them;
their atomicity across threads is A3's and phase D's. The handles held are
two lists of block ids, strong and weak. The invariant `ArcInv` says a
block a handle names is live, its counts are the handles (plus the one
shared weak), and it holds its value exactly while a strong handle names
it; once none does, the value slot holds no live value (`.gone`). For a
payload type with a drop the move out zeroes the slot in the emitted code;
for a trivial one the bits stay, but nothing reads them: no handle can
reach them, as the upgrade theorem shows. The operations are `arc_new`,
`arc_clone`, `arc_downgrade`, `ArcWeak_share` (through any held `Weak`,
also once no strong handle is left: `weakClone_ok`), `Arc_drop`,
`ArcWeak_drop` and `arc_weak_upgrade`. Each keeps the invariant, and every
operation through a held handle succeeds, so no handle ever reaches a
freed block. Moreover:

* the value comes out to be dropped exactly at the release of the last
  strong handle, and only then;
* the block is freed exactly when the last handle of either kind goes;
* an upgrade succeeds exactly while the value is alive, so a `Weak` never
  yields a handle to a dropped value.
-/

namespace B

open A1 (upd)

variable {V : Type}

/-- The counts and the value of the block a handle names, as the
    invariant asks: strong `= hs.count b`, weak `= ws.count b + [hs ∋ b]`,
    a value while a strong handle names the block, and the slot moved out
    of (`.gone`) once none does. -/
def ArcInv (h : Heap (RcCell V)) (hs ws : List Nat) : Prop :=
  ∀ b, (b ∈ hs ∨ b ∈ ws) → h.live b = true ∧ h.size b = 3 ∧
    h.cell b 0 = some (.cnt (hs.count b)) ∧
    h.cell b 1 = some (.cnt (ws.count b + (if b ∈ hs then 1 else 0))) ∧
    (b ∈ hs → ∃ v, h.cell b 2 = some (.val v)) ∧
    (b ∉ hs → h.cell b 2 = some .gone)

/-- `arc_new`: count 1, weak 1 (the strong handles' one), the value. -/
def arcNew (h : Heap (RcCell V)) (x : V) : Heap (RcCell V) × Nat :=
  ({ live := upd h.live h.nid true, size := upd h.size h.nid 3,
     cell := upd h.cell h.nid (fun i => if i = 0 then some (.cnt 1) else if i = 1 then some (.cnt 1)
       else if i = 2 then some (.val x) else none),
     nid := h.nid + 1 }, h.nid)

/-- A counter cell up by one (`nurl_arc_share`, `nurl_atomic_i64_inc`). -/
def cntInc (h : Heap (RcCell V)) (p c : Nat) : Option (Heap (RcCell V)) :=
  match h.load p c with
  | some (.cnt n) => h.store p c (.cnt (n + 1))
  | _ => none

/-- `__arc_weak_release`: weak down by one, and the last frees the block. -/
def weakRelease (h : Heap (RcCell V)) (p : Nat) : Option (Heap (RcCell V) × Bool) :=
  match h.load p 1 with
  | some (.cnt n) =>
    if n = 1 then (h.free p).map fun h1 => (h1, true)
    else (h.store p 1 (.cnt (n - 1))).map fun h1 => (h1, false)
  | _ => none

/-- `Arc_drop`: `nurl_arc_release`. Not the last strong handle: count down.
    The last: count 0, the value moved out of its slot (`.gone`: for a
    payload with a drop the emitted code zeroes the slot, `store
    zeroinitializer` through the field's address; a trivial payload's bits
    stay, no longer a value of anyone's), then either the block freed (no
    `Weak`, answer 2) or the strong handles' weak given up (answer 1). -/
def arcDrop (h : Heap (RcCell V)) (p : Nat) : Option (Heap (RcCell V) × Option V) :=
  match h.load p 0 with
  | some (.cnt n) =>
    if n = 1 then
      match h.load p 2, h.load p 1 with
      | some (.val v), some (.cnt w) =>
        match (h.store p 0 (.cnt 0)).bind fun h0 => h0.store p 2 .gone with
        | none => none
        | some h1 =>
          if w = 1 then (h1.free p).map fun h2 => (h2, some v)
          else (weakRelease h1 p).map fun r => (r.1, some v)
      | _, _ => none
    else (h.store p 0 (.cnt (n - 1))).map fun h1 => (h1, none)
  | _ => none

/-- `arc_weak_upgrade`: a strong handle while `count > 0`, none after. -/
def arcUpgrade (h : Heap (RcCell V)) (p : Nat) : Option (Heap (RcCell V) × Bool) :=
  match h.load p 0 with
  | some (.cnt n) => if n = 0 then some (h, false) else (h.store p 0 (.cnt (n + 1))).map fun h1 => (h1, true)
  | _ => none

/-! ### Small facts about the cells -/

theorem load_of {h : Heap (RcCell V)} {p i : Nat} {c : RcCell V} (hl : h.live p = true) (hs : h.size p = 3)
    (hi : i < 3) (hc : h.cell p i = some c) : h.load p i = some c := by
  simp only [Heap.load, hl, hs, true_and]; rw [ite_eq_left hi]; exact hc

theorem store_of {h : Heap (RcCell V)} {p i : Nat} {c : RcCell V} (hl : h.live p = true) (hs : h.size p = 3)
    (hi : i < 3) : h.store p i c = some { h with cell := upd h.cell p (upd (h.cell p) i (some c)) } := by
  have hin : h.live p = true ∧ i < h.size p := ⟨hl, by omega⟩
  simp only [Heap.store, hin, and_self, ↓reduceIte]

theorem arcNew_ok {h : Heap (RcCell V)} {hs ws : List Nat} (x : V) (hw : h.WF) (hi : ArcInv h hs ws) :
    ArcInv (arcNew h x).1 ((arcNew h x).2 :: hs) ws ∧ (arcNew h x).1.WF ∧ (arcNew h x).2 = h.nid := by
  have hnin : ∀ l : List Nat, (∀ b, b ∈ l → h.live b = true) → h.nid ∉ l := fun l hl hm => by
    have := hl _ hm; rw [hw h.nid (Nat.le_refl _)] at this; exact absurd this (by simp)
  have hnh : h.nid ∉ hs := hnin hs (fun b hb => (hi b (Or.inl hb)).1)
  have hnw : h.nid ∉ ws := hnin ws (fun b hb => (hi b (Or.inr hb)).1)
  refine ⟨fun b hb => ?_, fun b hb => ?_, rfl⟩
  · simp only [arcNew] at hb ⊢
    by_cases hbn : b = h.nid
    · subst hbn
      simp only [upd, ↓reduceIte, true_and]
      refine ⟨?_, ?_, fun _ => ⟨x, by simp⟩, fun hn => absurd List.mem_cons_self hn⟩
      · simp [List.count_eq_zero_of_not_mem hnh]
      · simp [List.count_eq_zero_of_not_mem hnw]
    · have hb' : b ∈ hs ∨ b ∈ ws := by simp [hbn] at hb; exact hb
      obtain ⟨h1, h2, h3, h4, h5, h6⟩ := hi b hb'
      simp only [upd, ite_eq_right hbn]
      refine ⟨h1, h2, ?_, ?_, fun hm => h5 (by simp [hbn] at hm; exact hm),
        fun hn => h6 (fun hm => hn (List.mem_cons_of_mem _ hm))⟩
      · rw [h3, List.count_cons]; simp [Ne.symm hbn]
      · rw [h4]; simp [hbn]
  · simp only [arcNew, upd] at hb ⊢
    rw [ite_eq_right (by omega)]; exact hw b (by omega)

/-- `arc_clone` through a held strong handle. -/
theorem arcClone_ok {h : Heap (RcCell V)} {hs ws : List Nat} {p : Nat} (hw : h.WF) (hi : ArcInv h hs ws)
    (hp : p ∈ hs) :
    ∃ h', cntInc h p 0 = some h' ∧ ArcInv h' (p :: hs) ws ∧ h'.WF ∧ h'.live = h.live := by
  obtain ⟨hl, hsz, hc0, hc1, hv, -⟩ := hi p (Or.inl hp)
  refine ⟨{ h with cell := upd h.cell p (upd (h.cell p) 0 (some (.cnt (hs.count p + 1)))) },
    by simp only [cntInc, load_of hl hsz (by omega) hc0, store_of hl hsz (by omega : 0 < 3)], ?_,
    fun b hb => hw b hb, rfl⟩
  intro b hb
  by_cases hbp : b = p
  · subst hbp
    refine ⟨hl, hsz, by show (upd h.cell b _) b 0 = _; simp [upd], ?_, fun _ => ?_,
      fun hn => absurd List.mem_cons_self hn⟩
    · show (upd h.cell b _) b 1 = _; simp [upd, hc1, hp]
    · obtain ⟨v, hv⟩ := hv hp; exact ⟨v, by show (upd h.cell b _) b 2 = _; simp [upd, hv]⟩
  · have hb' : b ∈ hs ∨ b ∈ ws := by simp [hbp] at hb; exact hb
    obtain ⟨g1, g2, g3, g4, g5, g6⟩ := hi b hb'
    refine ⟨g1, g2, ?_, ?_, fun hm => ?_, fun hn => ?_⟩
    · show (upd h.cell p _) b 0 = _; simp only [upd, ite_eq_right hbp]; rw [g3, List.count_cons]; simp [Ne.symm hbp]
    · show (upd h.cell p _) b 1 = _; simp only [upd, ite_eq_right hbp]; rw [g4]; simp [hbp]
    · obtain ⟨v, hv⟩ := g5 (by simp [hbp] at hm; exact hm)
      exact ⟨v, by show (upd h.cell p _) b 2 = _; simp only [upd, ite_eq_right hbp]; exact hv⟩
    · show (upd h.cell p _) b 2 = _; simp only [upd, ite_eq_right hbp]
      exact g6 (fun hm => hn (List.mem_cons_of_mem _ hm))

/-- `arc_downgrade` through a held strong handle: a `Weak` more. -/
theorem arcDowngrade_ok {h : Heap (RcCell V)} {hs ws : List Nat} {p : Nat} (hw : h.WF) (hi : ArcInv h hs ws)
    (hp : p ∈ hs) :
    ∃ h', cntInc h p 1 = some h' ∧ ArcInv h' hs (p :: ws) ∧ h'.WF ∧ h'.live = h.live := by
  obtain ⟨hl, hsz, hc0, hc1, hv, -⟩ := hi p (Or.inl hp)
  refine ⟨{ h with cell := upd h.cell p (upd (h.cell p) 1
      (some (.cnt (ws.count p + (if p ∈ hs then 1 else 0) + 1)))) },
    by simp only [cntInc, load_of hl hsz (by omega) hc1, store_of hl hsz (by omega : 1 < 3)], ?_,
    fun b hb => hw b hb, rfl⟩
  intro b hb
  by_cases hbp : b = p
  · subst hbp
    refine ⟨hl, hsz, by show (upd h.cell b _) b 0 = _; simp [upd, hc0], ?_, fun _ => ?_,
      fun hn => absurd hp hn⟩
    · show (upd h.cell b _) b 1 = _; simp [upd, hp]
    · obtain ⟨v, hv⟩ := hv hp; exact ⟨v, by show (upd h.cell b _) b 2 = _; simp [upd, hv]⟩
  · have hb' : b ∈ hs ∨ b ∈ ws := by simp [hbp] at hb; exact hb
    obtain ⟨g1, g2, g3, g4, g5, g6⟩ := hi b hb'
    refine ⟨g1, g2, ?_, ?_, fun hm => ?_, fun hn => ?_⟩
    · show (upd h.cell p _) b 0 = _; simp only [upd, ite_eq_right hbp]; exact g3
    · show (upd h.cell p _) b 1 = _; simp only [upd, ite_eq_right hbp]; rw [g4, List.count_cons]; simp [Ne.symm hbp]
    · obtain ⟨v, hv⟩ := g5 hm
      exact ⟨v, by show (upd h.cell p _) b 2 = _; simp only [upd, ite_eq_right hbp]; exact hv⟩
    · show (upd h.cell p _) b 2 = _; simp only [upd, ite_eq_right hbp]; exact g6 hn

/-- `ArcWeak_share` through a held `Weak`: a `Weak` more. The runtime
    increments only the weak count (`nurl_atomic_i64_inc` on `ctl + 8`),
    whether or not a strong handle is left: while one is, the value stays in
    its slot; once none is, the block stays live, holding `.gone`. The
    invariant holds for the handles with the new `Weak`, the value slot and
    the strong count are unchanged, and nothing is allocated or freed. -/
theorem weakClone_ok {h : Heap (RcCell V)} {hs ws : List Nat} {p : Nat} (hw : h.WF) (hi : ArcInv h hs ws)
    (hp : p ∈ ws) :
    ∃ h', cntInc h p 1 = some h' ∧ ArcInv h' hs (p :: ws) ∧ h'.WF ∧ h'.live = h.live ∧
      h'.cell p 0 = h.cell p 0 ∧ h'.cell p 2 = h.cell p 2 ∧ ∀ b, b ≠ p → h'.cell b = h.cell b := by
  obtain ⟨hl, hsz, hc0, hc1, hv, hg⟩ := hi p (Or.inr hp)
  refine ⟨{ h with cell := upd h.cell p (upd (h.cell p) 1
      (some (.cnt (ws.count p + (if p ∈ hs then 1 else 0) + 1)))) },
    by simp only [cntInc, load_of hl hsz (by omega) hc1, store_of hl hsz (by omega : 1 < 3)], ?_,
    fun b hb => hw b hb, rfl, by show (upd h.cell p _) p 0 = _; simp [upd],
    by show (upd h.cell p _) p 2 = _; simp [upd],
    fun b hb => by show (upd h.cell p _) b = _; simp [upd, hb]⟩
  intro b hb
  by_cases hbp : b = p
  · subst hbp
    refine ⟨hl, hsz, by show (upd h.cell b _) b 0 = _; simp [upd, hc0], ?_, fun hm => ?_, fun hn => ?_⟩
    · show (upd h.cell b _) b 1 = _
      by_cases hm : b ∈ hs <;> simp [upd, hm] <;> omega
    · obtain ⟨v, hv⟩ := hv hm; exact ⟨v, by show (upd h.cell b _) b 2 = _; simp [upd, hv]⟩
    · show (upd h.cell b _) b 2 = _; simp [upd, hg hn]
  · have hb' : b ∈ hs ∨ b ∈ ws := by simp [hbp] at hb; exact hb
    obtain ⟨g1, g2, g3, g4, g5, g6⟩ := hi b hb'
    refine ⟨g1, g2, ?_, ?_, fun hm => ?_, fun hn => ?_⟩
    · show (upd h.cell p _) b 0 = _; simp only [upd, ite_eq_right hbp]; exact g3
    · show (upd h.cell p _) b 1 = _; simp only [upd, ite_eq_right hbp]; rw [g4, List.count_cons]; simp [Ne.symm hbp]
    · obtain ⟨v, hv⟩ := g5 hm
      exact ⟨v, by show (upd h.cell p _) b 2 = _; simp only [upd, ite_eq_right hbp]; exact hv⟩
    · show (upd h.cell p _) b 2 = _; simp only [upd, ite_eq_right hbp]; exact g6 hn

/-- Any change to block `p` alone keeps the invariant's clauses for every
    other block whose handles did not change. -/
theorem arcInv_other {h h' : Heap (RcCell V)} {hs ws hs' ws' : List Nat} {p : Nat} (hi : ArcInv h hs ws)
    (hlv : ∀ b, b ≠ p → h'.live b = h.live b) (hsz : ∀ b, b ≠ p → h'.size b = h.size b)
    (hc : ∀ b, b ≠ p → h'.cell b = h.cell b)
    (hhs : ∀ b, b ≠ p → hs'.count b = hs.count b) (hws : ∀ b, b ≠ p → ws'.count b = ws.count b) :
    ∀ b, b ≠ p → (b ∈ hs' ∨ b ∈ ws') → h'.live b = true ∧ h'.size b = 3 ∧
      h'.cell b 0 = some (.cnt (hs'.count b)) ∧
      h'.cell b 1 = some (.cnt (ws'.count b + (if b ∈ hs' then 1 else 0))) ∧
      (b ∈ hs' → ∃ v, h'.cell b 2 = some (.val v)) ∧ (b ∉ hs' → h'.cell b 2 = some .gone) := by
  intro b hbp hb
  have hmem : ∀ (l l' : List Nat), l'.count b = l.count b → (b ∈ l' ↔ b ∈ l) := by
    intro l l' e
    rw [← List.count_pos_iff, ← List.count_pos_iff, e]
  have e1 := hmem hs hs' (hhs b hbp)
  have e2 := hmem ws ws' (hws b hbp)
  obtain ⟨g1, g2, g3, g4, g5, g6⟩ := hi b (by rcases hb with hb | hb; exact Or.inl (e1.mp hb); exact Or.inr (e2.mp hb))
  refine ⟨by rw [hlv b hbp]; exact g1, by rw [hsz b hbp]; exact g2, ?_, ?_, fun hm => ?_, fun hn => ?_⟩
  · rw [hc b hbp, g3, hhs b hbp]
  · rw [hc b hbp, g4, hws b hbp]; simp only [e1]
  · obtain ⟨v, hv⟩ := g5 (e1.mp hm); exact ⟨v, by rw [hc b hbp]; exact hv⟩
  · rw [hc b hbp]; exact g6 (fun hm => hn (e1.mpr hm))

/-- `Arc_drop` through a held strong handle succeeds. The value comes out
    exactly when it was the last strong handle, and it is the value the
    block held (`h.cell p 2`), as `rcRelease_ok` states for `rcbox`; a
    release that is not the last hands back nothing. The block is freed
    exactly when no handle of either kind is left on it. The invariant
    holds for the handles left. -/
theorem arcDrop_ok {h : Heap (RcCell V)} {hs ws : List Nat} {p : Nat} (hw : h.WF) (hi : ArcInv h hs ws)
    (hp : p ∈ hs) :
    ∃ h' r, arcDrop h p = some (h', r) ∧ ArcInv h' (hs.erase p) ws ∧ h'.WF ∧
      ((hs.count p = 1 ↔ ∃ v, r = some v) ∧ (h'.live p = false ↔ p ∉ hs.erase p ∧ p ∉ ws) ∧
       (hs.count p = 1 → ∃ v, r = some v ∧ h.cell p 2 = some (.val v)) ∧ (hs.count p ≠ 1 → r = none)) := by
  obtain ⟨hl, hsz, hc0, hc1, hv, -⟩ := hi p (Or.inl hp)
  obtain ⟨v, hv⟩ := hv hp
  have hpos : 0 < hs.count p := List.count_pos_iff.mpr hp
  have hc1' : h.cell p 1 = some (.cnt (ws.count p + 1)) := by rw [hc1]; simp [hp]
  have herase : ∀ b, b ≠ p → (hs.erase p).count b = hs.count b := fun b hb => List.count_erase_of_ne hb
  by_cases h1 : hs.count p = 1
  · have hpe : p ∉ hs.erase p := by
      intro hm; have := List.count_pos_iff.mpr hm; rw [List.count_erase_self] at this; omega
    let h0 : Heap (RcCell V) := { h with cell := upd h.cell p (upd (h.cell p) 0 (some (.cnt 0))) }
    let h1' : Heap (RcCell V) := { h0 with cell := upd h0.cell p (upd (h0.cell p) 2 (some .gone)) }
    have hst : ((h.store p 0 (.cnt 0)).bind fun h0 => h0.store p 2 .gone) = some h1' := by
      rw [store_of (c := .cnt 0) hl hsz (by omega : 0 < 3), Option.bind_some]
      exact store_of (h := h0) hl hsz (by omega : 2 < 3)
    -- block `p`'s cells in `h1'`, and every other block's
    have hp0 : h1'.cell p 0 = some (.cnt 0) := by simp [h1', h0, upd]
    have hp1 : h1'.cell p 1 = h.cell p 1 := by simp [h1', h0, upd]
    have hp2 : h1'.cell p 2 = some .gone := by simp [h1', upd]
    have hoth : ∀ b, b ≠ p → h1'.cell b = h.cell b := fun b hb => by simp [h1', h0, upd, hb]
    by_cases hw1 : ws.count p = 0
    · -- the only owner, no Weak: the block freed at once (answer 2)
      have hpw : p ∉ ws := fun hm => by have := List.count_pos_iff.mpr hm; omega
      refine ⟨{ h1' with live := upd h1'.live p false }, some v, ?_, ?_, ?_, ⟨⟨fun _ => ⟨v, rfl⟩, fun _ => h1⟩, ?_,
        fun _ => ⟨v, rfl, hv⟩, fun e => absurd h1 e⟩⟩
      · simp only [arcDrop, load_of hl hsz (by omega) hc0, h1, ↓reduceIte, load_of hl hsz (by omega) hv,
          load_of hl hsz (by omega) hc1', hst, hw1, Nat.zero_add, Heap.free]
        simp [h1', h0, hl]
      · intro b hb
        have hbp : b ≠ p := by rintro rfl; rcases hb with hb | hb; exact hpe hb; exact hpw hb
        exact arcInv_other (h' := { h1' with live := upd h1'.live p false }) hi
          (fun b hb => by show (upd h.live p false) b = _; simp [upd, hb])
          (fun _ _ => rfl) hoth herase (fun _ _ => rfl) b hbp hb
      · intro b hb; show (upd h.live p false) b = false
        simp only [upd]; split
        · rfl
        · exact hw b hb
      · show (upd h.live p false) p = false ↔ _; simp [upd, hpe, hpw]
    · -- the last strong handle while a Weak names the block (answer 1): weak down by one
      have hpw : p ∈ ws := List.count_pos_iff.mp (by omega)
      let h2 : Heap (RcCell V) := { h1' with cell := upd h1'.cell p (upd (h1'.cell p) 1 (some (.cnt (ws.count p)))) }
      have hl1 : h1'.live p = true := hl
      have hsz1 : h1'.size p = 3 := hsz
      have hc1'' : h1'.cell p 1 = some (.cnt (ws.count p + 1)) := by rw [hp1, hc1']
      have hwr : weakRelease h1' p = some (h2, false) := by
        simp only [weakRelease, load_of hl1 hsz1 (by omega) hc1'', show ¬ ws.count p + 1 = 1 by omega,
          ↓reduceIte, store_of hl1 hsz1 (by omega : 1 < 3), Option.map_some, Nat.add_sub_cancel]
        rfl
      refine ⟨h2, some v, ?_, ?_, fun b hb => hw b hb, ⟨⟨fun _ => ⟨v, rfl⟩, fun _ => h1⟩, ?_,
        fun _ => ⟨v, rfl, hv⟩, fun e => absurd h1 e⟩⟩
      · simp only [arcDrop, load_of hl hsz (by omega) hc0, h1, ↓reduceIte, load_of hl hsz (by omega) hv,
          load_of hl hsz (by omega) hc1', hst, show ¬ ws.count p + 1 = 1 by omega]
        rw [hwr]; rfl
      · intro b hb
        by_cases hbp : b = p
        · subst hbp
          refine ⟨hl, hsz, ?_, ?_, fun hm => absurd hm hpe, fun _ => ?_⟩
          · show (upd h1'.cell b _) b 0 = _
            simp only [upd, ↓reduceIte]
            rw [show (h1'.cell b) 0 = some (.cnt 0) from hp0]
            simp [List.count_erase_self, h1]
          · show (upd h1'.cell b _) b 1 = _
            simp [upd, hpe]
          · show (upd h1'.cell b _) b 2 = _
            simp only [upd, ↓reduceIte]
            rw [show (h1'.cell b) 2 = some .gone from hp2]; rfl
        · exact arcInv_other (h' := h2) hi (fun _ _ => rfl) (fun _ _ => rfl)
            (fun b hb => by show (upd h1'.cell p _) b = _; simp only [upd, ite_eq_right hb]; exact hoth b hb)
            herase (fun _ _ => rfl) b hbp hb
      · show h.live p = false ↔ _; simp [hl, hpw]
  · -- not the last strong handle: count down
    have hpe : p ∈ hs.erase p := by
      apply List.count_pos_iff.mp; rw [List.count_erase_self]; omega
    refine ⟨{ h with cell := upd h.cell p (upd (h.cell p) 0 (some (.cnt (hs.count p - 1)))) }, none, ?_, ?_,
      fun b hb => hw b hb, ⟨fun e => absurd e h1, fun ⟨x, hx⟩ => by cases hx⟩, ?_,
      fun e => absurd e h1, fun _ => rfl⟩
    · simp only [arcDrop, load_of hl hsz (by omega) hc0, h1, ↓reduceIte, store_of hl hsz (by omega : 0 < 3),
        Option.map_some]
    · intro b hb
      by_cases hbp : b = p
      · subst hbp
        refine ⟨hl, hsz, ?_, ?_, fun _ => ⟨v, by show (upd h.cell b _) b 2 = _; simp [upd, hv]⟩,
          fun hn => absurd hpe hn⟩
        · show (upd h.cell b _) b 0 = _; simp [upd, List.count_erase_self]
        · show (upd h.cell b _) b 1 = _; simp [upd, hc1', hpe]
      · exact arcInv_other (h' := { h with cell := upd h.cell p (upd (h.cell p) 0 (some (.cnt (hs.count p - 1)))) })
          hi (fun _ _ => rfl) (fun _ _ => rfl)
          (fun b hb => by show (upd h.cell p _) b = _; simp [upd, hb]) herase (fun _ _ => rfl) b hbp hb
    · show h.live p = false ↔ _; simp [hl, hpe]

/-- `ArcWeak_drop` through a held `Weak`: weak down by one, and the block is
    freed exactly when it was the last handle of either kind. Both the
    returned flag and the heap say so: `h'.live p` is `false` exactly when
    no handle is left on `p`, in `arcDrop_ok`'s form. -/
theorem weakDrop_ok {h : Heap (RcCell V)} {hs ws : List Nat} {p : Nat} (hw : h.WF) (hi : ArcInv h hs ws)
    (hp : p ∈ ws) :
    ∃ h' fr, weakRelease h p = some (h', fr) ∧ ArcInv h' hs (ws.erase p) ∧ h'.WF ∧
      (fr = true ↔ (p ∉ hs ∧ p ∉ ws.erase p)) ∧ (h'.live p = false ↔ p ∉ hs ∧ p ∉ ws.erase p) := by
  obtain ⟨hl, hsz, hc0, hc1, hv, hg⟩ := hi p (Or.inr hp)
  have hpos : 0 < ws.count p := List.count_pos_iff.mpr hp
  have herase : ∀ b, b ≠ p → (ws.erase p).count b = ws.count b := fun b hb => List.count_erase_of_ne hb
  have hcnt : (ws.erase p).count p = ws.count p - 1 := by rw [List.count_erase_self]
  by_cases hlast : ws.count p + (if p ∈ hs then 1 else 0) = 1
  · have hph : p ∉ hs := by intro hm; simp [hm] at hlast; omega
    have hpe : p ∉ ws.erase p := by
      intro hm; have := List.count_pos_iff.mpr hm; simp [hph] at hlast; omega
    refine ⟨{ h with live := upd h.live p false }, true, ?_, ?_, ?_, by simp [hph, hpe],
      by show (upd h.live p false) p = false ↔ _; simp [upd, hph, hpe]⟩
    · simp only [weakRelease, load_of hl hsz (by omega) hc1, hlast, ↓reduceIte, Heap.free, hl, Option.map_some]
    · intro b hb
      have hbp : b ≠ p := by rintro rfl; rcases hb with hb | hb; exact hph hb; exact hpe hb
      exact arcInv_other (h' := { h with live := upd h.live p false }) hi
        (fun b hb => by show (upd h.live p false) b = _; simp [upd, hb])
        (fun _ _ => rfl) (fun _ _ => rfl) (fun _ _ => rfl) herase b hbp hb
    · intro b hb; show (upd h.live p false) b = false
      simp only [upd]; split
      · rfl
      · exact hw b hb
  · refine ⟨{ h with cell := upd h.cell p (upd (h.cell p) 1
        (some (.cnt (ws.count p + (if p ∈ hs then 1 else 0) - 1)))) }, false, ?_, ?_, fun b hb => hw b hb, ?_, ?_⟩
    · simp only [weakRelease, load_of hl hsz (by omega) hc1, hlast, ↓reduceIte, store_of hl hsz (by omega : 1 < 3),
        Option.map_some]
    · intro b hb
      by_cases hbp : b = p
      · subst hbp
        refine ⟨hl, hsz, by show (upd h.cell b _) b 0 = _; simp [upd, hc0], ?_, fun hm => ?_, fun hn => ?_⟩
        · show (upd h.cell b _) b 1 = _
          simp only [upd, ↓reduceIte, hcnt]
          by_cases hm : b ∈ hs <;> simp [hm] at hlast ⊢ <;> omega
        · obtain ⟨x, hx⟩ := hv hm; exact ⟨x, by show (upd h.cell b _) b 2 = _; simp [upd, hx]⟩
        · show (upd h.cell b _) b 2 = _; simp [upd, hg hn]
      · exact arcInv_other (h' := { h with cell := upd h.cell p (upd (h.cell p) 1
            (some (.cnt (ws.count p + (if p ∈ hs then 1 else 0) - 1)))) }) hi (fun _ _ => rfl) (fun _ _ => rfl)
          (fun b hb => by show (upd h.cell p _) b = _; simp [upd, hb]) (fun _ _ => rfl) herase b hbp hb
    · simp only [Bool.false_eq_true, false_iff, not_and, Decidable.not_not]
      intro hph
      apply List.count_pos_iff.mp
      simp [hph] at hlast; rw [hcnt]; omega
    · show h.live p = false ↔ _
      simp only [hl, Bool.true_eq_false, false_iff, not_and, Decidable.not_not]
      intro hph
      apply List.count_pos_iff.mp
      simp [hph] at hlast; rw [hcnt]; omega

/-- `arc_weak_upgrade` through a held `Weak`: a strong handle exactly while
    the value is alive (a strong handle names the block). Otherwise none,
    nothing changes, and the slot the value was in is empty. -/
theorem upgrade_ok {h : Heap (RcCell V)} {hs ws : List Nat} {p : Nat} (hw : h.WF) (hi : ArcInv h hs ws)
    (hp : p ∈ ws) :
    ∃ h' ok, arcUpgrade h p = some (h', ok) ∧ (ok = true ↔ p ∈ hs) ∧
      ArcInv h' (if ok then p :: hs else hs) ws ∧ h'.WF ∧ (ok = true → ∃ v, h'.cell p 2 = some (.val v)) ∧
      (ok = false → h'.cell p 2 = some .gone) := by
  obtain ⟨hl, hsz, hc0, hc1, hv, hg⟩ := hi p (Or.inr hp)
  by_cases hph : p ∈ hs
  · have hpos : hs.count p ≠ 0 := by have := List.count_pos_iff.mpr hph; omega
    obtain ⟨h', he, hi', hw', hlv⟩ := arcClone_ok hw hi hph
    refine ⟨h', true, ?_, by simp [hph], by simpa using hi', hw', fun _ => ?_, fun e => by cases e⟩
    · simp only [cntInc] at he
      simp only [arcUpgrade, load_of hl hsz (by omega) hc0, hpos, ↓reduceIte]
      simp only [load_of hl hsz (by omega) hc0] at he
      rw [he]; rfl
    · exact (hi' p (Or.inl (List.mem_cons_self))).2.2.2.2.1 List.mem_cons_self
  · have hz : hs.count p = 0 := List.count_eq_zero_of_not_mem hph
    refine ⟨h, false, ?_, by simp [hph], by simpa using hi, hw, fun e => (by cases e), fun _ => hg hph⟩
    simp only [arcUpgrade, load_of hl hsz (by omega) hc0, hz, ↓reduceIte]

end B
