import A1.Semantics

/-!
# B1: the raw core of `Vec` meets A1's `Vec` (AGORA-970)

Phase B proves that the standard library's `unsafe` base meets the semantic
types the rules give it. This file covers the first piece, the owned buffer
of `stdlib/core/vec.nu`. It models the buffer at the level that code runs on:
a heap of blocks, a control triple `(data, len, cap)`, and the code of
`vec_push`, `__vec_grow_to`, `__vec_place`, `alloc_grow_cap`, `vec_get`,
`vec_set` (by `.data idx`), `vec_pop` and `vec_free`. It proves that each
operation:

* touches only cells inside a live block (`load` and `store` are
  `none` — undefined behaviour — anywhere else, and every operation here
  succeeds on a represented `Vec`);
* keeps the representation: the first `len` cells of the buffer hold the
  abstract list, `len ≤ cap`, and the block's size is `cap`;
* changes the buffer exactly as A1's step does. `vec_push` either keeps the
  block (A1's `push`) or ends it and gets the heap's next fresh id (A1's
  `pushRealloc`, the same `upd (upd alloc d false) nid true`). So a view of
  the old buffer, which A1's `realloc` effect ends, is a pointer into a
  block the heap no longer has live;
* leaves every other block as it was;
* frees the block once: `vec_free` of a represented `Vec` succeeds, and a
  second `free` of the same block is `none`.

The heap has provenance. A block is named by the id it was allocated with,
and an id is never reused. C's `realloc` ends its old block even when it
hands back the same address, which matches the C standard; `Heap.realloc`
always gives a new id.

What B1 leaves out, for the next steps: a borrowed view (`cap < 0`,
`vec_borrow_raw`), the packed-string layout, element destructors (cells
here are values that are moved by bit copy, as `mem_take` makes them),
byte sizes and their overflow (`alloc_size`), and `vec_insert` /
`vec_remove`'s shifts.
-/

namespace B

open A1 (upd)

/-- A heap with provenance: `live b` says whether block `b` is allocated,
    `size b` how many element cells it has, `cell b i` what cell `i` holds
    (`none`: never written). `nid` is the next fresh id. -/
structure Heap (α : Type) where
  live : Nat → Bool
  size : Nat → Nat
  cell : Nat → Nat → Option α
  nid  : Nat

namespace Heap

variable {α : Type}

/-- No block at or past the next fresh id is live. -/
def WF (h : Heap α) : Prop := ∀ b, h.nid ≤ b → h.live b = false

/-- A read of cell `i` of block `b`: `none` outside a live block. -/
def load (h : Heap α) (b i : Nat) : Option α :=
  if h.live b = true ∧ i < h.size b then h.cell b i else none

/-- A write of cell `i` of block `b`: `none` outside a live block. -/
def store (h : Heap α) (b i : Nat) (x : α) : Option (Heap α) :=
  if h.live b = true ∧ i < h.size b then
    some { h with cell := upd h.cell b (upd (h.cell b) i (some x)) }
  else none

/-- `nurl_alloc`: a fresh block of `n` cells. -/
def alloc (h : Heap α) (n : Nat) : Heap α × Nat :=
  ({ live := upd h.live h.nid true, size := upd h.size h.nid n,
     cell := upd h.cell h.nid (fun _ => none), nid := h.nid + 1 }, h.nid)

/-- `nurl_free`: `none` on a block that is not live (a double free). -/
def free (h : Heap α) (b : Nat) : Option (Heap α) :=
  if h.live b = true then some { h with live := upd h.live b false } else none

/-- `nurl_realloc` to `n` cells. The old block ends, the new one is fresh,
    and the cells both have move over. -/
def realloc (h : Heap α) (b n : Nat) : Option (Heap α × Nat) :=
  if h.live b = true then
    some ({ live := upd (upd h.live b false) h.nid true, size := upd h.size h.nid n,
            cell := upd h.cell h.nid (fun i => if i < h.size b ∧ i < n then h.cell b i else none),
            nid := h.nid + 1 }, h.nid)
  else none

end Heap

/-- The doubling loop of `alloc_grow_cap`: from `c`, double while below
    `need`. -/
def doubleTo (c need : Nat) : Nat :=
  if 0 < c ∧ c < need then doubleTo (2 * c) need else c
termination_by need - c

theorem doubleTo_ge {c need : Nat} (hc : 0 < c) : need ≤ doubleTo c need := by
  induction c using doubleTo.induct (need := need) with
  | case1 c h ih =>
    rw [doubleTo]; simp only [h, and_self, ↓reduceIte]; exact ih (by omega)
  | case2 c h =>
    rw [doubleTo]; simp only [h, ↓reduceIte]; omega

/-- `alloc_grow_cap cap need`: doubled from `cap` (from 4 when empty) until
    it holds `need`, or `need` itself past `2^62`. -/
def growCap (cap need : Nat) : Nat :=
  let c := if 0 < cap then cap else 4
  if need > 4611686018427387904 then (if c > need then c else need) else doubleTo c need

theorem growCap_ge (cap need : Nat) : need ≤ growCap cap need := by
  unfold growCap
  have hc : 0 < (if 0 < cap then cap else 4) := by split <;> omega
  generalize (if 0 < cap then cap else 4) = c at hc ⊢
  dsimp only
  split
  · split <;> omega
  · exact doubleTo_ge hc

/-- A `Vec`'s control block: the data pointer (`none`: null, no buffer yet),
    the length and the capacity. B1 covers owned buffers only, so `cap ≥ 0`
    is built in. -/
structure RVec where
  data : Option Nat
  len  : Nat
  cap  : Nat

variable {α : Type}

/-- The control block `v` on heap `h` represents the list `es`. -/
def Rep (h : Heap α) (v : RVec) (es : List α) : Prop :=
  v.len = es.length ∧ v.len ≤ v.cap ∧
  match v.data with
  | none => v.cap = 0
  | some d => h.live d = true ∧ h.size d = v.cap ∧
      ∀ i (hi : i < es.length), h.cell d i = some es[i]

/-- `__vec_grow_to` with `__vec_place` on an owned buffer: when the capacity
    is below `need`, the first buffer comes from `nurl_alloc` and any later
    one from `nurl_realloc`. -/
def growTo (h : Heap α) (v : RVec) (need : Nat) : Option (Heap α × RVec) :=
  if v.cap < need then
    match v.data with
    | none =>
      some ((h.alloc (growCap v.cap need)).1,
            { v with data := some (h.alloc (growCap v.cap need)).2, cap := growCap v.cap need })
    | some d =>
      (h.realloc d (growCap v.cap need)).map fun p =>
        (p.1, { v with data := some p.2, cap := growCap v.cap need })
  else some (h, v)

/-- `vec_push`: grow when full, store at `len`, bump the length. -/
def push (h : Heap α) (v : RVec) (x : α) : Option (Heap α × RVec) :=
  match (if v.len ≥ v.cap then growTo h v (v.len + 1) else some (h, v)) with
  | none => none
  | some (h1, v1) =>
    match v1.data with
    | none => none
    | some d => (h1.store d v1.len x).map fun h2 => (h2, { v1 with len := v1.len + 1 })

/-- `vec_get`: the bounds check, then the load. -/
def get (h : Heap α) (v : RVec) (i : Nat) : Option (Option α) :=
  if i < v.len then
    match v.data with
    | none => none
    | some d => (h.load d i).map some
  else some none

/-- `vec_pop`: the load of the last cell, then the length down by one. -/
def pop (h : Heap α) (v : RVec) : Option (Option α × RVec) :=
  if v.len = 0 then some (none, v) else
    match v.data with
    | none => none
    | some d => (h.load d (v.len - 1)).map fun x => (some x, { v with len := v.len - 1 })

/-- `vec_set` / `= . data idx x` in bounds: the store over the old cell. -/
def set (h : Heap α) (v : RVec) (i : Nat) (x : α) : Option (Heap α) :=
  match v.data with
  | none => none
  | some d => h.store d i x

/-- `vec_free`: the buffer's block, when there is one. -/
def free (h : Heap α) (v : RVec) : Option (Heap α) :=
  match v.data with
  | none => some h
  | some d => h.free d

/-! ### Representation lemmas -/

theorem rep_none {h : Heap α} {v : RVec} {es : List α} (hr : Rep h v es) (hd : v.data = none) :
    v.cap = 0 := by
  unfold Rep at hr; rw [hd] at hr; exact hr.2.2

theorem rep_some {h : Heap α} {v : RVec} {es : List α} {d : Nat} (hr : Rep h v es)
    (hd : v.data = some d) :
    h.live d = true ∧ h.size d = v.cap ∧ ∀ i (hi : i < es.length), h.cell d i = some es[i] := by
  unfold Rep at hr; rw [hd] at hr; exact hr.2.2

/-! ### Growth -/

/-- What `growTo` leaves: the same list, room for `need`, and the buffer
    kept or moved to the heap's next fresh id, as A1's two push steps. -/
theorem growTo_ok {h : Heap α} {v : RVec} {es : List α} {need : Nat}
    (hw : h.WF) (hr : Rep h v es) :
    ∃ h1 v1, growTo h v need = some (h1, v1) ∧ Rep h1 v1 es ∧ h1.WF ∧ need ≤ v1.cap ∧
      v1.len = v.len ∧
      ((v1 = v ∧ h1 = h) ∨
       (v1.data = some h.nid ∧ h1.nid = h.nid + 1 ∧
        h1.live = (match v.data with
                   | none => upd h.live h.nid true
                   | some d => upd (upd h.live d false) h.nid true) ∧
        ∀ b, b < h.nid → v.data ≠ some b → h1.cell b = h.cell b ∧ h1.size b = h.size b)) := by
  have hl := hr.1
  have hlc := hr.2.1
  unfold growTo
  by_cases hc : v.cap < need
  · rw [ite_eq_left hc]
    have hg := growCap_ge v.cap need
    cases hd : v.data with
    | none =>
      have h0 := rep_none hr hd
      refine ⟨_, _, rfl, ⟨hl, ?_, ?_⟩, ?_, hg, rfl, Or.inr ⟨rfl, rfl, rfl, ?_⟩⟩
      · show v.len ≤ growCap v.cap need; omega
      · show (upd h.live h.nid true) h.nid = true ∧ (upd h.size h.nid (growCap v.cap need)) h.nid =
            growCap v.cap need ∧ ∀ i (hi : i < es.length), (upd h.cell h.nid (fun _ => none)) h.nid i = some es[i]
        refine ⟨by simp [upd], by simp [upd], fun i hi => ?_⟩
        exfalso; omega
      · intro b hb
        show (upd h.live h.nid true) b = false
        have hb' : h.nid + 1 ≤ b := hb
        simp only [upd]
        rw [ite_eq_right (by omega)]
        exact hw b (by omega)
      · intro b hb _
        show (upd h.cell h.nid (fun _ => none)) b = h.cell b ∧ (upd h.size h.nid (growCap v.cap need)) b = h.size b
        simp only [upd]
        rw [ite_eq_right (by omega), ite_eq_right (by omega)]
        exact ⟨rfl, rfl⟩
    | some d =>
      obtain ⟨hld, hsz, hcell⟩ := rep_some hr hd
      have hdn : d < h.nid := by
        rcases Nat.lt_or_ge d h.nid with h' | h'
        · exact h'
        · rw [hw d h'] at hld; exact absurd hld (by simp)
      simp only [Heap.realloc, ite_eq_left hld, Option.map_some]
      refine ⟨_, _, rfl, ⟨hl, ?_, ?_⟩, ?_, hg, rfl, Or.inr ⟨rfl, rfl, rfl, ?_⟩⟩
      · show v.len ≤ growCap v.cap need; omega
      · show (upd (upd h.live d false) h.nid true) h.nid = true ∧
            (upd h.size h.nid (growCap v.cap need)) h.nid = growCap v.cap need ∧
            ∀ i (hi : i < es.length), (upd h.cell h.nid (fun i => if i < h.size d ∧ i < growCap v.cap need then h.cell d i else none)) h.nid i = some es[i]
        refine ⟨by simp [upd], by simp [upd], fun i hi => ?_⟩
        have hin : i < h.size d ∧ i < growCap v.cap need := ⟨by omega, by omega⟩
        simp only [upd, ↓reduceIte, hin, and_self]
        exact hcell i hi
      · intro b hb
        show (upd (upd h.live d false) h.nid true) b = false
        simp at hb
        simp only [upd]
        rw [ite_eq_right (by omega), ite_eq_right (by omega)]; exact hw b (by omega)
      · intro b hb hne
        have hbd : b ≠ d := fun e => hne (by rw [e])
        show (upd h.cell h.nid _) b = h.cell b ∧ (upd h.size h.nid (growCap v.cap need)) b = h.size b
        simp only [upd]
        rw [ite_eq_right (by omega), ite_eq_right (by omega)]
        exact ⟨rfl, rfl⟩
  · rw [ite_eq_right hc]
    exact ⟨h, v, rfl, hr, hw, by omega, rfl, Or.inl ⟨rfl, rfl⟩⟩

/-! ### `vec_push` -/

/-- `vec_push` on a represented `Vec` succeeds and represents `es ++ [x]`.
    Its buffer is either the one it had (A1's `push`) or the heap's next
    fresh id, with the old block ended (A1's `pushRealloc`: the same
    `upd (upd alloc d false) nid true`). No other block changes. -/
theorem push_ok {h : Heap α} {v : RVec} {es : List α} (x : α) (hw : h.WF) (hr : Rep h v es) :
    ∃ h' v', push h v x = some (h', v') ∧ Rep h' v' (es ++ [x]) ∧ h'.WF ∧
      ((v'.data = v.data ∧ h'.live = h.live ∧ h'.nid = h.nid ∧ h'.size = h.size) ∨
       (v'.data = some h.nid ∧ h'.nid = h.nid + 1 ∧
        h'.live = (match v.data with
                   | none => upd h.live h.nid true
                   | some d => upd (upd h.live d false) h.nid true))) ∧
      ∀ b, b < h.nid → v.data ≠ some b → h'.cell b = h.cell b ∧ h'.size b = h.size b := by
  -- the growth step, or none
  have hg : ∃ h1 v1, (if v.len ≥ v.cap then growTo h v (v.len + 1) else some (h, v)) = some (h1, v1) ∧
      Rep h1 v1 es ∧ h1.WF ∧ v.len + 1 ≤ v1.cap ∧ v1.len = v.len ∧
      ((v1 = v ∧ h1 = h) ∨
       (v1.data = some h.nid ∧ h1.nid = h.nid + 1 ∧
        h1.live = (match v.data with
                   | none => upd h.live h.nid true
                   | some d => upd (upd h.live d false) h.nid true) ∧
        ∀ b, b < h.nid → v.data ≠ some b → h1.cell b = h.cell b ∧ h1.size b = h.size b)) := by
    by_cases hf : v.len ≥ v.cap
    · rw [ite_eq_left hf]; exact growTo_ok hw hr
    · rw [ite_eq_right hf]; exact ⟨h, v, rfl, hr, hw, by omega, rfl, Or.inl ⟨rfl, rfl⟩⟩
  obtain ⟨h1, v1, he, hr1, hw1, hroom, hlen, hbuf⟩ := hg
  -- after the growth there is a buffer: a `none` data pointer has cap 0
  cases hd1 : v1.data with
  | none => have := rep_none hr1 hd1; omega
  | some d =>
    obtain ⟨hld, hsz, hcell⟩ := rep_some hr1 hd1
    have hl1 : v1.len = es.length := hr1.1
    have hin : h1.live d = true ∧ v1.len < h1.size d := ⟨hld, by omega⟩
    unfold push
    rw [he]
    simp only [hd1, Heap.store, hin, and_self, ↓reduceIte, Option.map_some]
    refine ⟨_, _, rfl, ⟨?_, ?_, ?_⟩, ?_, ?_, ?_⟩
    · show v1.len + 1 = (es ++ [x]).length; simp; omega
    · show v1.len + 1 ≤ v1.cap; omega
    · show h1.live d = true ∧ h1.size d = v1.cap ∧
        ∀ i (hi : i < (es ++ [x]).length), (upd h1.cell d (upd (h1.cell d) v1.len (some x))) d i = some (es ++ [x])[i]
      refine ⟨hld, hsz, fun i hi => ?_⟩
      simp only [upd, ↓reduceIte]
      by_cases hil : i = v1.len
      · subst hil; simp only [↓reduceIte]
        rw [List.getElem_append_right (by omega)]; simp [hl1]
      · rw [ite_eq_right hil]
        have hi' : i < es.length := by simp at hi; omega
        rw [List.getElem_append_left hi']; exact hcell i hi'
    · exact hw1
    · rcases hbuf with ⟨rfl, rfl⟩ | ⟨hd, hn, hlv, _⟩
      · exact Or.inl ⟨hd1.symm ▸ rfl, rfl, rfl, rfl⟩
      · exact Or.inr ⟨by rw [← hd, hd1], hn, hlv⟩
    · intro b hb hne
      have hcs : h1.cell b = h.cell b ∧ h1.size b = h.size b := by
        rcases hbuf with ⟨rfl, rfl⟩ | ⟨_, _, _, hfr⟩
        · exact ⟨rfl, rfl⟩
        · exact hfr b hb hne
      have hbd : b ≠ d := by
        rcases hbuf with ⟨rfl, rfl⟩ | ⟨hd, _, _, _⟩
        · intro e; exact hne (by rw [hd1, e])
        · intro e; rw [hd1] at hd; injection hd with hd; omega
      show (upd h1.cell d _) b = h.cell b ∧ h1.size b = h.size b
      simp only [upd, ite_eq_right hbd]; exact hcs

/-! ### `vec_get`, `vec_set`, `vec_pop` -/

/-- `vec_get` reads `es[i]` in bounds and `none` past the end, reading no
    cell there. -/
theorem get_ok {h : Heap α} {v : RVec} {es : List α} (hr : Rep h v es) (i : Nat) :
    get h v i = some es[i]? := by
  unfold get
  by_cases hi : i < v.len
  · rw [ite_eq_left hi]
    have hl : v.len = es.length := hr.1
    cases hd : v.data with
    | none => have := rep_none hr hd; have := hr.2.1; omega
    | some d =>
      obtain ⟨hld, hsz, hcell⟩ := rep_some hr hd
      have hin : h.live d = true ∧ i < h.size d := ⟨hld, by have := hr.2.1; omega⟩
      simp only [Heap.load, hin, and_self, ↓reduceIte, hcell i (by omega), Option.map_some]
      rw [List.getElem?_eq_getElem (by omega)]
  · rw [ite_eq_right hi]
    have hl : v.len = es.length := hr.1
    rw [List.getElem?_eq_none (by omega)]

/-- An in-bounds store (`vec_set`, `= . data idx x`) succeeds and represents
    the list with element `i` replaced. -/
theorem set_ok {h : Heap α} {v : RVec} {es : List α} {i : Nat} (x : α) (hr : Rep h v es)
    (hi : i < es.length) :
    ∃ h', set h v i x = some h' ∧ Rep h' v (es.set i x) ∧ h'.live = h.live ∧ h'.nid = h.nid ∧
      h'.size = h.size ∧ ∀ b, v.data ≠ some b → h'.cell b = h.cell b := by
  have hl : v.len = es.length := hr.1
  cases hd : v.data with
  | none => have := rep_none hr hd; have := hr.2.1; omega
  | some d =>
    obtain ⟨hld, hsz, hcell⟩ := rep_some hr hd
    have hin : h.live d = true ∧ i < h.size d := ⟨hld, by have := hr.2.1; omega⟩
    unfold set
    simp only [hd, Heap.store, hin, and_self, ↓reduceIte]
    refine ⟨_, rfl, ⟨by simp [hl], hr.2.1, ?_⟩, rfl, rfl, rfl, ?_⟩
    · rw [hd]
      refine ⟨hld, hsz, fun j hj => ?_⟩
      simp only [upd, ↓reduceIte]
      rw [List.getElem_set]
      by_cases hij : j = i
      · subst hij; simp
      · rw [ite_eq_right hij, ite_eq_right (fun e => hij e.symm)]; exact hcell j (by simpa using hj)
    · intro b hb
      have hbd : b ≠ d := fun e => hb (by rw [e])
      show (upd h.cell d _) b = h.cell b
      simp only [upd, ite_eq_right hbd]

/-- `vec_pop` of a non-empty `Vec` hands back its last element and
    represents the rest, on the same heap. Of an empty one, `none`, reading
    nothing. -/
theorem pop_ok {h : Heap α} {v : RVec} {es : List α} (hr : Rep h v es) :
    (es = [] → pop h v = some (none, v)) ∧
    ∀ es' x, es = es' ++ [x] → ∃ v', pop h v = some (some x, v') ∧ Rep h v' es' ∧ v'.data = v.data := by
  have hl : v.len = es.length := hr.1
  constructor
  · intro he; subst he; unfold pop; simp at hl; simp [hl]
  · intro es' x he
    subst he
    have hne : v.len ≠ 0 := by simp at hl; omega
    cases hd : v.data with
    | none => have := rep_none hr hd; have := hr.2.1; omega
    | some d =>
      obtain ⟨hld, hsz, hcell⟩ := rep_some hr hd
      have hin : h.live d = true ∧ v.len - 1 < h.size d := ⟨hld, by have := hr.2.1; omega⟩
      have hlast : h.cell d (v.len - 1) = some x := by
        have := hcell (v.len - 1) (by simp at hl ⊢; omega)
        rw [this]; simp at hl
        rw [List.getElem_append_right (by omega)]; simp
      unfold pop
      simp only [hne, ↓reduceIte, hd, Heap.load, hin, and_self, hlast, Option.map_some]
      refine ⟨_, rfl, ⟨?_, by have := hr.2.1; simp; omega, ?_⟩, rfl⟩
      · simp at hl ⊢; omega
      · show h.live d = true ∧ h.size d = v.cap ∧ ∀ i (hi : i < es'.length), h.cell d i = some es'[i]
        refine ⟨hld, hsz, fun i hi => ?_⟩
        rw [hcell i (by simp; omega), List.getElem_append_left hi]

/-! ### `vec_free` -/

/-- `vec_free` of a represented `Vec` succeeds and ends its block (and only
    it). Freeing the same buffer again is `none`, a double free the heap
    refuses. -/
theorem free_ok {h : Heap α} {v : RVec} {es : List α} (hr : Rep h v es) :
    ∃ h', free h v = some h' ∧ h'.cell = h.cell ∧ h'.size = h.size ∧ h'.nid = h.nid ∧
      (∀ b, v.data ≠ some b → h'.live b = h.live b) ∧ (∀ d, v.data = some d → free h' v = none) := by
  cases hd : v.data with
  | none => exact ⟨h, by simp [free, hd], rfl, rfl, rfl, fun _ _ => rfl, fun _ e => by cases e⟩
  | some d =>
    obtain ⟨hld, _, _⟩ := rep_some hr hd
    refine ⟨{ h with live := upd h.live d false }, by simp [free, hd, Heap.free, hld], rfl, rfl, rfl, ?_, ?_⟩
    · intro b hb
      have hbd : b ≠ d := fun e => hb (by rw [e])
      show (upd h.live d false) b = h.live b
      simp only [upd, ite_eq_right hbd]
    · intro d' hd'
      simp [free, hd, Heap.free, upd]

/-! ### The link to A1

A1 tracks each allocation by an id and one liveness bit (`Mem.alloc`,
`Mem.nid`). A1's `Vec` value `.node t c d es` names its buffer `d`, and A1
lets `vec_push` take either of two steps: `push` keeps `d`, `pushRealloc` ends
`d` and takes `nid`. `Agree` says the heap's blocks are A1's allocations.
`push_refines` says the raw push, on a buffer A1 names, makes exactly one of
A1's two steps: the same buffer and the same allocation map, or the next
fresh id with A1's own update of the map. -/

/-- The heap's liveness and fresh-id counter are A1's. -/
def Agree (m : A1.Mem) (h : Heap α) : Prop := m.alloc = h.live ∧ m.nid = h.nid

theorem push_refines {m : A1.Mem} {h : Heap α} {v : RVec} {es : List α} {d : Nat} (x : α)
    (ha : Agree m h) (hw : h.WF) (hr : Rep h v es) (hd : v.data = some d) :
    ∃ h' v', push h v x = some (h', v') ∧ Rep h' v' (es ++ [x]) ∧ h'.WF ∧
      ((v'.data = some d ∧ Agree m h') ∨
       (v'.data = some m.nid ∧
        Agree { m with alloc := upd (upd m.alloc d false) m.nid true, nid := m.nid + 1 } h')) := by
  obtain ⟨h', v', he, hr', hw', hbuf, _⟩ := push_ok x hw hr
  refine ⟨h', v', he, hr', hw', ?_⟩
  obtain ⟨hal, hn⟩ := ha
  rcases hbuf with ⟨hd', hl, hn', _⟩ | ⟨hd', hn', hl⟩
  · exact Or.inl ⟨hd' ▸ hd, ⟨hal.trans hl.symm, hn.trans hn'.symm⟩⟩
  · rw [hd] at hl
    refine Or.inr ⟨by rw [hd', hn], ?_, ?_⟩
    · show upd (upd m.alloc d false) m.nid true = h'.live
      rw [hl, hal, hn]
    · show m.nid + 1 = h'.nid
      rw [hn', hn]

end B
