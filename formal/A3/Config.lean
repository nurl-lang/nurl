import A3.Touch

/-! A3.0 — the configuration invariant.

The address space is cut three ways (A3.1): one part per thread, disjoint,
and the shared, read-only part of the live blocks' payloads, apart from
every thread's (`payPart`); together they are the whole of it.  Each thread
sees its own part and the payloads (`ownView`), and there it has A2's facts
(`ThreadOK`) and address-free borrows (`BorFree`).  This file states it,
shows the program's start has it, and draws the leak claim from it: when
every thread has finished nothing is allocated (each finished thread's part
is empty, and no slot is left to reach a block, so the last sweep left no
payload).  The race claim is drawn in `A3.Pres`, from a thread's step on its
own view. -/

namespace A3
open A2

/-- Thread `t` with its part `a` of the address space, and (A3.1) the shared
    payloads, which every thread reads. -/
noncomputable def ownView (C : Cfg) (t : Thread) (a : Nat → Bool) : Mem :=
  { alloc := union a (payPart C.blk), nid := C.nid, nv := t.nv, st := t.st, blk := C.blk }

/-- The configuration invariant, with the threads' parts `ps`. -/
structure CParts (P : Prog) (C : Cfg) (ps : List (Nat → Bool)) : Prop where
  len  : ps.length = C.ths.length
  /-- Every live address is on a part, or a payload's. -/
  all  : ∀ i, C.alloc i = true ↔ (∃ a ∈ ps, a i = true) ∨ PayIn C.blk i
  disj : ∀ (j k : Nat) (a b : Nat → Bool), j ≠ k → ps[j]? = some a → ps[k]? = some b →
    ∀ i, a i = true → b i = false
  /-- No part holds a payload's address. -/
  pay  : ∀ (j : Nat) (a : Nat → Bool), ps[j]? = some a → ∀ i, a i = true → ¬ PayIn C.blk i
  /-- One payload owns each payload address. -/
  uniq : ∀ k k' bl bl' i, C.blk k = some bl → C.blk k' = some bl' → i ∈ bl.pay.ids → i ∈ bl'.pay.ids →
    k = k'
  ok   : ∀ (j : Nat) (t : Thread) (a : Nat → Bool), C.ths[j]? = some t → ps[j]? = some a →
    ThreadOK P (ownView C t a) t.s ∧ BorFree (ownView C t a)

/-- The configuration invariant: its parts, and (A3.1) every block is
    reached from some thread's slots — the last sweep left no other. -/
def CInv (P : Prog) (C : Cfg) : Prop :=
  ∃ ps : List (Nat → Bool), CParts P C ps ∧ ∀ k bl, C.blk k = some bl → Reached C.vals C.blk k

theorem part_of {α β : Type} {ps : List α} {ths : List β} (hlen : ps.length = ths.length) {j : Nat}
    {t : β} (hj : ths[j]? = some t) : ∃ a, ps[j]? = some a := by
  have hlt : j < ps.length := by rw [hlen]; exact (List.getElem?_eq_some_iff.mp hj).1
  exact ⟨ps[j], List.getElem?_eq_getElem hlt⟩

theorem thread_of {α β : Type} {ps : List α} {ths : List β} (hlen : ps.length = ths.length) {j : Nat}
    {a : α} (hj : ps[j]? = some a) : ∃ t, ths[j]? = some t := by
  have hlt : j < ths.length := by rw [← hlen]; exact (List.getElem?_eq_some_iff.mp hj).1
  exact ⟨ths[j], List.getElem?_eq_getElem hlt⟩

/-- An address live on a thread's view: on its part, or a payload's. -/
theorem ownView_alloc {C : Cfg} {t : Thread} {a : Nat → Bool} {i : Nat} :
    (ownView C t a).alloc i = true ↔ a i = true ∨ PayIn C.blk i := by
  simp only [ownView, union, Bool.or_eq_true, payPart_iff]

