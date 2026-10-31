import A2.Rename
import A2.Preservation

/-! A2 — the call step.

A call binds its parameters and runs the callee's body, renamed apart, inside
their scopes (`callStmt`).  The context it runs in is the caller's view of the
callee's own starting context (`RSetup.canon`): the renaming lemma types the
body there, and the summary the callee was checked against says what the
parameters' exits leave. -/

namespace A2

/-! ### A source statement keeps the domain, modes and types -/

def DomTy (Γ0 Γ : Ctx) : Prop :=
  (∀ x, (Γ x).isSome = (Γ0 x).isSome) ∧
  ∀ x E, Γ x = some E → ∃ E0, Γ0 x = some E0 ∧ E.mode = E0.mode ∧ E.ty = E0.ty

theorem DomTy.refl (Γ : Ctx) : DomTy Γ Γ := ⟨fun _ => rfl, fun _ E h => ⟨E, h, rfl, rfl⟩⟩

theorem DomTy.trans {Γ1 Γ2 Γ3 : Ctx} (h1 : DomTy Γ1 Γ2) (h2 : DomTy Γ2 Γ3) : DomTy Γ1 Γ3 := by
  refine ⟨fun x => (h2.1 x).trans (h1.1 x), fun x E h => ?_⟩
  obtain ⟨E2, h2', hm2, ht2⟩ := h2.2 x E h
  obtain ⟨E1, h1', hm1, ht1⟩ := h1.2 x E2 h2'
  exact ⟨E1, h1', hm2.trans hm1, ht2.trans ht1⟩

theorem DomTy.kill {Γ0 Γ : Ctx} (h : DomTy Γ0 Γ) (e : Eff) (hv : Bool) (x : Var) :
    DomTy Γ0 (A2.kill e hv x Γ) := by
  refine ⟨fun y => by rw [kill_dom]; exact h.1 y, fun y E hy => ?_⟩
  obtain ⟨E1, h1, hm1, _⟩ := kill_cmode hy
  obtain ⟨E0, h0, hm0, ht0⟩ := h.2 y E1 h1
  simp only [A2.kill, h1, Option.map_some, Option.some.injEq] at hy; subst hy
  exact ⟨E0, h0, by rw [killE_mode, hm0], by rw [killE_ty, ht0]⟩

theorem DomTy.setE {Γ0 Γ : Ctx} (h : DomTy Γ0 Γ) {x : Var} {E : Entry}
    (hx : ∃ E0, Γ0 x = some E0 ∧ E.mode = E0.mode ∧ E.ty = E0.ty) : DomTy Γ0 (A2.setE Γ x E) := by
  obtain ⟨E0, h0, hm, ht⟩ := hx
  refine ⟨fun y => ?_, fun y E' hy => ?_⟩
  · by_cases hyx : y = x
    · subst hyx; simp [A2.setE, h0]
    · simp only [A2.setE, upd_ne _ _ hyx]; exact h.1 y
  · by_cases hyx : y = x
    · subst hyx; simp only [A2.setE, upd_same, Option.some.injEq] at hy; subst hy; exact ⟨E0, h0, hm, ht⟩
    · simp only [A2.setE, upd_ne _ _ hyx] at hy; exact h.2 y E' hy

theorem DomTy.killNames {Γ0 Γ : Ctx} (h : DomTy Γ0 Γ) : ∀ ds, DomTy Γ0 (A2.killNames ds Γ)
  | [] => h
  | _ :: ds => show DomTy Γ0 (A2.kill _ _ _ (A2.killNames ds Γ)) from (DomTy.killNames h ds).kill _ _ _

/-- What running the closures handed to a call leaves of a binding. -/
theorem killNames_get {Γ : Ctx} {y : Var} : ∀ (ds : List Dep) {E : Entry}, killNames ds Γ y = some E →
    ∃ E0, Γ y = some E0 ∧ E.ty = E0.ty ∧ E.mode = E0.mode ∧ E.path = E0.path ∧ E.held = E0.held ∧
      (E.live = true → E0.live = true ∧ ∀ d ∈ ds, hits d.kind.bound false d.root E0 = false)
  | [], E, h => ⟨E, h, rfl, rfl, rfl, rfl, fun hl => ⟨hl, fun _ hd => by cases hd⟩⟩
  | d :: ds, E, h => by
    change (A2.kill _ _ _ (A2.killNames ds Γ)) y = some E at h
    simp only [A2.kill] at h
    cases h1 : killNames ds Γ y with
    | none => rw [h1] at h; cases h
    | some E1 =>
      rw [h1] at h; simp only [Option.map_some, Option.some.injEq] at h; subst h
      obtain ⟨E0, h0, ht, hm, hp, hh, hl⟩ := killNames_get ds h1
      refine ⟨E0, h0, by rw [killE_ty, ht], by rw [killE_mode, hm], by rw [killE_path, hp],
        by rw [killE_held, hh], fun hl' => ?_⟩
      rw [killE_live] at hl'
      simp only [Bool.and_eq_true, Bool.not_eq_eq_eq_not, Bool.not_true] at hl'
      obtain ⟨hl1, hs⟩ := hl hl'.1
      have hvd : E1.vdeps = E0.vdeps := by unfold Entry.vdeps; rw [hm, hp, hh]
      refine ⟨hl1, fun d' hd' => ?_⟩
      rcases List.mem_cons.mp hd' with rfl | hd'
      · have := hl'.2; unfold hits at this ⊢; rwa [ht, hm, hvd] at this
      · exact hs d' hd'

theorem DomTy.weaker {Γ Γ' : Ctx} (hw : Weaker Γ Γ') : DomTy Γ Γ' := by
  refine ⟨fun x => (hw.isSome x).symm, fun x E h => ?_⟩
  obtain ⟨E0, h0, hw0⟩ := hw.get' h
  exact ⟨E0, h0, hw0.mode, hw0.1⟩

theorem PushArg.domTy {Γ Γ1 : Ctx} {F : List Var} {y : Var} {Ey : Entry} {t : Ty} {D : List Dep}
    (hy : Γ y = some Ey) (hp : PushArg Γ F y Ey t D Γ1) : DomTy Γ Γ1 := by
  cases hp with
  | move _ _ => exact ((DomTy.refl Γ).kill .replace false y).setE ⟨Ey, hy, rfl, rfl⟩
  | int => exact DomTy.refl Γ
  | slice _ => exact DomTy.refl Γ

theorem RhsT.domTy {Γ Γ1 : Ctx} {F : List Var} {r : Rhs} {E : Entry} (hr : RhsT Γ F r E Γ1) :
    DomTy Γ Γ1 := by
  cases hr with
  | @moveOwn y Ey hy _ _ _ => exact ((DomTy.refl Γ).kill .replace false y).setE ⟨Ey, hy, rfl, rfl⟩
  | pop _ _ _ _ _ => exact (DomTy.refl Γ).kill _ _ _
  | pair hy _ hpa1 hz _ hpa2 _ => exact (PushArg.domTy hy hpa1).trans (PushArg.domTy hz hpa2)
  | inl hy _ hpa _ => exact PushArg.domTy hy hpa
  | inr hy _ hpa _ => exact PushArg.domTy hy hpa
  | pack hy _ _ hpa => exact PushArg.domTy hy hpa
  | @takel y Ey _ _ hy _ _ _ _ => exact ((DomTy.refl Γ).kill .replace false y).setE ⟨Ey, hy, rfl, rfl⟩
  | @taker y Ey _ _ hy _ _ _ _ => exact ((DomTy.refl Γ).kill .replace false y).setE ⟨Ey, hy, rfl, rfl⟩
  | _ => exact DomTy.refl Γ

