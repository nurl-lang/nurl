import A1.Rename
import A1.Preservation

/-! A1 — the call step.

A call binds its parameters and runs the callee's body, renamed apart, inside
their scopes (`callStmt`).  The context it runs in is the caller's view of the
callee's own starting context (`RSetup.canon`): the renaming lemma types the
body there, and the summary the callee was checked against says what the
parameters' exits leave. -/

namespace A1

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
    DomTy Γ0 (A1.kill e hv x Γ) := by
  refine ⟨fun y => by rw [kill_dom]; exact h.1 y, fun y E hy => ?_⟩
  obtain ⟨E1, h1, hm1, _⟩ := kill_cmode hy
  obtain ⟨E0, h0, hm0, ht0⟩ := h.2 y E1 h1
  simp only [A1.kill, h1, Option.map_some, Option.some.injEq] at hy; subst hy
  exact ⟨E0, h0, by rw [killE_mode, hm0], by rw [killE_ty, ht0]⟩

theorem DomTy.setE {Γ0 Γ : Ctx} (h : DomTy Γ0 Γ) {x : Var} {E : Entry}
    (hx : ∃ E0, Γ0 x = some E0 ∧ E.mode = E0.mode ∧ E.ty = E0.ty) : DomTy Γ0 (A1.setE Γ x E) := by
  obtain ⟨E0, h0, hm, ht⟩ := hx
  refine ⟨fun y => ?_, fun y E' hy => ?_⟩
  · by_cases hyx : y = x
    · subst hyx; simp [A1.setE, h0]
    · simp only [A1.setE, upd_ne _ _ hyx]; exact h.1 y
  · by_cases hyx : y = x
    · subst hyx; simp only [A1.setE, upd_same, Option.some.injEq] at hy; subst hy; exact ⟨E0, h0, hm, ht⟩
    · simp only [A1.setE, upd_ne _ _ hyx] at hy; exact h.2 y E' hy

theorem DomTy.weaker {Γ Γ' : Ctx} (hw : Weaker Γ Γ') : DomTy Γ Γ' := by
  refine ⟨fun x => (hw.isSome x).symm, fun x E h => ?_⟩
  obtain ⟨E0, h0, hw0⟩ := hw.get' h
  exact ⟨E0, h0, hw0.2.1, hw0.1⟩

theorem RhsT.domTy {Γ Γ1 : Ctx} {F : List Var} {r : Rhs} {E : Entry} (hr : RhsT Γ F r E Γ1) :
    DomTy Γ Γ1 := by
  cases hr with
  | @moveOwn y Ey hy _ _ _ => exact ((DomTy.refl Γ).kill .replace false y).setE ⟨Ey, hy, rfl, rfl⟩
  | pop _ _ _ _ _ => exact (DomTy.refl Γ).kill _ _ _
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
  obtain ⟨fn, _, hlen, hargs, _, rfl⟩ := hc
  refine callPostAux_domTy _ _ _ _ (fun a ha => ?_) (DomTy.refl Γ)
  obtain ⟨i, hi, rfl⟩ := mem_args ha
  obtain ⟨Ea, hEa, _⟩ := hargs i (hlen ▸ hi)
  exact ⟨Ea, hEa⟩

theorem PushArg.domTy {Γ Γ1 : Ctx} {F : List Var} {y : Var} {Ey : Entry} {t : Ty} {D : List Dep}
    (hy : Γ y = some Ey) (hp : PushArg Γ F y Ey t D Γ1) : DomTy Γ Γ1 := by
  cases hp with
  | move _ _ => exact ((DomTy.refl Γ).kill .replace false y).setE ⟨Ey, hy, rfl, rfl⟩
  | int => exact DomTy.refl Γ
  | slice _ => exact DomTy.refl Γ

