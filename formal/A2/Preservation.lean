import A2.TypingFacts

/-! A2 — preservation: a step of a well-typed configuration leads to a
well-typed configuration. -/

namespace A2

/-- How the context after a step relates to the one before: bindings outside
    the run-time scopes stay, with their mode and type, and a borrowed
    parameter's entry is untouched; new bindings are inside new scopes. -/
def Keep (Γ Γ' : Ctx) (s s' : Stmt) : Prop :=
  (∀ v E, Γ v = some E → v ∉ s.spine → v ∉ s'.spine ∧
      ∃ E', Γ' v = some E' ∧ E'.mode = E.mode ∧ E'.ty = E.ty ∧ (E.mode = .rootb → E' = E)) ∧
  (∀ v E', Γ' v = some E' → v ∉ s'.spine → v ∉ s.spine ∧ ∃ E, Γ v = some E)

structure CtxRel (Γ Γ' : Ctx) : Prop where
  dom   : ∀ x, (Γ' x).isSome = (Γ x).isSome
  mode  : ∀ x E1, Γ' x = some E1 → ∃ E0, Γ x = some E0 ∧ E1.mode = E0.mode ∧ E1.ty = E0.ty
  rootb : ∀ p Ep, Γ p = some Ep → Ep.mode = .rootb → Γ' p = some Ep

theorem RhsPost.rel {m m1 : Mem} {Γ Γ1 : Ctx} {F : List Var} (h : RhsPost m m1 Γ Γ1 F) :
    CtxRel Γ Γ1 := ⟨h.cdom, h.cmode, h.rootb⟩

theorem CtxRel.refl (Γ : Ctx) : CtxRel Γ Γ := ⟨fun _ => rfl, fun _ E h => ⟨E, h, rfl, rfl⟩, fun _ _ h _ => h⟩

theorem CtxRel.trans {Γ1 Γ2 Γ3 : Ctx} (h1 : CtxRel Γ1 Γ2) (h2 : CtxRel Γ2 Γ3) : CtxRel Γ1 Γ3 where
  dom x := (h2.dom x).trans (h1.dom x)
  mode x E h := by
    obtain ⟨E2, h2', hm2, ht2⟩ := h2.mode x E h
    obtain ⟨E1, h1', hm1, ht1⟩ := h1.mode x E2 h2'
    exact ⟨E1, h1', hm2.trans hm1, ht2.trans ht1⟩
  rootb p E h hm := h2.rootb p E (h1.rootb p E h hm) hm

theorem CtxRel.kill {Γ : Ctx} {F : List Var}
    (hanch : RootbAnch Γ F)
    {x : Var} (hxF : x ∉ F) (e : Eff) (hv : Bool)
    (hmn : ∀ p E, Γ p = some E → E.mode = .rootb → ∀ d ∈ E.vdeps, d.kind.bound ≠ .none →
      e.kills hv d.kind = true → d.root ≠ x) : CtxRel Γ (kill e hv x Γ) where
  dom x := kill_dom ..
  mode _ _ h := kill_cmode h
  rootb p E h hm := by simp only [A2.kill, h, Option.map_some]; rw [killE_rootb hanch hxF e hv hmn h hm]

theorem CtxRel.setE {Γ : Ctx} {x : Var} {Ex E : Entry} (hx : Γ x = some Ex) (hm : E.mode = Ex.mode)
    (ht : E.ty = Ex.ty) (hnrb : Ex.mode ≠ .rootb) : CtxRel Γ (setE Γ x E) where
  dom y := by
    by_cases h : y = x
    · subst h; simp [A2.setE, hx]
    · simp [A2.setE, upd_ne _ _ h]
  mode y E1 h := by
    by_cases hy : y = x
    · subst hy; simp only [A2.setE, upd_same, Option.some.injEq] at h; subst h; exact ⟨Ex, hx, hm, ht⟩
    · simp only [A2.setE, upd_ne _ _ hy] at h; exact ⟨E1, h, rfl, rfl⟩
  rootb p Ep h hmp := by
    have hpx : p ≠ x := fun e => by subst e; rw [hx] at h; cases h; exact hnrb hmp
    simp [A2.setE, upd_ne _ _ hpx, h]

theorem CtxRel.keep {Γ Γ' : Ctx} (h : CtxRel Γ Γ') {s s' : Stmt} (hs : s.spine = [])
    (hs' : s'.spine = []) : Keep Γ Γ' s s' := by
  refine ⟨fun v E hv _ => ⟨by rw [hs']; simp, ?_⟩, fun v E' hv _ => ⟨by rw [hs]; simp, ?_⟩⟩
  · have hd := h.dom v; rw [hv] at hd
    cases hE' : Γ' v with
    | none => rw [hE'] at hd; cases hd
    | some E' =>
      obtain ⟨E0, h0, hm, ht⟩ := h.mode v E' hE'
      rw [hv] at h0; cases h0
      refine ⟨E', rfl, hm, ht, fun hrb => ?_⟩
      have := h.rootb v E hv hrb; rw [hE'] at this; cases this; rfl
  · obtain ⟨E0, h0, _⟩ := h.mode v E' hv; exact ⟨E0, h0⟩

theorem CtxRel.anch {Γ Γ' : Ctx} (h : CtxRel Γ Γ') {F : List Var}
    (hanch : RootbAnch Γ F) : RootbAnch Γ' F :=
  hanch_of hanch h.mode h.rootb

/-- The leaf of a step: no run-time scope is open in the statement. -/
theorem Inv.leafAnch {m : Mem} {Γ : Ctx} {F : List Var} {s : Stmt} (hi : Inv m Γ F s)
    (hs : s.spine = []) : RootbAnch Γ F :=
  fun p E hp hm => hi.anch p E hp hm (by rw [hs]; simp)

theorem Inv.ofLeaf {m m' : Mem} {Γ Γ' : Ctx} {F : List Var} {s s' : Stmt} (hi : Inv m Γ F s)
    (hm : MInv m' Γ') (hnv : m.nv ≤ m'.nv) (hvars : ∀ v ∈ s'.vars, v < m'.nv)
    (hanch : RootbAnch Γ' F)
    (hs' : s'.spine = []) (hc : Covers m') (hck : CatchOK m' s') : Inv m' Γ' F s' :=
  { toMInv := hm
    nvS := hvars
    nvF := fun v hv => Nat.lt_of_lt_of_le (hi.nvF v hv) hnv
    anch := fun p E hp hmd _ => hanch p E hp hmd
    spineNd := by rw [hs']; exact List.nodup_nil
    spineDom := by rw [hs']; simp
    catchOK := hck
    cover := hc }

theorem vars_sub {m : Mem} {Γ : Ctx} {F : List Var} {s : Stmt} (hi : Inv m Γ F s) {s' : Stmt}
    (h : ∀ v ∈ s'.vars, v ∈ s.vars) : ∀ v ∈ s'.vars, v < m.nv := fun v hv => hi.nvS v (h v hv)

theorem Inv.respine {m : Mem} {Γ : Ctx} {F : List Var} {s : Stmt} (hi : Inv m Γ F s) {s' : Stmt}
    (hsp : s'.spine = s.spine) (hvs : ∀ v ∈ s'.vars, v ∈ s.vars) (hck : CatchOK m s') : Inv m Γ F s' :=
  { toMInv := hi.toMInv
    nvS := fun v h => hi.nvS v (hvs v h)
    nvF := hi.nvF
    anch := fun p E hp hm hs => hi.anch p E hp hm (by rw [← hsp]; exact hs)
    spineNd := by rw [hsp]; exact hi.spineNd
    spineDom := by rw [hsp]; exact hi.spineDom
    catchOK := hck
    cover := hi.cover }

/-- A step leaves what is lent out as it was. -/
def Frz (F : List Var) (m m' : Mem) : Prop := ∀ v ∈ F, m'.st v = m.st v

/-- The call case, proven separately (`Call.lean`). -/
def CallCase (P : Prog) : Prop :=
  ∀ {Γ : Ctx} {F : List Var} {x : Var} {f : Nat} {args : List Var} {k : Stmt} {E : Entry}
    {Γ1 Δ : Ctx} {m m' : Mem} {s' : Stmt},
    k.src = true → Γ x = none → x ∉ F → CallT P Γ F f args E Γ1 → StmtT P (setE Γ1 x E) F k Δ →
    NoPin Δ x → Inv m Γ F (.letcall x f args k) → Step P m (.letcall x f args k) (.ok m' s') →
    ∃ Γ', StmtT P Γ' F s' (exitScope x Δ) ∧ Inv m' Γ' F s' ∧ m.nv ≤ m'.nv ∧
      Keep Γ Γ' (.letcall x f args k) s' ∧ Frz F m m'

/-- The `recover` case, proven with the call case. -/
def RecCase (P : Prog) : Prop :=
  ∀ {Γ : Ctx} {F : List Var} {x : Var} {f : Nat} {k : Stmt} {E : Entry} {fn : Fn}
    {Γ1 Δ : Ctx} {m m' : Mem} {s' : Stmt},
    k.src = true → Γ x = none → x ∉ F → P[f]? = some fn → fn.params = [] → fn.resTy = .int →
    fn.resOwn = false → CallT P Γ F f [] E Γ1 → StmtT P (setE Γ1 x E) F k Δ →
    NoPin Δ x → Inv m Γ F (.letrec x f k) → Step P m (.letrec x f k) (.ok m' s') →
    ∃ Γ', StmtT P Γ' F s' (exitScope x Δ) ∧ Inv m' Γ' F s' ∧ m.nv ≤ m'.nv ∧
      Keep Γ Γ' (.letrec x f k) s' ∧ Frz F m m'

/-- The case of a call through a package, proven with the call case
    (`Closure.lean`).  It reads which code the package holds from memory. -/
def CloCase (P : Prog) : Prop :=
  ∀ {Γ Γ1 : Ctx} {F : List Var} {x c : Var} {j : Nat} {zs : List Var} {k : Stmt} {Ec E : Entry}
    {ms : List Nat} {σ : Nat} {sig : Fn} {Δ : Ctx} {m m' : Mem} {s' : Stmt},
    k.src = true → Γ x = none → x ∉ F → Γ c = some Ec → Ec.ty = .fn ms → ms[j]? = some σ →
    P[σ]? = some sig → sig.params.head? = some (.inp, .fn ms) → (∀ o ∈ sig.outHolds, o.2.1 ≠ 0) →
    CallT P Γ F σ (c :: zs) E Γ1 → (∀ z ∈ zs, ∀ d ∈ Ec.vdeps, d.kind.bound ≠ .none → d.root ≠ z) →
    StmtT P (setE Γ1 x (recvRes c Ec E)) F k Δ →
    NoPin Δ x → MemCodes P m → Inv m Γ F (.callc x c j zs k) →
    Step P m (.callc x c j zs k) (.ok m' s') →
    ∃ Γ', StmtT P Γ' F s' (exitScope x Δ) ∧ Inv m' Γ' F s' ∧ m.nv ≤ m'.nv ∧
      Keep Γ Γ' (.callc x c j zs k) s' ∧ Frz F m m'

/-- A borrowed parameter outside the step's scopes was there before,
    unchanged: it keeps its anchors. -/
theorem Keep.anchOut {Γ Γ' : Ctx} {s s' : Stmt} {F : List Var} (hk : Keep Γ Γ' s s')
    (hA : ∀ p E, Γ p = some E → E.mode = .rootb → p ∉ s.spine → Anchored E F) :
    ∀ p E, Γ' p = some E → E.mode = .rootb → p ∉ s'.spine → Anchored E F := by
  intro p E hp hm hps
  obtain ⟨hpa, E0, h0⟩ := hk.2 p E hp hps
  obtain ⟨_, E1, h1, hm1, _, hrb1⟩ := hk.1 p E0 h0 hpa
  rw [hp] at h1; cases h1
  have hE : E = E0 := hrb1 (hm1 ▸ hm)
  subst hE; exact hA p E h0 hm hpa

theorem NoPin.weaker {Γ Γ' : Ctx} (hw : Weaker Γ Γ') {x : Var} (h : NoPin Γ' x) : NoPin Γ x := by
  intro p E hp hm
  obtain ⟨E', h', hwe⟩ := hw.get hp
  rw [hwe.2.2.1 (Or.inl hm)] at h'
  exact h p E h' hm

theorem Keep.weaker {Γ Γ0 Γ' : Ctx} {s s' : Stmt} (hw : Weaker Γ Γ0) (h : Keep Γ0 Γ' s s') :
    Keep Γ Γ' s s' := by
  refine ⟨fun v E hv hs => ?_, fun v E' hv hs => ?_⟩
  · obtain ⟨E0, h0, hw0⟩ := hw.get hv
    obtain ⟨hs', E', h', hm, hty, hrb⟩ := h.1 v E0 h0 hs
    refine ⟨hs', E', h', hm.trans hw0.2.1, hty.trans hw0.1, fun hr => ?_⟩
    rw [hrb (hw0.2.1 ▸ hr), hw0.2.2.1 (Or.inl hr)]
  · obtain ⟨hs', E0, h0⟩ := h.2 v E' hv hs
    obtain ⟨E, hE, _⟩ := hw.get' h0
    exact ⟨hs', E, hE⟩


/-! ### Taking a struct apart -/

/-- What a right-hand side hands over stays valid when a fresh binding takes
    another value beside it. -/
theorem RhsOut.add {m : Mem} {Γ : Ctx} {E2 : Entry} {w : Val} {o2 : Bool} (hout : RhsOut m Γ E2 w o2)
    {x : Var} (hx : Γ x = none) (hmx : m.st x = none) {E1 : Entry} {v : Val} {o1 : Bool}
    (hdisj : ∀ i ∈ w.ids, i ∉ v.ids) : RhsOut (m.set x ⟨o1, some v⟩) (setE Γ x E1) E2 w o2 := by
  have hext : ∀ o', m.st o' ≠ none → (m.set x ⟨o1, some v⟩).st o' = m.st o' := by
    intro o' ho'
    have : o' ≠ x := fun h => ho' (h ▸ hmx)
    simp [upd_ne _ _ this]
  have hk : ∀ dep : Dep, VKeep m (m.set x ⟨o1, some v⟩) dep ∧ HKeep m (m.set x ⟨o1, some v⟩) dep :=
    fun dep => ⟨(rootKeep_ext hext dep.root).vkeep, (rootKeep_ext hext dep.root).hkeep⟩
  refine ⟨hout.own, hout.mode, hout.live, hout.tyok, fun hn r hr => ?_, fun hm => ?_, fun hm => ?_,
    fun hn => (hout.names hn).transport (fun r Er _ hr hl hh _ => ⟨Er, by
      have hrx : r ≠ x := fun h => by rw [h, hx] at hr; cases hr
      simp [setE, upd_ne _ _ hrx, hr], hl, hh, rfl, rfl⟩) (List.Subset.refl _), hout.held, hout.pkgs⟩
  · obtain ⟨Er, hEr, hro⟩ := hout.wf hn r hr
    have hrx : r ≠ x := fun h => by rw [h, hx] at hEr; cases hEr
    exact ⟨Er, by simp [setE, upd_ne _ _ hrx, hEr], hro⟩
  · obtain ⟨ho, hw, hvs, hnd, hal, hdis, hsf⟩ := hout.valOwn hm
    refine ⟨ho, hw, hvs.keep fun dep _ => (hk dep).1, hnd, hal, fun o U hU i hi => ?_, hsf⟩
    rcases ownedAt_set.mp hU with ⟨_, h⟩ | ⟨_, h⟩
    · cases h; exact hdisj i hi
    · exact hdis o U h i hi
  · exact (hout.valBor hm).keep (fun dep _ => hk dep) (fun dep _ => hk dep)

theorem compE_mode_ne (E : Entry) (t : Ty) : (compE E t).mode ≠ .rootb := by
  cases t <;> simp [compE, intE]

/-- `unpair`: the struct moves apart into its fields. -/
theorem pres_unpair {P : Prog} {Γ Δ : Ctx} {F : List Var} {y x z : Var} {s : Stmt} {E : Entry} {a b : Ty}
    (hsrc : s.src = true) (hy : Γ y = some E) (hl : E.live = true) (hm : canDo E.mode .replace)
    (hty : E.ty = .prod a b) (hyF : y ∉ F) (hx : Γ x = none) (hz : Γ z = none) (hxz : x ≠ z)
    (hxF : x ∉ F) (hzF : z ∉ F)
    (hs : StmtT P (setE (setE (setE (kill .replace false y Γ) y { E with live := false }) x (compE E a)) z
      (compE E b)) F s Δ) (hpy : NoPin Γ y) (hpz : NoPin Δ z) (hpx : NoPin (exitScope z Δ) x)
    {m m' : Mem} {s' : Stmt} (hi : Inv m Γ F (.unpair y x z s)) (hst : Step P m (.unpair y x z s) (.ok m' s')) :
    ∃ Γ', StmtT P Γ' F s' (exitScope x (exitScope z Δ)) ∧ Inv m' Γ' F s' ∧ m.nv ≤ m'.nv ∧
      Keep Γ Γ' (.unpair y x z s) s' ∧ Frz F m m' := by
  cases hst with
  | unpair hvy hmx hmz hxz' =>
    rename_i v w
    have hanch := hi.leafAnch rfl
    have hos : E.mode.ownSlot = true := by rcases hm with h | ⟨b, h, _⟩ <;> rw [h] <;> rfl
    obtain ⟨post, out⟩ := rhs_move' hi.toMInv hanch hy hl hos hyF hpy hvy
    have hxy : x ≠ y := fun h => by rw [h, hy] at hx; cases hx
    have hzy : z ≠ y := fun h => by rw [h, hy] at hz; cases hz
    have hx1 : setE (kill .replace false y Γ) y { E with live := false } x = none := by
      simp [setE, upd_ne _ _ hxy, kill, hx]
    have hz1 : setE (kill .replace false y Γ) y { E with live := false } z = none := by
      simp [setE, upd_ne _ _ hzy, kill, hz]
    have hτ : E.ty ≠ .int := by rw [hty]; simp
    obtain ⟨_, hwT, _, hnd, _, _, _⟩ := out.valOwn rfl
    rw [hty] at hwT
    cases hwT with
    | pair hwa hwb =>
    have hok := hi.tyok hy; rw [hty] at hok
    simp only [Ty.ok, Bool.and_eq_true] at hok
    have outx := out_part out hτ hwa (Sub.fst (Sub.refl _)) (fun s u h => by rw [hty]; exact ViewIn.fst h)
      (by simp only [ids_pair]; exact List.sublist_append_left _ _) hok.1
    have outz := out_part out hτ hwb (Sub.snd (Sub.refl _)) (fun s u h => by rw [hty]; exact ViewIn.snd h)
      (by simp only [ids_pair]; exact List.sublist_append_right _ _) hok.2
    have hvars : ∀ u ∈ (Stmt.unpair y x z s).vars, u < m.nv := hi.nvS
    have hxn : x < (m.set y ⟨true, none⟩).nv := by simpa using hvars x (by simp [Stmt.vars])
    have hzn : z < ((m.set y ⟨true, none⟩).set x ⟨v.owns, some v⟩).nv := by
      simpa using hvars z (by simp [Stmt.vars])
    have hi2 := post.inv.add hx1 hxn outx
    have hmz1 : (m.set y ⟨true, none⟩).st z = none := by simp [upd_ne _ _ hzy, hmz]
    have hdisj : ∀ i ∈ w.ids, i ∉ v.ids := by
      simp only [ids_pair, List.nodup_append] at hnd
      exact fun i hi hi' => hnd.2.2 i hi' i hi rfl
    have hmx1 : (m.set y ⟨true, none⟩).st x = none := by simp [upd_ne _ _ hxy, hmx]
    have outz' := outz.add (E1 := compE E a) (o1 := v.owns) hx1 hmx1 hdisj
    have hz2 : setE (setE (kill .replace false y Γ) y { E with live := false }) x (compE E a) z = none := by
      simp [setE, upd_ne _ _ (Ne.symm hxz), upd_ne _ _ hzy, kill, hz]
    have hi3 := hi2.add hz2 hzn outz'
    have hrel := post.rel
    have hanch1 := hrel.anch hanch
    refine ⟨_, StmtT.scope ⟨compE E a, by simp [setE, upd_ne _ _ hxz], compE_mode_ne E a⟩ hxF
      (StmtT.scope ⟨compE E b, by simp [setE], compE_mode_ne E b⟩ hzF hs hpz) hpx, ?_, by simp, ?_, ?_⟩
    · refine Inv.mk hi3 (fun u hu => ?_) (fun u hu => ?_) (fun p Ep hp hmp _ => ?_) ?_ ?_
        (show CatchOK _ s from catchOK_src hsrc) ?_
      · simp only [Stmt.vars, List.mem_cons] at hu
        simp only [Mem.set_nv]
        rcases hu with rfl | rfl | hu
        · exact hvars _ (by simp [Stmt.vars])
        · exact hvars _ (by simp [Stmt.vars])
        · exact hvars u (by simp [Stmt.vars, hu])
      · simp only [Mem.set_nv]; exact hi.nvF u hu
      · by_cases hpz : p = z
        · subst hpz; simp [setE] at hp; subst hp; exact absurd hmp (compE_mode_ne E b)
        by_cases hpx : p = x
        · subst hpx; simp [setE, upd_ne _ _ hxz] at hp; subst hp; exact absurd hmp (compE_mode_ne E a)
        simp only [setE, upd_ne _ _ hpz, upd_ne _ _ hpx] at hp
        exact hanch1 p Ep hp hmp
      · simp [Stmt.spine, src_spine hsrc, hxz]
      · intro u hu
        simp only [Stmt.spine, src_spine hsrc, List.mem_cons, List.not_mem_nil, or_false] at hu
        rcases hu with rfl | rfl
        · exact ⟨compE E a, by simp [setE, upd_ne _ _ hxz]⟩
        · exact ⟨compE E b, by simp [setE]⟩
      · intro i hia
        simp only [Mem.set_alloc] at hia
        obtain ⟨o, U, hU, hiU⟩ := hi.cover i hia
        by_cases hoy : o = y
        · subst hoy
          unfold OwnedAt at hU; rw [hvy] at hU; cases hU
          simp only [ids_pair, List.mem_append] at hiU
          rcases hiU with hiv | hiw
          · have hv : v.owns = true := by
              cases h : v.owns
              · rw [ids_nonNode h] at hiv; cases hiv
              · rfl
            exact ⟨x, v, by unfold OwnedAt; simp [upd_ne _ _ hxz, hv], hiv⟩
          · have hw : w.owns = true := by
              cases h : w.owns
              · rw [ids_nonNode h] at hiw; cases hiw
              · rfl
            exact ⟨z, w, by unfold OwnedAt; simp [hw], hiw⟩
        · have hox : o ≠ x := fun h => by subst h; unfold OwnedAt at hU; rw [hmx] at hU; cases hU
          have hoz : o ≠ z := fun h => by subst h; unfold OwnedAt at hU; rw [hmz] at hU; cases hU
          exact ⟨o, U, by unfold OwnedAt at hU ⊢; simp [upd_ne _ _ hox, upd_ne _ _ hoz, upd_ne _ _ hoy, hU],
            hiU⟩
    · refine ⟨fun u Eu hu _ => ?_, fun u Eu hu hus => ?_⟩
      · have hux : u ≠ x := fun h => by rw [h, hx] at hu; cases hu
        have huz : u ≠ z := fun h => by rw [h, hz] at hu; cases hu
        refine ⟨by simp [Stmt.spine, src_spine hsrc, hux, huz], ?_⟩
        have hk := hrel.keep (s := .skip) (s' := .skip) rfl rfl
        obtain ⟨_, E', h', hm', ht', hrb'⟩ := hk.1 u Eu hu (by simp [Stmt.spine])
        exact ⟨E', by simp [setE, upd_ne _ _ hux, upd_ne _ _ huz]; exact h', hm', ht', hrb'⟩
      · have hux : u ≠ x := fun h => hus (by simp [Stmt.spine, h])
        have huz : u ≠ z := fun h => hus (by simp [Stmt.spine, h])
        simp only [setE, upd_ne _ _ hux, upd_ne _ _ huz] at hu
        obtain ⟨E0, h0, _⟩ := hrel.mode u Eu hu
        exact ⟨by simp [Stmt.spine], E0, h0⟩
    · intro u hu
      have huy : u ≠ y := fun h => hyF (h ▸ hu)
      have hux : u ≠ x := fun h => hxF (h ▸ hu)
      have huz : u ≠ z := fun h => hzF (h ▸ hu)
      simp [upd_ne _ _ huy, upd_ne _ _ hux, upd_ne _ _ huz]

/-- Preservation: every step of a well-typed configuration, given the call
    case. -/
theorem preserve {P : Prog} (hcall : CallCase P) (hrec : RecCase P) (hclo : CloCase P) {Γ : Ctx} {F : List Var} {s : Stmt}
    {Δ : Ctx} (ht : StmtT P Γ F s Δ) :
    ∀ {m m' : Mem} {s' : Stmt}, MemCodes P m → Inv m Γ F s → Step P m s (.ok m' s') →
      ∃ Γ', StmtT P Γ' F s' Δ ∧ Inv m' Γ' F s' ∧ m.nv ≤ m'.nv ∧ Keep Γ Γ' s s' ∧ Frz F m m' := by
  induction ht with
  | skip => intro m m' s' _ _ hst; cases hst
  | sub hw _ ho ih =>
    intro m m' s' hcd hi hst
    obtain ⟨Γ', ht', hi', hnv, hk, hfz⟩ := ih hcd (hi.weaker hw) hst
    exact ⟨Γ', ht'.weakenOut hi'.wf hi'.names ho, hi', hnv, hk.weaker hw, hfz⟩
  | seq hbsrc ha hb iha ihb =>
    intro m m' s' hcd hi hst
    cases hst with
    | seqSkip =>
      refine ⟨_, ?_, ?_, Nat.le_refl _, (CtxRel.refl _).keep rfl (src_spine hbsrc), fun _ _ => rfl⟩
      · rcases skip_inv ha with rfl | hw
        · exact hb
        · exact hb.weakenIn hw
      · exact hi.respine (by rw [src_spine hbsrc]; rfl) (fun v hv => by simp [Stmt.vars, hv])
          (catchOK_src hbsrc)
    | seqL hst' =>
      obtain ⟨Γ', ht', hi', hnv, hk, hfz⟩ := iha hcd hi.seqIn hst'
      refine ⟨Γ', StmtT.seq hbsrc ht' hb,
        { hi' with
          nvS := fun v hv => ?_
          anch := hi'.anch }, hnv, hk, hfz⟩
      simp only [Stmt.vars, List.mem_append] at hv
      rcases hv with hv | hv
      · exact hi'.nvS v hv
      · exact Nat.lt_of_lt_of_le (hi.nvS v (by simp [Stmt.vars, hv])) hnv
  | @letv Γ Γ1 Δ F x r k E hsrc hx hxF hr hs hpx _ =>
    intro m m' s' hcd hi hst
    cases hst with
    | letv hmx he =>
      rename_i m1 v o
      have hanch := hi.leafAnch rfl
      obtain ⟨post, out⟩ := rhs_pres hi.toMInv hanch hr he
      have hx1 : Γ1 x = none := by
        have := post.cdom x; rw [hx] at this; cases h : Γ1 x <;> simp_all
      have hxn : x < m1.nv := by rw [post.nv]; exact hi.nvS x (by simp [Stmt.vars])
      have hm := post.inv.add hx1 hxn out
      have hnrb : E.mode ≠ .rootb := by rcases out.mode with h | h <;> rw [h] <;> simp
      have hanch1 := post.rel.anch hanch
      have hsp : k.spine = [] := src_spine hsrc
      refine ⟨setE Γ1 x E, StmtT.scope ⟨E, by simp [setE], hnrb⟩ hxF hs hpx, ?_, by simp [post.nv], ?_,
        fun v hv => ?_⟩
      · refine Inv.mk hm (fun v hv => ?_) (fun v hv => ?_) ?_ (by simp [Stmt.spine, hsp])
          (by simp [Stmt.spine, hsp, setE]) (show CatchOK _ k from catchOK_src hsrc)
          (covers_take (covers_evalR hi.cover he) (fun T h => by
            unfold OwnedAt at h; rw [evalR_none he hmx] at h; cases h))
        · simp only [Mem.set_nv, post.nv]
          simp only [Stmt.vars, List.mem_cons] at hv
          rcases hv with rfl | hv
          · exact hi.nvS _ (by simp [Stmt.vars])
          · exact hi.nvS v (by simp [Stmt.vars, hv])
        · simp only [Mem.set_nv, post.nv]; exact hi.nvF v hv
        · intro p Ep hp hmp _
          by_cases hpx : p = x
          · subst hpx; simp only [setE, upd_same, Option.some.injEq] at hp; subst hp
            exact absurd hmp hnrb
          · simp only [setE, upd_ne _ _ hpx] at hp; exact hanch1 p Ep hp hmp
      · refine ⟨fun v Ev hv _ => ?_, fun v Ev hv hvs => ?_⟩
        · have hvx : v ≠ x := fun h => by subst h; rw [hx] at hv; cases hv
          refine ⟨by simp [Stmt.spine, hsp, hvx], ?_⟩
          have hk := post.rel.keep (s := .skip) (s' := .skip) rfl rfl
          obtain ⟨_, E', h', hm', ht', hrb'⟩ := hk.1 v Ev hv (by simp [Stmt.spine])
          exact ⟨E', by simp [setE, upd_ne _ _ hvx, h'], hm', ht', hrb'⟩
        · have hvx : v ≠ x := fun h => by subst h; simp [Stmt.spine] at hvs
          simp only [setE, upd_ne _ _ hvx] at hv
          obtain ⟨E0, h0, _⟩ := post.rel.mode v Ev hv
          exact ⟨by simp [Stmt.spine], E0, h0⟩
      · have hvx : v ≠ x := fun e => hxF (e ▸ hv)
        simp only [Mem.set_st, upd_ne _ _ hvx]; exact post.frz v hv
  | @letd Γ Γ1 Δ F x f r k E hsrc hx hxF hr hmo hview hdtor hs hpx _ =>
    intro m m' s' hcd hi hst
    cases hst with
    | letd hmx he =>
      rename_i m1 v o
      have hanch := hi.leafAnch rfl
      obtain ⟨post, out⟩ := rhs_pres hi.toMInv hanch hr he
      have hx1 : Γ1 x = none := by
        have := post.cdom x; rw [hx] at this; cases h : Γ1 x <;> simp_all
      have hxn : x < m1.nv := by rw [post.nv]; exact hi.nvS x (by simp [Stmt.vars])
      have hm := post.inv.add hx1 hxn out
      have hnrb : E.mode ≠ .rootb := by rcases out.mode with h | h <;> rw [h] <;> simp
      have hanch1 := post.rel.anch hanch
      have hsp : k.spine = [] := src_spine hsrc
      refine ⟨setE Γ1 x E, StmtT.scopeD ⟨E, by simp [setE], hmo, hview, hdtor⟩ hxF hs hpx, ?_, by simp [post.nv], ?_,
        fun v hv => ?_⟩
      · refine Inv.mk hm (fun v hv => ?_) (fun v hv => ?_) ?_ (by simp [Stmt.spine, hsp])
          (by simp [Stmt.spine, hsp, setE]) (show CatchOK _ k from catchOK_src hsrc)
          (covers_take (covers_evalR hi.cover he) (fun T h => by
            unfold OwnedAt at h; rw [evalR_none he hmx] at h; cases h))
        · simp only [Mem.set_nv, post.nv]
          simp only [Stmt.vars, List.mem_cons] at hv
          rcases hv with rfl | hv
          · exact hi.nvS _ (by simp [Stmt.vars])
          · exact hi.nvS v (by simp [Stmt.vars, hv])
        · simp only [Mem.set_nv, post.nv]; exact hi.nvF v hv
        · intro p Ep hp hmp _
          by_cases hpx : p = x
          · subst hpx; simp only [setE, upd_same, Option.some.injEq] at hp; subst hp
            exact absurd hmp hnrb
          · simp only [setE, upd_ne _ _ hpx] at hp; exact hanch1 p Ep hp hmp
      · refine ⟨fun v Ev hv _ => ?_, fun v Ev hv hvs => ?_⟩
        · have hvx : v ≠ x := fun h => by subst h; rw [hx] at hv; cases hv
          refine ⟨by simp [Stmt.spine, hsp, hvx], ?_⟩
          have hk := post.rel.keep (s := .skip) (s' := .skip) rfl rfl
          obtain ⟨_, E', h', hm', ht', hrb'⟩ := hk.1 v Ev hv (by simp [Stmt.spine])
          exact ⟨E', by simp [setE, upd_ne _ _ hvx, h'], hm', ht', hrb'⟩
        · have hvx : v ≠ x := fun h => by subst h; simp [Stmt.spine] at hvs
          simp only [setE, upd_ne _ _ hvx] at hv
          obtain ⟨E0, h0, _⟩ := post.rel.mode v Ev hv
          exact ⟨by simp [Stmt.spine], E0, h0⟩
      · have hvx : v ≠ x := fun e => hxF (e ▸ hv)
        simp only [Mem.set_st, upd_ne _ _ hvx]; exact post.frz v hv
  | letcall hsrc hx hxF hc hs hpx _ =>
    intro m m' s' hcd hi hst
    exact hcall hsrc hx hxF hc hs hpx hi hst
  | assign hx hxF hmodes hr hty hxd _ hpin =>
    intro m m' s' hcd hi hst
    cases hst with
    | assign _ he hsl hd =>
      have hanch := hi.leafAnch rfl
      have post := step_assign hi.toMInv hanch hx hxF hmodes hr hty hxd he hsl hd hpin
      exact ⟨_, StmtT.skip, Inv.ofLeaf hi post.inv (by rw [post.nv]; simp) (by simp [Stmt.vars])
        (post.rel.anch hanch) rfl (covers_assign (covers_evalR hi.cover he) hsl hd) trivial,
        by rw [post.nv]; simp, post.rel.keep rfl rfl, post.frz⟩
  | ite hsa hsb _ ha hb _ _ =>
    intro m m' s' hcd hi hst
    cases hst with
    | iteT _ _ =>
      exact ⟨_, ha, hi.respine (by rw [src_spine hsa]; rfl) (fun v hv => by
        simp [Stmt.vars, hv]) (catchOK_src hsa), Nat.le_refl _, (CtxRel.refl _).keep rfl (src_spine hsa), fun _ _ => rfl⟩
    | iteF _ =>
      exact ⟨_, hb, hi.respine (by rw [src_spine hsb]; rfl) (fun v hv => by
        simp [Stmt.vars, hv]) (catchOK_src hsb), Nat.le_refl _, (CtxRel.refl _).keep rfl (src_spine hsb), fun _ _ => rfl⟩
  | «while» hsrc hc hs _ =>
    intro m m' s' hcd hi hst
    cases hst with
    | «while» =>
      refine ⟨_, StmtT.ite (by simp [Stmt.src, hsrc]) rfl hc
        (StmtT.seq (by simp [Stmt.src, hsrc]) hs (StmtT.while hsrc hc hs)) StmtT.skip,
        hi.respine rfl (fun v hv => ?_) (catchOK_src (by simp [Stmt.src, hsrc])), Nat.le_refl _,
        (CtxRel.refl _).keep rfl rfl, fun _ _ => rfl⟩
      simp only [Stmt.vars, List.mem_append, List.not_mem_nil, or_false] at hv ⊢
      grind
  | @push Γ Γ1 F x y Ex Ey Ex1 t D hx hl hty hcan hxF hy hly htyy hyx hpa hxD hx1 hl1 =>
    intro m m' s' hcd hi hst
    have hanch := hi.leafAnch rfl
    have hgo : ∀ {m1 : Mem} {v : Val}, TakeVal m y v m1 →
        RhsPost m m1 Γ Γ1 F ∧ Pushed m1 Γ1 t v D := fun htk =>
      push_take hi.toMInv hanch hy hly htyy hpa htk
    have fin : ∀ {m1 m' : Mem} {v : Val}, TakeVal m y v m1 →
        MInv m' (setE (kill .realloc t.holdsView x Γ1) x { Ex1 with held := Ex1.held ++ ownHeld true t D }) →
        m'.nv = m1.nv → Covers m' → (∀ v, v ≠ x → m'.st v = m1.st v) →
        ∃ Γ', StmtT P Γ' F .skip (setE (kill .realloc t.holdsView x Γ1) x
            { Ex1 with held := Ex1.held ++ ownHeld true t D }) ∧ Inv m' Γ' F .skip ∧ m.nv ≤ m'.nv ∧
          Keep Γ Γ' (.push x y) .skip ∧ Frz F m m' := by
      intro m1 m' v htk hinv hnv hcov hst1
      obtain ⟨post, _⟩ := hgo htk
      have hanch1 := post.rel.anch hanch
      obtain ⟨E0, h0, hm0, ht0⟩ := post.rel.mode x Ex1 hx1
      rw [hx] at h0; cases h0
      have hrel : CtxRel Γ (setE (kill .realloc t.holdsView x Γ1) x { Ex1 with held := Ex1.held ++ ownHeld true t D }) :=
        post.rel.trans ((CtxRel.kill hanch1 hxF .realloc t.holdsView
          (hmn_of_ne_replace _ (by decide) x)).trans
          (CtxRel.setE (x := x) (Ex := killE .realloc t.holdsView x Ex1) (by simp [A2.kill, hx1])
            (by rw [killE_mode]) (by rw [killE_ty]) (by
              rw [killE_mode, hm0]; rcases hcan with h | ⟨b, h, _⟩ <;> rw [h] <;> simp)))
      exact ⟨_, StmtT.skip, Inv.ofLeaf hi hinv (by rw [hnv, post.nv]; exact Nat.le_refl _)
        (by simp [Stmt.vars]) (hrel.anch hanch) rfl hcov trivial,
        by rw [hnv, post.nv]; exact Nat.le_refl _,
        hrel.keep rfl rfl, fun w hw => by rw [hst1 w (fun e => hxF (e ▸ hw))]; exact post.frz w hw⟩
    have prep : ∀ {m1 : Mem} {v : Val}, TakeVal m y v m1 →
        Pushed m1 Γ1 t v D ∧ MInv m1 Γ1 ∧ canDo Ex1.mode .realloc ∧ Ex1.ty = .vec t ∧
        (RootbAnch Γ1 F) := by
      intro m1 v htk
      obtain ⟨post, hp⟩ := hgo htk
      obtain ⟨E0, h0, hm0, ht0⟩ := post.rel.mode x Ex1 hx1
      rw [hx] at h0; cases h0
      exact ⟨hp, post.inv, by rw [hm0]; exact hcan, by rw [ht0, hty], post.rel.anch hanch⟩
    cases hst with
    | push htk hT _ _ =>
      obtain ⟨hp, hinv1, hcan1, hty1, hanch1⟩ := prep htk
      exact fin htk (push_grow hinv1 hanch1 hx1 hl1 hcan1 hxF hty1 hT hp.ownHeld (fun h => hxD (ownHeld_roots h))
        (fun h => by simp [ownHeld, h])
        (Or.inl ⟨rfl, rfl, rfl⟩)) rfl (covers_push (covers_takeVal hi.cover htk) hT)
        (fun w hw => by simp [upd_ne _ _ hw])
    | pushRealloc htk hT _ _ =>
      obtain ⟨hp, hinv1, hcan1, hty1, hanch1⟩ := prep htk
      exact fin htk (push_grow hinv1 hanch1 hx1 hl1 hcan1 hxF hty1 hT hp.ownHeld (fun h => hxD (ownHeld_roots h))
        (fun h => by simp [ownHeld, h])
        (Or.inr ⟨rfl, rfl, rfl⟩)) rfl (covers_pushRealloc (covers_takeVal hi.cover htk) hT)
        (fun w hw => by simp [upd_ne _ _ hw])
  | @free Γ F x E t hx hl hm hty hxF hpin =>
    intro m m' s' hcd hi hst
    cases hst with
    | free ht hf =>
      have hanch := hi.leafAnch rfl
      have hinv := step_free hi.toMInv hanch hx hm hxF ht hf hpin
      have hrel : CtxRel Γ (setE (kill .replace false x Γ) x { E with live := false }) :=
        (CtxRel.kill hanch hxF .replace false
          (hpin.kills _ _)).trans
        (CtxRel.setE (x := x) (Ex := killE .replace false x E) (by simp [A2.kill, hx])
          (by rw [killE_mode]) (by rw [killE_ty]) (by rw [killE_mode, hm]; simp))
      exact ⟨_, StmtT.skip, Inv.ofLeaf hi hinv (by simp) (by simp [Stmt.vars]) (hrel.anch hanch)
        rfl (covers_free hi.cover ht hf) trivial,
        by simp, hrel.keep rfl rfl, fun w hw => by simp [upd_ne _ _ (show w ≠ x from fun e => hxF (e ▸ hw))]⟩
  | @scope Γ Δ1 F x k hxE hxF hs hpx ihs =>
    intro m m' s' hcd hi hst
    obtain ⟨Ex, hx, hnrb⟩ := hxE
    have hxsp : x ∉ k.spine := by
      have := hi.spineNd; simp only [Stmt.spine, List.nodup_cons] at this; exact this.1
    cases hst with
    | scopeSkip hsl hd =>
      have hanch : RootbAnch Γ F := by
        intro p E hp hm
        refine hi.anch p E hp hm ?_
        simp only [Stmt.spine, List.mem_cons, List.not_mem_nil, or_false]
        intro h; subst h; rw [hx] at hp; cases hp; exact hnrb hm
      have hxn : NoPin Γ x := by
        rcases skip_inv hs with rfl | hw
        · exact hpx
        · exact hpx.weaker hw
      have hmn := hxn.kills .replace false
      have hinv := step_scopeExit hi.toMInv hanch hx hnrb hxF hsl hd hxn
      have hrel : ∀ v E', exitScope x Γ v = some E' → v ≠ x ∧ ∃ E, Γ v = some E ∧
          E' = killE .replace false x E := by
        intro v E' h
        have hvx : v ≠ x := fun e => by subst e; simp [exitScope] at h
        simp only [exitScope, upd_ne _ _ hvx, A2.kill] at h
        cases hE : Γ v with
        | none => rw [hE] at h; cases h
        | some E => rw [hE] at h; cases h; exact ⟨hvx, E, rfl, rfl⟩
      refine ⟨exitScope x Γ, ?_, Inv.ofLeaf hi hinv (by simp) (by simp [Stmt.vars]) ?_
        rfl (covers_remove hi.cover hsl hd) trivial, by simp, ⟨?_, ?_⟩,
        fun w hw => by simp [upd_ne _ _ (show w ≠ x from fun e => hxF (e ▸ hw))]⟩
      · rcases skip_inv hs with rfl | hw
        · exact StmtT.skip
        · exact StmtT.skip.weakenOut hinv.wf hinv.names (Or.inr (hw.exitScope x))
      · intro p E' hp hm
        obtain ⟨hpx, E, hE, rfl⟩ := hrel p E' hp
        rw [killE_mode] at hm
        rw [killE_rootb hanch hxF _ _ hmn hE hm]
        exact hanch p E hE hm
      · intro v E hv hvs
        have hvx : v ≠ x := fun e => hvs (by simp [Stmt.spine, e])
        refine ⟨by simp [Stmt.spine], killE .replace false x E, ?_, killE_mode .., killE_ty .., fun hrb => ?_⟩
        · simp [exitScope, upd_ne _ _ hvx, A2.kill, hv]
        · exact killE_rootb hanch hxF _ _ hmn hv hrb
      · intro v E' hv _
        obtain ⟨hvx, E, hE, _⟩ := hrel v E' hv
        exact ⟨by simp [Stmt.spine, hvx], E, hE⟩
    | scopeIn hst' =>
      have hi0 : Inv m Γ F k := hi.scopeIn hx hnrb
      obtain ⟨Γ', ht', hi', hnv, hk, hfz⟩ := ihs hcd hi0 hst'
      obtain ⟨hxsp', Ex', hx', hm', ht'', _⟩ := hk.1 x Ex hx hxsp
      refine ⟨Γ', StmtT.scope ⟨Ex', hx', by rw [hm']; exact hnrb⟩ hxF ht' hpx, ?_, hnv, ⟨?_, ?_⟩, hfz⟩
      · exact
        { toMInv := hi'.toMInv
          nvS := fun v hv => by
            simp only [Stmt.vars, List.mem_cons] at hv
            rcases hv with rfl | hv
            · exact Nat.lt_of_lt_of_le (hi.nvS v (by simp [Stmt.vars])) hnv
            · exact hi'.nvS v hv
          nvF := hi'.nvF
          anch := fun p E hp hm hps => hi'.anch p E hp hm (fun h => hps (by simp [Stmt.spine, h]))
          spineNd := by simp only [Stmt.spine, List.nodup_cons]; exact ⟨hxsp', hi'.spineNd⟩
          spineDom := fun v hv => by
            simp only [Stmt.spine, List.mem_cons] at hv
            rcases hv with rfl | hv
            · exact ⟨Ex', hx'⟩
            · exact hi'.spineDom v hv
          catchOK := hi'.catchOK
          cover := hi'.cover }
      · intro v E hv hvs
        simp only [Stmt.spine, List.mem_cons, not_or] at hvs
        obtain ⟨hvs', rest⟩ := hk.1 v E hv hvs.2
        exact ⟨by simp only [Stmt.spine, List.mem_cons, not_or]; exact ⟨hvs.1, hvs'⟩, rest⟩
      · intro v E' hv hvs
        simp only [Stmt.spine, List.mem_cons, not_or] at hvs
        obtain ⟨hvs', rest⟩ := hk.2 v E' hv hvs.2
        exact ⟨by simp only [Stmt.spine, List.mem_cons, not_or]; exact ⟨hvs.1, hvs'⟩, rest⟩
  | @scopeD Γ Δ1 F x f k hxE hxF hs hpx ihs =>
    intro m m' s' hcd hi hst
    obtain ⟨Ex, hx, hmo, hview, hdtor⟩ := hxE
    have hnrb : Ex.mode ≠ .rootb := by rw [hmo]; simp
    have hiS : Inv m Γ F (.scope x k) := Inv.scopeD_iff.mp hi
    have hxsp : x ∉ k.spine := by
      have := hiS.spineNd; simp only [Stmt.spine, List.nodup_cons] at this; exact this.1
    cases hst with
    | scopeDIn hst' =>
      have hi0 : Inv m Γ F k := hiS.scopeIn hx hnrb
      obtain ⟨Γ', ht', hi', hnv, hk, hfz⟩ := ihs hcd hi0 hst'
      obtain ⟨hxsp', Ex', hx', hm', ht'', _⟩ := hk.1 x Ex hx hxsp
      refine ⟨Γ', StmtT.scopeD ⟨Ex', hx', by rw [hm', hmo], by rw [ht'', hview],
          by rw [ht'']; exact hdtor⟩ hxF ht' hpx, Inv.scopeD_iff.mpr ?_, hnv, ⟨?_, ?_⟩, hfz⟩
      · exact
        { toMInv := hi'.toMInv
          nvS := fun v hv => by
            simp only [Stmt.vars, List.mem_cons] at hv
            rcases hv with rfl | hv
            · exact Nat.lt_of_lt_of_le (hiS.nvS v (by simp [Stmt.vars])) hnv
            · exact hi'.nvS v hv
          nvF := hi'.nvF
          anch := fun p E hp hm hps => hi'.anch p E hp hm (fun h => hps (by simp [Stmt.spine, h]))
          spineNd := by simp only [Stmt.spine, List.nodup_cons]; exact ⟨hxsp', hi'.spineNd⟩
          spineDom := fun v hv => by
            simp only [Stmt.spine, List.mem_cons] at hv
            rcases hv with rfl | hv
            · exact ⟨Ex', hx'⟩
            · exact hi'.spineDom v hv
          catchOK := hi'.catchOK
          cover := hi'.cover }
      · intro v E hv hvs
        simp only [Stmt.spine, List.mem_cons, not_or] at hvs
        obtain ⟨hvs', rest⟩ := hk.1 v E hv hvs.2
        exact ⟨by simp only [Stmt.spine, List.mem_cons, not_or]; exact ⟨hvs.1, hvs'⟩, rest⟩
      · intro v E' hv hvs
        simp only [Stmt.spine, List.mem_cons, not_or] at hvs
        obtain ⟨hvs', rest⟩ := hk.2 v E' hv hvs.2
        exact ⟨by simp only [Stmt.spine, List.mem_cons, not_or]; exact ⟨hvs.1, hvs'⟩, rest⟩
    | scopeDMoved hsl =>
      have hd : DropSlot m.alloc ⟨true, none⟩ m.alloc := DropSlot.moved
      have hanch : RootbAnch Γ F := by
        intro p E hp hm
        refine hiS.anch p E hp hm ?_
        simp only [Stmt.spine, List.mem_cons, List.not_mem_nil, or_false]
        intro h; subst h; rw [hx] at hp; cases hp; exact hnrb hm
      have hxn : NoPin Γ x := by
        rcases skip_inv hs with rfl | hw
        · exact hpx
        · exact hpx.weaker hw
      have hmn := hxn.kills .replace false
      have hinv := step_scopeExit hiS.toMInv hanch hx hnrb hxF hsl hd hxn
      have hrel : ∀ v E', exitScope x Γ v = some E' → v ≠ x ∧ ∃ E, Γ v = some E ∧
          E' = killE .replace false x E := by
        intro v E' h
        have hvx : v ≠ x := fun e => by subst e; simp [exitScope] at h
        simp only [exitScope, upd_ne _ _ hvx, A2.kill] at h
        cases hE : Γ v with
        | none => rw [hE] at h; cases h
        | some E => rw [hE] at h; cases h; exact ⟨hvx, E, rfl, rfl⟩
      refine ⟨exitScope x Γ, ?_, Inv.ofLeaf hiS hinv (by simp) (by simp [Stmt.vars]) ?_
        rfl (covers_remove hiS.cover hsl hd) trivial, by simp, ⟨?_, ?_⟩,
        fun w hw => by simp [upd_ne _ _ (show w ≠ x from fun e => hxF (e ▸ hw))]⟩
      · rcases skip_inv hs with rfl | hw
        · exact StmtT.skip
        · exact StmtT.skip.weakenOut hinv.wf hinv.names (Or.inr (hw.exitScope x))
      · intro p E' hp hm
        obtain ⟨hpx, E, hE, rfl⟩ := hrel p E' hp
        rw [killE_mode] at hm
        rw [killE_rootb hanch hxF _ _ hmn hE hm]
        exact hanch p E hE hm
      · intro v E hv hvs
        have hvx : v ≠ x := fun e => hvs (by simp [Stmt.spine, e])
        refine ⟨by simp [Stmt.spine], killE .replace false x E, ?_, killE_mode .., killE_ty .., fun hrb => ?_⟩
        · simp [exitScope, upd_ne _ _ hvx, A2.kill, hv]
        · exact killE_rootb hanch hxF _ _ hmn hv hrb
      · intro v E' hv _
        obtain ⟨hvx, E, hE, _⟩ := hrel v E' hv
        exact ⟨by simp [Stmt.spine, hvx], E, hE⟩
    | scopeDEnd hsl => sorry
    | scopeDP hp hsl => sorry
  | @rbind Γ Δ1 F p k Ep hp hm hl hroots hpF hs hrr ihs =>
    intro m m' s' hcd hi hst
    have hpsp : p ∉ k.spine := by
      have := hi.spineNd; simp only [Stmt.spine, List.nodup_cons] at this; exact this.1
    have hanchk : ∀ q E, Γ q = some E → E.mode = .rootb → q ∉ k.spine → Anchored E F := by
      intro q E hq hmq hqs
      by_cases hqp : q = p
      · subst hqp; rw [hp] at hq; cases hq; exact hroots
      · exact hi.anch q E hq hmq (by simp [Stmt.spine, hqp, hqs])
    have hpo : ∀ Ep', Γ p = some Ep' → Ep'.mode.ownSlot = false := fun Ep' h => by
      rw [hp] at h; cases h; rw [hm]; rfl
    have hpn : ∀ q E, Γ q = some E → E.mode = .rootb → ∀ d ∈ E.vdeps, d.kind.isName = true → d.root ≠ p :=
      fun q E hq hmq => (hi.names q E hq (hi.rootbLive q E hq hmq) (Or.inr hmq)).not_root hpo
    cases hst with
    | rbindSkip hsl =>
      have hanch : RootbAnch Γ F :=
        fun q E hq hmq => hanchk q E hq hmq (by simp [Stmt.spine])
      have hos' : Ep.mode.ownSlot = false := by rw [hm]; rfl
      have hinv := step_rbindExit hi.toMInv hanch hp hm hpF
      have hrel : ∀ v E', exitRoot p (Ep.path ++ Ep.held) Γ v = some E' → v ≠ p ∧ ∃ E, Γ v = some E ∧
          E' = rerootE p (Ep.path ++ Ep.held) E := by
        intro v E' h
        have hvp : v ≠ p := fun e => by subst e; simp [exitRoot] at h
        simp only [exitRoot, upd_ne _ _ hvp] at h
        cases hE : Γ v with
        | none => rw [hE] at h; cases h
        | some E => rw [hE] at h; cases h; exact ⟨hvp, E, rfl, rfl⟩
      have hos : Ep.mode.ownSlot = false := by rw [hm]; rfl
      refine ⟨exitRoot p (Ep.path ++ Ep.held) Γ, ?_, Inv.ofLeaf hi hinv (by simp) (by simp [Stmt.vars]) ?_
        rfl (covers_remove_bor hi.cover hsl) trivial, by simp, ⟨?_, ?_⟩,
        fun w hw => by simp [upd_ne _ _ (show w ≠ p from fun e => hpF (e ▸ hw))]⟩
      · rcases skip_inv hs with rfl | hw
        · exact StmtT.skip
        · refine StmtT.skip.weakenOut hinv.wf hinv.names (Or.inr (hw.exitRoot p (Ep.path ++ Ep.held)
            (fun d hd => ?_) (fun Ep' h => ?_) (fun d hd b t hk => ?_)))
          rotate_left
          · obtain ⟨E1, h1, hw1⟩ := hw.get hp
            rw [h] at h1; cases h1; rw [hw1.2.2.1 (Or.inl hm), hm]; rfl
          · -- `p` is as it was in the weaker context, which names what it holds
            obtain ⟨E1, h1, hw1⟩ := hw.get hp
            rw [hw1.2.2.1 (Or.inl hm)] at h1
            exact hw.2.2 p Ep h1 hl (Or.inr hm) d
              (by simp [Entry.vdeps, hos]; exact List.mem_append.mp hd) b t hk
          have hdv : d.root ∈ roots Ep.vdeps := by
            simp only [roots, Entry.vdeps, hos, Bool.false_eq_true, ↓reduceIte, List.mem_map]
            exact ⟨d, hd, rfl⟩
          refine ⟨fun h => ?_, ?_⟩
          · have := hi.rootbLt p Ep hp hm d.root hdv; rw [h] at this; exact Nat.lt_irrefl _ this
          · obtain ⟨Er, hEr, hro⟩ := hi.wf p Ep hp hl (Or.inr hm) d.root hdv
            obtain ⟨Er', hEr', hw'⟩ := hw.get hEr
            exact ⟨Er', hEr', by rw [hw'.2.1]; exact hro⟩
      · intro q E' hq hmq
        obtain ⟨_, E, hE, rfl⟩ := hrel q E' hq
        have hmq' : E.mode = .rootb := hmq
        rw [rerootE_rootb hanch hpF _ hE hmq' (hpn q E hE hmq')]
        exact hanch q E hE hmq'
      · intro v E hv hvs
        have hvp : v ≠ p := fun e => hvs (by simp [Stmt.spine, e])
        refine ⟨by simp [Stmt.spine], rerootE p (Ep.path ++ Ep.held) E, ?_, rfl, rfl, fun hrb => ?_⟩
        · simp [exitRoot, upd_ne _ _ hvp, hv]
        · exact rerootE_rootb hanch hpF _ hv hrb (hpn v E hv hrb)
      · intro v E' hv _
        obtain ⟨hvp, E, hE, _⟩ := hrel v E' hv
        exact ⟨by simp [Stmt.spine, hvp], E, hE⟩
    | rbindIn hst' =>
      have hi0 : Inv m Γ F k := hi.rbindIn hp hroots
      obtain ⟨Γ', ht', hi', hnv, hk, hfz⟩ := ihs hcd hi0 hst'
      obtain ⟨hpsp', Ep', hp', _, _, hrb⟩ := hk.1 p Ep hp hpsp
      have hEp : Ep' = Ep := hrb hm
      subst hEp
      refine ⟨Γ', StmtT.rbind hp' hm hl hroots hpF ht' hrr, ?_, hnv, ⟨?_, ?_⟩, hfz⟩
      · exact
        { toMInv := hi'.toMInv
          nvS := fun v hv => by
            simp only [Stmt.vars, List.mem_cons] at hv
            rcases hv with rfl | hv
            · exact Nat.lt_of_lt_of_le (hi.nvS v (by simp [Stmt.vars])) hnv
            · exact hi'.nvS v hv
          nvF := hi'.nvF
          anch := fun q E hq hmq hqs => hi'.anch q E hq hmq (fun h => hqs (by simp [Stmt.spine, h]))
          spineNd := by simp only [Stmt.spine, List.nodup_cons]; exact ⟨hpsp', hi'.spineNd⟩
          spineDom := fun v hv => by
            simp only [Stmt.spine, List.mem_cons] at hv
            rcases hv with rfl | hv
            · exact ⟨Ep', hp'⟩
            · exact hi'.spineDom v hv
          catchOK := hi'.catchOK
          cover := hi'.cover }
      · intro v E hv hvs
        simp only [Stmt.spine, List.mem_cons, not_or] at hvs
        obtain ⟨hvs', rest⟩ := hk.1 v E hv hvs.2
        exact ⟨by simp only [Stmt.spine, List.mem_cons, not_or]; exact ⟨hvs.1, hvs'⟩, rest⟩
      · intro v E' hv hvs
        simp only [Stmt.spine, List.mem_cons, not_or] at hvs
        obtain ⟨hvs', rest⟩ := hk.2 v E' hv hvs.2
        exact ⟨by simp only [Stmt.spine, List.mem_cons, not_or]; exact ⟨hvs.1, hvs'⟩, rest⟩
  | @frozen Γ Δ F z z' k hs hz ihs =>
    intro m m' s' hcd hi hst
    cases hst with
    | frozenSkip =>
      refine ⟨Γ, ?_, hi.respine rfl (by simp [Stmt.vars]) trivial, Nat.le_refl _,
        (CtxRel.refl Γ).keep rfl rfl, fun _ _ => rfl⟩
      rcases skip_inv hs with rfl | hw
      · exact StmtT.skip
      · exact StmtT.skip.weakenOut hi.wf hi.names (Or.inr hw)
    | frozenIn hst' =>
      have hi0 : Inv m Γ (F ++ z') k := hi.frozenIn hz
      obtain ⟨Γ', ht', hi', hnv, hk, hfz⟩ := ihs hcd hi0 hst'
      refine ⟨Γ', StmtT.frozen ht' hz, ?_, hnv, hk, fun v hv => hfz v (List.mem_append_left _ hv)⟩
      exact
        { toMInv := hi'.toMInv
          nvS := fun v hv => by
            simp only [Stmt.vars, List.mem_append] at hv
            rcases hv with hv | hv
            · exact Nat.lt_of_lt_of_le (hi.nvS v (by simp [Stmt.vars, hv])) hnv
            · exact hi'.nvS v hv
          nvF := fun v hv => Nat.lt_of_lt_of_le (hi.nvF v hv) hnv
          anch := fun p E hp hm hps => by
            obtain ⟨hps0, E0, h0⟩ := hk.2 p E hp hps
            obtain ⟨_, E', h', hm', _, hrb⟩ := hk.1 p E0 h0 hps0
            rw [hp] at h'; cases h'
            have hm0 : E0.mode = .rootb := by rw [← hm']; exact hm
            rw [hrb hm0]
            exact hi.anch p E0 h0 hm0 hps0
          spineNd := hi'.spineNd
          spineDom := hi'.spineDom
          catchOK := hi'.catchOK
          cover := hi'.cover }

  | panic => intro m m' s' _ _ hst; cases hst
  | letrec hsrc hx hxF hf hp hty ho hc hs hpx _ =>
    intro m m' s' hcd hi hst
    exact hrec hsrc hx hxF hf hp hty ho hc hs hpx hi hst
  | callc hk hx hxF hc htc hj hσ hhd hout hcT hnz hkT hpx _ =>
    intro m m' s' hcd hi hst
    exact hclo hk hx hxF hc htc hj hσ hhd hout hcT hnz hkT hpx hcd hi hst
  | @catchR Γ Δ F x m0 s hxF hs hM hanchΔ hKO ih =>
    intro m m' s' hcd hi hst
    obtain ⟨hfr, hxs, hnv0, hck⟩ := hi.catchOK
    have hlo : ∀ v, v ≠ x → v ∉ F ++ (List.range m0.nv).filter (· ≠ x) → m0.st v = none := by
      intro v hvx hvF
      cases h0 : m0.st v with
      | none => rfl
      | some _ =>
        have := hM.nvSt v (by simp [upd_ne _ _ hvx, h0])
        exact absurd (List.mem_append_right _ (List.mem_filter.mpr
          ⟨List.mem_range.mpr this, by simpa using hvx⟩)) hvF
    obtain ⟨Ex, hEx⟩ : ∃ Ex, Δ x = some Ex := by
      have := hM.dom x; simp at this; exact Option.isSome_iff_exists.mp this
    cases hst with
    | catchIn hst' =>
      rename_i s'
      obtain ⟨Γ', ht', hi', hnv, hk, hfz⟩ := ih hcd hi.catchIn hst'
      have hKO' : KeepOut Γ' Δ s'.spine := by
        refine ⟨fun v E' hv hvs => ?_, fun v E' hv => ?_⟩
        · obtain ⟨hvs0, E0, h0⟩ := hk.2 v E' hv hvs
          obtain ⟨_, E1, h1, hm1, ht1, hrb1⟩ := hk.1 v E0 h0 hvs0
          rw [hv] at h1; cases h1
          obtain ⟨E'', h'', hm'', ht'', hrb''⟩ := hKO.1 v E0 h0 hvs0
          refine ⟨E'', h'', hm''.trans hm1.symm, ht''.trans ht1.symm, fun hr => ?_⟩
          have hr0 : E0.mode = .rootb := hm1 ▸ hr
          rw [hrb'' hr0, hrb1 hr0]
        · obtain ⟨hvs0, E0, h0⟩ := hKO.2 v E' hv
          obtain ⟨hvs', E1, h1, _⟩ := hk.1 v E0 h0 hvs0
          exact ⟨hvs', E1, h1⟩
      have hxs' : x ∉ s'.spine := (hKO'.2 x Ex hEx).1
      refine ⟨Γ', StmtT.catchR hxF ht' hM hanchΔ hKO', ?_, hnv, hk,
        fun v hv => hfz v (List.mem_append_left _ hv)⟩
      exact
        { toMInv := hi'.toMInv
          nvS := fun v hv => by
            simp only [Stmt.vars, List.mem_cons] at hv
            rcases hv with rfl | hv
            · exact Nat.lt_of_lt_of_le (hi.nvS v (by simp [Stmt.vars])) hnv
            · exact hi'.nvS v hv
          nvF := fun v hv => Nat.lt_of_lt_of_le (hi.nvF v hv) hnv
          anch := fun p E hp hm hps => by
            obtain ⟨hps0, E0, h0⟩ := hk.2 p E hp hps
            obtain ⟨_, E', h', hm', _, hrb⟩ := hk.1 p E0 h0 hps0
            rw [hp] at h'; cases h'
            have hm0 : E0.mode = .rootb := by rw [← hm']; exact hm
            rw [hrb hm0]
            exact hi.anch p E0 h0 hm0 hps0
          spineNd := hi'.spineNd
          spineDom := hi'.spineDom
          catchOK := by
            refine ⟨fun v hv hvx => ?_, hxs', Nat.le_trans hnv0 hnv, hi'.catchOK⟩
            by_cases hvs : v ∈ s.spine
            · rw [step_gone hst' hck v hvs hv, hlo v hvx (hs.spine_F v hvs)]
            · by_cases hvF : v ∈ F ++ (List.range m0.nv).filter (· ≠ x)
              · rw [hfz v hvF]; exact hfr v hvs hvx
              · have h0 := hlo v hvx hvF
                have hm : m.st v = none := (hfr v hvs hvx).trans h0
                rw [h0]
                cases h' : m'.st v with
                | none => rfl
                | some _ => exact absurd (step_new hst' v hm (by simp [h'])) hv
          cover := hi'.cover }
    | catchSkip =>
      refine ⟨Γ, ?_, hi.respine rfl (by simp [Stmt.vars]) trivial, Nat.le_refl _,
        (CtxRel.refl Γ).keep rfl rfl, fun _ _ => rfl⟩
      rcases skip_inv hs with rfl | hw
      · exact StmtT.skip
      · exact StmtT.skip.weakenOut hi.wf hi.names (Or.inr hw)
    | catchP hp hx1 =>
      rename_i m1
      obtain ⟨hout, hin, hh1, hc1, hnv1, _⟩ := panic_unwind hp hi.heap hi.cover hi.spineNd
      have hsteq : (m1.set x ⟨false, some (.int 1)⟩).st = (m0.set x ⟨false, some (.int 1)⟩).st := by
        funext v
        by_cases hvx : v = x
        · subst hvx; simp
        · simp only [Mem.set_st, upd_ne _ _ hvx]
          by_cases hvs : v ∈ s.spine
          · rw [hin v hvs, hlo v hvx (hs.spine_F v hvs)]
          · rw [hout v hvs]; exact hfr v hvs hvx
      have hM' : MInv (m1.set x ⟨false, some (.int 1)⟩) Δ :=
        hM.of_st hsteq (hh1.set_bor x _) (by simp [hnv1, hnv0])
      obtain ⟨E0, h0⟩ := (hKO.2 x Ex hEx).2
      have hxown : ∀ T, ¬ OwnedAt m1 x T := by
        intro T hT
        unfold OwnedAt at hT
        rw [hout x hxs] at hT
        obtain ⟨E'', h'', hm'', _⟩ := hKO.1 x E0 h0 hxs
        obtain ⟨sl, hsl, _, hsok, _⟩ := hM.slot x E'' h''
        obtain ⟨sl0, hsl0, _, hsok0, _⟩ := hi.slot x E0 h0
        simp at hsl; subst hsl
        rw [hT] at hsl0; cases hsl0
        simp only at hsok hsok0
        rw [hm''] at hsok; rw [← hsok] at hsok0; cases hsok0
      refine ⟨Δ, StmtT.skip, Inv.ofLeaf hi hM' (by simp [hnv1]) (by simp [Stmt.vars])
        hanchΔ rfl (covers_set_none hc1 hxown (fun _ h => by cases h)) trivial,
        by simp [hnv1], ⟨fun v E hv hvs => ⟨by simp [Stmt.spine], hKO.1 v E hv hvs⟩,
          fun v E' hv _ => hKO.2 v E' hv⟩, fun v hv => ?_⟩
      have hvx : v ≠ x := fun e => hxF (e ▸ hv)
      have hvs : v ∉ s.spine := fun h => hs.spine_F v h (List.mem_append_left _ hv)
      simp only [Mem.set_st, upd_ne _ _ hvx]; exact hout v hvs

  | unpair hsrc hy hl hm hty hyF hx hz hxz hxF hzF hs hpy hpz hpx _ =>
    intro m m' s' hcd hi hst
    exact pres_unpair hsrc hy hl hm hty hyF hx hz hxz hxF hzF hs hpy hpz hpx hi hst

end A2