/-- An address a thread owns is on its part. -/
theorem owned_part {P : Prog} {C : Cfg} {t : Thread} {a : Nat → Bool} {s : Stmt}
    (h : ThreadOK P (ownView C t a) s) {i : Nat} (hi : OwnedId (C.view t) i) : a i = true := by
  have hi' : OwnedId (ownView C t a) i := hi.st_eq rfl
  rcases ownView_alloc.mp (h.owned i hi') with h1 | h1
  · exact h1
  · exact absurd h1 (h.notPay hi')

/-- The start: one thread, the whole (empty) address space its part. -/
theorem CInv.init {P : Prog} {s : Stmt} {Δ : Ctx} {nv : Nat}
    (ht : StmtT P (fun _ => none) [] s Δ) (hs : s.src = true) (hsc : s.codesOK P)
    (hv : ∀ v ∈ s.vars, v < nv) : CInv P (Cfg.init s nv) := by
  have hnp : ∀ i, ¬ PayIn (Cfg.init s nv).blk i := fun i ⟨_, _, hk, _⟩ => by simp [Cfg.init] at hk
  refine ⟨[fun _ => false], ⟨rfl, fun i => ?_, fun j k a b hjk hj hk => ?_, fun j a _ i _ => hnp i,
    fun k _ bl _ _ hk => by simp [Cfg.init] at hk, fun j t a hj ha => ?_⟩, fun k bl hk => by simp [Cfg.init] at hk⟩
  · constructor
    · intro h; simp [Cfg.init] at h
    · rintro (⟨a, ha, h⟩ | h)
      · simp only [List.mem_singleton] at ha; subst ha; cases h
      · exact absurd h (hnp i)
  · cases j <;> cases k <;> simp_all
  · cases j with
    | succ j => simp [Cfg.init] at hj
    | zero =>
      simp [Cfg.init] at hj ha
      subst hj; subst ha
      have heq : ownView (Cfg.init s nv) ⟨fun _ => none, nv, s⟩ (fun _ => false) = emptyMem nv := by
        simp only [ownView, emptyMem, Cfg.init]
        congr 1
        funext i
        simp only [union, Bool.false_or]
        exact payPart_false.mpr (hnp i)
      rw [heq]
      exact ⟨ThreadOK.init ht hs hsc hv, fun _ _ h => by cases h⟩

/-- When every thread has finished, no slot holds a value. -/
theorem CParts.vals_end {P : Prog} {C : Cfg} {ps : List (Nat → Bool)} (hc : CParts P C ps)
    (hend : ∀ t ∈ C.ths, t.s = .skip) (v : Val) : ¬ C.vals v := by
  rintro ⟨j, t, ht, x, o, hx⟩
  obtain ⟨a, ha⟩ := part_of hc.len ht
  obtain ⟨hto, _⟩ := hc.ok j t a ht ha
  rw [hend t (List.mem_of_getElem? ht)] at hto
  have := hto.skip_st x
  simp only [ownView] at this
  rw [this] at hx; cases hx

/-- **No leak**: when every thread has finished, nothing is allocated: no
    thread owns a tree, and (A3.1) no slot is left to reach a block, so the
    last sweep left none. -/
theorem CInv.noLeak {P : Prog} {C : Cfg} (h : CInv P C) (hend : ∀ t ∈ C.ths, t.s = .skip) :
    ∀ i, C.alloc i = false := by
  obtain ⟨ps, hc, hreach⟩ := h
  have hnr : ∀ k, ¬ Reached C.vals C.blk k := by
    intro k hr
    induction hr with
    | root hv _ => exact hc.vals_end hend _ hv
    | pay _ _ _ ih => exact ih
  have hnb : ∀ k bl, C.blk k ≠ some bl := fun k bl hk => hnr k (hreach k bl hk)
  intro i
  cases hai : C.alloc i with
  | false => rfl
  | true =>
    rcases (hc.all i).mp hai with ⟨a, ha, hai'⟩ | ⟨k, bl, hk, _⟩
    · obtain ⟨j, hj⟩ := List.mem_iff_getElem?.mp ha
      obtain ⟨t, ht⟩ := thread_of hc.len hj
      obtain ⟨hto, _⟩ := hc.ok j t a ht hj
      rw [hend t (List.mem_of_getElem? ht)] at hto
      exact absurd (hto.no_leak i (ownView_alloc.mpr (.inl hai'))) (hc.pay j a hj i hai')
    · exact absurd hk (hnb k bl)

end A3