theorem callPostAux_domTy {Γ0 : Ctx} {fn : Fn} {args : List Var} :
    ∀ (ps : List (PMode × Ty)) (as : List Var) (i : Nat) (Γ : Ctx),
      (∀ a ∈ as, ∃ E0, Γ0 a = some E0) → DomTy Γ0 Γ →
      DomTy Γ0 (callPostAux Γ0 fn args ps as i Γ) := by
  intro ps
  induction ps with
  | nil => intro as i Γ _ hd; cases as <;> exact hd
  | cons p ps ih =>
    intro as i Γ has hd
    obtain ⟨pm, t⟩ := p
    cases as with
    | nil => cases pm <;> exact hd
    | cons a as =>
      obtain ⟨E0, h0⟩ := has a (by simp)
      have has' : ∀ a' ∈ as, ∃ E0, Γ0 a' = some E0 := fun a' h' => has a' (by simp [h'])
      have hargE : argE Γ0 a = E0 := by unfold argE; rw [h0]; rfl
      cases pm with
      | inp => exact ih as (i + 1) Γ has' hd
      | sink => exact ih as (i + 1) _ has' ((hd.kill _ _ _).setE ⟨E0, h0, by rw [hargE], by rw [hargE]⟩)
      | inout b => exact ih as (i + 1) _ has' ((hd.kill _ _ _).setE ⟨E0, h0, by rw [hargE], by rw [hargE]⟩)

theorem CallT.domTy {P : Prog} {Γ Γ1 : Ctx} {F : List Var} {f : Nat} {args : List Var}
    {E : Entry} (hc : CallT P Γ F f args E Γ1) : DomTy Γ Γ1 := by
  obtain ⟨fn, _, hlen, hargs, _, _, rfl⟩ := hc
  refine DomTy.killNames (callPostAux_domTy _ _ _ _ (fun a ha => ?_) (DomTy.refl Γ)) _
  obtain ⟨i, hi, rfl⟩ := mem_args ha
  obtain ⟨Ea, hEa, _⟩ := hargs i (hlen ▸ hi)
  exact ⟨Ea, hEa⟩

theorem DomTy.exitScope_fresh {Γ Γ1 Δ : Ctx} {x : Var} {E : Entry} (hx : Γ x = none)
    (h1 : DomTy Γ Γ1) (h2 : DomTy (A2.setE Γ1 x E) Δ) : DomTy Γ (A2.exitScope x Δ) := by
  refine ⟨fun y => ?_, fun y E' hy => ?_⟩
  · by_cases hyx : y = x
    · subst hyx; simp [A2.exitScope, hx]
    · simp only [A2.exitScope, upd_ne _ _ hyx, kill_dom]
      rw [h2.1 y]; simp only [A2.setE, upd_ne _ _ hyx]; exact h1.1 y
  · have hyx : y ≠ x := fun e => by subst e; simp [A2.exitScope] at hy
    simp only [A2.exitScope, upd_ne _ _ hyx] at hy
    obtain ⟨E1, h1', hm1, _⟩ := kill_cmode hy
    simp only [A2.kill, h1', Option.map_some, Option.some.injEq] at hy; subst hy
    obtain ⟨E2, h2', hm2, ht2⟩ := h2.2 y E1 h1'
    simp only [A2.setE, upd_ne _ _ hyx] at h2'
    obtain ⟨E3, h3, hm3, ht3⟩ := h1.2 y E2 h2'
    exact ⟨E3, h3, by rw [killE_mode, hm2, hm3], by rw [killE_ty, ht2, ht3]⟩

/-- Source code keeps every binding's mode and type, and binds nothing new. -/
theorem StmtT.domTy {P : Prog} {Γ : Ctx} {F : List Var} {s : Stmt} {Δ : Ctx}
    (ht : StmtT P Γ F s Δ) : s.src = true → DomTy Γ Δ := by
  induction ht with
  | skip => exact fun _ => DomTy.refl _
  | seq _ _ _ iha ihb =>
    intro hs; simp only [Stmt.src, Bool.and_eq_true] at hs; exact (iha hs.1).trans (ihb hs.2)
  | letv hks hx _ hr _ _ ih => exact fun _ => DomTy.exitScope_fresh hx hr.domTy (ih hks)
  | letd hks hx _ hr _ _ _ _ _ ih => exact fun _ => DomTy.exitScope_fresh hx hr.domTy (ih hks)
  | letcall hks hx _ hc _ _ ih => exact fun _ => DomTy.exitScope_fresh hx hc.domTy (ih hks)
  | letrec hks hx _ _ _ _ _ hc _ _ ih => exact fun _ => DomTy.exitScope_fresh hx hc.domTy (ih hks)
  | callc hks hx _ _ _ _ _ _ _ hcT _ _ _ ih => exact fun _ => DomTy.exitScope_fresh hx hcT.domTy (ih hks)
  | @unpair Γ Δ F y x z k E a b hks hy _ _ _ _ hx hz hxz _ _ _ _ _ _ ih =>
    intro _
    have hxy : x ≠ y := fun e => by rw [e, hy] at hx; cases hx
    have hzy : z ≠ y := fun e => by rw [e, hy] at hz; cases hz
    have h1 : DomTy Γ (A2.setE (A2.kill .replace false y Γ) y { E with live := false, dtor := false }) :=
      ((DomTy.refl Γ).kill .replace false y).setE ⟨E, hy, rfl, rfl⟩
    refine DomTy.exitScope_fresh hx h1 (DomTy.exitScope_fresh ?_ (DomTy.refl _) (ih hks))
    simp [A2.setE, upd_ne _ _ (Ne.symm hxz), upd_ne _ _ hzy, A2.kill, hz]
  | panic _ _ hdom hm =>
    exact fun _ => ⟨fun v => (hdom v).symm, fun v E hv => by
      obtain ⟨E0, h0, hm0, ht0, _⟩ := hm v E hv; exact ⟨E0, h0, hm0, ht0⟩⟩
  | catchR => intro hs; simp [Stmt.src] at hs
  | scopeD => intro hs; simp [Stmt.src] at hs
  | scope => intro hs; simp [Stmt.src] at hs
  | rbind => intro hs; simp [Stmt.src] at hs
  | frozen => intro hs; simp [Stmt.src] at hs
  | @assign Γ Γ1 F x r Ex E hx _ _ hr hty _ _ _ =>
    intro _
    exact (hr.domTy.kill _ _ _).setE ⟨Ex, hx, rfl, hty⟩
  | ite _ _ _ _ _ iha _ => intro _; exact iha (by assumption)
  | «while» => exact fun _ => DomTy.refl _
  | @push Γ Γ1 F x y Ex Ey Ex1 t D hx _ _ _ _ hy _ _ _ hpa _ hx1 _ =>
    intro _
    obtain ⟨E0, h0, hm0, ht0⟩ := (hpa.domTy hy).2 x Ex1 hx1
    exact ((hpa.domTy hy).kill _ _ _).setE ⟨E0, h0, hm0, ht0⟩
  | @free Γ F x E t hx _ _ _ _ _ => exact fun _ => ((DomTy.refl Γ).kill _ _ _).setE ⟨E, hx, rfl, rfl⟩
  | sub hw _ ho ih =>
    intro hs
    have h0 := (DomTy.weaker hw).trans (ih hs)
    rcases ho with rfl | hwo
    · exact h0
    · exact h0.trans (DomTy.weaker hwo)

/-! ### What the call sets up -/

/-- The dependencies of an integer, or of a dead binding, say nothing; the
    call forgets them. -/
noncomputable def Entry.clean (E : Entry) : Entry :=
  open Classical in
  if ¬ E.fixed ∧ (E.ty = .int ∨ E.live = false) then { E with path := [], held := [] } else E

/-- The roots of what the arguments hold views of. -/
def callR (Γ : Ctx) (args : List Var) : List Var :=
  args.flatMap (fun a => if (argE Γ a).ty = .int then [] else roots (memDeps (argE Γ a).held))

/-- What an entry of a type holds, as far as the type can: one that holds no
    closure holds nothing by name. -/
def typedDeps (t : Ty) (ds : List Dep) : List Dep := if t.hasFn then ds else memDeps ds

theorem typedDeps_hasFn {t : Ty} (h : t.hasFn = true) (ds : List Dep) : typedDeps t ds = ds := by
  simp [typedDeps, h]

theorem typedDeps_noFn {t : Ty} (h : t.hasFn = false) (ds : List Dep) : typedDeps t ds = memDeps ds := by
  simp [typedDeps, h]

theorem typedDeps_sub (t : Ty) (ds : List Dep) : typedDeps t ds ⊆ ds := by
  unfold typedDeps; split
  · exact List.Subset.refl _
  · exact fun _ hd => (List.mem_filter.mp hd).1

theorem mem_typedDeps {t : Ty} {ds : List Dep} {d : Dep} (hd : d ∈ typedDeps t ds) :
    d ∈ ds ∧ (d.kind.isName = true → t.hasFn = true) := by
  unfold typedDeps at hd; split at hd
  · exact ⟨hd, fun _ => by assumption⟩
  · obtain ⟨hd, hn⟩ := List.mem_filter.mp hd
    exact ⟨hd, fun hn' => by simp [hn'] at hn⟩

theorem mem_typedDeps_of {t : Ty} {ds : List Dep} {d : Dep} (hd : d ∈ ds)
    (h : d.kind.isName = true → t.hasFn = true) : d ∈ typedDeps t ds := by
  unfold typedDeps; split
  · exact hd
  · rename_i hf
    refine List.mem_filter.mpr ⟨hd, ?_⟩
    cases hn : d.kind.isName
    · rfl
    · exact absurd (h hn) (by simpa using hf)

/-- An `in` parameter, as the caller sees it: a borrow of its argument,
    holding by name only what its type can (a closure, in something). -/
def callPe (Γ : Ctx) (ps : List (PMode × Ty)) (args : List Var) (v : Var) : Entry :=
  match ps[v]? with
  | some (.inp, _) =>
    if (argE Γ (args.getD v 0)).ty = .int then ⟨.int, .rootb, true, [], [], false⟩
    else ⟨(argE Γ (args.getD v 0)).ty, .rootb, true,
          typedDeps (argE Γ (args.getD v 0)).ty (derive (args.getD v 0) (argE Γ (args.getD v 0)) .self),
          typedDeps (argE Γ (args.getD v 0)).ty (argE Γ (args.getD v 0)).held, false⟩
  | _ => ⟨.int, .rootb, true, [], [], false⟩

/-- The caller's binding of the result, before the result is moved in. -/
def callX (fn : Fn) : Entry := ⟨fn.resTy, resMode fn, false, [], [], false⟩

theorem callX_vdeps (fn : Fn) : (callX fn).vdeps = [] := by
  unfold Entry.vdeps callX; cases (resMode fn).ownSlot <;> rfl

/-- Every caller binding but the `inout` arguments is lent out for the call
    (at most: the run-time form records this bound) ... -/
def zOf (fn : Fn) (args : List Var) (base : Nat) : List Var :=
  (List.range base).filter (fun v => !(inoutArgs fn.params args).contains v)

/-- ... and the typing lends all of them but what the closures handed to the
    call may change. -/
def zN (Γ : Ctx) (fn : Fn) (args : List Var) (base : Nat) : List Var :=
  (zOf fn args base).filter (fun v => !(roots (mutNames Γ args)).contains v)

theorem zN_sub {Γ : Ctx} {fn : Fn} {args : List Var} {base : Nat} :
    ∀ v ∈ zN Γ fn args base, v ∈ zOf fn args base := fun _ h => (List.mem_filter.mp h).1

def bndOf (ps : List (PMode × Ty)) (v : Var) : Option (Eff × Bool) :=
  match ps[v]? with
  | some (.inout b, t) => some (b, t.elem.holdsView)
  | _ => none

open Classical in
noncomputable def callS (Γ : Ctx) (F : List Var) (fn : Fn) (args : List Var) (base : Nat) (x : Var) :
    RSetup where
  ρ := callRen fn.params args base
  R := callR Γ args
  pe := callPe Γ fn.params args
  Φ := fun y => if ∃ v, callRen fn.params args base v = y then none
    else (setE (callPost Γ fn args) x (callX fn) y).map Entry.clean
  Fc := F ++ zN Γ fn args base
  bnd := bndOf fn.params
  pty := fun v => ((fn.params[v]?).map (·.2)).getD .int
  N := (argNames Γ args).filter (fun d => !(inoutArgs fn.params args).contains d.root)
  sym := symNames fn.params

/-- What a call's typing says of its arguments, with the caller's names and
    its borrowed parameters' anchors: the part of `CallH` that no run-time
    frame enters into, so source typing has it at every call (`CallT.toA`). -/
structure CallA (Γ : Ctx) (F : List Var) (fn : Fn) (args : List Var) : Prop where
  len     : args.length = fn.params.length
  arg     : ∀ i (h : i < fn.params.length), ∃ Ea, Γ (args.getD i 0) = some Ea ∧ Ea.live = true ∧
              paramOK fn.params[i].1 fn.params[i].2 Ea ∧
              (fn.params[i].1.moves = true →
                args.getD i 0 ∉ F ∧ args.getD i 0 ∉ roots (memDeps Ea.vdeps) ∧
                (fn.params[i].1 = .sink → args.getD i 0 ∉ roots Ea.vdeps) ∧
                (∀ b, fn.params[i].1 = .inout b → ∀ d ∈ Ea.vdeps,
                  d.root = args.getD i 0 → d.kind.bound = b ∧ b ≠ .none) ∧
                ∀ j < fn.params.length, j ≠ i →
                  args.getD j 0 ≠ args.getD i 0 ∧
                  args.getD i 0 ∉ roots (memDeps (argE Γ (args.getD j 0)).vdeps) ∧
                  (fn.params[i].1 = .sink → args.getD i 0 ∉ roots (argE Γ (args.getD j 0)).vdeps) ∧
                  (∀ b, fn.params[i].1 = .inout b → ∀ d ∈ (argE Γ (args.getD j 0)).vdeps,
                    d.root = args.getD i 0 → d.kind.bound = b ∧ b ≠ .none)) ∧
              (fn.params[i].1 = .sink ∨ fn.params[i].1 = .inout .replace → NoPin Γ (args.getD i 0))
  nfree   : NamesFree Γ F fn.params args
  names   : NameWF Γ
  anch    : RootbAnch Γ F

/-- What a well-typed call, in a well-formed configuration, gives. -/
structure CallH (P : Prog) (Γ : Ctx) (F : List Var) (x : Var) (fn : Fn) (args : List Var) (base : Nat) :
    Prop extends CallA Γ F fn args where
  prog    : ProgOK P
  fnok    : FnOK P fn
  postdt  : DomTy Γ (callPost Γ fn args)
  resnames : NameWF (setE (callPost Γ fn args) x (callRes Γ fn args))
  fresh   : Γ x = none
  xF      : x ∉ F
  xlt     : x < base
  domlt   : ∀ v E, Γ v = some E → v < base
  noio    : ∀ v E b, Γ v = some E → E.mode ≠ .inout b
  Flt     : ∀ v ∈ F, v < base
  wf      : CtxWF Γ
  noInout : ∀ v E b, Γ v = some E → E.mode ≠ .inout b
  rbLive  : ∀ p E, Γ p = some E → E.mode = .rootb → E.live = true
  postwf  : CtxWF (callPost Γ fn args)
  postdm  : DomMode Γ (callPost Γ fn args)
  reswf   : ∀ r ∈ roots (callRes Γ fn args).vdeps, ∃ Er, callPost Γ fn args r = some Er ∧ Er.mode.isRoot = true

theorem derive_roots_cases {y : Var} {E : Entry} {k : Kind} {r : Var} (hr : r ∈ roots (derive y E k)) :
    (r = y ∧ E.mode.isRoot = true) ∨ (E.mode.isRoot = false ∧ r ∈ roots E.vdeps) := by
  unfold derive at hr
  cases hrt : E.mode.isRoot with
  | true => simp only [hrt, ↓reduceIte, roots, List.map_cons, List.map_nil, List.mem_singleton] at hr
            exact Or.inl ⟨hr, rfl⟩
  | false =>
    simp only [hrt, Bool.false_eq_true, ↓reduceIte, roots, List.map_map, List.mem_map,
      Function.comp] at hr
    obtain ⟨dep, hd, rfl⟩ := hr
    have hos : E.mode.ownSlot = false := by cases hm : E.mode <;> simp_all [Mode.isRoot, Mode.ownSlot]
    exact Or.inr ⟨rfl, by simp [roots, Entry.vdeps, hos, List.mem_map_of_mem hd]⟩

namespace CallH
variable {P : Prog} {Γ : Ctx} {F : List Var} {x : Var} {fn : Fn} {args : List Var} {base : Nat}

theorem argLt (h : CallH P Γ F x fn args base) {i : Nat} (hi : i < fn.params.length) :
    args.getD i 0 < base := by
  obtain ⟨Ea, hEa, _⟩ := h.arg i hi; exact h.domlt _ _ hEa

/-- The argument of an `inout` or `sink` parameter is passed nowhere else. -/
theorem moving (h : CallH P Γ F x fn args base) {i j : Nat} (hi : i < fn.params.length)
    (hj : j < fn.params.length) (hm : fn.params[i].1.moves = true) (he : args.getD j 0 = args.getD i 0) :
    j = i := by
  refine Classical.byContradiction fun hne => ?_
  obtain ⟨_, _, _, _, hmv, _⟩ := h.arg i hi
  exact ((hmv hm).2.2.2.2 j hj hne).1 he

/-- ... nor reached from any argument in memory. -/
theorem moving_root (h : CallH P Γ F x fn args base) {i j : Nat} (hi : i < fn.params.length)
    (hj : j < fn.params.length) (hm : fn.params[i].1.moves = true) :
    args.getD i 0 ∉ roots (memDeps (argE Γ (args.getD j 0)).vdeps) := by
  obtain ⟨Ea, hEa, _, _, hmv, _⟩ := h.arg i hi
  by_cases hji : j = i
  · subst hji
    have : argE Γ (args.getD j 0) = Ea := by unfold argE; rw [hEa]; rfl
    rw [this]; exact (hmv hm).2.1
  · exact ((hmv hm).2.2.2.2 j hj hji).2.1

/-- A `sink` argument is reached from no argument at all. -/
theorem moving_sink (h : CallH P Γ F x fn args base) {i j : Nat} (hi : i < fn.params.length)
    (hj : j < fn.params.length) (hs : fn.params[i].1 = .sink) :
    args.getD i 0 ∉ roots (argE Γ (args.getD j 0)).vdeps := by
  obtain ⟨Ea, hEa, _, _, hmv, _⟩ := h.arg i hi
  have hm : fn.params[i].1.moves = true := by rw [hs]; rfl
  by_cases hji : j = i
  · subst hji
    have : argE Γ (args.getD j 0) = Ea := by unfold argE; rw [hEa]; rfl
    rw [this]; exact (hmv hm).2.2.1 hs
  · exact ((hmv hm).2.2.2.2 j hj hji).2.2.1 hs

/-- An `inout` argument is reached from another argument only by a name of
    the parameter's bound. -/
theorem moving_name (h : CallH P Γ F x fn args base) {i j : Nat} (hi : i < fn.params.length)
    (hj : j < fn.params.length) {b : Eff} (hb : fn.params[i].1 = .inout b) (hji : j ≠ i) :
    ∀ d ∈ (argE Γ (args.getD j 0)).vdeps, d.root = args.getD i 0 → d.kind.bound = b ∧ b ≠ .none := by
  obtain ⟨_, _, _, _, hmv, _⟩ := h.arg i hi
  have hm : fn.params[i].1.moves = true := by rw [hb]; rfl
  exact ((hmv hm).2.2.2.2 j hj hji).2.2.2 b hb

/-- ... and from itself only so. -/
theorem moving_self (h : CallH P Γ F x fn args base) {i : Nat} (hi : i < fn.params.length)
    {b : Eff} (hb : fn.params[i].1 = .inout b) :
    ∀ d ∈ (argE Γ (args.getD i 0)).vdeps, d.root = args.getD i 0 → d.kind.bound = b ∧ b ≠ .none := by
  obtain ⟨Ea, hEa, _, _, hmv, _⟩ := h.arg i hi
  have hm : fn.params[i].1.moves = true := by rw [hb]; rfl
  have : argE Γ (args.getD i 0) = Ea := by unfold argE; rw [hEa]; rfl
  rw [this]; exact (hmv hm).2.2.2.1 b hb
end CallH

/-! ### The context after the call, at the bindings it does not touch -/

def Survives (ps : List (PMode × Ty)) (as : List Var) (E : Entry) : Prop :=
  ∀ pa ∈ ps.zip as, (pa.1.1 = .sink → hits .replace false pa.2 E = false) ∧
    (∀ b, pa.1.1 = .inout b → hits b pa.1.2.elem.holdsView pa.2 E = false)

theorem callPostAux_frame {Γ0 : Ctx} {fn : Fn} {args : List Var} {y : Var} :
    ∀ (ps : List (PMode × Ty)) (as : List Var) (i : Nat) (Γ : Ctx),
      (∀ pa ∈ ps.zip as, pa.1.1.moves = true → pa.2 ≠ y) →
      ∀ E, callPostAux Γ0 fn args ps as i Γ y = some E →
        ∃ E0, Γ y = some E0 ∧ E.ty = E0.ty ∧ E.mode = E0.mode ∧ E.path = E0.path ∧ E.held = E0.held ∧
          (E.live = true → E0.live = true ∧ Survives ps as E0) := by
  intro ps
  induction ps with
  | nil =>
    intro as i Γ _ E hE
    cases as <;> exact ⟨E, by simpa [callPostAux] using hE, rfl, rfl, rfl, rfl,
      fun hl => ⟨hl, fun pa hpa => by simp at hpa⟩⟩
  | cons p ps ih =>
    intro as i Γ hy E hE
    obtain ⟨pm, t⟩ := p
    cases as with
    | nil =>
      cases pm <;> exact ⟨E, by simpa [callPostAux] using hE, rfl, rfl, rfl, rfl,
        fun hl => ⟨hl, fun pa hpa => by simp at hpa⟩⟩
    | cons a as =>
      have hy' : ∀ pa ∈ ps.zip as, pa.1.1.moves = true → pa.2 ≠ y :=
        fun pa hpa => hy pa (by simp [hpa])
      have hsurv : ∀ E0, (pm = .sink → hits .replace false a E0 = false) →
          (∀ b, pm = .inout b → hits b t.elem.holdsView a E0 = false) → Survives ps as E0 →
          Survives ((pm, t) :: ps) (a :: as) E0 := by
        intro E0 h1 h2 h3 pa hpa
        simp only [List.zip_cons_cons, List.mem_cons] at hpa
        rcases hpa with rfl | hpa
        · exact ⟨h1, h2⟩
        · exact h3 pa hpa
      cases pm with
      | inp =>
        obtain ⟨E0, h0, h1, h2, h3, h4, h5⟩ := ih as (i + 1) Γ hy' E hE
        exact ⟨E0, h0, h1, h2, h3, h4, fun hl => ⟨(h5 hl).1,
          hsurv E0 (fun h => by cases h) (fun _ h => by cases h) (h5 hl).2⟩⟩
      | sink =>
        have hay : a ≠ y := hy ((.sink, t), a) (by simp) rfl
        obtain ⟨E1, h0, h1, h2, h3, h4, h5⟩ := ih as (i + 1) _ hy' E hE
        simp only [setE, upd_ne _ _ hay.symm, A2.kill] at h0
        cases hE0 : Γ y with
        | none => rw [hE0] at h0; cases h0
        | some E0 =>
          rw [hE0] at h0; simp only [Option.map_some, Option.some.injEq] at h0; subst h0
          refine ⟨E0, rfl, by rw [h1, killE_ty], by rw [h2, killE_mode], by rw [h3, killE_path],
            by rw [h4, killE_held], fun hl => ?_⟩
          obtain ⟨hl1, hs⟩ := h5 hl
          rw [killE_live] at hl1
          simp only [Bool.and_eq_true, Bool.not_eq_eq_eq_not, Bool.not_true] at hl1
          refine ⟨hl1.1, hsurv E0 (fun _ => hl1.2) (fun _ h => by cases h) (fun pa hpa => ?_)⟩
          have := hs pa hpa
          unfold hits at this ⊢
          rwa [killE_ty, killE_mode, killE_vdeps] at this
      | inout b =>
        have hay : a ≠ y := hy ((.inout b, t), a) (by simp) rfl
        obtain ⟨E1, h0, h1, h2, h3, h4, h5⟩ := ih as (i + 1) _ hy' E hE
        simp only [setE, upd_ne _ _ hay.symm, A2.kill] at h0
        cases hE0 : Γ y with
        | none => rw [hE0] at h0; cases h0
        | some E0 =>
          rw [hE0] at h0; simp only [Option.map_some, Option.some.injEq] at h0; subst h0
          refine ⟨E0, rfl, by rw [h1, killE_ty], by rw [h2, killE_mode], by rw [h3, killE_path],
            by rw [h4, killE_held], fun hl => ?_⟩
          obtain ⟨hl1, hs⟩ := h5 hl
          rw [killE_live] at hl1
          simp only [Bool.and_eq_true, Bool.not_eq_eq_eq_not, Bool.not_true] at hl1
          refine ⟨hl1.1, hsurv E0 (fun h => by cases h) (fun b' h => by cases h; exact hl1.2)
            (fun pa hpa => ?_)⟩
          have := hs pa hpa
          unfold hits at this ⊢
          rwa [killE_ty, killE_mode, killE_vdeps] at this

/-- What the context after the call says of a moved or changed argument. -/
def postEnt (Γ0 : Ctx) (fn : Fn) (args : List Var) (i : Nat) (a : Var) (t : Ty) : PMode → Entry
  | .sink => { argE Γ0 a with live := false, dtor := false }
  | .inout _ => { argE Γ0 a with held := if t.holdsView then
      (argE Γ0 a).held ++ outHeld Γ0 fn args i ++ heldOfArgs Γ0 args else (argE Γ0 a).held }
  | .inp => argE Γ0 a

theorem callPostAux_at {Γ0 : Ctx} {fn : Fn} {args : List Var} {y : Var} :
    ∀ (ps : List (PMode × Ty)) (as : List Var) (i k : Nat) (Γ : Ctx) {pm : PMode} {t : Ty},
      as[k]? = some y → (∀ k', k' ≠ k → as[k']? ≠ some y) → ps[k]? = some (pm, t) → pm.moves = true →
      ∀ E, callPostAux Γ0 fn args ps as i Γ y = some E →
        let E0 := postEnt Γ0 fn args (i + k) y t pm
        E.ty = E0.ty ∧ E.mode = E0.mode ∧ E.path = E0.path ∧ E.held = E0.held ∧ (E.live = true → E0.live = true) := by
  intro ps
  induction ps with
  | nil => intro as i k Γ pm t _ _ hp; simp at hp
  | cons p ps ih =>
    intro as i k Γ pm t ha hu hp hm E hE
    obtain ⟨pm0, t0⟩ := p
    cases as with
    | nil => simp at ha
    | cons a as =>
      cases k with
      | zero =>
        simp only [List.getElem?_cons_zero, Option.some.injEq] at ha hp
        subst ha; cases hp
        have hyn : ∀ pa ∈ ps.zip as, pa.1.1.moves = true → pa.2 ≠ a := by
          intro pa hpa _ he
          obtain ⟨k', hk', _, rfl⟩ := RSetup.mem_zip_getD hpa
          have hk2 : k' < as.length := by
            have := List.length_zip (l₁ := ps) (l₂ := as); omega
          refine hu (k' + 1) (by omega) ?_
          simp only [List.getElem?_cons_succ]
          rw [← he]; simp [List.getD, hk2]
        cases pm with
        | inp => cases hm
        | sink =>
          obtain ⟨E0, h0, h1, h2, h3, h4, h5⟩ := callPostAux_frame ps as (i + 1) _ hyn E hE
          simp only [setE, upd_same, Option.some.injEq] at h0; subst h0
          exact ⟨h1, h2, h3, h4, fun hl => (h5 hl).1⟩
        | inout b =>
          obtain ⟨E0, h0, h1, h2, h3, h4, h5⟩ := callPostAux_frame ps as (i + 1) _ hyn E hE
          simp only [setE, upd_same, Option.some.injEq] at h0; subst h0
          exact ⟨h1, h2, h3, h4, fun hl => (h5 hl).1⟩
      | succ k =>
        simp only [List.getElem?_cons_succ] at ha hp
        have hu' : ∀ k', k' ≠ k → as[k']? ≠ some y := fun k' hk' => by
          have := hu (k' + 1) (by omega); simpa using this
        have := fun Γ' => ih as (i + 1) k Γ' ha hu' hp hm E
        rw [show i + (k + 1) = i + 1 + k by omega]
        cases pm0 with
        | inp => exact this Γ hE
        | sink => exact this _ hE
        | inout b => exact this _ hE

/-! ### The renaming of a call -/

theorem callRen_cases (ps : List (PMode × Ty)) (args : List Var) (base v : Nat) :
    (∃ b t, ps[v]? = some (.inout b, t) ∧ callRen ps args base v = args.getD v 0) ∨
    ((∀ b t, ps[v]? ≠ some (.inout b, t)) ∧ callRen ps args base v = base + v) := by
  unfold callRen
  cases hv : ps[v]? with
  | none => exact Or.inr ⟨fun _ _ h' => (by cases h'), rfl⟩
  | some p =>
    obtain ⟨pm, t⟩ := p
    cases pm with
    | inout b => exact Or.inl ⟨b, t, rfl, rfl⟩
    | inp => exact Or.inr ⟨fun _ _ h' => (by cases h'), rfl⟩
    | sink => exact Or.inr ⟨fun _ _ h' => (by cases h'), rfl⟩

theorem mem_inoutArgs {ps : List (PMode × Ty)} {args : List Var} {v : Nat} {b : Eff} {t : Ty}
    (h : ps[v]? = some (.inout b, t)) : args.getD v 0 ∈ inoutArgs ps args := by
  have hv : v < ps.length := (List.getElem?_eq_some_iff.mp h).1
  unfold inoutArgs
  refine List.mem_map.mpr ⟨v, List.mem_filter.mpr ⟨List.mem_range.mpr hv, ?_⟩, rfl⟩
  simp [h]

theorem inoutArgs_mem {ps : List (PMode × Ty)} {args : List Var} {a : Var} (h : a ∈ inoutArgs ps args) :
    ∃ v b t, ps[v]? = some (.inout b, t) ∧ args.getD v 0 = a := by
  unfold inoutArgs at h
  obtain ⟨v, hv, rfl⟩ := List.mem_map.mp h
  obtain ⟨_, hm⟩ := List.mem_filter.mp hv
  split at hm
  · rename_i b t hp; exact ⟨v, b, t, hp, rfl⟩
  · cases hm

theorem resMode_ne' (fn : Fn) : resMode fn ≠ .rootb := by unfold resMode; split <;> simp
theorem resMode_inout (fn : Fn) (b : Eff) : resMode fn ≠ .inout b := by unfold resMode; split <;> simp

theorem clean_fixed_iff (E : Entry) : E.clean.fixed ↔ E.fixed := by
  unfold Entry.clean; split <;> simp [Entry.fixed_def]
theorem fixed_setLive (E : Entry) (b : Bool) : ({E with live := b} : Entry).fixed ↔ E.fixed := by
  simp [Entry.fixed_def]
theorem fixed_setHeld (E : Entry) (H : List Dep) : ({E with held := H} : Entry).fixed ↔ E.fixed := by
  simp [Entry.fixed_def]
theorem clean_mode (E : Entry) : E.clean.mode = E.mode := by unfold Entry.clean; split <;> rfl
theorem clean_ty (E : Entry) : E.clean.ty = E.ty := by unfold Entry.clean; split <;> rfl
theorem clean_live (E : Entry) : E.clean.live = E.live := by unfold Entry.clean; split <;> rfl
theorem clean_fixed {E : Entry} (h : E.fixed) : E.clean = E := by
  unfold Entry.clean; rw [ite_eq_right (fun hc => hc.1 h)]
theorem clean_id {E : Entry} (h : E.ty ≠ .int ∨ E.mode = .rootb) (hl : E.live = true) : E.clean = E := by
  unfold Entry.clean; rw [ite_eq_right]; rintro ⟨h1, h2 | h2⟩
  · rcases h with h | h
    · exact h h2
    · exact h1 (Or.inl h)
  · rw [hl] at h2; cases h2

/-- Moving a binding out (`live` and `dtor` cleared) keeps whether it is
    fixed: that is its mode and type. -/
theorem fixed_moveOut (E : Entry) : ({E with live := false, dtor := false} : Entry).fixed ↔ E.fixed := by
  simp [Entry.fixed]

theorem mem_callR {Γ : Ctx} {args : List Var} {r : Var} :
    r ∈ callR Γ args ↔ ∃ a ∈ args, (argE Γ a).ty ≠ .int ∧ r ∈ roots (memDeps (argE Γ a).held) := by
  unfold callR
  simp only [List.mem_flatMap]
  constructor
  · rintro ⟨a, ha, hr⟩; split at hr
    · simp at hr
    · exact ⟨a, ha, by assumption, hr⟩
  · rintro ⟨a, ha, hn, hr⟩; exact ⟨a, ha, by rw [ite_eq_right hn]; exact hr⟩

theorem hits_false_dep {e : Eff} {hv : Bool} {x : Var} {E : Entry} (h : hits e hv x E = false)
    (hn : E.ty ≠ .int ∨ E.mode = .rootb) (d : Dep) (hd : d ∈ E.vdeps) (hr : d.root = x) :
    e.kills hv d.kind = false := by
  cases hk : e.kills hv d.kind with
  | false => rfl
  | true =>
    have : hits e hv x E = true := by
      unfold hits
      simp only [Bool.and_eq_true, Bool.or_eq_true, bne_iff_ne, ne_eq, beq_iff_eq, List.any_eq_true]
      refine ⟨?_, d, hd, hr, hk⟩
      rcases hn with h' | h'
      · exact Or.inl h'
      · exact Or.inr (by rw [h'])
    rw [this] at h; cases h

theorem mem_zip_of {ps : List (PMode × Ty)} {as : List Var} {v : Nat} {p : PMode × Ty}
    (hv : ps[v]? = some p) (hva : v < as.length) : (p, as.getD v 0) ∈ ps.zip as := by
  have hvl : v < ps.length := (List.getElem?_eq_some_iff.mp hv).1
  refine List.mem_iff_getElem.mpr ⟨v, by simp only [List.length_zip]; omega, ?_⟩
  simp [List.getD, hva, (List.getElem?_eq_some_iff.mp hv).2]

theorem held_vdeps {E : Entry} {r : Var} (h : r ∈ roots E.held) : r ∈ roots E.vdeps := by
  simp only [roots, Entry.vdeps, List.map_append, List.mem_append] at h ⊢; exact Or.inr h

theorem held_memDeps_vdeps {E : Entry} {r : Var} (h : r ∈ roots (memDeps E.held)) :
    r ∈ roots (memDeps E.vdeps) := by
  obtain ⟨d, hd, rfl⟩ := List.mem_map.mp h
  obtain ⟨hd, hn⟩ := List.mem_filter.mp hd
  exact List.mem_map_of_mem (List.mem_filter.mpr ⟨by unfold Entry.vdeps; exact List.mem_append_right _ hd, hn⟩)

namespace CallH
variable {P : Prog} {Γ : Ctx} {F : List Var} {x : Var} {fn : Fn} {args : List Var} {base : Nat}

theorem _root_.A2.CallA.argE_eq (h : CallA Γ F fn args) {i : Nat} (hi : i < fn.params.length) :
    ∃ Ea, Γ (args.getD i 0) = some Ea ∧ argE Γ (args.getD i 0) = Ea := by
  obtain ⟨Ea, hEa, _⟩ := h.arg i hi; exact ⟨Ea, hEa, by unfold argE; rw [hEa]; rfl⟩

theorem lt_of_get {i : Nat} {p : PMode × Ty} (hp : fn.params[i]? = some p) : i < fn.params.length :=
  (List.getElem?_eq_some_iff.mp hp).1

theorem get_of {i : Nat} {p : PMode × Ty} (hp : fn.params[i]? = some p) :
    fn.params[i]'(lt_of_get hp) = p := (List.getElem?_eq_some_iff.mp hp).2

/-- Roots reached from an argument are outside the callee and stay roots in the frame. -/
theorem post_root (h : CallH P Γ F x fn args base) {r : Var} {Er : Entry} (hr : Γ r = some Er)
    (hro : Er.mode.isRoot = true) : ∃ E', callPost Γ fn args r = some E' ∧ E'.mode.isRoot = true := by
  obtain ⟨E', h', hm⟩ := h.postdm.get hr
  exact ⟨E', h', by rw [hm]; exact hro⟩

theorem ren_inj (h : CallH P Γ F x fn args base) (v w : Nat)
    (he : callRen fn.params args base v = callRen fn.params args base w) : v = w := by
  rcases callRen_cases fn.params args base v with ⟨b, t, hv, hrv⟩ | ⟨hv, hrv⟩ <;>
  rcases callRen_cases fn.params args base w with ⟨b', t', hw, hrw⟩ | ⟨hw, hrw⟩ <;>
  rw [hrv, hrw] at he
  · have hvl := lt_of_get hv
    have hwl := lt_of_get hw
    exact (h.moving hwl hvl (by rw [get_of hw]; rfl) he)
  · exact absurd (he ▸ h.argLt (lt_of_get hv)) (Nat.not_lt.mpr (Nat.le_add_right _ _))
  · exact absurd (he ▸ h.argLt (lt_of_get hw)) (Nat.not_lt.mpr (Nat.le_add_right _ _))
  · exact Nat.add_left_cancel he

/-- What the callee may name through `ρ` is either fresh or an `inout` argument. -/
theorem ren_dom (_h : CallH P Γ F x fn args base) {v : Nat} {r : Var} (hr : callRen fn.params args base v = r)
    (hlt : r < base) : ∃ b t, fn.params[v]? = some (.inout b, t) ∧ args.getD v 0 = r := by
  rcases callRen_cases fn.params args base v with ⟨b, t, hv, hrv⟩ | ⟨_, hrv⟩
  · exact ⟨b, t, hv, hrv ▸ hr⟩
  · rw [hrv] at hr; subst hr; exact absurd hlt (Nat.not_lt.mpr (Nat.le_add_right _ _))

theorem notRen_root (h : CallH P Γ F x fn args base) {j : Nat} (hj : j < fn.params.length) {r : Var}
    (hr : r ∈ roots (memDeps (argE Γ (args.getD j 0)).vdeps)) (hrlt : r < base) :
    ∀ w, callRen fn.params args base w ≠ r := by
  intro w hw
  obtain ⟨b, t, hwp, rfl⟩ := h.ren_dom hw hrlt
  exact h.moving_root (lt_of_get hwp) hj (by rw [get_of hwp]; rfl) hr

theorem frame_some (_h : CallH P Γ F x fn args base) {y : Var} {E : Entry}
    (hy : (callS Γ F fn args base x).Φ y = some E) :
    (∀ v, callRen fn.params args base v ≠ y) ∧ ∃ E1, setE (callPost Γ fn args) x (callX fn) y = some E1 ∧
      E = E1.clean := by
  simp only [callS] at hy
  split at hy
  · cases hy
  · rename_i hn
    refine ⟨fun v hv => hn ⟨v, hv⟩, ?_⟩
    cases h1 : setE (callPost Γ fn args) x (callX fn) y with
    | none => rw [h1] at hy; cases hy
    | some E1 => rw [h1] at hy; cases hy; exact ⟨E1, rfl, rfl⟩

theorem frame_of (_h : CallH P Γ F x fn args base) {y : Var} (hy : ∀ v, callRen fn.params args base v ≠ y)
    (hyx : y ≠ x) : (callS Γ F fn args base x).Φ y = (callPost Γ fn args y).map Entry.clean := by
  simp only [callS]
  rw [ite_eq_right (fun ⟨v, hv⟩ => hy v hv)]
  simp [setE, upd_ne _ _ hyx]

theorem post_lt (h : CallH P Γ F x fn args base) {y : Var} {E : Entry} (hy : callPost Γ fn args y = some E) :
    y < base := by
  have := h.postdm.1 y; rw [hy] at this
  cases h0 : Γ y with
  | none => rw [h0] at this; cases this
  | some E0 => exact h.domlt y E0 h0

theorem post_ne_x (h : CallH P Γ F x fn args base) {y : Var} {E : Entry} (hy : callPost Γ fn args y = some E) :
    y ≠ x := by
  intro e; subst e
  have := h.postdm.1 y; rw [hy, h.fresh] at this; cases this

theorem frame_root (h : CallH P Γ F x fn args base) {r : Var} {Er : Entry} (hr : Γ r = some Er)
    (hro : Er.mode.isRoot = true) (hout : ∀ v, callRen fn.params args base v ≠ r) :
    ∃ E, (callS Γ F fn args base x).Φ r = some E ∧ E.mode.isRoot = true := by
  obtain ⟨E', h', hm'⟩ := h.post_root hr hro
  rw [h.frame_of hout (h.post_ne_x h')]
  exact ⟨E'.clean, by rw [h']; rfl, by rw [clean_mode]; exact hm'⟩

/-- The argument roots `R`: reached from an argument, so outside the callee. -/
theorem R_facts (h : CallH P Γ F x fn args base) {r : Var} (hr : r ∈ callR Γ args) :
    (∀ v, callRen fn.params args base v ≠ r) ∧ ∃ Er, Γ r = some Er ∧ Er.mode.isRoot = true := by
  obtain ⟨a, ha, hn, hrh⟩ := mem_callR.mp hr
  obtain ⟨j, hj, rfl⟩ := mem_args ha
  have hjp : j < fn.params.length := h.len ▸ hj
  obtain ⟨Ea, hEa, hae⟩ := h.argE_eq hjp
  obtain ⟨_, _, hl, _⟩ := h.arg j hjp
  rw [hae] at hn hrh
  have hvd := held_vdeps (roots_memDeps hrh)
  obtain ⟨Er, hEr, hro⟩ := h.wf _ Ea hEa (by obtain ⟨E', h1, h2, _⟩ := h.arg j hjp; rw [hEa] at h1; cases h1; exact h2)
    (Or.inl hn) r hvd
  refine ⟨h.notRen_root hjp (by rw [hae]; exact held_memDeps_vdeps hrh) (h.domlt r Er hEr), Er, hEr, hro⟩

theorem bound_isName {k : Kind} (h : k.bound ≠ .none) : k.isName = true := by
  cases k <;> simp_all [Kind.bound, Kind.isName]

theorem hits_clean {e : Eff} {hv : Bool} {r : Var} {E : Entry} (hl : E.live = true) :
    hits e hv r E.clean = hits e hv r E := by
  unfold Entry.clean
  split
  · rename_i hc
    obtain ⟨hrb, hc⟩ := hc
    rcases hc with hi | hd
    · have hb : (E.mode == Mode.rootb) = false := by
        simp only [beq_eq_false_iff_ne, ne_eq]; exact fun e => hrb (Or.inl e)
      simp [hits, hi, hb]
    · rw [hl] at hd; cases hd
  · rfl

/-- What the arguments hold by name: names in a live, non-integer argument. -/
theorem _root_.A2.CallA.argNames_mem (h : CallA Γ F fn args) {d : Dep} (hd : d ∈ argNames Γ args) :
    ∃ j < fn.params.length, ∃ Ea, Γ (args.getD j 0) = some Ea ∧ Ea.live = true ∧ Ea.ty ≠ .int ∧
      d ∈ Ea.vdeps ∧ d.kind.isName = true := by
  simp only [argNames, List.mem_flatMap] at hd
  obtain ⟨a, ha, hda⟩ := hd
  obtain ⟨j, hj, rfl⟩ := mem_args ha
  have hjp : j < fn.params.length := h.len ▸ hj
  obtain ⟨Ea, hEa, hae⟩ := h.argE_eq hjp
  obtain ⟨_, h1, hl, _⟩ := h.arg j hjp
  rw [hEa] at h1; cases h1
  rw [hae] at hda
  split at hda
  · simp at hda
  · rename_i hn
    obtain ⟨hdv, hdn⟩ := List.mem_filter.mp hda
    exact ⟨j, hjp, Ea, hEa, hl, hn, hdv, hdn⟩

theorem _root_.A2.CallA.argNames_named (h : CallA Γ F fn args) {d : Dep} (hd : d ∈ argNames Γ args) :
    DepsNamed Γ [d] := by
  obtain ⟨j, _, Ea, hEa, hl, hn, hdv, _⟩ := h.argNames_mem hd
  exact DepsNamed.sub (h.names _ Ea hEa hl (Or.inl hn)) (fun d' hd' => by
    simp only [List.mem_singleton] at hd'; subst hd'; exact hdv)

theorem _root_.A2.CallA.argNames_bound (h : CallA Γ F fn args) {d : Dep} (hd : d ∈ argNames Γ args)
    (hb : d.kind.bound ≠ .none) : d.kind.bound ≠ .replace := by
  obtain ⟨r, k⟩ := d
  cases k with
  | name b t =>
    obtain ⟨_, _, _, _, _, _, hc, _⟩ := h.argNames_named hd _ (List.mem_singleton_self _) b t rfl
    rcases hc with hc | ⟨hc, _⟩
    · exact absurd hc hb
    · exact hc
  | _ => exact absurd rfl hb

/-- ... at roots of the caller's. -/
theorem argNames_rootE (h : CallH P Γ F x fn args base) {d : Dep} (hd : d ∈ argNames Γ args) :
    ∃ Er, Γ d.root = some Er ∧ Er.mode.isRoot = true := by
  obtain ⟨j, hj, Ea, hEa, hl, hn, hdv, _⟩ := h.argNames_mem hd
  exact h.wf _ Ea hEa hl (Or.inl hn) d.root (List.mem_map_of_mem hdv)

theorem mem_N (_h : CallH P Γ F x fn args base) {d : Dep} :
    d ∈ (callS Γ F fn args base x).N ↔ d ∈ argNames Γ args ∧ d.root ∉ inoutArgs fn.params args := by
  show d ∈ (argNames Γ args).filter _ ↔ _
  simp [List.mem_filter]

/-- What the arguments hold by name of the frame: at roots of the caller's
    the callee cannot name. -/
theorem N_root (h : CallH P Γ F x fn args base) {d : Dep} (hd : d ∈ (callS Γ F fn args base x).N) :
    (∀ w, callRen fn.params args base w ≠ d.root) ∧ ∃ Er, Γ d.root = some Er ∧ Er.mode.isRoot = true := by
  obtain ⟨hd, hio⟩ := (h.mem_N).mp hd
  refine ⟨fun w hw => ?_, h.argNames_rootE hd⟩
  obtain ⟨Er, hEr, _⟩ := h.argNames_rootE hd
  obtain ⟨b, t, hwp, hwe⟩ := h.ren_dom hw (h.domlt _ _ hEr)
  exact hio (hwe ▸ mem_inoutArgs hwp)


/-- A caller binding the callee cannot name is in the frame, of its type and mode. -/
theorem frame_ty (h : CallH P Γ F x fn args base) {r : Var} {Er : Entry} (hr : Γ r = some Er)
    (hout : ∀ w, callRen fn.params args base w ≠ r) :
    ∃ E, (callS Γ F fn args base x).Φ r = some E ∧ E.ty = Er.ty ∧ E.mode = Er.mode := by
  have hs := h.postdt.1 r
  rw [hr] at hs
  cases h1 : callPost Γ fn args r with
  | none => rw [h1] at hs; simp at hs
  | some E1 =>
    obtain ⟨E0, h0, hm, ht⟩ := h.postdt.2 r E1 h1
    rw [hr] at h0; cases h0
    rw [h.frame_of hout (h.post_ne_x h1), h1]
    exact ⟨E1.clean, rfl, by rw [clean_ty, ht], by rw [clean_mode, hm]⟩

/-- An argument reached by name from another (or the same) argument: of the
    frame, or an `inout` argument by the parameter's own bound, which the
    callee's symbolic name stands for. -/
theorem argName_cases (h : CallH P Γ F x fn args base) {j : Nat} (hj : j < fn.params.length) {Ea : Entry}
    (hEa : Γ (args.getD j 0) = some Ea) (hn : Ea.ty ≠ .int) {d : Dep} (hdv : d ∈ Ea.vdeps)
    (hname : d.kind.isName = true) :
    d ∈ (callS Γ F fn args base x).N ∨
      d ∈ rds (callRen fn.params args base) (symNames fn.params) := by
  have hae : argE Γ (args.getD j 0) = Ea := by unfold argE; rw [hEa]; rfl
  have hdn : d ∈ argNames Γ args := by
    simp only [argNames, List.mem_flatMap]
    refine ⟨args.getD j 0, by simp [List.getD, show j < args.length from h.len ▸ hj], ?_⟩
    rw [hae, ite_eq_right hn]; exact List.mem_filter.mpr ⟨hdv, hname⟩
  by_cases hio : d.root ∈ inoutArgs fn.params args
  · right
    obtain ⟨w, b, t, hwp, hwe⟩ := inoutArgs_mem hio
    have hwl := lt_of_get hwp
    obtain ⟨hb, hbn⟩ : d.kind.bound = b ∧ b ≠ .none := by
      by_cases hjw : j = w
      · subst hjw; exact h.moving_self hj (by rw [get_of hwp]) d (by rw [hae]; exact hdv) hwe.symm
      · exact h.moving_name hwl hj (by rw [get_of hwp]) hjw d (by rw [hae]; exact hdv) hwe.symm
    obtain ⟨r, k⟩ := d
    cases k with
    | name b0 t0 =>
      simp only [Kind.bound] at hb; subst hb
      obtain ⟨Er, hEr, _, _, ht, _, hc', hhv⟩ := h.argNames_named hdn _ (List.mem_singleton_self _) b0 t0 rfl
      have hbr : b0 ≠ .replace := by
        rcases hc' with hc' | ⟨hc', _⟩
        · exact absurd hc' hbn
        · exact hc'
      obtain ⟨Ew, hEw, _, hokw, _⟩ := h.arg w hwl
      simp only at hwe; rw [hwe] at hEw
      rw [hEr] at hEw; cases hEw
      have htw : Er.ty = t := by rw [get_of hwp] at hokw; exact hokw.1
      refine RSetup.mem_rds.mpr ⟨⟨w, .name b0 t0⟩, mem_symNames.mpr ⟨?_, hhv, hbn, hbr⟩, ?_⟩
      · rw [hwp, ← ht, htw]
      · simp only [Dep.ren, callRen, hwp]; rw [hwe]
    | _ => cases hname
  · exact Or.inl ((h.mem_N).mpr ⟨hdn, hio⟩)

/-- What an `in` parameter depends on: its argument's own handle, or what
    the argument depends on. -/
theorem pe_vdeps (h : CallH P Γ F x fn args base) (v : Nat) {d : Dep}
    (hd : d ∈ (callPe Γ fn.params args v).vdeps) :
    ∃ Ea, v < fn.params.length ∧ Γ (args.getD v 0) = some Ea ∧ Ea.live = true ∧ Ea.ty ≠ .int ∧
      ((d.root = args.getD v 0 ∧ d.kind.isName = false ∧ Ea.mode.isRoot = true) ∨ d ∈ Ea.vdeps) ∧
      (d.kind.isName = true → Ea.ty.hasFn = true) ∧ fn.params[v]? = some (.inp, Ea.ty) := by
  unfold callPe at hd
  split at hd
  · rename_i t hv
    have hvp := lt_of_get hv
    obtain ⟨Ea, hEa, hae⟩ := h.argE_eq hvp
    obtain ⟨_, h1, hl, hok, _⟩ := h.arg v hvp
    rw [hEa] at h1; cases h1
    have hty : Ea.ty = t := by rw [get_of hv] at hok; exact hok
    split at hd
    · simp [Entry.vdeps, Mode.ownSlot] at hd
    · rename_i hn
      rw [hae] at hn hd
      have hf : d.kind.isName = true → Ea.ty.hasFn = true := by
        simp only [Entry.vdeps, Mode.ownSlot, Bool.false_eq_true, ↓reduceIte, List.mem_append] at hd
        rcases hd with hd | hd <;> exact (mem_typedDeps hd).2
      refine ⟨Ea, hvp, hEa, hl, hn, ?_, hf, by rw [hty]; exact hv⟩
      simp only [Entry.vdeps, Mode.ownSlot, Bool.false_eq_true, ↓reduceIte, List.mem_append] at hd
      rcases hd with hd | hd
      · replace hd := (mem_typedDeps hd).1
        unfold derive at hd
        cases hrt : Ea.mode.isRoot with
        | true =>
          simp only [hrt, ↓reduceIte, List.mem_singleton] at hd
          subst hd
          refine Or.inl ⟨rfl, ?_, rfl⟩
          generalize Ea.ty = t0; cases t0 <;> rfl
        | false =>
          simp only [hrt, Bool.false_eq_true, ↓reduceIte, List.mem_map] at hd
          obtain ⟨d0, hd0, rfl⟩ := hd
          have hos : Ea.mode.ownSlot = false := by
            cases hm : Ea.mode <;> simp_all [Mode.isRoot, Mode.ownSlot]
          have hc : (⟨d0.root, comp d0.kind .self⟩ : Dep) = d0 := by
            obtain ⟨r0, k0⟩ := d0; cases k0 <;> rfl
          rw [hc]
          refine Or.inr ?_
          simp only [Entry.vdeps, hos, Bool.false_eq_true, ↓reduceIte]
          exact List.mem_append_left _ hd0
      · exact Or.inr (by unfold Entry.vdeps; exact List.mem_append_right _ (mem_typedDeps hd).1)
  · simp [Entry.vdeps, Mode.ownSlot] at hd

theorem pe_argNames (h : CallH P Γ F x fn args base) (v : Nat) {d : Dep}
    (hd : d ∈ (callPe Γ fn.params args v).vdeps) (hn : d.kind.isName = true) : d ∈ argNames Γ args := by
  obtain ⟨Ea, hvp, hEa, _, hni, hc, _⟩ := h.pe_vdeps v hd
  rcases hc with ⟨_, hnn, _⟩ | hdv
  · rw [hnn] at hn; cases hn
  · have hae : argE Γ (args.getD v 0) = Ea := by unfold argE; rw [hEa]; rfl
    simp only [argNames, List.mem_flatMap]
    refine ⟨args.getD v 0, by simp [List.getD, show v < args.length from h.len ▸ hvp], ?_⟩
    rw [hae, ite_eq_right hni]; exact List.mem_filter.mpr ⟨hdv, hn⟩

/-- What a borrowed parameter holds by name: of the frame, or an `inout`
    argument by the parameter's own bound — the callee's symbolic name, which
    the parameter carries only when its type may hold a closure. -/
theorem pe_names (h : CallH P Γ F x fn args base) (v : Nat) {d : Dep}
    (hd : d ∈ (callPe Γ fn.params args v).vdeps) (hn : d.kind.isName = true) :
    d ∈ (callS Γ F fn args base x).N ∨
      (d ∈ rds (callRen fn.params args base) (symNames fn.params) ∧ (callPe Γ fn.params args v).ty.hasFn = true) := by
  obtain ⟨Ea, hvp, hEa, hl, hni, hc, hf, hvi⟩ := h.pe_vdeps v hd
  have hae : argE Γ (args.getD v 0) = Ea := by unfold argE; rw [hEa]; rfl
  rcases hc with ⟨_, hnn, _⟩ | hdv
  · rw [hnn] at hn; cases hn
  rcases h.argName_cases hvp hEa hni hdv hn with hN | hs
  · exact Or.inl hN
  · refine Or.inr ⟨hs, ?_⟩
    show (callPe Γ fn.params args v).ty.hasFn = true
    unfold callPe; rw [hvi]; simp only
    rw [hae, ite_eq_right hni]; exact hf hn

theorem callPostAux_rootb {Γ0 : Ctx} {fn : Fn} {args : List Var} {p : Var} {Ep : Entry} :
    ∀ (ps : List (PMode × Ty)) (as : List Var) (i : Nat) (Γ : Ctx),
      (∀ pa ∈ ps.zip as, pa.1.1.moves = true → pa.2 ≠ p ∧
        ∀ d ∈ Ep.vdeps, d.root = pa.2 → d.kind.isName = true ∧ ∃ b, pa.1.1 = .inout b ∧ b ≠ .replace) →
      Γ p = some Ep → callPostAux Γ0 fn args ps as i Γ p = some Ep := by
  intro ps
  induction ps with
  | nil => intro as i Γ _ hp; cases as <;> exact hp
  | cons q ps ih =>
    intro as i Γ hz hp
    obtain ⟨pm, t⟩ := q
    cases as with
    | nil => cases pm <;> exact hp
    | cons a as =>
      have hz' : ∀ pa ∈ ps.zip as, pa.1.1.moves = true → pa.2 ≠ p ∧
          ∀ d ∈ Ep.vdeps, d.root = pa.2 → d.kind.isName = true ∧ ∃ b, pa.1.1 = .inout b ∧ b ≠ .replace :=
        fun pa hpa => hz pa (by simp [hpa])
      have hk : ∀ e hv, (∀ d ∈ Ep.vdeps, d.root = a → e.kills hv d.kind = false) →
          A2.kill e hv a Γ p = some Ep := by
        intro e hv hno
        simp [A2.kill, hp, killE, RSetup.hits_false_of hno]
      cases pm with
      | inp => exact ih as (i + 1) Γ hz' hp
      | sink =>
        obtain ⟨hap, hd⟩ := hz ((.sink, t), a) (by simp) rfl
        apply ih as (i + 1) _ hz'
        simp only [setE, upd_ne _ _ hap.symm]
        exact hk .replace false (fun d hd' hr => by
          obtain ⟨_, b, hb, _⟩ := hd d hd' hr; cases hb)
      | inout b =>
        obtain ⟨hap, hd⟩ := hz ((.inout b, t), a) (by simp) rfl
        apply ih as (i + 1) _ hz'
        simp only [setE, upd_ne _ _ hap.symm]
        exact hk _ _ (fun d hd' hr => by
          obtain ⟨hn, b', hb, hbr⟩ := hd d hd' hr
          cases hb
          exact RSetup.kills_isName hbr _ hn)

/-- A borrowed parameter of the caller is untouched by the call's context
    change: what it borrows and reads by name is lent out, what the call
    moves or changes is not, and what the call's closures change it reaches
    only by name. -/
theorem _root_.A2.CallA.post_rootb (h : CallA Γ F fn args) {p : Var} {Ep : Entry} (hp : Γ p = some Ep)
    (hrb : Ep.mode = .rootb) : callPost Γ fn args p = some Ep := by
  have hanch := h.anch p Ep hp hrb
  have haux : callPostAux Γ fn args fn.params args 0 Γ p = some Ep := by
    refine callPostAux_rootb fn.params args 0 Γ (fun pa hpa hm => ?_) hp
    obtain ⟨k, hk, _, rfl⟩ := RSetup.mem_zip_getD hpa
    obtain ⟨Ea, hEa, _, hok, hmv, hpin⟩ := h.arg k hk
    simp only at hm ⊢
    obtain ⟨haF, _⟩ := hmv hm
    have hne : args.getD k 0 ≠ p := by
      intro he; rw [he, hp] at hEa; cases hEa
      generalize fn.params[k] = q at hok hm
      obtain ⟨pm, t⟩ := q
      cases pm with
      | inp => cases hm
      | sink => obtain ⟨_, hm', _⟩ := hok; rw [hrb] at hm'; cases hm'
      | inout b =>
        obtain ⟨_, hcan, _⟩ := hok
        rcases hcan with hm' | ⟨b', hm', _⟩ <;> rw [hrb] at hm' <;> cases hm'
    refine ⟨hne, fun d hd hr => ?_⟩
    by_cases hb : d.kind.bound = .none
    · exact absurd (hr ▸ hanch d hd hb) haF
    · refine ⟨bound_isName hb, ?_⟩
      generalize fn.params[k] = q at hm hpin
      obtain ⟨pm, t⟩ := q
      cases pm with
      | inp => cases hm
      | sink => exact absurd hr ((hpin (Or.inl rfl)) p Ep hp hrb d hd hb)
      | inout b =>
        refine ⟨b, rfl, fun hbr => ?_⟩
        subst hbr
        exact (hpin (Or.inr rfl)) p Ep hp hrb d hd hb hr
  unfold callPost
  rw [RSetup.killNames_eq, haux]
  simp only [Option.map_some, Option.some.injEq]
  unfold RSetup.killAll
  rw [ite_eq_right]
  intro hany
  obtain ⟨d, hdm, hh⟩ := List.any_eq_true.mp hany
  obtain ⟨hdn, hb⟩ := List.mem_filter.mp hdm
  obtain ⟨_, _, hF, _, _⟩ := h.nfree d hdm
  have hb' : d.kind.bound ≠ .none := by simpa using hb
  have hbr := h.argNames_bound hdn hb'
  have hno : hits d.kind.bound false d.root Ep = false := RSetup.hits_false_of (fun d' hd' hr => by
    by_cases hb0 : d'.kind.bound = .none
    · exact absurd (hr ▸ hanch d' hd' hb0) hF
    · exact RSetup.kills_isName hbr _ (bound_isName hb0))
  rw [hno] at hh; cases hh

theorem killNames_nil {Γ : Ctx} {p : Var} {E : Entry} (hp : Γ p = some E) (hv : E.vdeps = []) :
    ∀ ds, killNames ds Γ p = some E
  | [] => hp
  | d :: ds => by
    change (A2.kill _ _ _ (A2.killNames ds Γ)) p = some E
    simp only [A2.kill, killNames_nil hp hv ds, Option.map_some, killE_nil hv]

/-- A binding that may be held by name and that the call does not move is
    as it was. -/
theorem post_named (_h : CallH P Γ F x fn args base) {p : Var} {Ep : Entry} (hp : Γ p = some Ep)
    (hn : Ep.named) (hnm : ∀ k (hk : k < fn.params.length), fn.params[k].1.moves = true → args.getD k 0 ≠ p) :
    callPost Γ fn args p = some Ep := by
  have haux : callPostAux Γ fn args fn.params args 0 Γ p = some Ep := by
    refine callPostAux_rootb fn.params args 0 Γ (fun pa hpa hm => ⟨?_, fun d hd => ?_⟩) hp
    · obtain ⟨k, hk, _, rfl⟩ := RSetup.mem_zip_getD hpa
      exact hnm k hk hm
    · rw [hn.vdeps] at hd; cases hd
  exact killNames_nil haux hn.vdeps _

theorem N_named (h : CallH P Γ F x fn args base) :
    DepsNamed (callS Γ F fn args base x).Φ (callS Γ F fn args base x).N := by
  intro d hdN b t hk
  obtain ⟨hd, hio⟩ := (h.mem_N).mp hdN
  obtain ⟨Er, hEr, hl, hh, ht, ho, hc, hhv⟩ := h.argNames_named hd d (List.mem_singleton_self _) b t hk
  -- no argument the call moves is it: a `sink` argument is reached by
  -- nothing, an `inout` one is no root of the frame's names
  have hnm : ∀ k (hk : k < fn.params.length), fn.params[k].1.moves = true → args.getD k 0 ≠ d.root := by
    intro k hk hm he
    obtain ⟨j, hj, Ea, hEa, _, _, hdv, _⟩ := h.argNames_mem hd
    have hr : d.root ∈ roots Ea.vdeps := List.mem_map_of_mem hdv
    have hae : argE Γ (args.getD j 0) = Ea := by unfold argE; rw [hEa]; rfl
    revert hm; generalize hq : fn.params[k] = q; obtain ⟨pm, tk⟩ := q
    cases pm with
    | inp => intro hm; cases hm
    | sink => intro _; exact h.moving_sink hk hj (by rw [hq]) (by rw [hae, he]; exact hr)
    | inout bk => intro _; exact hio (he ▸ mem_inoutArgs (List.getElem?_eq_getElem hk |>.trans (by rw [hq])))
  have hpost := h.post_named hEr ⟨hl, hh, ho, by rw [ht]; exact hhv⟩ hnm
  refine ⟨Er.clean, by rw [h.frame_of (h.N_root hdN).1 (h.post_ne_x hpost), hpost]; rfl,
    by rw [clean_live]; exact hl, by unfold Entry.clean; split <;> simp [hh],
    by rw [clean_ty, ht], by rw [clean_mode]; exact ho, by rw [clean_mode]; exact hc, hhv⟩

theorem post_live_rootb (h : CallH P Γ F x fn args base) {y : Var} {E1 : Entry}
    (hy : callPost Γ fn args y = some E1) (hrb : E1.mode = .rootb) : E1.live = true := by
  obtain ⟨E0, h0, hm⟩ := h.postdm.2 y E1 hy
  rw [hrb] at hm
  have := h.post_rootb h0 hm.symm
  rw [hy] at this
  rw [Option.some.inj this]
  exact h.rbLive y E0 h0 hm.symm

/-- A frame binding the call does not move: its argument (if any) is an `inout` one, renamed. -/
theorem frame_nomove (h : CallH P Γ F x fn args base) {y : Var}
    (hout : ∀ v, callRen fn.params args base v ≠ y) {E2 : Entry}
    (h2 : callPostAux Γ fn args fn.params args 0 Γ y = some E2) (hl : E2.live = true) :
    ∀ pa ∈ fn.params.zip args, pa.1.1.moves = true → pa.2 ≠ y := by
  intro pa hpa hm hpy
  obtain ⟨k, hk, hka, rfl⟩ := RSetup.mem_zip_getD hpa
  simp only at hm hpy
  have hget : fn.params[k]? = some fn.params[k] := List.getElem?_eq_getElem hk
  generalize hp : fn.params[k] = p at hm hget
  obtain ⟨pm, t'⟩ := p
  cases pm with
  | inp => cases hm
  | inout b' =>
    exact hout k (by
      rcases callRen_cases fn.params args base k with ⟨_, _, _, hr⟩ | ⟨hk', _⟩
      · exact hr.trans hpy
      · exact absurd hget (hk' b' t'))
  | sink =>
    have hak : args[k]? = some y := by rw [← hpy]; simp [List.getD, hka]
    have hu : ∀ k', k' ≠ k → args[k']? ≠ some y := by
      intro k' hk' he
      have hk'l : k' < args.length := (List.getElem?_eq_some_iff.mp he).1
      have hge : args.getD k' 0 = args.getD k 0 := by
        rw [hpy]; simp [List.getD, he]
      exact hk' (h.moving hk (h.len ▸ hk'l) (by rw [hp]; rfl) hge)
    have := callPostAux_at fn.params args 0 k Γ hak hu hget rfl E2 h2
    simp only [postEnt] at this
    exact absurd (this.2.2.2.2 hl) (by simp)

/-- A live frame binding is a live caller binding, as it was. -/
theorem frame_src (h : CallH P Γ F x fn args base) {y : Var} {E : Entry}
    (hy : (callS Γ F fn args base x).Φ y = some E) (hl : E.live = true) :
    ∃ E0, Γ y = some E0 ∧ E0.live = true ∧ E.ty = E0.ty ∧ E.mode = E0.mode ∧
      ((E.ty ≠ .int ∨ E.mode = .rootb) → E.vdeps = E0.vdeps ∧ E.held = E0.held) := by
  obtain ⟨hout, E1, h1, rfl⟩ := h.frame_some hy
  rw [clean_live] at hl
  have hyx : y ≠ x := by
    intro e; subst e; simp only [setE, upd_same, Option.some.injEq] at h1; subst h1; cases hl
  simp only [setE, upd_ne _ _ hyx] at h1
  obtain ⟨E2, h2, ht2, hm2, hp2, hh2, hl2⟩ := killNames_get _ h1
  have hl2' := (hl2 hl).1
  obtain ⟨E0, h0, ht0, hm0, hp0, hh0, hsv⟩ :=
    callPostAux_frame fn.params args 0 Γ (h.frame_nomove hout h2 hl2') E2 h2
  refine ⟨E0, h0, (hsv hl2').1, by rw [clean_ty, ht2, ht0], by rw [clean_mode, hm2, hm0], fun hn => ?_⟩
  rw [clean_ty, clean_mode] at hn
  rw [clean_id hn hl]
  exact ⟨by unfold Entry.vdeps; rw [hm2, hp2, hh2, hm0, hp0, hh0], by rw [hh2, hh0]⟩

/-- What the frame depends on in the callee is an `inout` argument, whose
    bound ends none of it. -/
theorem frame_sat (h : CallH P Γ F x fn args base) :
    ∀ y E, (callS Γ F fn args base x).Φ y = some E → E.live = true → (E.ty ≠ .int ∨ E.mode = .rootb) →
      ∀ d ∈ E.vdeps, ∀ v, (callS Γ F fn args base x).ρ v = d.root →
        ∃ b hv, (callS Γ F fn args base x).bnd v = some (b, hv) ∧ b.kills hv d.kind = false := by
  intro y E hy hl hn d hd v hv
  obtain ⟨hout, E1, h1, rfl⟩ := h.frame_some hy
  rw [clean_live] at hl
  have hn1 : E1.ty ≠ .int ∨ E1.mode = .rootb := by rwa [clean_ty, clean_mode] at hn
  rw [clean_id hn1 hl] at hd
  have hyx : y ≠ x := by
    intro e; subst e; simp only [setE, upd_same, Option.some.injEq] at h1; subst h1; cases hl
  simp only [setE, upd_ne _ _ hyx] at h1
  -- the root lies in the caller's context, so it is an `inout` argument
  obtain ⟨Er, hEr, _⟩ := h.postwf y E1 h1 hl hn1 d.root (List.mem_map_of_mem hd)
  obtain ⟨b, t, hvp, hav⟩ := h.ren_dom hv (h.post_lt hEr)
  refine ⟨b, t.elem.holdsView, by simp [callS, bndOf, hvp], ?_⟩
  obtain ⟨E2, h2, ht2, hm2, hp2, hh2, hl2⟩ := killNames_get _ h1
  -- `y` is no moving argument: an `inout` one is renamed, a `sink` one is dead
  have hmv : ∀ pa ∈ fn.params.zip args, pa.1.1.moves = true → pa.2 ≠ y := by
    intro pa hpa hm hpy
    obtain ⟨k, hk, hka, rfl⟩ := RSetup.mem_zip_getD hpa
    simp only at hm hpy
    have hget : fn.params[k]? = some fn.params[k] := List.getElem?_eq_getElem hk
    generalize hp : fn.params[k] = p at hm hget
    obtain ⟨pm, t'⟩ := p
    cases pm with
    | inp => cases hm
    | inout b' =>
      exact hout k (by
        rcases callRen_cases fn.params args base k with ⟨_, _, _, hr⟩ | ⟨hk', _⟩
        · exact hr.trans hpy
        · exact absurd hget (hk' b' t'))
    | sink =>
      have hak : args[k]? = some y := by rw [← hpy]; simp [List.getD, hka]
      have hu : ∀ k', k' ≠ k → args[k']? ≠ some y := by
        intro k' hk' he
        have hk'l : k' < args.length := (List.getElem?_eq_some_iff.mp he).1
        have hge : args.getD k' 0 = args.getD k 0 := by
          rw [hpy]; simp [List.getD, he]
        exact hk' (h.moving hk (h.len ▸ hk'l) (by rw [hp]; rfl) hge)
      have := callPostAux_at fn.params args 0 k Γ hak hu hget rfl E2 h2
      simp only [postEnt] at this
      exact absurd (this.2.2.2.2 (hl2 hl).1) (by simp)
  obtain ⟨E0, h0, ht0, hm0, hp0, hh0, hsv⟩ := callPostAux_frame fn.params args 0 Γ hmv E2 h2
  rw [← ht2] at ht0; rw [← hm2] at hm0; rw [← hp2] at hp0; rw [← hh2] at hh0
  replace hl := (hl2 hl).1
  have hs := ((hsv hl).2 ((.inout b, t), args.getD v 0)
    (mem_zip_of hvp (h.len ▸ lt_of_get hvp))).2 b rfl
  have hn0 : E0.ty ≠ .int ∨ E0.mode = .rootb := by rwa [← ht0, ← hm0]
  have hd0 : d ∈ E0.vdeps := by unfold Entry.vdeps at hd ⊢; rwa [← hm0, ← hp0, ← hh0]
  exact hits_false_dep hs hn0 d hd0 hav.symm

theorem sOK (h : CallH P Γ F x fn args base) : (callS Γ F fn args base x).OK where
  inj := h.ren_inj
  Rout r hr := (h.R_facts hr).1
  Rroot r hr := by
    obtain ⟨hout, Er, hEr, hro⟩ := h.R_facts hr
    exact h.frame_root hEr hro hout
  Fcout v := by
    show callRen fn.params args base v ∉ F ++ zN Γ fn args base
    intro hm
    rcases callRen_cases fn.params args base v with ⟨b, t, hv, hrv⟩ | ⟨_, hrv⟩ <;> rw [hrv] at hm
    · rcases List.mem_append.mp hm with hm | hm
      · obtain ⟨_, _, _, _, hmv, _⟩ := h.arg v (lt_of_get hv)
        exact (hmv (by rw [get_of hv]; rfl)).1 hm
      · replace hm := zN_sub _ hm
        simp only [zOf, List.mem_filter, Bool.not_eq_eq_eq_not, Bool.not_true,
          List.contains_eq_mem, decide_eq_false_iff_not] at hm
        exact hm.2 (mem_inoutArgs hv)
    · rcases List.mem_append.mp hm with hm | hm
      · exact absurd (h.Flt _ hm) (Nat.not_lt.mpr (Nat.le_add_right _ _))
      · replace hm := zN_sub _ hm
        simp only [zOf, List.mem_filter, List.mem_range] at hm
        exact absurd hm.1 (Nat.not_lt.mpr (Nat.le_add_right _ _))
  pe_rb v := by
    show (callPe Γ fn.params args v).mode = .rootb
    unfold callPe; split
    · split <;> rfl
    · rfl
  pe_out v d hd hn := by
    obtain ⟨Ea, hvp, hEa, hl, hni, hc, _, hvi⟩ := h.pe_vdeps v hd
    have hae : argE Γ (args.getD v 0) = Ea := by unfold argE; rw [hEa]; rfl
    rcases hc with ⟨he, _, hro⟩ | hdv
    · rw [he]
      have hout : ∀ w, callRen fn.params args base w ≠ args.getD v 0 := by
        intro w hw
        obtain ⟨b, t', hwp, hwe⟩ := h.ren_dom hw (h.argLt hvp)
        have := h.moving (lt_of_get hwp) hvp (by rw [get_of hwp]; rfl) hwe.symm
        subst this; rw [hvi] at hwp; cases hwp
      exact ⟨hout, h.frame_root hEa hro hout⟩
    · have hrv : d.root ∈ roots (memDeps Ea.vdeps) :=
        List.mem_map_of_mem (List.mem_filter.mpr ⟨hdv, by simp [hn]⟩)
      obtain ⟨Er, hEr, hro⟩ := h.wf _ Ea hEa hl (Or.inl hni) d.root (List.mem_map_of_mem hdv)
      have hout := h.notRen_root hvp (by rw [hae]; exact hrv) (h.domlt _ Er hEr)
      exact ⟨hout, h.frame_root hEr hro hout⟩
  Φsat := h.frame_sat
  Φwf y E hy hl hn r hr hout := by
    obtain ⟨_, E1, h1, rfl⟩ := h.frame_some hy
    rw [clean_live] at hl
    have hn1 : E1.ty ≠ .int ∨ E1.mode = .rootb := by rwa [clean_ty, clean_mode] at hn
    rw [clean_id hn1 hl] at hr
    have hyx : y ≠ x := by
      intro e; subst e; simp only [setE, upd_same, Option.some.injEq] at h1; subst h1; cases hl
    simp only [setE, upd_ne _ _ hyx] at h1
    obtain ⟨Er, hEr, hro⟩ := h.postwf y E1 h1 hl hn1 r hr
    rw [h.frame_of hout (h.post_ne_x hEr)]
    exact ⟨Er.clean, by rw [hEr]; rfl, by rw [clean_mode]; exact hro⟩
  Φρ v := by simp only [callS]; rw [ite_eq_left ⟨v, rfl⟩]
  pe_held v d hd := by
    cases hk : d.kind.isName with
    | false =>
      -- in memory: what the argument holds, a root the arguments hold views of
      left
      have hdv : d ∈ (callPe Γ fn.params args v).vdeps := by
        unfold Entry.vdeps; exact List.mem_append_right _ hd
      obtain ⟨Ea, hvp, hEa, _, hn, _, _, hvi⟩ := h.pe_vdeps v hdv
      have hmem : args.getD v 0 ∈ args := by simp [List.getD, show v < args.length from h.len ▸ hvp]
      have hae : argE Γ (args.getD v 0) = Ea := by unfold argE; rw [hEa]; rfl
      have hd' : d ∈ Ea.held := by
        revert hd; show d ∈ (callPe Γ fn.params args v).held → _
        unfold callPe; rw [hvi]; simp only; rw [ite_eq_right (by rw [hae]; exact hn)]
        intro hd; rw [hae] at hd; exact (mem_typedDeps hd).1
      exact List.mem_append_left _ (RSetup.mem_allKinds_iff.mpr ⟨mem_callR.mpr ⟨_, hmem, by rw [hae]; exact hn,
        by rw [hae]; exact List.mem_map_of_mem (List.mem_filter.mpr ⟨hd', by simp [hk]⟩)⟩, hk⟩)
    | true =>
      have hdv : d ∈ (callPe Γ fn.params args v).vdeps := by
        unfold Entry.vdeps; exact List.mem_append_right _ hd
      rcases h.pe_names v hdv hk with hN | hs
      · exact Or.inl (List.mem_append_right _ hN)
      · exact Or.inr hs
  pe_names v d hd hn := h.pe_names v hd hn
  sym_ok d hd := by
    obtain ⟨w, b, t, rfl, hp, hhv, hbn, hbr⟩ := mem_symNames' hd
    refine ⟨w, b, t, rfl, ?_, ?_, hbn, hbr⟩
    · show bndOf fn.params w = _
      unfold bndOf; rw [hp]; simp [elem_holdsView, hhv]
    · show ((fn.params[w]?).map (·.2)).getD .int = t
      rw [hp]; rfl
  sym_of w b t hb ht hbn hbr := by
    change bndOf fn.params w = some (b, false) at hb
    change ((fn.params[w]?).map (·.2)).getD .int = t at ht
    unfold bndOf at hb
    split at hb
    · rename_i b' t' hp
      simp only [Option.some.injEq, Prod.mk.injEq] at hb
      obtain ⟨rfl, hhv⟩ := hb
      rw [hp] at ht; simp only [Option.map_some, Option.getD_some] at ht; subst ht
      exact mem_symNames.mpr ⟨hp, by rw [← elem_holdsView]; exact hhv, hbn, hbr⟩
    · cases hb
  Φio y E b hy := by
    obtain ⟨_, E1, h1, rfl⟩ := h.frame_some hy
    rw [clean_mode]
    by_cases hyx : y = x
    · subst hyx; simp only [setE, upd_same, Option.some.injEq] at h1; subst h1
      exact resMode_inout fn b
    · simp only [setE, upd_ne _ _ hyx] at h1
      obtain ⟨E0, h0, hm, _⟩ := h.postdt.2 y E1 h1
      rw [hm]; exact h.noio y E0 b h0
  N_name d hd := by
    obtain ⟨_, _, _, _, _, _, _, hn⟩ := h.argNames_mem ((h.mem_N).mp hd).1; exact hn
  N_out d hd := by
    obtain ⟨hout, Er, hEr, hro⟩ := h.N_root hd
    exact ⟨hout, h.frame_root hEr hro hout⟩
  N_named := h.N_named
  N_mut d hdN hb := by
    obtain ⟨hout, Er, hEr, _⟩ := h.N_root hdN
    obtain ⟨hd, _⟩ := (h.mem_N).mp hdN
    have hdm : d ∈ mutNames Γ args := List.mem_filter.mpr ⟨hd, by simpa using hb⟩
    obtain ⟨hcan, ⟨s, hts, hsv⟩, hF, hna, hoth⟩ := h.nfree d hdm
    have hae : argE Γ d.root = Er := by unfold argE; rw [hEr]; rfl
    rw [hae] at hcan hts
    refine ⟨?_, ?_, ?_, ?_, ?_, ?_⟩
    · show d.root ∉ F ++ zN Γ fn args base
      intro hm
      rcases List.mem_append.mp hm with hm | hm
      · exact hF hm
      · have := (List.mem_filter.mp hm).2
        have hin : d.root ∈ roots (mutNames Γ args) := List.mem_map_of_mem hdm
        simp [hin] at this
    · show d.root ∉ callR Γ args
      intro hm
      obtain ⟨a, ha, hn, hrh⟩ := mem_callR.mp hm
      obtain ⟨d', hd', hr'⟩ := List.mem_map.mp hrh
      obtain ⟨hd'h, hd'n⟩ := List.mem_filter.mp hd'
      have := hoth a ha (Or.inl hn) d' (by unfold Entry.vdeps; exact List.mem_append_right _ hd'h) hr'
      rw [bound_isName (by rw [this]; exact hb)] at hd'n; cases hd'n
    · obtain ⟨E, hE, hte, hme⟩ := h.frame_ty hEr hout
      exact ⟨E, hE, by rw [hme]; exact hcan, s, by rw [hte]; exact hts, hsv⟩
    · intro v d' hd' hr'
      obtain ⟨Ea, hvp, hEa, _, hni, hc, _⟩ := h.pe_vdeps v hd'
      have hmem : args.getD v 0 ∈ args := by simp [List.getD, show v < args.length from h.len ▸ hvp]
      have hae' : argE Γ (args.getD v 0) = Ea := by unfold argE; rw [hEa]; rfl
      rcases hc with ⟨he, _, _⟩ | hdv
      · have hre : d.root = args.getD v 0 := hr'.symm.trans he
        rcases hna with hna | ⟨i, t, hai, hpi⟩
        · exact absurd (hre ▸ hmem) hna
        · have hai' : args.getD i 0 = d.root := by simp [List.getD_eq_getElem?_getD, hai]
          exact absurd (hai' ▸ mem_inoutArgs hpi) ((h.mem_N).mp hdN).2
      · exact hoth _ hmem (Or.inl (by rw [hae']; exact hni)) d' (by rw [hae']; exact hdv) hr'
    · intro d' hd' hr'
      obtain ⟨j, hj, Ea, hEa, _, hni, hdv, _⟩ := h.argNames_mem ((h.mem_N).mp hd').1
      have hmem : args.getD j 0 ∈ args := by simp [List.getD, show j < args.length from h.len ▸ hj]
      have hae' : argE Γ (args.getD j 0) = Ea := by unfold argE; rw [hEa]; rfl
      exact hoth _ hmem (Or.inl (by rw [hae']; exact hni)) d' (by rw [hae']; exact hdv) hr'
    · intro y E hy hl
      obtain ⟨_, E1, h1, rfl⟩ := h.frame_some hy
      rw [clean_live] at hl
      have hyx : y ≠ x := by
        intro e; subst e; simp only [setE, upd_same, Option.some.injEq] at h1; subst h1; cases hl
      simp only [setE, upd_ne _ _ hyx] at h1
      obtain ⟨E2, h2, ht2, hm2, hp2, hh2, hl2⟩ := killNames_get _ h1
      rw [hits_clean hl]
      have hv : E1.vdeps = E2.vdeps := by unfold Entry.vdeps; rw [hm2, hp2, hh2]
      have := (hl2 hl).2 d hdm
      unfold hits at this ⊢; rw [ht2, hm2, hv]; exact this
  Φrb y E hy hm := by
    obtain ⟨_, E1, h1, rfl⟩ := h.frame_some hy
    rw [clean_mode] at hm
    have hyx : y ≠ x := by
      intro e; subst e; simp only [setE, upd_same, Option.some.injEq] at h1; subst h1
      exact resMode_ne' fn hm
    simp only [setE, upd_ne _ _ hyx] at h1
    rw [clean_live]; exact h.post_live_rootb h1 hm
  Φnamed y E hy hl hn d hd b t hk := by
    have hsat := h.frame_sat y E hy hl hn d hd
    obtain ⟨hout, E1, h1, rfl⟩ := h.frame_some hy
    rw [clean_live] at hl
    have hn1 : E1.ty ≠ .int ∨ E1.mode = .rootb := by rwa [clean_ty, clean_mode] at hn
    rw [clean_id hn1 hl] at hd
    have hyx : y ≠ x := by
      intro e; subst e; simp only [setE, upd_same, Option.some.injEq] at h1; subst h1; cases hl
    have h1' : callPost Γ fn args y = some E1 := by simpa [setE, upd_ne _ _ hyx] using h1
    -- after the call, what `y` holds by name is bound, live and holds nothing
    obtain ⟨Er0, hEr0, _⟩ := h.postwf y E1 h1' hl hn1 d.root (List.mem_map_of_mem hd)
    have hrx : d.root ≠ x := h.post_ne_x hEr0
    obtain ⟨Er, hEr, hlr, hhr, htr, hor, hcr, hhv⟩ :=
      h.resnames y E1 (by simp [setE, upd_ne _ _ hyx, h1']) hl hn1 d hd b t hk
    simp only [setE, upd_ne _ _ hrx] at hEr
    by_cases hρ : ∃ v, callRen fn.params args base v = d.root
    · obtain ⟨v, hv⟩ := hρ
      obtain ⟨b', t', hvp, hav⟩ := h.ren_dom hv (h.post_lt hEr)
      have hbe : (callS Γ F fn args base x).bnd v = some (b', t'.elem.holdsView) := by
        simp [callS, bndOf, hvp]
      obtain ⟨b'', hv'', hbnd, hkill⟩ := hsat v hv
      rw [hbe] at hbnd
      simp only [Option.some.injEq, Prod.mk.injEq] at hbnd
      obtain ⟨rfl, rfl⟩ := hbnd
      have hbr : b' ≠ .replace := fun e => by rw [e, hk] at hkill; simp [Eff.kills] at hkill
      refine Or.inl ⟨v, (b', t'.elem.holdsView), hv, hbe, ?_, ?_, hbr, hhv⟩
      · show ((fn.params[v]?).map (·.2)).getD .int = t
        rw [hvp]; simp only [Option.map_some, Option.getD_some]
        obtain ⟨Ea, hEa, _, hok, _⟩ := h.arg v (lt_of_get hvp)
        rw [get_of hvp] at hok
        obtain ⟨hty, _⟩ := hok
        obtain ⟨E0, h0, _, ht0⟩ := h.postdt.2 _ Er hEr
        rw [hav, h0] at hEa; cases hEa
        exact hty.symm.trans (ht0.symm.trans htr)
      · rcases hcr with hcr | ⟨hcr, _⟩
        · rw [hcr]; exact fun e => by cases e
        · exact hcr
    · have hout' : ∀ v, callRen fn.params args base v ≠ d.root := fun v hv => hρ ⟨v, hv⟩
      exact Or.inr ⟨hout', Er.clean, by rw [h.frame_of hout' hrx, hEr]; rfl,
        by rw [clean_live]; exact hlr, by unfold Entry.clean; split <;> simp [hhr],
        by rw [clean_ty]; exact htr, by rw [clean_mode]; exact hor, by rw [clean_mode]; exact hcr, hhv⟩

end CallH

/-! ### The exits of the parameters' scopes -/

/-- The context after the parameters' scopes end, innermost first. -/
def exitsP : List (PMode × Ty) → Nat → Nat → (Var → Entry) → Ctx → Ctx
  | [], _, _, _, Δ => Δ
  | (.inp, _) :: ps, base, i, pe, Δ => exitRoot (base + i) ((pe i).path ++ (pe i).held) (exitsP ps base (i + 1) pe Δ)
  | (.sink, _) :: ps, base, i, pe, Δ => exitScope (base + i) (exitsP ps base (i + 1) pe Δ)
  | (.inout _, _) :: ps, base, i, pe, Δ => exitsP ps base (i + 1) pe Δ

/-- What the exits make of a list of dependencies. -/
def rrL : List (PMode × Ty) → Nat → Nat → (Var → Entry) → List Dep → List Dep
  | [], _, _, _, L => L
  | (.inp, _) :: ps, base, i, pe, L => reroot (base + i) ((pe i).path ++ (pe i).held) (rrL ps base (i + 1) pe L)
  | _ :: ps, base, i, pe, L => rrL ps base (i + 1) pe L

def rrE (ps : List (PMode × Ty)) (base i : Nat) (pe : Var → Entry) (E : Entry) : Entry :=
  { E with path := rrL ps base i pe E.path, held := rrL ps base i pe E.held }

/-- The condition for binding the parameters' scopes. -/
def WrapCond (Γ : Ctx) (Fc : List Var) (base : Nat) (pe : Var → Entry) (j : Nat) : PMode × Ty → Prop
  | (.inp, _) => ∃ E, Γ (base + j) = some E ∧ E.mode = .rootb ∧ E.live = true ∧
      Anchored E Fc ∧ base + j ∉ Fc ∧ E.path ++ E.held = (pe j).path ++ (pe j).held
  | (.sink, _) => (∃ E, Γ (base + j) = some E ∧ E.mode ≠ .rootb) ∧ base + j ∉ Fc
  | (.inout _, _) => True

/-- The exits keep the caller's bindings and their modes. -/
theorem exitsP_mode {base : Nat} {pe : Var → Entry} : ∀ (ps : List (PMode × Ty)) (i : Nat) (Δ : Ctx)
    {y : Var}, y < base → (exitsP ps base i pe Δ y).map Entry.mode = (Δ y).map Entry.mode
  | [], _, _, _, _ => rfl
  | (pm, t) :: ps, i, Δ, y, hy => by
    have hne : y ≠ base + i := fun e => by have := vlt hy; have := veq e; omega
    have ih := exitsP_mode (pe := pe) ps (i + 1) Δ hy
    cases pm with
    | inp =>
      simp only [exitsP, exitRoot, upd_ne _ _ hne]; rw [← ih]
      cases exitsP ps base (i + 1) pe Δ y <;> rfl
    | sink =>
      simp only [exitsP, A2.exitScope, upd_ne _ _ hne, A2.kill]; rw [← ih]
      cases exitsP ps base (i + 1) pe Δ y <;> simp [killE_mode]
    | inout b => exact ih

theorem reroot_lt {p base : Var} {D L : List Dep} (hL : ∀ d ∈ L, d.root < base) (hD : ∀ d ∈ D, d.root < base) :
    ∀ d ∈ reroot p D L, d.root < base := by
  intro d hd
  rcases mem_reroot hd with ⟨hin, _⟩ | ⟨k, d', _, hd', rfl⟩
  · exact hL d hin
  · exact hD d' hd'

/-- What every borrowed parameter's dependencies satisfy. -/
def RbQ (Q : Var → Prop) (Γ : Ctx) : Prop :=
  ∀ p E, Γ p = some E → E.mode = .rootb → ∀ d ∈ E.vdeps, Q d.root

theorem RbQ.kill {Q : Var → Prop} {Γ : Ctx} (h : RbQ Q Γ) (e : Eff) (hv : Bool) (x : Var) :
    RbQ Q (A2.kill e hv x Γ) := by
  intro p E hp hm d hd
  simp only [A2.kill] at hp
  cases h0 : Γ p with
  | none => rw [h0] at hp; cases hp
  | some E0 =>
    rw [h0] at hp; simp only [Option.map_some, Option.some.injEq] at hp; subst hp
    rw [killE_mode] at hm; rw [killE_vdeps] at hd
    exact h p E0 h0 hm d hd

theorem RbQ.setE {Q : Var → Prop} {Γ : Ctx} (h : RbQ Q Γ) {x : Var} {E : Entry} (hE : E.mode ≠ .rootb) :
    RbQ Q (A2.setE Γ x E) := by
  intro p E' hp hm d hd
  by_cases hpx : p = x
  · subst hpx; simp only [A2.setE, upd_same, Option.some.injEq] at hp; subst hp; exact absurd hm hE
  · simp only [A2.setE, upd_ne _ _ hpx] at hp; exact h p E' hp hm d hd

theorem RbQ.noPin {Q : Var → Prop} {Γ : Ctx} (h : RbQ Q Γ) {x : Var} (hx : ¬ Q x) : NoPin Γ x :=
  fun p E hp hm d hd _ he => hx (he ▸ h p E hp hm d hd)

/-- A borrowed parameter depends on nothing of the callee's, before the exits
    and after. -/
theorem exitsP_rblt {base : Nat} {pe : Var → Entry} {Q : Var → Prop}
    (hpe : ∀ j, ∀ d ∈ (pe j).path ++ (pe j).held, Q d.root) :
    ∀ (ps : List (PMode × Ty)) (i : Nat) (Δ : Ctx), RbQ Q Δ → RbQ Q (exitsP ps base i pe Δ)
  | [], _, _, h => h
  | (pm, t) :: ps, i, Δ, h => by
    have ih := exitsP_rblt (base := base) hpe ps (i + 1) Δ h
    intro p E hp hm d hd
    cases pm with
    | inp =>
      simp only [exitsP, exitRoot] at hp
      by_cases hpi : p = base + i
      · subst hpi; simp [upd] at hp
      · rw [upd_ne _ _ hpi] at hp
        cases h0 : exitsP ps base (i + 1) pe Δ p with
        | none => rw [h0] at hp; cases hp
        | some E0 =>
          rw [h0] at hp; simp only [Option.map_some, Option.some.injEq] at hp; subst hp
          have hm0 : E0.mode = .rootb := hm
          have hall : ∀ d ∈ E0.path ++ E0.held, Q d.root := by
            have := ih p E0 h0 hm0; simpa [Entry.vdeps, hm0, Mode.ownSlot] using this
          simp only [Entry.vdeps, rerootE, hm0, Mode.ownSlot, Bool.false_eq_true, ↓reduceIte,
            List.mem_append] at hd
          have hq : ∀ L, (∀ d ∈ L, Q d.root) → ∀ d ∈ reroot (base + i) ((pe i).path ++ (pe i).held) L,
              Q d.root := by
            intro L hL d hd
            rcases mem_reroot hd with ⟨hin, _⟩ | ⟨k, d', _, hd', rfl⟩
            · exact hL d hin
            · exact hpe i d' hd'
          rcases hd with hd | hd
          · exact hq _ (fun d' h' => hall d' (List.mem_append_left _ h')) d hd
          · exact hq _ (fun d' h' => hall d' (List.mem_append_right _ h')) d hd
    | sink =>
      simp only [exitsP, A2.exitScope] at hp
      by_cases hpi : p = base + i
      · subst hpi; simp [upd] at hp
      · rw [upd_ne _ _ hpi] at hp
        exact (RbQ.kill ih .replace false (base + i)) p E hp hm d hd
    | inout b => exact ih p E hp hm d hd

theorem wrap_typed {P : Prog} {Γ : Ctx} {Fc : List Var} {base : Nat} {pe : Var → Entry} {s : Stmt}
    {Δ : Ctx} (hs : StmtT P Γ Fc s Δ) (hpe : ∀ j, ∀ d ∈ (pe j).path ++ (pe j).held, d.root < base)
    -- what a borrowed parameter may change by name stays bound to the end
    (hpw : ∀ j, ∀ d ∈ (pe j).path ++ (pe j).held, d.kind.bound ≠ .none →
      ∃ Er, Δ d.root = some Er ∧ Er.mode.isRoot = true)
    (hΔrb : RbQ (· < base) Δ) :
    ∀ (ps : List (PMode × Ty)) (i : Nat), (∀ k p, ps[k]? = some p → WrapCond Γ Fc base pe (i + k) p) →
      StmtT P Γ Fc (wrapParams ps base i s) (exitsP ps base i pe Δ) := by
  intro ps
  induction ps with
  | nil => intro i _; exact hs
  | cons p ps ih =>
    intro i hc
    have hc' : ∀ k p, ps[k]? = some p → WrapCond Γ Fc base pe (i + 1 + k) p := by
      intro k p hp; have := hc (k + 1) p (by simpa using hp); rwa [show i + (k + 1) = i + 1 + k by omega] at this
    have h0 := hc 0 p (by simp)
    simp only [Nat.add_zero] at h0
    obtain ⟨pm, t⟩ := p
    cases pm with
    | inp =>
      obtain ⟨E, hE, hm, hl, hr, hF, hp⟩ := h0
      have hvd : E.vdeps = (pe i).path ++ (pe i).held := by
        rw [← hp]; simp [Entry.vdeps, hm, Mode.ownSlot]
      have := StmtT.rbind (P := P) hE hm hl hr hF (ih (i + 1) hc') (fun d hd hb => by
        rw [hvd] at hd
        obtain ⟨Er, hEr, hro⟩ := hpw i d hd hb
        have hlt := hpe i d hd
        refine ⟨fun e => by have := vlt hlt; have := veq e; omega, ?_⟩
        have hmode := exitsP_mode (pe := pe) ps (i + 1) Δ hlt
        rw [hEr] at hmode
        cases hx : exitsP ps base (i + 1) pe Δ d.root with
        | none => rw [hx] at hmode; cases hmode
        | some Er' =>
          rw [hx] at hmode; simp only [Option.map_some, Option.some.injEq] at hmode
          exact ⟨Er', rfl, by rw [hmode]; exact hro⟩)
      rw [hp] at this; exact this
    | sink =>
      obtain ⟨hE, hF⟩ := h0
      exact StmtT.scope hE hF (ih (i + 1) hc') (fun p E hp hm d hd _ he => by
        have := vlt (exitsP_rblt (Q := (· < base)) hpe ps (i + 1) Δ hΔrb p E hp hm d hd)
        have := veq he
        omega)
    | inout b => exact ih (i + 1) hc'

theorem mem_rrL {base : Nat} {pe : Var → Entry} (hpe : ∀ j, ∀ d ∈ (pe j).path ++ (pe j).held, d.root < base) :
    ∀ (ps : List (PMode × Ty)) (i : Nat) (L : List Dep) {d' : Dep}, d' ∈ rrL ps base i pe L →
      (d' ∈ L ∧ ∀ k t, ps[k]? = some (.inp, t) → d'.root ≠ base + i + k) ∨
      (∃ k t, ps[k]? = some (.inp, t) ∧ ∃ kd, (⟨base + i + k, kd⟩ : Dep) ∈ L ∧
        ∃ d'' ∈ (pe (i + k)).path ++ (pe (i + k)).held, d' = ⟨d''.root, comp d''.kind kd⟩) := by
  intro ps
  induction ps with
  | nil => intro i L d' h; exact Or.inl ⟨h, fun k t hk => by simp at hk⟩
  | cons p ps ih =>
    intro i L d' h
    obtain ⟨pm, t⟩ := p
    have shift : ∀ k (q : PMode × Ty), ps[k]? = some q → ((pm, t) :: ps)[k + 1]? = some q := by
      intro k q hk; simpa using hk
    have liftOr : (d' ∈ L ∧ ∀ k t, ps[k]? = some (.inp, t) → d'.root ≠ base + (i + 1) + k) ∨
        (∃ k t, ps[k]? = some (.inp, t) ∧ ∃ kd, (⟨base + (i + 1) + k, kd⟩ : Dep) ∈ L ∧
          ∃ d'' ∈ (pe (i + 1 + k)).path ++ (pe (i + 1 + k)).held, d' = ⟨d''.root, comp d''.kind kd⟩) →
        (d'.root ≠ base + i ∨ pm ≠ .inp) →
        (d' ∈ L ∧ ∀ k t', ((pm, t) :: ps)[k]? = some (.inp, t') → d'.root ≠ base + i + k) ∨
        (∃ k t', ((pm, t) :: ps)[k]? = some (.inp, t') ∧ ∃ kd, (⟨base + i + k, kd⟩ : Dep) ∈ L ∧
          ∃ d'' ∈ (pe (i + k)).path ++ (pe (i + k)).held, d' = ⟨d''.root, comp d''.kind kd⟩) := by
      intro hh hne
      rcases hh with ⟨hL, hk⟩ | ⟨k, t', hk, kd, hkd, d'', hd'', rfl⟩
      · refine Or.inl ⟨hL, fun k t' hk' => ?_⟩
        cases k with
        | zero =>
          simp only [List.getElem?_cons_zero, Option.some.injEq, Prod.mk.injEq] at hk'
          rcases hne with hne | hne
          · simpa using hne
          · exact absurd hk'.1 hne
        | succ k =>
          have := hk k t' (by simpa using hk')
          rwa [show base + (i + 1) + k = base + i + (k + 1) by omega] at this
      · refine Or.inr ⟨k + 1, t', shift k _ hk, kd, ?_, d'', ?_, rfl⟩
        · rwa [show base + i + (k + 1) = base + (i + 1) + k by omega]
        · rwa [show i + (k + 1) = i + 1 + k by omega]
    cases pm with
    | inp =>
      simp only [rrL] at h
      rcases mem_reroot h with ⟨hin, hne⟩ | ⟨kd, d'', hin, hd'', rfl⟩
      · exact liftOr (ih (i + 1) L hin) (Or.inl hne)
      · rcases ih (i + 1) L hin with ⟨hL, _⟩ | ⟨k, t', _, kd', _, d3, hd3, he⟩
        · exact Or.inr ⟨0, t, by simp, kd, by simpa using hL, d'', by simpa using hd'', rfl⟩
        · exfalso
          have := hpe _ d3 hd3
          have he' : base + i = d3.root := congrArg Dep.root he
          rw [← he'] at this
          exact absurd this (Nat.not_lt.mpr (Nat.le_add_right _ _))
    | sink => exact liftOr (ih (i + 1) L h) (Or.inr (by simp))
    | inout b => exact liftOr (ih (i + 1) L h) (Or.inr (by simp))

theorem exits_at {base : Nat} {pe : Var → Entry} (hpe : ∀ j, ∀ d ∈ (pe j).path ++ (pe j).held, d.root < base) :
    ∀ (ps : List (PMode × Ty)) (i : Nat) (Δ : Ctx) {y : Var} {E : Entry}, Δ y = some E →
      (∀ k p, ps[k]? = some p → (∀ b, p.1 ≠ .inout b) → y ≠ base + i + k) →
      (∀ d ∈ E.vdeps, ∀ k t, ps[k]? = some (.sink, t) → d.root ≠ base + i + k) →
      exitsP ps base i pe Δ y = some (rrE ps base i pe E) := by
  intro ps
  induction ps with
  | nil => intro i Δ y E hE _ _; simp [exitsP, rrE, rrL, hE]
  | cons p ps ih =>
    intro i Δ y E hE hy hd
    obtain ⟨pm, t⟩ := p
    have hy' : ∀ k p, ps[k]? = some p → (∀ b, p.1 ≠ .inout b) → y ≠ base + (i + 1) + k := by
      intro k p hk hp
      have := hy (k + 1) p (by simpa using hk) hp
      rwa [show base + i + (k + 1) = base + (i + 1) + k by omega] at this
    have hd' : ∀ d ∈ E.vdeps, ∀ k t, ps[k]? = some (.sink, t) → d.root ≠ base + (i + 1) + k := by
      intro d hd0 k t hk
      have := hd d hd0 (k + 1) t (by simpa using hk)
      rwa [show base + i + (k + 1) = base + (i + 1) + k by omega] at this
    have hin := ih (i + 1) Δ hE hy' hd'
    cases pm with
    | inp =>
      have hne : y ≠ base + i := by have := hy 0 (.inp, t) (by simp) (fun b h => by cases h); simpa using this
      simp only [exitsP, exitRoot, upd_ne _ _ hne, hin, Option.map_some]
      rfl
    | sink =>
      have hne : y ≠ base + i := by have := hy 0 (.sink, t) (by simp) (fun b h => by cases h); simpa using this
      simp only [exitsP, A2.exitScope, upd_ne _ _ hne, A2.kill, hin, Option.map_some]
      congr 1
      unfold killE
      rw [ite_eq_right]
      · rfl
      · intro hh
        unfold hits at hh
        simp only [Bool.and_eq_true, List.any_eq_true, beq_iff_eq] at hh
        obtain ⟨_, d, hdv, hdr, _⟩ := hh
        have hsk := hd d
        have hL : ∀ L' : List Dep, (∀ d0 ∈ L', d0 ∈ E.vdeps) → d ∈ rrL ps base (i + 1) pe L' → False := by
          intro L' hL' hdL
          rcases mem_rrL hpe ps (i + 1) L' hdL with ⟨hin', _⟩ | ⟨k, t', _, kd, _, d'', hd'', rfl⟩
          · exact hd d (hL' d hin') 0 t (by simp) (by simpa using hdr)
          · have := hpe _ d'' hd''
            simp only at hdr
            rw [hdr] at this
            exact absurd this (Nat.not_lt.mpr (Nat.le_add_right _ _))
        unfold Entry.vdeps at hdv
        simp only [rrE] at hdv
        rcases List.mem_append.mp hdv with h1 | h1
        · have hm : (rrE ps base (i + 1) pe E).mode = E.mode := rfl
          cases ho : E.mode.ownSlot
          · simp only [ho, Bool.false_eq_true, ↓reduceIte] at h1
            exact hL E.path (fun d0 h0 => by simp [Entry.vdeps, ho, h0]) h1
          · simp [ho] at h1
        · exact hL E.held (fun d0 h0 => by simp [Entry.vdeps, h0]) h1
    | inout b =>
      simp only [exitsP]; rw [hin]; rfl

theorem exits_none {base : Nat} {pe : Var → Entry} :
    ∀ (ps : List (PMode × Ty)) (i : Nat) (Δ : Ctx) {y : Var}, Δ y = none →
      exitsP ps base i pe Δ y = none := by
  intro ps
  induction ps with
  | nil => intro i Δ y h; exact h
  | cons p ps ih =>
    intro i Δ y h
    obtain ⟨pm, t⟩ := p
    have hin := ih (i + 1) Δ h
    cases pm with
    | inp =>
      simp only [exitsP, exitRoot]
      by_cases hy : y = base + i
      · subst hy; simp
      · simp [upd_ne _ _ hy, hin]
    | sink =>
      simp only [exitsP, A2.exitScope]
      by_cases hy : y = base + i
      · subst hy; simp
      · simp [upd_ne _ _ hy, A2.kill, hin]
    | inout b => exact hin

theorem exits_slot {base : Nat} {pe : Var → Entry} :
    ∀ (ps : List (PMode × Ty)) (i : Nat) (Δ : Ctx) (k : Nat) (p : PMode × Ty), ps[k]? = some p →
      (∀ b, p.1 ≠ .inout b) → exitsP ps base i pe Δ (base + i + k) = none := by
  intro ps
  induction ps with
  | nil => intro i Δ k p hk; simp at hk
  | cons q ps ih =>
    intro i Δ k p hk hp
    obtain ⟨pm, t⟩ := q
    cases k with
    | zero =>
      simp only [List.getElem?_cons_zero, Option.some.injEq] at hk
      subst hk
      cases pm with
      | inp => simp [exitsP, exitRoot]
      | sink => simp [exitsP, A2.exitScope]
      | inout b => exact absurd rfl (hp b)
    | succ k =>
      have hin := ih (i + 1) Δ k p (by simpa using hk) hp
      rw [show base + (i + 1) + k = base + i + (k + 1) by omega] at hin
      cases pm with
      | inp =>
        simp only [exitsP, exitRoot]
        by_cases hy : base + i + (k + 1) = base + i
        · omega
        · simp [hin]
      | sink =>
        simp only [exitsP, A2.exitScope]
        by_cases hy : base + i + (k + 1) = base + i
        · omega
        · simp [A2.kill, hin]
      | inout b => exact hin

theorem rrL_id {base : Nat} {pe : Var → Entry} :
    ∀ (ps : List (PMode × Ty)) (i : Nat) (L : List Dep), (∀ d ∈ L, d.root < base + i) →
      rrL ps base i pe L = L := by
  intro ps
  induction ps with
  | nil => intro i L _; rfl
  | cons p ps ih =>
    intro i L hL
    obtain ⟨pm, t⟩ := p
    have hL' : ∀ d ∈ L, d.root < base + (i + 1) := fun d hd => Nat.lt_of_lt_of_le (hL d hd) (by omega)
    cases pm with
    | inp =>
      simp only [rrL, ih (i + 1) L hL']
      exact reroot_id (fun d hd he => absurd (he ▸ hL d hd) (Nat.lt_irrefl _))
    | sink => exact ih (i + 1) L hL'
    | inout b => exact ih (i + 1) L hL'

theorem rrL_nil {base i : Nat} {pe : Var → Entry} (ps : List (PMode × Ty)) : rrL ps base i pe [] = [] :=
  rrL_id ps i [] (fun d hd => by simp at hd)

theorem killE_dead {e : Eff} {hv : Bool} {x : Var} {E : Entry} (h : E.live = false) : killE e hv x E = E := by
  unfold killE; split
  · cases E; simp_all
  · rfl

theorem killE_nohit {e : Eff} {hv : Bool} {x : Var} {E : Entry} (h : ∀ d ∈ E.vdeps, d.root ≠ x) :
    killE e hv x E = E := by
  unfold killE; rw [ite_eq_right]
  intro hh; unfold hits at hh
  simp only [Bool.and_eq_true, List.any_eq_true, beq_iff_eq] at hh
  obtain ⟨_, d, hd, hr, _⟩ := hh
  exact h d hd hr

/-! ### The callee's starting context, as the caller sees it -/

theorem sigCtx_of {fn : Fn} {v : Nat} {p : PMode × Ty} (hp : fn.params[v]? = some p) :
    sigCtx fn v = some (paramE fn.params p) := by
  have hv : v < fn.params.length := (List.getElem?_eq_some_iff.mp hp).1
  simp [sigCtx, hv, (List.getElem?_eq_some_iff.mp hp).2]

theorem sigCtx_res (fn : Fn) : sigCtx fn fn.params.length = some ⟨fn.resTy, resMode fn, false, [], [], false⟩ := by
  simp [sigCtx]

theorem sigCtx_none {fn : Fn} {v : Nat} (hv : fn.params.length < v) : sigCtx fn v = none := by
  simp [sigCtx, show ¬ v < fn.params.length by omega, show v ≠ fn.params.length by omega]

/-- A symbolic name's target in the callee's own context: an `inout`
    parameter that holds no views, so holds nothing. -/
theorem sigCtx_sym {fn : Fn} {w : Var} {b : Eff} {t : Ty} (hp : fn.params[w]? = some (.inout b, t))
    (hhv : t.holdsView = false) : sigCtx fn w = some ⟨t, .inout b, true, [], [], false⟩ := by
  rw [sigCtx_of hp]
  have hf : t.hasFn = false := by
    cases h : t.hasFn
    · rfl
    · rw [hasFn_holdsView h] at hhv; cases hhv
  simp [paramE, hf]

/-- Every parameter's symbolic names (if any) are what `symNames` says. -/
theorem paramE_vdeps (ps : List (PMode × Ty)) (p : PMode × Ty) :
    (paramE ps p).vdeps = if p.2.hasFn then symNames ps else [] := by
  obtain ⟨pm, t⟩ := p
  cases pm <;> simp [paramE, Entry.vdeps, Mode.ownSlot]

/-- The callee's symbolic names are valid in its own context: an `inout`
    parameter that holds no views and is not replaced owns its slot, holds
    nothing and allows its own bound. -/
theorem sigCtx_names (fn : Fn) : NameWF (sigCtx fn) := by
  intro v E hv _ _ d hd b t hk
  unfold sigCtx at hv
  split at hv
  · simp only [Option.some.injEq] at hv; subst hv
    rw [paramE_vdeps] at hd
    split at hd
    · obtain ⟨w, b', t'', rfl, hp, hhv, _, hbr⟩ := mem_symNames' hd
      simp only [Kind.name.injEq] at hk
      obtain ⟨hb1, ht1⟩ := hk
      subst hb1 ht1
      exact ⟨⟨t'', .inout b', true, [], [], false⟩, sigCtx_sym hp hhv, rfl, rfl, rfl, rfl,
        Or.inr ⟨hbr, Or.inr ⟨b', rfl, Nat.le_refl _⟩⟩, hhv⟩
    · cases hd
  · split at hv
    · simp only [Option.some.injEq] at hv; subst hv; simp [Entry.vdeps] at hd
    · cases hv

theorem sigCtx_wf (fn : Fn) : CtxWF (sigCtx fn) := by
  intro v E hv _ _ r hr
  unfold sigCtx at hv
  split at hv
  · rename_i h
    simp only [Option.some.injEq] at hv; subst hv
    rw [paramE_vdeps] at hr
    obtain ⟨d, hd, rfl⟩ := List.mem_map.mp hr
    split at hd
    · obtain ⟨w, b, t', rfl, hp, _⟩ := mem_symNames' hd
      exact ⟨_, sigCtx_of hp, rfl⟩
    · cases hd
  · split at hv
    · simp only [Option.some.injEq] at hv; subst hv; simp [roots, Entry.vdeps] at hr
    · cases hv

namespace CallH
variable {P : Prog} {Γ : Ctx} {F : List Var} {x : Var} {fn : Fn} {args : List Var} {base : Nat}

theorem sig_abs (h : CallH P Γ F x fn args base) : (callS Γ F fn args base x).AbsOK (sigCtx fn) := by
  obtain ⟨_, _, _, _, _, hpar, _⟩ := h.fnok
  refine ⟨fun v E hv hm => ?_, fun v E b hv hm => ?_, fun v bh hb => ?_⟩
  · unfold sigCtx at hv
    split at hv
    · rename_i hvl
      simp only [Option.some.injEq] at hv; subst hv
      have hget : fn.params[v]? = some fn.params[v] := List.getElem?_eq_getElem hvl
      obtain ⟨Ea, hEa, hl, hok, _⟩ := h.arg v hvl
      generalize hp : fn.params[v] = p at hget hok hm
      obtain ⟨pm, t⟩ := p
      cases pm with
      | inp =>
        have hae : argE Γ (args.getD v 0) = Ea := by unfold argE; rw [hEa]; rfl
        simp only [paramOK] at hok
        refine ⟨?_, rfl, rfl⟩
        show t = (callPe Γ fn.params args v).ty
        unfold callPe; rw [hget]; simp only [hae]
        split
        · rename_i hi; rw [← hok, hi]
        · exact hok.symm
      | sink => simp [paramE] at hm
      | inout b => simp [paramE] at hm
    · split at hv
      · simp only [Option.some.injEq] at hv; subst hv
        exact absurd hm (resMode_ne' fn)
      · cases hv
  · unfold sigCtx at hv
    split at hv
    · rename_i hvl
      simp only [Option.some.injEq] at hv; subst hv
      have hget : fn.params[v]? = some fn.params[v] := List.getElem?_eq_getElem hvl
      have hmem : fn.params[v] ∈ fn.params := List.getElem_mem hvl
      generalize hp : fn.params[v] = p at hget hm hmem
      obtain ⟨pm, t⟩ := p
      cases pm with
      | inout b' =>
        simp only [paramE, Mode.inout.injEq] at hm; subst hm
        obtain ⟨_, _, hvec⟩ := hpar _ hmem
        exact ⟨hvec b' rfl, by simp [callS, bndOf, hget, paramE]⟩
      | inp => simp [paramE] at hm
      | sink => simp [paramE] at hm
    · split at hv
      · simp only [Option.some.injEq] at hv; subst hv
        exact absurd hm (resMode_inout fn b)
      · cases hv
  · simp only [callS, bndOf] at hb
    split at hb
    · rename_i b t hget
      simp only [Option.some.injEq] at hb; subst hb
      refine ⟨_, sigCtx_of hget, rfl, by simp [callS, paramE, hget], fun hfx => ⟨rfl, ?_⟩⟩
      -- fixed: it holds no views, so no closure, so no symbolic names
      rcases hfx with hfx | ⟨_, _, _, hhv⟩
      · simp [paramE] at hfx
      · simp only [paramE] at hhv
        have hf : t.hasFn = false := by
          cases h' : t.hasFn
          · rfl
          · rw [hasFn_holdsView h'] at hhv; cases hhv
        simp [paramE, hf]
    · cases hb

theorem x_notRen (h : CallH P Γ F x fn args base) (v : Nat) : callRen fn.params args base v ≠ x := by
  intro hv
  obtain ⟨b, t, hvp, hav⟩ := h.ren_dom hv h.xlt
  obtain ⟨Ea, hEa, _⟩ := h.arg v (lt_of_get hvp)
  rw [hav, h.fresh] at hEa; cases hEa

theorem canon_x (h : CallH P Γ F x fn args base) (Γa : Ctx) :
    (callS Γ F fn args base x).canon Γa x = some (callX fn) := by
  rw [RSetup.canon_frame Γa (fun v => h.x_notRen v)]
  simp only [callS]
  rw [ite_eq_right (fun ⟨v, hv⟩ => h.x_notRen v hv)]
  simp [setE, Entry.clean, callX]

theorem ren_res (fn : Fn) (args : List Var) (base : Nat) :
    callRen fn.params args base fn.params.length = base + fn.params.length := by
  unfold callRen; simp

theorem pe_lt (h : CallH P Γ F x fn args base) (j : Nat) :
    ∀ d ∈ (callPe Γ fn.params args j).path ++ (callPe Γ fn.params args j).held, d.root < base := by
  intro d hd
  unfold callPe at hd
  split at hd
  · rename_i t hj
    split at hd
    · simp at hd
    · rename_i hn
      have hjl := lt_of_get hj
      obtain ⟨Ea, hEa, hae⟩ := h.argE_eq hjl
      obtain ⟨_, h1, hl, _⟩ := h.arg j hjl
      rw [hEa] at h1; cases h1
      simp only at hd
      rw [hae] at hd hn
      rcases List.mem_append.mp hd with hd | hd
      · rcases derive_roots_cases (List.mem_map_of_mem (f := Dep.root) (typedDeps_sub _ _ hd)) with
          ⟨hr, _⟩ | ⟨_, hrv⟩
        · rw [hr]; exact h.argLt hjl
        · obtain ⟨Er, hEr, _⟩ := h.wf _ Ea hEa hl (Or.inl hn) _ hrv
          exact h.domlt _ _ hEr
      · obtain ⟨Er, hEr, _⟩ := h.wf _ Ea hEa hl (Or.inl hn) _
          (held_vdeps (List.mem_map_of_mem (typedDeps_sub _ _ hd)))
        exact h.domlt _ _ hEr
  · simp at hd

theorem frame_lt (h : CallH P Γ F x fn args base) {r : Var} {E : Entry}
    (hr : (callS Γ F fn args base x).Φ r = some E) : r < base := by
  obtain ⟨_, E1, h1, _⟩ := h.frame_some hr
  by_cases hrx : r = x
  · rw [hrx]; exact h.xlt
  · simp only [setE, upd_ne _ _ hrx] at h1; exact h.post_lt h1

theorem notRen_z (_h : CallH P Γ F x fn args base) {r : Var} (hout : ∀ w, callRen fn.params args base w ≠ r)
    (hlt : r < base) : r ∈ zOf fn args base := by
  simp only [zOf, List.mem_filter, List.mem_range, Bool.not_eq_eq_eq_not, Bool.not_true,
    List.contains_eq_mem, decide_eq_false_iff_not]
  refine ⟨hlt, fun hm => ?_⟩
  unfold inoutArgs at hm
  obtain ⟨w, hw, rfl⟩ := List.mem_map.mp hm
  obtain ⟨hwr, hwi⟩ := List.mem_filter.mp hw
  split at hwi
  · rename_i b t hwp
    exact hout w (by unfold callRen; rw [hwp])
  · cases hwi

/-- What an `in` parameter's entry borrows or reads by name is lent out for
    the call: no closure handed to it may change it (§2.11). -/
theorem pe_Fc (h : CallH P Γ F x fn args base) (j : Nat) :
    Anchored (callPe Γ fn.params args j) (F ++ zN Γ fn args base) := by
  intro d hd hb
  -- a reader is of the frame: a symbolic name's image changes its binding
  have hfr : (∀ w, callRen fn.params args base w ≠ d.root) ∧
      ∃ Er, (callS Γ F fn args base x).Φ d.root = some Er ∧ Er.mode.isRoot = true := by
    rcases RSetup.pe_dep h.sOK hd with hfr | ⟨hs, _⟩
    · exact hfr
    · obtain ⟨_, b, _, rfl, _, _, hbn, _⟩ := RSetup.sym_ren h.sOK hs
      exact absurd hb hbn
  obtain ⟨hout, Er, hEr, _⟩ := hfr
  refine List.mem_append_right _ (List.mem_filter.mpr ⟨h.notRen_z hout (h.frame_lt hEr), ?_⟩)
  have hnot : d.root ∉ roots (mutNames Γ args) := by
    intro hm
    obtain ⟨dm, hdm, hr⟩ := List.mem_map.mp hm
    obtain ⟨_, _, _, hna, hoth⟩ := h.nfree dm hdm
    obtain ⟨Ea, hvp, hEa, _, hni, hc, _⟩ := h.pe_vdeps j hd
    have hmem : args.getD j 0 ∈ args := by simp [List.getD, show j < args.length from h.len ▸ hvp]
    have hae' : argE Γ (args.getD j 0) = Ea := by unfold argE; rw [hEa]; rfl
    rcases hc with ⟨he, _, _⟩ | hdv
    · rcases hna with hna | ⟨i, t, hai, hpi⟩
      · exact hna (by rw [hr, he]; exact hmem)
      · -- `dm` changes an `inout` argument, which the callee can name
        have hai' : args.getD i 0 = dm.root := by simp [List.getD_eq_getElem?_getD, hai]
        exact hout i (by simp only [callRen, hpi]; rw [hai', hr, he])
    · have := hoth _ hmem (Or.inl (by rw [hae']; exact hni)) d (by rw [hae']; exact hdv) hr.symm
      rw [hb] at this
      exact (by simpa using (List.mem_filter.mp hdm).2 : dm.kind.bound ≠ .none) this.symm
  simpa using hnot

theorem wrapCond (h : CallH P Γ F x fn args base) :
    ∀ k p, fn.params[k]? = some p →
      WrapCond ((callS Γ F fn args base x).canon (sigCtx fn)) (F ++ zN Γ fn args base) base
        (callPe Γ fn.params args) (0 + k) p := by
  intro k p hk
  rw [Nat.zero_add]
  obtain ⟨pm, t⟩ := p
  have hρ : (∀ b' t', (pm, t) ≠ (.inout b', t')) → callRen fn.params args base k = base + k := by
    intro hne
    unfold callRen; rw [hk]
    cases pm with
    | inout b => exact absurd rfl (hne b t)
    | _ => rfl
  have hc : (∀ b' t', (pm, t) ≠ (.inout b', t')) →
      (callS Γ F fn args base x).canon (sigCtx fn) (base + k) =
        some ((callS Γ F fn args base x).liftE k (paramE fn.params (pm, t))) := by
    intro hne
    rw [← hρ hne]
    show (callS Γ F fn args base x).canon (sigCtx fn) ((callS Γ F fn args base x).ρ k) = _
    rw [RSetup.canon_ρ h.sOK, sigCtx_of hk]; rfl
  have hF : (∀ b' t', (pm, t) ≠ (.inout b', t')) → base + k ∉ F ++ zN Γ fn args base := by
    intro hne
    have := h.sOK.Fcout k
    simp only [callS] at this
    rwa [hρ hne] at this
  cases pm with
  | inp =>
    have hne : ∀ b' t', (PMode.inp, t) ≠ (.inout b', t') := fun _ _ h => by cases h
    refine ⟨_, hc hne, ?_, ?_, ?_, hF hne, ?_⟩
    · simp [RSetup.liftE, paramE, callS]; exact h.sOK.pe_rb k
    · simp [RSetup.liftE, paramE]
    · intro d hd hb
      have : ((callS Γ F fn args base x).liftE k (paramE fn.params (.inp, t))).vdeps =
          (callPe Γ fn.params args k).vdeps := by simp [RSetup.liftE, paramE, Entry.vdeps, callS]
      rw [this] at hd
      exact h.pe_Fc k d hd hb
    · simp [RSetup.liftE, paramE, callS]
  | sink =>
    have hne : ∀ b' t', (PMode.sink, t) ≠ (.inout b', t') := fun _ _ h => by cases h
    exact ⟨⟨_, hc hne, by simp [RSetup.liftE, paramE, liftMode]⟩, hF hne⟩
  | inout b => trivial

/-- The inside of the call is well-typed, given what its parameters' exits
    leave (`hfin`). -/
theorem pe_vd (j : Nat) : (callPe Γ fn.params args j).vdeps =
    (callPe Γ fn.params args j).path ++ (callPe Γ fn.params args j).held := by
  have hm : (callPe Γ fn.params args j).mode = .rootb := by
    unfold callPe; split
    · split <;> rfl
    · rfl
  unfold Entry.vdeps; rw [hm]; rfl

/-- What an `in` parameter depends on lies in the caller's context. -/
theorem pe_q (h : CallH P Γ F x fn args base) (j : Nat) :
    ∀ d ∈ (callPe Γ fn.params args j).path ++ (callPe Γ fn.params args j).held,
      d.root < base ∧ (Γ d.root).isSome := by
  intro d hd
  refine ⟨h.pe_lt j d hd, ?_⟩
  obtain ⟨Ea, _, hEa, hl, hni, hc, _⟩ := h.pe_vdeps j (by rw [pe_vd]; exact hd)
  rcases hc with ⟨he, _, _⟩ | hdv
  · rw [he, hEa]; rfl
  · obtain ⟨Er, hEr, _⟩ := h.wf _ Ea hEa hl (Or.inl hni) d.root (List.mem_map_of_mem hdv)
    rw [hEr]; rfl

/-- Every borrowed parameter where the call places the callee depends on
    the caller's context only. -/
theorem canon_rbq (h : CallH P Γ F x fn args base) (Δa : Ctx) :
    RbQ (fun r => r < base ∧ (Γ r).isSome) ((callS Γ F fn args base x).canon Δa) := by
  intro p E hp hm d hd
  rcases RSetup.canon_cases h.sOK Δa p with ⟨v, rfl, hc⟩ | ⟨_, hc⟩
  · rw [hc] at hp
    cases hE : Δa v with
    | none => rw [hE] at hp; cases hp
    | some E0 =>
      rw [hE] at hp; simp only [Option.map_some, Option.some.injEq] at hp; subst hp
      have hrb : E0.mode = .rootb := (RSetup.liftE_rootb h.sOK).mp hm
      have hvd : ((callS Γ F fn args base x).liftE v E0).vdeps = (callPe Γ fn.params args v).vdeps := by
        simp [RSetup.liftE, hrb, Entry.vdeps, callS]
      rw [hvd, pe_vd] at hd
      exact h.pe_q v d hd
  · rw [hc] at hp
    have hl := h.sOK.Φrb p E hp hm
    obtain ⟨E0, h0, hl0, _, hm0, hvd⟩ := h.frame_src hp hl
    rw [(hvd (Or.inr hm)).1] at hd
    obtain ⟨Er, hEr, _⟩ := h.wf p E0 h0 hl0 (Or.inr (by rw [← hm0]; exact hm)) d.root
      (List.mem_map_of_mem hd)
    exact ⟨h.domlt _ _ hEr, by rw [hEr]; rfl⟩

theorem typedIn_of (h : CallH P Γ F x fn args base)
    {Δa : Ctx} (habΔ : (callS Γ F fn args base x).AbsOK Δa)
    (hbody : StmtT P ((callS Γ F fn args base x).canon (sigCtx fn)) (F ++ zN Γ fn args base)
      (fn.body.rename (callRen fn.params args base)) ((callS Γ F fn args base x).canon Δa))
    {Er' : Entry}
    (hr : exitsP fn.params base 0 (callPe Γ fn.params args) ((callS Γ F fn args base x).canon Δa)
      (base + fn.params.length) = some Er')
    (hrl : Er'.live = true) (hrm : Er'.mode = resMode fn) (hrt : Er'.ty = fn.resTy)
    (hxr : x ∉ roots Er'.vdeps)
    (hfin : ∀ Γ3, (Γ3 = setE (A2.kill .replace false x
          (if fn.resOwn then setE (A2.kill .replace false (base + fn.params.length)
              (exitsP fn.params base 0 (callPe Γ fn.params args) ((callS Γ F fn args base x).canon Δa)))
            (base + fn.params.length) { Er' with live := false, dtor := false }
           else exitsP fn.params base 0 (callPe Γ fn.params args) ((callS Γ F fn args base x).canon Δa)))
          x (if fn.resOwn then { (⟨Er'.ty, .own, true, [], Er'.held, false⟩ : Entry) with mode := resMode fn }
             else { Er' with mode := resMode fn })) →
      Weaker (exitScope (base + fn.params.length) Γ3) (setE (callPost Γ fn args) x (callRes Γ fn args))) :
    StmtT P ((callS Γ F fn args base x).canon (sigCtx fn)) F (callIn fn args base x)
      (setE (callPost Γ fn args) x (callRes Γ fn args)) := by
  have hpw : ∀ j, ∀ d ∈ (callPe Γ fn.params args j).path ++ (callPe Γ fn.params args j).held,
      d.kind.bound ≠ .none →
      ∃ Er, (callS Γ F fn args base x).canon Δa d.root = some Er ∧ Er.mode.isRoot = true := by
    intro j d hd hb
    have hdv : d ∈ (callPe Γ fn.params args j).vdeps := by rw [pe_vd]; exact hd
    rcases h.sOK.pe_names j d hdv (bound_isName hb) with hN | ⟨hs, _⟩
    · -- a binding of the frame that allows the change
      obtain ⟨_, _, ⟨Er, hEr, hcan, _⟩, _⟩ := h.sOK.N_mut d hN hb
      refine ⟨Er, by rw [RSetup.canon_frame _ (h.sOK.N_out d hN).1]; exact hEr, ?_⟩
      rcases hcan with hm | ⟨_, hm, _⟩ <;> rw [hm] <;> rfl
    · -- an `inout` argument: the parameter's binding at the end, lifted
      obtain ⟨w, b, t, rfl, hbw, _, _, _⟩ := RSetup.sym_ren h.sOK hs
      obtain ⟨Ew, hEw, hm, _⟩ := habΔ.2.2 w (b, false) hbw
      refine ⟨_, by rw [RSetup.canon_ρ h.sOK, hEw]; rfl, ?_⟩
      rw [RSetup.liftE_mode _ (by rw [hm]; simp), hm]; rfl
  have hwrap := wrap_typed (pe := callPe Γ fn.params args) (base := base) hbody h.pe_lt hpw
    (fun p E hp hm d hd => (h.canon_rbq Δa p E hp hm d hd).1) fn.params 0 h.wrapCond
  have hfz := StmtT.frozen (z := zOf fn args base) hwrap zN_sub
  have hQb := exitsP_rblt (base := base) (Q := fun r => r < base ∧ (Γ r).isSome) h.pe_q fn.params 0 _
    (h.canon_rbq Δa)
  generalize hΓb : exitsP fn.params base 0 (callPe Γ fn.params args) ((callS Γ F fn args base x).canon Δa) = Γb
    at hfz hr hfin hQb
  have hbx : Γb x = some (callX fn) := by
    rw [← hΓb]
    have := exits_at (pe := callPe Γ fn.params args) (base := base) h.pe_lt fn.params 0
      ((callS Γ F fn args base x).canon Δa) (h.canon_x Δa)
      (fun k p hkp _ he => by have := vlt h.xlt; have := veq he; omega)
      (fun d hd => by rw [callX_vdeps] at hd; cases hd)
    rw [this]; simp [rrE, rrL_nil, callX]
  have hrF : base + fn.params.length ∉ F := fun hm => by have := vlt (h.Flt _ hm); omega
  have hxr' : x ≠ base + fn.params.length := by
    intro he; have := vlt h.xlt; have := veq he; omega
  have hseq : StmtT P ((callS Γ F fn args base x).canon (sigCtx fn)) F
      (.seq (.frozen (zOf fn args base) (wrapParams fn.params base 0 (fn.body.rename (callRen fn.params args base))))
        (.assign x (.var (base + fn.params.length))))
      (setE (A2.kill .replace false x
          (if fn.resOwn then setE (A2.kill .replace false (base + fn.params.length) Γb)
            (base + fn.params.length) { Er' with live := false, dtor := false } else Γb))
        x (if fn.resOwn then { (⟨Er'.ty, .own, true, [], Er'.held, false⟩ : Entry) with mode := resMode fn }
           else { Er' with mode := resMode fn })) := by
    cases ho : fn.resOwn with
    | true =>
      have hm : Er'.mode = .own := by rw [hrm]; simp [resMode, ho]
      have hrhs := RhsT.moveOwn (F := F) hr hrl hm hrF
        (hQb.noPin fun hq => absurd hq.1 (Nat.not_lt.mpr (Nat.le_add_right _ _)))
      have hX : (callX fn).mode = .own := by simp [callX, resMode, ho]
      refine StmtT.seq rfl hfz (StmtT.assign hbx h.xF (Or.inl ⟨hX, rfl⟩) hrhs
        (by simp [callX, hrt]) ?_ (by simp [setE, upd_ne _ _ hxr', A2.kill, hbx])
        (hQb.noPin fun hq => by simp [h.fresh] at hq))
      have hv : (⟨Er'.ty, .own, true, [], Er'.held, false⟩ : Entry).vdeps = Er'.vdeps := by
        simp [Entry.vdeps, hm, Mode.ownSlot]
      rw [hv]; exact hxr
    | false =>
      have hm : Er'.mode = .bor := by rw [hrm]; simp [resMode, ho]
      have hrhs := RhsT.copyBor (F := F) hr hrl hm
      have hX : (callX fn).mode = .bor := by simp [callX, resMode, ho]
      exact StmtT.seq rfl hfz (StmtT.assign hbx h.xF (Or.inr (Or.inr ⟨hX, hm⟩)) hrhs
        (by simp [callX, hrt]) hxr (by simp [hbx]) (hQb.noPin fun hq => by simp [h.fresh] at hq))
  have hscr := StmtT.scope (⟨_, by
      rw [show base + fn.params.length = callRen fn.params args base fn.params.length from
        (ren_res fn args base).symm]
      show (callS Γ F fn args base x).canon (sigCtx fn) ((callS Γ F fn args base x).ρ _) = _
      rw [RSetup.canon_ρ h.sOK, sigCtx_res]; rfl, by
      rw [RSetup.liftE_mode _ (resMode_ne' fn), RSetup.liftMode_resMode]; exact resMode_ne' fn⟩) hrF hseq
    (RbQ.noPin (Q := fun r => r < base ∧ (Γ r).isSome) ?_
      fun hq => absurd hq.1 (Nat.not_lt.mpr (Nat.le_add_right _ _)))
  · exact StmtT.weakenOut (RSetup.canon_wf h.sOK h.sig_abs (sigCtx_wf fn))
      (RSetup.canon_names h.sOK h.sig_abs (sigCtx_names fn)) hscr (Or.inr (hfin _ rfl))
  · refine RbQ.setE (RbQ.kill ?_ _ _ _) ?_
    · split
      · exact (hQb.kill _ _ _).setE (show Er'.mode ≠ .rootb by rw [hrm]; exact resMode_ne' fn)
      · exact hQb
    · split <;> exact resMode_ne' fn

end CallH

theorem comp_self_r (a : Kind) : comp a .self = a := by cases a <;> rfl
theorem comp_rootKind (t : Ty) (k : Kind) : comp (rootKind t .self) k = rootKind t k := by
  cases t <;> cases k <;> rfl

theorem derive_comp {y : Var} {E : Entry} {d : Dep} (hd : d ∈ derive y E .self) (k : Kind) :
    (⟨d.root, comp d.kind k⟩ : Dep) ∈ derive y E k := by
  unfold derive at hd ⊢
  split
  · rename_i hr; simp only [hr, ↓reduceIte, List.mem_singleton] at hd; subst hd
    simp [comp_rootKind]
  · rename_i hr; simp only [hr, Bool.false_eq_true, ↓reduceIte, List.mem_map] at hd
    obtain ⟨d0, hd0, rfl⟩ := hd
    exact List.mem_map.mpr ⟨d0, hd0, by simp [comp_self_r]⟩

namespace CallH
variable {P : Prog} {Γ : Ctx} {F : List Var} {x : Var} {fn : Fn} {args : List Var} {base : Nat}

theorem pe_dom (h : CallH P Γ F x fn args base) (j : Nat) :
    ∀ d ∈ (callPe Γ fn.params args j).path ++ (callPe Γ fn.params args j).held, (Γ d.root).isSome := by
  intro d hd
  unfold callPe at hd
  split at hd
  · rename_i t hj
    split at hd
    · simp at hd
    · rename_i hn
      have hjl := lt_of_get hj
      obtain ⟨Ea, hEa, hae⟩ := h.argE_eq hjl
      obtain ⟨_, h1, hl, _⟩ := h.arg j hjl
      rw [hEa] at h1; cases h1
      simp only at hd
      rw [hae] at hd hn
      rcases List.mem_append.mp hd with hd | hd
      · rcases derive_roots_cases (List.mem_map_of_mem (f := Dep.root) (typedDeps_sub _ _ hd)) with
          ⟨hr, _⟩ | ⟨_, hrv⟩
        · rw [hr, hEa]; rfl
        · obtain ⟨Er, hEr, _⟩ := h.wf _ Ea hEa hl (Or.inl hn) _ hrv
          rw [hEr]; rfl
      · obtain ⟨Er, hEr, _⟩ := h.wf _ Ea hEa hl (Or.inl hn) _
          (held_vdeps (List.mem_map_of_mem (typedDeps_sub _ _ hd)))
        rw [hEr]; rfl
  · simp at hd

/-- A lendable parameter `j`, as the exits leave it, is what the summary
    says the call lends from argument `j`. -/
theorem rr_sub (h : CallH P Γ F x fn args base) {L T : List Dep}
    (hL : ∀ d ∈ L, ((Γ d.root).isSome ∧ d ∈ T) ∨
      ∃ j kd, d = ⟨callRen fn.params args base j, kd⟩ ∧ lendable fn j ∧ argDeps Γ args (j, kd) ⊆ T ∧
        kd.isName = false ∧ kindFits fn j kd)
    (hR : heldOfArgs Γ args ⊆ T) :
    ∀ d' ∈ rrL fn.params base 0 (callPe Γ fn.params args) L, (Γ d'.root).isSome ∧ d' ∈ T := by
  intro d' hd'
  rcases mem_rrL h.pe_lt fn.params 0 L hd' with ⟨hin, hne⟩ | ⟨k, t, hk, kd0, hkL, d'', hd'', rfl⟩
  · rcases hL d' hin with h1 | ⟨j, kd, rfl, ⟨hjl, hjm⟩, hsub, _, hfit⟩
    · exact h1
    · rcases hjm with hjm | ⟨b, hjm⟩
      · exfalso
        have hget : fn.params[j]? = some (.inp, fn.params[j].2) := by
          rw [List.getElem?_eq_getElem hjl, ← hjm]
        have hρ : callRen fn.params args base j = base + j := by unfold callRen; rw [hget]
        exact hne j fn.params[j].2 hget (by simp [hρ])
      · have hget : fn.params[j]? = some (.inout b, fn.params[j].2) := by
          rw [List.getElem?_eq_getElem hjl, ← hjm]
        have hρ : callRen fn.params args base j = args.getD j 0 := by unfold callRen; rw [hget]
        obtain ⟨Ea, hEa, hae⟩ := h.argE_eq hjl
        obtain ⟨_, h1, _, hok, _⟩ := h.arg j hjl
        rw [hEa] at h1; cases h1
        simp only [hjm, paramOK] at hok
        obtain ⟨hty, hcan, hown'⟩ := hok
        have hown : Ea.mode = .own := by
          rcases hcan with hm | ⟨b', hm, _⟩
          · exact hm
          · exact absurd hm (h.noInout _ Ea b' hEa)
        have hni : Ea.ty ≠ .int := by
          intro hi; rw [hty] at hi; rw [hi] at hown'; cases hown'
        have hfk : rootKind Ea.ty kd = kd := by rw [hty]; exact hfit b _ hget
        refine ⟨by show (Γ (callRen fn.params args base j)).isSome = true; rw [hρ, hEa]; rfl, hsub ?_⟩
        unfold argDeps
        rw [hae, ite_eq_right hni]
        simp [derive, hown, Mode.isRoot, hρ, hfk]
  · -- reached through the `in` parameter `k`
    have hkd : (⟨base + 0 + k, kd0⟩ : Dep) ∈ L := hkL
    rcases hL _ hkd with ⟨hdom, _⟩ | ⟨j, kd, he, _, hsub, hkn, _⟩
    · exfalso
      obtain ⟨E, hE⟩ := Option.isSome_iff_exists.mp hdom
      exact absurd (vlt (h.domlt _ E hE))
        (Nat.not_lt.mpr (Nat.le_trans (Nat.le_add_right base 0) (Nat.le_add_right _ k)))
    · have hjk : j = k := by
        have he1 : base + 0 + k = callRen fn.params args base j := congrArg Dep.root he
        rcases callRen_cases fn.params args base j with ⟨b, t', hjp, hr⟩ | ⟨_, hr⟩
        · rw [hr] at he1
          have hlt := h.argLt (lt_of_get hjp)
          rw [← he1] at hlt
          exact absurd hlt (Nat.not_lt.mpr (Nat.le_trans (Nat.le_add_right _ 0) (Nat.le_add_right _ k)))
        · rw [hr] at he1; simp only [Nat.add_zero, Nat.add_left_cancel_iff] at he1; exact he1.symm
      have hkd' : kd = kd0 := (congrArg Dep.kind he).symm
      subst hjk hkd'
      rw [Nat.zero_add] at hd''
      refine ⟨h.pe_dom j d'' hd'', ?_⟩
      simp only [callPe, hk] at hd''
      split at hd''
      · simp at hd''
      · rename_i hn
        rcases List.mem_append.mp hd'' with hd'' | hd''
        · apply hsub
          unfold argDeps
          rw [ite_eq_right hn]
          exact derive_comp (typedDeps_sub _ _ hd'') kd
        · replace hd'' := typedDeps_sub _ _ hd''
          apply hR
          unfold heldOfArgs
          have hmem : args.getD j 0 ∈ args := by
            have := lt_of_get hk
            simp [List.getD, show j < args.length from h.len ▸ this]
          cases hk' : d''.kind.isName with
          | false =>
            have hcn : (comp d''.kind kd).isName = false := by
              revert hk' hkn; generalize d''.kind = a; generalize kd = b
              cases a <;> cases b <;> simp [comp, Kind.isName]
            refine List.mem_append_left _ (RSetup.mem_allKinds_iff.mpr
              ⟨List.mem_flatMap.mpr ⟨args.getD j 0, hmem, ?_⟩, hcn⟩)
            rw [ite_eq_right hn]
            exact List.mem_map.mpr ⟨d'', List.mem_filter.mpr ⟨hd'', by simp [hk']⟩, rfl⟩
          | true =>
            have hcn : comp d''.kind kd = d''.kind := by
              revert hk'; generalize d''.kind = a; generalize kd = b
              cases a <;> cases b <;> simp [comp, Kind.isName]
            have he' : (⟨d''.root, comp d''.kind kd⟩ : Dep) = d'' := by rw [hcn]
            rw [he']
            refine List.mem_append_right _ (List.mem_flatMap.mpr ⟨args.getD j 0, hmem, ?_⟩)
            rw [ite_eq_right hn]
            exact List.mem_filter.mpr ⟨by unfold Entry.vdeps; exact List.mem_append_right _ hd'', hk'⟩

/-- A lifted list of the callee's dependencies on lendable parameters, as
    the exits leave it. -/
theorem lift_sub (h : CallH P Γ F x fn args base) {L0 T X : List Dep}
    (hL0 : ∀ d0 ∈ L0, lendable fn d0.root ∧ argDeps Γ args (d0.root, d0.kind) ⊆ T ∧ d0.kind.isName = false ∧
      kindFits fn d0.root d0.kind)
    (hR : heldOfArgs Γ args ⊆ T) (hX : X ⊆ (callS Γ F fn args base x).A) :
    ∀ d' ∈ rrL fn.params base 0 (callPe Γ fn.params args)
        (rds (callRen fn.params args base) L0 ++ X),
      (Γ d'.root).isSome ∧ d' ∈ T := by
  refine h.rr_sub (fun d hd => ?_) hR
  rcases List.mem_append.mp hd with hd | hd
  · obtain ⟨d0, hd0, rfl⟩ := RSetup.mem_rds.mp hd
    exact Or.inr ⟨d0.root, d0.kind, rfl, (hL0 d0 hd0).1, (hL0 d0 hd0).2.1, (hL0 d0 hd0).2.2.1,
      (hL0 d0 hd0).2.2.2⟩
  · rcases RSetup.mem_A.mp (hX hd) with hd | hd
    · obtain ⟨_, Er, hEr, _⟩ := h.R_facts (RSetup.mem_allKinds hd)
      exact Or.inl ⟨by rw [hEr]; rfl, hR (List.mem_append_left _ hd)⟩
    · obtain ⟨Er, hEr, _⟩ := h.argNames_rootE ((h.mem_N).mp hd).1
      exact Or.inl ⟨by rw [hEr]; rfl, hR (List.mem_append_right _ ((h.mem_N).mp hd).1)⟩

/-- No lifted dependency on a lendable parameter names a `sink` parameter's slot. -/
theorem lift_nosink (h : CallH P Γ F x fn args base) {v : Var} {E : Entry} (hrb : E.mode ≠ .rootb)
    (hE : ∀ d0 ∈ E.vdeps, lendable fn d0.root) :
    ∀ d ∈ ((callS Γ F fn args base x).liftE v E).vdeps, ∀ k t, fn.params[k]? = some (.sink, t) →
      d.root ≠ base + 0 + k := by
  intro d hd k t hk he
  rcases RSetup.liftE_vdeps_cases hrb hd with ⟨d0, hd0, rfl⟩ | ha
  · obtain ⟨hjl, hjm⟩ := hE d0 hd0
    simp only [Dep.ren, callS] at he
    rcases callRen_cases fn.params args base d0.root with ⟨b, t', hjp, hr⟩ | ⟨_, hr⟩
    · rw [hr] at he
      have hlt := h.argLt (lt_of_get hjp)
      rw [he] at hlt
      exact absurd hlt (Nat.not_lt.mpr (Nat.le_trans (Nat.le_add_right _ 0) (Nat.le_add_right _ k)))
    · rw [hr] at he
      simp only [Nat.add_zero, Nat.add_left_cancel_iff] at he
      subst he
      rw [List.getElem?_eq_getElem hjl] at hk
      simp only [Option.some.injEq] at hk
      rcases hjm with hjm | ⟨b, hjm⟩ <;> rw [hk] at hjm <;> cases hjm
  · have hEr' : ∃ Er, Γ d.root = some Er := by
      rcases RSetup.mem_A.mp ha with ha | ha
      · obtain ⟨_, Er, hEr, _⟩ := h.R_facts (RSetup.mem_allKinds ha); exact ⟨Er, hEr⟩
      · obtain ⟨Er, hEr, _⟩ := h.argNames_rootE ((h.mem_N).mp ha).1; exact ⟨Er, hEr⟩
    obtain ⟨Er, hEr⟩ := hEr'
    have hlt := vlt (h.domlt _ _ hEr)
    rw [he] at hlt
    exact absurd hlt (Nat.not_lt.mpr (Nat.le_trans (Nat.le_add_right _ 0) (Nat.le_add_right _ k)))

theorem liftE_eq (S : RSetup) {v : Var} {E : Entry} (hrb : E.mode ≠ .rootb) :
    S.liftE v E = ⟨E.ty, liftMode E.mode, E.live,
      rds S.ρ E.path ++ (if E.mode.ownSlot then [] else S.A),
      rds S.ρ E.held ++ ownHeld E.mode.ownSlot E.ty S.A, false⟩ := by
  simp [RSetup.liftE, hrb]

/-- The callee's result, where the exits leave it. -/
theorem res_at (h : CallH P Γ F x fn args base) {Δa : Ctx} {Er : Entry}
    (hEr : Δa fn.params.length = some Er) (hErm : Er.mode = resMode fn)
    (hErv : ∀ d0 ∈ Er.vdeps, lendable fn d0.root) :
    exitsP fn.params base 0 (callPe Γ fn.params args) ((callS Γ F fn args base x).canon Δa)
        (base + fn.params.length) =
      some (rrE fn.params base 0 (callPe Γ fn.params args) ((callS Γ F fn args base x).liftE fn.params.length Er)) := by
  have hrb : Er.mode ≠ .rootb := by rw [hErm]; exact resMode_ne' fn
  refine exits_at h.pe_lt fn.params 0 _ ?_ (fun k p hkp _ he => ?_) (h.lift_nosink hrb hErv)
  · rw [show base + fn.params.length = (callS Γ F fn args base x).ρ fn.params.length from
      (ren_res fn args base).symm, RSetup.canon_ρ h.sOK, hEr]; rfl
  · have hlt := lt_of_get hkp
    simp only [Nat.add_zero, Nat.add_left_cancel_iff] at he
    rw [← he] at hlt; exact Nat.lt_irrefl _ hlt

theorem res_props (h : CallH P Γ F x fn args base) {Er : Entry} (hErl : Er.live = true)
    (hErt : Er.ty = fn.resTy) (hErm : Er.mode = resMode fn)
    (hErp : ∀ d ∈ Er.path, (d.root, d.kind) ∈ fn.lends) (hErh : ∀ d ∈ Er.held, (d.root, d.kind) ∈ fn.rholds)
    (hEr0 : fn.resOwn = true → fn.resTy.holdsView = false → Er.held = []) :
    let Er' := rrE fn.params base 0 (callPe Γ fn.params args)
      ((callS Γ F fn args base x).liftE fn.params.length Er)
    Er'.live = true ∧ Er'.mode = resMode fn ∧ Er'.ty = fn.resTy ∧
    ((resMode fn).ownSlot = false → ∀ d ∈ Er'.path, (Γ d.root).isSome ∧ d ∈ (callRes Γ fn args).path) ∧
    (∀ d ∈ Er'.held, (Γ d.root).isSome ∧ d ∈ (callRes Γ fn args).held) := by
  obtain ⟨_, _, _, _, _, _, hlends, hrholds, _, hfits, _⟩ := h.fnok
  have hrb : Er.mode ≠ .rootb := by rw [hErm]; exact resMode_ne' fn
  have hl : ∀ jk ∈ fn.lends, argDeps Γ args jk ⊆ (callRes Γ fn args).path := fun jk hjk d hd =>
    List.mem_append_left _ (List.mem_flatMap.mpr ⟨jk, hjk, hd⟩)
  simp only [rrE, liftE_eq _ hrb, hErm, RSetup.liftMode_resMode]
  refine ⟨hErl, by first | rfl | trivial, hErt, fun ho => ?_, ?_⟩
  · simp only [ho, Bool.false_eq_true, ↓reduceIte]
    exact h.lift_sub (fun d0 hd0 => ⟨(hlends _ (hErp d0 hd0)).1, hl _ (hErp d0 hd0),
      (hlends _ (hErp d0 hd0)).2, hfits _ (List.mem_append_left _ (hErp d0 hd0))⟩)
      (fun d hd => List.mem_append_right _ hd) (List.Subset.refl _)
  · rw [RSetup.resMode_ownSlot, hErt]
    by_cases hc0 : (fn.resOwn && !fn.resTy.holdsView) = true
    · -- an owned result of a type that holds no views holds nothing
      simp only [Bool.and_eq_true, Bool.not_eq_eq_eq_not, Bool.not_true] at hc0
      rw [hEr0 hc0.1 hc0.2]
      simp [ownHeld, hc0.1, hc0.2, rds, rrL_nil]
    · have hT : (callRes Γ fn args).held = fn.rholds.flatMap (argDeps Γ args) ++ heldOfArgs Γ args := by
        simp only [callRes, ownHeld, hc0, Bool.false_eq_true, ↓reduceIte]
      have hX : ownHeld fn.resOwn fn.resTy (callS Γ F fn args base x).A = (callS Γ F fn args base x).A := by
        simp only [ownHeld, hc0, Bool.false_eq_true, ↓reduceIte]
      rw [hT, hX]
      exact h.lift_sub (fun d0 hd0 => ⟨(hrholds _ (hErh d0 hd0)).1,
        fun d hd => List.mem_append_left _ (List.mem_flatMap.mpr ⟨_, hErh d0 hd0, hd⟩),
        (hrholds _ (hErh d0 hd0)).2, hfits _ (List.mem_append_right _ (hErh d0 hd0))⟩)
        (fun d hd => List.mem_append_right _ hd) (List.Subset.refl _)

/-- An `inout` argument, where the exits leave it. -/
theorem inout_at (h : CallH P Γ F x fn args base) {Δa : Ctx} {i : Nat} {b : Eff} {t : Ty}
    (hip : fn.params[i]? = some (.inout b, t)) {Ei : Entry} (hEi : Δa i = some Ei) (hEim : Ei.mode = .inout b)
    (hEih : ∀ d ∈ Ei.held, (i, d.root, d.kind) ∈ fn.outHolds) :
    exitsP fn.params base 0 (callPe Γ fn.params args) ((callS Γ F fn args base x).canon Δa) (args.getD i 0) =
      some (rrE fn.params base 0 (callPe Γ fn.params args) ((callS Γ F fn args base x).liftE i Ei)) ∧
    ∀ d ∈ (rrE fn.params base 0 (callPe Γ fn.params args) ((callS Γ F fn args base x).liftE i Ei)).held,
      (Γ d.root).isSome ∧
      d ∈ (argE Γ (args.getD i 0)).held ++ outHeld Γ fn args i ++ heldOfArgs Γ args := by
  obtain ⟨_, _, _, _, _, _, _, _, houts, _, hofits, _⟩ := h.fnok
  have hrb : Ei.mode ≠ .rootb := by rw [hEim]; simp
  have hρ : callRen fn.params args base i = args.getD i 0 := by unfold callRen; rw [hip]
  have hil := lt_of_get hip
  have hvd : ∀ d0 ∈ Ei.vdeps, lendable fn d0.root := by
    intro d0 hd0
    have hh : d0 ∈ Ei.held := by
      unfold Entry.vdeps at hd0; rw [hEim] at hd0; simpa [Mode.ownSlot] using hd0
    exact (houts _ (hEih d0 hh)).1
  refine ⟨exits_at h.pe_lt fn.params 0 _ ?_ (fun k p hkp _ he => ?_) (h.lift_nosink hrb hvd), ?_⟩
  · rw [← hρ]; exact (RSetup.canon_ρ h.sOK _ i).trans (by rw [hEi]; rfl)
  · have hlt := h.argLt hil
    rw [he] at hlt
    exact absurd hlt (Nat.not_lt.mpr (Nat.le_trans (Nat.le_add_right _ 0) (Nat.le_add_right _ k)))
  · simp only [rrE, liftE_eq _ hrb]
    refine h.lift_sub (fun d0 hd0 => ⟨(houts _ (hEih d0 hd0)).1, fun d hd => ?_,
      (houts _ (hEih d0 hd0)).2, hofits _ (hEih d0 hd0)⟩)
      (fun d hd => List.mem_append_right _ hd) (ownHeld_sub _ _ _)
    refine List.mem_append_left _ (List.mem_append_right _ ?_)
    unfold outHeld
    exact List.mem_flatMap.mpr ⟨(i, d0.root, d0.kind), List.mem_filter.mpr ⟨hEih d0 hd0, by simp⟩, hd⟩

end CallH

namespace CallH
variable {P : Prog} {Γ : Ctx} {F : List Var} {x : Var} {fn : Fn} {args : List Var} {base : Nat}

/-- A frame binding, where the exits leave it. -/
theorem frame_at (h : CallH P Γ F x fn args base) {Δa : Ctx} {y : Var}
    (hy : ∀ v, callRen fn.params args base v ≠ y) (hyx : y ≠ x) {E1 : Entry}
    (h1 : callPost Γ fn args y = some E1) :
    exitsP fn.params base 0 (callPe Γ fn.params args) ((callS Γ F fn args base x).canon Δa) y =
      some (rrE fn.params base 0 (callPe Γ fn.params args) E1.clean) ∧
    (∀ d ∈ (rrE fn.params base 0 (callPe Γ fn.params args) E1.clean).vdeps, (Γ d.root).isSome) ∧
    EntryWeaker (rrE fn.params base 0 (callPe Γ fn.params args) E1.clean) E1 := by
  have hc : (callS Γ F fn args base x).canon Δa y = some E1.clean := by
    rw [RSetup.canon_frame _ hy, h.frame_of hy hyx, h1]; rfl
  have hylt := h.post_lt h1
  have hyk : ∀ k p, fn.params[k]? = some p → (∀ b, p.1 ≠ .inout b) → y ≠ base + 0 + k := by
    intro k p _ _ he
    rw [he] at hylt
    exact absurd hylt (Nat.not_lt.mpr (Nat.le_trans (Nat.le_add_right _ 0) (Nat.le_add_right _ k)))
  by_cases hcl : ¬ E1.fixed ∧ (E1.ty = .int ∨ E1.live = false)
  · have hce : E1.clean = { E1 with path := [], held := [] } := by unfold Entry.clean; rw [ite_eq_left hcl]
    have hrr : rrE fn.params base 0 (callPe Γ fn.params args) E1.clean = { E1 with path := [], held := [] } := by
      rw [hce]; simp [rrE, rrL_nil]
    have hv0 : ({ E1 with path := [], held := [] } : Entry).vdeps = [] := by
      unfold Entry.vdeps; cases E1.mode.ownSlot <;> rfl
    refine ⟨?_, ?_, ?_⟩
    · rw [exits_at h.pe_lt fn.params 0 _ hc hyk (fun d hd => by rw [hce, hv0] at hd; cases hd)]
    · rw [hrr, hv0]; intro d hd; cases hd
    · rw [hrr]
      exact ⟨rfl, rfl, fun hf => absurd hf hcl.1, fun hl => ⟨hl, fun _ => by simp, by simp⟩⟩
  · have hce : E1.clean = E1 := by unfold Entry.clean; rw [ite_eq_right hcl]
    have hl : E1.live = true := by
      by_cases hrb : E1.fixed
      · exact h.post_live_rootb h1 (by
          rcases hrb with hrb | ⟨b, hb, _⟩
          · exact hrb
          · obtain ⟨E0, h0, hm0, _⟩ := h.postdt.2 y E1 h1
            exact absurd (hm0 ▸ hb : E0.mode = .inout b) (h.noio y E0 b h0))
      · cases hlv : E1.live
        · exact absurd ⟨hrb, Or.inr hlv⟩ hcl
        · rfl
    have hn : E1.ty ≠ .int ∨ E1.mode = .rootb := by
      by_cases hrb : E1.mode = .rootb
      · exact Or.inr hrb
      · exact Or.inl fun ht => hcl ⟨fun hf => by
          rcases hf with hf | ⟨b, hb, _⟩
          · exact hrb hf
          · obtain ⟨E0, h0, hm0, _⟩ := h.postdt.2 y E1 h1
            exact absurd (hm0 ▸ hb : E0.mode = .inout b) (h.noio y E0 b h0), Or.inl ht⟩
    have hroots : ∀ d ∈ E1.vdeps, (Γ d.root).isSome ∧ d.root < base + 0 := by
      intro d hd
      obtain ⟨Er, hEr, _⟩ := h.postwf y E1 h1 hl hn d.root (List.mem_map_of_mem hd)
      refine ⟨by rw [← h.postdm.1, hEr]; rfl, h.post_lt hEr⟩
    have hpath : E1.mode.ownSlot = false → rrL fn.params base 0 (callPe Γ fn.params args) E1.path = E1.path :=
      fun ho => rrL_id _ _ _ fun d hd => (hroots d (by simp [Entry.vdeps, ho, hd])).2
    have hheld : rrL fn.params base 0 (callPe Γ fn.params args) E1.held = E1.held :=
      rrL_id _ _ _ fun d hd => (hroots d (by simp [Entry.vdeps, hd])).2
    have hvd : (rrE fn.params base 0 (callPe Γ fn.params args) E1).vdeps = E1.vdeps := by
      unfold Entry.vdeps rrE
      cases ho : E1.mode.ownSlot
      · simp only [Bool.false_eq_true, ↓reduceIte]; rw [hpath ho, hheld]
      · simp only [↓reduceIte]; rw [hheld]
    refine ⟨?_, ?_, ?_⟩
    · rw [exits_at h.pe_lt fn.params 0 _ hc hyk (fun d hd k t hk he => by
        rw [hce] at hd
        have := (hroots d hd).2
        rw [he] at this
        exact absurd this (Nat.not_lt.mpr (Nat.le_add_right _ k)))]
    · rw [hce, hvd]; exact fun d hd => (hroots d hd).1
    · rw [hce]
      refine ⟨rfl, rfl, fun hrb => ?_, fun _ => ⟨hl, fun ho => ?_, ?_⟩⟩
      · have hrb' : E1.mode = .rootb := by
          rcases hrb with hrb | ⟨b, hb, _⟩
          · exact hrb
          · obtain ⟨E0, h0, hm0, _⟩ := h.postdt.2 y E1 h1
            exact absurd (hm0 ▸ hb : E0.mode = .inout b) (h.noio y E0 b h0)
        have ho : E1.mode.ownSlot = false := by rw [hrb']; rfl
        show E1 = { E1 with path := _, held := _ }
        rw [hpath ho, hheld]
      · show rrL fn.params base 0 (callPe Γ fn.params args) E1.path ⊆ E1.path
        rw [hpath ho]; exact List.Subset.refl _
      · show rrL fn.params base 0 (callPe Γ fn.params args) E1.held ⊆ E1.held
        rw [hheld]; exact List.Subset.refl _

theorem dom_ne (h : CallH P Γ F x fn args base) {r : Var} (hr : (Γ r).isSome) :
    r ≠ x ∧ r ≠ base + fn.params.length := by
  obtain ⟨E, hE⟩ := Option.isSome_iff_exists.mp hr
  refine ⟨fun e => (by rw [e, h.fresh] at hE; cases hE), fun e => ?_⟩
  have hlt := h.domlt r E hE
  rw [e] at hlt
  exact absurd hlt (Nat.not_lt.mpr (Nat.le_add_right _ _))

theorem chain_id (h : CallH P Γ F x fn args base) {E : Entry} (hE : ∀ d ∈ E.vdeps, (Γ d.root).isSome) (o : Bool) :
    killE .replace false (base + fn.params.length) (killE .replace false x
      (if o then killE .replace false (base + fn.params.length) E else E)) = E := by
  have hn : ∀ d ∈ E.vdeps, d.root ≠ base + fn.params.length := fun d hd => (h.dom_ne (hE d hd)).2
  have hx : ∀ d ∈ E.vdeps, d.root ≠ x := fun d hd => (h.dom_ne (hE d hd)).1
  have h1 : (if o then killE .replace false (base + fn.params.length) E else E) = E := by
    cases o
    · rfl
    · exact killE_nohit hn
  rw [h1, killE_nohit hx, killE_nohit hn]

theorem post_none_ge (h : CallH P Γ F x fn args base) {y : Var} (hy : base ≤ y) : callPost Γ fn args y = none := by
  cases h1 : callPost Γ fn args y with
  | none => rfl
  | some E => exact absurd (h.post_lt h1) (Nat.not_lt.mpr hy)

/-- What the exits, the result's move and the end of the result's scope
    leave is at least as strong as the context the summary promises. -/
theorem fin_weaker (h : CallH P Γ F x fn args base) {Δa : Ctx} (hdt : DomTy (sigCtx fn) Δa) {Er : Entry}
    (hErl : Er.live = true) (hErt : Er.ty = fn.resTy) (hErm : Er.mode = resMode fn)
    (hErp : ∀ d ∈ Er.path, (d.root, d.kind) ∈ fn.lends) (hErh : ∀ d ∈ Er.held, (d.root, d.kind) ∈ fn.rholds)
    (hEr0 : fn.resOwn = true → fn.resTy.holdsView = false → Er.held = [])
    (hio : ∀ i (hi : i < fn.params.length) b, fn.params[i].1 = .inout b →
      ∃ Ei, Δa i = some Ei ∧ Ei.live = true ∧ (∀ d ∈ Ei.held, (i, d.root, d.kind) ∈ fn.outHolds) ∧
        (fn.params[i].2.holdsView = false → Ei.held = []))
    (Γ3 : Ctx)
    (hΓ3 : Γ3 = setE (A2.kill .replace false x
          (if fn.resOwn then setE (A2.kill .replace false (base + fn.params.length)
              (exitsP fn.params base 0 (callPe Γ fn.params args) ((callS Γ F fn args base x).canon Δa)))
            (base + fn.params.length)
              { rrE fn.params base 0 (callPe Γ fn.params args)
                  ((callS Γ F fn args base x).liftE fn.params.length Er) with live := false, dtor := false }
           else exitsP fn.params base 0 (callPe Γ fn.params args) ((callS Γ F fn args base x).canon Δa)))
          x (if fn.resOwn then { (⟨(rrE fn.params base 0 (callPe Γ fn.params args)
                ((callS Γ F fn args base x).liftE fn.params.length Er)).ty, .own, true, [],
                (rrE fn.params base 0 (callPe Γ fn.params args)
                ((callS Γ F fn args base x).liftE fn.params.length Er)).held, false⟩ : Entry) with mode := resMode fn }
             else { rrE fn.params base 0 (callPe Γ fn.params args)
                ((callS Γ F fn args base x).liftE fn.params.length Er) with mode := resMode fn })) :
    Weaker (exitScope (base + fn.params.length) Γ3) (setE (callPost Γ fn args) x (callRes Γ fn args)) := by
  obtain ⟨hl', hm', ht', hp', hh'⟩ := h.res_props hErl hErt hErm hErp hErh hEr0
  generalize hE' : rrE fn.params base 0 (callPe Γ fn.params args)
    ((callS Γ F fn args base x).liftE fn.params.length Er) = Er' at hl' hm' ht' hp' hh' hΓ3
  generalize hΓb : exitsP fn.params base 0 (callPe Γ fn.params args) ((callS Γ F fn args base x).canon Δa) = Γb
    at hΓ3
  subst hΓ3
  have hx1 : callPost Γ fn args x = none := by
    have := h.postdm.1 x; rw [h.fresh] at this; cases h' : callPost Γ fn args x <;> simp_all
  have hxr : x ≠ base + fn.params.length := by
    intro e; have := vlt h.xlt; rw [e] at this; exact absurd this (Nat.not_lt.mpr (Nat.le_add_right _ _))
  -- the bindings other than `x` and the result slot
  have hother : ∀ y, y ≠ x → y ≠ base + fn.params.length →
      exitScope (base + fn.params.length) (setE (A2.kill .replace false x
        (if fn.resOwn then setE (A2.kill .replace false (base + fn.params.length) Γb)
          (base + fn.params.length) { Er' with live := false, dtor := false } else Γb)) x
        (if fn.resOwn then { (⟨Er'.ty, .own, true, [], Er'.held, false⟩ : Entry) with mode := resMode fn }
         else { Er' with mode := resMode fn })) y =
      (Γb y).map (fun E => killE .replace false (base + fn.params.length) (killE .replace false x
        (if fn.resOwn then killE .replace false (base + fn.params.length) E else E))) := by
    intro y hyx hyr
    cases ho : fn.resOwn <;>
      simp [A2.exitScope, setE, upd_ne _ _ hyx, upd_ne _ _ hyr, A2.kill, Option.map_map, Function.comp_def]
  have key : ∀ y, (exitScope (base + fn.params.length) (setE (A2.kill .replace false x
        (if fn.resOwn then setE (A2.kill .replace false (base + fn.params.length) Γb)
          (base + fn.params.length) { Er' with live := false, dtor := false } else Γb)) x
        (if fn.resOwn then { (⟨Er'.ty, .own, true, [], Er'.held, false⟩ : Entry) with mode := resMode fn }
         else { Er' with mode := resMode fn })) y = none ∧
        setE (callPost Γ fn args) x (callRes Γ fn args) y = none) ∨
      ∃ Eo Et, exitScope (base + fn.params.length) (setE (A2.kill .replace false x
        (if fn.resOwn then setE (A2.kill .replace false (base + fn.params.length) Γb)
          (base + fn.params.length) { Er' with live := false, dtor := false } else Γb)) x
        (if fn.resOwn then { (⟨Er'.ty, .own, true, [], Er'.held, false⟩ : Entry) with mode := resMode fn }
         else { Er' with mode := resMode fn })) y = some Eo ∧
        setE (callPost Γ fn args) x (callRes Γ fn args) y = some Et ∧ EntryWeaker Eo Et := by
    intro y
    have hT : ∀ y, y ≠ x → setE (callPost Γ fn args) x (callRes Γ fn args) y = callPost Γ fn args y :=
      fun y hyx => by simp [setE, upd_ne _ _ hyx]
    by_cases hyr : y = base + fn.params.length
    · subst hyr
      left
      refine ⟨exitScope_none, ?_⟩
      rw [hT _ hxr.symm]; exact h.post_none_ge (Nat.le_add_right _ _)
    by_cases hyx : y = x
    · subst hyx
      right
      -- the result, moved into `x`
      have hv : ∀ d ∈ (if fn.resOwn then { (⟨Er'.ty, .own, true, [], Er'.held, false⟩ : Entry) with mode := resMode fn }
          else { Er' with mode := resMode fn }).vdeps, (Γ d.root).isSome := by
        intro d hd
        cases ho : fn.resOwn
        · rw [ho] at hd
          have hos : (resMode fn).ownSlot = false := by simp [resMode, ho, Mode.ownSlot]
          simp only [Bool.false_eq_true, ↓reduceIte, Entry.vdeps, hos, List.mem_append] at hd
          rcases hd with hd | hd
          · exact (hp' hos d hd).1
          · exact (hh' d hd).1
        · rw [ho] at hd
          have hos : (resMode fn).ownSlot = true := by simp [resMode, ho, Mode.ownSlot]
          simp only [↓reduceIte, Entry.vdeps, hos, List.nil_append] at hd
          exact (hh' d hd).1
      refine ⟨killE .replace false (base + fn.params.length)
          (if fn.resOwn then { (⟨Er'.ty, .own, true, [], Er'.held, false⟩ : Entry) with mode := resMode fn }
            else { Er' with mode := resMode fn }), callRes Γ fn args,
        by simp [A2.exitScope, upd_ne _ _ hxr, setE, A2.kill], by simp [setE], ?_⟩
      rw [killE_nohit (fun d hd => (h.dom_ne (hv d hd)).2)]
      cases ho : fn.resOwn
      · have hos : (resMode fn).ownSlot = false := by simp [resMode, ho, Mode.ownSlot]
        exact RSetup.EntryWeaker.mk' (by simp [callRes, ht']) (by simp [callRes])
          (by simp [resMode_ne' fn, resMode_inout fn])
          (by simp [callRes, hl']) (fun _ d hd => (hp' hos d hd).2) (fun d hd => (hh' d hd).2)
      · exact RSetup.EntryWeaker.mk' (by simp [callRes, ht']) (by simp [callRes])
          (by simp [resMode_ne' fn, resMode_inout fn])
          (by simp [callRes]) (fun _ d hd => by simp at hd) (fun d hd => (hh' d hd).2)
    rw [hother y hyx hyr, hT y hyx]
    have hnone : Γb y = none → callPost Γ fn args y = none →
        ((Γb y).map (fun E => killE .replace false (base + fn.params.length) (killE .replace false x
          (if fn.resOwn then killE .replace false (base + fn.params.length) E else E))) = none ∧
          callPost Γ fn args y = none) := fun h1 h2 => ⟨by rw [h1]; rfl, h2⟩
    rcases RSetup.canon_cases h.sOK Δa y with ⟨v, hv, hc⟩ | ⟨hy, hc⟩
    · change callRen fn.params args base v = y at hv
      rcases callRen_cases fn.params args base v with ⟨b, t, hvp, hr⟩ | ⟨hnv, hr⟩
      · -- an `inout` argument
        rw [hr] at hv; subst hv
        have hvl := lt_of_get hvp
        have hpv := get_of hvp
        obtain ⟨Ei, hEi, hEil, hEih, hEi0⟩ := hio v hvl b (by rw [hpv])
        obtain ⟨E0, h0, hm0, ht0⟩ := hdt.2 v Ei hEi
        rw [sigCtx_of hvp] at h0; cases h0
        simp only [paramE] at hm0 ht0
        obtain ⟨hat, hheld⟩ := h.inout_at hvp hEi hm0 hEih
        rw [hΓb] at hat
        obtain ⟨Ea, hEa, hae⟩ := h.argE_eq hvl
        obtain ⟨_, h1, _, hok, hmv, _⟩ := h.arg v hvl
        rw [hEa] at h1; cases h1
        simp only [hpv, paramOK] at hok
        obtain ⟨hty, hcan, _⟩ := hok
        have hown : Ea.mode = .own := by
          rcases hcan with hm | ⟨b', hm, _⟩
          · exact hm
          · exact absurd hm (h.noInout _ Ea b' hEa)
        obtain ⟨Et, hEt, _⟩ := h.postdm.get hEa
        have hak : args[v]? = some (args.getD v 0) := by
          simp [List.getD, show v < args.length from h.len ▸ hvl]
        have hu : ∀ k', k' ≠ v → args[k']? ≠ some (args.getD v 0) := by
          intro k' hk' he
          have hk'l : k' < args.length := (List.getElem?_eq_some_iff.mp he).1
          have hge : args.getD k' 0 = args.getD v 0 := by simp [List.getD, he]
          exact hk' (h.moving hvl (h.len ▸ hk'l) (by rw [hpv]; rfl) hge)
        obtain ⟨E2, h2, ht2, hm2, _, hh2, _⟩ := killNames_get _ hEt
        have hpost := callPostAux_at fn.params args 0 v Γ hak hu hvp rfl E2 h2
        simp only [postEnt, Nat.zero_add, hae] at hpost
        obtain ⟨hpt, hpm, _, hph, _⟩ := hpost
        rw [← ht2] at hpt; rw [← hm2] at hpm; rw [← hh2] at hph
        have hrb : Ei.mode ≠ .rootb := by rw [hm0]; simp
        have hvd : ∀ d ∈ (rrE fn.params base 0 (callPe Γ fn.params args)
            ((callS Γ F fn args base x).liftE v Ei)).vdeps, (Γ d.root).isSome := by
          intro d hd
          have hos : (rrE fn.params base 0 (callPe Γ fn.params args)
              ((callS Γ F fn args base x).liftE v Ei)).mode.ownSlot = true := by
            simp [rrE, liftE_eq _ hrb, hm0, liftMode, Mode.ownSlot]
          simp only [Entry.vdeps, hos, ↓reduceIte, List.nil_append] at hd
          exact (hheld d hd).1
        refine Or.inr ⟨rrE fn.params base 0 (callPe Γ fn.params args) ((callS Γ F fn args base x).liftE v Ei),
          Et, by rw [hat, Option.map_some, h.chain_id hvd], hEt, ?_⟩
        refine ⟨?_, ?_, fun hr => by simp [rrE, liftE_eq _ hrb, hm0, liftMode] at hr,
          fun _ => ⟨by simp [rrE, liftE_eq _ hrb, hEil], fun ho => ?_, fun d hd => ?_⟩⟩
        · rw [hpt, hty]; simp [rrE, liftE_eq _ hrb, ht0]
        · rw [hpm, hown]; simp [rrE, liftE_eq _ hrb, hm0, liftMode]
        · simp [rrE, liftE_eq _ hrb, hm0, liftMode, Mode.ownSlot] at ho
        · rw [hph, ← hae]
          by_cases hv : t.holdsView = true
          · simp only [hv, ↓reduceIte]; exact (hheld d hd).2
          · -- an `inout` parameter whose type holds no views holds nothing
            have hv' : t.holdsView = false := by simpa using hv
            have he0 := hEi0 (by rw [hpv]; exact hv')
            simp only [rrE, liftE_eq _ hrb, he0, ht0, hm0, Mode.ownSlot, hv', ownHeld] at hd
            simp [rds, rrL_nil] at hd
      · -- a parameter slot, the result slot, or a callee local
        rw [hr] at hv; subst hv
        refine Or.inl (hnone ?_ (h.post_none_ge (Nat.le_add_right _ _)))
        rw [← hΓb]
        rcases Nat.lt_trichotomy v fn.params.length with hlt | heq | hgt
        · have hget : fn.params[v]? = some fn.params[v] := List.getElem?_eq_getElem hlt
          have := exits_slot (base := base) (pe := callPe Γ fn.params args) fn.params 0
            ((callS Γ F fn args base x).canon Δa) v fn.params[v] hget
            (fun b he => hnv b fn.params[v].2 (by rw [hget, ← he]))
          simpa using this
        · exact absurd (by rw [heq]) hyr
        · apply exits_none
          have hnone' : Δa v = none := by
            have := hdt.1 v; rw [sigCtx_none hgt] at this
            cases h' : Δa v <;> simp_all
          rw [hc, hnone']; rfl
    · -- the frame
      cases h1 : callPost Γ fn args y with
      | none =>
        refine Or.inl ⟨?_, rfl⟩
        have : Γb y = none := by
          rw [← hΓb]; apply exits_none
          rw [hc, h.frame_of hy hyx, h1]; rfl
        rw [this]; rfl
      | some E1 =>
        obtain ⟨hat, hvd, hw⟩ := h.frame_at (Δa := Δa) hy hyx h1
        rw [hΓb] at hat
        exact Or.inr ⟨_, E1, by rw [hat, Option.map_some, h.chain_id hvd], rfl, hw⟩
  refine ⟨fun y => ?_, h.postwf.add hx1 (fun _ _ r hr => h.reswf r hr), h.resnames⟩
  rcases key y with ⟨h1, h2⟩ | ⟨Eo, Et, h1, h2, hw⟩
  · rw [h1, h2]; exact ⟨Iff.rfl, fun E E' hE => (by cases hE)⟩
  · rw [h1, h2]
    refine ⟨by simp, fun E E' hE hE' => ?_⟩
    cases hE; cases hE'; exact hw

/-- The inside of the call is well-typed where the call was. -/
theorem typedIn (h : CallH P Γ F x fn args base) :
    StmtT P ((callS Γ F fn args base x).canon (sigCtx fn)) F (callIn fn args base x)
      (setE (callPost Γ fn args) x (callRes Γ fn args)) := by
  obtain ⟨hsrc, _, _, _, _, _, hlends, hrholds, _, _, _, Δa, hbody,
    ⟨Er, hEr, hErl, hErt, hErm, hErp, hErh, hEr0⟩, hio⟩ := h.fnok
  obtain ⟨hren, habΔ⟩ := RSetup.StmtT.ren h.sOK h.prog hbody hsrc h.sig_abs (sigCtx_wf fn) (sigCtx_names fn)
  have hdt := StmtT.domTy hbody hsrc
  have hErv : ∀ d0 ∈ Er.vdeps, lendable fn d0.root := by
    intro d0 hd0
    unfold Entry.vdeps at hd0
    rcases List.mem_append.mp hd0 with hd | hd
    · split at hd
      · cases hd
      · exact (hlends _ (hErp d0 hd)).1
    · exact (hrholds _ (hErh d0 hd)).1
  obtain ⟨hl', hm', ht', hp', hh'⟩ := h.res_props hErl hErt hErm hErp hErh hEr0
  refine h.typedIn_of habΔ hren (h.res_at hEr hErm hErv) hl' hm' ht' ?_
    (fun Γ3 hΓ3 => h.fin_weaker hdt hErl hErt hErm hErp hErh hEr0 hio Γ3 hΓ3)
  intro hx
  obtain ⟨d, hd, hdx⟩ := List.mem_map.mp hx
  have hdom : (Γ d.root).isSome := by
    unfold Entry.vdeps at hd
    rcases List.mem_append.mp hd with hd | hd
    · split at hd
      · cases hd
      · rename_i ho
        rw [hm'] at ho
        exact (hp' (by simpa using ho) d hd).1
    · exact (hh' d hd).1
  exact (h.dom_ne hdom).1 hdx

/-- The call's expansion is well-typed where the call was. -/
theorem typed (h : CallH P Γ F x fn args base) {k : Stmt} {Δ : Ctx} (hk : k.src = true)
    (hkT : StmtT P (setE (callPost Γ fn args) x (callRes Γ fn args)) F k Δ) (hpx : NoPin Δ x) :
    StmtT P ((callS Γ F fn args base x).canon (sigCtx fn)) F (callStmt fn args base x k) (exitScope x Δ) :=
  StmtT.scope ⟨callX fn, h.canon_x _, by simp [callX, resMode_ne' fn]⟩ h.xF (StmtT.seq hk h.typedIn hkT) hpx

end CallH

end A2