theorem DomTy.exitScope_fresh {Γ Γ1 Δ : Ctx} {x : Var} {E : Entry} (hx : Γ x = none)
    (h1 : DomTy Γ Γ1) (h2 : DomTy (A1.setE Γ1 x E) Δ) : DomTy Γ (A1.exitScope x Δ) := by
  refine ⟨fun y => ?_, fun y E' hy => ?_⟩
  · by_cases hyx : y = x
    · subst hyx; simp [A1.exitScope, hx]
    · simp only [A1.exitScope, upd_ne _ _ hyx, kill_dom]
      rw [h2.1 y]; simp only [A1.setE, upd_ne _ _ hyx]; exact h1.1 y
  · have hyx : y ≠ x := fun e => by subst e; simp [A1.exitScope] at hy
    simp only [A1.exitScope, upd_ne _ _ hyx] at hy
    obtain ⟨E1, h1', hm1, _⟩ := kill_cmode hy
    simp only [A1.kill, h1', Option.map_some, Option.some.injEq] at hy; subst hy
    obtain ⟨E2, h2', hm2, ht2⟩ := h2.2 y E1 h1'
    simp only [A1.setE, upd_ne _ _ hyx] at h2'
    obtain ⟨E3, h3, hm3, ht3⟩ := h1.2 y E2 h2'
    exact ⟨E3, h3, by rw [killE_mode, hm2, hm3], by rw [killE_ty, ht2, ht3]⟩

/-- Source code keeps every binding's mode and type, and binds nothing new. -/
theorem StmtT.domTy {P : Prog} {Γ : Ctx} {F : List Var} {s : Stmt} {Δ : Ctx}
    (ht : StmtT P Γ F s Δ) : s.src = true → DomTy Γ Δ := by
  induction ht with
  | skip => exact fun _ => DomTy.refl _
  | seq _ _ _ iha ihb =>
    intro hs; simp only [Stmt.src, Bool.and_eq_true] at hs; exact (iha hs.1).trans (ihb hs.2)
  | letv hks hx _ hr _ ih => exact fun _ => DomTy.exitScope_fresh hx hr.domTy (ih hks)
  | letcall hks hx _ hc _ ih => exact fun _ => DomTy.exitScope_fresh hx hc.domTy (ih hks)
  | scope => intro hs; simp [Stmt.src] at hs
  | rbind => intro hs; simp [Stmt.src] at hs
  | frozen => intro hs; simp [Stmt.src] at hs
  | @assign Γ Γ1 F x r Ex E hx _ _ hr hty _ _ =>
    intro _
    exact (hr.domTy.kill _ _ _).setE ⟨Ex, hx, rfl, hty⟩
  | ite _ _ _ _ _ iha _ => intro _; exact iha (by assumption)
  | «while» => exact fun _ => DomTy.refl _
  | @push Γ Γ1 F x y Ex Ey Ex1 t D hx _ _ _ _ hy _ _ _ hpa _ hx1 _ =>
    intro _
    obtain ⟨E0, h0, hm0, ht0⟩ := (hpa.domTy hy).2 x Ex1 hx1
    exact ((hpa.domTy hy).kill _ _ _).setE ⟨E0, h0, hm0, ht0⟩
  | @free Γ F x E t hx _ _ _ _ => exact fun _ => ((DomTy.refl Γ).kill _ _ _).setE ⟨E, hx, rfl, rfl⟩
  | sub hw _ ho ih =>
    intro hs
    have h0 := (DomTy.weaker hw).trans (ih hs)
    rcases ho with rfl | hwo
    · exact h0
    · exact h0.trans (DomTy.weaker hwo)

/-! ### What the call sets up -/

/-- An integer's dependencies say nothing; the call forgets them. -/
def Entry.clean (E : Entry) : Entry :=
  if E.ty = .int ∧ E.mode ≠ .rootb then { E with path := [], held := [] } else E

/-- The roots of what the arguments hold views of. -/
def callR (Γ : Ctx) (args : List Var) : List Var :=
  args.flatMap (fun a => if (argE Γ a).ty = .int then [] else roots (argE Γ a).held)

/-- An `in` parameter, as the caller sees it: a borrow of its argument. -/
def callPe (Γ : Ctx) (ps : List (PMode × Ty)) (args : List Var) (v : Var) : Entry :=
  match ps[v]? with
  | some (.inp, _) =>
    if (argE Γ (args.getD v 0)).ty = .int then ⟨.int, .rootb, true, [], []⟩
    else ⟨(argE Γ (args.getD v 0)).ty, .rootb, true,
          derive (args.getD v 0) (argE Γ (args.getD v 0)) .self, (argE Γ (args.getD v 0)).held⟩
  | _ => ⟨.int, .rootb, true, [], []⟩

/-- The caller's binding of the result, before the result is moved in. -/
def callX (fn : Fn) : Entry := ⟨fn.resTy, resMode fn, false, [], []⟩

/-- Every caller binding but the `inout` arguments is lent out for the call. -/
def zOf (fn : Fn) (args : List Var) (base : Nat) : List Var :=
  (List.range base).filter (fun v => !(inoutArgs fn.params args).contains v)

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
  Fc := F ++ zOf fn args base
  bnd := bndOf fn.params

/-- What a well-typed call, in a well-formed configuration, gives. -/
structure CallH (P : Prog) (Γ : Ctx) (F : List Var) (x : Var) (fn : Fn) (args : List Var) (base : Nat) :
    Prop where
  prog    : ProgOK P
  fnok    : FnOK P fn
  len     : args.length = fn.params.length
  arg     : ∀ i (h : i < fn.params.length), ∃ Ea, Γ (args.getD i 0) = some Ea ∧ Ea.live = true ∧
              paramOK fn.params[i].1 fn.params[i].2 Ea ∧
              (fn.params[i].1.moves = true →
                args.getD i 0 ∉ F ∧ args.getD i 0 ∉ roots Ea.vdeps ∧
                ∀ j < fn.params.length, j ≠ i →
                  args.getD j 0 ≠ args.getD i 0 ∧ args.getD i 0 ∉ roots (argE Γ (args.getD j 0)).vdeps)
  fresh   : Γ x = none
  xF      : x ∉ F
  xlt     : x < base
  domlt   : ∀ v E, Γ v = some E → v < base
  Flt     : ∀ v ∈ F, v < base
  wf      : CtxWF Γ
  noInout : ∀ v E b, Γ v = some E → E.mode ≠ .inout b
  rbLive  : ∀ p E, Γ p = some E → E.mode = .rootb → E.live = true
  anch    : ∀ p E, Γ p = some E → E.mode = .rootb → ∀ r ∈ roots E.vdeps, r ∈ F
  postwf  : CtxWF (callPost Γ fn args)
  postdm  : DomMode Γ (callPost Γ fn args)

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
  obtain ⟨_, _, _, _, hmv⟩ := h.arg i hi
  exact ((hmv hm).2.2 j hj hne).1 he

/-- ... nor reached from any argument. -/
theorem moving_root (h : CallH P Γ F x fn args base) {i j : Nat} (hi : i < fn.params.length)
    (hj : j < fn.params.length) (hm : fn.params[i].1.moves = true) :
    args.getD i 0 ∉ roots (argE Γ (args.getD j 0)).vdeps := by
  obtain ⟨Ea, hEa, _, _, hmv⟩ := h.arg i hi
  by_cases hji : j = i
  · subst hji
    have : argE Γ (args.getD j 0) = Ea := by unfold argE; rw [hEa]; rfl
    rw [this]; exact (hmv hm).2.1
  · exact ((hmv hm).2.2 j hj hji).2

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
        simp only [setE, upd_ne _ _ hay.symm, A1.kill] at h0
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
        simp only [setE, upd_ne _ _ hay.symm, A1.kill] at h0
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
def postEnt (Γ0 : Ctx) (fn : Fn) (args : List Var) (i : Nat) (a : Var) : PMode → Entry
  | .sink => { argE Γ0 a with live := false }
  | .inout _ => { argE Γ0 a with held := (argE Γ0 a).held ++ outHeld Γ0 fn args i ++ heldOfArgs Γ0 args }
  | .inp => argE Γ0 a

theorem callPostAux_at {Γ0 : Ctx} {fn : Fn} {args : List Var} {y : Var} :
    ∀ (ps : List (PMode × Ty)) (as : List Var) (i k : Nat) (Γ : Ctx) {pm : PMode} {t : Ty},
      as[k]? = some y → (∀ k', k' ≠ k → as[k']? ≠ some y) → ps[k]? = some (pm, t) → pm.moves = true →
      ∀ E, callPostAux Γ0 fn args ps as i Γ y = some E →
        let E0 := postEnt Γ0 fn args (i + k) y pm
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

theorem clean_mode (E : Entry) : E.clean.mode = E.mode := by unfold Entry.clean; split <;> rfl
theorem clean_ty (E : Entry) : E.clean.ty = E.ty := by unfold Entry.clean; split <;> rfl
theorem clean_live (E : Entry) : E.clean.live = E.live := by unfold Entry.clean; split <;> rfl
theorem clean_id {E : Entry} (h : E.ty ≠ .int ∨ E.mode = .rootb) : E.clean = E := by
  unfold Entry.clean; rw [if_neg]; rintro ⟨h1, h2⟩; rcases h with h | h <;> contradiction

theorem mem_callR {Γ : Ctx} {args : List Var} {r : Var} :
    r ∈ callR Γ args ↔ ∃ a ∈ args, (argE Γ a).ty ≠ .int ∧ r ∈ roots (argE Γ a).held := by
  unfold callR
  simp only [List.mem_flatMap]
  constructor
  · rintro ⟨a, ha, hr⟩; split at hr
    · simp at hr
    · exact ⟨a, ha, by assumption, hr⟩
  · rintro ⟨a, ha, hn, hr⟩; exact ⟨a, ha, by rw [if_neg hn]; exact hr⟩

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

namespace CallH
variable {P : Prog} {Γ : Ctx} {F : List Var} {x : Var} {fn : Fn} {args : List Var} {base : Nat}

theorem argE_eq (h : CallH P Γ F x fn args base) {i : Nat} (hi : i < fn.params.length) :
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
theorem ren_dom (h : CallH P Γ F x fn args base) {v : Nat} {r : Var} (hr : callRen fn.params args base v = r)
    (hlt : r < base) : ∃ b t, fn.params[v]? = some (.inout b, t) ∧ args.getD v 0 = r := by
  rcases callRen_cases fn.params args base v with ⟨b, t, hv, hrv⟩ | ⟨_, hrv⟩
  · exact ⟨b, t, hv, hrv ▸ hr⟩
  · rw [hrv] at hr; subst hr; exact absurd hlt (Nat.not_lt.mpr (Nat.le_add_right _ _))

theorem notRen_root (h : CallH P Γ F x fn args base) {j : Nat} (hj : j < fn.params.length) {r : Var}
    (hr : r ∈ roots (argE Γ (args.getD j 0)).vdeps) (hrlt : r < base) :
    ∀ w, callRen fn.params args base w ≠ r := by
  intro w hw
  obtain ⟨b, t, hwp, rfl⟩ := h.ren_dom hw hrlt
  exact h.moving_root (lt_of_get hwp) hj (by rw [get_of hwp]; rfl) hr

theorem frame_some (h : CallH P Γ F x fn args base) {y : Var} {E : Entry}
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

theorem frame_of (h : CallH P Γ F x fn args base) {y : Var} (hy : ∀ v, callRen fn.params args base v ≠ y)
    (hyx : y ≠ x) : (callS Γ F fn args base x).Φ y = (callPost Γ fn args y).map Entry.clean := by
  simp only [callS]
  rw [if_neg (fun ⟨v, hv⟩ => hy v hv)]
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
  have hvd := held_vdeps hrh
  obtain ⟨Er, hEr, hro⟩ := h.wf _ Ea hEa (by obtain ⟨E', h1, h2, _⟩ := h.arg j hjp; rw [hEa] at h1; cases h1; exact h2)
    (Or.inl hn) r hvd
  refine ⟨h.notRen_root hjp (by rw [hae]; exact hvd) (h.domlt r Er hEr), Er, hEr, hro⟩

theorem sOK (h : CallH P Γ F x fn args base) : (callS Γ F fn args base x).OK where
  inj := h.ren_inj
  Rout r hr := (h.R_facts hr).1
  Rroot r hr := by
    obtain ⟨hout, Er, hEr, hro⟩ := h.R_facts hr
    exact h.frame_root hEr hro hout
  Fcout v := by
    show callRen fn.params args base v ∉ F ++ zOf fn args base
    intro hm
    rcases callRen_cases fn.params args base v with ⟨b, t, hv, hrv⟩ | ⟨_, hrv⟩ <;> rw [hrv] at hm
    · rcases List.mem_append.mp hm with hm | hm
      · obtain ⟨_, _, _, _, hmv⟩ := h.arg v (lt_of_get hv)
        exact (hmv (by rw [get_of hv]; rfl)).1 hm
      · simp only [zOf, List.mem_filter, Bool.not_eq_eq_eq_not, Bool.not_true,
          List.contains_eq_mem, decide_eq_false_iff_not] at hm
        exact hm.2 (mem_inoutArgs hv)
    · rcases List.mem_append.mp hm with hm | hm
      · exact absurd (h.Flt _ hm) (Nat.not_lt.mpr (Nat.le_add_right _ _))
      · simp only [zOf, List.mem_filter, List.mem_range] at hm
        exact absurd hm.1 (Nat.not_lt.mpr (Nat.le_add_right _ _))
  pe_rb v := by
    show (callPe Γ fn.params args v).mode = .rootb
    unfold callPe; split
    · split <;> rfl
    · rfl
  pe_out v r hr := by
    change r ∈ roots (callPe Γ fn.params args v).vdeps at hr
    unfold callPe at hr
    split at hr
    · rename_i t hv
      have hvp := lt_of_get hv
      obtain ⟨Ea, hEa, hae⟩ := h.argE_eq hvp
      obtain ⟨_, h1, hl, _⟩ := h.arg v hvp
      rw [hEa] at h1; cases h1
      split at hr
      · simp [roots, Entry.vdeps, Mode.ownSlot] at hr
      · rename_i hn
        rw [hae] at hn hr
        simp only [roots, Entry.vdeps, Mode.ownSlot, Bool.false_eq_true, ↓reduceIte, List.map_append,
          List.mem_append] at hr
        have hgen : r ∈ roots Ea.vdeps → (∀ w, callRen fn.params args base w ≠ r) ∧
            ∃ E, (callS Γ F fn args base x).Φ r = some E ∧ E.mode.isRoot = true := by
          intro hrv
          obtain ⟨Er, hEr, hro⟩ := h.wf _ Ea hEa hl (Or.inl hn) r hrv
          have hout := h.notRen_root hvp (by rw [hae]; exact hrv) (h.domlt r Er hEr)
          exact ⟨hout, h.frame_root hEr hro hout⟩
        rcases hr with hr | hr
        · rcases derive_roots_cases hr with ⟨rfl, hro⟩ | ⟨_, hrv⟩
          · have hout : ∀ w, callRen fn.params args base w ≠ args.getD v 0 := by
              intro w hw
              obtain ⟨b, t', hwp, hwe⟩ := h.ren_dom hw (h.argLt hvp)
              have := h.moving (lt_of_get hwp) hvp (by rw [get_of hwp]; rfl) hwe.symm
              subst this; rw [hv] at hwp; cases hwp
            exact ⟨hout, h.frame_root hEa hro hout⟩
          · exact hgen hrv
        · exact hgen (held_vdeps hr)
    · simp [roots, Entry.vdeps, Mode.ownSlot] at hr
  Φsat y E hy hl hn d hd v hv := by
    obtain ⟨hout, E1, h1, rfl⟩ := h.frame_some hy
    rw [clean_live] at hl
    have hn1 : E1.ty ≠ .int ∨ E1.mode = .rootb := by rwa [clean_ty, clean_mode] at hn
    rw [clean_id hn1] at hd
    have hyx : y ≠ x := by
      intro e; subst e; simp only [setE, upd_same, Option.some.injEq] at h1; subst h1; cases hl
    simp only [setE, upd_ne _ _ hyx] at h1
    -- the root lies in the caller's context, so it is an `inout` argument
    obtain ⟨Er, hEr, _⟩ := h.postwf y E1 h1 hl hn1 d.root (List.mem_map_of_mem hd)
    obtain ⟨b, t, hvp, hav⟩ := h.ren_dom hv (h.post_lt hEr)
    refine ⟨b, t.elem.holdsView, by simp [callS, bndOf, hvp], ?_⟩
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
        have := callPostAux_at fn.params args 0 k Γ hak hu hget rfl E1 h1
        simp only [postEnt] at this
        exact absurd (this.2.2.2.2 hl) (by simp)
    obtain ⟨E0, h0, ht0, hm0, hp0, hh0, hsv⟩ := callPostAux_frame fn.params args 0 Γ hmv E1 h1
    have hs := ((hsv hl).2 ((.inout b, t), args.getD v 0)
      (mem_zip_of hvp (h.len ▸ lt_of_get hvp))).2 b rfl
    have hn0 : E0.ty ≠ .int ∨ E0.mode = .rootb := by rwa [← ht0, ← hm0]
    have hd0 : d ∈ E0.vdeps := by unfold Entry.vdeps at hd ⊢; rwa [← hm0, ← hp0, ← hh0]
    exact hits_false_dep hs hn0 d hd0 hav.symm
  Φwf y E hy hl hn r hr hout := by
    obtain ⟨_, E1, h1, rfl⟩ := h.frame_some hy
    rw [clean_live] at hl
    have hn1 : E1.ty ≠ .int ∨ E1.mode = .rootb := by rwa [clean_ty, clean_mode] at hn
    rw [clean_id hn1] at hr
    have hyx : y ≠ x := by
      intro e; subst e; simp only [setE, upd_same, Option.some.injEq] at h1; subst h1; cases hl
    simp only [setE, upd_ne _ _ hyx] at h1
    obtain ⟨Er, hEr, hro⟩ := h.postwf y E1 h1 hl hn1 r hr
    rw [h.frame_of hout (h.post_ne_x hEr)]
    exact ⟨Er.clean, by rw [hEr]; rfl, by rw [clean_mode]; exact hro⟩
  Φρ v := by simp only [callS]; rw [if_pos ⟨v, rfl⟩]
  pe_held v := by
    show (callPe Γ fn.params args v).held ⊆ allKinds (callR Γ args)
    unfold callPe
    split
    · rename_i t hv
      split
      · simp
      · rename_i hn
        intro d hd
        refine RSetup.mem_allKinds_iff.mpr (mem_callR.mpr ⟨_, ?_, hn, List.mem_map_of_mem hd⟩)
        have hvl := lt_of_get hv
        simp [List.getD, show v < args.length from h.len ▸ hvl]
    · simp

end CallH

end A1
