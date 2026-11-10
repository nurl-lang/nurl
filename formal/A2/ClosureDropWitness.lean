import A2.DtorWitness
import A2.EnvHand

/-! # Agora #609: a closure whose environment is a destructor value, a witness

A closure literal whose environment holds a destructor value is of the class
`dropd` (`Cross.Fits`), so its type holds one (`Ty.holdsDtor`) and it is bound
by `letd` at a destructor type of its own, whose destructor is the closure's
drop glue (`ClosureGlueOK`): a function that takes the closure owned and calls
its drop method first thing (`StmtT.callcE`, the interface taking the receiver
owned), which hands the environment to the method's code for good; the code
binds it under a `letd`, whose frame runs its destructor.

This file is a witness that those premises are satisfiable: a program of three
functions,

* `dfn` (0): the destructor of `DT = dtor 0 T`, which takes it lent;
* `code` (1): the closure's drop method's code: `@ code sink env → i { :drop w env  = r 0 }`;
* `glue` (2): the closure's drop glue, and its drop method's interface at once:
  `@ glue sink self → i { ( self.drop )  = r 0 }`, of `CDT = dtor 2 (fn [2] dropd)`;

all typed (`prog_ok`, `prog_codes`), and a caller

    : a 1  : b 2  :drop d ( pair a b )  :drop c \ [d] …

typed from nothing (`main_typed`), with `memory_safe` applied (`main_safe`).
-/

namespace A2.ClosureDropWitness
open A2.DynCell (NoRootb noRootb_empty)
open A2.DtorWitness (NoDeps)

def T : Ty := .prod .int .int
def DT : Ty := .dtor 0 T

/-- The closure's type: one method, whose interface is function 2; its
    environment may hold destructor values (`dropd`). -/
def CT : Ty := .fn [2] .dropd
/-- ... bound at the destructor type whose destructor is its glue, function 2. -/
def CDT : Ty := .dtor 2 CT

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

/-- The closure's drop method's code: it takes the environment owned and
    hands it to a `letd`, whose frame runs its destructor:
    `@ code sink env → i { :drop w env  = r 0 }`. -/
def code : Fn where
  params := [(.sink, DT)]
  resTy := .int
  resOwn := false
  lends := []
  rholds := []
  outHolds := []
  body := .letd 2 0 (.var 0) (.assign 1 (.expr (.lit 0)))
  nvars := 3

/-- The closure's drop glue, and its drop method's interface at once: it
    takes the closure owned and calls its drop method (method 0, whose
    interface is this very signature) first thing:
    `@ glue sink self → i { ( self.drop )  = r 0 }`. -/
def glue : Fn where
  params := [(.sink, CDT)]
  resTy := .int
  resOwn := false
  lends := []
  rholds := []
  outHolds := []
  body := .callcE 2 0 0 [] (.assign 1 (.expr (.lit 0)))
  nvars := 3

def Pc : Prog := [dfn, code, glue]

theorem dfn_not_thru : ¬ ThruFn Pc 0 := by
  intro h
  cases h with
  | here hf hb => simp [Pc] at hf; subst hf; simp [dfn, Stmt.hasThru] at hb
  | call hf hg _ => simp [Pc] at hf; subst hf; simp [dfn, Stmt.calls] at hg

theorem code_not_thru : ¬ ThruFn Pc 1 := by
  intro h
  cases h with
  | here hf hb => simp [Pc] at hf; subst hf; simp [code, Stmt.hasThru] at hb
  | call hf hg ht => simp [Pc] at hf; subst hf; simp [code, Stmt.calls] at hg; subst hg; exact dfn_not_thru ht

theorem glue_not_thru : ¬ ThruFn Pc 2 := by
  intro h
  cases h with
  | here hf hb => simp [Pc] at hf; subst hf; simp [glue, Stmt.hasThru] at hb
  | call hf hg _ => simp [Pc] at hf; subst hf; simp [glue, Stmt.calls] at hg

theorem dtor_ok : DtorOK Pc 0 DT :=
  ⟨dfn, rfl, rfl, rfl, rfl, rfl, rfl, rfl, dfn_not_thru⟩

theorem drop_ok : DropFnOK Pc 0 T := Or.inl ⟨dtor_ok, by decide⟩

