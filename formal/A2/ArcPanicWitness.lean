import A2.ArcDtorWitness

/-! A2 — Agora #790: an orphan the unwinding makes is reaped inside the frame
that caught it.

When a panic's unwinding drops the last share of an `Arc` of a destructor
value, the block is orphaned when a frame catches the panic: a destructor
frame (`Step.scopeDP`, `scopeDPDrain`) or a `recover` (`Step.catchP`); the
marking sweep that ends that step marks it `dead`, and the thread's next
step is its reap (`Settle`), at the thread's redex.  Both catching steps
leave the frame in place, at its end (`seq (scopeD x f skip) panic`,
`catchR x m0 skip`), so the only redex is that end's `skip`, inside the
frame: the reaped destructor runs inside it, and a panic of that destructor
comes back to the same frame.  So x's own destructor still runs after it,
and the `recover` still catches, as nurlc's journal drain does: a panic
raised by a drop while a frame's journal drains is caught by the same
frame, the drain releases what is left, and the first panic goes on
(`stdlib/runtime_core.c`, `nurl_panic`).

* Steps, of any program: `frame_reap_inside` / `recover_reap_inside` (the
  reap a `Settle` takes there lands inside the frame), `reaped_panic_runs_dtor`
  (a panic out of the reaped frame comes back to x's frame, whose end then
  calls x's destructor and nothing else), `recover_catches_reaped`,
  `catchR_no_panic` (no step of a `recover` frame is a panic).
* The witness programs (`P`: `dfn`, the destructor of `DT`; `pfn`, the
  destructor of `DP`, which panics; `rfn`, a function a `recover` calls):
  `main1`, a destructor binding `x` (of `DT`) whose scope panics while an
  `Arc` of a `DP` value is its last share's (typed, safe, `no_leak_panic`,
  `no_leak_end`; `main1_reap`); `main2`, a `recover` of `rfn`, whose body
  makes such an `Arc` and panics (typed, safe, leak-free both ways;
  `main2_reap`).  As for the other witnesses, no theorem traces the runs:
  the steps above are theorems about any store and statement of their shape. -/

namespace A2.ArcPanicWitness
open A2.DynCell (NoRootb noRootb_empty)
open A2.DtorWitness (NoDeps T DT dfn EP R0)

/-! ### The steps, of any program -/

/-- `skip` never panics. -/
theorem skip_no_panic {P : Prog} {m m' : Mem} (h : Step P m .skip (.panic m')) : False := by
  cases h with
  | waitPanic hw => exact hw

/-- A reap changes the store's blocks: its block is emptied. -/
theorem reapMem_blk {m m1 : Mem} (hr : ReapMem m m1) (he : m1.blk = m.blk) : False := by
  obtain ⟨k, n, f, u, p, hk, rfl⟩ := hr
  have h := congrFun he k
  simp only [upd] at h
  rw [hk] at h
  cases h

/-- **Agora #790: after a destructor frame caught the unwinding**
    (`Step.scopeDP` / `scopeDPDrain`: the frame at its end, the panic
    after it), a reap (`Settle`'s next step while an orphan is left) lands
    inside the frame, at its end's `skip`: the reaped destructor's frame
    runs inside `x`'s. -/
theorem frame_reap_inside {P : Prog} {m m1 : Mem} {x : Var} {f : Nat} {s1 : Stmt}
    (h : Step P m (.seq (.scopeD x f .skip) .panic) (.ok m1 s1)) (hr : ReapMem m m1) :
    ∃ g, s1 = .seq (.scopeD x f (.seq (.scopeD m.nv g .skip) .skip)) .panic := by
  cases h with
  | reap hrs _ _ => cases hrs
  | seqL h =>
    cases h with
    | reap hrs _ _ => cases hrs
    | scopeDIn h =>
      cases h with
      | reap _ _ _ => exact ⟨_, rfl⟩
    | scopeDEnd _ _ => exact (reapMem_blk hr rfl).elim
    | scopeDMoved _ => exact (reapMem_blk hr rfl).elim
    | scopeDDrain _ => exact (reapMem_blk hr rfl).elim
    | scopeDEmpty _ => exact (reapMem_blk hr rfl).elim
    | scopeDP hs _ _ => exact (skip_no_panic hs).elim
    | scopeDPDrain hs _ => exact (skip_no_panic hs).elim

/-- **... and a panic out of the reaped frame comes back to `x`'s frame**,
    which is left at its end again, followed by the panic (twice: the
    reaped destructor's, then the unwinding's); from there (no orphan left)
    the only step is that end, which calls `x`'s destructor `f` on `x`.  So
    a panicking destructor of what the unwinding orphaned does not skip
    `x`'s own (before Agora #790 the reap sat at the call of `f`, inside
    `scope x`, and the panic dropped the call). -/
