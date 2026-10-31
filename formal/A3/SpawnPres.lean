import A3.Assemble

/-! A3.0 — a spawn keeps the configuration invariant.

The spawner's part splits in two: the trees it moves to the new thread
(their addresses become the new thread's part), and the rest, which stays
its own.  The spawner's facts after the spawn and the new thread's facts
are the spawn case's two lemmas (`A3.SpawnOld`, `A3.SpawnNew`), taken here
as hypotheses in the shapes they are proved in. -/

namespace A3
open A2

/-- The spawner's side (proved in `A3.SpawnOld`). -/
def SpawnerLemma (P : Prog) (spawn : Nat → Bool) : Prop :=
  ∀ {m : Mem} {s : Stmt}, ThreadOK P m s → ∀ {K : Stmt → Stmt} {x f : Nat} {args : List Var} {k : Stmt}
    {fn : Fn} {vs : List Val} {st' : Var → Option Slot},
    Redex s K (.letcall x f args k) → spawn f = true → P[f]? = some fn → m.st x = none →
    MoveArgs m.st args vs st' →
    ∃ a', FreesL m.alloc vs a' ∧
      ThreadOK P { m with alloc := a', st := upd st' x (some ⟨false, some (.int 0)⟩) } (K (.scope x k))

/-- What the moved arguments are (proved in `A3.SpawnOld`). -/
def SpawnArgsLemma (P : Prog) (spawn : Nat → Bool) : Prop :=
  ∀ {m : Mem} {s : Stmt}, ThreadOK P m s → ∀ {K : Stmt → Stmt} {x f : Nat} {args : List Var} {k : Stmt}
    {fn : Fn} {vs : List Val} {st' : Var → Option Slot},
    Redex s K (.letcall x f args k) → spawn f = true → P[f]? = some fn → MoveArgs m.st args vs st' →
    vs.length = fn.params.length ∧
    (∀ (j : Nat) (v : Val) (pt : PMode × Ty), vs[j]? = some v → fn.params[j]? = some pt → WFv pt.2 v) ∧
    (∀ (j : Nat) (v : Val), vs[j]? = some v → ∃ a, args[j]? = some a ∧ m.st a = some ⟨true, some v⟩) ∧
    (∀ (j k : Nat) (v w : Val), j ≠ k → vs[j]? = some v → vs[k]? = some w → ∀ i ∈ v.ids, i ∉ w.ids)

/-- The new thread's side (proved in `A3.SpawnNew`). -/
def NewThreadLemma (P : Prog) (spawn : Nat → Bool) : Prop :=
  ∀ {f : Nat} {fn : Fn}, spawn f = true → P[f]? = some fn → ∀ {vs : List Val},
    vs.length = fn.params.length →
    (∀ (j : Nat) (v : Val) (pt : PMode × Ty), vs[j]? = some v → fn.params[j]? = some pt → WFv pt.2 v) →
    (∀ v ∈ vs, v.ids.Nodup) →
    (∀ (j k : Nat) (v w : Val), j ≠ k → vs[j]? = some v → vs[k]? = some w → ∀ i ∈ v.ids, i ∉ w.ids) →
    (∀ v ∈ vs, SelfFree v) → (∀ v ∈ vs, PkgsOK v) → (∀ v ∈ vs, PkgOK P v) →
    ∀ {part : Nat → Bool}, (∀ i, part i = true ↔ ∃ v ∈ vs, i ∈ v.ids) →
    ∀ {N : Nat}, (∀ v ∈ vs, ∀ i ∈ v.ids, i < N) → ∀ {B : Nat → Option Blk},
    ThreadOK P { alloc := part, nid := N, nv := fn.nvars, st := spawnSt fn vs, blk := B }
      (wrapParams fn.params 0 0 (.scope fn.params.length fn.body))

theorem MoveArgs.slot {st st' : Var → Option Slot} {as : List Var} {vs : List Val}
    (h : MoveArgs st as vs st') : ∀ y sl, st' y = some sl → st y = some sl ∨ sl = ⟨true, none⟩ := by
  induction h with
  | nil => exact fun _ _ h => .inl h
  | cons _ _ ih =>
    intro y sl hy
    rcases ih y sl hy with h | h
    · simp only [upd] at h
      split at h
      · cases h; exact .inr rfl
      · exact .inl h
    · exact .inr h

theorem list_append_get {α : Type} {l : List α} {y : α} {j : Nat} :
    (l ++ [y])[j]? = if j < l.length then l[j]? else if j = l.length then some y else none := by
  by_cases h : j < l.length
  · rw [ite_eq_left h, List.getElem?_append_left h]
  · rw [ite_eq_right h, List.getElem?_append_right (by omega)]
    by_cases he : j = l.length
    · subst he; simp
    · rw [ite_eq_right he]; simp; omega

/-- A list with one element replaced and one appended, by index. -/
theorem get_set_append {α : Type} {l : List α} {i : Nat} {x y : α} (hi : i < l.length) (j : Nat) :
    (l.set i x ++ [y])[j]? =
      if j < l.length then (if i = j then some x else l[j]?) else if j = l.length then some y else none := by
  rw [list_append_get]
  simp only [List.length_set]
  by_cases hj : j < l.length
  · rw [ite_eq_left hj, ite_eq_left hj, list_set_get hi]
  · rw [ite_eq_right hj, ite_eq_right hj]

/-- **A spawn keeps the configuration invariant.** -/
theorem CInv.spawn_of {P : Prog} {spawn : Nat → Bool} (hSO : SpawnerLemma P spawn)
    (hSA : SpawnArgsLemma P spawn) (hNT : NewThreadLemma P spawn)
    {C : Cfg} {i : Nat} {t : Thread} {K : Stmt → Stmt} {x f : Nat} {args : List Var}
    {k : Stmt} {fn : Fn} {vs : List Val} {st' : Var → Option Slot}
    (h : CInv P C) (hi : C.ths[i]? = some t) (hK : Redex t.s K (.letcall x f args k))
    (hsp : spawn f = true) (hf : P[f]? = some fn) (hx : t.st x = none) (hmv : MoveArgs t.st args vs st') :
    CInv P { C with ths := C.ths.set i ⟨upd st' x (some ⟨false, some (.int 0)⟩), t.nv, K (.scope x k)⟩ ++
                      [⟨spawnSt fn vs, fn.nvars,
                        wrapParams fn.params 0 0 (.scope fn.params.length fn.body)⟩] } := by
  obtain ⟨ps, hlen, hall, hdisj, hok⟩ := h
  obtain ⟨a, ha⟩ := part_of hlen hi
  obtain ⟨hto, hbo⟩ := hok i t a hi ha
  have hilen : i < C.ths.length := (List.getElem?_eq_some_iff.mp hi).1
  have hilen' : i < ps.length := by rw [hlen]; exact hilen
  obtain ⟨Γ, F, Δ, _, hinv, hcds, _, _⟩ := id hto
  obtain ⟨a', hfr, hto'⟩ := hSO hto hK hsp hf hx hmv
  obtain ⟨hvlen, hwf, hslots, hvdisj⟩ := hSA hto hK hsp hf hmv
  -- the moved trees: owned slots of the spawner
  have hown : ∀ v ∈ vs, ∃ a0, t.st a0 = some ⟨true, some v⟩ := fun v hv => by
    obtain ⟨j, hj⟩ := List.mem_iff_getElem?.mp hv
    obtain ⟨a0, _, h0⟩ := hslots j v hj
    exact ⟨a0, h0⟩
  have hids : ∀ v ∈ vs, ∀ k ∈ v.ids, a k = true ∧ k < C.nid := fun v hv k hk => by
    obtain ⟨a0, h0⟩ := hown v hv
    exact hinv.heap.alloc a0 v h0 k hk
  -- the new thread's part
  let aN : Nat → Bool := minus a a'
  have hpart : ∀ k, aN k = true ↔ ∃ v ∈ vs, k ∈ v.ids := fun k => by
    constructor
    · intro hk
      simp only [aN, minus, Bool.and_eq_true, Bool.not_eq_true'] at hk
      by_cases hm : k ∈ idsL vs
      · exact mem_idsL_iff.mp hm
      · have h0 : a k = false := (FreesL.other hfr hm).symm.trans hk.2
        rw [hk.1] at h0; cases h0
    · rintro ⟨v, hv, hk⟩
      have h1 := (hids v hv k hk).1
      have h2 := FreesL.freed hfr (mem_idsL_iff.mpr ⟨v, hv, hk⟩)
      simp only [aN, minus, h1, h2]; rfl
  have htoN := hNT (B := C.blk) hsp hf hvlen hwf
    (fun v hv => by obtain ⟨a0, h0⟩ := hown v hv; exact hinv.heap.nodup a0 v h0) hvdisj
    (fun v hv => by obtain ⟨a0, h0⟩ := hown v hv; exact hinv.heap.self a0 v h0)
    (fun v hv => by obtain ⟨a0, h0⟩ := hown v hv; exact hinv.pkgs a0 _ v h0 rfl)
    (fun v hv => by obtain ⟨a0, h0⟩ := hown v hv; exact memCodes_iff.mp hcds a0 true v h0)
    hpart (fun v hv k hk => (hids v hv k hk).2)
  -- the spawner keeps `a'`, the new thread gets `aN`
  have ha'a : ∀ k, a' k = true → a k = true := fun k hk => FreesL.le hfr hk
  have haNa : ∀ k, aN k = true → a k = true := fun k hk => minus_le k hk
  have hsub := part_sub hall ha
  have hlen' : (C.ths.set i ⟨upd st' x (some ⟨false, some (.int 0)⟩), t.nv, K (.scope x k)⟩).length =
      ps.length := by rw [List.length_set, hlen]
  refine ⟨ps.set i a' ++ [aN], by simp [hlen], fun k => ?_, ?_, ?_⟩
  · -- every live address is on a part
    constructor
    · intro hk
      obtain ⟨b, hb, hbk⟩ := (hall k).mp hk
      obtain ⟨j, hj⟩ := List.mem_iff_getElem?.mp hb
      by_cases hji : i = j
      · subst hji; rw [ha] at hj; cases hj
        cases ha' : a' k with
        | true =>
          exact ⟨a', List.mem_of_getElem? (i := i) (by rw [get_set_append hilen']; simp [hilen']), ha'⟩
        | false =>
          refine ⟨aN, List.mem_of_getElem? (i := ps.length) (by rw [get_set_append hilen']; simp), ?_⟩
          show (a k && !a' k) = true
          rw [hbk, ha']; rfl
      · have hjl : j < ps.length := (List.getElem?_eq_some_iff.mp hj).1
        exact ⟨b, List.mem_of_getElem? (i := j) (by rw [get_set_append hilen', ite_eq_left hjl, ite_eq_right hji]; exact hj), hbk⟩
    · rintro ⟨b, hb, hbk⟩
      obtain ⟨j, hj⟩ := List.mem_iff_getElem?.mp hb
      rw [get_set_append hilen'] at hj
      by_cases hjl : j < ps.length
      · rw [ite_eq_left hjl] at hj
        by_cases hji : i = j
        · rw [ite_eq_left hji] at hj; cases hj; exact hsub k (ha'a k hbk)
        · rw [ite_eq_right hji] at hj; exact part_sub hall hj k hbk
      · rw [ite_eq_right hjl] at hj
        by_cases hje : j = ps.length
        · rw [ite_eq_left hje] at hj; cases hj; exact hsub k (haNa k hbk)
        · rw [ite_eq_right hje] at hj; cases hj
  · -- the parts are disjoint
    intro j j' b c hjj hj hj' z hz
    rw [get_set_append hilen'] at hj hj'
    -- what each index holds, and that it lies inside `a` or another thread's part
    have side : ∀ (q : Nat) (e : Nat → Bool), (if q < ps.length then (if i = q then some a' else ps[q]?)
        else if q = ps.length then some aN else none) = some e →
        (q = i ∧ e = a') ∨ (q = ps.length ∧ e = aN) ∨ (q ≠ i ∧ q < ps.length ∧ ps[q]? = some e) := by
      intro q e he
      by_cases hq : q < ps.length
      · rw [ite_eq_left hq] at he
        by_cases hiq : i = q
        · rw [ite_eq_left hiq] at he; cases he; exact .inl ⟨hiq.symm, rfl⟩
        · rw [ite_eq_right hiq] at he; exact .inr (.inr ⟨Ne.symm hiq, hq, he⟩)
      · rw [ite_eq_right hq] at he
        by_cases hq' : q = ps.length
        · rw [ite_eq_left hq'] at he; cases he; exact .inr (.inl ⟨hq', rfl⟩)
        · rw [ite_eq_right hq'] at he; cases he
    rcases side j b hj with ⟨hji, hbe⟩ | ⟨hjl, hbe⟩ | ⟨hji, _, hjp⟩ <;>
    rcases side j' c hj' with ⟨hji', hce⟩ | ⟨hjl', hce⟩ | ⟨hji', _, hjp'⟩
    · exact absurd (hji.trans hji'.symm) hjj
    · rw [hbe] at hz; rw [hce]
      show (a z && !a' z) = false
      rw [hz]; simp
    · rw [hbe] at hz; exact hdisj i j' a c (Ne.symm hji') ha hjp' z (ha'a z hz)
    · rw [hbe] at hz; rw [hce]
      simp only [aN, minus, Bool.and_eq_true, Bool.not_eq_true'] at hz; exact hz.2
    · exact absurd (hjl.trans hjl'.symm) hjj
    · rw [hbe] at hz; exact hdisj i j' a c (Ne.symm hji') ha hjp' z (haNa z hz)
    · rw [hce]
      cases hc : a' z with
      | false => rfl
      | true =>
        have := hdisj j i b a hji hjp ha z hz
        rw [ha'a z hc] at this; cases this
    · rw [hce]
      show (a z && !a' z) = false
      rw [hdisj j i b a hji hjp ha z hz]; rfl
    · exact hdisj j j' b c hjj hjp hjp' z hz
  · -- every thread has its facts
    intro j t0 b ht0 hb
    rw [get_set_append hilen'] at hb
    rw [list_append_get, hlen', list_set_get hilen] at ht0
    by_cases hjl : j < ps.length
    · rw [ite_eq_left hjl] at hb ht0
      by_cases hij : i = j
      · rw [ite_eq_left hij] at hb ht0; cases hb; cases ht0
        refine ⟨hto', fun y v hy => ?_⟩
        simp only [ownView, upd] at hy
        split at hy
        · cases hy; rfl
        · rcases MoveArgs.slot hmv y _ hy with h0 | h0
          · exact hbo y v h0
          · cases h0
      · rw [ite_eq_right hij] at hb ht0
        exact hok j t0 b ht0 hb
    · rw [ite_eq_right hjl] at hb ht0
      by_cases hje : j = ps.length
      · rw [ite_eq_left hje] at hb ht0; cases hb; cases ht0
        refine ⟨htoN, fun y v hy => ?_⟩
        simp only [ownView, spawnSt] at hy
        split at hy
        · cases hy
        · cases hv : vs[y]? with
          | none => rw [hv] at hy; cases hy
          | some w => rw [hv] at hy; cases hy
      · rw [ite_eq_right hje] at hb; cases hb

/-- **A3.0**, given the two frame lemmas and the spawn case's three. -/
theorem claim_from (hR : ∀ P, RestrictLemma P) (hL : ∀ P, LiftLemma P)
    (hSO : ∀ P spawn, ProgOK P → ProgCodes P → SpawnOK P spawn → SpawnerLemma P spawn)
    (hSA : ∀ P spawn, ProgOK P → SpawnOK P spawn → SpawnArgsLemma P spawn)
    (hNT : ∀ P spawn, ProgOK P → ProgCodes P → SpawnOK P spawn → NewThreadLemma P spawn) : Claim :=
  claim_of hR hL fun P spawn hP hPc hS {_ _ _ _ _ _ _ _ _ _ _} h hi hK hsp hf hx hmv =>
    CInv.spawn_of (hSO P spawn hP hPc hS) (hSA P spawn hP hS) (hNT P spawn hP hPc hS) h hi hK hsp hf hx hmv

end A3
