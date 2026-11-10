import A2.DynCell

/-! # A2-drop.3a: the destructor on the type, checked

Two kinds of fact, both checked here (`check.sh` prints their axioms):

* **The guarantee of the typing** (`A2.Dtor.*`): every binder of an owned
  value of a destructor type (or of a struct or an enum holding one) either
  is a `letd`, whose scope is a `scopeD` frame, or hands the value to one
  first thing (`Stmt.movedFirst`); a `letd`'s value is of the destructor type,
  whose function is a `DtorOK` destructor, and the binding is assigned nothing
  in its scope (`Stmt.assigns`).  A typed `scopeD` frame whose binding still
  owns its value at its end has exactly one step: it runs that destructor on
  the binding lent, then frees the tree (`Step.scopeDEnd`).
* **A witness** (`A2.DtorWitness`): a program with a destructor type, its
  destructor, a function handing back an owned value of that type, and two
  callers (`main`: a `letd` of a struct literal; `main2`: a call's result
  handed to its `letd`), all typed, with `memory_safe` applied: the premises
  the cut adds are satisfiable.  `lock_checkout_assign` types the gap the
  docs list (a lock check-out binding of a destructor type is assigned, its
  old value dropped with no destructor: A2-drop.3d).
-/

namespace A2.Dtor

/-- `skip` has no step. -/
theorem skip_no_step {P : Prog} {m : Mem} {r : Res} (h : Step P m .skip r) : False := by
  cases h with
  | waitPanic hw => exact hw

/-- A typed `letv` binds no owned value of a destructor type (nor of a struct
    or an enum holding one). (In the context its rule was applied in, under
    any `sub`sumptions.) -/
theorem letv_owned_no_dtor {P : Prog} {Γ Δ : Ctx} {F : List Var} {x : Var} {r : Rhs} {s : Stmt}
    (h : StmtT P Γ F (.letv x r s) Δ) :
    ∃ Γ0 E Γ1, RhsT Γ0 F r E Γ1 ∧ (E.mode = .own → E.ty.holdsDtor = false) := by
  generalize hst : Stmt.letv x r s = st at h
  induction h with
  | letv _ _ _ hr _ _ hnd => cases hst; exact ⟨_, _, _, hr, hnd⟩
  | sub _ _ _ ih => exact ih hst
  | _ => cases hst

/-- A typed call's owned result of a destructor type is handed to its `letd`
    first thing, and the result binding is assigned nothing. -/
theorem letcall_hands_over {P : Prog} {Γ Δ : Ctx} {F : List Var} {x : Var} {f : Nat}
    {args : List Var} {s : Stmt} (h : StmtT P Γ F (.letcall x f args s) Δ) :
    ∀ fn, P[f]? = some fn → fn.resOwn = true → fn.resTy.holdsDtor = true →
      x ∈ s.movedFirst ∧ x ∉ s.assigns := by
  generalize hst : Stmt.letcall x f args s = st at h
  induction h with
  | letcall _ _ _ _ _ _ hdk => cases hst; exact hdk
  | sub _ _ _ ih => exact ih hst
  | _ => cases hst

/-- A typed `unpair`'s field of a destructor type is handed to its `letd`
    first thing. -/
theorem unpair_hands_over {P : Prog} {Γ Δ : Ctx} {F : List Var} {y x z : Var} {s : Stmt}
    (h : StmtT P Γ F (.unpair y x z s) Δ) :
    ∃ a b : Ty, (a.holdsDtor = true → x ∈ s.movedFirst ∧ x ∉ s.assigns) ∧
      (b.holdsDtor = true → z ∈ s.movedFirst ∧ z ∉ s.assigns) := by
  generalize hst : Stmt.unpair y x z s = st at h
  induction h with
  | unpair _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ hdx hdz => cases hst; exact ⟨_, _, hdx, hdz⟩
  | sub _ _ _ ih => exact ih hst
  | _ => cases hst

/-- A typed `letd` binds a value of the destructor type `Ty.dtor f t` (`t` a
    struct or an enum), `f` is a destructor of it (`DtorOK`), and the binding
    is assigned nothing in its scope. -/
