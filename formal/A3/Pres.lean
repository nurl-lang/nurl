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
back in, which the other threads' facts survive (`ThreadOK.move`). -/

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
      have hv : ownView (C.put i m' s') tj b =
          { ownView C tj b with alloc := union b (payPart m'.blk), nid := m'.nid, blk := m'.blk } := by
        have hgl : m'.gl = C.gl := Step.gl hst
        simp only [ownView, Cfg.put, hgl]
      have hB : BlocksAt m'.blk m'.nid := hto1.blocksAt
      rw [hv]
      refine ⟨ThreadOK.move htoj (fun x T hT k hkT => ?_) (fun k hk => ?_) (fun k hk => ?_) hgrow.nid hblk hB
        (fun k hk x T hT hkT => ?_), hboj.of_st rfl⟩
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

/-- **The configuration's sweep keeps its parts**, and leaves only blocks
    some thread's slots reach.  Every thread's view loses exactly the
    payloads of the blocks no thread reaches, none of which its own trees
    hold, and its facts survive that (`ThreadOK.sweepR`: the roots include
    its slots). -/
theorem CParts.sweep {P : Prog} {C : Cfg} {ps : List (Nat → Bool)} (hc : CParts P C ps) :
    CParts P C.sweep ps ∧ ∀ k bl, C.sweep.blk k = some bl → Reached C.sweep.vals C.sweep.blk k := by
  have hblk : ∀ k bl, C.sweep.blk k = some bl ↔ C.blk k = some bl ∧ Reached C.vals C.blk k :=
    fun _ _ => sweepBlk_some
  have halloc : ∀ i, C.sweep.alloc i = true ↔ C.alloc i = true ∧ ¬ Unreached C.vals C.blk i :=
    fun _ => sweepAlloc_true
  -- a reached payload's address is in no unreached one
  have hnu : ∀ i k bl, C.blk k = some bl → Reached C.vals C.blk k → i ∈ bl.tree.ids →
      ¬ Unreached C.vals C.blk i := by
    rintro i k bl hk hr hi ⟨k', bl', hk', hnr, hi'⟩
    exact hnr (hc.uniq k k' bl bl' i hk hk' hi hi' ▸ hr)
  refine ⟨⟨hc.len, fun i => ?_, hc.disj,
    fun j a ha i hai ⟨k, bl, hk, hik⟩ => hc.pay j a ha i hai ⟨k, bl, ((hblk k bl).mp hk).1, hik⟩,
    fun k k' bl bl' i hk hk' => hc.uniq k k' bl bl' i ((hblk k bl).mp hk).1 ((hblk k' bl').mp hk').1,
    fun j t a ht ha => ?_⟩, fun k bl hk => Reached.sweepBlk ((hblk k bl).mp hk).2⟩
  · -- every live address is on a part, or a reached payload's
    rw [halloc]
    constructor
    · rintro ⟨hCi, hnu'⟩
      rcases (hc.all i).mp hCi with h | ⟨k, bl, hk, hik⟩
      · exact .inl h
      · exact .inr ⟨k, bl, (hblk k bl).mpr ⟨hk, Classical.byContradiction fun hr => hnu' ⟨k, bl, hk, hr, hik⟩⟩,
          hik⟩
    · rintro (⟨a, ha, hai⟩ | ⟨k, bl, hk, hik⟩)
      · obtain ⟨j, hj⟩ := List.mem_iff_getElem?.mp ha
        refine ⟨(hc.all i).mpr (.inl ⟨a, ha, hai⟩), ?_⟩
        rintro ⟨k, bl, hk, _, hik⟩
        exact hc.pay j a hj i hai ⟨k, bl, hk, hik⟩
      · obtain ⟨hk0, hr⟩ := (hblk k bl).mp hk
        exact ⟨(hc.all i).mpr (.inr ⟨k, bl, hk0, hik⟩), hnu i k bl hk0 hr hik⟩
  · -- every thread keeps its facts: its view is swept from every thread's slots
    obtain ⟨hto, hbo⟩ := hc.ok j t a ht ha
    have heq : ownView C.sweep t a = (ownView C t a).sweepR C.vals := by
      simp only [ownView, Mem.sweepR, Cfg.sweep]
      congr 1
      funext i
      apply Bool.eq_iff_iff.mpr
      rw [sweepAlloc_true]
      simp only [union, Bool.or_eq_true, payPart_iff]
      constructor
      · rintro (hai | ⟨k, bl, hk, hik⟩)
        · refine ⟨.inl hai, ?_⟩
          rintro ⟨k, bl, hk, _, hik⟩
          exact hc.pay j a ha i hai ⟨k, bl, hk, hik⟩
        · obtain ⟨hk0, hr⟩ := sweepBlk_some.mp hk
          exact ⟨.inr ⟨k, bl, hk0, hik⟩, hnu i k bl hk0 hr hik⟩
      · rintro ⟨hai | ⟨k, bl, hk, hik⟩, hnu'⟩
        · exact .inl hai
        · exact .inr ⟨k, bl, sweepBlk_some.mpr ⟨hk, Classical.byContradiction fun hr => hnu' ⟨k, bl, hk, hr, hik⟩⟩,
            hik⟩
    rw [heq]
    exact ⟨hto.sweepR fun v ⟨x, o, hx⟩ => ⟨j, t, ht, x, o, hx⟩, hbo.of_st rfl⟩

/-- **A thread's step, and the sweep that ends it, keep the configuration
    invariant.** -/
theorem CInv.thread_of {P : Prog} (hP : ProgOK P) (hPc : ProgCodes P) (hR : RestrictLemma P)
    {C : Cfg} (h : CInv P C) {i : Nat} {t : Thread} {m' : Mem} {s' : Stmt}
    (hi : C.ths[i]? = some t) (hst : Step P (C.view t) t.s (.ok m' s')) :
    CInv P (C.put i m' s').sweep := by
  obtain ⟨ps, hc, _⟩ := h
  obtain ⟨ps', hc'⟩ := hc.thread_of hP hPc hR hi hst
  obtain ⟨h1, h2⟩ := hc'.sweep
  exact ⟨ps', h1, h2⟩

/-! ### No race -/

/-- The values the threads other than the `i`-th hold. -/
def Cfg.valsBut (C : Cfg) (i : Nat) (v : Val) : Prop :=
  ∃ (j : Nat) (t : Thread), j ≠ i ∧ C.ths[j]? = some t ∧ ∃ x o, t.st x = some ⟨o, some v⟩

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

theorem Cfg.vals_split {C : Cfg} {i : Nat} {t : Thread} (hi : C.ths[i]? = some t) {v : Val}
    (h : C.vals v) : (C.view t).vals v ∨ C.valsBut i v := by
  obtain ⟨j, tj, hj, x, o, hx⟩ := h
  by_cases hji : j = i
  · subst hji; rw [hi] at hj; cases hj; exact .inl ⟨x, o, hx⟩
  · exact .inr ⟨j, tj, hji, hj, x, o, hx⟩

/-- Thread `i`'s step leaves the other threads' slots as they were. -/
theorem Cfg.valsBut_put {C : Cfg} {i : Nat} {m' : Mem} {s' : Stmt} {v : Val} (h : C.valsBut i v) :
    (C.put i m' s').vals v := by
  obtain ⟨j, tj, hji, hj, x, o, hx⟩ := h
  exact ⟨j, tj, by simp only [Cfg.put]; rw [List.getElem?_set_ne (Ne.symm hji)]; exact hj, x, o, hx⟩

/-- **What a thread's next step touches**: an address of its own part; a
    read of a payload its own slots reach; or (what the sweep that ends it
    frees) a payload no other thread's slots reach. -/
theorem CParts.ctouch {P : Prog} {C : Cfg}
    {ps : List (Nat → Bool)} (hc : CParts P C ps) {q : Nat} {tq : Thread} {aq : Nat → Bool}
    (hq : C.ths[q]? = some tq) (haq : ps[q]? = some aq) {a : Nat} {b : Bool} (h : CTouch P C q tq a b) :
    aq a = true ∨ ∃ k bl, C.blk k = some bl ∧ a ∈ bl.tree.ids ∧
      ((b = false ∧ Reached (C.view tq).vals C.blk k) ∨ ¬ Reached (C.valsBut q) C.blk k) := by
  obtain ⟨hto, hbo⟩ := hc.ok q tq aq hq haq
  cases h with
  | step ht =>
    rcases touch_seen ht (m1 := ownView C tq aq) rfl rfl (TypedAt.of_threadOK hto) with
      h1 | ⟨hb, h1 | ⟨k, bl, hk, hak, hr⟩⟩
    · exact .inl (owned_part hto h1)
    · exact .inl (owned_part hto h1)
    · obtain ⟨k0, bl0, hk0, hak0, hr0⟩ := hto.blocksAt.views.rd_reached hk hak hr
      exact .inr ⟨k0, bl0, hk0, hak0, .inl ⟨hb, hr0⟩⟩
  | sweep hs =>
    obtain ⟨m', s', hst, _, hma, hsw⟩ := hs
    -- the sweep frees `a`: an unreached block's payload owns it
    have hu : Unreached (C.put q m' s').vals m'.blk a := Classical.byContradiction fun hnu => by
      have : (C.put q m' s').sweep.alloc a = true := sweepAlloc_true.mpr ⟨hma, hnu⟩
      rw [hsw] at this; cases this
    obtain ⟨k, bl, hk, hnr, hak⟩ := hu
    -- A3.2: the same block's payload owned it before the step, or the
    -- thread did (a new block's, or a lock's given back)
    rcases Step.payAt hst (hbo.of_st rfl) k a ⟨bl, hk, hak⟩ with ⟨bl0, hk0, hak0⟩ | h1
    · exact .inr ⟨k, bl0, hk0, hak0, .inr fun hr =>
        hnr (hr.mono (fun v hv => Cfg.valsBut_put hv) (Step.grows hst).blk)⟩
    · exact .inl (owned_part hto h1)

/-- **No race**: two threads never touch one address, one of them writing.
    A write is to the writer's own part, or (the sweep's frees) to a payload
    no other thread reaches; what another thread touches is on its own part,
    or a payload its own slots reach, or one the sweep after its own step
    would free — and a block is reached from some thread (`CInv`), so not
    two threads' sweeps free it. -/
