import A3.Touch

/-! A3.0 — the configuration invariant.

The address space is cut into one part per thread, disjoint, together the
whole of it.  On its part each thread has A2's facts (`ThreadOK`) and
address-free borrows (`BorFree`).  This file states it, shows the program's
start has it, and draws two of the claims from it: no reachable
configuration has a race (each thread touches only its own trees, which
are on its own part), and when every thread has finished nothing is
allocated (each finished thread's part is empty). -/

namespace A3
open A2

/-- Thread `t` with its part `a` of the address space. -/
def ownView (C : Cfg) (t : Thread) (a : Nat → Bool) : Mem :=
  { alloc := a, nid := C.nid, nv := t.nv, st := t.st }

/-- The configuration invariant. -/
def CInv (P : Prog) (C : Cfg) : Prop :=
  ∃ ps : List (Nat → Bool), ps.length = C.ths.length ∧
    (∀ i, C.alloc i = true ↔ ∃ a ∈ ps, a i = true) ∧
    (∀ (j k : Nat) (a b : Nat → Bool), j ≠ k → ps[j]? = some a → ps[k]? = some b →
      ∀ i, a i = true → b i = false) ∧
    ∀ (j : Nat) (t : Thread) (a : Nat → Bool), C.ths[j]? = some t → ps[j]? = some a →
      ThreadOK P (ownView C t a) t.s ∧ BorFree (ownView C t a)

/-- The start: one thread, the whole (empty) address space its part. -/
theorem CInv.init {P : Prog} {s : Stmt} {Δ : Ctx} {nv : Nat}
    (ht : StmtT P (fun _ => none) [] s Δ) (hs : s.src = true) (hsc : s.codesOK P)
    (hv : ∀ v ∈ s.vars, v < nv) : CInv P (Cfg.init s nv) := by
  refine ⟨[fun _ => false], rfl, fun i => ?_, fun j k a b hjk hj hk => ?_, fun j t a hj ha => ?_⟩
  · simp [Cfg.init]
  · cases j <;> cases k <;> simp_all
  · cases j with
    | succ j => simp [Cfg.init] at hj
    | zero =>
      simp [Cfg.init] at hj ha
      subst hj; subst ha
      exact ⟨ThreadOK.init ht hs hsc hv, fun _ _ h => by cases h⟩

theorem part_of {α β : Type} {ps : List α} {ths : List β} (hlen : ps.length = ths.length) {j : Nat}
    {t : β} (hj : ths[j]? = some t) : ∃ a, ps[j]? = some a := by
  have hlt : j < ps.length := by rw [hlen]; exact (List.getElem?_eq_some_iff.mp hj).1
  exact ⟨ps[j], List.getElem?_eq_getElem hlt⟩

theorem thread_of {α β : Type} {ps : List α} {ths : List β} (hlen : ps.length = ths.length) {j : Nat}
    {a : α} (hj : ps[j]? = some a) : ∃ t, ths[j]? = some t := by
  have hlt : j < ths.length := by rw [← hlen]; exact (List.getElem?_eq_some_iff.mp hj).1
  exact ⟨ths[j], List.getElem?_eq_getElem hlt⟩

/-- **No leak**: when every thread has finished, nothing is allocated. -/
theorem CInv.noLeak {P : Prog} {C : Cfg} (h : CInv P C) (hend : ∀ t ∈ C.ths, t.s = .skip) :
    ∀ i, C.alloc i = false := by
  obtain ⟨ps, hlen, hall, _, hok⟩ := h
  intro i
  cases hai : C.alloc i with
  | false => rfl
  | true =>
    obtain ⟨a, ha, hai'⟩ := (hall i).mp hai
    obtain ⟨j, hj⟩ := List.mem_iff_getElem?.mp ha
    obtain ⟨t, ht⟩ := thread_of hlen hj
    obtain ⟨hto, _⟩ := hok j t a ht hj
    rw [hend t (List.mem_of_getElem? ht)] at hto
    have := ThreadOK.no_leak hto i
    simp only [ownView] at this
    rw [hai'] at this; cases this

/-- **No race**: two threads never touch one address, one of them writing. -/
theorem CInv.raceFree {P : Prog} {C : Cfg} (h : CInv P C) : ¬ Race P C := by
  rintro ⟨i, j, ti, tj, a, w, hij, hi, hj, hti, htj⟩
  obtain ⟨ps, hlen, _, hdisj, hok⟩ := h
  obtain ⟨ai, hai⟩ := part_of hlen hi
  obtain ⟨aj, haj⟩ := part_of hlen hj
  obtain ⟨hoki, _⟩ := hok i ti ai hi hai
  obtain ⟨hokj, _⟩ := hok j tj aj hj haj
  have h1 := touch_owned hti (m1 := ownView C ti ai) rfl (TypedAt.of_threadOK hoki)
  have h2 := touch_owned htj (m1 := ownView C tj aj) rfl (TypedAt.of_threadOK hokj)
  have hai1 : ai a = true := ThreadOK.owned hoki a (h1.st_eq rfl)
  have haj1 : aj a = true := ThreadOK.owned hokj a (h2.st_eq rfl)
  rw [hdisj i j ai aj hij hai haj a hai1] at haj1
  cases haj1

end A3
