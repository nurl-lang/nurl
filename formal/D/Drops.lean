/-!
# D2: what D0's "validated" means (AGORA-981 / AGORA-984 follow-up)

`tools/ncore/tvdrops.py` (phase D0) checks the LLVM nurlc emits path by
path, with drop flags as the ownership record codegen keeps: a slot owns
the block it holds while its flag is set and the block was not released.
This file states, on a model of one path, what an accepted path guarantees
about the heap, and proves it.

A path is a list of operations on a frame's slots (`Op`), each the shape of
an LLVM sequence codegen emits:

* `new s`: a fresh block stored into `s` and its flag set (`store`, then
  `store i1 true`);
* `put s`: a value the frame does not own stored into `s`, flag clear;
* `clr s`: the value moved out of `s` (handed to a callee or the caller) and
  its flag cleared;
* `copy d s`: `= d s`, the slot and flag moved from `s` to `d` (codegen
  clears `s`'s flag next, with a `clr`-free `store i1 0`, modelled here as
  `off s`);
* `off s`: `s`'s flag cleared, nothing handed on;
* `drop s`: `__dropif(flag s, s)`.

The concrete run (`runC`) keeps the frame's live blocks. It fails on a free
of a block that is not live (a double free), on a move out of one that is
not live (a use after free), and, at the end of the path (the `ret`), on any
block still live (a leak). The checker (`checkA`) is D0's: value ids, the
list of released ones, and "owned" as flag set and not released; it never
looks at the live set. `checkA_sound`: an accepted path's concrete run ends
with no error and nothing live.
-/

namespace D

abbrev Slot := Nat

inductive Op where
  | new (s : Slot)
  | put (s : Slot)
  | clr (s : Slot)
  | copy (d s : Slot)
  | off (s : Slot)
  | drop (s : Slot)
deriving DecidableEq, Repr

/-- The slots an operation names. -/
def Op.slots : Op → List Slot
  | .new s | .put s | .clr s | .off s | .drop s => [s]
  | .copy d s => [d, s]

/-- The state both runs share: each slot's block (`none`: no block the frame
    tracks) and flag, and the next fresh block. -/
structure Fr where
  val : Slot → Option Nat
  flg : Slot → Bool
  next : Nat

def Fr.init : Fr := ⟨fun _ => none, fun _ => false, 0⟩

def upd {α : Type} (f : Slot → α) (s : Slot) (a : α) : Slot → α :=
  fun t => if t = s then a else f t

/-! ## The concrete run: a heap of live blocks -/

/-- One step of the concrete run, with the live blocks; `none` is an error
    (a double free, or a use after free). -/
def stepC (fr : Fr) (live : List Nat) : Op → Option (Fr × List Nat)
  | .new s => some (⟨upd fr.val s (some fr.next), upd fr.flg s true, fr.next + 1⟩, fr.next :: live)
  | .put s => some (⟨upd fr.val s none, upd fr.flg s false, fr.next⟩, live)
  | .clr s =>
    if fr.flg s then
      match fr.val s with
      | some b => if b ∈ live then some (⟨fr.val, upd fr.flg s false, fr.next⟩, live.erase b) else none
      | none => none
    else some (fr, live)
  | .copy d s => some (⟨upd fr.val d (fr.val s), upd fr.flg d (fr.flg s), fr.next⟩, live)
  | .off s => some (⟨fr.val, upd fr.flg s false, fr.next⟩, live)
  | .drop s =>
    if fr.flg s then
      match fr.val s with
      | some b => if b ∈ live then some (fr, live.erase b) else none
      | none => none
    else some (fr, live)

/-- The concrete run of a path: `true` when it ends with no error and no
    block live. -/
def runC : List Op → Fr → List Nat → Bool
  | [], _, live => live.isEmpty
  | o :: os, fr, live =>
    match stepC fr live o with
    | some (fr', live') => runC os fr' live'
    | none => false

/-! ## The checker: D0's abstract run, with released ids -/