theorem letd_dtor {P : Prog} {Γ Δ : Ctx} {F : List Var} {x : Var} {f : Nat} {r : Rhs} {s : Stmt}
    (h : StmtT P Γ F (.letd x f r s) Δ) :
    ∃ t, t.isStruct = true ∧ DtorOK P f (.dtor f t) ∧ x ∉ s.assigns := by
  generalize hst : Stmt.letd x f r s = st at h
  induction h with
  | letd _ _ _ _ _ _ hst' _ hok _ _ _ hna => cases hst; exact ⟨_, hst', hok, hna⟩
  | sub _ _ _ ih => exact ih hst
  | _ => cases hst

/-- **The scope end of a destructor frame runs the destructor.** In a typed
    `scopeD x f` frame, `f` is a destructor (`DtorOK`) of `x`'s type, a
    destructor type `Ty.dtor f t`; when its body is done and `x` still owns its value, the frame's
    one step runs `f` on `x` lent, then `scope x` frees the tree. -/
theorem scopeD_end_runs_dtor {P : Prog} {Γ Δ : Ctx} {F : List Var} {x : Var} {f : Nat}
    {m : Mem} {v : Val} (ht : StmtT P Γ F (.scopeD x f .skip) Δ)
    (hx : m.st x = some ⟨true, some v⟩) :
    (∃ t, DtorOK P f (.dtor f t)) ∧
      Step P m (.scopeD x f .skip) (.ok { m with nv := m.nv + 1 } (.scope x (.letcall m.nv f [x] .skip))) ∧
      ∀ r, Step P m (.scopeD x f .skip) r →
        r = .ok { m with nv := m.nv + 1 } (.scope x (.letcall m.nv f [x] .skip)) := by
  refine ⟨?_, Step.scopeDEnd hx, fun r h => ?_⟩
  · generalize hst : Stmt.scopeD x f .skip = st at ht
    induction ht with
    | scopeD hE _ _ _ _ _ _ _ =>
      cases hst
      obtain ⟨E, t, _, _, h3, _, h5⟩ := hE
      exact ⟨t, h3 ▸ h5⟩
    | sub _ _ _ ih => exact ih hst
    | _ => cases hst
  · cases h with
    | scopeDIn hs => exact (skip_no_step hs).elim
    | scopeDEnd _ => rfl
    | scopeDMoved hm => rw [hx] at hm; cases hm
    | scopeDP hs _ => exact (skip_no_step hs).elim
    | scopeDPMoved hs _ => exact (skip_no_step hs).elim
    | waitPanic hw => exact hw.elim

/-- …and on the panic path: a panic out of the body with `x` still owning
    its value stops at the frame, runs `f` on `x`, frees it, and raises again. -/
theorem scopeD_panic_runs_dtor {P : Prog} {x : Var} {f : Nat} {m m1 : Mem} {s : Stmt} {v : Val}
    (hs : Step P m s (.panic m1)) (hx : m1.st x = some ⟨true, some v⟩) :
    Step P m (.scopeD x f s)
      (.ok { m1 with nv := m1.nv + 1 } (.seq (.scope x (.letcall m1.nv f [x] .skip)) .panic)) :=
  Step.scopeDP hs hx

end A2.Dtor


namespace A2.DtorWitness
open A2.DynCell (NoRootb noRootb_empty)

def T : Ty := .prod .int .int
def DT : Ty := .dtor 0 T

/-- destructor: `@ drop in self → i { = r 0 }` -/
def dfn : Fn where
  params := [(.inp, DT)]
  resTy := .int
  resOwn := false
  lends := []
  rholds := []
  outHolds := []
  body := .assign 1 (.expr (.lit 0))
  nvars := 2

/-- maker: `@ mk → DT { : a 1  : b 2  :drop w ( pair a b )  = r w }` (result slot 0) -/
def mk : Fn where
  params := []
  resTy := DT
  resOwn := true
  lends := []
  rholds := []
  outHolds := []
  body := .letv 1 (.expr (.lit 1)) (.letv 2 (.expr (.lit 2)) (.letd 3 0 (.pair 1 2) (.assign 0 (.var 3))))
  nvars := 4

def P : Prog := [dfn, mk]

theorem dfn_not_thru : ¬ ThruFn P 0 := by
  intro h
  cases h with
  | here hf hb => simp [P] at hf; subst hf; simp [dfn, Stmt.hasThru] at hb
  | call hf hg _ => simp [P] at hf; subst hf; simp [dfn, Stmt.calls] at hg

theorem dtor_ok : DtorOK P 0 DT :=
  ⟨dfn, rfl, rfl, rfl, rfl, rfl, rfl, rfl, dfn_not_thru⟩

