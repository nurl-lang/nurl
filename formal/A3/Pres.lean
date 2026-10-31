import A3.Config
import A3.Keep

/-! A3.0 — a thread's own step keeps the configuration invariant.

The step runs on the shared address space.  On the thread's own part it is
a step too (the frame lemma `restrict`, taken here as a hypothesis so this
file builds before it), so A2's preservation gives the thread's facts after
it, up to the store a `recover` frame remembers (`ThreadOK.ghost`).  It
leaves the other threads' parts as they were (`Step.keep`) and moves `nid`
up, which their facts survive (`ThreadOK.nid_le`). -/

namespace A3
open A2

/-- The downward frame lemma's statement (proved in `A3.Restrict`). -/
def RestrictLemma (P : Prog) : Prop :=
  ∀ {m : Mem} {s : Stmt} {r : Res}, Step P m s r → ∀ {a2 : Nat → Bool}, Avoids m a2 → BorFree m →
    FreshFrom a2 m.nid → ∃ r1, Step P { m with alloc := minus m.alloc a2 } s r1 ∧ ResDown a2 r r1

theorem list_set_get {α : Type} {l : List α} {i j : Nat} {x : α} (hi : i < l.length) :
    (l.set i x)[j]? = if i = j then some x else l[j]? := by
  rw [List.getElem?_set]
  by_cases h : i = j
  · subst h; simp [hi]
  · simp [h]

/-- The parts of a configuration: every address of a part is live. -/
theorem part_sub {ps : List (Nat → Bool)} {C : Cfg} (hall : ∀ i, C.alloc i = true ↔ ∃ a ∈ ps, a i = true)
    {j : Nat} {a : Nat → Bool} (ha : ps[j]? = some a) : ∀ k, a k = true → C.alloc k = true :=
  fun k hk => (hall k).mpr ⟨a, List.mem_of_getElem? ha, hk⟩

/-- Every live address is below the shared `nid`. -/
theorem CInv.lt_nid {P : Prog} {C : Cfg} (h : CInv P C) : ∀ k, C.alloc k = true → k < C.nid := by
  obtain ⟨ps, hlen, hall, _, hok⟩ := h
  intro k hk
  obtain ⟨b, hb, hbk⟩ := (hall k).mp hk
  obtain ⟨j, hj⟩ := List.mem_iff_getElem?.mp hb
  obtain ⟨tj, htj⟩ := thread_of hlen hj
  exact ThreadOK.lt_nid (hok j tj b htj hj).1 k hbk

