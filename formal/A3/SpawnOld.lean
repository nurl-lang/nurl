import A3.Rel

/-! A3.0 — the spawner's side of a spawn.

A spawn moves its arguments to the new thread: on the spawner's own part of
the address space their trees are gone, and the spawner goes on with its
result bound to `0`.  That is exactly what A2 does with the statement
`dropSeq x args (letv x 0 k)`: each argument moves into `x`, whose scope
ends at once and frees the tree, and then `x` is bound to `0`.  A2 types
that statement where it types the call, so A2's soundness gives the
spawner's facts after the spawn. -/

namespace A3
open A2

/-- Each argument moved into `x` and dropped, in order, then `k`. -/
def dropSeq (x : Var) : List Var → Stmt → Stmt
  | [], k => k
  | a :: as, k => .seq (.letv x (.var a) .skip) (dropSeq x as k)

theorem dropSeq_src {x : Var} {L : Stmt} (hL : L.src = true) : ∀ as, (dropSeq x as L).src = true
  | [] => hL
  | _ :: as => by simp [dropSeq, Stmt.src, dropSeq_src hL as]

theorem dropSeq_spine (x : Var) (L : Stmt) (hL : L.spine = []) : ∀ as, (dropSeq x as L).spine = []
  | [] => hL
  | _ :: _ => rfl

theorem dropSeq_vars {x : Var} {L : Stmt} :
    ∀ as, ∀ v ∈ (dropSeq x as L).vars, v = x ∨ v ∈ as ∨ v ∈ L.vars
  | [], v, hv => .inr (.inr hv)
  | a :: as, v, hv => by
    simp only [dropSeq, Stmt.vars, Rhs.vars, List.mem_append, List.mem_cons, List.not_mem_nil,
      or_false] at hv
    rcases hv with (rfl | rfl) | hv
    · exact .inl rfl
    · exact .inr (.inl (List.mem_cons_self))
    · rcases dropSeq_vars as v hv with h | h | h
      · exact .inl h
      · exact .inr (.inl (List.mem_cons_of_mem _ h))
      · exact .inr (.inr h)

theorem dropSeq_codes {P : Prog} {x : Var} {L : Stmt} (hL : L.codesOK P) :
    ∀ as, (dropSeq x as L).codesOK P
  | [] => hL
  | _ :: as => ⟨⟨trivial, trivial⟩, dropSeq_codes hL as⟩

/-! ### The frames around the next step -/

theorem Redex.eq {s r : Stmt} {K : Stmt → Stmt} (h : Redex s K r) : s = K r := by
  induction h with
  | here => rfl
  | seq _ ih => subst ih; rfl
  | scope _ ih => subst ih; rfl
  | rbind _ ih => subst ih; rfl
  | frozen _ ih => subst ih; rfl
  | catchR _ ih => subst ih; rfl
  | scopeD _ ih => subst ih; rfl