/-- `: a 1  : b 2  :drop x ( pair a b )` -/
def main : Stmt := .letv 0 (.expr (.lit 1)) (.letv 1 (.expr (.lit 2)) (.letd 2 0 (.pair 0 1) .skip))

def EP : Entry := ⟨T, .own, true, [], [] ++ [], false, false⟩

theorem main_typed : ∃ Δ, StmtT P (fun _ => none) [] main Δ := by
  let K1 : Ctx := A2.setE (fun _ => none) 0 intE
  let K2 : Ctx := A2.setE K1 1 intE
  have hK1 : NoRootb K1 := noRootb_empty.setE (by simp [intE])
  have hK2 : NoRootb K2 := hK1.setE (by simp [intE])
  let ED : Entry := Entry.arm { EP with ty := DT, held := [] }
  have hED : ED.mode ≠ .rootb ∧ ED.dtor = false ∧ ED.dbind = false := by
    simp [ED, EP, Entry.arm, DT, T, Ty.dtorViews, Ty.hasDtor, Ty.holdsView]
  have hK3 : NoRootb (A2.setE K2 2 ED) := hK2.setE hED
  have hpair : RhsT K2 [] (.pair 0 1) EP K2 :=
    RhsT.pair (Ey := intE) (Ez := intE) (by simp [K2, K1, A2.setE, upd]) rfl PushArg.int
      (by simp [K2, K1, A2.setE, upd]) rfl PushArg.int (by simp [intE, Mode.ownSlot])
  have hd := StmtT.letd (P := P) (Γ := K2) (Γ1 := K2) (F := []) (x := 2) (f := 0) (r := .pair 0 1)
    (s := .skip) (E := EP) (t := T) (H := []) rfl (by simp [K2, K1, A2.setE, upd]) (by simp) hpair rfl
    (Or.inl rfl) rfl rfl dtor_ok (HeldUp.refl _ _) StmtT.skip (hK3.endOK _)
  have h1 := StmtT.letv (P := P) (x := 1) (r := .expr (.lit 2)) (E := intE) (F := []) (Γ := K1) (Γ1 := K1)
    rfl (by simp [K1, A2.setE, upd]) (by simp) (RhsT.expr ExprT.lit) hd ((hK3.exitScope 2).endOK _)
  exact ⟨_, StmtT.letv (P := P) (x := 0) (r := .expr (.lit 1)) (E := intE) (F := []) (Γ := fun _ => none)
    (Γ1 := fun _ => none) rfl rfl (by simp) (RhsT.expr ExprT.lit) h1
    (((hK3.exitScope 2).exitScope 1).endOK _)⟩


/-! ### The destructor's own FnOK -/

def R0 : Entry := ⟨.int, .bor, false, [], [], false, false⟩
def Epar : Entry := ⟨DT, .rootb, true, [], [], false, false⟩

theorem dfn_body : StmtT P (sigCtx dfn) [] dfn.body
    (setE (kill .replace false 1 (sigCtx dfn)) 1 { intE with mode := R0.mode }) := by
  have hc : sigCtx dfn 1 = some R0 := by simp [sigCtx, dfn, R0, resMode]
  have hflags : ∀ v E, sigCtx dfn v = some E → E.dtor = false ∧ E.dbind = false := by
    intro v E h
    rcases v with _ | _ | v <;> simp [sigCtx, dfn, paramE, resMode] at h <;> subst h <;> exact ⟨rfl, rfl⟩
  exact StmtT.assign (Ex := R0) (E := intE) hc (by simp) (Or.inr (Or.inr ⟨rfl, rfl⟩))
    (RhsT.expr ExprT.lit) rfl (by simp [intE, roots, Entry.vdeps, Mode.ownSlot]) (by simp [hc])
    (by
      intro p E hp hm d hd _
      rcases p with _ | _ | p <;> simp [sigCtx, dfn, paramE, resMode, DT, T, Ty.hasFn] at hp <;> subst hp <;>
        simp [Entry.vdeps, Mode.ownSlot] at hd <;> simp at hm)
    (DtorSafe.of_none (fun v E h => (hflags v E h).1) _ _ _) rfl

