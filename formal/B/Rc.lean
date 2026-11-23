import B.Vec

/-!
# B3: `rcbox`, the reference-counted block behind library handles (AGORA-970)

`stdlib/core/rcbox.nu` keeps a library handle's state in one heap block,
`[ owners ][ value ]`. `rcbox_new` makes it with one owner, `rcbox_share`
adds one (`nurl_rc_share`), and `rcbox_release` takes one away
(`nurl_rc_release`, which answers 1 for the last owner). The last owner
moves the value out to drop it (`mem_take`) and frees the block.
`Shared T` and every library handle (`Regex`, `Sha256`, ...) are built on it.

The model runs that code on the provenance heap of `B/Vec.lean`. A block
has two cells, the count and the value. The handles the program holds are
a list of block ids, one entry per owner. The invariant `RcInv` says every
block a handle names is live, has the two cells, and has a count equal to
the number of handles naming it. Each operation keeps it. As a result:

* a share or a release through a handle the program holds never reads or
  writes a freed block (each succeeds);
* the value is handed out to be dropped exactly at the release of the last
  handle, which also frees the block. No handle names it afterwards, so it
  cannot be released or read again: no use after free, no double drop;
* a release that is not the last leaves the value in place.

`nurl_rc_share` / `nurl_rc_release` are atomic in the runtime. Here they
are single steps, which is what they are to one thread. Their atomicity
across threads is A3's `Arc` (and phase D's runtime obligation).
-/

namespace B

open A1 (upd)

/-- A cell of an rcbox: the owner count, or the value. -/
inductive RcCell (V : Type) where
  | cnt (n : Nat)
  | val (v : V)

variable {V : Type}

/-- `rcbox_new x`: `nurl_alloc` of the two cells, the count 1, the value. -/
def rcNew (h : Heap (RcCell V)) (x : V) : Heap (RcCell V) × Nat :=
  ({ live := upd h.live h.nid true, size := upd h.size h.nid 2,
     cell := upd h.cell h.nid (fun i => if i = 0 then some (.cnt 1) else if i = 1 then some (.val x) else none),
     nid := h.nid + 1 }, h.nid)

/-- `rcbox_share p`: the count up by one. -/
def rcShare (h : Heap (RcCell V)) (p : Nat) : Option (Heap (RcCell V)) :=
  match h.load p 0 with
  | some (.cnt n) => h.store p 0 (.cnt (n + 1))
  | _ => none

/-- `rcbox_release p`: the count down by one. For the last owner, the
    value is moved out (to be dropped) and the block freed. -/
def rcRelease (h : Heap (RcCell V)) (p : Nat) : Option (Heap (RcCell V) × Option V) :=
  match h.load p 0 with
  | some (.cnt n) =>
    if n = 1 then
      match h.load p 1 with
      | some (.val v) => (h.free p).map fun h1 => (h1, some v)
      | _ => none
    else (h.store p 0 (.cnt (n - 1))).map fun h1 => (h1, none)
  | _ => none

/-- Every block a handle in `hs` names is live, has its two cells, a count
    equal to the number of handles naming it, and a value. -/
def RcInv (h : Heap (RcCell V)) (hs : List Nat) : Prop :=
  ∀ b, b ∈ hs → h.live b = true ∧ h.size b = 2 ∧ h.cell b 0 = some (.cnt (hs.count b)) ∧
    ∃ v, h.cell b 1 = some (.val v)

theorem rcNew_ok {h : Heap (RcCell V)} {hs : List Nat} (x : V) (hw : h.WF) (hi : RcInv h hs) :
    RcInv (rcNew h x).1 ((rcNew h x).2 :: hs) ∧ (rcNew h x).1.WF ∧ (rcNew h x).2 = h.nid ∧
      ∀ b, b ≠ h.nid → (rcNew h x).1.cell b = h.cell b := by
  have hnin : h.nid ∉ hs := fun hm => by
    have := (hi h.nid hm).1; rw [hw h.nid (Nat.le_refl _)] at this; exact absurd this (by simp)
  refine ⟨fun b hb => ?_, fun b hb => ?_, rfl, fun b hb => ?_⟩
  · simp only [rcNew] at hb ⊢
    by_cases hbn : b = h.nid
    · subst hbn
      simp only [upd, ↓reduceIte, true_and]
      refine ⟨?_, ⟨x, by simp⟩⟩
      simp [List.count_eq_zero_of_not_mem hnin]
    · have hb' : b ∈ hs := by simp [hbn] at hb; exact hb
      obtain ⟨h1, h2, h3, v, h4⟩ := hi b hb'
      simp only [upd, ite_eq_right hbn]
      refine ⟨h1, h2, ?_, v, h4⟩
      rw [h3, List.count_cons]; simp [Ne.symm hbn]
  · simp only [rcNew, upd] at hb ⊢
    rw [ite_eq_right (by omega)]; exact hw b (by omega)
  · simp only [rcNew, upd, ite_eq_right hb]