/-- `s` owns its block: its flag is set, and the block was not released. -/
def owned (fr : Fr) (rel : List Nat) (s : Slot) : Bool :=
  fr.flg s && match fr.val s with
    | some b => !(rel.contains b)
    | none => false

/-- Another slot of `S` owns `s`'s block too (`= d s` copied the flag). -/
def ownedElsewhere (S : List Slot) (fr : Fr) (s : Slot) : Bool :=
  S.any fun t => t != s && fr.flg t && fr.val t == fr.val s

/-- One step of the checker over the slots `S`; `none` is a mismatch. -/
def stepA (S : List Slot) (fr : Fr) (rel : List Nat) : Op → Option (Fr × List Nat)
  | .new s => if owned fr rel s then none
      else some (⟨upd fr.val s (some fr.next), upd fr.flg s true, fr.next + 1⟩, rel)
  | .put s => if owned fr rel s then none
      else some (⟨upd fr.val s none, upd fr.flg s false, fr.next⟩, rel)
  | .clr s =>
    if fr.flg s then
      match fr.val s with
      | some b => if rel.contains b then none else some (⟨fr.val, upd fr.flg s false, fr.next⟩, b :: rel)
      | none => none
    else some (fr, rel)
  | .copy d s => if owned fr rel d then none
      else some (⟨upd fr.val d (fr.val s), upd fr.flg d (fr.flg s), fr.next⟩, rel)
  | .off s => if owned fr rel s && !ownedElsewhere S fr s then none
      else some (⟨fr.val, upd fr.flg s false, fr.next⟩, rel)
  | .drop s =>
    if fr.flg s then
      match fr.val s with
      | some b => if rel.contains b then none else some (fr, b :: rel)
      | none => none
    else some (fr, rel)

/-- The checker on a path over the slots `S`: every step passes, and at the
    end no slot of `S` owns a block. -/
def checkA (S : List Slot) : List Op → Fr → List Nat → Bool
  | [], fr, rel => S.all (fun s => !owned fr rel s)
  | o :: os, fr, rel =>
    o.slots.all (· ∈ S) &&
    match stepA S fr rel o with
    | some (fr', rel') => checkA S os fr' rel'
    | none => false

/-! ## The invariant between the two runs -/

/-- Every block a slot holds or the checker released was made; the live
    blocks are the made ones not released, each held by an owning slot of
    `S`; slots outside `S` hold none; no block is live twice. -/
structure Inv (S : List Slot) (fr : Fr) (rel live : List Nat) : Prop where
  made : ∀ s b, fr.val s = some b → b < fr.next
  relMade : ∀ b, b ∈ rel → b < fr.next
  liveIff : ∀ b, b < fr.next → (b ∈ live ↔ b ∉ rel)
  liveMade : ∀ b, b ∈ live → b < fr.next
  held : ∀ b, b ∈ live → ∃ s, s ∈ S ∧ fr.val s = some b ∧ fr.flg s = true
  outside : ∀ s, s ∉ S → fr.val s = none
  nodup : live.Nodup

theorem inv_init (S : List Slot) : Inv S Fr.init [] [] where
  made := fun _ _ h => by simp [Fr.init] at h
  relMade := fun _ h => by simp at h
  liveIff := fun _ h => by simp [Fr.init] at h
  liveMade := fun _ h => by simp at h
  held := fun _ h => by simp at h
  outside := fun _ _ => rfl
  nodup := List.nodup_nil

theorem owned_iff {fr : Fr} {rel : List Nat} {s : Slot} :
    owned fr rel s = true ↔ ∃ b, fr.val s = some b ∧ fr.flg s = true ∧ b ∉ rel := by
  unfold owned
  cases h : fr.val s with
  | none => simp
  | some b => simp

/-- A live block is held by an owning slot of `S`. -/
theorem live_owned {S : List Slot} {fr : Fr} {rel live : List Nat} (hi : Inv S fr rel live)
    {b : Nat} (hb : b ∈ live) : ∃ s, s ∈ S ∧ owned fr rel s = true := by
  obtain ⟨s, hs, hv, hf⟩ := hi.held b hb
  have hrel : b ∉ rel := (hi.liveIff b (hi.liveMade b hb)).mp hb
  exact ⟨s, hs, owned_iff.mpr ⟨b, hv, hf, hrel⟩⟩