/-- **A thread's step keeps the configuration invariant.** -/
theorem CInv.thread_of {P : Prog} (hP : ProgOK P) (hPc : ProgCodes P) (hR : RestrictLemma P)
    {C : Cfg} (h : CInv P C) {i : Nat} {t : Thread} {m' : Mem} {s' : Stmt}
    (hi : C.ths[i]? = some t) (hst : Step P (C.view t) t.s (.ok m' s')) : CInv P (C.put i m' s') := by
  have hlt := CInv.lt_nid h
  obtain ⟨ps, hlen, hall, hdisj, hok⟩ := h
  obtain ⟨a, ha⟩ := part_of hlen hi
  obtain ⟨hto, hbo⟩ := hok i t a hi ha
  have hsub := part_sub hall ha
  have hilen : i < C.ths.length := (List.getElem?_eq_some_iff.mp hi).1
  have hilen' : i < ps.length := by rw [hlen]; exact hilen
  -- the other threads' part, and what the thread is to it
  have hview : ownView C t a = { C.view t with alloc := minus (C.view t).alloc (minus C.alloc a) } := by
    simp only [ownView, Cfg.view, minus_minus hsub]
  have hav : Avoids (C.view t) (minus C.alloc a) := fun k hk => by
    have : a k = true := ThreadOK.owned hto k (hk.st_eq rfl)
    simp [minus, this]
  have hbf : BorFree (C.view t) := hbo.of_st rfl
  have hfr : FreshFrom (minus C.alloc a) C.nid := fun k hk => by
    cases hk' : minus C.alloc a k with
    | false => rfl
    | true => exact absurd (hlt k (minus_le k hk')) (Nat.not_lt.mpr hk)
  obtain ⟨r1, hst1, hrd⟩ := hR hst hav hbf hfr
  cases r1 with
  | panic _ => exact absurd hrd (by simp [ResDown])
  | ok m1 s1 =>
    obtain ⟨hm1, hg⟩ := hrd
    rw [← hview] at hst1
    have hto1 : ThreadOK P m1 s' := ThreadOK.ghost (ThreadOK.step hP hPc hto hst1) hg
    have hbo1 : BorFree m1 := Step.borFree hst1 hbo
    have hgrow := Step.grows hst
    have hkeep := Step.keep hst hbf hav hfr
    -- the new parts
    refine ⟨ps.set i m1.alloc, by simp [hlen, Cfg.put], fun k => ?_, ?_, ?_⟩
    · -- every live address is on a part
      show m'.alloc k = true ↔ _
      constructor
      · intro hk
        cases ho : minus C.alloc a k with
        | false =>
          refine ⟨m1.alloc, List.mem_of_getElem? (i := i) (by rw [list_set_get hilen']; simp), ?_⟩
          rw [hm1]
          show (m'.alloc k && !(minus C.alloc a k)) = true
          rw [hk, ho]; rfl
        | true =>
          have hCk := minus_le k ho
          have hak : a k = false := by simp [minus] at ho; exact ho.2
          obtain ⟨b, hb, hbk⟩ := (hall k).mp hCk
          obtain ⟨j, hj⟩ := List.mem_iff_getElem?.mp hb
          have hji : i ≠ j := fun he => by subst he; rw [ha] at hj; cases hj; rw [hbk] at hak; cases hak
          exact ⟨b, List.mem_of_getElem? (by rw [list_set_get hilen', if_neg hji]; exact hj), hbk⟩
      · rintro ⟨b, hb, hbk⟩
        obtain ⟨j, hj⟩ := List.mem_iff_getElem?.mp hb
        rw [list_set_get hilen'] at hj
        by_cases hji : i = j
        · rw [if_pos hji] at hj; cases hj; rw [hm1] at hbk; exact minus_le k hbk
        · rw [if_neg hji] at hj
          have hCk := part_sub hall hj k hbk
          have hak : a k = false := hdisj j i b a (Ne.symm hji) hj ha k hbk
          have ho : minus C.alloc a k = true := by simp [minus, hCk, hak]
          show (Res.ok m' s').mem.alloc k = true
          rw [hkeep k ho]; exact hCk
    · -- the parts are disjoint
      intro j k b c hjk hj hk x hx
      rw [list_set_get hilen'] at hj hk
      by_cases hij : i = j
      · rw [if_pos hij] at hj; cases hj
        rw [if_neg (by omega)] at hk
        cases hc : c x with
        | false => rfl
        | true =>
          have hCx := part_sub hall hk x hc
          have hax : a x = false := hdisj k i c a (by omega) hk ha x hc
          rw [hm1] at hx; simp [minus, hCx, hax] at hx
      · rw [if_neg hij] at hj
        by_cases hik : i = k
        · rw [if_pos hik] at hk; cases hk
          have hCx := part_sub hall hj x hx
          have hax : a x = false := hdisj j i b a (by omega) hj ha x hx
          rw [hm1]; simp [minus, hCx, hax]
        · rw [if_neg hik] at hk; exact hdisj j k b c hjk hj hk x hx
    · -- every thread keeps its facts
      intro j tj b htj hb
      simp only [Cfg.put] at htj
      rw [list_set_get hilen'] at hb
      rw [list_set_get hilen] at htj
      by_cases hij : i = j
      · rw [if_pos hij] at hb htj; cases hb; cases htj
        have hm : ownView (C.put i m' s') ⟨m'.st, m'.nv, s'⟩ m1.alloc = m1 := by
          rw [hm1]; rfl
        rw [hm]; exact ⟨hto1, hbo1⟩
      · rw [if_neg hij] at hb htj
        obtain ⟨htoj, hboj⟩ := hok j tj b htj hb
        have hn : C.nid ≤ m'.nid := hgrow.nid
        exact ⟨ThreadOK.nid_le htoj hn, hboj.of_st rfl⟩

end A3
