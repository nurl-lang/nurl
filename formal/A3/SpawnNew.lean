import A3.Rel

/-! A3.0 — the thread a spawn starts.

`TStep.spawn` runs the spawned function's body on a new thread, inside its
parameters' scopes and its result's (`wrapParams fn.params 0 0 (.scope n
fn.body)`, `n` the number of parameters), with the bindings `spawnSt`:
parameter `j` owns the `j`-th tree moved to it, and the result slot is bound
and empty.  Its own part of the address space is the addresses of those
trees, and it sees the shared `nid`.

A2 types the body in the callee's own view of its parameters (`sigCtx`).
Every parameter of a spawned function is a `sink` of a type that holds no
views, so that view says of each parameter only that it owns a tree of its
type, and depends on nothing: what the moved trees are.  The result is an
integer, a borrow that is not live until the body sets it.  So the new
thread is a call's inside with nothing around it: no borrowed parameter, and
nothing lent out. -/

namespace A3
open A2

/-- A type that holds no views holds no closure. -/
theorem hasFn_of_holdsView {t : Ty} (h : t.holdsView = false) : t.hasFn = false := by
  cases hf : t.hasFn
  · rfl
  · rw [hasFn_holdsView hf] at h; cases h

/-! ### The spawned function's own context -/

/-- A parameter of a spawned function: a `sink` of a type that holds no views. -/
theorem spawn_param {fn : Fn} (hpar : ∀ pt ∈ fn.params, pt.1 = .sink ∧ pt.2.holdsView = false)
    {v : Nat} (hv : v < fn.params.length) :
    ∃ t, fn.params[v]? = some (.sink, t) ∧ t.holdsView = false := by
  obtain ⟨p, hp⟩ : ∃ p, fn.params[v]? = some p := ⟨_, List.getElem?_eq_getElem hv⟩
  obtain ⟨h1, h2⟩ := hpar p (List.mem_of_getElem? hp)
  obtain ⟨pm, t⟩ := p
  simp only at h1 h2
  subst h1
  exact ⟨t, hp, h2⟩

/-- Its entry: an owner that depends on nothing. -/
theorem sigCtx_sink {fn : Fn} {v : Nat} {t : Ty} (hp : fn.params[v]? = some (.sink, t))
    (ht : t.holdsView = false) : sigCtx fn v = some ⟨t, .own, true, [], [], false, false⟩ := by
  rw [sigCtx_of hp]
  simp [paramE, hasFn_of_holdsView ht]

/-- The entries of a spawned function's own context: its parameters', and
    its result's. -/
theorem sigCtx_spawn {fn : Fn} (hpar : ∀ pt ∈ fn.params, pt.1 = .sink ∧ pt.2.holdsView = false)
    {v : Nat} {E : Entry} (hv : sigCtx fn v = some E) :
    (∃ t, fn.params[v]? = some (.sink, t) ∧ t.holdsView = false ∧ E = ⟨t, .own, true, [], [], false, false⟩) ∨
    (v = fn.params.length ∧ E = ⟨fn.resTy, resMode fn, false, [], [], false, false⟩) := by
  rcases Nat.lt_trichotomy v fn.params.length with h | h | h
  · obtain ⟨t, hp, ht⟩ := spawn_param hpar h
    rw [sigCtx_sink hp ht] at hv
    exact .inl ⟨t, hp, ht, (Option.some.inj hv).symm⟩
  · subst h
    rw [sigCtx_res] at hv
    exact .inr ⟨rfl, (Option.some.inj hv).symm⟩
  · rw [sigCtx_none h] at hv; cases hv

/-- None of them is a borrowed parameter or an `inout` one. -/
theorem sigCtx_spawn_mode {fn : Fn} (hpar : ∀ pt ∈ fn.params, pt.1 = .sink ∧ pt.2.holdsView = false)
    {v : Nat} {E : Entry} (hv : sigCtx fn v = some E) :
    E.mode ≠ .rootb ∧ ∀ b, E.mode ≠ .inout b := by
  rcases sigCtx_spawn hpar hv with ⟨t, _, _, rfl⟩ | ⟨_, rfl⟩
  · exact ⟨fun h => (by cases h), fun b h => (by cases h)⟩
  · exact ⟨resMode_ne' fn, resMode_inout fn⟩