theorem dfn_ok : FnOK P dfn := by
  refine ⟨rfl, by decide, by decide, rfl, by simp [dfn], ?_, by simp [dfn], by simp [dfn], by simp [dfn],
    by simp [dfn], by simp [dfn], ?_, _, dfn_body, ?_, ?_, ?_⟩
  · intro pt hpt; simp [dfn] at hpt; subst hpt; simp [DT, T, Ty.ok, Ty.isStruct]
  · refine ⟨fun i hi hs _ => ?_, fun i hi b hb _ => ?_, fun h => by simp [dfn] at h⟩
    · simp [dfn] at hi; subst hi; simp [dfn] at hs
    · simp [dfn] at hi; subst hi; simp [dfn] at hb
  · intro v E h
    rcases v with _ | _ | v <;> simp [setE, upd, kill, killE, sigCtx, dfn, paramE, resMode, intE] at h <;>
      subst h <;> exact ⟨rfl, rfl⟩
  · exact ⟨{ intE with mode := R0.mode }, by simp [setE, upd, dfn], rfl, rfl, by simp [R0, resMode, dfn], by simp [intE], by simp [intE],
      by simp [dfn]⟩
  · intro i hi b hb; simp [dfn] at hi; subst hi; simp [dfn] at hb


/-! ### The maker: a function whose owned result is a destructor value -/

def Rr : Entry := ⟨DT, .own, false, [], [], false, false⟩
def EDd : Entry := Entry.arm { EP with ty := DT, held := [] }

theorem EDd_eq : EDd = ⟨DT, .own, true, [], [], false, false⟩ := by
  simp [EDd, EP, Entry.arm, DT, T, Ty.dtorViews, Ty.hasDtor, Ty.holdsView]

theorem sig_mk : sigCtx mk = A2.setE (fun _ => none) 0 Rr := by
  funext v; rcases v with _ | v <;> simp [sigCtx, mk, resMode, Rr, A2.setE, upd]

theorem mk_typed : ∃ Δ, StmtT P (sigCtx mk) [] mk.body Δ ∧ NoRootb Δ ∧
    Δ 0 = some ⟨DT, .own, true, [], [], false, false⟩ := by
  rw [sig_mk]
  let S : Ctx := A2.setE (fun _ => none) 0 Rr
  have hS : NoRootb S := noRootb_empty.setE (by simp [Rr])
  let C1 : Ctx := A2.setE S 1 intE
  let C2 : Ctx := A2.setE C1 2 intE
  have hC2 : NoRootb C2 := (hS.setE (by simp [intE])).setE (by simp [intE])
  let C3 : Ctx := A2.setE C2 3 EDd
  have hC3 : NoRootb C3 := hC2.setE (by rw [EDd_eq]; simp)
  have hmv : RhsT C3 [] (.var 3) ⟨DT, .own, true, [], [], false, false⟩
      (A2.setE (kill .replace false 3 C3) 3 { EDd with live := false, dtor := false }) := by
    have := RhsT.moveOwn (Γ := C3) (F := []) (y := 3) (E := EDd) (by simp [C3, A2.setE, upd]) (by rw [EDd_eq])
      (by rw [EDd_eq]) (by simp) (hC3.noPin _) (DtorSafe.of_none (fun v E h => (hC3 v E h).2.1) _ _ _)
    rw [EDd_eq] at this ⊢; exact this
  let G1 : Ctx := A2.setE (kill .replace false 3 C3) 3 { EDd with live := false, dtor := false }
  have hG1 : NoRootb G1 := (hC3.kill _ _ _).setE (by rw [EDd_eq]; simp)
  have ha := StmtT.assign (P := P) (Γ := C3) (F := []) (x := 0) (r := .var 3) (Ex := Rr)
    (E := ⟨DT, .own, true, [], [], false, false⟩) (Γ1 := G1)
    (by simp [C3, C2, C1, S, A2.setE, upd]) (by simp) (Or.inl ⟨rfl, rfl⟩) hmv rfl
    (by simp [roots, Entry.vdeps, Mode.ownSlot]) (by simp [G1, C3, C2, C1, S, A2.setE, upd, kill]) (hC3.noPin _)
    (DtorSafe.of_none (fun v E h => (hG1 v E h).2.1) _ _ _) rfl
  let Da : Ctx := A2.setE (kill .replace false 0 G1) 0 { (⟨DT, .own, true, [], [], false, false⟩ : Entry) with mode := Rr.mode }
  have hDa : NoRootb Da := (hG1.kill _ _ _).setE (by simp [Rr])
  have hpair : RhsT C2 [] (.pair 1 2) EP C2 :=
    RhsT.pair (Ey := intE) (Ez := intE) (by simp [C2, C1, A2.setE, upd]) rfl PushArg.int
      (by simp [C2, A2.setE, upd]) rfl PushArg.int (by simp [intE, Mode.ownSlot])
  have hd := StmtT.letd (P := P) (Γ := C2) (Γ1 := C2) (F := []) (x := 3) (f := 0) (r := .pair 1 2)
    (s := .assign 0 (.var 3)) (E := EP) (t := T) (H := []) rfl (by simp [C2, C1, S, A2.setE, upd]) (by simp)
    hpair rfl (Or.inl rfl) rfl rfl dtor_ok (HeldUp.refl _ _) ha (hDa.endOK _)
  have h2 := StmtT.letv (P := P) (x := 2) (r := .expr (.lit 2)) (E := intE) (F := []) (Γ := C1) (Γ1 := C1)
    rfl (by simp [C1, S, A2.setE, upd]) (by simp) (RhsT.expr ExprT.lit) hd ((hDa.exitScope 3).endOK _)
  have h1 := StmtT.letv (P := P) (x := 1) (r := .expr (.lit 1)) (E := intE) (F := []) (Γ := S) (Γ1 := S)
    rfl (by simp [S, A2.setE, upd]) (by simp) (RhsT.expr ExprT.lit) h2 (((hDa.exitScope 3).exitScope 2).endOK _)
  refine ⟨_, h1, ((hDa.exitScope 3).exitScope 2).exitScope 1, ?_⟩
  simp [Da, G1, C3, C2, C1, S, exitScope, A2.setE, upd, kill, killE, hits, Rr, Entry.vdeps, Mode.ownSlot]