theorem reaped_panic_runs_dtor {P : Prog} {m m1 : Mem} {x : Var} {f : Nat} {t : Stmt} {v : Val}
    (ht : Step P m t (.panic m1)) (hx : m1.st x = some ⟨true, some v⟩) (hv : v.isNode = false) :
    Step P m (.seq (.scopeD x f t) .panic) (.ok m1 (.seq (.seq (.scopeD x f .skip) .panic) .panic)) ∧
      (¬ Orphan m1 → ∀ r, Step P m1 (.seq (.seq (.scopeD x f .skip) .panic) .panic) r ↔
        r = .ok { m1 with nv := m1.nv + 1 }
          (.seq (.seq (.scope x (.letcall m1.nv f [x] .skip)) .panic) .panic)) := by
  obtain ⟨h1, h2⟩ := A2.Dtor.scopeD_panic_runs_dtor (f := f) ht hx hv
  refine ⟨Step.seqL h1, fun hno r => ⟨fun h => ?_, fun h => h ▸ Step.seqL ((h2 hno _).mpr rfl)⟩⟩
  cases h with
  | reap hrs _ _ => cases hrs
  | seqL h => cases (h2 hno _).mp h; rfl
  | seqP h => cases (h2 hno _).mp h
  | waitPanic hw => exact hw.elim

/-- **Agora #790: after a `recover` caught the unwinding** (`Step.catchP`:
    the frame at its end), a reap lands inside the frame, at its `skip`. -/
theorem recover_reap_inside {P : Prog} {m m1 : Mem} {x : Var} {m0 : Mem} {s1 : Stmt}
    (h : Step P m (.catchR x m0 .skip) (.ok m1 s1)) (hr : ReapMem m m1) :
    ∃ g, s1 = .catchR x m0 (.seq (.scopeD m.nv g .skip) .skip) := by
  cases h with
  | reap hrs _ _ => cases hrs
  | catchIn h =>
    cases h with
    | reap _ _ _ => exact ⟨_, rfl⟩
  | catchSkip => exact (reapMem_blk hr rfl).elim
  | catchP hs _ => exact (skip_no_panic hs).elim

/-- **No step of a `recover` frame is a panic**: whatever its body raises,
    the frame catches. -/