/-- A live block held by `s`, whose flag is set, makes `s` owning. -/
theorem owned_of_held {S : List Slot} {fr : Fr} {rel live : List Nat} (hi : Inv S fr rel live)
    {b : Nat} (hb : b ∈ live) {s : Slot} (hv : fr.val s = some b) (hf : fr.flg s = true) :
    owned fr rel s = true :=
  owned_iff.mpr ⟨b, hv, hf, (hi.liveIff b (hi.liveMade b hb)).mp hb⟩

/-- Releasing `b`, a held block that was not released: the invariant for
    the live blocks without it, the flags as `flg'`, when no other live
    block was held only through a flag `flg'` changes. -/
theorem inv_release {S : List Slot} {fr : Fr} {rel live : List Nat} (hi : Inv S fr rel live)
    {b : Nat} (hbm : b < fr.next) (flg' : Slot → Bool)
    (hkeep : ∀ c, c ∈ live → c ≠ b → ∀ t, fr.val t = some c → fr.flg t = true → flg' t = true) :
    Inv S ⟨fr.val, flg', fr.next⟩ (b :: rel) (live.erase b) where
  made := hi.made
  relMade := fun c hc => by
    rcases List.mem_cons.mp hc with rfl | hc
    · exact hbm
    · exact hi.relMade c hc
  liveIff := fun c hc => by
    rw [hi.nodup.mem_erase_iff, List.mem_cons, hi.liveIff c hc]
    exact ⟨fun ⟨h1, h2⟩ h => h.elim h1 h2, fun h => ⟨fun e => h (Or.inl e), fun e => h (Or.inr e)⟩⟩
  liveMade := fun c hc => hi.liveMade c (List.mem_of_mem_erase hc)
  held := fun c hc => by
    rw [hi.nodup.mem_erase_iff] at hc
    obtain ⟨t, ht, hv, hf⟩ := hi.held c hc.2
    exact ⟨t, ht, hv, hkeep c hc.2 hc.1 t hv hf⟩
  outside := hi.outside
  nodup := hi.nodup.erase b

/-- One step keeps the invariant, and the concrete step succeeds wherever
    the checker's does. -/
theorem step_ok {S : List Slot} {fr : Fr} {rel live : List Nat} (hi : Inv S fr rel live)
    {o : Op} (hS : ∀ s ∈ o.slots, s ∈ S) {fr' : Fr} {rel' : List Nat}
    (h : stepA S fr rel o = some (fr', rel')) :
    ∃ live', stepC fr live o = some (fr', live') ∧ Inv S fr' rel' live' := by
  cases o with
  | new s =>
    have hs : s ∈ S := hS s (by simp [Op.slots])
    simp only [stepA] at h
    split at h
    · cases h
    · rename_i hno
      simp only [Option.some.injEq, Prod.mk.injEq] at h
      obtain ⟨rfl, rfl⟩ := h
      refine ⟨_, rfl, ⟨?_, ?_, ?_, ?_, ?_, ?_, ?_⟩⟩
      · intro t c hv; simp only [upd] at hv ⊢; split at hv
        · cases hv; omega
        · have := hi.made t c hv; omega
      · intro c hc; have := hi.relMade c hc; simp only; omega
      · intro c hc; simp only [List.mem_cons] at hc ⊢
        by_cases hcn : c = fr.next
        · subst hcn
          exact ⟨fun _ hr => by have := hi.relMade _ hr; omega, fun _ => Or.inl rfl⟩
        · have hlt : c < fr.next := by omega
          rw [← hi.liveIff c hlt]; simp [hcn]
      · intro c hc; simp only [List.mem_cons] at hc ⊢
        rcases hc with rfl | hc
        · omega
        · have := hi.liveMade c hc; omega
      · intro c hc; simp only [List.mem_cons] at hc
        rcases hc with rfl | hc
        · exact ⟨s, hs, by simp [upd], by simp [upd]⟩
        · obtain ⟨t, ht, hv, hf⟩ := hi.held c hc
          by_cases hts : t = s
          · subst hts; exact absurd (owned_of_held hi hc hv hf) hno
          · exact ⟨t, ht, by simp [upd, hts, hv], by simp [upd, hts, hf]⟩
      · intro t ht
        have : t ≠ s := fun e => ht (e ▸ hs)
        simp [upd, this, hi.outside t ht]
      · exact List.nodup_cons.mpr ⟨fun hl => by have := hi.liveMade _ hl; omega, hi.nodup⟩
  | put s =>
    simp only [stepA] at h
    split at h
    · cases h
    · rename_i hno
      simp only [Option.some.injEq, Prod.mk.injEq] at h
      obtain ⟨rfl, rfl⟩ := h
      refine ⟨_, rfl, ⟨?_, hi.relMade, hi.liveIff, hi.liveMade, ?_, ?_, hi.nodup⟩⟩
      · intro t c hv; simp only [upd] at hv; split at hv
        · cases hv
        · exact hi.made t c hv
      · intro c hc
        obtain ⟨t, ht, hv, hf⟩ := hi.held c hc
        by_cases hts : t = s
        · subst hts; exact absurd (owned_of_held hi hc hv hf) hno
        · exact ⟨t, ht, by simp [upd, hts, hv], by simp [upd, hts, hf]⟩
      · intro t ht; simp only [upd]; split
        · rfl
        · exact hi.outside t ht
  | clr s =>
    simp only [stepA] at h
    split at h
    · rename_i hf
      split at h
      · rename_i b hv
        split at h
        · cases h
        · rename_i hr
          simp only [Option.some.injEq, Prod.mk.injEq] at h
          obtain ⟨rfl, rfl⟩ := h
          have hbm := hi.made s b hv
          have hrel : b ∉ rel := by simpa [List.contains_iff_mem] using hr
          have hbl : b ∈ live := (hi.liveIff b hbm).mpr hrel
          refine ⟨live.erase b, by simp [stepC, hf, hv, hbl], ?_⟩
          refine inv_release hi hbm _ (fun c _ hcb t hvt hft => ?_)
          by_cases hts : t = s
          · subst hts; rw [hv] at hvt; cases hvt; exact absurd rfl hcb
          · simp [upd, hts, hft]
      · cases h
    · rename_i hf
      simp only [Option.some.injEq, Prod.mk.injEq] at h
      obtain ⟨rfl, rfl⟩ := h
      exact ⟨live, by simp [stepC, hf], hi⟩
  | copy d s =>
    have hd : d ∈ S := hS d (by simp [Op.slots])
    simp only [stepA] at h
    split at h
    · cases h
    · rename_i hno
      simp only [Option.some.injEq, Prod.mk.injEq] at h
      obtain ⟨rfl, rfl⟩ := h
      refine ⟨_, rfl, ⟨?_, hi.relMade, hi.liveIff, hi.liveMade, ?_, ?_, hi.nodup⟩⟩
      · intro t c hv; simp only [upd] at hv; split at hv
        · exact hi.made s c hv
        · exact hi.made t c hv
      · intro c hc
        obtain ⟨t, ht, hv, hf⟩ := hi.held c hc
        by_cases htd : t = d
        · subst htd; exact absurd (owned_of_held hi hc hv hf) hno
        · exact ⟨t, ht, by simp [upd, htd, hv], by simp [upd, htd, hf]⟩
      · intro t ht
        have : t ≠ d := fun e => ht (e ▸ hd)
        simp [upd, this, hi.outside t ht]
  | off s =>
    simp only [stepA] at h
    split at h
    · cases h
    · rename_i hno
      simp only [Option.some.injEq, Prod.mk.injEq] at h
      obtain ⟨rfl, rfl⟩ := h
      refine ⟨_, rfl, ⟨hi.made, hi.relMade, hi.liveIff, hi.liveMade, ?_, hi.outside, hi.nodup⟩⟩
      intro c hc
      obtain ⟨t, ht, hv, hf⟩ := hi.held c hc
      by_cases hts : t = s
      · subst hts
        -- `t` owns `c`, so another slot owning it too is what let the flag go
        have ho := owned_of_held hi hc hv hf
        have he : ownedElsewhere S fr t = true := by
          cases hh : ownedElsewhere S fr t
          · simp [ho, hh] at hno
          · rfl
        simp only [ownedElsewhere, List.any_eq_true, Bool.and_eq_true, bne_iff_ne, ne_eq,
          beq_iff_eq] at he
        obtain ⟨u, hu, ⟨hut, hfu⟩, hvu⟩ := he
        exact ⟨u, hu, by rw [hvu, hv], by simp [upd, hut, hfu]⟩
      · exact ⟨t, ht, hv, by simp [upd, hts, hf]⟩
  | drop s =>
    simp only [stepA] at h
    split at h
    · rename_i hf
      split at h
      · rename_i b hv
        split at h
        · cases h
        · rename_i hr
          simp only [Option.some.injEq, Prod.mk.injEq] at h
          obtain ⟨rfl, rfl⟩ := h
          have hbm := hi.made s b hv
          have hrel : b ∉ rel := by simpa [List.contains_iff_mem] using hr
          have hbl : b ∈ live := (hi.liveIff b hbm).mpr hrel
          refine ⟨live.erase b, by simp [stepC, hf, hv, hbl], ?_⟩
          exact inv_release hi hbm fr.flg (fun _ _ _ _ _ hft => hft)
      · cases h
    · rename_i hf
      simp only [Option.some.injEq, Prod.mk.injEq] at h
      obtain ⟨rfl, rfl⟩ := h
      exact ⟨live, by simp [stepC, hf], hi⟩

/-- **D0's guarantee.** A path the checker accepts runs, on the concrete
    heap, with no double free and no use after free, and ends with every
    block the frame made released or handed on: nothing leaks. -/
theorem checkA_sound (S : List Slot) :
    ∀ (os : List Op) (fr : Fr) (rel live : List Nat), Inv S fr rel live →
      checkA S os fr rel = true → runC os fr live = true := by
  intro os
  induction os with
  | nil =>
    intro fr rel live hi h
    simp only [checkA, List.all_eq_true, Bool.not_eq_true'] at h
    simp only [runC, List.isEmpty_iff]
    apply List.eq_nil_iff_forall_not_mem.mpr
    intro b hb
    obtain ⟨s, hs, ho⟩ := live_owned hi hb
    rw [h s hs] at ho; cases ho
  | cons o os ih =>
    intro fr rel live hi h
    simp only [checkA, Bool.and_eq_true, List.all_eq_true, decide_eq_true_eq] at h
    obtain ⟨hS, h⟩ := h
    split at h
    · rename_i fr' rel' hst
      obtain ⟨live', hc, hi'⟩ := step_ok hi hS hst
      simp only [runC, hc]
      exact ih fr' rel' live' hi' h
    · cases h

/-- From the start of a frame: an accepted path is a safe one. -/
theorem validated_safe (S : List Slot) (os : List Op) (h : checkA S os Fr.init [] = true) :
    runC os Fr.init [] = true :=
  checkA_sound S os Fr.init [] [] (inv_init S) h

/-! Witnesses: the checker refuses what the concrete run would get wrong. -/

/-- A block released twice (a move that leaves its flag set). -/
example : checkA [0, 1] [.new 0, .copy 1 0, .drop 0, .drop 1] Fr.init [] = false := by decide
example : runC [.new 0, .copy 1 0, .drop 0, .drop 1] Fr.init [] = false := by decide
/-- The same with the flag cleared after the move: accepted, and safe. -/
example : checkA [0, 1] [.new 0, .copy 1 0, .off 0, .drop 0, .drop 1] Fr.init [] = true := by decide
/-- A leak: the release missing. -/
example : checkA [0] [.new 0] Fr.init [] = false := by decide

end D