/-- A context with no borrowed parameter pins nothing inside any call. -/
theorem pinOK_noRootb {Γ : Ctx} (h : ∀ p E, Γ p = some E → E.mode ≠ .rootb) (s : Stmt) :
    PinOK Γ s := by
  induction s with
  | seq a _ iha _ => exact iha
  | scope _ k ih => exact ih
  | scopeD _ _ k ih => exact ih
  | rbind p k ih => exact ⟨fun E hE hm => absurd hm (h p E hE), ih⟩
  | frozen _ k ih => exact ih
  | catchR _ _ k ih => exact ih
  | _ => trivial

/-! ### The new thread's bindings -/

theorem spawnSt_res (fn : Fn) (vs : List Val) :
    spawnSt fn vs fn.params.length = some ⟨false, none⟩ := by
  simp [spawnSt]

theorem spawnSt_of {fn : Fn} {vs : List Val} (hlen : vs.length = fn.params.length) {v : Nat} {w : Val}
    (hw : vs[v]? = some w) : spawnSt fn vs v = some ⟨true, some w⟩ := by
  have hv : v < vs.length := (List.getElem?_eq_some_iff.mp hw).1
  have hne : v ≠ fn.params.length := by omega
  simp [spawnSt, hne, hw]

theorem spawnSt_none {fn : Fn} {vs : List Val} (hlen : vs.length = fn.params.length) {v : Nat}
    (hv : fn.params.length < v) : spawnSt fn vs v = none := by
  have hne : v ≠ fn.params.length := by omega
  have hvs : vs[v]? = none := List.getElem?_eq_none (by omega)
  simp [spawnSt, hne, hvs]

/-- A slot of the new thread that holds a value holds a moved tree, and owns it. -/
theorem spawnSt_val {fn : Fn} {vs : List Val} {v : Nat} {sl : Slot} {T : Val}
    (h : spawnSt fn vs v = some sl) (hT : sl.val = some T) : vs[v]? = some T ∧ sl.own = true := by
  unfold spawnSt at h
  split at h
  · cases h; cases hT
  · obtain ⟨w, hw, rfl⟩ := Option.map_eq_some_iff.mp h
    cases hT
    exact ⟨hw, rfl⟩

/-! ### The new thread's facts -/

/-- **The new thread is typed**: its parameters' scopes and its result's, around
    the body, in the spawned function's own context. -/