theorem catchR_no_panic {P : Prog} {m m' : Mem} {x : Var} {m0 : Mem} {s : Stmt} :
    ¬ Step P m (.catchR x m0 s) (.panic m') := by
  intro h
  cases h with
  | waitPanic hw => exact hw

/-- **... so a panic of the reaped destructor is caught by the same
    `recover`**: the frame is at its end again, `x` saying the call failed. -/
theorem recover_catches_reaped {P : Prog} {m m1 : Mem} {x : Var} {m0 : Mem} {t : Stmt}
    (ht : Step P m t (.panic m1)) (hx : (m1.st x).isSome) :
    Step P m (.catchR x m0 t) (.ok (m1.set x ⟨false, some (.int 1)⟩) (.catchR x m0 .skip)) :=
  Step.catchP ht hx

/-! ### The program -/

/-- The destructor type whose destructor panics: the struct `T` again, its
    destructor `pfn`. -/
def DP : Ty := .dtor 1 T

/-- the panicking destructor: `@ pdrop in self → i { = r 0  ( panic ) }` -/
def pfn : Fn where
  params := [(.inp, DP)]
  resTy := .int
  resOwn := false
  lends := []
  rholds := []
  outHolds := []
  body := .seq (.assign 1 (.expr (.lit 0))) .panic
  nvars := 2

/-- `: a 1  : b 2  :drop y ( pair a b )  : s ( arc_new y )  ( panic )`: an
    `Arc` of a `DP` value, whose only share `s` the panic's unwinding drops. -/
def tail (a b y s : Var) : Stmt :=
  .letv a (.expr (.lit 1)) (.letv b (.expr (.lit 2))
    (.letd y 1 (.pair a b) (.letv s (.arcNew DP y) .panic)))

/-- the function a `recover` calls: `@ rfn → i { = r 0  tail }` -/
def rfn : Fn where
  params := []
  resTy := .int
  resOwn := false
  lends := []
  rholds := []
  outHolds := []
  body := .seq (.assign 0 (.expr (.lit 0))) (tail 1 2 3 4)
  nvars := 5

def P : Prog := [dfn, pfn, rfn]

theorem dfn_not_thru : ¬ ThruFn P 0 := by
  intro h
  cases h with
  | here hf hb => simp [P] at hf; subst hf; simp [dfn, Stmt.hasThru] at hb
  | call hf hg _ => simp [P] at hf; subst hf; simp [dfn, Stmt.calls] at hg

theorem pfn_not_thru : ¬ ThruFn P 1 := by
  intro h
  cases h with
  | here hf hb => simp [P] at hf; subst hf; simp [pfn, Stmt.hasThru] at hb
  | call hf hg _ => simp [P] at hf; subst hf; simp [pfn, Stmt.calls] at hg

theorem drop0_ok : DropFnOK P 0 T :=
  Or.inl ⟨⟨dfn, rfl, rfl, rfl, rfl, rfl, rfl, rfl, dfn_not_thru⟩, by decide⟩

theorem drop1_ok : DropFnOK P 1 T :=
  Or.inl ⟨⟨pfn, rfl, rfl, rfl, rfl, rfl, rfl, rfl, pfn_not_thru⟩, by decide⟩

/-! ### Typing -/

theorem _root_.A2.DtorWitness.NoDeps.upd_none {Γ : Ctx} (h : NoDeps Γ) (x : Var) : NoDeps (upd Γ x none) := fun v E hv => by
  by_cases hvx : v = x
  · subst hvx; simp at hv
  · rw [upd_ne _ _ hvx] at hv; exact h v E hv

theorem _root_.A2.DtorWitness.NoDeps.exitScope_eq {Γ : Ctx} (h : NoDeps Γ) (x : Var) : exitScope x Γ = upd Γ x none := by
  simp [exitScope, h.kill_eq]

/-- A context with no views and no `letd` binding is well formed. -/
theorem wf_of {Γ : Ctx} (hD : NoDeps Γ) (hf : ∀ v E, Γ v = some E → E.dtor = false ∧ E.dbind = false) :
    CtxWF Γ :=
  ⟨fun v E hE _ _ r hr => by rw [hD v E hE] at hr; simp [roots] at hr,
    fun v E hE hd => (by rw [(hf v E hE).2] at hd; cases hd),
    fun v E hE hd => (by rw [(hf v E hE).1] at hd; cases hd),
    fun v E hE hd => (by rw [(hf v E hE).2] at hd; cases hd)⟩

/-- A panic typed at the context it is in. -/
theorem panic_typed {Γ : Ctx} {F : List Var} (hD : NoDeps Γ)
    (hf : ∀ v E, Γ v = some E → E.dtor = false ∧ E.dbind = false) : StmtT P Γ F .panic Γ :=
  StmtT.panic (wf_of hD hf) hD.names (fun _ => rfl) (fun _ E h => ⟨E, h, rfl, rfl, fun _ => rfl⟩)
    (DKeep.refl _ _) (DStay.refl _ _)

/-- The share's entry: owned, holding nothing. -/
def ES : Entry := ⟨.arc DP, .own, true, [], [], false, false⟩

/-- **`tail` is typed** in any context with no views and no borrowed
    parameter that leaves its four bindings unbound; it ends in that
    context. -/
theorem tail_typed {Γ : Ctx} (hR : NoRootb Γ) (hD : NoDeps Γ) {a b y s : Var}
    (hab : a ≠ b) (hay : a ≠ y) (has : a ≠ s) (hby : b ≠ y) (hbs : b ≠ s) (hys : y ≠ s)
    (ha : Γ a = none) (hb : Γ b = none) (hy : Γ y = none) (hs : Γ s = none) :
    ∃ Δ, StmtT P Γ [] (tail a b y s) Δ ∧ NoRootb Δ ∧ NoDeps Δ ∧
      ∀ v, v ≠ a → v ≠ b → v ≠ y → v ≠ s → Δ v = Γ v := by
  let K1 : Ctx := A2.setE Γ a intE
  let K2 : Ctx := A2.setE K1 b intE
  have hK1 : NoRootb K1 := hR.setE (by simp [intE])
  have hK2 : NoRootb K2 := hK1.setE (by simp [intE])
  have hD2 : NoDeps K2 := (hD.setE rfl).setE rfl
  let ED : Entry := Entry.arm { EP with ty := DP, held := [] }
  have hED : ED.mode ≠ .rootb ∧ ED.dtor = false ∧ ED.dbind = false := by
    simp [ED, EP, Entry.arm, DP, T, Ty.dtorViews, Ty.holdsView]
  let K3 : Ctx := A2.setE K2 y ED
  have hK3 : NoRootb K3 := hK2.setE hED
  have hD3 : NoDeps K3 := hD2.setE (by simp [ED, EP, Entry.arm, Entry.vdeps])
  have hK3d : K3 y = some ED := by simp [K3, A2.setE]
  let ED' : Entry := { ED with live := false, dtor := false }
  let K3' : Ctx := A2.setE K3 y ED'
  have hkill : A2.kill .replace false y K3 = K3 := hD3.kill_eq _ _ _
  have hnew : RhsT K3 [] (.arcNew DP y) ES K3' := by
    have h := RhsT.arcNew (Γ := K3) (F := []) (t := DP) (y := y) (Ey := ED) hK3d
      (by simp [ED, Entry.arm, EP]) (by simp [ED, Entry.arm]) (Or.inr rfl)
      ⟨by simp [DP, T, Ty.holdsView], by simp [DP, T, Ty.hasFn]⟩ (by simp [DP, T, Ty.hasCell])
      (PushArg.move (by simp [DP, T, Ty.owning]) (by simp [ED, Entry.arm, EP]) (by simp)
        (hK3.noPin y) (DtorSafe.of_none (fun v E h => (hK3 v E h).2.1) _ _ _))
    rw [hkill] at h; exact h
  have hK3' : NoRootb K3' := hK3.setE (by simp [ED', ED, EP, Entry.arm, DP, T, Ty.dtorViews, Ty.holdsView])
  have hD3' : NoDeps K3' := hD3.setE (by simp [ED', ED, EP, Entry.arm, Entry.vdeps])
  let K4 : Ctx := A2.setE K3' s ES
  have hK4 : NoRootb K4 := hK3'.setE (by simp [ES])
  have hD4 : NoDeps K4 := hD3'.setE rfl
  have hp := panic_typed (F := []) hD4 (fun v E h => (hK4 v E h).2)
  have hsc := StmtT.letv (P := P) (x := s) (r := .arcNew DP y) (E := ES) (F := []) (Γ := K3) (Γ1 := K3')
    rfl (by simp [K3, K2, K1, A2.setE, upd_ne _ _ hys.symm, upd_ne _ _ hbs.symm, upd_ne _ _ has.symm, hs])
    (by simp) hnew hp (hK4.endOK _) (fun _ => rfl)
  have hpair : RhsT K2 [] (.pair a b) EP K2 :=
    RhsT.pair (Ey := intE) (Ez := intE) (by simp [K2, K1, A2.setE, upd_ne _ _ hab]) rfl PushArg.int
      (by simp [K2, K1, A2.setE]) rfl PushArg.int (by simp [intE, Mode.ownSlot])
  have hd := StmtT.letd (P := P) (Γ := K2) (Γ1 := K2) (F := []) (x := y) (f := 1) (r := .pair a b)
    (E := EP) (t := T) (H := []) rfl (by simp [K2, K1, A2.setE, upd_ne _ _ hby.symm, upd_ne _ _ hay.symm, hy])
    (by simp) hpair rfl (Or.inl ⟨rfl, Or.inl rfl⟩) rfl rfl (letd_fn drop1_ok) (HeldUp.refl _ _) hsc
    ((hK4.exitScope s).endOK _)
  have h2 := StmtT.letv (P := P) (x := b) (r := .expr (.lit 2)) (E := intE) (F := []) (Γ := K1) (Γ1 := K1)
    rfl (by simp [K1, A2.setE, upd_ne _ _ hab.symm, hb]) (by simp) (RhsT.expr ExprT.lit) hd
    (((hK4.exitScope s).exitScope y).endOK _)
  have h1 := StmtT.letv (P := P) (x := a) (r := .expr (.lit 1)) (E := intE) (F := []) (Γ := Γ) (Γ1 := Γ)
    rfl ha (by simp) (RhsT.expr ExprT.lit) h2 ((((hK4.exitScope s).exitScope y).exitScope b).endOK _)
  refine ⟨_, h1, (((hK4.exitScope s).exitScope y).exitScope b).exitScope a, ?_, ?_⟩
  · rw [hD4.exitScope_eq, (hD4.upd_none s).exitScope_eq, ((hD4.upd_none s).upd_none y).exitScope_eq,
      (((hD4.upd_none s).upd_none y).upd_none b).exitScope_eq]
    exact (((hD4.upd_none s).upd_none y).upd_none b).upd_none a
  · intro v hva hvb hvy hvs
    rw [hD4.exitScope_eq, (hD4.upd_none s).exitScope_eq, ((hD4.upd_none s).upd_none y).exitScope_eq,
      (((hD4.upd_none s).upd_none y).upd_none b).exitScope_eq]
    simp [K4, K3', K3, K2, K1, A2.setE, upd_ne _ _ hva, upd_ne _ _ hvb, upd_ne _ _ hvy, upd_ne _ _ hvs]

/-! ### The functions' `FnOK` -/

/-- `= r 0`, the result slot `r` of a function of an integer result. -/
theorem assign_res {fn : Fn} {r : Var} (hc : sigCtx fn r = some R0)
    (hp : ∀ p E, sigCtx fn p = some E → E.mode = .rootb → E.vdeps = [])
    (hflags : ∀ v E, sigCtx fn v = some E → E.dtor = false ∧ E.dbind = false) :
    StmtT P (sigCtx fn) [] (.assign r (.expr (.lit 0)))
      (setE (kill .replace false r (sigCtx fn)) r { intE with mode := R0.mode }) :=
  StmtT.assign (Ex := R0) (E := intE) hc (by simp) (Or.inr (Or.inr ⟨rfl, rfl⟩))
    (RhsT.expr ExprT.lit) rfl (by simp [intE, roots, Entry.vdeps, Mode.ownSlot]) (by simp [hc])
    (by intro p E hp' _ d hd _; rw [hp p E hp' (by assumption)] at hd; cases hd)
    (DtorSafe.of_none (fun v E h => (hflags v E h).1) _ _ _) rfl

theorem sig_dfn_flags : ∀ v E, sigCtx dfn v = some E → E.dtor = false ∧ E.dbind = false := by
  intro v E h
  rcases v with _ | _ | v <;> simp [sigCtx, dfn, paramE, resMode] at h <;> subst h <;> exact ⟨rfl, rfl⟩

theorem dfn_ok : FnOK P dfn := by
  refine ⟨rfl, by decide, by decide, rfl, by simp [dfn], ?_, by simp [dfn], by simp [dfn], by simp [dfn],
    by simp [dfn], by simp [dfn], ?_, _,
    assign_res (by simp [sigCtx, dfn, R0, resMode]) ?_ sig_dfn_flags, ?_, ?_, ?_⟩
  · intro pt hpt; simp [dfn] at hpt; subst hpt; simp [DT, T, Ty.ok, Ty.isStruct]
  · refine ⟨fun i hi hs _ => ?_, fun i hi b hb _ => ?_, fun h => by simp [dfn] at h⟩
    · simp [dfn] at hi; subst hi; simp [dfn] at hs
    · simp [dfn] at hi; subst hi; simp [dfn] at hb
  · intro p E hp _
    rcases p with _ | _ | p <;> simp [sigCtx, dfn, paramE, resMode, DT, T, Ty.hasFn] at hp <;> subst hp <;>
      simp [Entry.vdeps]
  · intro v E h
    rcases v with _ | _ | v <;> simp [setE, upd, kill, killE, sigCtx, dfn, paramE, intE] at h <;>
      subst h <;> exact ⟨rfl, rfl⟩
  · exact ⟨{ intE with mode := R0.mode }, by simp [setE, upd, dfn], rfl, rfl, by simp [R0, resMode, dfn],
      by simp [intE], by simp [intE], by simp [dfn]⟩
  · intro i hi b hb; simp [dfn] at hi; subst hi; simp [dfn] at hb

/-- The context after `pfn`'s `= r 0`. -/
def Gp : Ctx := setE (kill .replace false 1 (sigCtx pfn)) 1 { intE with mode := R0.mode }

theorem Gp_flags : ∀ v E, Gp v = some E → E.dtor = false ∧ E.dbind = false ∧ E.vdeps = [] := by
  intro v E h
  rcases v with _ | _ | v <;> simp [Gp, setE, upd, kill, killE, sigCtx, pfn, paramE, intE, DP, T,
    Ty.hasFn] at h <;> subst h <;> (try split) <;> simp [Entry.vdeps]

theorem pfn_ok : FnOK P pfn := by
  have ha := assign_res (fn := pfn) (r := 1) (by simp [sigCtx, pfn, R0, resMode])
    (by
      intro p E hp _
      rcases p with _ | _ | p <;> simp [sigCtx, pfn, paramE, resMode, DP, T, Ty.hasFn] at hp <;> subst hp <;>
        simp [Entry.vdeps])
    (by
      intro v E h
      rcases v with _ | _ | v <;> simp [sigCtx, pfn, paramE, resMode] at h <;> subst h <;> exact ⟨rfl, rfl⟩)
  have hp := panic_typed (Γ := Gp) (F := []) (fun v E h => (Gp_flags v E h).2.2)
    (fun v E h => ⟨(Gp_flags v E h).1, (Gp_flags v E h).2.1⟩)
  refine ⟨rfl, by decide, by decide, rfl, by simp [pfn], ?_, by simp [pfn], by simp [pfn], by simp [pfn],
    by simp [pfn], by simp [pfn], ?_, Gp, StmtT.seq rfl ha hp,
    fun v E h => ⟨(Gp_flags v E h).1, (Gp_flags v E h).2.1⟩, ?_, ?_⟩
  · intro pt hpt; simp [pfn] at hpt; subst hpt; simp [DP, T, Ty.ok, Ty.isStruct]
  · refine ⟨fun i hi hs _ => ?_, fun i hi b hb _ => ?_, fun h => by simp [pfn] at h⟩
    · simp [pfn] at hi; subst hi; simp [pfn] at hs
    · simp [pfn] at hi; subst hi; simp [pfn] at hb
  · exact ⟨{ intE with mode := R0.mode }, by simp [Gp, setE, upd, pfn], rfl, rfl, by simp [R0, resMode, pfn],
      by simp [intE], by simp [intE], by simp [pfn]⟩
  · intro i hi b hb; simp [pfn] at hi; subst hi; simp [pfn] at hb

/-- The context after `rfn`'s `= r 0`. -/
def Gr : Ctx := setE (kill .replace false 0 (sigCtx rfn)) 0 { intE with mode := R0.mode }

theorem Gr_eq : Gr = setE (fun _ => none) 0 intE := by
  funext v
  rcases v with _ | v <;> simp [Gr, setE, upd, kill, sigCtx, rfn, intE, R0]

theorem rfn_ok : FnOK P rfn := by
  have ha := assign_res (fn := rfn) (r := 0) (by simp [sigCtx, rfn, R0, resMode])
    (by intro p E hp hm; rcases p with _ | p <;> simp [sigCtx, rfn, resMode] at hp <;> subst hp <;> simp at hm)
    (by intro v E h; rcases v with _ | v <;> simp [sigCtx, rfn, resMode] at h <;> subst h <;> exact ⟨rfl, rfl⟩)
  have hR : NoRootb Gr := by rw [Gr_eq]; exact noRootb_empty.setE (by simp [intE])
  have hD : NoDeps Gr := by rw [Gr_eq]; exact NoDeps.setE (fun _ _ h => by cases h) rfl
  obtain ⟨Δ, ht, hΔR, _, hΔ⟩ := tail_typed (Γ := Gr) hR hD (a := 1) (b := 2) (y := 3) (s := 4)
    (by decide) (by decide) (by decide) (by decide) (by decide) (by decide)
    (by rw [Gr_eq]; simp [setE]) (by rw [Gr_eq]; simp [setE]) (by rw [Gr_eq]; simp [setE])
    (by rw [Gr_eq]; simp [setE])
  refine ⟨rfl, by decide, by decide, rfl, by simp [rfn], by simp [rfn], by simp [rfn], by simp [rfn],
    by simp [rfn], by simp [rfn], by simp [rfn], ?_, Δ, StmtT.seq rfl ha ht,
    fun v E h => ⟨(hΔR v E h).2.1, (hΔR v E h).2.2⟩, ?_, ?_⟩
  · refine ⟨fun i hi _ _ => ?_, fun i hi _ _ _ => ?_, fun h => by simp [rfn] at h⟩
    · simp [rfn] at hi
    · simp [rfn] at hi
  · refine ⟨intE, ?_, rfl, rfl, by simp [intE, resMode, rfn], by simp [intE], by simp [intE], by simp [rfn]⟩
    show Δ 0 = some intE
    rw [hΔ 0 (by decide) (by decide) (by decide) (by decide), Gr_eq]; simp [setE]
  · intro i hi; simp [rfn] at hi

theorem prog_ok : ProgOK P := by
  intro fn hfn
  simp only [P, List.mem_cons, List.mem_nil_iff, or_false] at hfn
  rcases hfn with rfl | rfl | rfl
  · exact dfn_ok
  · exact pfn_ok
  · exact rfn_ok

theorem prog_codes : ProgCodes P := by
  intro fn hfn
  simp only [P, List.mem_cons, List.mem_nil_iff, or_false] at hfn
  rcases hfn with rfl | rfl | rfl
  · simp [dfn, Stmt.codesOK, Rhs.codeOK]
  · simp [pfn, Stmt.codesOK, Rhs.codeOK]
  · simp only [rfn, tail, Stmt.codesOK, Rhs.codeOK, DP]
    exact ⟨trivial, trivial, trivial, trivial, arcNew_codeOK (n := 0) drop1_ok, trivial⟩

/-! ### The reap's step, of any program -/

/-- **Agora #790: the reap a destructor frame's catch leaves room for**: with a
    `dead` block (the last share dropped by the unwinding the frame caught),
    the reap can be taken at the frame's end, inside it (and only there,
    `frame_reap_inside`): its payload moves to the fresh slot `m.nv`, in a
    destructor frame of its own inside `x`'s. -/
theorem unwind_reap {P : Prog} {m : Mem} {x : Var} {f k n g : Nat} {u : Ty} {p : Val}
    (hk : m.blk k = some ⟨Ty.nest n (.dtor g u), .dead, some p⟩) (hnc : ∀ c, ¬ Sub (.cell c) p) :
    ∃ m1, Step P m (.seq (.scopeD x f .skip) .panic)
        (.ok m1 (.seq (.scopeD x f (.seq (.scopeD m.nv g .skip) .skip)) .panic)) ∧
      ReapMem m m1 ∧ m1.st m.nv = some ⟨true, some p⟩ :=
  ⟨_, Step.seqL (Step.scopeDIn (Step.reap rfl hk hnc)), ⟨k, n, g, u, p, hk, rfl⟩, by simp [Mem.set]⟩

/-- ... and the one a `recover`'s catch leaves room for, inside the frame
    (and only there, `recover_reap_inside`). -/
theorem recover_reap {P : Prog} {m : Mem} {x : Var} {m0 : Mem} {k n g : Nat} {u : Ty} {p : Val}
    (hk : m.blk k = some ⟨Ty.nest n (.dtor g u), .dead, some p⟩) (hnc : ∀ c, ¬ Sub (.cell c) p) :
    ∃ m1, Step P m (.catchR x m0 .skip) (.ok m1 (.catchR x m0 (.seq (.scopeD m.nv g .skip) .skip))) ∧
      ReapMem m m1 ∧ m1.st m.nv = some ⟨true, some p⟩ :=
  ⟨_, Step.catchIn (Step.reap rfl hk hnc), ⟨k, n, g, u, p, hk, rfl⟩, by simp [Mem.set]⟩

/-- When nothing refers to the `Arc`'s block any more (the unwinding dropped
    its last share), the marking sweep that ends the catching step marks it
    `dead`, its payload in it (`Mem.sweepD_marks`, at `DP`). -/
theorem last_drop_marks {m : Mem} {k : Nat} {p : Val} (hk : m.blk k = some ⟨DP, .arc, some p⟩)
    (hv : ∀ x o v, m.st x = some ⟨o, some v⟩ → ¬ Refers m.blk v k)
    (hb : ∀ k' bl', m.blk k' = some bl' → ¬ Refers m.blk bl'.keeps k) :
    m.sweepD.blk k = some ⟨DP, .dead, some p⟩ :=
  Mem.sweepD_marks (n := 0) (f := 1) (u := T) hk hv hb

/-! ### The first witness: a destructor binding whose scope panics

```
: a 1  : b 2  :drop x ( pair a b )                      -- x : DT, destructor dfn
: c 1  : d 2  :drop y ( pair c d )  : s ( arc_new y )   -- y : DP, destructor pfn (panics)
( panic )
```

The panic unwinds `s`'s scope (the `Arc`'s last share goes), `y`'s (moved
out), `d`'s, `c`'s, and stops at `x`'s destructor frame (`Step.scopeDP`),
which is left at its end; the marking sweep marks the block `dead`, and the
reap lands inside `x`'s frame (`unwind_reap`, `frame_reap_inside`).  `pfn`
panics there; the panic comes back to `x`'s frame, whose end then runs
`dfn` on `x` (`reaped_panic_runs_dtor`, `main1_unwind`); then the panic
goes on, uncaught. -/

def main1 : Stmt :=
  .letv 0 (.expr (.lit 1)) (.letv 1 (.expr (.lit 2)) (.letd 2 0 (.pair 0 1) (tail 3 4 5 6)))

theorem main1_typed : ∃ Δ, StmtT P (fun _ => none) [] main1 Δ := by
  let K1 : Ctx := A2.setE (fun _ => none) 0 intE
  let K2 : Ctx := A2.setE K1 1 intE
  have hK1 : NoRootb K1 := noRootb_empty.setE (by simp [intE])
  have hK2 : NoRootb K2 := hK1.setE (by simp [intE])
  have hD2 : NoDeps K2 := (NoDeps.setE (fun _ _ h => by cases h) rfl).setE rfl
  let ED : Entry := Entry.arm { EP with ty := DT, held := [] }
  have hED : ED.mode ≠ .rootb ∧ ED.dtor = false ∧ ED.dbind = false := by
    simp [ED, EP, Entry.arm, DT, T, Ty.dtorViews, Ty.holdsView]
  let K3 : Ctx := A2.setE K2 2 ED
  have hK3 : NoRootb K3 := hK2.setE hED
  have hD3 : NoDeps K3 := hD2.setE (by simp [ED, EP, Entry.arm, Entry.vdeps])
  obtain ⟨Δ, ht, hΔR, _, _⟩ := tail_typed (Γ := K3) hK3 hD3 (a := 3) (b := 4) (y := 5) (s := 6)
    (by decide) (by decide) (by decide) (by decide) (by decide) (by decide)
    (by simp [K3, K2, K1, A2.setE]) (by simp [K3, K2, K1, A2.setE]) (by simp [K3, K2, K1, A2.setE])
    (by simp [K3, K2, K1, A2.setE])
  have hpair : RhsT K2 [] (.pair 0 1) EP K2 :=
    RhsT.pair (Ey := intE) (Ez := intE) (by simp [K2, K1, A2.setE]) rfl PushArg.int
      (by simp [K2, K1, A2.setE]) rfl PushArg.int (by simp [intE, Mode.ownSlot])
  have hd := StmtT.letd (P := P) (Γ := K2) (Γ1 := K2) (F := []) (x := 2) (f := 0) (r := .pair 0 1)
    (E := EP) (t := T) (H := []) rfl (by simp [K2, K1, A2.setE]) (by simp) hpair rfl
    (Or.inl ⟨rfl, Or.inl rfl⟩) rfl rfl (letd_fn drop0_ok) (HeldUp.refl _ _) ht (hΔR.endOK _)
    (hna := by simp [tail, Stmt.assigns])
  have h1 := StmtT.letv (P := P) (x := 1) (r := .expr (.lit 2)) (E := intE) (F := []) (Γ := K1) (Γ1 := K1)
    rfl (by simp [K1, A2.setE]) (by simp) (RhsT.expr ExprT.lit) hd ((hΔR.exitScope 2).endOK _)
  exact ⟨_, StmtT.letv (P := P) (x := 0) (r := .expr (.lit 1)) (E := intE) (F := []) (Γ := fun _ => none)
    (Γ1 := fun _ => none) rfl rfl (by simp) (RhsT.expr ExprT.lit) h1
    (((hΔR.exitScope 2).exitScope 1).endOK _)⟩

theorem main1_codes : main1.codesOK P := by
  simp only [main1, tail, Stmt.codesOK, Rhs.codeOK, DP]
  exact ⟨trivial, trivial, trivial, trivial, trivial, trivial, arcNew_codeOK (n := 0) drop1_ok, trivial⟩

/-- **Every run of it is safe.** -/
theorem main1_safe {m' : Mem} {s' : Stmt} (hr : Steps P (emptyMem 7) main1 (.ok m' s')) :
    ¬ Stuck P m' s' := by
  obtain ⟨Δ, ht⟩ := main1_typed
  exact memory_safe prog_ok prog_codes ht rfl main1_codes (by decide) hr

/-- **... its panic leaks nothing** (the panic `pfn` raises inside `x`'s
    frame, and the first one, go on uncaught: the run ends in a panic) ... -/
theorem main1_no_leak_panic {m' : Mem} (hr : Steps P (emptyMem 7) main1 (.panic m')) :
    ∀ i, m'.alloc i = false := by
  obtain ⟨Δ, ht⟩ := main1_typed
  exact no_leak_panic prog_ok prog_codes ht rfl main1_codes (by decide) hr

/-- **... nor does a finished run** (none finishes: it panics). -/
theorem main1_no_leak {m' : Mem} (hr : Steps P (emptyMem 7) main1 (.ok m' .skip)) :
    ∀ i, m'.alloc i = false := by
  obtain ⟨Δ, ht⟩ := main1_typed
  exact no_leak_end prog_ok prog_codes ht rfl main1_codes (by decide) hr

/-- **Agora #790, the first case, at `main1`'s frame** (`x` is slot 2, its
    destructor `dfn`, 0; the `Arc`'s payload a `DP`, destructor `pfn`, 1):
    once `x`'s frame has caught the unwinding and the marking sweep has
    marked the block `dead`, the reap (`Settle`'s next step) puts `pfn`'s
    frame inside `x`'s, and only there; and when that frame panics with `x`
    still owning its value (no frame inside touches it), the panic comes back
    to `x`'s frame, whose end then calls `dfn` on `x` and nothing else. -/
theorem main1_unwind {m : Mem} {k : Nat} {p : Val} (hk : m.blk k = some ⟨DP, .dead, some p⟩)
    (hnc : ∀ c, ¬ Sub (.cell c) p) :
    (∃ m1, Step P m (.seq (.scopeD 2 0 .skip) .panic)
        (.ok m1 (.seq (.scopeD 2 0 (.seq (.scopeD m.nv 1 .skip) .skip)) .panic)) ∧ ReapMem m m1 ∧
        m1.st m.nv = some ⟨true, some p⟩) ∧
      (∀ m1 s1, Step P m (.seq (.scopeD 2 0 .skip) .panic) (.ok m1 s1) → ReapMem m m1 →
        ∃ g, s1 = .seq (.scopeD 2 0 (.seq (.scopeD m.nv g .skip) .skip)) .panic) ∧
      (∀ {m2 m3 : Mem} {t : Stmt} {v : Val}, Step P m2 t (.panic m3) →
        m3.st 2 = some ⟨true, some v⟩ → v.isNode = false →
        Step P m2 (.seq (.scopeD 2 0 t) .panic) (.ok m3 (.seq (.seq (.scopeD 2 0 .skip) .panic) .panic)) ∧
        (¬ Orphan m3 → ∀ r, Step P m3 (.seq (.seq (.scopeD 2 0 .skip) .panic) .panic) r ↔
          r = .ok { m3 with nv := m3.nv + 1 }
            (.seq (.seq (.scope 2 (.letcall m3.nv 0 [2] .skip)) .panic) .panic))) :=
  ⟨unwind_reap (n := 0) (u := T) hk hnc, fun _ _ h hr => frame_reap_inside h hr,
    fun ht hx hv => reaped_panic_runs_dtor ht hx hv⟩

/-! ### The second witness: a `recover` of a function whose body panics

```
: !v PanicInfo e ( recover rfn )
@ rfn → i { = r 0  : c 1  : d 2  :drop y ( pair c d )  : s ( arc_new y )  ( panic ) }
```

The panic unwinds `rfn`'s frames (the `Arc`'s last share goes) and stops at
the `recover` (`Step.catchP`), which is left at its end; the marking sweep
marks the block `dead`, and the reap lands inside the `recover`
(`recover_reap`, `recover_reap_inside`).  `pfn` panics there, and the same
`recover` catches it (`recover_catches_reaped`; no step of a `recover` frame
is a panic, `catchR_no_panic`): the run goes on and finishes. -/

def main2 : Stmt := .letrec 0 2 .skip

theorem main2_typed : ∃ Δ, StmtT P (fun _ => none) [] main2 Δ := by
  have hpost : callPost (fun _ => none) rfn [] = fun _ => none := by
    funext v; simp [callPost, callPostAux, rfn, killNames, mutNames, argNames]
  have hres : callRes (fun _ => none) rfn [] = intE := by
    simp [callRes, rfn, resMode, intE, heldOfArgs, ownHeld, allKinds, argNames]
  have hc : CallT P (fun _ => none) [] 2 [] intE (fun _ => none) := by
    refine ⟨rfn, rfl, rfl, fun i hi => by simp [rfn] at hi, ?_, CallDtorSafe.of_none (fun _ _ h => by cases h) _ _,
      hres.symm, hpost.symm, fun _ => by simp [callR]⟩
    intro d hd; simp [mutNames, argNames] at hd
  have hK : NoRootb (A2.setE (fun _ => none) 0 intE) := noRootb_empty.setE (by simp [intE])
  exact ⟨_, StmtT.letrec (P := P) (fn := rfn) rfl rfl (by simp) rfl rfl rfl rfl hc StmtT.skip (hK.endOK _)⟩

theorem main2_codes : main2.codesOK P := by
  simp [main2, Stmt.codesOK]

/-- **Every run of it is safe.** -/
theorem main2_safe {m' : Mem} {s' : Stmt} (hr : Steps P (emptyMem 1) main2 (.ok m' s')) :
    ¬ Stuck P m' s' := by
  obtain ⟨Δ, ht⟩ := main2_typed
  exact memory_safe prog_ok prog_codes ht rfl main2_codes (by decide) hr

/-- **... and, finished (the `recover` catches both panics), leaks nothing** ... -/
theorem main2_no_leak {m' : Mem} (hr : Steps P (emptyMem 1) main2 (.ok m' .skip)) :
    ∀ i, m'.alloc i = false := by
  obtain ⟨Δ, ht⟩ := main2_typed
  exact no_leak_end prog_ok prog_codes ht rfl main2_codes (by decide) hr

/-- **... nor does a run that panics.** -/
theorem main2_no_leak_panic {m' : Mem} (hr : Steps P (emptyMem 1) main2 (.panic m')) :
    ∀ i, m'.alloc i = false := by
  obtain ⟨Δ, ht⟩ := main2_typed
  exact no_leak_panic prog_ok prog_codes ht rfl main2_codes (by decide) hr

