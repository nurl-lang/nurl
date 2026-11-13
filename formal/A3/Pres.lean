import A3.Config
import A3.Keep

/-! A3.0 — a thread's own step keeps the configuration invariant.

The step runs on the shared address space.  On the thread's own view (its
part and the payloads) it is a step too (the frame lemma `restrict`, taken
here as a hypothesis so this file builds before it), so A2's preservation
gives the thread's facts after it, up to the store a `recover` frame
remembers (`ThreadOK.ghost`).  It leaves the other threads' parts as they
were (`Step.keep`), moves `nid` up and adds blocks, whose payloads it took
from its own part, or (A3.2) checks a lock's payload out into its part or
back in, which the other threads' facts survive (`ThreadOK.move`); (Agora
#755 item 1) or reaps an orphan, moving its payload into its part.  The
marking sweep that ends the step, the reaps after it and the race claim
are in `A3.Mark`. -/

namespace A3
open A2

/-- The downward frame lemma's statement (proved in `A3.Restrict`). -/
def RestrictLemma (P : Prog) : Prop :=
  ∀ {m : Mem} {s : Stmt} {r : Res}, Step P m s r → ∀ {a2 : Nat → Bool}, Avoids m a2 → BorFree m →
    PayOff m a2 → FreshFrom a2 m.nid → ∃ r1, Step P { m with alloc := minus m.alloc a2 } s r1 ∧ ResDown a2 r r1

theorem list_set_get {α : Type} {l : List α} {i j : Nat} {x : α} (hi : i < l.length) :
    (l.set i x)[j]? = if i = j then some x else l[j]? := by
  rw [List.getElem?_set]
  by_cases h : i = j
  · subst h; simp [hi]
  · simp [h]

/-- The parts of a configuration: every address of a part is live. -/
theorem CParts.part_sub {P : Prog} {C : Cfg} {ps : List (Nat → Bool)} (hc : CParts P C ps)
    {j : Nat} {a : Nat → Bool} (ha : ps[j]? = some a) : ∀ k, a k = true → C.alloc k = true :=
  fun k hk => (hc.all k).mpr (.inl ⟨a, List.mem_of_getElem? ha, hk⟩)

/-- What a thread sees is live. -/
theorem CParts.view_sub {P : Prog} {C : Cfg} {ps : List (Nat → Bool)} (hc : CParts P C ps)
    {j : Nat} {a : Nat → Bool} (ha : ps[j]? = some a) :
    ∀ k, union a (payPart C.blk) k = true → C.alloc k = true := by
  intro k hk
  simp only [union, Bool.or_eq_true, payPart_iff] at hk
  rcases hk with hk | hk
  · exact hc.part_sub ha k hk
  · exact (hc.all k).mpr (.inr hk)

/-- Every live address is below the shared `nid` (read off any thread's
    facts). -/
theorem CParts.lt_nid {P : Prog} {C : Cfg} {ps : List (Nat → Bool)} (hc : CParts P C ps) {i : Nat}
    {t : Thread} (hi : C.ths[i]? = some t) : ∀ k, C.alloc k = true → k < C.nid := by
  intro k hk
  obtain ⟨a, ha⟩ := part_of hc.len hi
  have hpay : PayIn C.blk k → k < C.nid := fun hp =>
    ThreadOK.lt_nid (hc.ok i t a hi ha).1 k (ownView_alloc.mpr (.inr hp))
  rcases (hc.all k).mp hk with ⟨b, hb, hbk⟩ | hp
  · obtain ⟨j, hj⟩ := List.mem_iff_getElem?.mp hb
    obtain ⟨tj, htj⟩ := thread_of hc.len hj
    exact ThreadOK.lt_nid (hc.ok j tj b htj hj).1 k (ownView_alloc.mpr (.inl hbk))
  · exact hpay hp

/-- A thread's view is the shared address space without the other threads'
    parts. -/