/-- The frames read a statement's spine only through the hole's. -/
theorem Redex.spine_eq {s r : Stmt} {K : Stmt → Stmt} (h : Redex s K r) {y y' : Stmt}
    (hy : y.spine = y'.spine) : (K y).spine = (K y').spine := by
  induction h with
  | here => exact hy
  | seq _ ih => exact ih
  | scope _ ih => simp only [Stmt.spine, ih]
  | rbind _ ih => simp only [Stmt.spine, ih]
  | frozen _ ih => exact ih
  | catchR _ ih => exact ih
  | scopeD _ ih => simp only [Stmt.spine, ih]

theorem Redex.vars_sub {s r : Stmt} {K : Stmt → Stmt} (h : Redex s K r) {y y' : Stmt}
    (hy : ∀ v ∈ y.vars, v ∈ y'.vars) : ∀ v ∈ (K y).vars, v ∈ (K y').vars := by
  induction h with
  | here => exact hy
  | seq _ ih =>
    intro v hv
    simp only [Stmt.vars, List.mem_append] at hv ⊢
    exact hv.imp_left (ih v)
  | scope _ ih =>
    intro v hv
    simp only [Stmt.vars, List.mem_cons] at hv ⊢
    exact hv.imp_right (ih v)
  | rbind _ ih =>
    intro v hv
    simp only [Stmt.vars, List.mem_cons] at hv ⊢
    exact hv.imp_right (ih v)
  | frozen _ ih =>
    intro v hv
    simp only [Stmt.vars, List.mem_append] at hv ⊢
    exact hv.imp_right (ih v)
  | catchR _ ih =>
    intro v hv
    simp only [Stmt.vars, List.mem_cons] at hv ⊢
    exact hv.imp_right (ih v)
  | scopeD _ ih =>
    intro v hv
    simp only [Stmt.vars, List.mem_cons] at hv ⊢
    exact hv.imp_right (ih v)

theorem Redex.catchOK {s r : Stmt} {K : Stmt → Stmt} (h : Redex s K r) {m : Mem} {y y' : Stmt}
    (hy : y.spine = y'.spine) (hc : CatchOK m y) (hc' : CatchOK m (K y')) : CatchOK m (K y) := by
  induction h with
  | here => exact hc
  | seq _ ih => exact ih hc'
  | scope _ ih => exact ih hc'
  | rbind _ ih => exact ih hc'
  | frozen _ ih => exact ih hc'
  | catchR h ih =>
    obtain ⟨h1, h2, h3, h4⟩ := hc'
    have hsp := Redex.spine_eq h hy
    exact ⟨by rw [hsp]; exact h1, by rw [hsp]; exact h2, h3, ih h4⟩
  | scopeD _ ih => exact ih hc'

theorem Redex.pinOK {s r : Stmt} {K : Stmt → Stmt} (h : Redex s K r) {Γ : Ctx} {y y' : Stmt}
    (hy : y.spine = y'.spine) (hp : PinOK Γ y) (hp' : PinOK Γ (K y')) : PinOK Γ (K y) := by
  induction h with
  | here => exact hp
  | seq _ ih => exact ih hp'
  | scope _ ih => exact ih hp'
  | rbind h ih =>
    obtain ⟨h1, h2⟩ := hp'
    exact ⟨by rw [Redex.spine_eq h hy]; exact h1, ih h2⟩
  | frozen _ ih => exact ih hp'
  | catchR _ ih => exact ih hp'
  | scopeD _ ih => exact ih hp'

theorem Redex.dtorPinOK {s r : Stmt} {K : Stmt → Stmt} (h : Redex s K r) {Γ : Ctx} {y y' : Stmt}
    (hy : y.spine = y'.spine) (hp : DtorPinOK Γ y) (hp' : DtorPinOK Γ (K y')) : DtorPinOK Γ (K y) := by
  induction h with
  | here => exact hp
  | seq _ ih => exact ih hp'
  | scope h ih =>
    obtain ⟨h1, h2⟩ := hp'
    exact ⟨fun E hE hd hos hn d hdd hnm => by
      rw [Redex.spine_eq h hy]; exact h1 E hE hd hos hn d hdd hnm, ih h2⟩
  | rbind h ih =>
    obtain ⟨h1, h2⟩ := hp'
    exact ⟨fun E hE hd hos hn d hdd hnm => by
      rw [Redex.spine_eq h hy]; exact h1 E hE hd hos hn d hdd hnm, ih h2⟩
  | frozen _ ih => exact ih hp'
  | catchR _ ih => exact ih hp'
  | scopeD h ih =>
    obtain ⟨h1, h2⟩ := hp'
    exact ⟨fun E hE hd hos hn d hdd hnm => by
      rw [Redex.spine_eq h hy]; exact h1 E hE hd hos hn d hdd hnm, ih h2⟩

theorem Redex.codesOK {s r : Stmt} {K : Stmt → Stmt} (h : Redex s K r) {P : Prog} {y y' : Stmt}
    (hy : y.codesOK P) (hy' : (K y').codesOK P) : (K y).codesOK P := by
  induction h with
  | here => exact hy
  | seq _ ih => exact ⟨ih hy'.1, hy'.2⟩
  | scope _ ih => exact ih hy'
  | rbind _ ih => exact ih hy'
  | frozen _ ih => exact ih hy'
  | catchR _ ih => exact ih hy'
  | scopeD _ ih => exact ih hy'

/-- A step at the hole is a step of the whole. -/
theorem Redex.step {s r : Stmt} {K : Stmt → Stmt} (h : Redex s K r) {P : Prog} {m m' : Mem}
    {y y' : Stmt} (hst : Step P m y (.ok m' y')) : Step P m (K y) (.ok m' (K y')) := by
  induction h with
  | here => exact hst
  | seq _ ih => exact Step.seqL ih
  | scope _ ih => exact Step.scopeIn ih
  | rbind _ ih => exact Step.rbindIn ih
  | frozen _ ih => exact Step.frozenIn ih
  | catchR _ ih => exact Step.catchIn ih
  | scopeD _ ih => exact Step.scopeDIn ih

theorem Redex.steps {s r : Stmt} {K : Stmt → Stmt} (h : Redex s K r) {P : Prog} {m m' : Mem}
    {y y' : Stmt} (hst : Steps P m y (.ok m' y')) : Steps P m (K y) (.ok m' (K y')) := by
  generalize hr : (Res.ok m' y') = R at hst
  induction hst with
  | refl => cases hr; exact Steps.refl
  | step h1 _ ih => exact Steps.step (h.step h1) (ih hr)
  | panic _ => cases hr

/-! ### Typing through the frames -/

/-- What the typing of a statement says at its hole, with the invariant
    there: the frames type their body in the context they are typed in (a
    `frozen` or `recover` frame lends out more). -/
theorem Redex.typed {s r : Stmt} {K : Stmt → Stmt} (hR : Redex s K r) {P : Prog} {m : Mem} :
    ∀ Γ F Δ, StmtT P Γ F s Δ → Inv m Γ F s →
      ∃ Γ' F' Δ', StmtT P Γ' F' r Δ' ∧ Inv m Γ' F' r := by
  induction hR with
  | here => exact fun Γ F Δ ht hi => ⟨Γ, F, Δ, ht, hi⟩
  | @seq a b r K _ ih =>
    intro Γ F Δ ht hi
    generalize hS : Stmt.seq a b = S at ht hi
    induction ht with
    | seq _ ha _ _ _ => cases hS; exact ih _ _ _ ha hi.seqIn
    | sub hw _ _ ih0 => exact ih0 hS (hi.weaker hw)
    | _ => cases hS
  | @scope x s r K _ ih =>
    intro Γ F Δ ht hi
    generalize hS : Stmt.scope x s = S at ht hi
    induction ht with
    | scope hxE _ hs _ _ =>
      cases hS
      obtain ⟨Ex, hx, hnrb⟩ := hxE
      exact ih _ _ _ hs (hi.scopeIn hx hnrb)
    | sub hw _ _ ih0 => exact ih0 hS (hi.weaker hw)
    | _ => cases hS
  | @rbind p s r K _ ih =>
    intro Γ F Δ ht hi
    generalize hS : Stmt.rbind p s = S at ht hi
    induction ht with
    | rbind hp _ _ hanch _ hs _ _ => cases hS; exact ih _ _ _ hs (hi.rbindIn hp hanch)
    | sub hw _ _ ih0 => exact ih0 hS (hi.weaker hw)
    | _ => cases hS
  | @frozen z s r K _ ih =>
    intro Γ F Δ ht hi
    generalize hS : Stmt.frozen z s = S at ht hi
    induction ht with
    | frozen hs hz _ => cases hS; exact ih _ _ _ hs (hi.frozenIn hz)
    | sub hw _ _ ih0 => exact ih0 hS (hi.weaker hw)
    | _ => cases hS
  | @catchR x m0 s r K _ ih =>
    intro Γ F Δ ht hi
    generalize hS : Stmt.catchR x m0 s = S at ht hi
    induction ht with
    | catchR _ hs _ _ _ _ => cases hS; exact ih _ _ _ hs hi.catchIn
    | sub hw _ _ ih0 => exact ih0 hS (hi.weaker hw)
    | _ => cases hS
  | @scopeD x f s r K _ ih =>
    intro Γ F Δ ht hi
    generalize hS : Stmt.scopeD x f s = S at ht hi
    induction ht with
    | scopeD hxE _ hs _ _ _ _ _ =>
      cases hS
      obtain ⟨Ex, hx, hmo, _⟩ := hxE
      exact ih _ _ _ hs ((Inv.scopeD_iff.mp hi).scopeIn hx (by rw [hmo]; simp))
    | sub hw _ _ ih0 => exact ih0 hS (hi.weaker hw)
    | _ => cases hS

/-- **Replacing the hole keeps the typing**: if every typing of `r` at the
    hole, with the invariant there, types `r'` the same way, and `r'` has
    `r`'s spine, then the whole stays typed. -/
theorem Redex.plug {s r : Stmt} {K : Stmt → Stmt} (hR : Redex s K r) {P : Prog} {m : Mem} {r' : Stmt}
    (hsp : r'.spine = r.spine)
    (hhole : ∀ Γ F Δ, StmtT P Γ F r Δ → Inv m Γ F r → StmtT P Γ F r' Δ) :
    ∀ Γ F Δ, StmtT P Γ F s Δ → Inv m Γ F s → StmtT P Γ F (K r') Δ := by
  induction hR with
  | here => exact hhole
  | @seq a b r K _ ih =>
    intro Γ F Δ ht hi
    generalize hS : Stmt.seq a b = S at ht hi
    induction ht with
    | seq hb ha hb' _ _ => cases hS; exact StmtT.seq hb (ih hsp hhole _ _ _ ha hi.seqIn) hb'
    | sub hw _ ho ih0 => exact StmtT.sub hw (ih0 hS (hi.weaker hw)) ho
    | _ => cases hS
  | @scope x s r K _ ih =>
    intro Γ F Δ ht hi
    generalize hS : Stmt.scope x s = S at ht hi
    induction ht with
    | scope hxE hxF hs hpx _ =>
      cases hS
      obtain ⟨Ex, hx, hnrb⟩ := hxE
      exact StmtT.scope ⟨Ex, hx, hnrb⟩ hxF (ih hsp hhole _ _ _ hs (hi.scopeIn hx hnrb)) hpx
    | sub hw _ ho ih0 => exact StmtT.sub hw (ih0 hS (hi.weaker hw)) ho
    | _ => cases hS
  | @rbind p s r K _ ih =>
    intro Γ F Δ ht hi
    generalize hS : Stmt.rbind p s = S at ht hi
    induction ht with
    | rbind hp hm hl hanch hpF hs hd _ =>
      cases hS
      exact StmtT.rbind hp hm hl hanch hpF (ih hsp hhole _ _ _ hs (hi.rbindIn hp hanch)) hd
    | sub hw _ ho ih0 => exact StmtT.sub hw (ih0 hS (hi.weaker hw)) ho
    | _ => cases hS
  | @frozen z s r K _ ih =>
    intro Γ F Δ ht hi
    generalize hS : Stmt.frozen z s = S at ht hi
    induction ht with
    | frozen hs hz _ => cases hS; exact StmtT.frozen (ih hsp hhole _ _ _ hs (hi.frozenIn hz)) hz
    | sub hw _ ho ih0 => exact StmtT.sub hw (ih0 hS (hi.weaker hw)) ho
    | _ => cases hS
  | @catchR x m0 s r K h ih =>
    intro Γ F Δ ht hi
    generalize hS : Stmt.catchR x m0 s = S at ht hi
    induction ht with
    | catchR hxF hs hM hanch hKO _ =>
      cases hS
      have hsp' : (K r').spine = s.spine := by rw [Redex.spine_eq h hsp, ← Redex.eq h]
      exact StmtT.catchR hxF (ih hsp hhole _ _ _ hs hi.catchIn) hM hanch (by rw [hsp']; exact hKO)
    | sub hw _ ho ih0 => exact StmtT.sub hw (ih0 hS (hi.weaker hw)) ho
    | _ => cases hS
  | @scopeD x f s r K h ih =>
    intro Γ F Δ ht hi
    generalize hS : Stmt.scopeD x f s = S at ht hi
    induction ht with
    | scopeD hxE hxF hs hpx hKO hWd hNd _ =>
      cases hS
      have hsp' : (K r').spine = s.spine := by rw [Redex.spine_eq h hsp, ← Redex.eq h]
      obtain ⟨Ex, hx, hmo, hrest⟩ := hxE
      exact StmtT.scopeD ⟨Ex, hx, hmo, hrest⟩ hxF
        (ih hsp hhole _ _ _ hs ((Inv.scopeD_iff.mp hi).scopeIn hx (by rw [hmo]; simp))) hpx
        (by rw [hsp']; exact hKO) hWd hNd
    | sub hw _ ho ih0 => exact StmtT.sub hw (ih0 hS (hi.weaker hw)) ho
    | _ => cases hS

/-! ### The moves, typed -/

/-- Every borrowed parameter of `Γ'` is one of `Γ`'s, with its
    dependencies. -/
def RbFrom (Γ Γ' : Ctx) : Prop :=
  ∀ p E, Γ' p = some E → E.mode = .rootb →
    ∃ E0, Γ p = some E0 ∧ E0.mode = .rootb ∧ E0.vdeps = E.vdeps

theorem RbFrom.trans {Γ1 Γ2 Γ3 : Ctx} (h1 : RbFrom Γ1 Γ2) (h2 : RbFrom Γ2 Γ3) : RbFrom Γ1 Γ3 := by
  intro p E hp hm
  obtain ⟨E2, h2', hm2, hv2⟩ := h2 p E hp hm
  obtain ⟨E1, h1', hm1, hv1⟩ := h1 p E2 h2' hm2
  exact ⟨E1, h1', hm1, hv1.trans hv2⟩

theorem rbFrom_kill (Γ : Ctx) (e : Eff) (hv : Bool) (y : Var) : RbFrom Γ (A2.kill e hv y Γ) := by
  intro p E hp hm
  simp only [A2.kill] at hp
  obtain ⟨E0, h0, rfl⟩ := Option.map_eq_some_iff.mp hp
  exact ⟨E0, h0, by rw [killE_mode] at hm; exact hm, (killE_vdeps ..).symm⟩

theorem rbFrom_setE (Γ : Ctx) {y : Var} {E : Entry} (hE : E.mode ≠ .rootb) : RbFrom Γ (A2.setE Γ y E) := by
  intro p E' hp hm
  by_cases hpy : p = y
  · subst hpy; simp only [A2.setE, upd_same, Option.some.injEq] at hp; subst hp; exact absurd hm hE
  · simp only [A2.setE, upd_ne _ _ hpy] at hp; exact ⟨E', hp, hm, rfl⟩

theorem noPin_of_rbFrom {Γ Γ' : Ctx} (h : RbFrom Γ Γ') {y : Var} (hp : NoPin Γ y) : NoPin Γ' y := by
  intro p E hpE hm d hd hb
  obtain ⟨E0, h0, hm0, hv0⟩ := h p E hpE hm
  exact hp p E0 h0 hm0 d (by rw [hv0]; exact hd) hb

/-- **The moves are typed**: each `sink` argument moved into `x`, whose
    scope ends at once, leaves the context the call's parameters leave
    (`callPostAux`).  An argument is reached from no other, so moving one
    ends none of the others. -/
theorem drops_typed {P : Prog} {Γ0 : Ctx} {F : List Var} {fn : Fn} {args : List Var} {x : Var}
    {L : Stmt} {Δ : Ctx} (hL : L.src = true) (hxF : x ∉ F) :
    ∀ (ps : List (PMode × Ty)) (as : List Var) (i : Nat) (Γc : Ctx),
      (∀ q ∈ ps, q.1 = .sink) → ps.length = as.length → as.Nodup →
      (∀ a ∈ as, Γc a = some (argE Γ0 a) ∧ (argE Γ0 a).live = true ∧ (argE Γ0 a).mode = .own ∧
        a ∉ F ∧ NoPin Γc a) →
      (∀ a ∈ as, DtorSafe Γc .replace false a) →
      (∀ a ∈ as, ∀ a' ∈ as, a ≠ a' → ∀ d ∈ (argE Γ0 a').vdeps, d.root ≠ a) →
      Γc x = none → CtxWF Γc → NoPin Γc x →
      StmtT P (callPostAux Γ0 fn args ps as i Γc) F L Δ → StmtT P Γc F (dropSeq x as L) Δ := by
  intro ps
  induction ps with
  | nil =>
    intro as i Γc _ hlen _ _ _ _ _ _ _ ht
    cases as with
    | nil => exact ht
    | cons _ _ => simp at hlen
  | cons q ps ih =>
    intro as i Γc hsk hlen hnd hargs hds0 hdep hx hwf hnx ht
    cases as with
    | nil => simp at hlen
    | cons a as =>
      obtain ⟨pm, t⟩ := q
      have hpm : pm = .sink := hsk (pm, t) List.mem_cons_self
      subst hpm
      obtain ⟨hca, hl, hmo, haF, hpa⟩ := hargs a List.mem_cons_self
      have hax : a ≠ x := fun e => by rw [e, hx] at hca; cases hca
      have hnd' := List.nodup_cons.mp hnd
      -- the context after `a` moved out
      have hrb : RbFrom Γc (A2.setE (A2.kill .replace false a Γc) a { argE Γ0 a with live := false, dtor := false }) :=
        (rbFrom_kill Γc _ _ a).trans (rbFrom_setE _ (by simp [hmo]))
      have hx1 : A2.setE (A2.kill .replace false a Γc) a { argE Γ0 a with live := false, dtor := false } x = none := by
        simp [A2.setE, upd_ne _ _ hax.symm, A2.kill, hx]
      have hwf1 : CtxWF (A2.setE (A2.kill .replace false a Γc) a { argE Γ0 a with live := false, dtor := false }) :=
        hwf.moveOut hca .replace false
      have ht1 : StmtT P (A2.setE (A2.kill .replace false a Γc) a { argE Γ0 a with live := false, dtor := false }) F
          (dropSeq x as L) Δ := by
        refine ih as (i + 1) _ (fun q hq => hsk q (List.mem_cons_of_mem _ hq)) (by simpa using hlen)
          hnd'.2 (fun a' ha' => ?_)
          (fun a' ha' => ((hds0 a' (List.mem_cons_of_mem _ ha')).kill _ _ _).setE_off rfl)
          (fun b hb b' hb' => hdep b (List.mem_cons_of_mem _ hb) b' (List.mem_cons_of_mem _ hb'))
          hx1 hwf1 (noPin_of_rbFrom hrb hnx) ht
        have ha'a : a' ≠ a := fun e => hnd'.1 (e ▸ ha')
        obtain ⟨hca', hl', hmo', haF', hpa'⟩ := hargs a' (List.mem_cons_of_mem _ ha')
        refine ⟨?_, hl', hmo', haF', noPin_of_rbFrom hrb hpa'⟩
        have hno := hdep a List.mem_cons_self a' (List.mem_cons_of_mem _ ha') (Ne.symm ha'a)
        simp [A2.setE, upd_ne _ _ ha'a, A2.kill, hca', killE_nohit hno]
      -- `a` moves into `x`, and `x`'s scope ends
      have hlet : StmtT P Γc F (.letv x (.var a) .skip)
          (A2.setE (A2.kill .replace false a Γc) a { argE Γ0 a with live := false, dtor := false }) := by
        have h := StmtT.letv (P := P) (s := .skip) rfl hx hxF
          (RhsT.moveOwn hca hl hmo haF hpa (hds0 a List.mem_cons_self))
          StmtT.skip ⟨noPin_of_rbFrom (hrb.trans (rbFrom_setE _ (by simp))) hnx,
            (DtorSafe.of_fresh hwf1 hx1 _ _).setE_off rfl, (DbindSafe.of_fresh hwf1 hx1).setE_off rfl⟩
        rwa [exitScope_setE_fresh hwf1 hx1] at h
      exact StmtT.seq (dropSeq_src hL as) hlet ht1

/-- A spawned function returns an unowned integer, and takes only `sink`
    parameters. -/
theorem spawn_fn {P : Prog} {spawn : Nat → Bool} (hP : ProgOK P) (hS : SpawnOK P spawn) {f : Nat}
    {fn : Fn} (hsp : spawn f = true) (hf : P[f]? = some fn) :
    fn.resTy = .int ∧ fn.resOwn = false ∧ ∀ pt ∈ fn.params, pt.1 = .sink ∧ pt.2.holdsView = false := by
  obtain ⟨fn', hf', hres, hall⟩ := hS f hsp
  rw [hf] at hf'; cases hf'
  refine ⟨hres, ?_, hall⟩
  obtain ⟨_, _, _, _, hro, _⟩ := hP fn (List.mem_of_getElem? hf)
  cases h : fn.resOwn with
  | false => rfl
  | true => have := hro h; rw [hres] at this; cases this

/-- **At the hole**: a spawn's call, typed and with the invariant, types its
    moves and the binding of its result to `0` the same way.  The context
    after the moves is the call's (`callPostAux`); running the closures the
    arguments hold (`callPost`) only ends entries, and the result is an
    unowned integer, so `x := 0` is as strong as the call's result. -/
theorem spawn_hole {P : Prog} {spawn : Nat → Bool} (hP : ProgOK P) (hS : SpawnOK P spawn) {m : Mem}
    {x f : Nat} {args : List Var} {k : Stmt} {fn : Fn} (hsp : spawn f = true) (hf : P[f]? = some fn)
    (hnd : args.Nodup) :
    ∀ Γ F Δ, StmtT P Γ F (.letcall x f args k) Δ → Inv m Γ F (.letcall x f args k) →
      StmtT P Γ F (dropSeq x args (.letv x (.expr (.lit 0)) k)) Δ := by
  obtain ⟨hres, hro, hall⟩ := spawn_fn hP hS hsp hf
  intro Γt Ft Δt ht hi
  generalize hS' : Stmt.letcall x f args k = S at ht hi
  induction ht with
  | @letcall Γ Γ1 Δ F x0 f0 args0 k0 E hsrc hx hxF hc hk hpin _ =>
    cases hS'
    obtain ⟨fn', hf', hlen, hargs, hnf, hds, rfl, rfl⟩ := hc
    rw [hf] at hf'; cases hf'
    have hc' : CallT P Γ F f args (callRes Γ fn args) (callPost Γ fn args) :=
      ⟨fn, hf, hlen, hargs, hnf, hds, rfl, rfl⟩
    have h := callH_of hP hf hx hxF hc' hi
    have hsk : ∀ i (hi : i < fn.params.length), fn.params[i].1 = .sink :=
      fun i hi => (hall _ (List.getElem_mem hi)).1
    -- the arguments, as the moves need them
    have hargs' : ∀ a ∈ args, Γ a = some (argE Γ a) ∧ (argE Γ a).live = true ∧
        (argE Γ a).mode = .own ∧ a ∉ F ∧ NoPin Γ a := by
      intro a ha
      obtain ⟨i, hi', rfl⟩ := mem_args ha
      have hip : i < fn.params.length := hlen ▸ hi'
      obtain ⟨Ea, hEa, hl, hok, hmv, hpn⟩ := hargs i hip
      have hae : argE Γ (args.getD i 0) = Ea := by unfold argE; rw [hEa]; rfl
      have hs := hsk i hip
      rw [hs] at hok
      obtain ⟨_, hmo, _⟩ := hok
      rw [hae]
      exact ⟨hEa, hl, hmo, (hmv (by rw [hs]; rfl)).1, hpn (Or.inl hs)⟩
    have hdsa : ∀ a ∈ args, DtorSafe Γ .replace false a := by
      intro a ha
      obtain ⟨i, hi', rfl⟩ := mem_args ha
      exact (hds.1 i (hlen ▸ hi')).1 (hsk i (hlen ▸ hi'))
    have hdep : ∀ a ∈ args, ∀ a' ∈ args, a ≠ a' → ∀ d ∈ (argE Γ a').vdeps, d.root ≠ a := by
      intro a ha a' ha' _ d hd hda
      obtain ⟨i, hi', rfl⟩ := mem_args ha
      obtain ⟨j, hj', rfl⟩ := mem_args ha'
      have hip : i < fn.params.length := hlen ▸ hi'
      have hjp : j < fn.params.length := hlen ▸ hj'
      exact h.moving_sink hip hjp (hsk i hip) (by rw [← hda]; exact List.mem_map_of_mem hd)
    have hnx : NoPin Γ x := by
      intro p E hp hm d hd _ hdx
      obtain ⟨Er, hEr, _⟩ := hi.wf p E hp (hi.rootbLive p E hp hm) (Or.inr hm) d.root
        (List.mem_map_of_mem hd)
      rw [hdx, hx] at hEr; cases hEr
    -- the context the moves leave
    have hdt : DomTy Γ (callPostAux Γ fn args fn.params args 0 Γ) :=
      callPostAux_domTy fn.params args 0 Γ (fun a ha => ⟨_, (hargs' a ha).1⟩) (DomTy.refl Γ)
    have hGx : callPostAux Γ fn args fn.params args 0 Γ x = none := by
      have := hdt.1 x
      rw [hx] at this
      cases h' : callPostAux Γ fn args fn.params args 0 Γ x with
      | none => rfl
      | some _ => rw [h'] at this; simp at this
    have hx1 : callPost Γ fn args x = none := by
      have := h.postdt.1 x
      rw [hx] at this
      cases h' : callPost Γ fn args x with
      | none => rfl
      | some _ => rw [h'] at this; simp at this
    -- ... is as strong as the call's
    have hPW : RSetup.PW (callPostAux Γ fn args fn.params args 0 Γ) (callPost Γ fn args) := by
      have := RSetup.PW.killNames' (X := callPostAux Γ fn args fn.params args 0 Γ)
        (Y := callPostAux Γ fn args fn.params args 0 Γ) (M := []) (ds := mutNames Γ args)
        (RSetup.PW.refl _) (fun d hd => Or.inr fun v E hv hfx hl => ?_) (fun d hd => by cases hd)
      · exact this
      obtain ⟨E0, h0, hm0, _⟩ := hdt.2 v E hv
      have hrb : E.mode = .rootb := by
        rcases hfx with h1 | ⟨b, h1, _⟩
        · exact h1
        · exact absurd (hm0.symm.trans h1) (h.noInout v E0 b h0)
      have hrb0 : E0.mode = .rootb := hm0.symm.trans hrb
      have hpost : killNames (mutNames Γ args) (callPostAux Γ fn args fn.params args 0 Γ) v = some E0 :=
        h.post_rootb h0 hrb0
      obtain ⟨E1, h1, -, -, -, -, hlive⟩ := killNames_get (mutNames Γ args) hpost
      rw [hv] at h1; cases h1
      exact (hlive (h.rbLive v E0 h0 hrb0)).2 d hd
    have hEW : EntryWeaker intE (callRes Γ fn args) := by
      refine ⟨by simp [callRes, intE, hres], by simp [callRes, intE, resMode, hro], fun hfx => ?_,
        fun _ => ⟨rfl, fun _ => List.nil_subset _, List.nil_subset _⟩,
        fun h => by simp [intE] at h, by simp [callRes, intE], fun h => by simp [callRes] at h,
        fun h => by simp [intE] at h⟩
      exfalso; simp [Entry.fixed, intE] at hfx
    have hW : Weaker (A2.setE (callPostAux Γ fn args fn.params args 0 Γ) x intE)
        (A2.setE (callPost Γ fn args) x (callRes Γ fn args)) :=
      RSetup.PW.weaker (hPW.setE hEW) (CtxWF.add h.postwf hx1 (fun _ _ r hr => h.reswf r hr))
        h.resnames
    have hlast : StmtT P (callPostAux Γ fn args fn.params args 0 Γ) F (.letv x (.expr (.lit 0)) k)
        (exitScope x Δ) :=
      StmtT.letv hsrc hGx hxF (RhsT.expr ExprT.lit) (StmtT.weakenIn hW hk) hpin
    exact drops_typed (L := .letv x (.expr (.lit 0)) k) hsrc hxF fn.params args 0 Γ
      (fun q hq => (hall q hq).1) hlen.symm hnd hargs' hdsa hdep hx hi.wf hnx hlast
  | sub hw _ ho ih0 => exact StmtT.sub hw (ih0 hS' (hi.weaker hw)) ho
  | _ => cases hS'

/-! ### The moves, run -/

section MoveArgs
variable {st st' : Var → Option Slot} {args : List Var} {vs : List Val}

theorem MoveArgs.owned (h : MoveArgs st args vs st') : ∀ a ∈ args, ∃ v, st a = some ⟨true, some v⟩ := by
  induction h with
  | nil => intro a ha; cases ha
  | @cons st st' a0 as v vs ha0 _ ih =>
    intro a ha
    rcases List.mem_cons.mp ha with rfl | ha
    · exact ⟨v, ha0⟩
    · obtain ⟨w, hw⟩ := ih a ha
      by_cases hae : a = a0
      · subst hae; simp at hw
      · rw [upd_ne _ _ hae] at hw; exact ⟨w, hw⟩

/-- An argument moves once. -/
theorem MoveArgs.nodup (h : MoveArgs st args vs st') : args.Nodup := by
  induction h with
  | nil => exact List.nodup_nil
  | @cons st st' a0 as v vs _ hrest ih =>
    refine List.nodup_cons.mpr ⟨fun ha => ?_, ih⟩
    obtain ⟨w, hw⟩ := MoveArgs.owned hrest a0 ha
    simp at hw

theorem MoveArgs.length (h : MoveArgs st args vs st') : vs.length = args.length := by
  induction h with
  | nil => rfl
  | cons _ _ ih => simp [ih]

/-- The `j`-th value moved is what the `j`-th argument owned. -/
theorem MoveArgs.get (h : MoveArgs st args vs st') :
    ∀ (j : Nat) v, vs[j]? = some v → ∃ a, args[j]? = some a ∧ st a = some ⟨true, some v⟩ := by
  induction h with
  | nil => intro j v hv; simp at hv
  | @cons st st' a0 as v0 vs ha0 _ ih =>
    intro j v hv
    cases j with
    | zero =>
      simp only [List.getElem?_cons_zero, Option.some.injEq] at hv
      subst hv
      exact ⟨a0, by simp, ha0⟩
    | succ j =>
      simp only [List.getElem?_cons_succ] at hv
      obtain ⟨a, haj, hav⟩ := ih j v hv
      have hne : a ≠ a0 := by intro e; subst e; simp at hav
      rw [upd_ne _ _ hne] at hav
      exact ⟨a, by simpa using haj, hav⟩

theorem MoveArgs.other (h : MoveArgs st args vs st') : ∀ y, y ∉ args → st' y = st y := by
  induction h with
  | nil => intro y _; rfl
  | @cons st st' a0 as v vs _ _ ih =>
    intro y hy
    simp only [List.mem_cons, not_or] at hy
    rw [ih y hy.2, upd_ne _ _ hy.1]

/-- **The moved trees can be freed**, one after the other: each is
    well-formed, its addresses distinct and live, and no two share one. -/
theorem MoveArgs.frees (h : MoveArgs st args vs st') : ∀ (a : Nat → Bool),
    (∀ y t, st y = some ⟨true, some t⟩ →
      (∃ τ, WFv τ t) ∧ t.ids.Nodup ∧ ∀ i ∈ t.ids, a i = true) →
    (∀ y z t u, y ≠ z → st y = some ⟨true, some t⟩ → st z = some ⟨true, some u⟩ →
      ∀ i ∈ t.ids, i ∉ u.ids) →
    ∃ a', FreesL a vs a' := by
  induction h with
  | nil => intro a _ _; exact ⟨a, FreesL.nil⟩
  | @cons st st' a0 as v vs ha0 _ ih =>
    intro a hown hdisj
    obtain ⟨⟨τ, hw⟩, hnd, hal⟩ := hown a0 v ha0
    obtain ⟨a1, hf⟩ := frees_exists hw a hnd hal
    have hst : ∀ y t, upd st a0 (some ⟨true, none⟩) y = some ⟨true, some t⟩ →
        y ≠ a0 ∧ st y = some ⟨true, some t⟩ := by
      intro y t hy
      by_cases hya : y = a0
      · subst hya; simp at hy
      · rw [upd_ne _ _ hya] at hy; exact ⟨hya, hy⟩
    have hown' : ∀ y t, upd st a0 (some ⟨true, none⟩) y = some ⟨true, some t⟩ →
        (∃ τ, WFv τ t) ∧ t.ids.Nodup ∧ ∀ i ∈ t.ids, a1 i = true := by
      intro y t hy
      obtain ⟨hya, hy'⟩ := hst y t hy
      obtain ⟨hw', hnd', hal'⟩ := hown y t hy'
      refine ⟨hw', hnd', fun i hi => ?_⟩
      rw [hf.other (fun hv => hdisj y a0 t v hya hy' ha0 i hi hv)]
      exact hal' i hi
    obtain ⟨a', hfl⟩ := ih a1 hown' (fun y z t u hne hy hz => hdisj y z t u hne (hst y t hy).2 (hst z u hz).2)
    exact ⟨a', FreesL.cons hf hfl⟩

end MoveArgs

/-- **The moves, run**: from bindings `st`, the moves free the trees `vs`
    one after the other (`FreesL`) and leave the arguments' slots empty
    (`st'`), then the rest runs. -/
theorem dropSeq_run {s0 r0 : Stmt} {K : Stmt → Stmt} (hR : Redex s0 K r0) {P : Prog} {x : Var}
    {L : Stmt} {st : Var → Option Slot} {args : List Var} {vs : List Val} {st' : Var → Option Slot}
    (h : MoveArgs st args vs st') :
    ∀ (m : Mem), m.st = st → st x = none → ∀ {a' : Nat → Bool}, FreesL m.alloc vs a' → ∀ {R : Res},
      Steps P { m with alloc := a', st := st' } (K L) R → Steps P m (K (dropSeq x args L)) R := by
  induction h with
  | nil =>
    intro m hm _ a' hf R hrest
    cases hf
    subst hm
    exact hrest
  | @cons st st' a0 as v vs ha0 _ ih =>
    intro m hm hx a' hf R hrest
    subst hm
    cases hf with
    | cons hf1 hfl =>
      rename_i a1
      have hax : a0 ≠ x := fun e => by rw [e, hx] at ha0; cases ha0
      have hx' : upd m.st a0 (some ⟨true, none⟩) x = none := by rw [upd_ne _ _ hax.symm]; exact hx
      have h1 : Step P m (.letv x (.var a0) .skip)
          (.ok ((m.set a0 ⟨true, none⟩).set x ⟨true, some v⟩) (.scope x .skip)) :=
        Step.letv hx (EvalR.moveOwn ha0)
      have h2 : Step P ((m.set a0 ⟨true, none⟩).set x ⟨true, some v⟩) (.scope x .skip)
          (.ok ({ ((m.set a0 ⟨true, none⟩).set x ⟨true, some v⟩) with alloc := a1 }.remove x) .skip) :=
        Step.scopeSkip (by simp) (DropSlot.owned hf1)
      have heq : { ((m.set a0 ⟨true, none⟩).set x ⟨true, some v⟩) with alloc := a1 }.remove x =
          { m with alloc := a1, st := upd m.st a0 (some ⟨true, none⟩) } := by
        simp only [Mem.remove, Mem.set]
        congr 1
        funext y
        by_cases hyx : y = x
        · subst hyx; simp [upd_ne _ _ hax.symm, hx]
        · simp [upd_ne _ _ hyx]
      refine Steps.step (hR.step (Step.seqL h1)) (Steps.step (hR.step (Step.seqL h2)) ?_)
      rw [heq]
      exact Steps.step (hR.step Step.seqSkip) (ih _ rfl hx' hfl hrest)

/-! ### The spawner after the spawn -/

theorem Redex.codes_hole {s r : Stmt} {K : Stmt → Stmt} (h : Redex s K r) {P : Prog}
    (hs : (K r).codesOK P) : r.codesOK P := by
  induction h with
  | here => exact hs
  | seq _ ih => exact ih hs.1
  | scope _ ih => exact ih hs
  | rbind _ ih => exact ih hs
  | frozen _ ih => exact ih hs
  | catchR _ ih => exact ih hs
  | scopeD _ ih => exact ih hs

/-- A typed call is checked against its callee, in a context of the
    invariant. -/
theorem letcall_call {P : Prog} {m : Mem} {Γ : Ctx} {F : List Var} {x f : Nat} {args : List Var}
    {k : Stmt} {Δ : Ctx} (ht : StmtT P Γ F (.letcall x f args k) Δ)
    (hi : Inv m Γ F (.letcall x f args k)) : ∃ Γ0 E Γ1, CallT P Γ0 F f args E Γ1 ∧ MInv m Γ0 := by
  generalize hS : Stmt.letcall x f args k = S at ht hi
  induction ht with
  | letcall _ _ _ hc _ _ _ => cases hS; exact ⟨_, _, _, hc, hi.toMInv⟩
  | sub hw _ _ ih0 => exact ih0 hS (hi.weaker hw)
  | _ => cases hS

/-- An owned tree is well-formed at its binding's type. -/
theorem owned_wf {m : Mem} {Γ : Ctx} (hi : MInv m Γ) {y : Var} {t : Val}
    (hy : m.st y = some ⟨true, some t⟩) : ∃ E, Γ y = some E ∧ WFv E.ty t := by
  have hd := hi.dom y
  rw [hy] at hd
  obtain ⟨E, hE⟩ := Option.isSome_iff_exists.mp hd
  obtain ⟨sl, hsl, _, ho, hown, _⟩ := hi.slot y E hE
  rw [hy] at hsl; cases hsl
  exact ⟨E, hE, (hown ho.symm).2.1 t rfl⟩

/-- **The spawner after a spawn**: the moved trees are freed from its own
    part of the address space, in argument order, and A2 knows of what is
    left what it knew before — the spawner goes on with its result bound to
    `0`. -/
theorem spawner_ok {P : Prog} {spawn : Nat → Bool} (hP : ProgOK P) (hPc : ProgCodes P) (hS : SpawnOK P spawn)
    {m : Mem} {s : Stmt} (hok : ThreadOK P m s) {K : Stmt → Stmt} {x f : Nat} {args : List Var} {k : Stmt}
    {fn : Fn} {vs : List Val} {st' : Var → Option Slot}
    (hR : Redex s K (.letcall x f args k)) (hsp : spawn f = true) (hf : P[f]? = some fn)
    (hx : m.st x = none) (hmv : MoveArgs m.st args vs st') :
    ∃ a', FreesL m.alloc vs a' ∧
      ThreadOK P { m with alloc := a', st := upd st' x (some ⟨false, some (.int 0)⟩) } (K (.scope x k)) := by
  obtain ⟨Γ, F, Δ, ht, hi, hcd, hsc, hc⟩ := hok
  have hown : ∀ y t, m.st y = some ⟨true, some t⟩ →
      (∃ τ, WFv τ t) ∧ t.ids.Nodup ∧ ∀ i ∈ t.ids, m.alloc i = true := by
    intro y t hy
    obtain ⟨E, _, hw⟩ := owned_wf hi.toMInv hy
    exact ⟨⟨_, hw⟩, hi.heap.nodup y t hy, fun i hi' => (hi.heap.alloc y t hy i hi').1⟩
  obtain ⟨a', hfl⟩ := hmv.frees m.alloc hown (fun y z t u hne hy hz => hi.heap.disj y z t u hne hy hz)
  refine ⟨a', hfl, ?_⟩
  have hs : s = K (.letcall x f args k) := hR.eq
  subst hs
  have hDsp : (dropSeq x args (.letv x (.expr (.lit 0)) k)).spine = (Stmt.letcall x f args k).spine :=
    dropSeq_spine x _ rfl args
  have hsp' := hR.spine_eq hDsp
  -- the spawner's part, as A2 runs it: the moves, then `x := 0`
  have ht' := hR.plug hDsp (spawn_hole hP hS hsp hf hmv.nodup) Γ F Δ ht hi
  have hi' : Inv m Γ F (K (dropSeq x args (.letv x (.expr (.lit 0)) k))) := by
    refine hi.respine hsp' (hR.vars_sub fun v hv => ?_) (hR.catchOK hDsp ?_ hi.catchOK)
      (hR.pinOK hDsp ?_ hi.pinIn) (hR.dtorPinOK hDsp ?_ hi.dtorIn)
    · have hv' : v = x ∨ v ∈ args ∨ v ∈ k.vars := by
        rcases dropSeq_vars args v hv with h | h | h
        · exact .inl h
        · exact .inr (.inl h)
        · simp [Stmt.vars, Rhs.vars, Expr.vars] at h
          exact h.imp_right .inr
      simp only [Stmt.vars, List.mem_cons, List.mem_append]
      exact or_assoc.mpr hv'
    · cases args <;> exact trivial
    · cases args <;> exact trivial
    · cases args <;> exact trivial
  have hsc' : (K (dropSeq x args (.letv x (.expr (.lit 0)) k))).codesOK P :=
    hR.codesOK (dropSeq_codes (L := .letv x (.expr (.lit 0)) k)
      (show (Stmt.letv x (.expr (.lit 0)) k).codesOK P from ⟨trivial, hR.codes_hole hsc⟩) args) hsc
  have hc' : Closed Γ (K (dropSeq x args (.letv x (.expr (.lit 0)) k))) := by
    intro v hv; rw [hsp']; exact hc v hv
  have hxa : x ∉ args := fun hxa => by
    obtain ⟨w, hw⟩ := hmv.owned x hxa
    rw [hx] at hw; cases hw
  have hrun : Steps P m (K (dropSeq x args (.letv x (.expr (.lit 0)) k)))
      (.ok { m with alloc := a', st := upd st' x (some ⟨false, some (.int 0)⟩) } (K (.scope x k))) :=
    dropSeq_run hR hmv m rfl hx hfl
      (Steps.step (hR.step (Step.letv (by show st' x = none; rw [hmv.other x hxa]; exact hx)
        (EvalR.expr Eval.lit))) Steps.refl)
  obtain ⟨Γ', ht'', hi'', hc'', hcd'', hsc''⟩ := reach_ok hP hPc ht' hcd hsc' hi' hc' hrun
  exact ⟨Γ', F, Δ, ht'', hi'', hcd'', hsc'', hc''⟩

/-- **What moves to the new thread**: one value per parameter, each of its
    parameter's type, each the tree its argument owned, no two sharing an
    address. -/
theorem spawn_args {P : Prog} {spawn : Nat → Bool} (hP : ProgOK P) (hS : SpawnOK P spawn)
    {m : Mem} {s : Stmt} (hok : ThreadOK P m s) {K : Stmt → Stmt} {x f : Nat} {args : List Var} {k : Stmt}
    {fn : Fn} {vs : List Val} {st' : Var → Option Slot}
    (hR : Redex s K (.letcall x f args k)) (hsp : spawn f = true) (hf : P[f]? = some fn)
    (hmv : MoveArgs m.st args vs st') :
    vs.length = fn.params.length ∧
    (∀ (j : Nat) (v : Val) (pt : PMode × Ty), vs[j]? = some v → fn.params[j]? = some pt →
      WFv pt.2 v) ∧
    (∀ (j : Nat) (v : Val), vs[j]? = some v →
      ∃ a, args[j]? = some a ∧ m.st a = some ⟨true, some v⟩) ∧
    (∀ (j k : Nat) (v w : Val), j ≠ k → vs[j]? = some v → vs[k]? = some w →
      ∀ i ∈ v.ids, i ∉ w.ids) := by
  obtain ⟨Γ, F, Δ, ht, hi, -, -, -⟩ := hok
  obtain ⟨Γh, Fh, Δh, hth, hih⟩ := hR.typed Γ F Δ ht hi
  obtain ⟨Γ0, E, Γ1, hc, hm0⟩ := letcall_call hth hih
  obtain ⟨fn', hf', hlen, hargs, -⟩ := hc
  rw [hf] at hf'; cases hf'
  obtain ⟨-, -, hall⟩ := spawn_fn hP hS hsp hf
  refine ⟨hmv.length.trans hlen, fun j v pt hv hpt => ?_, hmv.get, fun j k v w hjk hv hw => ?_⟩
  · obtain ⟨a, ha, hav⟩ := hmv.get j v hv
    obtain ⟨hj, hptj⟩ := List.getElem?_eq_some_iff.mp hpt
    obtain ⟨Ea, hEa, -, hok, -⟩ := hargs j hj
    have hgd : args.getD j 0 = a := by simp [List.getD, ha]
    rw [hgd] at hEa
    rw [hptj, (hall pt (List.mem_of_getElem? hpt)).1] at hok
    obtain ⟨hty, -, -⟩ := hok
    obtain ⟨E', hE', hw⟩ := owned_wf hm0 hav
    rw [hEa] at hE'; cases hE'
    rw [← hty]; exact hw
  · obtain ⟨a, ha, hav⟩ := hmv.get j v hv
    obtain ⟨b, hb, hbw⟩ := hmv.get k w hw
    have hab : a ≠ b := by
      intro e; subst e
      have hjl : j < args.length := (List.getElem?_eq_some_iff.mp ha).1
      exact hjk ((List.Nodup.getElem?_inj hjl hmv.nodup).mp (ha.trans hb.symm))
    exact hi.heap.disj a b v w hab hav hbw

/-- What the new thread's facts need of each moved tree, from the spawner's:
    its addresses are distinct, live and below `nid`, it views none of its
    own buffers, its packages' captures are well-formed and its packages
    name code of their signature. -/
theorem moved_trees {P : Prog} {m : Mem} {s : Stmt} (hok : ThreadOK P m s) {args : List Var}
    {vs : List Val} {st' : Var → Option Slot} (hmv : MoveArgs m.st args vs st') :
    ∀ v ∈ vs, v.ids.Nodup ∧ SelfFree v ∧ (∀ i ∈ v.ids, m.alloc i = true ∧ i < m.nid) ∧
      PkgsOK v ∧ PkgOK P v := by
  obtain ⟨Γ, F, Δ, -, hi, hcd, -, -⟩ := hok
  intro v hv
  obtain ⟨j, hj, hjv⟩ := List.getElem_of_mem hv
  obtain ⟨a, -, hav⟩ := hmv.get j v (by rw [List.getElem?_eq_getElem hj, hjv])
  exact ⟨hi.heap.nodup a v hav, hi.heap.self a v hav, hi.heap.alloc a v hav, hi.pkgs a _ v hav rfl,
    memCodes_iff.mp hcd a true v hav⟩

end A3
