import A1.Rename
import A1.Preservation

/-! A1 — the call step.

A call binds its parameters and runs the callee's body, renamed apart, inside
their scopes (`callStmt`).  The context it runs in is the caller's view of the
callee's own starting context (`RSetup.canon`): the renaming lemma types the
body there, and the summary the callee was checked against says what the
parameters' exits leave. -/

namespace A1

/-- `omega` reads facts about `Nat`; these restate facts about variables. -/
theorem vlt {a b : Var} (h : a < b) : @LT.lt Nat _ a b := h
theorem veq {a b : Var} (h : a = b) : @Eq Nat a b := h

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

/-- The dependencies of an integer, or of a dead binding, say nothing; the
    call forgets them. -/
def Entry.clean (E : Entry) : Entry :=
  if E.mode ≠ .rootb ∧ (E.ty = .int ∨ E.live = false) then { E with path := [], held := [] } else E

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

theorem callX_vdeps (fn : Fn) : (callX fn).vdeps = [] := by
  unfold Entry.vdeps callX; cases (resMode fn).ownSlot <;> rfl

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

theorem resMode_ne' (fn : Fn) : resMode fn ≠ .rootb := by unfold resMode; split <;> simp
theorem resMode_inout (fn : Fn) (b : Eff) : resMode fn ≠ .inout b := by unfold resMode; split <;> simp

theorem clean_mode (E : Entry) : E.clean.mode = E.mode := by unfold Entry.clean; split <;> rfl
theorem clean_ty (E : Entry) : E.clean.ty = E.ty := by unfold Entry.clean; split <;> rfl
theorem clean_live (E : Entry) : E.clean.live = E.live := by unfold Entry.clean; split <;> rfl
theorem clean_id {E : Entry} (h : E.ty ≠ .int ∨ E.mode = .rootb) (hl : E.live = true) : E.clean = E := by
  unfold Entry.clean; rw [if_neg]; rintro ⟨h1, h2 | h2⟩
  · rcases h with h | h <;> contradiction
  · rw [hl] at h2; cases h2

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
    rw [clean_id hn1 hl] at hd
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
    rw [clean_id hn1 hl] at hr
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

/-! ### The exits of the parameters' scopes -/

/-- The context after the parameters' scopes end, innermost first. -/
def exitsP : List (PMode × Ty) → Nat → Nat → (Var → Entry) → Ctx → Ctx
  | [], _, _, _, Δ => Δ
  | (.inp, _) :: ps, base, i, pe, Δ => exitRoot (base + i) (pe i).path (exitsP ps base (i + 1) pe Δ)
  | (.sink, _) :: ps, base, i, pe, Δ => exitScope (base + i) (exitsP ps base (i + 1) pe Δ)
  | (.inout _, _) :: ps, base, i, pe, Δ => exitsP ps base (i + 1) pe Δ

/-- What the exits make of a list of dependencies. -/
def rrL : List (PMode × Ty) → Nat → Nat → (Var → Entry) → List Dep → List Dep
  | [], _, _, _, L => L
  | (.inp, _) :: ps, base, i, pe, L => reroot (base + i) (pe i).path (rrL ps base (i + 1) pe L)
  | _ :: ps, base, i, pe, L => rrL ps base (i + 1) pe L

def rrE (ps : List (PMode × Ty)) (base i : Nat) (pe : Var → Entry) (E : Entry) : Entry :=
  { E with path := rrL ps base i pe E.path, held := rrL ps base i pe E.held }

/-- The condition for binding the parameters' scopes. -/
def WrapCond (Γ : Ctx) (Fc : List Var) (base : Nat) (pe : Var → Entry) (j : Nat) : PMode × Ty → Prop
  | (.inp, _) => ∃ E, Γ (base + j) = some E ∧ E.mode = .rootb ∧ E.live = true ∧
      (∀ r ∈ roots E.vdeps, r ∈ Fc) ∧ base + j ∉ Fc ∧ E.path = (pe j).path
  | (.sink, _) => (∃ E, Γ (base + j) = some E ∧ E.mode ≠ .rootb) ∧ base + j ∉ Fc
  | (.inout _, _) => True

