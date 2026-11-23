import A1.Semantics

/-!
# B1: the raw core of `Vec` meets A1's `Vec` (AGORA-970)

Phase B proves that the standard library's `unsafe` base meets the semantic
types the rules give it. This file covers the first piece, the owned buffer
of `stdlib/core/vec.nu`. It models the buffer at the level that code runs on:
a heap of blocks, a control triple `(data, len, cap)`, and the code of
`vec_push`, `__vec_grow_to`, `__vec_place`, `alloc_grow_cap`, `vec_get`,
`vec_set` (by `.data idx`), `vec_pop`, `vec_insert` and `vec_remove` (their
shift loops), `vec_truncate` (for elements whose drop runs no code of the
program's: the elements it drops are exactly the ones it no longer holds),
`vec_swap`, `vec_reserve`, `vec_append` (`__vec_extend_move`) and
`vec_free`. It proves that each
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

Borrowed views (`vec_borrow_raw`, `cap < 0`) are covered for reads and for
the push that detaches them (`vpush_ok`: the viewed block is never written
or freed). The packed-string layout's growth is the same detach (`packedPush_ok`).
What B1 leaves out, for the next steps: the runtime's `nurl_vec_drop` (C code; it frees a view's handle only), element destructors (cells
here are values that are moved by bit copy, as `mem_take` makes them),
byte sizes and their overflow (`alloc_size`).
`__vec_release_from` (the truncation path for elements whose drop runs
program code, Agora #709) is covered: `releaseFrom_ok`.
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

/-! ### `vec_insert` and `vec_remove`: the shifts -/

/-- `vec_insert`'s loop `~ > i idx { = . data i . data - i 1  = i - i 1 }`,
    from `i`: each cell above `idx` takes the one below it. -/
def shiftR (h : Heap α) (d idx : Nat) : Nat → Option (Heap α)
  | 0 => some h
  | k + 1 =>
    if idx < k + 1 then
      match h.load d k with
      | none => none
      | some y =>
        match h.store d (k + 1) y with
        | none => none
        | some h1 => shiftR h1 d idx k
    else some h

theorem shiftR_ok {d idx : Nat} : ∀ (i : Nat) (h : Heap α), idx ≤ i → h.live d = true → i < h.size d →
    (∀ k, idx ≤ k → k < i → (h.cell d k).isSome) →
    ∃ h', shiftR h d idx i = some h' ∧ h'.live = h.live ∧ h'.size = h.size ∧ h'.nid = h.nid ∧
      (∀ b, b ≠ d → h'.cell b = h.cell b) ∧
      ∀ j, h'.cell d j = if idx < j ∧ j ≤ i then h.cell d (j - 1) else h.cell d j := by
  intro i
  induction i with
  | zero =>
    intro h hi _ _ _
    refine ⟨h, rfl, rfl, rfl, rfl, fun _ _ => rfl, fun j => ?_⟩
    rw [ite_eq_right (by omega)]
  | succ k ih =>
    intro h hi hl hs hc
    by_cases hlt : idx < k + 1
    · obtain ⟨y, hy⟩ := Option.isSome_iff_exists.mp (hc k (by omega) (by omega))
      have hld : h.load d k = some y := by
        simp only [Heap.load, hl, true_and]; rw [ite_eq_left (by omega)]; exact hy
      have hin : h.live d = true ∧ k + 1 < h.size d := ⟨hl, hs⟩
      have hst : h.store d (k + 1) y =
          some { h with cell := upd h.cell d (upd (h.cell d) (k + 1) (some y)) } := by
        simp only [Heap.store, hin, and_self, ↓reduceIte]
      obtain ⟨h', he, hlv, hsz, hn, hoth, hcell⟩ :=
        ih { h with cell := upd h.cell d (upd (h.cell d) (k + 1) (some y)) } (by omega) hl (by
          show k < h.size d; omega) (by
          intro k' h1 h2
          show ((upd h.cell d (upd (h.cell d) (k + 1) (some y))) d k').isSome
          simp only [upd, ↓reduceIte]; rw [ite_eq_right (by omega)]; exact hc k' h1 (by omega))
      refine ⟨h', ?_, hlv, hsz, hn, ?_, ?_⟩
      · simp only [shiftR, ite_eq_left hlt, hld, hst]; exact he
      · intro b hb; rw [hoth b hb]; show (upd h.cell d _) b = h.cell b; simp only [upd, ite_eq_right hb]
      · intro j
        rw [hcell j]
        simp only [upd, ↓reduceIte]
        by_cases hj : idx < j ∧ j ≤ k
        · rw [ite_eq_left hj, ite_eq_right (by omega), ite_eq_left (by omega)]
        · rw [ite_eq_right hj]
          by_cases hjk : j = k + 1
          · subst hjk; rw [ite_eq_left rfl, ite_eq_left (by omega)]; simp [hy]
          · rw [ite_eq_right hjk, ite_eq_right (by omega)]
    · refine ⟨h, by simp only [shiftR, ite_eq_right hlt], rfl, rfl, rfl, fun _ _ => rfl, fun j => ?_⟩
      rw [ite_eq_right (by omega)]

/-- `vec_insert` at `idx ≤ len`: grow when full, shift `[idx, len)` up by
    one from the tail, store at `idx`. Out of range: `false`, nothing done. -/
def insert (h : Heap α) (v : RVec) (idx : Nat) (x : α) : Option (Bool × Heap α × RVec) :=
  if idx > v.len then some (false, h, v) else
  match (if v.cap < v.len + 1 then growTo h v (v.len + 1) else some (h, v)) with
  | none => none
  | some (h1, v1) =>
    match v1.data with
    | none => none
    | some d =>
      match shiftR h1 d idx v1.len with
      | none => none
      | some h2 => (h2.store d idx x).map fun h3 => (true, h3, { v1 with len := v1.len + 1 })

theorem insert_ok {h : Heap α} {v : RVec} {es : List α} {idx : Nat} (x : α) (hw : h.WF)
    (hr : Rep h v es) (hi : idx ≤ es.length) :
    ∃ h' v', insert h v idx x = some (true, h', v') ∧
      Rep h' v' (es.take idx ++ x :: es.drop idx) ∧ h'.WF := by
  have hl : v.len = es.length := hr.1
  have hg : ∃ h1 v1, (if v.cap < v.len + 1 then growTo h v (v.len + 1) else some (h, v)) = some (h1, v1) ∧
      Rep h1 v1 es ∧ h1.WF ∧ v.len + 1 ≤ v1.cap ∧ v1.len = v.len := by
    by_cases hf : v.cap < v.len + 1
    · rw [ite_eq_left hf]
      obtain ⟨h1, v1, he, hr1, hw1, hroom, hlen, _⟩ := growTo_ok (need := v.len + 1) hw hr
      exact ⟨h1, v1, he, hr1, hw1, hroom, hlen⟩
    · rw [ite_eq_right hf]; exact ⟨h, v, rfl, hr, hw, by omega, rfl⟩
  obtain ⟨h1, v1, he, hr1, hw1, hroom, hlen⟩ := hg
  have hl1 : v1.len = es.length := hr1.1
  cases hd1 : v1.data with
  | none => have := rep_none hr1 hd1; omega
  | some d =>
    obtain ⟨hld, hsz, hcell⟩ := rep_some hr1 hd1
    obtain ⟨h2, hs2, hlv2, hsz2, hn2, hoth2, hcell2⟩ := shiftR_ok (idx := idx) (d := d) v1.len h1
      (by omega) hld (by omega) (fun k _ hk => by rw [hcell k (by omega)]; rfl)
    have hin : h2.live d = true ∧ idx < h2.size d := ⟨by rw [hlv2]; exact hld, by rw [hsz2]; omega⟩
    refine ⟨{ h2 with cell := upd h2.cell d (upd (h2.cell d) idx (some x)) },
      { v1 with len := v1.len + 1 }, ?_, ⟨?_, ?_, ?_⟩, ?_⟩
    · unfold insert
      rw [ite_eq_right (by omega), he]
      simp only [hd1, hs2, Heap.store, hin, and_self, ↓reduceIte, Option.map_some]
    · show v1.len + 1 = (es.take idx ++ x :: es.drop idx).length
      simp; omega
    · show v1.len + 1 ≤ v1.cap; omega
    · simp only [hd1]
      show h2.live d = true ∧ h2.size d = v1.cap ∧ ∀ j (hj : j < (es.take idx ++ x :: es.drop idx).length),
        (upd h2.cell d (upd (h2.cell d) idx (some x))) d j = some (es.take idx ++ x :: es.drop idx)[j]
      refine ⟨hin.1, by rw [hsz2]; exact hsz, fun j hj => ?_⟩
      have hlen' : (es.take idx).length = idx := by simp; omega
      simp only [upd, ↓reduceIte]
      rw [hcell2 j]
      by_cases hji : j = idx
      · subst hji; rw [ite_eq_left rfl, List.getElem_append_right (by omega)]; simp [hlen']
      · rw [ite_eq_right hji]
        simp at hj
        by_cases hlt : j < idx
        · rw [ite_eq_right (by omega), hcell j (by omega), List.getElem_append_left (by omega)]
          simp
        · rw [ite_eq_left (by omega), hcell (j - 1) (by omega), List.getElem_append_right (by omega)]
          have hjp : j - (es.take idx).length = (j - 1 - idx) + 1 := by rw [hlen']; omega
          simp only [hjp, List.getElem_cons_succ, List.getElem_drop]
          have hix : idx + (j - 1 - idx) = j - 1 := by omega
          simp only [hix]
    · intro b hb
      show h2.live b = false
      rw [hlv2]; exact hw1 b (by rw [← hn2]; exact hb)

/-- `vec_remove`'s loop `~ < i - len 1 { = . data i . data + i 1  = i + i 1 }`,
    `n` rounds from `i`: each cell takes the one above it. -/
def shiftL (h : Heap α) (d : Nat) : Nat → Nat → Option (Heap α)
  | _, 0 => some h
  | i, n + 1 =>
    match h.load d (i + 1) with
    | none => none
    | some y =>
      match h.store d i y with
      | none => none
      | some h1 => shiftL h1 d (i + 1) n

theorem shiftL_ok {d : Nat} : ∀ (n i : Nat) (h : Heap α), h.live d = true → i + n < h.size d →
    (∀ k, i < k → k ≤ i + n → (h.cell d k).isSome) →
    ∃ h', shiftL h d i n = some h' ∧ h'.live = h.live ∧ h'.size = h.size ∧ h'.nid = h.nid ∧
      (∀ b, b ≠ d → h'.cell b = h.cell b) ∧
      ∀ j, h'.cell d j = if i ≤ j ∧ j < i + n then h.cell d (j + 1) else h.cell d j := by
  intro n
  induction n with
  | zero =>
    intro i h _ _ _
    refine ⟨h, rfl, rfl, rfl, rfl, fun _ _ => rfl, fun j => ?_⟩
    rw [ite_eq_right (by omega)]
  | succ n ih =>
    intro i h hl hs hc
    obtain ⟨y, hy⟩ := Option.isSome_iff_exists.mp (hc (i + 1) (by omega) (by omega))
    have hld : h.load d (i + 1) = some y := by
      simp only [Heap.load, hl, true_and]; rw [ite_eq_left (by omega)]; exact hy
    have hin : h.live d = true ∧ i < h.size d := ⟨hl, by omega⟩
    have hst : h.store d i y = some { h with cell := upd h.cell d (upd (h.cell d) i (some y)) } := by
      simp only [Heap.store, hin, and_self, ↓reduceIte]
    obtain ⟨h', he, hlv, hsz, hn, hoth, hcell⟩ :=
      ih (i + 1) { h with cell := upd h.cell d (upd (h.cell d) i (some y)) } hl (by
        show i + 1 + n < h.size d; omega) (by
        intro k h1 h2
        show ((upd h.cell d (upd (h.cell d) i (some y))) d k).isSome
        simp only [upd, ↓reduceIte]; rw [ite_eq_right (by omega)]; exact hc k (by omega) (by omega))
    refine ⟨h', ?_, hlv, hsz, hn, ?_, ?_⟩
    · simp only [shiftL, hld, hst]; exact he
    · intro b hb; rw [hoth b hb]; show (upd h.cell d _) b = h.cell b; simp only [upd, ite_eq_right hb]
    · intro j
      rw [hcell j]
      simp only [upd, ↓reduceIte]
      by_cases hj : i + 1 ≤ j ∧ j < i + 1 + n
      · rw [ite_eq_left hj, ite_eq_right (by omega), ite_eq_left (by omega)]
      · rw [ite_eq_right hj]
        by_cases hji : j = i
        · subst hji; rw [ite_eq_left rfl, ite_eq_left (by omega)]; simp [hy]
        · rw [ite_eq_right hji, ite_eq_right (by omega)]

/-- `vec_remove` at `idx < len`: load the element (it leaves the
    container), shift `(idx, len)` down by one, length down by one. Out of
    range: `none` handed back, nothing done. -/
def remove (h : Heap α) (v : RVec) (idx : Nat) : Option (Option α × Heap α × RVec) :=
  if idx ≥ v.len then some (none, h, v) else
  match v.data with
  | none => none
  | some d =>
    match h.load d idx with
    | none => none
    | some x =>
      (shiftL h d idx (v.len - 1 - idx)).map fun h2 => (some x, h2, { v with len := v.len - 1 })

theorem remove_ok {h : Heap α} {v : RVec} {es : List α} {idx : Nat} (hw : h.WF)
    (hr : Rep h v es) (hi : idx < es.length) :
    ∃ h' v', remove h v idx = some (some es[idx], h', v') ∧
      Rep h' v' (es.take idx ++ es.drop (idx + 1)) ∧ h'.WF ∧ v'.data = v.data := by
  have hl : v.len = es.length := hr.1
  have hlc := hr.2.1
  cases hd : v.data with
  | none => have := rep_none hr hd; omega
  | some d =>
    obtain ⟨hld, hsz, hcell⟩ := rep_some hr hd
    have hload : h.load d idx = some es[idx] := by
      simp only [Heap.load, hld, true_and]; rw [ite_eq_left (by omega)]; exact hcell idx hi
    obtain ⟨h2, hs2, hlv2, hsz2, hn2, _, hcell2⟩ := shiftL_ok (d := d) (v.len - 1 - idx) idx h
      hld (by omega) (fun k _ hk => by rw [hcell k (by omega)]; rfl)
    refine ⟨h2, { v with len := v.len - 1 }, ?_, ⟨?_, ?_, ?_⟩, ?_, hd⟩
    · unfold remove
      rw [ite_eq_right (by omega)]
      simp only [hd, hload, hs2, Option.map_some]
    · show v.len - 1 = (es.take idx ++ es.drop (idx + 1)).length
      simp; omega
    · show v.len - 1 ≤ v.cap; omega
    · simp only [hd]
      show h2.live d = true ∧ h2.size d = v.cap ∧ ∀ j (hj : j < (es.take idx ++ es.drop (idx + 1)).length),
        h2.cell d j = some (es.take idx ++ es.drop (idx + 1))[j]
      have hlen' : (es.take idx).length = idx := by simp; omega
      refine ⟨by rw [hlv2]; exact hld, by rw [hsz2]; exact hsz, fun j hj => ?_⟩
      rw [hcell2 j]
      simp at hj
      by_cases hlt : j < idx
      · rw [ite_eq_right (by omega), hcell j (by omega), List.getElem_append_left (by omega)]
        simp
      · rw [ite_eq_left (by omega), hcell (j + 1) (by omega), List.getElem_append_right (by omega)]
        simp only [List.getElem_drop, hlen']
        have hix : idx + 1 + (j - idx) = j + 1 := by omega
        simp only [hix]
    · intro b hb
      show h2.live b = false
      rw [hlv2]; exact hw b (by rw [← hn2]; exact hb)

/-! ### `vec_truncate`, `vec_swap`, `vec_reserve` -/

/-- `mem_drop_range data n len`'s reads: the cells `[n, n + k)`, in index
    order, each one loaded once to be dropped. -/
def loadRange (h : Heap α) (d : Nat) : Nat → Nat → Option (List α)
  | _, 0 => some []
  | n, k + 1 =>
    match h.load d n with
    | none => none
    | some y => (loadRange h d (n + 1) k).map (y :: ·)

theorem loadRange_ok {h : Heap α} {d : Nat} {es : List α} (hl : h.live d = true)
    (hcell : ∀ i (hi : i < es.length), h.cell d i = some es[i]) (hsz : es.length ≤ h.size d) :
    ∀ k n, n + k = es.length → loadRange h d n k = some (es.drop n) := by
  intro k
  induction k with
  | zero => intro n hn; simp [loadRange]; omega
  | succ k ih =>
    intro n hn
    have hns : n < h.size d := by omega
    have hld : h.load d n = some es[n] := by
      simp only [Heap.load, hl, true_and]; rw [ite_eq_left hns]; exact hcell n (by omega)
    have heq : es.drop n = es[n] :: es.drop (n + 1) := List.drop_eq_getElem_cons (by omega)
    rw [heq]
    simp only [loadRange, hld, ih (n + 1) (by omega), Option.map_some]

/-- `vec_truncate` to `n ≤ len` (for an element type whose drop runs no
    code of the program's): the length first, then the elements past `n`
    read out to be dropped. Out of range: `false`, nothing done. -/
def truncate (h : Heap α) (v : RVec) (n : Nat) : Option (Bool × List α × RVec) :=
  if n > v.len then some (false, [], v) else
  match v.data with
  | none => if v.len = 0 then some (true, [], { v with len := n }) else none
  | some d => (loadRange h d n (v.len - n)).map fun ds => (true, ds, { v with len := n })

/-- `vec_truncate` keeps the first `n` elements and hands every other one
    to drop exactly once: the two lists make up `es` (nothing leaks, and
    nothing is dropped twice). The heap is not written. -/
theorem truncate_ok {h : Heap α} {v : RVec} {es : List α} {n : Nat} (hr : Rep h v es)
    (hn : n ≤ es.length) :
    ∃ v', truncate h v n = some (true, es.drop n, v') ∧ Rep h v' (es.take n) ∧ v'.data = v.data ∧
      es.take n ++ es.drop n = es := by
  have hl : v.len = es.length := hr.1
  have hlc := hr.2.1
  refine ⟨{ v with len := n }, ?_, ⟨by simp; omega, by show n ≤ v.cap; omega, ?_⟩, rfl, List.take_append_drop n es⟩
  · unfold truncate
    rw [ite_eq_right (by omega)]
    cases hd : v.data with
    | none =>
      have h0 := rep_none hr hd
      have : es = [] := List.eq_nil_of_length_eq_zero (by omega)
      subst this
      simp at hn; subst hn
      simp [hl]
    | some d =>
      obtain ⟨hld, hsz, hcell⟩ := rep_some hr hd
      simp only [loadRange_ok hld hcell (by omega) (v.len - n) n (by omega), Option.map_some]
  · dsimp only
    cases hd : v.data with
    | none => exact rep_none hr hd
    | some d =>
      obtain ⟨hld, hsz, hcell⟩ := rep_some hr hd
      refine ⟨hld, hsz, fun i hi => ?_⟩
      simp at hi
      rw [hcell i (by omega)]; simp

/-- `vec_swap` of two indices in bounds: each element goes back into the
    other's cell as it is (no copy, nothing taken over). -/
def swap (h : Heap α) (v : RVec) (i j : Nat) : Option (Bool × Heap α) :=
  if i ≥ v.len ∨ j ≥ v.len then some (false, h) else
  if i = j then some (true, h) else
  match v.data with
  | none => none
  | some d =>
    match h.load d i, h.load d j with
    | some a, some b =>
      match h.store d i b with
      | none => none
      | some h1 => (h1.store d j a).map fun h2 => (true, h2)
    | _, _ => none

theorem swap_ok {h : Heap α} {v : RVec} {es : List α} {i j : Nat} (hr : Rep h v es)
    (hi : i < es.length) (hj : j < es.length) :
    ∃ h', swap h v i j = some (true, h') ∧ Rep h' v ((es.set i es[j]).set j es[i]) ∧
      h'.live = h.live ∧ h'.size = h.size ∧ h'.nid = h.nid ∧
      ∀ b, v.data ≠ some b → h'.cell b = h.cell b := by
  have hl : v.len = es.length := hr.1
  have hlc := hr.2.1
  by_cases hij : i = j
  · subst hij
    refine ⟨h, ?_, ?_, rfl, rfl, rfl, fun _ _ => rfl⟩
    · unfold swap; rw [ite_eq_right (by omega), ite_eq_left rfl]
    · simp only [List.set_getElem_self]; exact hr
  · cases hd : v.data with
    | none => have := rep_none hr hd; omega
    | some d =>
      obtain ⟨hld, hsz, hcell⟩ := rep_some hr hd
      have hli : h.load d i = some es[i] := by
        simp only [Heap.load, hld, true_and]; rw [ite_eq_left (by omega)]; exact hcell i hi
      have hlj : h.load d j = some es[j] := by
        simp only [Heap.load, hld, true_and]; rw [ite_eq_left (by omega)]; exact hcell j hj
      have hin : h.live d = true ∧ i < h.size d := ⟨hld, by omega⟩
      let h1 : Heap α := { h with cell := upd h.cell d (upd (h.cell d) i (some es[j])) }
      have hs1 : h.store d i es[j] = some h1 := by simp only [Heap.store, hin, and_self, ↓reduceIte]; rfl
      have hin1 : h1.live d = true ∧ j < h1.size d := ⟨hld, by show j < h.size d; omega⟩
      refine ⟨{ h1 with cell := upd h1.cell d (upd (h1.cell d) j (some es[i])) }, ?_, ⟨by simp; omega, hlc, ?_⟩, rfl, rfl, rfl, ?_⟩
      · unfold swap
        rw [ite_eq_right (by omega), ite_eq_right hij]
        simp only [hd, hli, hlj]
        rw [hs1]
        simp only [Heap.store, hin1, and_self, ↓reduceIte, Option.map_some]
      · simp only [hd]
        refine ⟨hld, hsz, fun k hk => ?_⟩
        simp only [h1, upd, ↓reduceIte]
        simp at hk
        rw [List.getElem_set, List.getElem_set]
        by_cases hkj : k = j
        · subst hkj; simp
        · have hjk : j ≠ k := fun e => hkj e.symm
          simp only [hkj, hjk, ↓reduceIte]
          by_cases hki : k = i
          · subst hki; simp
          · have hik : i ≠ k := fun e => hki e.symm
            simp only [hki, hik, ↓reduceIte]; exact hcell k hk
      · intro b hb
        have hbd : b ≠ d := fun e => hb (by rw [e])
        simp only [h1, upd, ite_eq_right hbd]

/-- `vec_reserve n` (`n > 0`): grow to `len + n` when the room left is
    less; the list is kept. (`len + n` is a `Nat` here: the runtime's
    checked count, `alloc_count_add`, panics when it overflows `i64`, before
    the Vec changes, B8; `reserve_ok` covers counts that fit.) -/
def reserve (h : Heap α) (v : RVec) (n : Nat) : Option (Heap α × RVec) :=
  if n > 0 ∧ v.cap - v.len < n then growTo h v (v.len + n) else some (h, v)

theorem reserve_ok {h : Heap α} {v : RVec} {es : List α} (n : Nat) (hw : h.WF) (hr : Rep h v es) :
    ∃ h' v', reserve h v n = some (h', v') ∧ Rep h' v' es ∧ h'.WF ∧ v.len + n ≤ v'.cap ∧
      v'.len = v.len := by
  have hlc := hr.2.1
  unfold reserve
  by_cases hc : n > 0 ∧ v.cap - v.len < n
  · rw [ite_eq_left hc]
    obtain ⟨h1, v1, he, hr1, hw1, hroom, hlen, _⟩ := growTo_ok (need := v.len + n) hw hr
    exact ⟨h1, v1, he, hr1, hw1, hroom, hlen⟩
  · rw [ite_eq_right hc]
    exact ⟨h, v, rfl, hr, hw, by omega, rfl⟩

/-! ### Borrowed views (`vec_borrow_raw`, `cap < 0`)

A view points into storage another owner holds: block `blk`, from cell
`off`. vec.nu keeps such a `Vec` at `cap = -1`, and "the buffer is not ours
to grow, shrink or free". The theorems below say that this holds. A read
sees the owner's cells. A push detaches: it copies the live cells into a
fresh block and writes only there, so the owner's block keeps its cells and
stays live. `vec_free` of a view releases nothing of the owner's. -/

/-- A borrowed view: `len` cells of block `blk` from cell `off`. -/
structure VView where
  blk : Nat
  off : Nat
  len : Nat

/-- The view `w` on `h` sees the list `es`. -/
def VRep (h : Heap α) (w : VView) (es : List α) : Prop :=
  w.len = es.length ∧ h.live w.blk = true ∧ w.off + w.len ≤ h.size w.blk ∧
  ∀ i (hi : i < es.length), h.cell w.blk (w.off + i) = some es[i]

/-- `nurl_memcpy` of `n` cells, from block `b` at `o` to block `d` at 0. -/
def memcpy (h : Heap α) (b o d : Nat) : Nat → Option (Heap α)
  | 0 => some h
  | n + 1 =>
    match memcpy h b o d n with
    | none => none
    | some h1 =>
      match h1.load b (o + n) with
      | none => none
      | some y => h1.store d n y

theorem memcpy_ok {h : Heap α} {b o d : Nat} (hbd : b ≠ d) (hlb : h.live b = true)
    (hld : h.live d = true) : ∀ n, o + n ≤ h.size b → n ≤ h.size d →
    (∀ k, k < n → (h.cell b (o + k)).isSome) →
    ∃ h', memcpy h b o d n = some h' ∧ h'.live = h.live ∧ h'.size = h.size ∧ h'.nid = h.nid ∧
      (∀ c, c ≠ d → h'.cell c = h.cell c) ∧
      ∀ j, h'.cell d j = if j < n then h.cell b (o + j) else h.cell d j := by
  intro n
  induction n with
  | zero =>
    intro _ _ _
    exact ⟨h, rfl, rfl, rfl, rfl, fun _ _ => rfl, fun j => by rw [ite_eq_right (by omega)]⟩
  | succ n ih =>
    intro hb hd hc
    obtain ⟨h1, he, hlv, hsz, hn, hoth, hcell⟩ := ih (by omega) (by omega) (fun k hk => hc k (by omega))
    obtain ⟨y, hy⟩ := Option.isSome_iff_exists.mp (hc n (by omega))
    have hy1 : h1.cell b (o + n) = some y := by rw [hoth b hbd]; exact hy
    have hload : h1.load b (o + n) = some y := by
      simp only [Heap.load, hlv, hsz, hlb, true_and]; rw [ite_eq_left (by omega)]; exact hy1
    have hin : h1.live d = true ∧ n < h1.size d := ⟨by rw [hlv]; exact hld, by rw [hsz]; omega⟩
    refine ⟨{ h1 with cell := upd h1.cell d (upd (h1.cell d) n (some y)) }, ?_, hlv, hsz, hn, ?_, ?_⟩
    · simp only [memcpy, he, hload, Heap.store, hin, and_self, ↓reduceIte]
    · intro c hc'
      show (upd h1.cell d _) c = h.cell c
      simp only [upd, ite_eq_right hc']; exact hoth c hc'
    · intro j
      show (upd h1.cell d (upd (h1.cell d) n (some y))) d j = _
      simp only [upd, ↓reduceIte]
      by_cases hjn : j = n
      · subst hjn; rw [ite_eq_left rfl, ite_eq_left (by omega)]; exact hy.symm
      · rw [ite_eq_right hjn, hcell j]
        by_cases hj : j < n
        · rw [ite_eq_left hj, ite_eq_left (by omega)]
        · rw [ite_eq_right hj, ite_eq_right (by omega)]

/-- `vec_get` on a view. -/
def vget (h : Heap α) (w : VView) (i : Nat) : Option (Option α) :=
  if i < w.len then (h.load w.blk (w.off + i)).map some else some none

theorem vget_ok {h : Heap α} {w : VView} {es : List α} (hr : VRep h w es) (i : Nat) :
    vget h w i = some es[i]? := by
  obtain ⟨hl, hlv, hsz, hcell⟩ := hr
  unfold vget
  by_cases hi : i < w.len
  · rw [ite_eq_left hi]
    simp only [Heap.load, hlv, true_and]
    rw [ite_eq_left (by omega), hcell i (by omega), List.getElem?_eq_getElem (by omega)]
    rfl
  · rw [ite_eq_right hi, List.getElem?_eq_none (by omega)]

/-- `vec_push` on a view: `__vec_grow_cap`'s view case (`alloc_grow_cap 4`
    to at least the length), `__vec_place`'s detach (a fresh `nurl_alloc`,
    the live cells copied), then the store and the length bump. The result
    is an ordinary owned `Vec`. -/
def vpush (h : Heap α) (w : VView) (x : α) : Option (Heap α × RVec) :=
  let nc := growCap 4 (w.len + 1)
  match memcpy (h.alloc nc).1 w.blk w.off (h.alloc nc).2 w.len with
  | none => none
  | some h1 =>
    (h1.store (h.alloc nc).2 w.len x).map fun h2 =>
      (h2, { data := some (h.alloc nc).2, len := w.len + 1, cap := nc })

/-- A push on a view detaches. The result represents `es ++ [x]` in a fresh
    block, and every block that was there keeps its cells, size and
    liveness: the owner's storage is never written or freed. -/
theorem vpush_ok {h : Heap α} {w : VView} {es : List α} (x : α) (hw : h.WF) (hr : VRep h w es) :
    ∃ h' v', vpush h w x = some (h', v') ∧ Rep h' v' (es ++ [x]) ∧ h'.WF ∧
      v'.data = some h.nid ∧ h'.nid = h.nid + 1 ∧ h'.live = upd h.live h.nid true ∧
      ∀ b, b < h.nid → h'.cell b = h.cell b ∧ h'.size b = h.size b := by
  obtain ⟨hl, hlv, hsz, hcell⟩ := hr
  have hbn : w.blk < h.nid := by
    rcases Nat.lt_or_ge w.blk h.nid with e | e
    · exact e
    · rw [hw _ e] at hlv; exact absurd hlv (by simp)
  have hg := growCap_ge 4 (w.len + 1)
  let nc := growCap 4 (w.len + 1)
  let ha := (h.alloc nc).1
  have hbd : w.blk ≠ h.nid := by omega
  have halb : ha.live w.blk = true := by
    show (upd h.live h.nid true) w.blk = true; simp only [upd, ite_eq_right hbd]; exact hlv
  have hald : ha.live h.nid = true := by show (upd h.live h.nid true) h.nid = true; simp [upd]
  have hasb : ha.size w.blk = h.size w.blk := by
    show (upd h.size h.nid nc) w.blk = _; simp only [upd, ite_eq_right hbd]
  have hasd : ha.size h.nid = nc := by show (upd h.size h.nid nc) h.nid = nc; simp [upd]
  have hacb : ∀ j, ha.cell w.blk j = h.cell w.blk j := by
    intro j; show (upd h.cell h.nid _) w.blk j = _; simp only [upd, ite_eq_right hbd]
  obtain ⟨h1, he, hlv1, hsz1, hn1, hoth1, hcell1⟩ := memcpy_ok (o := w.off) hbd halb hald w.len
    (by rw [hasb]; exact hsz) (by rw [hasd]; omega)
    (fun k hk => by rw [hacb, hcell k (by omega)]; rfl)
  have hin : h1.live h.nid = true ∧ w.len < h1.size h.nid :=
    ⟨by rw [hlv1]; exact hald, by rw [hsz1, hasd]; omega⟩
  refine ⟨{ h1 with cell := upd h1.cell h.nid (upd (h1.cell h.nid) w.len (some x)) },
    { data := some h.nid, len := w.len + 1, cap := nc }, ?_, ⟨?_, ?_, ?_⟩, ?_, rfl, ?_, ?_, ?_⟩
  · unfold vpush
    simp only []
    show (match memcpy ha w.blk w.off h.nid w.len with
      | none => none
      | some h1 => (h1.store h.nid w.len x).map fun h2 => (h2, ({ data := some h.nid, len := w.len + 1, cap := nc } : RVec))) = _
    rw [he]
    simp only [Heap.store, hin, and_self, ↓reduceIte, Option.map_some]
  · simp; omega
  · show w.len + 1 ≤ nc; omega
  · show h1.live h.nid = true ∧ h1.size h.nid = nc ∧ ∀ i (hi : i < (es ++ [x]).length),
      (upd h1.cell h.nid (upd (h1.cell h.nid) w.len (some x))) h.nid i = some (es ++ [x])[i]
    refine ⟨hin.1, by rw [hsz1, hasd], fun i hi => ?_⟩
    simp only [upd, ↓reduceIte]
    by_cases hil : i = w.len
    · subst hil; rw [ite_eq_left rfl, List.getElem_append_right (by omega)]; simp [hl]
    · rw [ite_eq_right hil, hcell1 i]
      have hi' : i < es.length := by simp at hi; omega
      rw [ite_eq_left (by omega), hacb, hcell i hi', List.getElem_append_left hi']
  · intro b hb
    show h1.live b = false
    have hb1 : h1.nid ≤ b := hb
    rw [hn1] at hb1
    have hb' : h.nid + 1 ≤ b := hb1
    rw [hlv1]; show (upd h.live h.nid true) b = false
    simp only [upd, ite_eq_right (show ¬ b = h.nid by omega)]; exact hw b (by omega)
  · show h1.nid = h.nid + 1; rw [hn1]; rfl
  · show h1.live = upd h.live h.nid true; rw [hlv1]; rfl
  · intro b hb
    have hbne : b ≠ h.nid := by omega
    refine ⟨?_, ?_⟩
    · show (upd h1.cell h.nid _) b = h.cell b
      simp only [upd, ite_eq_right hbne]; rw [hoth1 b hbne]
      show (upd h.cell h.nid _) b = h.cell b; simp only [upd, ite_eq_right hbne]
    · show h1.size b = h.size b; rw [hsz1]; show (upd h.size h.nid nc) b = _; simp only [upd, ite_eq_right hbne]

/-! ### `__vec_release_from`: drops that run program code (Agora #709)

For an element type whose drop runs code of the program's, `vec_truncate`
and `vec_clear` go through `__vec_release_from` and the runtime's
`nurl_vec_move_drop_dtor`. The elements past `from` are moved into a
buffer of the release's own first. Then the count is written, and only
then is each one dropped from that buffer, in index order. A destructor is
program code and may reach the `Vec` again: push into it, grow it, clear
it. The theorem below says it cannot change which elements are dropped.
For any destructor that leaves the release's own buffer alone, every
element past `from` is dropped exactly once, in order, and the `Vec`
represents the first `from` before the first destructor runs. (Safe code
cannot name that buffer: no value of the program points into it. That is
A2's business.) The stack-or-heap choice for the buffer (Agora #748) is a
fresh block here. -/

/-- The drop loop over the release's buffer `t`: load cell `k`, run the
    destructor (which may do anything to the heap), go on with `k + 1`. The
    claim is the order of the destructor calls in a completed drain: a
    panicking destructor (the runtime drains the rest, then hands control to
    a `recover` frame, or ends the process) is not modelled as a return. -/
def dropLoop (dtor : α → Heap α → Heap α) (t : Nat) : Nat → Nat → Heap α → Option (Heap α × List α)
  | _, 0, h => some (h, [])
  | k, n + 1, h =>
    match h.load t k with
    | none => none
    | some y => (dropLoop dtor t (k + 1) n (dtor y h)).map fun r => (r.1, y :: r.2)

theorem dropLoop_ok {dtor : α → Heap α → Heap α} {t : Nat}
    (hD : ∀ y (h : Heap α), (dtor y h).live t = h.live t ∧ (dtor y h).size t = h.size t ∧
      (dtor y h).cell t = h.cell t) :
    ∀ n k (h : Heap α) (ys : List α), h.live t = true → k + n ≤ h.size t → ys.length = n →
      (∀ i (hi : i < ys.length), h.cell t (k + i) = some ys[i]) →
      ∃ h', dropLoop dtor t k n h = some (h', ys) := by
  intro n
  induction n with
  | zero => intro k h ys _ _ hl _; rw [List.eq_nil_of_length_eq_zero hl]; exact ⟨h, rfl⟩
  | succ n ih =>
    intro k h ys hlv hsz hl hc
    match ys, hl with
    | y :: ys', hl =>
      have hl' : ys'.length = n := by simpa using hl
      have hy : h.cell t k = some y := by have := hc 0 (by simp); simpa using this
      have hload : h.load t k = some y := by
        simp only [Heap.load, hlv, true_and]; rw [ite_eq_left (by omega)]; exact hy
      obtain ⟨hD1, hD2, hD3⟩ := hD y h
      obtain ⟨h', he⟩ := ih (k + 1) (dtor y h) ys' (by rw [hD1]; exact hlv) (by rw [hD2]; omega) hl'
        (fun i hi => by rw [hD3]; have := hc (i + 1) (by simp; omega); simpa [Nat.add_assoc, Nat.add_comm 1] using this)
      exact ⟨h', by simp only [dropLoop, hload, he, Option.map_some]⟩

/-- `__vec_release_from v from` with `nurl_vec_move_drop_dtor`: a fresh
    buffer, the elements `[from, len)` copied into it, the count set to
    `from`, then the drop loop over the buffer. It hands back the heap, the
    `Vec` as the destructors first see it, and the elements dropped. -/
def releaseFrom (dtor : α → Heap α → Heap α) (h : Heap α) (v : RVec) (fr : Nat) :
    Option (Heap α × RVec × List α) :=
  if fr ≥ v.len then some (h, v, []) else
  match v.data with
  | none => none
  | some d =>
    let n := v.len - fr
    match memcpy (h.alloc n).1 d fr (h.alloc n).2 n with
    | none => none
    | some h1 => (dropLoop dtor (h.alloc n).2 0 n h1).map fun r => (r.1, { v with len := fr }, r.2)

/-- The release drops exactly `es.drop from`, in index order, each once,
    whatever the destructors do elsewhere. Before the first of them runs,
    the `Vec` represents `es.take from` in its own block, which the
    release's buffer (the heap's next fresh id) is not. -/
theorem releaseFrom_ok {dtor : α → Heap α → Heap α} {h : Heap α} {v : RVec} {es : List α}
    {fr : Nat} (hw : h.WF) (hr : Rep h v es) (hf : fr < es.length)
    (hD : ∀ y (g : Heap α), (dtor y g).live h.nid = g.live h.nid ∧ (dtor y g).size h.nid = g.size h.nid ∧
      (dtor y g).cell h.nid = g.cell h.nid) :
    ∃ h' h1, releaseFrom dtor h v fr = some (h', { v with len := fr }, es.drop fr) ∧
      Rep h1 { v with len := fr } (es.take fr) ∧ v.data ≠ some h.nid := by
  have hl : v.len = es.length := hr.1
  have hlc := hr.2.1
  cases hd : v.data with
  | none => have := rep_none hr hd; omega
  | some d =>
    obtain ⟨hld, hsz, hcell⟩ := rep_some hr hd
    have hdn : d < h.nid := by
      rcases Nat.lt_or_ge d h.nid with e | e
      · exact e
      · rw [hw d e] at hld; exact absurd hld (by simp)
    have hdne : d ≠ h.nid := by omega
    let n := v.len - fr
    let ha := (h.alloc n).1
    have hald : ha.live d = true := by
      show (upd h.live h.nid true) d = true; simp only [upd, ite_eq_right hdne]; exact hld
    have halt : ha.live h.nid = true := by show (upd h.live h.nid true) h.nid = true; simp [upd]
    have hasd : ha.size d = h.size d := by
      show (upd h.size h.nid n) d = _; simp only [upd, ite_eq_right hdne]
    have hast : ha.size h.nid = n := by show (upd h.size h.nid n) h.nid = n; simp [upd]
    have hacd : ∀ j, ha.cell d j = h.cell d j := by
      intro j; show (upd h.cell h.nid _) d j = _; simp only [upd, ite_eq_right hdne]
    obtain ⟨h1, he, hlv1, hsz1, hn1, hoth1, hcell1⟩ := memcpy_ok (o := fr) hdne hald halt n
      (by rw [hasd]; omega) (by rw [hast]; omega)
      (fun k hk => by rw [hacd, hcell (fr + k) (by omega)]; rfl)
    obtain ⟨h', hdrop⟩ := dropLoop_ok (dtor := dtor) (t := h.nid) hD n 0 h1 (es.drop fr)
      (by rw [hlv1]; exact halt) (by rw [hsz1, hast]; omega) (by simp; omega)
      (fun i hi => by
        simp at hi
        rw [hcell1, ite_eq_left (by omega), hacd, Nat.zero_add, hcell (fr + i) (by omega)]
        simp)
    refine ⟨h', h1, ?_, ⟨by simp; omega, by show fr ≤ v.cap; omega, ?_⟩, by simp; omega⟩
    · unfold releaseFrom
      rw [ite_eq_right (by omega)]
      simp only [hd]
      show (match memcpy ha d fr h.nid n with
        | none => none
        | some h1 => (dropLoop dtor h.nid 0 n h1).map fun (r : Heap α × List α) => (r.1, ({ data := some d, len := fr, cap := v.cap } : RVec), r.2)) = _
      rw [he]
      simp only [hdrop, Option.map_some]
    · show h1.live d = true ∧ h1.size d = v.cap ∧
            ∀ i (hi : i < (es.take fr).length), h1.cell d i = some (es.take fr)[i]
      refine ⟨by rw [hlv1]; exact hald, by rw [hsz1, hasd]; exact hsz, fun i hi => ?_⟩
      simp at hi
      rw [hoth1 d hdne, hacd, hcell i (by omega)]
      simp

/-! ### `vec_append`: moving one `Vec`'s elements onto another

`vec_append dst src` (`src` a `sink`) runs `__vec_extend_move`. That grows
`dst` to `dlen + n`, copies `src`'s cells bitwise to `dst` from `dlen`, bumps
`dst`'s length and sets `src`'s to 0. The elements change owner, and none is
copied or dropped. Because `src` is a `sink`, the two never share a buffer,
and the theorem asks for that. A growth of `dst` that reallocates ends only
`dst`'s block, so `src`'s cells are still there to be read. -/

/-- The element-copy loop `= . ddata + dlen i . sdata i`, for `n` cells. -/
def copyAt (h : Heap α) (b o d p : Nat) : Nat → Option (Heap α)
  | 0 => some h
  | n + 1 =>
    match copyAt h b o d p n with
    | none => none
    | some h1 =>
      match h1.load b (o + n) with
      | none => none
      | some y => h1.store d (p + n) y

theorem copyAt_ok {h : Heap α} {b o d p : Nat} (hbd : b ≠ d) (hlb : h.live b = true)
    (hld : h.live d = true) : ∀ n, o + n ≤ h.size b → p + n ≤ h.size d →
    (∀ k, k < n → (h.cell b (o + k)).isSome) →
    ∃ h', copyAt h b o d p n = some h' ∧ h'.live = h.live ∧ h'.size = h.size ∧ h'.nid = h.nid ∧
      (∀ c, c ≠ d → h'.cell c = h.cell c) ∧
      ∀ j, h'.cell d j = if p ≤ j ∧ j < p + n then h.cell b (o + (j - p)) else h.cell d j := by
  intro n
  induction n with
  | zero =>
    intro _ _ _
    exact ⟨h, rfl, rfl, rfl, rfl, fun _ _ => rfl, fun j => by rw [ite_eq_right (by omega)]⟩
  | succ n ih =>
    intro hb hd hc
    obtain ⟨h1, he, hlv, hsz, hn, hoth, hcell⟩ := ih (by omega) (by omega) (fun k hk => hc k (by omega))
    obtain ⟨y, hy⟩ := Option.isSome_iff_exists.mp (hc n (by omega))
    have hy1 : h1.cell b (o + n) = some y := by rw [hoth b hbd]; exact hy
    have hload : h1.load b (o + n) = some y := by
      simp only [Heap.load, hlv, hsz, hlb, true_and]; rw [ite_eq_left (by omega)]; exact hy1
    have hin : h1.live d = true ∧ p + n < h1.size d := ⟨by rw [hlv]; exact hld, by rw [hsz]; omega⟩
    refine ⟨{ h1 with cell := upd h1.cell d (upd (h1.cell d) (p + n) (some y)) }, ?_, hlv, hsz, hn, ?_, ?_⟩
    · simp only [copyAt, he, hload, Heap.store, hin, and_self, ↓reduceIte]
    · intro c hc'
      show (upd h1.cell d _) c = h.cell c
      simp only [upd, ite_eq_right hc']; exact hoth c hc'
    · intro j
      show (upd h1.cell d (upd (h1.cell d) (p + n) (some y))) d j = _
      simp only [upd, ↓reduceIte]
      by_cases hjn : j = p + n
      · subst hjn; rw [ite_eq_left rfl, ite_eq_left (by omega)]
        have : o + (p + n - p) = o + n := by omega
        rw [this]; exact hy.symm
      · rw [ite_eq_right hjn, hcell j]
        by_cases hj : p ≤ j ∧ j < p + n
        · rw [ite_eq_left hj, ite_eq_left (by omega)]
        · rw [ite_eq_right hj, ite_eq_right (by omega)]

/-- `vec_append dst src`: `__vec_extend_move`, then `src`'s length set to
    0. -/
def append (h : Heap α) (dst src : RVec) : Option (Heap α × RVec × RVec) :=
  if src.len = 0 then some (h, dst, { src with len := 0 }) else
  match (if dst.cap < dst.len + src.len then growTo h dst (dst.len + src.len) else some (h, dst)) with
  | none => none
  | some (h1, d1) =>
    match d1.data, src.data with
    | some dd, some sd =>
      (copyAt h1 sd 0 dd d1.len src.len).map fun h2 =>
        (h2, { d1 with len := d1.len + src.len }, { src with len := 0 })
    | _, _ => none

/-- `vec_append` of two `Vec`s that share no buffer (`src` is a `sink`, so a
    `Vec` is never appended to itself): `dst` represents `es1 ++ es2` and
    `src` is empty, holding its block (released at its drop). Every element
    moves; none is copied twice or lost. -/
theorem append_ok {h : Heap α} {dst src : RVec} {es1 es2 : List α} (hw : h.WF)
    (hr1 : Rep h dst es1) (hr2 : Rep h src es2) (hne : ∀ b, dst.data = some b → src.data ≠ some b) :
    ∃ h' d', append h dst src = some (h', d', { src with len := 0 }) ∧ Rep h' d' (es1 ++ es2) ∧
      Rep h' { src with len := 0 } [] ∧ h'.WF := by
  have hl1 : dst.len = es1.length := hr1.1
  have hl2 : src.len = es2.length := hr2.1
  have hlc2 := hr2.2.1
  by_cases h0 : src.len = 0
  · have : es2 = [] := List.eq_nil_of_length_eq_zero (by omega)
    subst this
    refine ⟨h, dst, by unfold append; rw [ite_eq_left h0], by simpa using hr1, ⟨rfl, by simp, ?_⟩, hw⟩
    have h2 := hr2.2.2
    revert h2
    show (match src.data with
      | none => src.cap = 0
      | some d => h.live d = true ∧ h.size d = src.cap ∧ ∀ i (hi : i < ([] : List α).length), h.cell d i = some ([] : List α)[i]) → _
    intro h2; exact h2
  · cases hsd : src.data with
    | none => have := rep_none hr2 hsd; omega
    | some sd =>
      obtain ⟨hlsd, hszsd, hcsd⟩ := rep_some hr2 hsd
      have hsdn : sd < h.nid := by
        rcases Nat.lt_or_ge sd h.nid with e | e
        · exact e
        · rw [hw sd e] at hlsd; exact absurd hlsd (by simp)
      -- the growth of `dst`: kept, or moved to a fresh id; `src`'s block stays
      have hg : ∃ h1 d1, (if dst.cap < dst.len + src.len then growTo h dst (dst.len + src.len)
            else some (h, dst)) = some (h1, d1) ∧ Rep h1 d1 es1 ∧ h1.WF ∧ dst.len + src.len ≤ d1.cap ∧
          d1.len = dst.len ∧ h1.live sd = true ∧ h1.size sd = h.size sd ∧ h1.cell sd = h.cell sd ∧
          d1.data ≠ some sd := by
        by_cases hf : dst.cap < dst.len + src.len
        · rw [ite_eq_left hf]
          obtain ⟨h1, d1, he, hr1', hw1, hroom, hlen, hbuf⟩ := growTo_ok (need := dst.len + src.len) hw hr1
          refine ⟨h1, d1, he, hr1', hw1, hroom, hlen, ?_⟩
          rcases hbuf with ⟨rfl, rfl⟩ | ⟨hd1, _, hlv, hfr⟩
          · exact ⟨hlsd, rfl, rfl, fun e => hne sd e hsd⟩
          · have hsne : dst.data ≠ some sd := fun e => hne sd e hsd
            obtain ⟨hc, hs⟩ := hfr sd hsdn hsne
            refine ⟨?_, hs, hc, by rw [hd1]; intro e; injection e; omega⟩
            rw [hlv]
            cases hdd : dst.data with
            | none => simp only [upd]; rw [ite_eq_right (by omega)]; exact hlsd
            | some dd =>
              have : sd ≠ dd := fun e => hsne (by rw [hdd, e])
              simp only [upd]; rw [ite_eq_right (by omega), ite_eq_right this]; exact hlsd
        · rw [ite_eq_right hf]
          exact ⟨h, dst, rfl, hr1, hw, by omega, rfl, hlsd, rfl, rfl, fun e => hne sd e hsd⟩
      obtain ⟨h1, d1, he, hr1', hw1, hroom, hlen, hl1sd, hs1sd, hc1sd, hd1ne⟩ := hg
      have hl1' : d1.len = es1.length := hr1'.1
      cases hdd : d1.data with
      | none => have := rep_none hr1' hdd; omega
      | some dd =>
        obtain ⟨hldd, hszdd, hcdd⟩ := rep_some hr1' hdd
        have hsdd : sd ≠ dd := fun e => hd1ne (by rw [hdd, e])
        obtain ⟨h2, hc2, hlv2, hsz2, hn2, hoth2, hcell2⟩ := copyAt_ok (o := 0) (p := d1.len) hsdd hl1sd hldd
          src.len (by rw [hs1sd]; omega) (by rw [hszdd]; omega)
          (fun k hk => by rw [hc1sd, Nat.zero_add, hcsd k (by omega)]; rfl)
        refine ⟨h2, { d1 with len := d1.len + src.len }, ?_, ⟨by simp; omega, by show d1.len + src.len ≤ d1.cap; omega, ?_⟩,
          ⟨rfl, by simp, ?_⟩, ?_⟩
        · unfold append
          rw [ite_eq_right h0, he]
          simp only [hdd, hsd, hc2, Option.map_some]
        · simp only [hdd]
          show h2.live dd = true ∧ h2.size dd = d1.cap ∧ ∀ i (hi : i < (es1 ++ es2).length),
            h2.cell dd i = some (es1 ++ es2)[i]
          refine ⟨by rw [hlv2]; exact hldd, by rw [hsz2]; exact hszdd, fun i hi => ?_⟩
          rw [hcell2 i]
          simp at hi
          by_cases hi1 : i < es1.length
          · rw [ite_eq_right (by omega), hcdd i hi1, List.getElem_append_left hi1]
          · rw [ite_eq_left (by omega), hc1sd, Nat.zero_add, hcsd (i - d1.len) (by omega),
              List.getElem_append_right (by omega)]
            simp only [hl1']
        · show h2.live sd = true ∧ h2.size sd = src.cap ∧ ∀ i (hi : i < ([] : List α).length), h2.cell sd i = some ([] : List α)[i]
          refine ⟨by rw [hlv2]; exact hl1sd, by rw [hsz2, hs1sd]; exact hszsd, fun i hi => by simp at hi⟩
        · intro b hb
          show h2.live b = false
          rw [hlv2]; exact hw1 b (by rw [← hn2]; exact hb)

/-! ### The packed layout (`string_from_bytes_packed`, `vec_split_off_packed`)

A packed `Vec` keeps its elements in its control block's own allocation,
24 bytes in (here cell `off` of the control block). `realloc` of a pointer
into the middle of a block is undefined behaviour, so `__vec_place` gives
the packed case the same detach as a borrowed view: a fresh `nurl_alloc`,
the live cells copied over, the data pointer moved. The theorem is
`vpush_ok` for that view. The push detaches, the control block keeps its
cells and stays live, and the result represents `es ++ [x]` in a fresh
block. The packed-aware release then frees the control block (with
whatever cells it still holds) and the new buffer separately. -/

/-- A push on a packed `Vec` whose elements sit at cell `off` of its
    control block `ctl` detaches: no `realloc` of an interior pointer, the
    control block untouched and live, the elements in a fresh block. -/
theorem packedPush_ok {h : Heap α} {ctl off : Nat} {es : List α} (x : α) (hw : h.WF)
    (hr : VRep h ⟨ctl, off, es.length⟩ es) :
    ∃ h' v', vpush h ⟨ctl, off, es.length⟩ x = some (h', v') ∧ Rep h' v' (es ++ [x]) ∧ h'.WF ∧
      v'.data = some h.nid ∧ h'.live ctl = true ∧
      ∀ b, b < h.nid → h'.cell b = h.cell b ∧ h'.size b = h.size b := by
  obtain ⟨h', v', he, hr', hw', hd, hn, hlv, hfr⟩ := vpush_ok x hw hr
  have hctl : ctl < h.nid := by
    rcases Nat.lt_or_ge ctl h.nid with e | e
    · exact e
    · have := hr.2.1; rw [hw ctl e] at this; exact absurd this (by simp)
  refine ⟨h', v', he, hr', hw', hd, ?_, hfr⟩
  rw [hlv]; simp only [upd, ite_eq_right (show ¬ ctl = h.nid by omega)]; exact hr.2.1

/-! ### The link to A1

A1 tracks each allocation by an id and one liveness bit (`Mem.alloc`,
`Mem.nid`). A1's `Vec` value `.node t c d es` names its buffer `d`, and A1
lets `vec_push` take either of two steps: `push` keeps `d`, `pushRealloc` ends
`d` and takes `nid`. `Agree` says the heap's blocks are A1's allocations.
`push_refines` says the raw push, on a buffer A1 names, agrees with one of
A1's two steps on buffer identity and allocation state: the same buffer and
the same allocation map, or the next fresh id with A1's own update of the
map. (It does not by itself give an A1 transition, which also needs the
slots A1's push reads.) -/

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