theorem rcShare_ok {h : Heap (RcCell V)} {hs : List Nat} {p : Nat} (hw : h.WF) (hi : RcInv h hs)
    (hp : p ∈ hs) :
    ∃ h', rcShare h p = some h' ∧ RcInv h' (p :: hs) ∧ h'.WF ∧ h'.live = h.live ∧
      ∀ b, b ≠ p → h'.cell b = h.cell b := by
  obtain ⟨hl, hsz, hc, v, hv⟩ := hi p hp
  have hload : h.load p 0 = some (.cnt (hs.count p)) := by
    simp only [Heap.load, hl, hsz, true_and]; rw [ite_eq_left (by omega)]; exact hc
  have hin : h.live p = true ∧ 0 < h.size p := ⟨hl, by omega⟩
  refine ⟨{ h with cell := upd h.cell p (upd (h.cell p) 0 (some (.cnt (hs.count p + 1)))) }, ?_, ?_,
    fun b hb => hw b hb, rfl, fun b hb => ?_⟩
  · simp only [rcShare, hload, Heap.store, hin, and_self, ↓reduceIte]
  · intro b hb
    by_cases hbp : b = p
    · subst hbp
      refine ⟨hl, hsz, ?_, v, ?_⟩
      · show (upd h.cell b _) b 0 = _; simp [upd]
      · show (upd h.cell b _) b 1 = _; simp [upd, hv]
    · have hb' : b ∈ hs := by simp [hbp] at hb; exact hb
      obtain ⟨h1, h2, h3, w, h4⟩ := hi b hb'
      refine ⟨h1, h2, ?_, w, ?_⟩
      · show (upd h.cell p _) b 0 = _; simp only [upd, ite_eq_right hbp]; rw [h3, List.count_cons]
        simp [Ne.symm hbp]
      · show (upd h.cell p _) b 1 = _; simp only [upd, ite_eq_right hbp]; exact h4
  · show (upd h.cell p _) b = h.cell b; simp only [upd, ite_eq_right hb]

/-- A release through a handle the program holds succeeds. If it was the
    last handle on the block, the value comes out to be dropped and the
    block is freed. Otherwise the count drops and the value stays. Either
    way the invariant holds for the handles left. -/
theorem rcRelease_ok {h : Heap (RcCell V)} {hs : List Nat} {p : Nat} (hw : h.WF) (hi : RcInv h hs)
    (hp : p ∈ hs) :
    ∃ h' r, rcRelease h p = some (h', r) ∧ RcInv h' (hs.erase p) ∧ h'.WF ∧
      (hs.count p = 1 → (∃ v, r = some v ∧ h.cell p 1 = some (.val v)) ∧ h'.live p = false ∧ p ∉ hs.erase p) ∧
      (hs.count p ≠ 1 → r = none ∧ h'.live p = true ∧ h'.cell p 1 = h.cell p 1) ∧
      ∀ b, b ≠ p → h'.cell b = h.cell b ∧ h'.live b = h.live b := by
  obtain ⟨hl, hsz, hc, v, hv⟩ := hi p hp
  have hpos : 0 < hs.count p := List.count_pos_iff.mpr hp
  have hload : h.load p 0 = some (.cnt (hs.count p)) := by
    simp only [Heap.load, hl, hsz, true_and]; rw [ite_eq_left (by omega)]; exact hc
  by_cases h1 : hs.count p = 1
  · have hload1 : h.load p 1 = some (.val v) := by
      simp only [Heap.load, hl, hsz, true_and]; rw [ite_eq_left (by omega)]; exact hv
    have hnot : p ∉ hs.erase p := by
      intro hm
      have := List.count_pos_iff.mpr hm
      rw [List.count_erase_self] at this; omega
    refine ⟨{ h with live := upd h.live p false }, some v, ?_, ?_, ?_, fun _ => ⟨⟨v, rfl, hv⟩, by simp [upd], hnot⟩,
      fun e => absurd h1 e, fun b hb => ⟨rfl, by show (upd h.live p false) b = _; simp only [upd, ite_eq_right hb]⟩⟩
    · simp only [rcRelease, hload, h1, ↓reduceIte, hload1, Heap.free, hl, Option.map_some]
    · intro b hb
      have hbp : b ≠ p := fun e => hnot (e ▸ hb)
      have hb' : b ∈ hs := List.mem_of_mem_erase hb
      obtain ⟨g1, g2, g3, w, g4⟩ := hi b hb'
      refine ⟨by show (upd h.live p false) b = true; simp only [upd, ite_eq_right hbp]; exact g1, g2, ?_, w, g4⟩
      rw [g3, List.count_erase_of_ne hbp]
    · intro b hb
      show (upd h.live p false) b = false
      simp only [upd]
      by_cases hbp : b = p
      · rw [ite_eq_left hbp]
      · rw [ite_eq_right hbp]; exact hw b hb
  · have hin : h.live p = true ∧ 0 < h.size p := ⟨hl, by omega⟩
    refine ⟨{ h with cell := upd h.cell p (upd (h.cell p) 0 (some (.cnt (hs.count p - 1)))) }, none, ?_, ?_,
      fun b hb => hw b hb, fun e => absurd e h1, fun _ => ⟨rfl, hl, ?_⟩, fun b hb => ⟨?_, rfl⟩⟩
    · simp only [rcRelease, hload, h1, ↓reduceIte, Heap.store, hin, and_self, Option.map_some]
    · intro b hb
      by_cases hbp : b = p
      · subst hbp
        refine ⟨hl, hsz, ?_, v, ?_⟩
        · show (upd h.cell b _) b 0 = _; simp only [upd, ↓reduceIte]; rw [List.count_erase_self]
        · show (upd h.cell b _) b 1 = _; simp [upd, hv]
      · have hb' : b ∈ hs := List.mem_of_mem_erase hb
        obtain ⟨g1, g2, g3, w, g4⟩ := hi b hb'
        refine ⟨g1, g2, ?_, w, ?_⟩
        · show (upd h.cell p _) b 0 = _; simp only [upd, ite_eq_right hbp]
          rw [g3, List.count_erase_of_ne hbp]
        · show (upd h.cell p _) b 1 = _; simp only [upd, ite_eq_right hbp]; exact g4
    · show (upd h.cell p _) p 1 = h.cell p 1; simp [upd]
    · show (upd h.cell p _) b = h.cell b; simp only [upd, ite_eq_right hb]

end B
