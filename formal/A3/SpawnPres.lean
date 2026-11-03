import A3.Assemble

/-! A3.0 — a spawn keeps the configuration invariant.

The spawner's part splits in two: the trees it moves to the new thread
(their addresses become the new thread's part), and the rest, which stays
its own.  The payloads stay shared: the new thread sees them too.  The spawner's facts after the spawn and the new thread's facts
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
    (∀ (j : Nat) (v : Val) (pt : PMode × Ty), vs[j]? = some v → fn.params[j]? = some pt →
      SharesOK m pt.2 v) ∧
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
    (∀ (j : Nat) (v : Val) (pt : PMode × Ty), vs[j]? = some v → fn.params[j]? = some pt →
      SharesIn B pt.2 v) → BlocksAt B N → (∀ i, PayIn B i → ∀ v ∈ vs, i ∉ v.ids) →
    ThreadOK P { alloc := union part (payPart B), nid := N, nv := fn.nvars, st := spawnSt fn vs, blk := B }
      (wrapParams fn.params 0 0 (.scope fn.params.length fn.body))

/-- A3.5: a spawn whose crossing check fails (proved in `A3.SpawnOld`): the
    spawner panics where the call was, over the same store. -/
def SpawnFailLemma (P : Prog) : Prop :=
  ∀ {m : Mem} {s : Stmt}, ThreadOK P m s → ∀ {K : Stmt → Stmt} {x f : Nat} {args : List Var} {k : Stmt},
    Redex s K (.letcall x f args k) → ThreadOK P m (K (.seq .panic (.letcall x f args k)))

/-- **A3.5: a failed crossing keeps the configuration invariant**: one thread's
    statement changes, and nothing else; its facts hold over the same view. -/
theorem CInv.setStmt {P : Prog} {C : Cfg} (h : CInv P C) {i : Nat} {t : Thread} (hi : C.ths[i]? = some t)
    {s' : Stmt} (hs : ∀ a, ThreadOK P (ownView C t a) t.s → ThreadOK P (ownView C t a) s') :
    CInv P { C with ths := C.ths.set i ⟨t.st, t.nv, s'⟩ } := by
  obtain ⟨ps, hc, hreach⟩ := h
  have hilen : i < C.ths.length := (List.getElem?_eq_some_iff.mp hi).1
  have hvals : ∀ v, ({ C with ths := C.ths.set i ⟨t.st, t.nv, s'⟩ } : Cfg).vals v ↔ C.vals v := by
    intro v
    constructor
    · rintro ⟨j, tj, hj, x, o, hx⟩
      simp only at hj
      rw [list_set_get hilen] at hj
      by_cases hij : i = j
      · rw [ite_eq_left hij] at hj; cases hj; exact ⟨i, t, hi, x, o, hx⟩
      · rw [ite_eq_right hij] at hj; exact ⟨j, tj, hj, x, o, hx⟩
    · rintro ⟨j, tj, hj, x, o, hx⟩
      by_cases hij : i = j
      · subst hij; rw [hi] at hj; cases hj
        exact ⟨i, ⟨t.st, t.nv, s'⟩, by simp only; rw [list_set_get hilen]; simp, x, o, hx⟩
      · exact ⟨j, tj, by simp only; rw [list_set_get hilen, ite_eq_right hij]; exact hj, x, o, hx⟩
  refine ⟨ps, ⟨by simp [hc.len], hc.all, hc.disj, hc.pay, hc.uniq, fun j tj b hj hb => ?_⟩, fun k bl hk => ?_⟩
  · simp only at hj
    rw [list_set_get hilen] at hj
    by_cases hij : i = j
    · rw [ite_eq_left hij] at hj; cases hj; subst hij
      obtain ⟨hto, hbo⟩ := hc.ok i t b hi hb
      exact ⟨hs b hto, hbo⟩
    · rw [ite_eq_right hij] at hj; exact hc.ok j tj b hj hb
  · exact (hreach k bl hk).mono (fun v hv => (hvals v).mpr hv) (BlkLe.refl _)

/-- ... and so a spawn whose crossing check fails keeps it. -/
theorem CInv.spawnFail_of {P : Prog} (hSF : SpawnFailLemma P) {C : Cfg} (h : CInv P C) {i : Nat}
    {t : Thread} (hi : C.ths[i]? = some t) {K : Stmt → Stmt} {x f : Nat} {args : List Var} {k : Stmt}
    (hK : Redex t.s K (.letcall x f args k)) :
    CInv P { C with ths := C.ths.set i ⟨t.st, t.nv, K (.seq .panic (.letcall x f args k))⟩ } :=
  h.setStmt hi fun _ hto => hSF hto hK

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

/-- A3.1: a value a spawner's slot held is still there after the arguments
    move out, or it is one of the moved ones. -/
theorem MoveArgs.keep {st st' : Var → Option Slot} {as : List Var} {vs : List Val}
    (h : MoveArgs st as vs st') :
    ∀ y o v, st y = some ⟨o, some v⟩ → st' y = some ⟨o, some v⟩ ∨ v ∈ vs := by
  induction h with
  | nil => exact fun _ _ _ h => .inl h
  | @cons st st' a as v vs ha _ ih =>
    intro y o w hy
    by_cases hya : y = a
    · subst hya; rw [ha] at hy; cases hy; exact .inr (List.mem_cons_self ..)
    · have hy' : upd st a (some ⟨true, none⟩) y = some ⟨o, some w⟩ := by
        show (if y = a then _ else st y) = _
        rw [ite_eq_right hya]; exact hy
      rcases ih y o w hy' with h | h
      · exact .inl h
      · exact .inr (List.mem_cons_of_mem _ h)

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
  obtain ⟨ps, hc, hreach⟩ := h
  obtain ⟨a, ha⟩ := part_of hc.len hi
  obtain ⟨hto, hbo⟩ := hc.ok i t a hi ha
  have hilen : i < C.ths.length := (List.getElem?_eq_some_iff.mp hi).1
  have hilen' : i < ps.length := by rw [hc.len]; exact hilen
  obtain ⟨Γ, F, Δ, _, hinv, hcds, _, _⟩ := id hto
  obtain ⟨a', hfr, hto'⟩ := hSO hto hK hsp hf hx hmv
  obtain ⟨hvlen, hwf, hsh, hslots, hvdisj⟩ := hSA hto hK hsp hf hmv
  -- the spawner's view: its part and the payloads
  let A := union a (payPart C.blk)
  have hA : ∀ k, A k = true ↔ a k = true ∨ PayIn C.blk k := fun k => ownView_alloc (t := t)
  -- the moved trees: owned slots of the spawner
  have hown : ∀ v ∈ vs, ∃ a0, t.st a0 = some ⟨true, some v⟩ := fun v hv => by
    obtain ⟨j, hj⟩ := List.mem_iff_getElem?.mp hv
    obtain ⟨a0, _, h0⟩ := hslots j v hj
    exact ⟨a0, h0⟩
  have hids : ∀ v ∈ vs, ∀ k ∈ v.ids, A k = true ∧ k < C.nid := fun v hv k hk => by
    obtain ⟨a0, h0⟩ := hown v hv
    exact hinv.heap.alloc a0 v h0 k hk
  have hvnp : ∀ v ∈ vs, ∀ k ∈ v.ids, ¬ PayIn C.blk k := fun v hv k hk => by
    obtain ⟨a0, h0⟩ := hown v hv
    exact hinv.heap.notPay h0 hk
  -- the payloads stay on the spawner's view
  have hPa' : ∀ k, PayIn C.blk k → a' k = true := fun k hk => by
    rw [FreesL.other hfr (fun hm => by
      obtain ⟨v, hv, hkv⟩ := mem_idsL_iff.mp hm
      exact hvnp v hv k hkv hk)]
    exact (hA k).mpr (.inr hk)
  -- the spawner keeps `aS`, the new thread gets `aN`
  let aS : Nat → Bool := minus a' (payPart C.blk)
  let aN : Nat → Bool := minus A a'
  have hpart : ∀ k, aN k = true ↔ ∃ v ∈ vs, k ∈ v.ids := fun k => by
    constructor
    · intro hk
      simp only [aN, minus, Bool.and_eq_true, Bool.not_eq_true'] at hk
      by_cases hm : k ∈ idsL vs
      · exact mem_idsL_iff.mp hm
      · have h0 : A k = false := (FreesL.other hfr hm).symm.trans hk.2
        rw [hk.1] at h0; cases h0
    · rintro ⟨v, hv, hk⟩
      have h1 := (hids v hv k hk).1
      have h2 := FreesL.freed hfr (mem_idsL_iff.mpr ⟨v, hv, hk⟩)
      simp only [aN, minus, h1, h2]; rfl
  have haSa : ∀ k, aS k = true → a k = true := fun k hk => by
    simp only [aS, minus, Bool.and_eq_true, Bool.not_eq_true', payPart_false] at hk
    rcases (hA k).mp (FreesL.le hfr hk.1) with h | h
    · exact h
    · exact absurd h hk.2
  have haNa : ∀ k, aN k = true → a k = true := fun k hk => by
    simp only [aN, minus, Bool.and_eq_true, Bool.not_eq_true'] at hk
    rcases (hA k).mp hk.1 with h | h
    · exact h
    · rw [hPa' k h] at hk; cases hk.2
  have hsplit : ∀ k, a k = true → aS k = true ∨ aN k = true := fun k hk => by
    have hnp := hc.pay i a ha k hk
    cases ha' : a' k with
    | true => exact .inl (by simp only [aS, minus, ha', payPart_false.mpr hnp]; rfl)
    | false => exact .inr (by simp only [aN, minus, (hA k).mpr (.inl hk), ha']; rfl)
  have hSN : ∀ k, aS k = true → aN k = false := fun k hk => by
    simp only [aS, minus, Bool.and_eq_true] at hk
    simp [aN, minus, hk.1]
  have htoN := hNT (B := C.blk) hsp hf hvlen hwf
    (fun v hv => by obtain ⟨a0, h0⟩ := hown v hv; exact hinv.heap.nodup a0 v h0) hvdisj
    (fun v hv => by obtain ⟨a0, h0⟩ := hown v hv; exact hinv.heap.self a0 v h0)
    (fun v hv => by obtain ⟨a0, h0⟩ := hown v hv; exact hinv.pkgs a0 _ v h0 rfl)
    (fun v hv => by obtain ⟨a0, h0⟩ := hown v hv; exact memCodes_iff.mp hcds a0 true v h0)
    hpart (fun v hv k hk => (hids v hv k hk).2) hsh hto.blocksAt
    (fun k hk v hv hkv => hvnp v hv k hkv hk)
  have hlen' : (C.ths.set i ⟨upd st' x (some ⟨false, some (.int 0)⟩), t.nv, K (.scope x k)⟩).length =
      ps.length := by rw [List.length_set, hc.len]
  -- (A3.1) every value a slot held is still in one, and so every block stays reached
  have hvals : ∀ v, C.vals v → Cfg.vals { C with ths := C.ths.set i ⟨upd st' x (some ⟨false, some (.int 0)⟩),
      t.nv, K (.scope x k)⟩ ++ [⟨spawnSt fn vs, fn.nvars,
        wrapParams fn.params 0 0 (.scope fn.params.length fn.body)⟩] } v := by
    rintro v ⟨j, tj, hj, y, o, hy⟩
    have hjl : j < C.ths.length := (List.getElem?_eq_some_iff.mp hj).1
    by_cases hji : j = i
    · subst hji; rw [hi] at hj; cases hj
      have hyx : y ≠ x := fun he => by rw [he, hx] at hy; cases hy
      rcases MoveArgs.keep hmv y o v hy with h' | h'
      · refine ⟨j, _, by rw [get_set_append hilen, ite_eq_left hjl, ite_eq_left rfl], y, o, ?_⟩
        show (if y = x then _ else st' y) = _
        rw [ite_eq_right hyx]; exact h'
      · obtain ⟨n, hn⟩ := List.mem_iff_getElem?.mp h'
        have hnl : n < fn.params.length := by rw [← hvlen]; exact (List.getElem?_eq_some_iff.mp hn).1
        refine ⟨C.ths.length, _, by rw [get_set_append hilen]; simp; rfl, n, true, ?_⟩
        show spawnSt fn vs n = _
        simp only [spawnSt, Nat.ne_of_lt hnl, ↓reduceIte, hn, Option.map_some]
    · exact ⟨j, tj, by rw [get_set_append hilen, ite_eq_left hjl, ite_eq_right (Ne.symm hji)]; exact hj, y, o, hy⟩
  refine ⟨ps.set i aS ++ [aN], ⟨by simp [hc.len], fun k => ?_, ?_, ?_, hc.uniq, ?_⟩,
    fun k' bl hk' => (hreach k' bl hk').of_roots fun v hv _ _ => hvals v hv⟩
  · -- every live address is on a part, or a payload's
    constructor
    · intro hk
      rcases (hc.all k).mp hk with ⟨b, hb, hbk⟩ | hp
      · obtain ⟨j, hj⟩ := List.mem_iff_getElem?.mp hb
        by_cases hji : i = j
        · subst hji; rw [ha] at hj; cases hj
          rcases hsplit k hbk with h | h
          · exact .inl ⟨aS, List.mem_of_getElem? (i := i) (by rw [get_set_append hilen']; simp [hilen']), h⟩
          · exact .inl ⟨aN, List.mem_of_getElem? (i := ps.length) (by rw [get_set_append hilen']; simp), h⟩
        · have hjl : j < ps.length := (List.getElem?_eq_some_iff.mp hj).1
          exact .inl ⟨b, List.mem_of_getElem? (i := j)
            (by rw [get_set_append hilen', ite_eq_left hjl, ite_eq_right hji]; exact hj), hbk⟩
      · exact .inr hp
    · rintro (⟨b, hb, hbk⟩ | hp)
      · obtain ⟨j, hj⟩ := List.mem_iff_getElem?.mp hb
        rw [get_set_append hilen'] at hj
        by_cases hjl : j < ps.length
        · rw [ite_eq_left hjl] at hj
          by_cases hji : i = j
          · rw [ite_eq_left hji] at hj; cases hj; exact hc.part_sub ha k (haSa k hbk)
          · rw [ite_eq_right hji] at hj; exact hc.part_sub hj k hbk
        · rw [ite_eq_right hjl] at hj
          by_cases hje : j = ps.length
          · rw [ite_eq_left hje] at hj; cases hj; exact hc.part_sub ha k (haNa k hbk)
          · rw [ite_eq_right hje] at hj; cases hj
      · exact (hc.all k).mpr (.inr hp)
  · -- the parts are disjoint
    intro j j' b c hjj hj hj' z hz
    rw [get_set_append hilen'] at hj hj'
    have side : ∀ (q : Nat) (e : Nat → Bool), (if q < ps.length then (if i = q then some aS else ps[q]?)
        else if q = ps.length then some aN else none) = some e →
        (q = i ∧ e = aS) ∨ (q = ps.length ∧ e = aN) ∨ (q ≠ i ∧ q < ps.length ∧ ps[q]? = some e) := by
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
    · rw [hbe] at hz; rw [hce]; exact hSN z hz
    · rw [hbe] at hz; exact hc.disj i j' a c (Ne.symm hji') ha hjp' z (haSa z hz)
    · rw [hbe] at hz; rw [hce]
      cases h' : aS z with
      | false => rfl
      | true => rw [hSN z h'] at hz; cases hz
    · exact absurd (hjl.trans hjl'.symm) hjj
    · rw [hbe] at hz; exact hc.disj i j' a c (Ne.symm hji') ha hjp' z (haNa z hz)
    · rw [hce]
      cases hc' : aS z with
      | false => rfl
      | true =>
        have := hc.disj j i b a hji hjp ha z hz
        rw [haSa z hc'] at this; cases this
    · rw [hce]
      cases hc' : aN z with
      | false => rfl
      | true =>
        have := hc.disj j i b a hji hjp ha z hz
        rw [haNa z hc'] at this; cases this
    · exact hc.disj j j' b c hjj hjp hjp' z hz
  · -- no part holds a payload's address
    intro j b hb z hz
    rw [get_set_append hilen'] at hb
    by_cases hjl : j < ps.length
    · rw [ite_eq_left hjl] at hb
      by_cases hij : i = j
      · rw [ite_eq_left hij] at hb; cases hb; exact hc.pay i a ha z (haSa z hz)
      · rw [ite_eq_right hij] at hb; exact hc.pay j b hb z hz
    · rw [ite_eq_right hjl] at hb
      by_cases hje : j = ps.length
      · rw [ite_eq_left hje] at hb; cases hb; exact hc.pay i a ha z (haNa z hz)
      · rw [ite_eq_right hje] at hb; cases hb
  · -- every thread has its facts
    intro j t0 b ht0 hb
    rw [get_set_append hilen'] at hb
    rw [list_append_get, hlen', list_set_get hilen] at ht0
    by_cases hjl : j < ps.length
    · rw [ite_eq_left hjl] at hb ht0
      by_cases hij : i = j
      · rw [ite_eq_left hij] at hb ht0; cases hb; cases ht0
        have hv : ownView { C with ths := C.ths.set i ⟨upd st' x (some ⟨false, some (.int 0)⟩), t.nv,
            K (.scope x k)⟩ ++ [⟨spawnSt fn vs, fn.nvars, wrapParams fn.params 0 0 (.scope fn.params.length fn.body)⟩] }
            ⟨upd st' x (some ⟨false, some (.int 0)⟩), t.nv, K (.scope x k)⟩ aS =
            { ownView C t a with alloc := a', st := upd st' x (some ⟨false, some (.int 0)⟩) } := by
          simp only [ownView, aS]
          congr 1
          exact union_minus' fun k hk => hPa' k (payPart_iff.mp hk)
        rw [hv]
        refine ⟨hto', fun y v hy => ?_⟩
        simp only [upd] at hy
        split at hy
        · cases hy; rfl
        · rcases MoveArgs.slot hmv y _ hy with h0 | h0
          · exact hbo y v h0
          · cases h0
      · rw [ite_eq_right hij] at hb ht0
        exact hc.ok j t0 b ht0 hb
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

/-- **A3.0**, given the two frame lemmas and the spawn case's three (A3.5:
    and a failed crossing's). -/
theorem claim_from (hR : ∀ P, RestrictLemma P) (hL : ∀ P, LiftLemma P)
    (hSO : ∀ P spawn, ProgOK P → ProgCodes P → SpawnOK P spawn → SpawnerLemma P spawn)
    (hSA : ∀ P spawn, ProgOK P → SpawnOK P spawn → SpawnArgsLemma P spawn)
    (hNT : ∀ P spawn, ProgOK P → ProgCodes P → SpawnOK P spawn → NewThreadLemma P spawn)
    (hSF : ∀ P, SpawnFailLemma P) : Claim :=
  claim_of hR hL (fun P spawn hP hPc hS {_ _ _ _ _ _ _ _ _ _ _} h hi hK hsp hf hx hmv =>
    CInv.spawn_of (hSO P spawn hP hPc hS) (hSA P spawn hP hS) (hNT P spawn hP hPc hS) h hi hK hsp hf hx hmv)
    (fun P {_ _ _ _ _ _ _ _} h hi hK => CInv.spawnFail_of (hSF P) h hi hK)

end A3
