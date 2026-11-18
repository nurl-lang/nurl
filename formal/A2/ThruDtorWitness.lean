import A2.DtorWitness
import A2.ThruClosureWitness

/-! # A destructor that changes elements through a borrow of its own local

    : D { i a  i b }
    % Drop D { @ drop D d → v {
        : ( Vec ( Vec i ) ) loc ( vec_new … )
        ( vec_push loc ( vec_new [i] ) )
        ( vec_push [i] ( vec_at loc 0 ) 7 )   -- a push THROUGH a borrow of loc's element
    } }
    : a 1  : b 2  :drop x ( D a b )

A destructor whose code changes elements through a borrow (`ThruFn`, Agora
#295).  Before, `DtorOK` refused such code outright (`¬ ThruFn P f`).  Now a
destructor may be through-changing when the type it runs on holds no views
(`ThruFn P f → t.holdsView = false`): that is `CallT`'s `ThruFn` premise for
the call the frame's end makes, no argument holding views.  At the end of
the `letd`'s frame the value is revived holding nothing — no `letd` of a type
that holds no views records any (`CtxWF.view`) — so the call passes none
(`Step.scopeDEnd`'s case of `preserve`).

A program of one function:

* `dtor` (0): the destructor of `DT = Ty.dtor 0 (prod int int)`, which takes
  the value lent; its body is `ThruClosureWitness`'s through-changing body,
  `7` pushed through the borrow `( vec_at loc 0 )` (`StmtT.editB`), typed
  in this program (`thru_typed` holds in any program: it calls nothing);

typed (`prog_ok`), a destructor with `ThruFn` true (`dtor_thru`, `dtor_ok`),
and the caller

    : a 1  : b 2  :drop x ( pair a b )

typed from nothing (`main_typed`), with `memory_safe` and `no_leak_end`
applied (`main_safe`, `main_no_leak`): the frame's end runs the destructor,
which allocates `loc` and its element and frees them.
-/

namespace A2.ThruDtorWitness
open A2.DynCell (NoRootb noRootb_empty)
open A2.ThruClosureWitness (thru thru_typed body_typed Calm R0)

def T : Ty := .prod .int .int
def DT : Ty := .dtor 0 T

/-- The destructor: it takes the value lent (`d`, 0), changes elements
    through a borrow of a local of its own (`7` its local 5), and sets its
    result (1). -/
def dtor : Fn where
  params := [(.inp, DT)]
  resTy := .int
  resOwn := false
  lends := []
  rholds := []
  outHolds := []
  body := .seq (.letv 5 (.expr (.lit 7)) (thru 5)) (.assign 1 (.expr (.lit 0)))
  nvars := 6

def P : Prog := [dtor]

/-- The destructor changes elements through a borrow. -/
theorem dtor_thru : ThruFn P 0 := ThruFn.here rfl rfl

/-- **It is a destructor for `DT`**: through-changing, on a type that holds
    no views. -/
theorem dtor_ok : DtorOK P 0 DT := ⟨dtor, rfl, rfl, rfl, rfl, rfl, rfl, rfl, fun _ => rfl⟩

theorem drop_ok : DropFnOK P 0 T := Or.inl ⟨dtor_ok, by decide⟩

/-! ### The destructor is well-typed -/

theorem calm_dtor : Calm (sigCtx dtor) := by
  intro v E h
  rcases v with _ | _ | v <;> simp [sigCtx, dtor, paramE, DT, T, Ty.hasFn, resMode] at h <;>
    subst h <;> simp [Entry.vdeps, Mode.ownSlot]

theorem dtor_body : ∃ Δ, StmtT P .none (sigCtx dtor) [] dtor.body Δ ∧
    (∀ v E, Δ v = some E → E.dtor = false ∧ E.dbind = false) ∧
    Δ 1 = some { intE with mode := R0.mode } := by
  apply body_typed
  let G := A2.setE (sigCtx dtor) 5 intE
  have hG : Calm G := calm_dtor.setE (by simp [intE])
  obtain ⟨Δ, ht, hcΔ, h1⟩ := thru_typed (Q := P) hG (n := 5) (En := intE) (by simp [G, A2.setE]) rfl rfl
    (by decide) (by decide) (by decide) (by simp [G, A2.setE, sigCtx, dtor])
    (by simp [G, A2.setE, sigCtx, dtor]) (by simp [G, A2.setE, sigCtx, dtor])
    (by simp [G, A2.setE, sigCtx, dtor, R0, resMode])
  refine ⟨_, StmtT.letv (P := P) (ξ := .none) (x := 5) (Γ := sigCtx dtor) (Γ1 := sigCtx dtor) (F := [])
    (E := intE) rfl (by simp [sigCtx, dtor]) (by simp) (RhsT.expr ExprT.lit) ht.ofNone (hcΔ.endOK _)
    (fun h => by simp [intE] at h), hcΔ.exitScope 5, ?_⟩
  simp [A2.exitScope, upd, A2.kill, h1, killE, hits, R0]

theorem dtor_fnok : FnOK P dtor := by
  obtain ⟨Δ, hb, hfl, hr⟩ := dtor_body
  refine ⟨rfl, by decide, by decide, rfl, by simp [dtor], ?_, by simp [dtor], by simp [dtor], by simp [dtor],
    by simp [dtor], by simp [dtor], ?_, Δ, hb, hfl, ?_, ?_⟩
  · intro pt hpt; simp [dtor] at hpt; subst hpt; simp [DT, T, Ty.ok, Ty.isStruct]
  · refine ⟨fun i hi hs _ => ?_, fun i hi b hb _ => ?_, fun h => by simp [dtor] at h⟩
    · simp [dtor] at hi; subst hi; simp [dtor] at hs
    · simp [dtor] at hi; subst hi; simp [dtor] at hb
  · exact ⟨{ intE with mode := R0.mode }, by simpa [dtor] using hr, rfl, rfl, by simp [R0, resMode, dtor],
      by simp [intE], by simp [intE], by simp [dtor]⟩
  · intro i hi b hb; simp [dtor] at hi; subst hi; simp [dtor] at hb

theorem prog_ok : ProgOK P := by
  intro fn hfn
  simp only [P, List.mem_cons, List.mem_nil_iff, or_false] at hfn
  subst hfn; exact dtor_fnok

theorem prog_codes : ProgCodes P := by
  intro fn hfn
  simp only [P, List.mem_cons, List.mem_nil_iff, or_false] at hfn
  subst hfn; simp [dtor, thru, Stmt.codesOK, Rhs.codeOK]

/-! ### The caller: a `letd` of the struct, whose frame's end runs the destructor -/

/-- `: a 1  : b 2  :drop x ( pair a b )` -/
def main : Stmt := .letv 0 (.expr (.lit 1)) (.letv 1 (.expr (.lit 2)) (.letd 2 0 (.pair 0 1) .skip))

def EP : Entry := ⟨T, .own, true, [], [] ++ [], false, false⟩

/-- **The caller of a through-changing destructor is typed**: the `letd` of a
    struct that holds no views, its destructor `dtor`. -/
theorem main_typed : ∃ Δ, StmtT P ξ (fun _ => none) [] main Δ := by
  let K1 : Ctx := A2.setE (fun _ => none) 0 intE
  let K2 : Ctx := A2.setE K1 1 intE
  have hK1 : NoRootb K1 := noRootb_empty.setE (by simp [intE])
  have hK2 : NoRootb K2 := hK1.setE (by simp [intE])
  let ED : Entry := Entry.arm { EP with ty := DT, held := [] }
  have hED : ED.mode ≠ .rootb ∧ ED.dtor = false ∧ ED.dbind = false := by
    simp [ED, EP, Entry.arm, DT, T, Ty.dtorViews, Ty.holdsView]
  have hK3 : NoRootb (A2.setE K2 2 ED) := hK2.setE hED
  have hpair : RhsT K2 [] (.pair 0 1) EP K2 :=
    RhsT.pair (Ey := intE) (Ez := intE) (by simp [K2, K1, A2.setE, upd]) rfl PushArg.int
      (by simp [K2, K1, A2.setE]) rfl PushArg.int (by simp [intE, Mode.ownSlot])
  have hd := StmtT.letd (ξ := .none) (P := P) (Γ := K2) (Γ1 := K2) (F := []) (x := 2) (f := 0) (r := .pair 0 1)
    (s := .skip) (E := EP) (t := T) (H := []) rfl (by simp [K2, K1, A2.setE, upd]) (by simp) hpair rfl
    (Or.inl ⟨rfl, Or.inl rfl⟩) rfl rfl (letd_fn drop_ok) (HeldUp.refl _ _) StmtT.skip (hK3.endOK _)
  have h1 := StmtT.letv (ξ := .none) (P := P) (x := 1) (r := .expr (.lit 2)) (E := intE) (F := []) (Γ := K1) (Γ1 := K1)
    rfl (by simp [K1, A2.setE]) (by simp) (RhsT.expr ExprT.lit) hd.ofNone ((hK3.exitScope 2).endOK _)
  exact ⟨_, StmtT.letv (P := P) (x := 0) (r := .expr (.lit 1)) (E := intE) (F := []) (Γ := fun _ => none)
    (Γ1 := fun _ => none) rfl rfl (by simp) (RhsT.expr ExprT.lit) h1.ofNone
    (((hK3.exitScope 2).exitScope 1).endOK _)⟩

theorem main_codes : main.codesOK P := by
  simp [main, Stmt.codesOK, Rhs.codeOK]

/-- **A program whose destructor changes elements through a borrow of its
    own local is memory safe.** -/
theorem main_safe {m' : Mem} {s' : Stmt} (hr : Steps P (emptyMem 3) main (.ok m' s')) :
    ¬ Stuck P m' s' := by
  obtain ⟨Δ, ht⟩ := main_typed (ξ := .none)
  exact memory_safe prog_ok prog_codes ht rfl main_codes (by decide) hr

/-- ... and when it ends, everything it allocated is freed: the destructor's
    `loc` and its element, in the destructor's frame. -/
theorem main_no_leak {m' : Mem} (hr : Steps P (emptyMem 3) main (.ok m' .skip)) :
    ∀ i, m'.alloc i = false := by
  obtain ⟨Δ, ht⟩ := main_typed (ξ := .none)
  exact no_leak_end prog_ok prog_codes ht rfl main_codes (by decide) hr

end A2.ThruDtorWitness