theorem newThread_typed {P : Prog} {fn : Fn} (hok : FnOK P fn)
    (hpar : ∀ pt ∈ fn.params, pt.1 = .sink ∧ pt.2.holdsView = false) :
    ∃ Δ, StmtT P (sigCtx fn) [] (wrapParams fn.params 0 0 (.scope fn.params.length fn.body)) Δ := by
  obtain ⟨hsrc, -, -, -, -, -, -, -, -, -, -, Δb, hbody, hfl, -⟩ := hok
  have hrb : ∀ p E, sigCtx fn p = some E → E.mode ≠ .rootb := fun p E h =>
    (sigCtx_spawn_mode hpar h).1
  -- the body binds nothing new, so its end has no borrowed parameter either
  have hrbΔ : ∀ p E, Δb p = some E → E.mode ≠ .rootb := by
    intro p E hp hm
    obtain ⟨E0, h0, hm0, -⟩ := (hbody.domTy hsrc).2 p E hp
    exact hrb p E0 h0 (hm0.symm.trans hm)
  have hsc : StmtT P (sigCtx fn) [] (.scope fn.params.length fn.body) (exitScope fn.params.length Δb) :=
    StmtT.scope ⟨_, sigCtx_res fn, resMode_ne' fn⟩ (fun h => by cases h) hbody
      ⟨fun p E hp hm => absurd hm (hrbΔ p E hp), DtorSafe.of_none (fun v E h => (hfl v E h).1) _ _ _,
        DbindSafe.of_none (fun v E h => (hfl v E h).2) _⟩
  -- (and no binding of its end runs a destructor)
  have hfl' : ∀ v E, exitScope fn.params.length Δb v = some E → E.dtor = false ∧ E.dbind = false := by
    intro v E hv
    by_cases hvn : v = fn.params.length
    · subst hvn; simp [exitScope] at hv
    · rw [exitScope, upd_ne _ _ hvn] at hv
      simp only [A2.kill] at hv
      obtain ⟨E0, h0, rfl⟩ := Option.map_eq_some_iff.mp hv
      rw [killE_dtor, killE_dbind]; exact hfl v E0 h0
  have hq0 : RbQ (· < 0) Δb := fun p E hp hm => absurd hm (hrbΔ p E hp)
  have hq : RbQ (· < 0) (exitScope fn.params.length Δb) := by
    intro p E hp
    by_cases hpn : p = fn.params.length
    · subst hpn; simp [exitScope] at hp
    · rw [exitScope, upd_ne _ _ hpn] at hp
      exact (hq0.kill .replace false _) p E hp
  refine ⟨_, wrap_typed (base := 0) (pe := fun _ => intE) hsc (fun _ d hd => by simp [intE] at hd)
    (fun _ d hd => by simp [intE] at hd) hq (fun p E hp hd => absurd hd (by rw [(hfl' p E hp).1]; simp))
    (fun p E hp hd => absurd hd (by rw [(hfl' p E hp).2]; simp)) fn.params 0 (fun k p hk => ?_)⟩
  obtain ⟨h1, ht⟩ := hpar p (List.mem_of_getElem? hk)
  obtain ⟨pm, t⟩ := p
  simp only at h1 ht
  subst h1
  show (∃ E, sigCtx fn (0 + (0 + k)) = some E ∧ E.mode ≠ .rootb) ∧ 0 + (0 + k) ∉ []
  rw [Nat.zero_add, Nat.zero_add]
  exact ⟨⟨_, sigCtx_sink hk ht, fun h => (by cases h)⟩, fun h => (by cases h)⟩

/-- The new thread's statement runs inside the scopes of its parameters, then
    its result's. -/
theorem newThread_spine {fn : Fn} (hsrc : fn.body.src = true) :
    (wrapParams fn.params 0 0 (.scope fn.params.length fn.body)).spine =
      wrapSpine fn.params 0 0 ++ [fn.params.length] := by
  rw [spine_wrap]; simp [Stmt.spine, src_spine hsrc]

/-- Each binding of the spawned function's own context is bound by a scope the
    new thread runs inside of. -/
theorem newThread_closed {fn : Fn} (hpar : ∀ pt ∈ fn.params, pt.1 = .sink ∧ pt.2.holdsView = false)
    (hsrc : fn.body.src = true) :
    Closed (sigCtx fn) (wrapParams fn.params 0 0 (.scope fn.params.length fn.body)) := by
  intro v hv
  rw [newThread_spine hsrc]
  obtain ⟨E, hE⟩ := Option.isSome_iff_exists.mp hv
  rcases sigCtx_spawn hpar hE with ⟨t, hp, -, -⟩ | ⟨rfl, -⟩
  · apply List.mem_append_left
    have := mem_wrapSpine_of (base := 0) (i := 0) hp (fun b h => by cases h)
    simpa using this
  · exact List.mem_append_right _ (List.mem_singleton_self _)

/-- **The invariant holds on the new thread**, over its own part of the
    address space: what the moved trees hold. -/
theorem newThread_inv {P : Prog} {fn : Fn} (hok : FnOK P fn)
    (hpar : ∀ pt ∈ fn.params, pt.1 = .sink ∧ pt.2.holdsView = false) (hres : fn.resTy = .int)
    {vs : List Val} (hlen : vs.length = fn.params.length)
    (hwf : ∀ (j : Nat) (v : Val) (pt : PMode × Ty), vs[j]? = some v → fn.params[j]? = some pt →
      WFv pt.2 v)
    (hnd : ∀ v ∈ vs, v.ids.Nodup)
    (hdisj : ∀ (j k : Nat) (v w : Val), j ≠ k → vs[j]? = some v → vs[k]? = some w →
      ∀ i ∈ v.ids, i ∉ w.ids)
    (hself : ∀ v ∈ vs, SelfFree v) (hpk : ∀ v ∈ vs, PkgsOK v)
    {part : Nat → Bool} (hpart : ∀ i, part i = true ↔ ∃ v ∈ vs, i ∈ v.ids)
    {N : Nat} (hlt : ∀ v ∈ vs, ∀ i ∈ v.ids, i < N) :
    Inv { alloc := part, nid := N, nv := fn.nvars, st := spawnSt fn vs } (sigCtx fn) []
      (wrapParams fn.params 0 0 (.scope fn.params.length fn.body)) := by
  obtain ⟨hsrc, hnv, hvars, hrok, hrown, hps, -⟩ := hok
  have hown : fn.resOwn = false := by
    cases h : fn.resOwn
    · rfl
    · have := hrown h; rw [hres] at this; cases this
  have hmode : resMode fn = .bor := by simp [resMode, hown]
  have hmem : ∀ {x : Nat} {sl : Slot} {T : Val}, spawnSt fn vs x = some sl → sl.val = some T →
      T ∈ vs := fun h hT => List.mem_of_getElem? (spawnSt_val h hT).1
  have hrb : ∀ p E, sigCtx fn p = some E → E.mode ≠ .rootb := fun p E h =>
    (sigCtx_spawn_mode hpar h).1
  exact {
    dom := fun v => by
      show (sigCtx fn v).isSome = (spawnSt fn vs v).isSome
      rcases Nat.lt_trichotomy v fn.params.length with h | h | h
      · obtain ⟨t, hp, ht⟩ := spawn_param hpar h
        obtain ⟨w, hw⟩ : ∃ w, vs[v]? = some w := ⟨_, List.getElem?_eq_getElem (by omega)⟩
        rw [sigCtx_sink hp ht, spawnSt_of hlen hw]; rfl
      · subst h; rw [sigCtx_res, spawnSt_res]; rfl
      · rw [sigCtx_none h, spawnSt_none hlen h]; rfl
    slot := fun v E hv => by
      rcases sigCtx_spawn hpar hv with ⟨t, hp, ht, rfl⟩ | ⟨rfl, rfl⟩
      · have hvl : v < vs.length := by rw [hlen]; exact (List.getElem?_eq_some_iff.mp hp).1
        obtain ⟨w, hw⟩ : ∃ w, vs[v]? = some w := ⟨_, List.getElem?_eq_getElem hvl⟩
        obtain ⟨htok, hsink, -⟩ := hps _ (List.mem_of_getElem? hp)
        refine ⟨⟨true, some w⟩, spawnSt_of hlen hw, htok, rfl,
          fun _ => ⟨hsink rfl, fun T hT => ?_, fun _ => ⟨w, rfl, ViewsOK.none ht w []⟩⟩,
          fun h => (by cases h)⟩
        cases hT; exact hwf v w _ hw hp
      · refine ⟨⟨false, none⟩, spawnSt_res fn vs, hrok, (by rw [hmode]; rfl),
          fun h => (by rw [hmode] at h; cases h), fun _ h => (by cases h)⟩
    heap := {
      nodup := fun x t h => hnd t (hmem h rfl)
      disj := fun x y t u hne h1 h2 => hdisj x y t u hne (spawnSt_val h1 rfl).1 (spawnSt_val h2 rfl).1
      alloc := fun x t h i hi => ⟨(hpart i).mpr ⟨t, hmem h rfl, hi⟩, hlt t (hmem h rfl) i hi⟩
      self := fun x t h => hself t (hmem h rfl) }
    nvSt := fun v hv => by
      have h1 : v ≤ fn.params.length := Nat.not_lt.mp fun h => by
        have h2 : (spawnSt fn vs v).isSome = true := hv
        rw [spawnSt_none hlen h] at h2; cases h2
      exact Nat.lt_of_le_of_lt h1 hnv
    noInout := fun v E b hv => (sigCtx_spawn_mode hpar hv).2 b
    wf := sigCtx_wf fn
    rootbLive := fun p E hp hm => absurd hm (hrb p E hp)
    rootbLt := fun p E hp hm => absurd hm (hrb p E hp)
    names := sigCtx_names fn
    held := fun v E sl T hv hl hsl hT => by
      rcases sigCtx_spawn hpar hv with ⟨t, hp, ht, rfl⟩ | ⟨rfl, rfl⟩
      · intro c hc
        rw [WFv.names_nil (hwf v T _ (spawnSt_val hsl hT).1 hp) ht] at hc
        cases hc
      · cases hl
    pkgs := fun v sl T hsl hT => hpk T (hmem hsl hT)
    armed := fun v E sl hv _ => ArmOK.of_dbind (sigCtx_flags hv).2
    nvS := fun v hv => by
      show v < fn.nvars
      rw [vars_wrap] at hv
      simp only [Stmt.vars, List.mem_append, List.mem_cons] at hv
      rcases hv with hv | rfl | hv
      · obtain ⟨k, p, hk, _, he⟩ := mem_wrapSpine hv
        have hvk : v = k := by simpa using he
        subst hvk
        exact Nat.lt_trans (List.getElem?_eq_some_iff.mp hk).1 hnv
      · exact hnv
      · exact hvars v hv
    nvF := fun v hv => by cases hv
    anch := fun p E hp hm => absurd hm (hrb p E hp)
    spineNd := by
      rw [newThread_spine hsrc]
      refine List.nodup_append.mpr ⟨wrapSpine_nodup _ _ _,
        List.nodup_cons.mpr ⟨fun h => (by cases h), List.nodup_nil⟩, fun a ha b hb => ?_⟩
      obtain ⟨k, p, hk, _, he⟩ := mem_wrapSpine ha
      have hak : a = k := by simpa using he
      rw [List.mem_singleton] at hb
      subst hak hb
      exact Nat.ne_of_lt (List.getElem?_eq_some_iff.mp hk).1
    spineDom := fun v hv => by
      rw [newThread_spine hsrc] at hv
      rcases List.mem_append.mp hv with hv | hv
      · obtain ⟨k, p, hk, _, he⟩ := mem_wrapSpine hv
        have hvk : v = k := by simpa using he
        subst hvk
        exact ⟨_, sigCtx_of hk⟩
      · rw [List.mem_singleton] at hv
        subst hv
        exact ⟨_, sigCtx_res fn⟩
    catchOK := by
      rw [catchOK_wrap]
      exact (catchOK_src hsrc : CatchOK _ fn.body)
    cover := fun i hi => by
      obtain ⟨v, hv, hiv⟩ := (hpart i).mp hi
      obtain ⟨j, hj⟩ := List.mem_iff_getElem?.mp hv
      exact ⟨j, v, spawnSt_of hlen hj, hiv⟩
    pinOut := fun p E hp hm => absurd hm (hrb p E hp)
    pinIn := pinOK_noRootb hrb _
    dtorOut := fun v E hv hd => absurd hd (by rw [(sigCtx_flags hv).2]; simp)
    dtorIn := DtorPinOK.of_spine_dbind fun v _ E hE => (sigCtx_flags hE).2 }

/-- **The thread a spawn starts satisfies A2's invariant**, on its own part of
    the address space (the moved trees' addresses) and at the shared `nid`. -/
theorem newThread_ok {P : Prog} {spawn : Nat → Bool} (hP : ProgOK P) (hPc : ProgCodes P)
    (hS : SpawnOK P spawn)
    {f : Nat} {fn : Fn} (hsp : spawn f = true) (hf : P[f]? = some fn) {vs : List Val}
    (hlen : vs.length = fn.params.length)
    (hwf : ∀ (j : Nat) (v : Val) (pt : PMode × Ty), vs[j]? = some v → fn.params[j]? = some pt →
      WFv pt.2 v)
    (hnd : ∀ v ∈ vs, v.ids.Nodup)
    (hdisj : ∀ (j k : Nat) (v w : Val), j ≠ k → vs[j]? = some v → vs[k]? = some w →
      ∀ i ∈ v.ids, i ∉ w.ids)
    (hself : ∀ v ∈ vs, SelfFree v) (hpk : ∀ v ∈ vs, PkgsOK v) (hcd : ∀ v ∈ vs, PkgOK P v)
    {part : Nat → Bool} (hpart : ∀ i, part i = true ↔ ∃ v ∈ vs, i ∈ v.ids)
    {N : Nat} (hlt : ∀ v ∈ vs, ∀ i ∈ v.ids, i < N) :
    ThreadOK P { alloc := part, nid := N, nv := fn.nvars, st := spawnSt fn vs }
      (wrapParams fn.params 0 0 (.scope fn.params.length fn.body)) := by
  obtain ⟨fn', hf', hres, hpar⟩ := hS f hsp
  have hfn : fn' = fn := Option.some.inj (hf'.symm.trans hf)
  rw [hfn] at hres hpar
  have hok := hP fn (List.mem_of_getElem? hf)
  have hsrc : fn.body.src = true := by obtain ⟨h, -⟩ := hok; exact h
  obtain ⟨Δ, ht⟩ := newThread_typed hok hpar
  exact ⟨sigCtx fn, [], Δ, ht, newThread_inv hok hpar hres hlen hwf hnd hdisj hself hpk hpart hlt,
    memCodes_iff.mpr fun x o V hx => hcd V (List.mem_of_getElem? (spawnSt_val hx rfl).1),
    wrapParams_codes (s := .scope fn.params.length fn.body) (hPc fn (List.mem_of_getElem? hf)) _ _ _,
    newThread_closed hpar hsrc⟩

end A3