theorem CInv.raceFree {P : Prog} {C : Cfg}
    (h : CInv P C) : ¬ AddrRace P C := by
  rintro ⟨i, j, ti, tj, a, w, hij, hi, hj, hti, htj⟩
  obtain ⟨ps, hc, hreach⟩ := h
  obtain ⟨ai, hai⟩ := part_of hc.len hi
  obtain ⟨aj, haj⟩ := part_of hc.len hj
  rcases hc.ctouch hi hai hti with h1 | ⟨k, bl, hk, hak, ⟨hf, _⟩ | hnr⟩
  · -- `i` writes its own part
    have hnp : ¬ PayIn C.blk a := hc.pay i ai hai a h1
    rcases hc.ctouch hj haj htj with h2 | ⟨k', bl', hk', hak', _⟩
    · rw [hc.disj i j ai aj hij hai haj a h1] at h2; cases h2
    · exact hnp ⟨k', bl', hk', hak'⟩
  · cases hf
  · -- `i`'s sweep frees a payload no other thread reaches
    rcases hc.ctouch hj haj htj with h2 | ⟨k', bl', hk', hak', ⟨_, hr'⟩ | hnr'⟩
    · exact hc.pay j aj haj a h2 ⟨k, bl, hk, hak⟩
    · have := hc.uniq k k' bl bl' a hk hk' hak hak'; subst this
      exact hnr (hr'.mono (fun v ⟨x, o, hx⟩ => ⟨j, tj, Ne.symm hij, hj, x, o, hx⟩) (BlkLe.refl _))
    · have := hc.uniq k k' bl bl' a hk hk' hak hak'; subst this
      have hr0 : Reached (fun v => (C.view ti).vals v ∨ C.valsBut i v) C.blk k :=
        (hreach k bl hk).mono (fun v hv => Cfg.vals_split hi hv) (BlkLe.refl _)
      rcases Reached.or hr0 with h3 | h3
      · exact hnr' (h3.mono (fun v ⟨x, o, hx⟩ => ⟨i, ti, hij, hi, x, o, hx⟩) (BlkLe.refl _))
      · exact hnr h3

end A3
