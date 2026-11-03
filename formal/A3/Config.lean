import A3.Touch

/-! A3.0 — the configuration invariant.

The address space is cut three ways (A3.1): one part per thread, disjoint,
and the shared, read-only part of the live blocks' payloads, apart from
every thread's (`payPart`); together they are the whole of it.  Each thread
sees its own part and the payloads (`ownView`), and there it has A2's facts
(`ThreadOK`) and address-free borrows (`BorFree`).  This file states it,
shows the program's start has it, and draws the leak claim from it: when
every thread has finished nothing is allocated but what the module globals
reach (each finished thread's part is empty, and no slot is left to reach a
block, so the last sweep left only the payloads a global reaches, A3.6).  The race claim is drawn in `A3.Pres`, from a thread's step on its
own view. -/

namespace A3
open A2

/-- Thread `t` with its part `a` of the address space, and (A3.1) the shared
    payloads, which every thread reads. -/
noncomputable def ownView (C : Cfg) (t : Thread) (a : Nat → Bool) : Mem :=
  { alloc := union a (payPart C.blk), nid := C.nid, nv := t.nv, st := t.st, blk := C.blk, gl := C.gl }

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
  uniq : ∀ k k' bl bl' i, C.blk k = some bl → C.blk k' = some bl' → i ∈ bl.tree.ids → i ∈ bl'.tree.ids →
    k = k'
  ok   : ∀ (j : Nat) (t : Thread) (a : Nat → Bool), C.ths[j]? = some t → ps[j]? = some a →
    ThreadOK P (ownView C t a) t.s ∧ BorFree (ownView C t a)

/-- The configuration invariant: its parts, and (A3.1) every block is
    reached from some thread's slots or (A3.6) a global — the last sweep
    left no other. -/
def CInv (P : Prog) (C : Cfg) : Prop :=
  ∃ ps : List (Nat → Bool), CParts P C ps ∧ ∀ k bl, C.blk k = some bl → Reached C.roots C.blk k

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

/-- The start (A3.6: with the module globals set): one thread, whose part
    is empty; every live address is a payload of a block a global reaches. -/
theorem CInv.start {P : Prog} {s : Stmt} {Δ : Ctx} {nv : Nat} {G : Globs}
    (ht : StmtT P (fun _ => none) [] s Δ) (hs : s.src = true) (hsc : s.codesOK P)
    (hv : ∀ v ∈ s.vars, v < nv) (hG : GlobsOK P G) : CInv P (Cfg.start G s nv) := by
  refine ⟨[fun _ => false], ⟨rfl, fun i => ?_, fun j k a b hjk hj hk => ?_, fun j a ha i hai _ => ?_,
    fun k k' bl bl' i hk hk' hi hi' => ?_, fun j t a hj ha => ?_⟩,
    fun k bl hk => (hG.reach k bl hk).roots (fun v hv => .inr hv)⟩
  · show G.alloc i = true ↔ _
    rw [hG.alloc i]
    constructor
    · exact .inr
    · rintro (⟨a, ha, h⟩ | h)
      · simp only [List.mem_singleton] at ha; subst ha; cases h
      · exact h
  · cases j <;> cases k <;> simp_all
  · cases j with
    | zero => simp at ha; subst ha; cases hai
    | succ j => simp at ha
  · exact Classical.byContradiction fun hne =>
      (hG.blocksAt k bl hk).apart i hi k' bl' (fun e => hne e.symm) hk' hi'
  · cases j with
    | succ j => simp [Cfg.start] at hj
    | zero =>
      simp [Cfg.start] at hj ha
      subst hj; subst ha
      exact ⟨ThreadOK.start ht hs hsc hv hG, fun _ _ h => by cases h⟩

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

/-- **No leak**: when every thread has finished, nothing is allocated but
    what the module globals reach: no thread owns a tree, and (A3.1) no slot
    is left to reach a block, so the last sweep left only (A3.6) the blocks a
    global reaches, which own every live address. -/