theorem mk_ok : FnOK P mk := by
  obtain ⟨Δ, ht, hn, h0⟩ := mk_typed
  refine ⟨rfl, by decide, by decide, by simp [mk, DT, T, Ty.ok, Ty.isStruct], fun _ => rfl, by simp [mk],
    by simp [mk], by simp [mk], by simp [mk], by simp [mk], by simp [mk], ?_, Δ, ht,
    fun v E h => ⟨(hn v E h).2.1, (hn v E h).2.2⟩, ⟨_, h0, rfl, rfl, rfl, by simp, by simp, fun _ _ => rfl⟩,
    fun i hi => by simp [mk] at hi⟩
  refine ⟨fun i hi => by simp [mk] at hi, fun i hi => by simp [mk] at hi, fun _ _ => ?_⟩
  decide

theorem prog_ok : ProgOK P := by
  intro fn hfn
  simp only [P, List.mem_cons, List.mem_nil_iff, or_false] at hfn
  rcases hfn with rfl | rfl
  · exact dfn_ok
  · exact mk_ok

/-! ### The caller: `: DT y ( mk )  :drop z y` -/

def main2 : Stmt := .letcall 0 1 [] (.letd 1 0 (.var 0) .skip)

def Ecr : Entry := ⟨DT, .own, true, [], [], false, false⟩

