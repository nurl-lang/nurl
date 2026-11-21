import A2.DtorWitness
import A2.ThruClosureWitness

/-! # A struct's own `% Drop` that changes elements through a borrow, run by its glue

    : D { i n }
    % Drop D { @ drop D d → v { … } }
    : H { D inner  i k }
    % Drop H { @ drop H h → v {
        : ( Vec ( Vec i ) ) loc ( vec_new … )
        ( vec_push loc ( vec_new [i] ) )
        ( vec_push [i] ( vec_at loc 0 ) 7 )   -- a push THROUGH a borrow of loc's element
    } }

A struct that holds a destructor value has drop glue (Agora #616); one with a
`% Drop` of its own has glue that rebinds it under its fields' glue and runs
the impl on it lent (`ImplGlueOK`).  When the impl changes elements through a
borrow (`ThruFn`, Agora #295), so does the glue, which calls it.  Before, the
glue definitions refused that outright (`¬ ThruFn P f`); now, as for a
destructor called lent (`A2.ThruDtorWitness`), they ask only that the type
hold no views (`ThruFn P f → t.holdsView = false`): the glue's call at the
frame's end passes none (`glueCall_typed`), and so does the glue's own call
of the impl, on the `letd` it rebinds the value under.

A program of four functions, on `GT = prod DT int` (a destructor field and a
number), which holds no views:

* `dfn` (0): the field's destructor, which does nothing;
* `glue` (1): the fields' glue, `unpair` and a `letd` for the destructor field;
* `implT` (2): the struct's own `% Drop`, taken lent at the fields' glue type,
  its body `ThruClosureWitness`'s through-changing body (`thru_typed`, any
  program);
* `glue2` (3): the struct's glue, which rebinds it under `glue` and calls
  `implT` on it lent — through-changing itself, by the call (`glue2_thru`);

all typed (`prog_ok`), and the caller

    : a 1  : b 2  :drop c ( pair a b )  : k 3  :drop h ( pair c k )

typed from nothing (`main_typed`), with `memory_safe` and `no_leak_end`
applied (`main_safe`, `main_no_leak`).
-/

namespace A2.ThruGlueWitness
open A2.DynCell (NoRootb noRootb_empty)
open A2.ThruClosureWitness (thru thru_typed body_typed Calm R0)

def T : Ty := .prod .int .int
def DT : Ty := .dtor 0 T
def GT : Ty := .prod DT .int
def GDT : Ty := .dtor 1 GT
def SDT2 : Ty := .dtor 3 GT

/-- The field's destructor: `@ drop in self → i { = r 0 }`. -/
def dfn : Fn where
  params := [(.inp, DT)]
  resTy := .int
  resOwn := false
  lends := []
  rholds := []
  outHolds := []
  body := .assign 1 (.expr (.lit 0))
  nvars := 2

/-- The fields' glue: `@ glue sink self → i { unpair self x z  :drop y x  = r 0 }`. -/
def glue : Fn where
  params := [(.sink, GDT)]
  resTy := .int
  resOwn := false
  lends := []
  rholds := []
  outHolds := []
  body := .unpair 0 2 3 (.letd 4 0 (.var 2) (.assign 1 (.expr (.lit 0))))
  nvars := 5

/-- The struct's own `% Drop`, through-changing: it takes the struct lent at
    the fields' glue type and pushes `7` through a borrow of a local's
    element. -/
def implT : Fn where
  params := [(.inp, GDT)]
  resTy := .int
  resOwn := false
  lends := []
  rholds := []
  outHolds := []
  body := .seq (.letv 5 (.expr (.lit 7)) (thru 5)) (.assign 1 (.expr (.lit 0)))
  nvars := 6

/-- The struct's glue: `@ glue2 sink self → i { :drop w self  ( implT w )  = r 0 }`. -/
def glue2 : Fn where
  params := [(.sink, SDT2)]
  resTy := .int
  resOwn := false
  lends := []
  rholds := []
  outHolds := []
  body := .letd 2 1 (.var 0) (.letcall 3 2 [2] (.assign 1 (.expr (.lit 0))))
  nvars := 4

def P : Prog := [dfn, glue, implT, glue2]

/-! ### The field's destructor -/

theorem dfn_not_thru : ¬ ThruFn P 0 := by
  intro h
  cases h with
  | here hf hb => simp [P] at hf; subst hf; simp [dfn, Stmt.hasThru] at hb
  | call hf hg _ => simp [P] at hf; subst hf; simp [dfn, Stmt.calls] at hg

theorem dtor_ok : DtorOK P 0 DT :=
  ⟨dfn, rfl, rfl, rfl, rfl, rfl, rfl, rfl, fun h => absurd h dfn_not_thru⟩

theorem drop_ok : DropFnOK P 0 T := Or.inl ⟨dtor_ok, by decide⟩

theorem dfn_body : StmtT P ξ (sigCtx dfn) [] dfn.body
    (setE (kill .replace false 1 (sigCtx dfn)) 1 { intE with mode := R0.mode }) := by
  have hc : sigCtx dfn 1 = some R0 := by simp [↓sigCtx_noRegion (fn := dfn) (by decide), dfn, R0, resMode]
  have hflags : ∀ v E, sigCtx dfn v = some E → E.dtor = false ∧ E.dbind = false := by
    intro v E h
    rcases v with _ | _ | v <;> simp [↓sigCtx_noRegion (fn := dfn) (by decide), dfn, paramE, resMode] at h <;> subst h <;> exact ⟨rfl, rfl⟩
  exact StmtT.assign (Ex := R0) (E := intE) hc (by simp) (Or.inr (Or.inr ⟨rfl, rfl⟩))
    (RhsT.expr ExprT.lit) rfl (by simp [intE, roots, Entry.vdeps, Mode.ownSlot]) (by simp [hc])
    (by
      intro p E hp hm d hd _
      rcases p with _ | _ | p <;> simp [↓sigCtx_noRegion (fn := dfn) (by decide), dfn, paramE, resMode, DT, T, Ty.hasFn] at hp <;> subst hp <;>
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
    rcases v with _ | _ | v <;> simp [setE, upd, kill, killE, ↓sigCtx_noRegion (fn := dfn) (by decide), dfn, paramE, intE] at h <;>
      subst h <;> exact ⟨rfl, rfl⟩
  · exact ⟨{ intE with mode := R0.mode }, by simp [setE, upd, dfn], rfl, rfl, by simp [R0, resMode, dfn], by simp [intE], by simp [intE],
      by simp [dfn]⟩
  · intro i hi b hb; simp [dfn] at hi; subst hi; simp [dfn] at hb

/-! ### The fields' glue -/

theorem glue_not_thru : ¬ ThruFn P 1 := by
  intro h
  cases h with
  | here hf hb => simp [P] at hf; subst hf; simp [glue, Stmt.hasThru] at hb
  | call hf hg ht => simp [P] at hf; subst hf; simp [glue, Stmt.calls] at hg; subst hg; exact dfn_not_thru ht

theorem glue_glueOK : GlueOK P 1 GT :=
  ⟨glue, DT, .int, rfl, rfl, rfl, rfl, rfl, rfl, rfl, rfl, fun h => absurd h glue_not_thru, 2, 3, _, rfl, rfl⟩

theorem gluedrop_ok : DropFnOK P 1 GT := Or.inr (Or.inl glue_glueOK)

def EG : Entry := ⟨GDT, .own, true, [], [], false, false, false, false⟩

theorem glue_body : ∃ Δ, StmtT P ξ (sigCtx glue) [] glue.body Δ ∧
    (∀ v E, Δ v = some E → E.mode ≠ .rootb ∧ E.dtor = false ∧ E.dbind = false) ∧
    Δ 1 = some { intE with mode := R0.mode } := by
  have h0 : sigCtx glue 0 = some EG := by simp [↓sigCtx_noRegion (fn := glue) (by decide), glue, paramE, EG, GDT, GT, DT, T, Ty.hasFn]
  have h1 : sigCtx glue 1 = some R0 := by simp [↓sigCtx_noRegion (fn := glue) (by decide), glue, R0, resMode]
  have hS : NoRootb (sigCtx glue) := by
    intro v E h
    rcases v with _ | _ | v
    · rw [h0] at h; cases h; simp [EG]
    · rw [h1] at h; cases h; simp [R0]
    · simp [↓sigCtx_noRegion (fn := glue) (by decide), glue] at h
  let Ka : Ctx := A2.setE (A2.setE (A2.setE (kill .replace false 0 (sigCtx glue)) 0
    { EG with live := false, dtor := false }) 2 (compE EG DT)) 3 (compE EG .int)
  have hKa : NoRootb Ka :=
    (((hS.kill _ _ _).setE (by simp [EG])).setE (by simp [compE, DT])).setE (by simp [compE, intE])
  have hEx : compE EG DT = ⟨DT, .own, true, [], [], false, false, false, false⟩ := by
    simp [compE, DT, EG, ownHeld]
  let Kb : Ctx := A2.setE (kill .replace false 2 Ka) 2 { compE EG DT with live := false, dtor := false }
  have hKb : NoRootb Kb := (hKa.kill _ _ _).setE (by rw [hEx]; simp)
  have hmv : RhsT Ka [] (.var 2) ⟨(compE EG DT).ty, .own, true, [], (compE EG DT).held, false, false, false, false⟩ Kb :=
    RhsT.moveOwn (by simp [Ka, A2.setE, upd]) (by rw [hEx]) (by rw [hEx]) (by simp) (hKa.noPin _)
      (DtorSafe.of_none (fun v E h => (hKa v E h).2.1) _ _ _)
  let ED : Entry := Entry.arm { (⟨(compE EG DT).ty, .own, true, [], (compE EG DT).held, false, false, false, false⟩ : Entry)
    with ty := DT, held := (compE EG DT).held }
  have hED : ED = ⟨DT, .own, true, [], [], false, false, false, false⟩ := by
    simp only [ED]; rw [hEx]; simp [Entry.arm, DT, T, Ty.dtorViews, Ty.holdsView]
  let Kc : Ctx := A2.setE Kb 4 ED
  have hKc : NoRootb Kc := hKb.setE (by rw [hED]; simp)
  have hc1 : Kc 1 = some R0 := by
    simp [Kc, Kb, Ka, A2.setE, upd, A2.kill, h1, killE, hits, R0, Entry.vdeps]
  let Kd : Ctx := A2.setE (kill .replace false 1 Kc) 1 { intE with mode := R0.mode }
  have hKd : NoRootb Kd := (hKc.kill _ _ _).setE (by simp [intE, R0])
  have hasg : StmtT P .none Kc [] (.assign 1 (.expr (.lit 0))) Kd :=
    StmtT.assign (Ex := R0) (E := intE) hc1 (by simp) (Or.inr (Or.inr ⟨rfl, rfl⟩))
      (RhsT.expr ExprT.lit) rfl (by simp [intE, roots, Entry.vdeps, Mode.ownSlot]) (by simp [hc1])
      (hKc.noPin _) (DtorSafe.of_none (fun v E h => (hKc v E h).2.1) _ _ _) rfl
  have hlet := StmtT.letd (ξ := .none) (P := P) (Γ := Ka) (Γ1 := Kb) (F := []) (x := 4) (f := 0) (r := .var 2)
    (s := .assign 1 (.expr (.lit 0))) (t := T) (H := (compE EG DT).held) (τ := DT) rfl
    (by simp [Ka, A2.setE, upd, A2.kill, ↓sigCtx_noRegion (fn := glue) (by decide), glue]) (by simp) hmv rfl
    (Or.inl ⟨rfl, Or.inr ⟨0, by rw [hEx]; rfl⟩⟩) rfl rfl (letd_fn drop_ok) (HeldUp.refl _ _) hasg.ofNone (hKd.endOK _)
    (by simp [Stmt.assigns])
  have hun := StmtT.unpair (ξ := .none) (P := P) (Γ := sigCtx glue) (F := []) (y := 0) (x := 2) (z := 3)
    (s := .letd 4 0 (.var 2) (.assign 1 (.expr (.lit 0)))) (E := EG) (a := DT) (b := .int)
    rfl h0 rfl (Or.inl rfl) (Or.inr ⟨1, rfl, glue_glueOK⟩) (by simp)
    (by simp [↓sigCtx_noRegion (fn := glue) (by decide), glue]) (by simp [↓sigCtx_noRegion (fn := glue) (by decide), glue]) (by decide) (by simp) (by simp) hlet.ofNone
    (hS.noPin _) (DtorSafe.of_none (fun v E h => (hS v E h).2.1) _ _ _)
    ((hKd.exitScope 4).endOK _) (((hKd.exitScope 4).exitScope 3).endOK _)
    (fun _ => by simp [Stmt.movedFirst, Stmt.assigns]) (fun h => by simp [Ty.holdsDtor] at h)
  refine ⟨_, hun.ofNone, (((hKd.exitScope 4).exitScope 3).exitScope 2), ?_⟩
  simp [exitScope, upd, A2.kill, Kd, A2.setE, killE, hits, intE, Entry.vdeps, R0]

theorem glue_ok : FnOK P glue := by
  obtain ⟨Δ, hb, hfl, hr⟩ := glue_body
  refine ⟨rfl, by decide, by decide, rfl, by simp [glue], ?_, by simp [glue], by simp [glue], by simp [glue],
    by simp [glue], by simp [glue], ?_, Δ, hb, fun v E h => (hfl v E h).2, ?_, ?_⟩
  · intro pt hpt; simp [glue] at hpt; subst hpt; simp [GDT, GT, DT, T, Ty.ok, Ty.isStruct, Ty.owning]
  · refine ⟨fun i hi hs _ => ?_, fun i hi b hb _ => ?_, fun h => by simp [glue] at h⟩
    · simp [glue] at hi; subst hi; simp [glue, Stmt.movedFirst, Stmt.assigns]
    · simp [glue] at hi; subst hi; simp [glue] at hb
  · exact ⟨{ intE with mode := R0.mode }, by simpa [glue] using hr, rfl, rfl, by simp [R0, resMode, glue],
      by simp [intE], by simp [intE], by simp [glue]⟩
  · intro i hi b hb; simp [glue] at hi; subst hi; simp [glue] at hb

/-! ### The struct's own `% Drop`, through-changing -/

theorem implT_thru : ThruFn P 2 := ThruFn.here rfl rfl

/-- **The impl is a destructor of the struct at its fields' glue type**:
    through-changing, on a type that holds no views. -/
theorem implT_dtorOK : DtorOK P 2 GDT :=
  ⟨implT, rfl, rfl, rfl, rfl, rfl, rfl, rfl, fun _ => rfl⟩

theorem calm_implT : Calm (sigCtx implT) := by
  intro v E h
  rcases v with _ | _ | v <;> simp [↓sigCtx_noRegion (fn := implT) (by decide), implT, paramE, GDT, GT, DT, T, Ty.hasFn, resMode] at h <;>
    subst h <;> simp [Entry.vdeps, Mode.ownSlot]

theorem implT_body : ∃ Δ, StmtT P .none (sigCtx implT) [] implT.body Δ ∧
    (∀ v E, Δ v = some E → E.dtor = false ∧ E.dbind = false) ∧
    Δ 1 = some { intE with mode := R0.mode } := by
  apply body_typed
  let G := A2.setE (sigCtx implT) 5 intE
  have hG : Calm G := calm_implT.setE (by simp [intE])
  obtain ⟨Δ, ht, hcΔ, h1⟩ := thru_typed (Q := P) hG (n := 5) (En := intE) (by simp [G, A2.setE]) rfl rfl (fun h => by simp [intE] at h)
    (by decide) (by decide) (by decide) (by simp [G, A2.setE, ↓sigCtx_noRegion (fn := implT) (by decide), implT])
    (by simp [G, A2.setE, ↓sigCtx_noRegion (fn := implT) (by decide), implT]) (by simp [G, A2.setE, ↓sigCtx_noRegion (fn := implT) (by decide), implT])
    (by simp [G, A2.setE, ↓sigCtx_noRegion (fn := implT) (by decide), implT, R0, resMode])
  refine ⟨_, StmtT.letv (P := P) (ξ := .none) (x := 5) (Γ := sigCtx implT) (Γ1 := sigCtx implT) (F := [])
    (E := intE) rfl (by simp [↓sigCtx_noRegion (fn := implT) (by decide), implT]) (by simp) (RhsT.expr ExprT.lit) ht.ofNone (hcΔ.endOK _)
    (fun h => by simp [intE] at h), hcΔ.exitScope 5, ?_⟩
  simp [A2.exitScope, upd, A2.kill, h1, killE, hits, R0]

theorem implT_ok : FnOK P implT := by
  obtain ⟨Δ, hb, hfl, hr⟩ := implT_body
  refine ⟨rfl, by decide, by decide, rfl, by simp [implT], ?_, by simp [implT], by simp [implT], by simp [implT],
    by simp [implT], by simp [implT], ?_, Δ, hb, hfl, ?_, ?_⟩
  · intro pt hpt; simp [implT] at hpt; subst hpt; simp [GDT, GT, DT, T, Ty.ok, Ty.isStruct]
  · refine ⟨fun i hi hs _ => ?_, fun i hi b hb _ => ?_, fun h => by simp [implT] at h⟩
    · simp [implT] at hi; subst hi; simp [implT] at hs
    · simp [implT] at hi; subst hi; simp [implT] at hb
  · exact ⟨{ intE with mode := R0.mode }, by simpa [implT] using hr, rfl, rfl, by simp [R0, resMode, implT],
      by simp [intE], by simp [intE], by simp [implT]⟩
  · intro i hi b hb; simp [implT] at hi; subst hi; simp [implT] at hb

/-! ### The struct's glue, through-changing by its call of the impl -/

/-- The glue changes elements through a borrow: it calls the impl. -/
theorem glue2_thru : ThruFn P 3 := ThruFn.call rfl (by simp [glue2, Stmt.calls]) implT_thru

/-- **The struct's glue runs its through-changing impl**: through-changing
    itself, on a type that holds no views. -/
theorem glue2_implOK : ImplGlueOK P 3 GT 1 2 :=
  ⟨glue2, 2, 3, .lit 0, rfl, rfl, rfl, rfl, rfl, rfl, rfl, rfl, fun _ => rfl,
    Or.inl glue_glueOK, implT_dtorOK, rfl⟩

theorem impldrop_ok : DropFnOK P 3 GT := Or.inr (Or.inr (Or.inl ⟨1, 2, glue2_implOK⟩))

def ES2 : Entry := ⟨SDT2, .own, true, [], [], false, false, false, false⟩

theorem glue2_body : ∃ Δ, StmtT P ξ (sigCtx glue2) [] glue2.body Δ ∧
    (∀ v E, Δ v = some E → E.mode ≠ .rootb ∧ E.dtor = false ∧ E.dbind = false) ∧
    Δ 1 = some { intE with mode := R0.mode } := by
  have h0 : sigCtx glue2 0 = some ES2 := by simp [↓sigCtx_noRegion (fn := glue2) (by decide), glue2, paramE, ES2, SDT2, GT, DT, T, Ty.hasFn]
  have h1 : sigCtx glue2 1 = some R0 := by simp [↓sigCtx_noRegion (fn := glue2) (by decide), glue2, R0, resMode]
  have hS : NoRootb (sigCtx glue2) := by
    intro v E h
    rcases v with _ | _ | v
    · rw [h0] at h; cases h; simp [ES2]
    · rw [h1] at h; cases h; simp [R0]
    · simp [↓sigCtx_noRegion (fn := glue2) (by decide), glue2] at h
  let Ka : Ctx := A2.setE (kill .replace false 0 (sigCtx glue2)) 0 { ES2 with live := false, dtor := false }
  have hKa : NoRootb Ka := (hS.kill _ _ _).setE (by simp [ES2])
  have hmv : RhsT (sigCtx glue2) [] (.var 0) ⟨ES2.ty, .own, true, [], ES2.held, false, false, false, false⟩ Ka :=
    RhsT.moveOwn h0 rfl rfl (by simp) (hS.noPin _) (DtorSafe.of_none (fun v E h => (hS v E h).2.1) _ _ _)
  let EW : Entry := Entry.arm { (⟨ES2.ty, .own, true, [], ES2.held, false, false, false, false⟩ : Entry) with ty := GDT, held := ES2.held }
  have hEW : EW = ⟨GDT, .own, true, [], [], false, false, false, false⟩ := by
    simp [EW, ES2, Entry.arm, GDT, GT, DT, T, Ty.dtorViews, Ty.holdsView]
  let Kb : Ctx := A2.setE Ka 2 EW
  have hKb : NoRootb Kb := hKa.setE (by rw [hEW]; simp)
  have hb2 : Kb 2 = some EW := by simp [Kb, A2.setE]
  have hnm : mutNames Kb [2] = [] := by
    simp [mutNames, argNames, argE, hb2, hEW, Entry.vdeps, nameDeps, Mode.ownSlot]
  -- the impl changes elements through a borrow: the value it is handed, the
  -- `letd` the glue rebound the struct under, holds no views (`callR = []`)
  have hcall : CallT P Kb [] 2 [2] (callRes Kb implT [2]) Kb := by
    refine ⟨implT, rfl, by simp [implT], fun i hi => ?_, fun d hd => ?_,
      CallDtorSafe.of_inp (by simp [implT]) hnm, rfl, (callPost_dtor (t := GDT) rfl hnm).symm,
      fun _ => by simp [callR, argE, hb2, hEW, memDeps, roots]⟩
    · have hi0 : i = 0 := by simp [implT] at hi; omega
      subst hi0
      refine ⟨EW, by simp [hb2], by rw [hEW], ?_, fun h => ?_, fun h => ?_⟩
      · simp [implT, paramOK, hEW]
      · simp [implT, PMode.moves] at h
      · simp [implT] at h
    · rw [hnm] at hd; cases hd
  have hER : (callRes Kb implT [2]).mode ≠ .rootb ∧ (callRes Kb implT [2]).dtor = false ∧
      (callRes Kb implT [2]).dbind = false := by simp [callRes, resMode, implT]
  let Kc : Ctx := A2.setE Kb 3 (callRes Kb implT [2])
  have hKc : NoRootb Kc := hKb.setE hER
  have hc1 : Kc 1 = some R0 := by
    simp [Kc, Kb, Ka, A2.setE, upd, A2.kill, h1, killE, hits, R0, Entry.vdeps]
  let Kd : Ctx := A2.setE (kill .replace false 1 Kc) 1 { intE with mode := R0.mode }
  have hKd : NoRootb Kd := (hKc.kill _ _ _).setE (by simp [intE, R0])
  have hasg : StmtT P .none Kc [] (.assign 1 (.expr (.lit 0))) Kd :=
    StmtT.assign (Ex := R0) (E := intE) hc1 (by simp) (Or.inr (Or.inr ⟨rfl, rfl⟩))
      (RhsT.expr ExprT.lit) rfl (by simp [intE, roots, Entry.vdeps, Mode.ownSlot]) (by simp [hc1])
      (hKc.noPin _) (DtorSafe.of_none (fun v E h => (hKc v E h).2.1) _ _ _) rfl
  have hlc := StmtT.letcall (ξ := .none) (P := P) (Γ := Kb) (F := []) (x := 3) (f := 2) (args := [2])
    (s := .assign 1 (.expr (.lit 0))) rfl (by simp [Kb, Ka, A2.setE, upd, A2.kill, ↓sigCtx_noRegion (fn := glue2) (by decide), glue2]) (by simp)
    hcall hasg.ofNone (hKd.endOK _)
    (fun fn' hf' ho _ => by simp [P] at hf'; subst hf'; simp [implT] at ho)
  have hlet := StmtT.letd (ξ := .none) (P := P) (Γ := sigCtx glue2) (Γ1 := Ka) (F := []) (x := 2) (f := 1) (r := .var 0)
    (s := .letcall 3 2 [2] (.assign 1 (.expr (.lit 0)))) (t := GT) (H := ES2.held) (τ := GDT) rfl
    (by simp [↓sigCtx_noRegion (fn := glue2) (by decide), glue2]) (by simp) hmv rfl
    (Or.inl ⟨rfl, Or.inr ⟨3, rfl⟩⟩) rfl rfl
    ⟨⟨gluedrop_ok, fun g hg _ => by
      have hg3 : g = 3 := (Ty.dtor.inj hg).1.symm
      subst hg3
      exact ⟨2, 3, _, glue2_implOK, rfl⟩⟩,
      TakeOK.triv (fun y => ⟨(by intro h; cases h), (by intro h; cases h)⟩)⟩
    (HeldUp.refl _ _) hlc.ofNone ((hKd.exitScope 3).endOK _) (by simp [Stmt.assigns])
  refine ⟨_, hlet.ofNone, ((hKd.exitScope 3).exitScope 2), ?_⟩
  simp [exitScope, upd, A2.kill, Kd, A2.setE, killE, hits, intE, Entry.vdeps, R0]

theorem glue2_ok : FnOK P glue2 := by
  obtain ⟨Δ, hb, hfl, hr⟩ := glue2_body
  refine ⟨rfl, by decide, by decide, rfl, by simp [glue2], ?_, by simp [glue2], by simp [glue2], by simp [glue2],
    by simp [glue2], by simp [glue2], ?_, Δ, hb, fun v E h => (hfl v E h).2, ?_, ?_⟩
  · intro pt hpt; simp [glue2] at hpt; subst hpt; simp [SDT2, GT, DT, T, Ty.ok, Ty.isStruct, Ty.owning]
  · refine ⟨fun i hi hs _ => ?_, fun i hi b hb _ => ?_, fun h => by simp [glue2] at h⟩
    · simp [glue2] at hi; subst hi; simp [glue2, Stmt.movedFirst, Stmt.assigns]
    · simp [glue2] at hi; subst hi; simp [glue2] at hb
  · exact ⟨{ intE with mode := R0.mode }, by simpa [glue2] using hr, rfl, rfl, by simp [R0, resMode, glue2],
      by simp [intE], by simp [intE], by simp [glue2]⟩
  · intro i hi b hb; simp [glue2] at hi; subst hi; simp [glue2] at hb

theorem prog_ok : ProgOK P := by
  intro fn hfn
  simp only [P, List.mem_cons, List.mem_nil_iff, or_false] at hfn
  rcases hfn with rfl | rfl | rfl | rfl
  · exact dfn_ok
  · exact glue_ok
  · exact implT_ok
  · exact glue2_ok

theorem prog_codes : ProgCodes P := by
  intro fn hfn
  simp only [P, List.mem_cons, List.mem_nil_iff, or_false] at hfn
  rcases hfn with rfl | rfl | rfl | rfl <;> simp [dfn, glue, implT, glue2, thru, Stmt.codesOK, Rhs.codeOK]

/-! ### The caller: the struct bound by `letd`, its glue run at the frame's end -/

/-- `: a 1  : b 2  :drop c ( pair a b )  : k 3  :drop h ( pair c k )` -/
def main : Stmt :=
  .letv 0 (.expr (.lit 1)) (.letv 1 (.expr (.lit 2))
    (.letd 2 0 (.pair 0 1) (.letv 3 (.expr (.lit 3)) (.letd 4 3 (.pair 2 3) .skip))))

def EP : Entry := ⟨T, .own, true, [], [] ++ [], false, false, false, false⟩

/-- **The caller of a struct whose own `% Drop` changes elements through a
    borrow is typed**: the struct, which holds a destructor value and a
    number and no views, bound by `letd` at its glue's type. -/
theorem main_typed : ∃ Δ, StmtT P ξ (fun _ => none) [] main Δ := by
  let K1 : Ctx := A2.setE (fun _ => none) 0 intE
  let K2 : Ctx := A2.setE K1 1 intE
  have hK1 : NoRootb K1 := noRootb_empty.setE (by simp [intE])
  have hK2 : NoRootb K2 := hK1.setE (by simp [intE])
  let ED : Entry := Entry.arm { EP with ty := DT, held := [] }
  have hEDe : ED = ⟨DT, .own, true, [], [], false, false, false, false⟩ := by
    simp [ED, EP, Entry.arm, DT, T, Ty.dtorViews, Ty.holdsView]
  let K3 : Ctx := A2.setE K2 2 ED
  have hK3 : NoRootb K3 := hK2.setE (by rw [hEDe]; simp)
  have hpair : RhsT K2 [] (.pair 0 1) EP K2 :=
    RhsT.pair (Ey := intE) (Ez := intE) (by simp [K2, K1, A2.setE, upd]) rfl PushArg.int
      (by simp [K2, K1, A2.setE]) rfl PushArg.int (by simp [intE, Mode.ownSlot])
  let K4 : Ctx := A2.setE K3 3 intE
  have hK4 : NoRootb K4 := hK3.setE (by simp [intE])
  let K5 : Ctx := A2.setE (kill .replace false 2 K4) 2 { ED with live := false, dtor := false }
  have hK5 : NoRootb K5 := (hK4.kill _ _ _).setE (by rw [hEDe]; simp)
  have hmove : PushArg K4 [] 2 ED ED.ty ED.held K5 :=
    PushArg.move (Γ := K4) (F := []) (y := 2) (E := ED) (t := ED.ty) rfl (by rw [hEDe]) (by simp)
      (hK4.noPin _) (DtorSafe.of_none (fun v E h => (hK4 v E h).2.1) _ _ _)
  have hK53 : K5 3 = some intE := by
    simp [K5, K4, A2.setE, upd, A2.kill, killE, hits, intE, Entry.vdeps, Mode.ownSlot]
  let EG0 : Entry := ⟨.prod ED.ty intE.ty, .own, true, [], ED.held ++ [], false, false, false, false⟩
  have hgp : RhsT K4 [] (.pair 2 3) EG0 K5 :=
    RhsT.pair (Ey := ED) (Ez := intE) (by simp [K4, K3, A2.setE, upd]) (by rw [hEDe]) hmove
      hK53 rfl PushArg.int (by simp [intE, Mode.ownSlot])
  let EGa : Entry := Entry.arm { EG0 with ty := SDT2, held := EG0.held }
  have hEGa : EGa.mode ≠ .rootb ∧ EGa.dtor = false ∧ EGa.dbind = false := by
    simp [EGa, EG0, Entry.arm, SDT2, GT, DT, T, Ty.dtorViews, Ty.holdsView]
  have hK6 : NoRootb (A2.setE K5 4 EGa) := hK5.setE hEGa
  have hg := StmtT.letd (ξ := .none) (P := P) (Γ := K4) (Γ1 := K5) (F := []) (x := 4) (f := 3) (r := .pair 2 3)
    (s := .skip) (E := EG0) (t := GT) (H := EG0.held) (τ := SDT2) rfl
    (by simp [K4, K3, K2, K1, A2.setE, upd]) (by simp) hgp rfl
    (Or.inl ⟨rfl, Or.inl (by simp [EG0, hEDe, intE, GT])⟩) rfl rfl (letd_fn impldrop_ok) (HeldUp.refl _ _) StmtT.skip
    (hK6.endOK _)
  have h3 := StmtT.letv (ξ := .none) (P := P) (x := 3) (r := .expr (.lit 3)) (E := intE) (F := []) (Γ := K3) (Γ1 := K3)
    rfl (by simp [K3, K2, K1, A2.setE, upd]) (by simp) (RhsT.expr ExprT.lit) hg.ofNone ((hK6.exitScope 4).endOK _)
  have hd := StmtT.letd (ξ := .none) (P := P) (Γ := K2) (Γ1 := K2) (F := []) (x := 2) (f := 0) (r := .pair 0 1)
    (E := EP) (t := T) (H := []) rfl (by simp [K2, K1, A2.setE, upd])
    (by simp) hpair rfl (Or.inl ⟨rfl, Or.inl rfl⟩) rfl rfl (letd_fn drop_ok) (HeldUp.refl _ _) h3.ofNone
    (((hK6.exitScope 4).exitScope 3).endOK _)
  have h1 := StmtT.letv (ξ := .none) (P := P) (x := 1) (r := .expr (.lit 2)) (E := intE) (F := []) (Γ := K1) (Γ1 := K1)
    rfl (by simp [K1, A2.setE]) (by simp) (RhsT.expr ExprT.lit) hd.ofNone
    ((((hK6.exitScope 4).exitScope 3).exitScope 2).endOK _)
  exact ⟨_, StmtT.letv (P := P) (x := 0) (r := .expr (.lit 1)) (E := intE) (F := []) (Γ := fun _ => none)
    (Γ1 := fun _ => none) rfl rfl (by simp) (RhsT.expr ExprT.lit) h1.ofNone
    (((((hK6.exitScope 4).exitScope 3).exitScope 2).exitScope 1).endOK _)⟩

theorem main_codes : main.codesOK P := by
  simp [main, Stmt.codesOK, Rhs.codeOK]

/-- **A program whose struct's own `% Drop` changes elements through a borrow
    of its own local, run by the struct's glue, is memory safe.** -/
theorem main_safe {m' : Mem} {s' : Stmt} (hr : Steps P (emptyMem 5) main (.ok m' s')) :
    ¬ Stuck P m' s' := by
  obtain ⟨Δ, ht⟩ := main_typed (ξ := .none)
  exact memory_safe prog_ok prog_codes ht rfl main_codes (by decide) hr

/-- ... and when it ends, everything it allocated is freed: the impl's `loc`
    and its element, in the impl's frame inside the glue's. -/
theorem main_no_leak {m' : Mem} (hr : Steps P (emptyMem 5) main (.ok m' .skip)) :
    ∀ i, m'.alloc i = false := by
  obtain ⟨Δ, ht⟩ := main_typed (ξ := .none)
  exact no_leak_end prog_ok prog_codes ht rfl main_codes (by decide) hr

end A2.ThruGlueWitness