/-- **Agora #609: the closure's destructor is its glue, which calls its drop
    method.**  Function 2 takes the closure owned, at the destructor type
    `CDT`, and its body is the call of method 0, whose interface (function 2
    again) takes the receiver owned; then it sets its integer result. -/
theorem glue_calls_drop : ClosureGlueOK Pc 2 CT :=
  ⟨glue, [2], 0, 2, glue, 2, .lit 0, rfl, rfl, rfl, rfl, rfl, rfl, rfl, rfl, glue_not_thru, rfl, rfl, rfl, rfl⟩

theorem cdrop_ok : DropFnOK Pc 2 CT := Or.inr (Or.inr (Or.inr (Or.inr glue_calls_drop)))

/-- The code implements the drop method's interface: it takes the
    environment owned where the interface takes the receiver owned. -/
theorem code_impl : Implements Pc 1 DT [] 2 :=
  ⟨code, glue, rfl, rfl, rfl, fun _ => rfl, rfl, rfl, fun _ h => h, fun _ h => h, fun _ h => h, code_not_thru⟩

theorem pack_codes : CodeOK Pc [1] DT [2] [] := by
  refine ⟨rfl, fun j f σ hf hσ => ?_⟩
  rcases j with _ | j
  · simp at hf hσ; subst hf hσ; exact code_impl
  · simp at hf

/-- The environment, a destructor value, fits the class `dropd` (and no
    other: `Cross.Fits` of a class that does not drop asks `holdsDtor = false`). -/
theorem env_fits : Cross.dropd.Fits DT [] :=
  ⟨fun _ => ⟨rfl, rfl⟩, fun _ => rfl, fun h => absurd h (by decide), fun h => absurd h (by decide)⟩

theorem env_fits_only (q : Cross) (h : q.Fits DT []) : q = .dropd := by
  cases q
  case dropd => rfl
  all_goals exact absurd (h.2.2.2 rfl) (by decide)

/-! ### The destructor's own FnOK -/

def R0 : Entry := ⟨.int, .bor, false, [], [], false, false⟩
def EDT : Entry := ⟨DT, .own, true, [], [], false, false⟩
def ECD : Entry := ⟨CDT, .own, true, [], [], false, false⟩

theorem dfn_body : StmtT Pc (sigCtx dfn) [] dfn.body
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

theorem dfn_ok : FnOK Pc dfn := by
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

/-! ### The drop method's code: the environment goes to a `letd` -/

theorem code_body : ∃ Δ, StmtT Pc (sigCtx code) [] code.body Δ ∧
    (∀ v E, Δ v = some E → E.mode ≠ .rootb ∧ E.dtor = false ∧ E.dbind = false) ∧
    Δ 1 = some { intE with mode := R0.mode } := by
  have h0 : sigCtx code 0 = some EDT := by simp [sigCtx, code, paramE, EDT, DT, T, Ty.hasFn]
  have h1 : sigCtx code 1 = some R0 := by simp [sigCtx, code, R0, resMode]
  have hS : NoRootb (sigCtx code) := by
    intro v E h
    rcases v with _ | _ | v
    · rw [h0] at h; cases h; simp [EDT]
    · rw [h1] at h; cases h; simp [R0]
    · simp [sigCtx, code] at h
  let Kb : Ctx := A2.setE (kill .replace false 0 (sigCtx code)) 0 { EDT with live := false, dtor := false }
  have hKb : NoRootb Kb := (hS.kill _ _ _).setE (by simp [EDT])
  have hmv : RhsT (sigCtx code) [] (.var 0) ⟨EDT.ty, .own, true, [], EDT.held, false, false⟩ Kb :=
    RhsT.moveOwn h0 rfl rfl (by simp) (hS.noPin _) (DtorSafe.of_none (fun v E h => (hS v E h).2.1) _ _ _)
  let ED : Entry := Entry.arm { (⟨EDT.ty, .own, true, [], EDT.held, false, false⟩ : Entry)
    with ty := DT, held := EDT.held }
  have hED : ED = ⟨DT, .own, true, [], [], false, false⟩ := by
    simp [ED, EDT, Entry.arm, DT, T, Ty.dtorViews, Ty.hasDtor, Ty.holdsView]
  let Kc : Ctx := A2.setE Kb 2 ED
  have hKc : NoRootb Kc := hKb.setE (by rw [hED]; simp)
  have hc1 : Kc 1 = some R0 := by
    simp [Kc, Kb, A2.setE, upd, A2.kill, h1, killE, hits, R0, Entry.vdeps]
  let Kd : Ctx := A2.setE (kill .replace false 1 Kc) 1 { intE with mode := R0.mode }
  have hKd : NoRootb Kd := (hKc.kill _ _ _).setE (by simp [intE, R0])
  have hasg : StmtT Pc Kc [] (.assign 1 (.expr (.lit 0))) Kd :=
    StmtT.assign (Ex := R0) (E := intE) hc1 (by simp) (Or.inr (Or.inr ⟨rfl, rfl⟩))
      (RhsT.expr ExprT.lit) rfl (by simp [intE, roots, Entry.vdeps, Mode.ownSlot]) (by simp [hc1])
      (hKc.noPin _) (DtorSafe.of_none (fun v E h => (hKc v E h).2.1) _ _ _) rfl
  have hlet := StmtT.letd (P := Pc) (Γ := sigCtx code) (Γ1 := Kb) (F := []) (x := 2) (f := 0) (r := .var 0)
    (s := .assign 1 (.expr (.lit 0))) (t := T) (H := EDT.held) (τ := DT) rfl
    (by simp [sigCtx, code]) (by simp) hmv rfl
    (Or.inl ⟨rfl, Or.inr ⟨0, rfl⟩⟩) rfl rfl (letd_fn drop_ok) (HeldUp.refl _ _) hasg (hKd.endOK _)
    (by simp [Stmt.assigns])
  refine ⟨_, hlet, hKd.exitScope 2, ?_⟩
  simp [exitScope, upd, A2.kill, Kd, A2.setE, killE, hits, intE, Entry.vdeps, R0]