theorem main2_typed : ∃ Δ, StmtT P (fun _ => none) [] main2 Δ := by
  have hpost : callPost (fun _ => none) mk [] = fun _ => none := by
    funext v; simp [callPost, callPostAux, mk, killNames, mutNames, argNames]
  have hres : callRes (fun _ => none) mk [] = Ecr := by
    simp [callRes, mk, resMode, Ecr, heldOfArgs, ownHeld, allKinds, argNames]
  have hc : CallT P (fun _ => none) [] 1 [] Ecr (fun _ => none) := by
    refine ⟨mk, rfl, rfl, fun i hi => by simp [mk] at hi, ?_, CallDtorSafe.of_none (fun _ _ h => by cases h) _ _,
      hres.symm, hpost.symm, fun _ => by simp [callR]⟩
    intro d hd; simp [mutNames, argNames] at hd
  let K : Ctx := A2.setE (fun _ => none) 0 Ecr
  have hK : NoRootb K := noRootb_empty.setE (by simp [Ecr])
  have hmv := RhsT.moveOwn (Γ := K) (F := []) (y := 0) (E := Ecr) (by simp [K, A2.setE, upd]) rfl rfl (by simp)
    (hK.noPin _) (DtorSafe.of_none (fun v E h => (hK v E h).2.1) _ _ _)
  let K1 : Ctx := A2.setE (kill .replace false 0 K) 0 { Ecr with live := false, dtor := false }
  have hK1 : NoRootb K1 := (hK.kill _ _ _).setE (by simp [Ecr])
  let ED2 : Entry := Entry.arm { (⟨Ecr.ty, .own, true, [], Ecr.held, false, false⟩ : Entry) with ty := DT, held := Ecr.held }
  have hED2 : ED2.mode ≠ .rootb ∧ ED2.dtor = false ∧ ED2.dbind = false := by
    simp [ED2, Ecr, Entry.arm, DT, T, Ty.dtorViews, Ty.hasDtor, Ty.holdsView]
  have hK2 : NoRootb (A2.setE K1 1 ED2) := hK1.setE hED2
  have hd := StmtT.letd (P := P) (Γ := K) (Γ1 := K1) (F := []) (x := 1) (f := 0) (r := .var 0) (s := .skip)
    (t := T) (H := Ecr.held) rfl (by simp [K, A2.setE, upd]) (by simp) hmv rfl (Or.inr rfl) rfl rfl dtor_ok
    (HeldUp.refl _ _) StmtT.skip (hK2.endOK _)
  exact ⟨_, StmtT.letcall (P := P) (Γ := fun _ => none) (F := []) (x := 0) (f := 1) (args := [])
    (s := .letd 1 0 (.var 0) .skip) (E := Ecr) (Γ1 := fun _ => none) rfl rfl (by simp) hc hd
    ((hK2.exitScope 1).endOK _)
    (fun fn hf _ _ => by simp [P] at hf; subst hf; simp [Stmt.movedFirst, Stmt.assigns])⟩

theorem prog_codes : ProgCodes P := by
  intro fn hfn
  simp only [P, List.mem_cons, List.mem_nil_iff, or_false] at hfn
  rcases hfn with rfl | rfl <;> simp [dfn, mk, Stmt.codesOK, Rhs.codeOK]

theorem main2_safe {m' : Mem} {s' : Stmt} (hr : Steps P (emptyMem 2) main2 (.ok m' s')) :
    ¬ Stuck P m' s' := by
  obtain ⟨Δ, ht⟩ := main2_typed
  exact memory_safe prog_ok prog_codes ht rfl (by simp [main2, Stmt.codesOK, Rhs.codeOK]) (by decide) hr

theorem main_safe {m' : Mem} {s' : Stmt} (hr : Steps P (emptyMem 3) main (.ok m' s')) :
    ¬ Stuck P m' s' := by
  obtain ⟨Δ, ht⟩ := main_typed
  exact memory_safe prog_ok prog_codes ht rfl (by simp [main, Stmt.codesOK, Rhs.codeOK]) (by decide) hr



/-- A lock payload checked out to `x` (`withLock`, `lockE`) of a destructor type is
    an owned binding of that type that is no `letd`'s, and `assign` gives it a new
    value: the old one is dropped by `DropSlot`, running no destructor. -/
theorem lock_checkout_assign :
    let Γ : Ctx := A2.setE (A2.setE (fun _ => none) 0 (lockE DT)) 1 Ecr
    ∃ Δ, StmtT P Γ [] (.assign 0 (.var 1)) Δ := by
  intro Γ
  have hl : lockE DT = Ecr := by simp [lockE, DT, Ecr]
  have hK : NoRootb Γ := (noRootb_empty.setE (by rw [hl]; simp [Ecr])).setE (by simp [Ecr])
  have hmv := RhsT.moveOwn (Γ := Γ) (F := []) (y := 1) (E := Ecr) (by simp [Γ, A2.setE, upd]) rfl rfl (by simp)
    (hK.noPin _) (DtorSafe.of_none (fun v E h => (hK v E h).2.1) _ _ _)
  have hK1 : NoRootb (A2.setE (kill .replace false 1 Γ) 1 { Ecr with live := false, dtor := false }) :=
    (hK.kill _ _ _).setE (by simp [Ecr])
  exact ⟨_, StmtT.assign (Ex := lockE DT) (by simp [Γ, A2.setE, upd]) (by simp) (Or.inl ⟨by rw [hl]; rfl, rfl⟩)
    hmv (by rw [hl]) (by simp [roots, Entry.vdeps, Mode.ownSlot, Ecr]) (by simp [A2.setE, upd, kill, Γ])
    (hK.noPin _) (DtorSafe.of_none (fun v E h => (hK1 v E h).2.1) _ _ _) (by rw [hl]; rfl)⟩


end A2.DtorWitness