theorem wrap_typed {P : Prog} {Γ : Ctx} {Fc : List Var} {base : Nat} {pe : Var → Entry} {s : Stmt}
    {Δ : Ctx} (hs : StmtT P Γ Fc s Δ) :
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
      have := StmtT.rbind (P := P) hE hm hl hr hF (ih (i + 1) hc')
      rw [hp] at this; exact this
    | sink =>
      obtain ⟨hE, hF⟩ := h0
      exact StmtT.scope hE hF (ih (i + 1) hc')
    | inout b => exact ih (i + 1) hc'

theorem mem_rrL {base : Nat} {pe : Var → Entry} (hpe : ∀ j, ∀ d ∈ (pe j).path, d.root < base) :
    ∀ (ps : List (PMode × Ty)) (i : Nat) (L : List Dep) {d' : Dep}, d' ∈ rrL ps base i pe L →
      (d' ∈ L ∧ ∀ k t, ps[k]? = some (.inp, t) → d'.root ≠ base + i + k) ∨
      (∃ k t, ps[k]? = some (.inp, t) ∧ ∃ kd, (⟨base + i + k, kd⟩ : Dep) ∈ L ∧
        ∃ d'' ∈ (pe (i + k)).path, d' = ⟨d''.root, comp d''.kind kd⟩) := by
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
          ∃ d'' ∈ (pe (i + 1 + k)).path, d' = ⟨d''.root, comp d''.kind kd⟩) →
        (d'.root ≠ base + i ∨ pm ≠ .inp) →
        (d' ∈ L ∧ ∀ k t', ((pm, t) :: ps)[k]? = some (.inp, t') → d'.root ≠ base + i + k) ∨
        (∃ k t', ((pm, t) :: ps)[k]? = some (.inp, t') ∧ ∃ kd, (⟨base + i + k, kd⟩ : Dep) ∈ L ∧
          ∃ d'' ∈ (pe (i + k)).path, d' = ⟨d''.root, comp d''.kind kd⟩) := by
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

theorem exits_at {base : Nat} {pe : Var → Entry} (hpe : ∀ j, ∀ d ∈ (pe j).path, d.root < base) :
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
      simp only [exitsP, A1.exitScope, upd_ne _ _ hne, A1.kill, hin, Option.map_some]
      congr 1
      unfold killE
      rw [if_neg]
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
          · simp only [hm, ho, Bool.false_eq_true, ↓reduceIte] at h1
            exact hL E.path (fun d0 h0 => by simp [Entry.vdeps, ho, h0]) h1
          · simp [hm, ho] at h1
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
      simp only [exitsP, A1.exitScope]
      by_cases hy : y = base + i
      · subst hy; simp
      · simp [upd_ne _ _ hy, A1.kill, hin]
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
      | sink => simp [exitsP, A1.exitScope]
      | inout b => exact absurd rfl (hp b)
    | succ k =>
      have hin := ih (i + 1) Δ k p (by simpa using hk) hp
      rw [show base + (i + 1) + k = base + i + (k + 1) by omega] at hin
      cases pm with
      | inp =>
        simp only [exitsP, exitRoot]
        by_cases hy : base + i + (k + 1) = base + i
        · omega
        · simp [upd_ne _ _ hy, hin]
      | sink =>
        simp only [exitsP, A1.exitScope]
        by_cases hy : base + i + (k + 1) = base + i
        · omega
        · simp [upd_ne _ _ hy, A1.kill, hin]
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
  unfold killE; rw [if_neg]
  intro hh; unfold hits at hh
  simp only [Bool.and_eq_true, List.any_eq_true, beq_iff_eq] at hh
  obtain ⟨_, d, hd, hr, _⟩ := hh
  exact h d hd hr

/-! ### The callee's starting context, as the caller sees it -/

theorem sigCtx_of {fn : Fn} {v : Nat} {p : PMode × Ty} (hp : fn.params[v]? = some p) :
    sigCtx fn v = some (paramE p) := by
  have hv : v < fn.params.length := (List.getElem?_eq_some_iff.mp hp).1
  simp [sigCtx, hv, (List.getElem?_eq_some_iff.mp hp).2]

theorem sigCtx_res (fn : Fn) : sigCtx fn fn.params.length = some ⟨fn.resTy, resMode fn, false, [], []⟩ := by
  simp [sigCtx]

theorem sigCtx_none {fn : Fn} {v : Nat} (hv : fn.params.length < v) : sigCtx fn v = none := by
  simp [sigCtx, show ¬ v < fn.params.length by omega, show v ≠ fn.params.length by omega]

theorem sigCtx_wf (fn : Fn) : CtxWF (sigCtx fn) := by
  intro v E hv _ _ r hr
  unfold sigCtx at hv
  split at hv
  · rename_i h
    simp only [Option.some.injEq] at hv; subst hv
    generalize fn.params[v] = p at hr
    obtain ⟨pm, t⟩ := p
    cases pm <;> simp [paramE, roots, Entry.vdeps, Mode.ownSlot] at hr
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
        obtain ⟨_, hvec⟩ := hpar _ hmem
        obtain ⟨s, rfl⟩ := hvec (by simp)
        exact ⟨s, rfl, by simp [callS, bndOf, hget, Ty.elem]⟩
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
      exact ⟨_, sigCtx_of hget, rfl⟩
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
  rw [if_neg (fun ⟨v, hv⟩ => h.x_notRen v hv)]
  simp [setE, Entry.clean, callX]

theorem ren_res (fn : Fn) (args : List Var) (base : Nat) :
    callRen fn.params args base fn.params.length = base + fn.params.length := by
  unfold callRen; simp

theorem pe_lt (h : CallH P Γ F x fn args base) (j : Nat) :
    ∀ d ∈ (callPe Γ fn.params args j).path, d.root < base := by
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
      rcases derive_roots_cases (List.mem_map_of_mem (f := Dep.root) hd) with ⟨hr, _⟩ | ⟨_, hrv⟩
      · rw [hr]; exact h.argLt hjl
      · obtain ⟨Er, hEr, _⟩ := h.wf _ Ea hEa hl (Or.inl hn) _ hrv
        exact h.domlt _ _ hEr
  · simp at hd

theorem frame_lt (h : CallH P Γ F x fn args base) {r : Var} {E : Entry}
    (hr : (callS Γ F fn args base x).Φ r = some E) : r < base := by
  obtain ⟨_, E1, h1, _⟩ := h.frame_some hr
  by_cases hrx : r = x
  · rw [hrx]; exact h.xlt
  · simp only [setE, upd_ne _ _ hrx] at h1; exact h.post_lt h1

theorem notRen_z (h : CallH P Γ F x fn args base) {r : Var} (hout : ∀ w, callRen fn.params args base w ≠ r)
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

/-- The roots an `in` parameter's entry depends on are lent out for the call. -/
theorem pe_Fc (h : CallH P Γ F x fn args base) (j : Nat) :
    ∀ r ∈ roots (callPe Γ fn.params args j).vdeps, r ∈ F ++ zOf fn args base := by
  intro r hr
  obtain ⟨hout, Er, hEr, _⟩ := h.sOK.pe_out j r hr
  exact List.mem_append_right _ (h.notRen_z hout (h.frame_lt hEr))

theorem wrapCond (h : CallH P Γ F x fn args base) :
    ∀ k p, fn.params[k]? = some p →
      WrapCond ((callS Γ F fn args base x).canon (sigCtx fn)) (F ++ zOf fn args base) base
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
        some ((callS Γ F fn args base x).liftE k (paramE (pm, t))) := by
    intro hne
    rw [← hρ hne]
    show (callS Γ F fn args base x).canon (sigCtx fn) ((callS Γ F fn args base x).ρ k) = _
    rw [RSetup.canon_ρ h.sOK, sigCtx_of hk]; rfl
  have hF : (∀ b' t', (pm, t) ≠ (.inout b', t')) → base + k ∉ F ++ zOf fn args base := by
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
    · intro r hr
      have : ((callS Γ F fn args base x).liftE k (paramE (.inp, t))).vdeps =
          (callPe Γ fn.params args k).vdeps := by simp [RSetup.liftE, paramE, Entry.vdeps, callS]
      rw [this] at hr
      exact h.pe_Fc k r hr
    · simp [RSetup.liftE, paramE, callS]
  | sink =>
    have hne : ∀ b' t', (PMode.sink, t) ≠ (.inout b', t') := fun _ _ h => by cases h
    exact ⟨⟨_, hc hne, by simp [RSetup.liftE, paramE, liftMode]⟩, hF hne⟩
  | inout b => trivial

/-- The call's expansion is well-typed, given what its parameters' exits
    leave (`hfin`). -/
theorem typed_of (h : CallH P Γ F x fn args base) {k : Stmt} {Δ : Ctx} (hk : k.src = true)
    {Δa : Ctx} (hbody : StmtT P ((callS Γ F fn args base x).canon (sigCtx fn)) (F ++ zOf fn args base)
      (fn.body.rename (callRen fn.params args base)) ((callS Γ F fn args base x).canon Δa))
    {Er' : Entry}
    (hr : exitsP fn.params base 0 (callPe Γ fn.params args) ((callS Γ F fn args base x).canon Δa)
      (base + fn.params.length) = some Er')
    (hrl : Er'.live = true) (hrm : Er'.mode = resMode fn) (hrt : Er'.ty = fn.resTy)
    (hxr : x ∉ roots Er'.vdeps)
    (hfin : ∀ Γ3, (Γ3 = setE (A1.kill .replace false x
          (if fn.resOwn then setE (A1.kill .replace false (base + fn.params.length)
              (exitsP fn.params base 0 (callPe Γ fn.params args) ((callS Γ F fn args base x).canon Δa)))
            (base + fn.params.length) { Er' with live := false }
           else exitsP fn.params base 0 (callPe Γ fn.params args) ((callS Γ F fn args base x).canon Δa)))
          x (if fn.resOwn then { (⟨Er'.ty, .own, true, [], Er'.held⟩ : Entry) with mode := resMode fn }
             else { Er' with mode := resMode fn })) →
      Weaker (exitScope (base + fn.params.length) Γ3) (setE (callPost Γ fn args) x (callRes Γ fn args)))
    (hkT : StmtT P (setE (callPost Γ fn args) x (callRes Γ fn args)) F k Δ) :
    StmtT P ((callS Γ F fn args base x).canon (sigCtx fn)) F (callStmt fn args base x k) (exitScope x Δ) := by
  have hwrap := wrap_typed (pe := callPe Γ fn.params args) (base := base) hbody fn.params 0 h.wrapCond
  have hfz := StmtT.frozen (z := zOf fn args base) hwrap
  generalize hΓb : exitsP fn.params base 0 (callPe Γ fn.params args) ((callS Γ F fn args base x).canon Δa) = Γb
    at hfz hr hfin
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
      (setE (A1.kill .replace false x
          (if fn.resOwn then setE (A1.kill .replace false (base + fn.params.length) Γb)
            (base + fn.params.length) { Er' with live := false } else Γb))
        x (if fn.resOwn then { (⟨Er'.ty, .own, true, [], Er'.held⟩ : Entry) with mode := resMode fn }
           else { Er' with mode := resMode fn })) := by
    cases ho : fn.resOwn with
    | true =>
      have hm : Er'.mode = .own := by rw [hrm]; simp [resMode, ho]
      have hrhs := RhsT.moveOwn (F := F) hr hrl hm hrF
      have hX : (callX fn).mode = .own := by simp [callX, resMode, ho]
      refine StmtT.seq rfl hfz (StmtT.assign hbx h.xF (Or.inl ⟨hX, rfl⟩) hrhs
        (by simp [callX, hrt]) ?_ (by simp [setE, upd_ne _ _ hxr', A1.kill, hbx]))
      have hv : (⟨Er'.ty, .own, true, [], Er'.held⟩ : Entry).vdeps = Er'.vdeps := by
        simp [Entry.vdeps, hm, Mode.ownSlot]
      rw [hv]; exact hxr
    | false =>
      have hm : Er'.mode = .bor := by rw [hrm]; simp [resMode, ho]
      have hrhs := RhsT.copyBor (F := F) hr hrl hm
      have hX : (callX fn).mode = .bor := by simp [callX, resMode, ho]
      exact StmtT.seq rfl hfz (StmtT.assign hbx h.xF (Or.inr (Or.inr ⟨hX, hm⟩)) hrhs
        (by simp [callX, hrt]) hxr (by simp [hbx]))
  have hscr := StmtT.scope (⟨_, by
      rw [show base + fn.params.length = callRen fn.params args base fn.params.length from
        (ren_res fn args base).symm]
      show (callS Γ F fn args base x).canon (sigCtx fn) ((callS Γ F fn args base x).ρ _) = _
      rw [RSetup.canon_ρ h.sOK, sigCtx_res]; rfl, by
      rw [RSetup.liftE_mode _ (resMode_ne' fn), RSetup.liftMode_resMode]; exact resMode_ne' fn⟩) hrF hseq
  have hw := hfin _ rfl
  have hsq := StmtT.seq hk hscr (StmtT.weakenIn hw hkT)
  exact StmtT.scope ⟨callX fn, h.canon_x _, by simp [callX, resMode_ne' fn]⟩ h.xF hsq

end CallH

end A1