theorem CInv.noLeak {P : Prog} {C : Cfg} (h : CInv P C) (hend : ∀ t ∈ C.ths, t.s = .skip) :
    ∀ i, C.alloc i = true → ∃ k bl, C.blk k = some bl ∧ i ∈ bl.tree.ids ∧ Reached C.globVals C.blk k := by
  obtain ⟨ps, hc, hreach⟩ := h
  intro i hai
  rcases (hc.all i).mp hai with ⟨a, ha, hai'⟩ | ⟨k, bl, hk, hik⟩
  · obtain ⟨j, hj⟩ := List.mem_iff_getElem?.mp ha
    obtain ⟨t, ht⟩ := thread_of hc.len hj
    obtain ⟨hto, _⟩ := hc.ok j t a ht hj
    rw [hend t (List.mem_of_getElem? ht)] at hto
    exact absurd (hto.no_leak i (ownView_alloc.mpr (.inl hai'))) (hc.pay j a hj i hai')
  · refine ⟨k, bl, hk, hik, (hreach k bl hk).of_roots fun v hv _ _ => ?_⟩
    rcases hv with hv | hv
    · exact absurd hv (hc.vals_end hend v)
    · exact hv

/-- **A3.6: no step of the configuration writes a module global**: a thread's
    step writes none (`Step.gl`), and a spawn and the sweep leave them. -/
theorem TStep.gl {P : Prog} {spawn : Nat → Bool} {C C' : Cfg} (h : TStep P spawn C C') : C'.gl = C.gl := by
  cases h with
  | thread _ _ hs => have h := Step.gl hs; exact h
  | spawn => rfl
  | spawnFail => rfl

/-- ... so every configuration the start reaches holds its globals. -/
theorem Reach.gl {P : Prog} {spawn : Nat → Bool} {C C' : Cfg} (h : Reach P spawn C C') : C'.gl = C.gl := by
  induction h with
  | refl => rfl
  | step hst _ ih => exact ih.trans (TStep.gl hst)

/-- A3.6: a global's share fits its block as a later store keeps it: a lock
    block as a lock block of its type, an `arc` block as it was ... -/
theorem _root_.A2.GlobFits.grow {B B' : Nat → Option Blk} (hb : BlkLe B B') {t : Ty} {v : Val}
    (h : GlobFits B t v) : GlobFits B' t v := by
  rcases h with ⟨u, k, o, rfl, rfl, hk⟩ | ⟨u, k, p, rfl, rfl, hk⟩
  · obtain ⟨⟨u', kd, o'⟩, hk', hty, hkd, _⟩ := hb k _ hk
    simp only at hty hkd
    subst hty; subst hkd
    exact .inl ⟨_, _, _, rfl, rfl, hk'⟩
  · exact .inr ⟨_, _, _, rfl, rfl, hb.arc hk⟩

/-- ... and the configuration's sweep keeps it: a global is a root. -/
theorem _root_.A2.GlobFits.sweep {C : Cfg} {g : Nat} {t : Ty} {v : Val} (hg : C.gl g = some v)
    (h : GlobFits C.blk t v) : GlobFits C.sweep.blk t v := by
  rcases h with ⟨u, k, o, rfl, rfl, hk⟩ | ⟨u, k, p, rfl, rfl, hk⟩
  · exact .inl ⟨u, k, o, rfl, rfl,
      sweepBlk_some.mpr ⟨hk, .root (.inr ⟨g, hg⟩) (.inl (.inl ⟨none, Sub.refl _⟩))⟩⟩
  · exact .inr ⟨u, k, p, rfl, rfl,
      sweepBlk_some.mpr ⟨hk, .root (.inr ⟨g, hg⟩) (.inl (.inl ⟨some p, Sub.refl _⟩))⟩⟩

/-- **A3.6: a global stays readable**: what a global's share fits, it fits after
    every step of the configuration ... -/
theorem TStep.globFits {P : Prog} {spawn : Nat → Bool} {C C' : Cfg} (h : TStep P spawn C C') {g : Nat}
    {t : Ty} {v : Val} (hg : C.gl g = some v) (hf : GlobFits C.blk t v) : GlobFits C'.blk t v := by
  cases h with
  | @thread i th m' s' _ _ hs =>
    have hgl : m'.gl = C.gl := Step.gl hs
    exact GlobFits.sweep (C := C.put i m' s') (by show m'.gl g = some v; rw [hgl]; exact hg)
      (hf.grow (Step.grows hs).blk)
  | spawn => exact hf
  | spawnFail => exact hf

/-- ... and so in every configuration the start reaches ... -/
theorem Reach.globFits {P : Prog} {spawn : Nat → Bool} {C C' : Cfg} (h : Reach P spawn C C') {g : Nat}
    {t : Ty} {v : Val} (hg : C.gl g = some v) (hf : GlobFits C.blk t v) :
    C'.gl g = some v ∧ GlobFits C'.blk t v := by
  induction h with
  | refl => exact ⟨hg, hf⟩
  | step hst _ ih => exact ih (by rw [TStep.gl hst]; exact hg) (hst.globFits hg hf)

/-- ... so no thread's read of a start-set global, at the type the start holds
    it at, panics: it is always `EvalR.glob`, never `globP`. -/
theorem Reach.glob_noPanic {P : Prog} {spawn : Nat → Bool} {G : Globs} {s : Stmt} {nv : Nat} {C : Cfg}
    (hr : Reach P spawn (Cfg.start G s nv) C) {g : Nat} {t : Ty} {v : Val} (hg : G.gl g = some v)
    (hf : GlobFits G.blk t v) (th : Thread) : ¬ EvalR (C.view th) (.glob g t) .panic := by
  intro he
  obtain ⟨hg', hf'⟩ := hr.globFits (C := Cfg.start G s nv) hg hf
  cases he with
  | globP hn => exact hn ⟨v, hg', hf'⟩

end A3