/-- **Agora #790, the second case, at `main2`'s `recover`** (its flag `e` is
    slot 0): once the `recover` has caught the unwinding and the block is
    marked `dead`, the reap puts `pfn`'s frame inside the `recover`, and only
    there; a panic out of that frame is caught by the same `recover` (no step
    of it is a panic), which is at its end again. -/
theorem main2_unwind {m : Mem} {m0 : Mem} {k : Nat} {p : Val} (hk : m.blk k = some ⟨DP, .dead, some p⟩)
    (hnc : ∀ c, ¬ Sub (.cell c) p) :
    (∃ m1, Step P m (.catchR 0 m0 .skip) (.ok m1 (.catchR 0 m0 (.seq (.scopeD m.nv 1 .skip) .skip))) ∧
        ReapMem m m1 ∧ m1.st m.nv = some ⟨true, some p⟩) ∧
      (∀ m1 s1, Step P m (.catchR 0 m0 .skip) (.ok m1 s1) → ReapMem m m1 →
        ∃ g, s1 = .catchR 0 m0 (.seq (.scopeD m.nv g .skip) .skip)) ∧
      (∀ {m2 m3 : Mem} {t : Stmt}, Step P m2 t (.panic m3) → (m3.st 0).isSome →
        Step P m2 (.catchR 0 m0 t) (.ok (m3.set 0 ⟨false, some (.int 1)⟩) (.catchR 0 m0 .skip))) ∧
      (∀ {m2 m3 : Mem} {t : Stmt}, ¬ Step P m2 (.catchR 0 m0 t) (.panic m3)) :=
  ⟨recover_reap (n := 0) (u := T) hk hnc, fun _ _ h hr => recover_reap_inside h hr,
    fun ht hx => recover_catches_reaped ht hx, catchR_no_panic⟩

end A2.ArcPanicWitness