theorem CParts.view_eq {P : Prog} {C : Cfg} {ps : List (Nat → Bool)} (hc : CParts P C ps) {i : Nat}
    {t : Thread} {a : Nat → Bool} (ha : ps[i]? = some a) :
    ownView C t a = { C.view t with alloc := minus (C.view t).alloc (minus C.alloc (union a (payPart C.blk))) } := by
  simp only [ownView, Cfg.view, minus_minus (hc.view_sub ha)]

/-- **Thread `i`'s step, on its own view**: the frame lemma takes the other
    threads' parts out of it, and A2's preservation gives the thread's facts
    after it. -/
theorem CParts.down {P : Prog} (hP : ProgOK P) (hPc : ProgCodes P) (hR : RestrictLemma P) {C : Cfg}
    {ps : List (Nat → Bool)} (hc : CParts P C ps) {i : Nat} {t : Thread} {a : Nat → Bool}
    (hi : C.ths[i]? = some t) (ha : ps[i]? = some a) {m' : Mem} {s' : Stmt}
    (hst : Step P (C.view t) t.s (.ok m' s')) :
    ThreadOK P { m' with alloc := minus m'.alloc (minus C.alloc (union a (payPart C.blk))) } s' ∧
      BorFree { m' with alloc := minus m'.alloc (minus C.alloc (union a (payPart C.blk))) } ∧
      ∀ k, minus C.alloc (union a (payPart C.blk)) k = true → m'.alloc k = C.alloc k := by
  have hlt := hc.lt_nid hi
  obtain ⟨hto, hbo⟩ := hc.ok i t a hi ha
  have hview := hc.view_eq (t := t) ha
  have hav : Avoids (C.view t) (minus C.alloc (union a (payPart C.blk))) := fun k hk =>
    minus_disj k (hto.owned k (hk.st_eq rfl))
  have hpo : PayOff (C.view t) (minus C.alloc (union a (payPart C.blk))) := fun k hk =>
    minus_disj k (ownView_alloc (t := t) (a := a).mpr (.inr (by
      rcases hk with hk | ⟨k', bl, hk', hik⟩
      · exact hk
      · exact hto.blocksAt.views.rd_ids hk' hik)))
  have hbf : BorFree (C.view t) := hbo.of_st rfl
  have hfr : FreshFrom (minus C.alloc (union a (payPart C.blk))) C.nid := fun k hk => by
    cases hk' : minus C.alloc (union a (payPart C.blk)) k with
    | false => rfl
    | true => exact absurd (hlt k (minus_le k hk')) (Nat.not_lt.mpr hk)
  obtain ⟨r1, hst1, hrd⟩ := hR hst hav hbf hpo hfr
  cases r1 with
  | panic _ => exact absurd hrd (by simp [ResDown])
  | ok m1 s1 =>
    obtain ⟨hm1, hg⟩ := hrd
    subst hm1
    rw [← hview] at hst1
    exact ⟨ThreadOK.ghost (ThreadOK.step hP hPc hto hst1) hg, Step.borFree hst1 hbo,
      Step.keep hst hbf hav hfr⟩

theorem union_minus' {a b : Nat → Bool} (h : ∀ i, b i = true → a i = true) : union (minus a b) b = a := by
  funext i
  simp only [union, minus]
  cases hb : b i <;> cases ha : a i <;> simp_all

/-- **A thread's step keeps the configuration's parts**, before the sweep
    that ends it. -/
theorem CParts.thread_of {P : Prog} (hP : ProgOK P) (hPc : ProgCodes P) (hR : RestrictLemma P)
    {C : Cfg} {ps : List (Nat → Bool)} (hc : CParts P C ps) {i : Nat} {t : Thread} {m' : Mem} {s' : Stmt}
    (hi : C.ths[i]? = some t) (hst : Step P (C.view t) t.s (.ok m' s')) :
    ∃ ps', CParts P (C.put i m' s') ps' := by
  obtain ⟨a, ha⟩ := part_of hc.len hi
  obtain ⟨hto1, hbo1, hkeep⟩ := hc.down hP hPc hR hi ha hst
  have hilen : i < C.ths.length := (List.getElem?_eq_some_iff.mp hi).1
  have hilen' : i < ps.length := by rw [hc.len]; exact hilen
  have hgrow := Step.grows hst
  have hblk : BlkLe C.blk m'.blk := hgrow.blk
  -- the other threads' part, and the thread's new part
  let a2 := minus C.alloc (union a (payPart C.blk))
  let m1 : Mem := { m' with alloc := minus m'.alloc a2 }
  let a' := minus m1.alloc (payPart m'.blk)
  have hP1 : ∀ k, PayIn m'.blk k → m1.alloc k = true := fun k hk => hto1.payAlloc hk
  have ha2 : ∀ k, a2 k = true ↔ C.alloc k = true ∧ a k = false ∧ ¬ PayIn C.blk k := by
    intro k
    simp only [a2, minus, union, Bool.and_eq_true, Bool.not_eq_true', Bool.or_eq_false_iff, payPart_false]
  -- an address of another thread's part is in `a2`
  have hoth : ∀ j b k, j ≠ i → ps[j]? = some b → b k = true → a2 k = true := by
    intro j b k hji hb hbk
    exact (ha2 k).mpr ⟨hc.part_sub hb k hbk, hc.disj j i b a hji hb ha k hbk, hc.pay j b hb k hbk⟩
  -- no new payload holds another thread's address
  have hnp : ∀ j b k, j ≠ i → ps[j]? = some b → b k = true → ¬ PayIn m'.blk k := by
    intro j b k hji hb hbk hk
    have := hP1 k hk
    simp only [m1, minus, hoth j b k hji hb hbk, Bool.not_true, Bool.and_false] at this
    cases this
  have hm : ownView (C.put i m' s') ⟨m'.st, m'.nv, s'⟩ a' = m1 := by
    simp only [ownView, Cfg.put, a', m1]
    congr 1
    exact union_minus' fun k hk => hP1 k (payPart_iff.mp hk)
  refine ⟨ps.set i a', ⟨by simp [hc.len, Cfg.put], fun k => ?_, ?_, ?_, ?_, ?_⟩⟩
  · -- every live address is on a part, or a payload's
    show m'.alloc k = true ↔ _
    constructor
    · intro hk
      cases ho : a2 k with
      | false =>
        have hm1k : m1.alloc k = true := by simp only [m1, minus, hk, ho]; rfl
        by_cases hpk : PayIn m'.blk k
        · exact .inr hpk
        · refine .inl ⟨a', List.mem_of_getElem? (i := i) (by rw [list_set_get hilen']; simp), ?_⟩
          simp only [a', minus, hm1k, payPart_false.mpr hpk]; rfl
      | true =>
        obtain ⟨hCk, hak, hnpk⟩ := (ha2 k).mp ho
        rcases (hc.all k).mp hCk with ⟨b, hb, hbk⟩ | hp
        · obtain ⟨j, hj⟩ := List.mem_iff_getElem?.mp hb
          have hji : i ≠ j := fun he => by subst he; rw [ha] at hj; cases hj; rw [hbk] at hak; cases hak
          exact .inl ⟨b, List.mem_of_getElem? (by rw [list_set_get hilen', ite_eq_right hji]; exact hj), hbk⟩
        · exact absurd hp hnpk
    · rintro (⟨b, hb, hbk⟩ | hp)
      · obtain ⟨j, hj⟩ := List.mem_iff_getElem?.mp hb
        rw [list_set_get hilen'] at hj
        by_cases hji : i = j
        · rw [ite_eq_left hji] at hj; cases hj
          exact minus_le k (minus_le k hbk)
        · rw [ite_eq_right hji] at hj
          have := hkeep k (hoth j b k (Ne.symm hji) hj hbk)
          show (Res.ok m' s').mem.alloc k = true
          rw [show (Res.ok m' s').mem = m' from rfl, this]
          exact hc.part_sub hj k hbk
      · exact minus_le k (hP1 k hp)
  · -- the parts are disjoint
    intro j k b c hjk hj hk x hx
    rw [list_set_get hilen'] at hj hk
    -- the new part is apart from every other thread's
    have hnew : ∀ q e, q ≠ i → ps[q]? = some e → e x = true → a' x = false := by
      intro q e hqi he hex
      have h2 := hoth q e x hqi he hex
      simp only [a', m1, minus, h2, Bool.not_true, Bool.and_false, Bool.false_and]
    by_cases hij : i = j
    · rw [ite_eq_left hij] at hj; cases hj
      rw [ite_eq_right (by omega)] at hk
      cases hc' : c x with
      | false => rfl
      | true => rw [hnew k c (by omega) hk hc'] at hx; cases hx
    · rw [ite_eq_right hij] at hj
      by_cases hik : i = k
      · rw [ite_eq_left hik] at hk; cases hk
        exact hnew j b (by omega) hj hx
      · rw [ite_eq_right hik] at hk; exact hc.disj j k b c hjk hj hk x hx
  · -- no part holds a payload's address
    intro j b hb x hx
    rw [list_set_get hilen'] at hb
    by_cases hij : i = j
    · rw [ite_eq_left hij] at hb; cases hb
      intro hp
      have h1 : payPart m'.blk x = true := payPart_iff.mpr hp
      have h2 : (m1.alloc x && !payPart m'.blk x) = true := hx
      rw [h1] at h2; simp at h2
    · rw [ite_eq_right hij] at hb
      exact hnp j b x (Ne.symm hij) hb hx
  · -- one payload owns each payload address
    intro k k' bl bl' x hk hk' hx hx'
    exact hto1.pay_unique hk hk' hx hx'
  · -- every thread keeps its facts
    intro j tj b htj hb
    simp only [Cfg.put] at htj
    rw [list_set_get hilen'] at hb
    rw [list_set_get hilen] at htj
    by_cases hij : i = j
    · rw [ite_eq_left hij] at hb htj; cases hb; cases htj
      rw [hm]; exact ⟨hto1, hbo1⟩
    · rw [ite_eq_right hij] at hb htj
      obtain ⟨htoj, hboj⟩ := hc.ok j tj b htj hb
      have hv : ownView (C.put i m' s') tj b = { ownView C tj b with
          alloc := union b (payPart m'.blk), nid := m'.nid, blk := m'.blk, taken := m'.taken } := by
        have hgl : m'.gl = C.gl := Step.gl hst
        simp only [ownView, Cfg.put, hgl]
      have hB : BlocksAt m'.blk m'.nid := hto1.blocksAt
      rw [hv]
      refine ⟨ThreadOK.move htoj (fun x T hT k hkT => ?_) (fun k hk => ?_) (fun k hk => ?_) hgrow.nid hblk hB
        hto1.blkCodes (fun k hk x T hT hkT => ?_), hboj.of_st rfl⟩
      · simp only [union, Bool.or_eq_true, payPart_iff]; exact .inl (owned_part htoj ⟨x, T, hT, hkT⟩)
      · simp only [union, Bool.or_eq_true, payPart_iff] at hk
        rcases hk with h | h
        · -- an address of the thread's part is in one of its trees: its part holds no payload's
          rcases htoj.cover k (ownView_alloc.mpr (.inl h)) with ho | hp
          · exact .inl ho
          · exact absurd hp (hc.pay j b hb k h)
        · exact .inr h
      · simp only [union, Bool.or_eq_true, payPart_iff]; exact .inr hk
      · exact hnp j b k (Ne.symm hij) hb (owned_part htoj ⟨x, T, hT, hkT⟩) hk

/-! ### No race -/

/-- The roots no step of the `i`-th thread changes: the values the other
    threads hold, and (A3.6) the module globals'. -/
def Cfg.rootsBut (C : Cfg) (i : Nat) (v : Val) : Prop :=
  (∃ (j : Nat) (t : Thread), j ≠ i ∧ C.ths[j]? = some t ∧ ∃ x o, t.st x = some ⟨o, some v⟩) ∨
    C.globVals v

/-- What is reached from two sets of roots is reached from one of them: a
    chain starts at one root. -/
theorem Reached.or {R1 R2 : Val → Prop} {B : Nat → Option Blk} {k : Nat}
    (h : Reached (fun v => R1 v ∨ R2 v) B k) : Reached R1 B k ∨ Reached R2 B k := by
  induction h with
  | root hv hr =>
    rcases hv with h | h
    · exact .inl (.root h hr)
    · exact .inr (.root h hr)
  | pay _ hk hr ih =>
    rcases ih with h | h
    · exact .inl (.pay h hk hr)
    · exact .inr (.pay h hk hr)

theorem Cfg.roots_split {C : Cfg} {i : Nat} {t : Thread} (hi : C.ths[i]? = some t) {v : Val}
    (h : C.roots v) : (C.view t).vals v ∨ C.rootsBut i v := by
  rcases h with ⟨j, tj, hj, x, o, hx⟩ | h
  · by_cases hji : j = i
    · subst hji; rw [hi] at hj; cases hj; exact .inl ⟨x, o, hx⟩
    · exact .inr (.inl ⟨j, tj, hji, hj, x, o, hx⟩)
  · exact .inr (.inr h)

/-- Thread `i`'s step leaves the other threads' slots as they were, and
    (A3.6) writes no global (`Step.gl`). -/
theorem Cfg.rootsBut_put {C : Cfg} {i : Nat} {m' : Mem} {s' : Stmt} (hgl : m'.gl = C.gl) {v : Val}
    (h : C.rootsBut i v) : (C.put i m' s').roots v := by
  rcases h with ⟨j, tj, hji, hj, x, o, hx⟩ | ⟨g, hg⟩
  · exact .inl ⟨j, tj, by simp only [Cfg.put]; rw [List.getElem?_set_ne (Ne.symm hji)]; exact hj, x, o, hx⟩
  · exact .inr ⟨g, by show m'.gl g = some v; rw [hgl]; exact hg⟩

/-- What the stepping thread's slots hold after its step is a root of the
    configuration it writes back. -/
theorem Cfg.put_vals {C : Cfg} {i : Nat} {t : Thread} (hi : C.ths[i]? = some t) {m' : Mem} {s' : Stmt}
    {v : Val} (h : m'.vals v) : (C.put i m' s').roots v := by
  obtain ⟨x, o, hx⟩ := h
  have hlt : i < C.ths.length := (List.getElem?_eq_some_iff.mp hi).1
  exact .inl ⟨i, ⟨m'.st, m'.nv, s'⟩, by simp [Cfg.put, hlt], x, o, hx⟩

/-- A3.2's second cut: **what other roots reach before a thread's step, the
    roots after it reach**: every block is kept (`Step.blk`), a payload that
    is read as it was, and what a lock's payload held is in it still, or in
    one of the stepping thread's slots (`Step.leafKeep`). -/
theorem _root_.A2.Reached.step {P : Prog} {m m' : Mem} {s s' : Stmt} (hst : Step P m s (.ok m' s'))
    {R R' : Val → Prop} (hR : ∀ v, R v → R' v) (hR' : ∀ v, m'.vals v → R' v) {k : Nat}
    (h : Reached R m.blk k) : Reached R' m'.blk k := by
  have hb : BlkLe m.blk m'.blk := Step.blk hst
  induction h with
  | root hv hr => exact .root (hR _ hv) (hr.grow hb)
  | pay _ hk hr ih =>
    obtain ⟨w, hw, hs, hall⟩ := hr.leaf
    rcases Step.leafKeep hst hk hw hs with ⟨bl', hk', hs'⟩ | ⟨v, hv, hs'⟩
    · exact .pay ih hk' ((hall _ hs').grow hb)
    · exact .root (hR' v hv) ((hall _ hs').grow hb)

end A3