theorem code_ok : FnOK Pc code := by
  obtain ⟨Δ, hb, hfl, hr⟩ := code_body
  refine ⟨rfl, by decide, by decide, rfl, by simp [code], ?_, by simp [code], by simp [code], by simp [code],
    by simp [code], by simp [code], ?_, Δ, hb, fun v E h => (hfl v E h).2, ?_, ?_⟩
  · intro pt hpt; simp [code] at hpt; subst hpt; simp [DT, T, Ty.ok, Ty.isStruct, Ty.owning]
  · refine ⟨fun i hi hs _ => ?_, fun i hi b hb _ => ?_, fun h => by simp [code] at h⟩
    · simp [code] at hi; subst hi; simp [code, Stmt.movedFirst, Stmt.assigns]
    · simp [code] at hi; subst hi; simp [code] at hb
  · exact ⟨{ intE with mode := R0.mode }, by simpa [code] using hr, rfl, rfl, by simp [R0, resMode, code],
      by simp [intE], by simp [intE], by simp [code]⟩
  · intro i hi b hb; simp [code] at hi; subst hi; simp [code] at hb

/-! ### The glue: the call of the drop method, the receiver owned -/

theorem glue_body : ∃ Δ, StmtT Pc (sigCtx glue) [] glue.body Δ ∧
    (∀ v E, Δ v = some E → E.mode ≠ .rootb ∧ E.dtor = false ∧ E.dbind = false) ∧
    Δ 1 = some { intE with mode := R0.mode } := by
  have h0 : sigCtx glue 0 = some ECD := by simp [sigCtx, glue, paramE, ECD, CDT, CT, Ty.hasFn]
  have h1 : sigCtx glue 1 = some R0 := by simp [sigCtx, glue, R0, resMode]
  have h2 : sigCtx glue 2 = none := by simp [sigCtx, glue]
  have hS : NoRootb (sigCtx glue) := by
    intro v E h
    rcases v with _ | _ | v
    · rw [h0] at h; cases h; simp [ECD]
    · rw [h1] at h; cases h; simp [R0]
    · simp [sigCtx, glue] at h
  have hSd : NoDeps (sigCtx glue) := by
    intro v E h
    rcases v with _ | _ | v
    · rw [h0] at h; cases h; simp [ECD, Entry.vdeps, Mode.ownSlot]
    · rw [h1] at h; cases h; simp [R0, Entry.vdeps, Mode.ownSlot]
    · simp [sigCtx, glue] at h
  have hps : glue.params = [(.sink, CDT)] := rfl
  have hae : argE (sigCtx glue) 0 = ECD := by simp [argE, h0]
  have han : argNames (sigCtx glue) [0] = [] := by
    simp [argNames, hae, ECD, Entry.vdeps, Mode.ownSlot, nameDeps]
  have hmn : mutNames (sigCtx glue) [0] = [] := by simp [mutNames, han]
  -- the call moves the closure in: the receiver is the interface's `sink` parameter
  let G1 : Ctx := A2.setE (sigCtx glue) 0 { ECD with live := false, dtor := false }
  have hG1 : NoRootb G1 := hS.setE (by simp [ECD])
  have hpost : callPost (sigCtx glue) glue [0] = G1 := by
    simp only [callPost, hps, callPostAux, hmn, killNames, List.foldr, hae, hSd.kill_eq]
    rfl
  have hres : callRes (sigCtx glue) glue [0] = intE := by
    simp [callRes, heldOfArgs, han, hae, ECD, allKinds, memDeps, roots, ownHeld, resMode, intE,
      show glue.resTy = Ty.int from rfl, show glue.resOwn = false from rfl, show glue.lends = [] from rfl,
      show glue.rholds = [] from rfl]
  have hcall : CallT Pc (kill .replace false 0 (sigCtx glue)) [] 2 [0] intE G1 := by
    rw [hSd.kill_eq]
    refine ⟨glue, rfl, rfl, fun i hi => ?_, fun d hd => (by rw [hmn] at hd; cases hd),
      CallDtorSafe.of_none (fun v E h => ⟨(hS v E h).2.1, (hS v E h).2.2⟩) _ _, hres.symm, hpost.symm,
      fun ht => absurd ht glue_not_thru⟩
    have hi0 : i = 0 := by simpa [glue] using hi
    subst hi0
    refine ⟨ECD, h0, rfl, ⟨rfl, rfl, rfl⟩, fun _ => ⟨by simp, ?_, fun _ => ?_, fun b hb => by simp [glue] at hb,
      fun j hj hne => ?_⟩, fun _ => hS.noPin _⟩
    · simp [ECD, Entry.vdeps, Mode.ownSlot, memDeps, roots]
    · simp [ECD, Entry.vdeps, Mode.ownSlot, roots]
    · exact absurd (by simpa [glue] using hj) hne
  let Kc : Ctx := kill .replace false 0 (A2.setE G1 2 intE)
  have hKc : NoRootb Kc := (hG1.setE (by simp [intE])).kill _ _ _
  have hc1 : Kc 1 = some R0 := by
    simp [Kc, G1, A2.setE, upd, A2.kill, h1, killE, hits, R0, Entry.vdeps]
  let Kd : Ctx := A2.setE (kill .replace false 1 Kc) 1 { intE with mode := R0.mode }
  have hKd : NoRootb Kd := (hKc.kill _ _ _).setE (by simp [intE, R0])
  have hasg : StmtT Pc Kc [] (.assign 1 (.expr (.lit 0))) Kd :=
    StmtT.assign (Ex := R0) (E := intE) hc1 (by simp) (Or.inr (Or.inr ⟨rfl, rfl⟩))
      (RhsT.expr ExprT.lit) rfl (by simp [intE, roots, Entry.vdeps, Mode.ownSlot]) (by simp [hc1])
      (hKc.noPin _) (DtorSafe.of_none (fun v E h => (hKc v E h).2.1) _ _ _) rfl
  have hce := StmtT.callcE (P := Pc) (Γ := sigCtx glue) (Γ1 := G1) (F := []) (x := 2) (c := 0) (j := 0)
    (k := .assign 1 (.expr (.lit 0))) (Ec := ECD) (E := intE) (ms := [2]) (q := .dropd) (σ := 2) (sig := glue)
    (b := .replace) rfl h2 (by simp) h0 rfl (Or.inl rfl) (Or.inr rfl) rfl rfl
    -- Agora #609: the interface takes the receiver owned
    (Or.inr ⟨rfl, by simp [ECD, Entry.vdeps, Mode.ownSlot], rfl, rfl, rfl, rfl⟩)
    rfl rfl rfl (hS.noPin _) (DtorSafe.of_none (fun v E h => (hS v E h).2.1) _ _ _) hcall hasg
    (hKd.endOK _) glue_not_thru (fun ho => by simp [glue] at ho)
  refine ⟨_, hce, hKd.exitScope 2, ?_⟩
  simp [exitScope, upd, A2.kill, Kd, A2.setE, killE, hits, intE, Entry.vdeps, R0]

theorem glue_ok : FnOK Pc glue := by
  obtain ⟨Δ, hb, hfl, hr⟩ := glue_body
  refine ⟨rfl, by decide, by decide, rfl, by simp [glue], ?_, by simp [glue], by simp [glue], by simp [glue],
    by simp [glue], by simp [glue], ?_, Δ, hb, fun v E h => (hfl v E h).2, ?_, ?_⟩
  · intro pt hpt; simp [glue] at hpt; subst hpt; simp [CDT, CT, Ty.ok, Ty.isStruct, Ty.owning]
  · refine ⟨fun i hi hs _ => ?_, fun i hi b hb _ => ?_, fun h => by simp [glue] at h⟩
    · simp [glue] at hi; subst hi
      -- (Agora #609: the function is a closure's glue, which hands its parameter to the drop method)
      exact ⟨Or.inr ⟨2, CT, rfl, Or.inr glue_calls_drop⟩, by simp [glue, Stmt.assigns]⟩
    · simp [glue] at hi; subst hi; simp [glue] at hb
  · exact ⟨{ intE with mode := R0.mode }, by simpa [glue] using hr, rfl, rfl, by simp [R0, resMode, glue],
      by simp [intE], by simp [intE], by simp [glue]⟩
  · intro i hi b hb; simp [glue] at hi; subst hi; simp [glue] at hb

theorem prog_ok : ProgOK Pc := by
  intro fn hfn
  simp only [Pc, List.mem_cons, List.mem_nil_iff, or_false] at hfn
  rcases hfn with rfl | rfl | rfl
  · exact dfn_ok
  · exact code_ok
  · exact glue_ok

theorem prog_codes : ProgCodes Pc := by
  intro fn hfn
  simp only [Pc, List.mem_cons, List.mem_nil_iff, or_false] at hfn
  rcases hfn with rfl | rfl | rfl <;> simp [dfn, code, glue, Stmt.codesOK, Rhs.codeOK]

/-! ### The caller

`: a 1  : b 2  :drop d ( pair a b )  :drop c \ [d] …`: the destructor value
`d` moves into the closure literal as its environment; the closure, of the
class `dropd`, is bound by `letd` at `CDT`, whose destructor is its glue. -/

def main : Stmt :=
  .letv 0 (.expr (.lit 1)) (.letv 1 (.expr (.lit 2))
    (.letd 2 0 (.pair 0 1) (.letd 3 2 (.pack [1] DT [2] 2 []) .skip)))

def EP : Entry := ⟨T, .own, true, [], [] ++ [], false, false⟩

theorem main_typed : ∃ Δ, StmtT Pc (fun _ => none) [] main Δ := by
  let K1 : Ctx := A2.setE (fun _ => none) 0 intE
  let K2 : Ctx := A2.setE K1 1 intE
  have hK1 : NoRootb K1 := noRootb_empty.setE (by simp [intE])
  have hK2 : NoRootb K2 := hK1.setE (by simp [intE])
  let ED : Entry := Entry.arm { EP with ty := DT, held := [] }
  have hEDe : ED = ⟨DT, .own, true, [], [], false, false⟩ := by
    simp [ED, EP, Entry.arm, DT, T, Ty.dtorViews, Ty.hasDtor, Ty.holdsView]
  let K3 : Ctx := A2.setE K2 2 ED
  have hK3 : NoRootb K3 := hK2.setE (by rw [hEDe]; simp)
  have hpair : RhsT K2 [] (.pair 0 1) EP K2 :=
    RhsT.pair (Ey := intE) (Ez := intE) (by simp [K2, K1, A2.setE, upd]) rfl PushArg.int
      (by simp [K2, K1, A2.setE, upd]) rfl PushArg.int (by simp [intE, Mode.ownSlot])
  -- the destructor value moves into the closure literal
  let K5 : Ctx := A2.setE (kill .replace false 2 K3) 2 { ED with live := false, dtor := false }
  have hK5 : NoRootb K5 := (hK3.kill _ _ _).setE (by rw [hEDe]; simp)
  have hmove : PushArg K3 [] 2 ED DT ED.held K5 :=
    PushArg.move (Γ := K3) (F := []) (y := 2) (E := ED) (t := DT) rfl (by rw [hEDe]) (by simp)
      (hK3.noPin _) (DtorSafe.of_none (fun v E h => (hK3 v E h).2.1) _ _ _)
  let EC0 : Entry := ⟨.fn [2] .dropd, .own, true, [], ED.held ++ capDeps [], false, false⟩
  have hpack : RhsT K3 [] (.pack [1] DT [2] 2 []) EC0 K5 :=
    RhsT.pack (Γ := K3) (F := []) (fs := [1]) (te := DT) (ms := [2]) (q := .dropd) (y := 2) (cs := [])
      (Ey := ED) (by simp [K3, A2.setE, upd]) (by rw [hEDe]) (by rw [hEDe]) hmove
      ⟨List.nodup_nil, fun _ h => by cases h⟩ env_fits
  let ECa : Entry := Entry.arm { EC0 with ty := CDT, held := EC0.held }
  have hECa : ECa.mode ≠ .rootb ∧ ECa.dtor = false ∧ ECa.dbind = false := by
    simp [ECa, EC0, Entry.arm, CDT, CT, Ty.dtorViews, Ty.hasDtor, Ty.holdsView]
  have hK6 : NoRootb (A2.setE K5 3 ECa) := hK5.setE hECa
  have hg := StmtT.letd (P := Pc) (Γ := K3) (Γ1 := K5) (F := []) (x := 3) (f := 2)
    (r := .pack [1] DT [2] 2 []) (s := .skip) (E := EC0) (t := CT) (H := EC0.held) (τ := CDT) rfl
    (by simp [K3, K2, K1, A2.setE, upd]) (by simp) hpack rfl
    (Or.inl ⟨rfl, Or.inl rfl⟩) rfl rfl (letd_fn cdrop_ok) (HeldUp.refl _ _) StmtT.skip
    (hK6.endOK _)
  have hd := StmtT.letd (P := Pc) (Γ := K2) (Γ1 := K2) (F := []) (x := 2) (f := 0) (r := .pair 0 1)
    (E := EP) (t := T) (H := []) rfl (by simp [K2, K1, A2.setE, upd])
    (by simp) hpair rfl (Or.inl ⟨rfl, Or.inl rfl⟩) rfl rfl (letd_fn drop_ok) (HeldUp.refl _ _) hg
    ((hK6.exitScope 3).endOK _)
  have h1 := StmtT.letv (P := Pc) (x := 1) (r := .expr (.lit 2)) (E := intE) (F := []) (Γ := K1) (Γ1 := K1)
    rfl (by simp [K1, A2.setE, upd]) (by simp) (RhsT.expr ExprT.lit) hd
    (((hK6.exitScope 3).exitScope 2).endOK _)
  exact ⟨_, StmtT.letv (P := Pc) (x := 0) (r := .expr (.lit 1)) (E := intE) (F := []) (Γ := fun _ => none)
    (Γ1 := fun _ => none) rfl rfl (by simp) (RhsT.expr ExprT.lit) h1
    ((((hK6.exitScope 3).exitScope 2).exitScope 1).endOK _)⟩

theorem main_codes : main.codesOK Pc := by
  simp only [main, Stmt.codesOK, Rhs.codeOK, true_and, and_true]
  exact pack_codes

/-- **Agora #609: the program with a closure whose environment is a destructor
    value, dropped by its glue, is memory safe.** -/
theorem main_safe {m' : Mem} {s' : Stmt} (hr : Steps Pc (emptyMem 4) main (.ok m' s')) :
    ¬ Stuck Pc m' s' := by
  obtain ⟨Δ, ht⟩ := main_typed
  exact memory_safe prog_ok prog_codes ht rfl main_codes (by decide) hr

/-- ... and the closure is no `letv`'s: `letv` binds no owned value whose type
    holds a destructor value, which the closure's does. -/
theorem main_letv_refused {Γ Δ : Ctx} {F : List Var} {x : Var} {s : Stmt} :
    ¬ StmtT Pc Γ F (.letv x (.pack [1] DT [2] 2 []) s) Δ := by
  intro h
  obtain ⟨Γ0, E, Γ1, hr, hnd⟩ := A2.Dtor.letv_owned_no_dtor h
  cases hr with
  | pack _ _ _ _ _ hq =>
    have := env_fits_only _ hq
    subst this
    exact absurd (hnd rfl) (by simp [Ty.holdsDtor])

end A2.ClosureDropWitness
