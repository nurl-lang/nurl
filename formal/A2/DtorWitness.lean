import A2.Dtor

/-! # A2-drop.3a's witness (`A2.DtorWitness`): the program, its destructor,
its maker and its callers, typed, with `memory_safe` applied (the guarantee
of the typing it witnesses, `A2.Dtor.*`, is `A2/Dtor.lean`, apart so that a
certificate loads no witness program, AGORA-1013). -/


namespace A2.DtorWitness
open A2.DynCell (NoRootb noRootb_empty)

/-- No entry views anything. -/
def NoDeps (Γ : Ctx) : Prop := ∀ v E, Γ v = some E → E.vdeps = []

theorem NoDeps.setE {Γ : Ctx} (h : NoDeps Γ) {x : Var} {E : Entry} (hE : E.vdeps = []) :
    NoDeps (A2.setE Γ x E) := fun v E' hv => by
  by_cases hvx : v = x
  · subst hvx; simp [A2.setE] at hv; subst hv; exact hE
  · rw [A2.setE, upd_ne _ _ hvx] at hv; exact h v E' hv

theorem NoDeps.kill {Γ : Ctx} (h : NoDeps Γ) (e : Eff) (hv : Bool) (x : Var) :
    NoDeps (A2.kill e hv x Γ) := fun v E' hv' => by
  simp only [A2.kill] at hv'
  cases h0 : Γ v with
  | none => rw [h0] at hv'; cases hv'
  | some E0 =>
    rw [h0] at hv'; simp only [Option.map_some, Option.some.injEq] at hv'; subst hv'
    have := h v E0 h0
    unfold killE; split
    · simpa [Entry.vdeps] using this
    · exact this

theorem NoDeps.kill_eq {Γ : Ctx} (h : NoDeps Γ) (e : Eff) (hv : Bool) (x : Var) :
    A2.kill e hv x Γ = Γ := by
  funext v
  cases h0 : Γ v with
  | none => simp [A2.kill, h0]
  | some E =>
    simp only [A2.kill, h0, Option.map_some, Option.some.injEq]
    unfold killE
    have : hits e hv x E = false := by simp [hits, h v E h0]
    rw [this]; rfl

theorem NoDeps.wf {Γ : Ctx} (h : NoDeps Γ) (hf : NoRootb Γ) : CtxWF Γ :=
  ⟨fun v E hE _ _ r hr => by rw [h v E hE] at hr; simp [roots] at hr,
    fun v E hE hd => (by rw [(hf v E hE).2.2] at hd; cases hd),
    fun v E hE hd => (by rw [(hf v E hE).2.1] at hd; cases hd),
    fun v E hE hd => (by rw [(hf v E hE).2.2] at hd; cases hd)⟩

theorem NoDeps.names {Γ : Ctx} (h : NoDeps Γ) : NameWF Γ :=
  fun v E hE _ _ => by simp [NameOK, DepsNamed, h v E hE]

/-- AGORA-937: a context whose bindings depend on nothing but the region `r`
    (a regioned parameter's caller memory), never by name. -/
def RegDeps (r : Var) (Γ : Ctx) : Prop :=
  ∀ v E, Γ v = some E → ∀ d ∈ E.vdeps, d.root = r ∧ d.kind.isName = false

theorem NoDeps.regDeps {Γ : Ctx} (h : NoDeps Γ) (r : Var) : RegDeps r Γ :=
  fun v E hE d hd => by rw [h v E hE] at hd; cases hd

theorem RegDeps.setE {r : Var} {Γ : Ctx} (h : RegDeps r Γ) {x : Var} {E : Entry}
    (hE : ∀ d ∈ E.vdeps, d.root = r ∧ d.kind.isName = false) : RegDeps r (A2.setE Γ x E) := fun v E' hv => by
  by_cases hvx : v = x
  · subst hvx; simp [A2.setE] at hv; subst hv; exact hE
  · rw [A2.setE, upd_ne _ _ hvx] at hv; exact h v E' hv

theorem RegDeps.kill {r : Var} {Γ : Ctx} (h : RegDeps r Γ) (e : Eff) (hv : Bool) (x : Var) :
    RegDeps r (A2.kill e hv x Γ) := fun v E' hv' => by
  simp only [A2.kill] at hv'
  cases h0 : Γ v with
  | none => rw [h0] at hv'; cases hv'
  | some E0 =>
    rw [h0] at hv'; simp only [Option.map_some, Option.some.injEq] at hv'; subst hv'
    have := h v E0 h0
    unfold killE; split
    · simpa [Entry.vdeps] using this
    · exact this

theorem RegDeps.kill_eq {r : Var} {Γ : Ctx} (h : RegDeps r Γ) (e : Eff) (hv : Bool) {x : Var}
    (hx : x ≠ r) : A2.kill e hv x Γ = Γ := by
  funext v
  cases h0 : Γ v with
  | none => simp [A2.kill, h0]
  | some E =>
    simp only [A2.kill, h0, Option.map_some, Option.some.injEq]
    unfold killE
    have : hits e hv x E = false := by
      simp only [hits, Bool.and_eq_false_iff]
      right
      simp only [List.any_eq_false, Bool.and_eq_true, beq_iff_eq, not_and]
      intro d hd hdx
      rw [(h v E h0 d hd).1] at hdx
      exact absurd hdx.symm hx
    rw [this]; rfl

theorem RegDeps.wf {r : Var} {Γ : Ctx} (h : RegDeps r Γ) (hf : NoRootb Γ)
    (hr : ∃ Er, Γ r = some Er ∧ Er.mode.isRoot = true) : CtxWF Γ :=
  ⟨fun v E hE _ _ q hq => by
      obtain ⟨d, hd, rfl⟩ := List.mem_map.mp hq
      rw [(h v E hE d hd).1]; exact hr,
    fun v E hE hd => (by rw [(hf v E hE).2.2] at hd; cases hd),
    fun v E hE hd => (by rw [(hf v E hE).2.1] at hd; cases hd),
    fun v E hE hd => (by rw [(hf v E hE).2.2] at hd; cases hd)⟩

theorem RegDeps.names {r : Var} {Γ : Ctx} (h : RegDeps r Γ) : NameWF Γ :=
  fun v E hE _ _ d hd b t hk => by have := (h v E hE d hd).2; rw [hk] at this; cases this


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

/-- A2-drop.3b: an option of a destructor value, `sum DT int`, holds one,
    so it is bound by `letd` at a destructor type of its own whose
    destructor is its glue (Agora #632): it takes the option owned and, on
    `Some`, moves the payload out to a `letd` of its own:
    `@ ofn sink self → i { ? ( isl self ) { :drop y ( takel self )  = r 0 } { = r 0 } }`. -/
def OT : Ty := .sum DT .int
def ODT : Ty := .dtor 2 OT

def ofn : Fn where
  params := [(.sink, ODT)]
  resTy := .int
  resOwn := false
  lends := []
  rholds := []
  outHolds := []
  body := .ite (.isl 0) (.letd 2 0 (.takel 0) (.assign 1 (.expr (.lit 0)))) (.assign 1 (.expr (.lit 0)))
  nvars := 3

/-- A2-drop.3b: an enum one variant of which holds a struct holding a
    destructor value, `sum (prod DT int) int`: the destructor value is two
    levels down, under a struct of no destructor type of its own.  Its glue
    (Agora #632) moves that struct out to a `letd` at the struct's glue type
    (`GDT`, whose glue takes it apart). -/
def AT : Ty := .prod DT .int
def ST : Ty := .sum AT .int
def SDT : Ty := .dtor 3 ST

def gfn : Fn where
  params := [(.sink, SDT)]
  resTy := .int
  resOwn := false
  lends := []
  rholds := []
  outHolds := []
  body := .ite (.isl 0) (.letd 2 4 (.takel 0) (.assign 1 (.expr (.lit 0)))) (.assign 1 (.expr (.lit 0)))
  nvars := 3

/-- Agora #616: a struct with a destructor field, `prod DT int`, bound at
    the destructor type whose destructor is its glue: the function that
    takes the struct owned and takes it apart, the destructor field going to
    a `letd` of its own:
    `@ glue sink self → i { unpair self x z  :drop y x  = r 0 }`. -/
def GT : Ty := .prod DT .int
def GDT : Ty := .dtor 4 GT

def glue : Fn where
  params := [(.sink, GDT)]
  resTy := .int
  resOwn := false
  lends := []
  rholds := []
  outHolds := []
  body := .unpair 0 2 3 (.letd 4 0 (.var 2) (.assign 1 (.expr (.lit 0))))
  nvars := 5

/-- Agora #616: the same struct with a `% Drop` of its own beside its
    destructor field.  Its impl takes the struct lent, at the fields' glue
    type `GDT`: `@ drop in self → i { = r 0 }` ... -/
def impl : Fn where
  params := [(.inp, GDT)]
  resTy := .int
  resOwn := false
  lends := []
  rholds := []
  outHolds := []
  body := .assign 1 (.expr (.lit 0))
  nvars := 2

/-- ... and its glue takes it owned, rebinds it under the fields' glue
    (from here a panic takes it apart, the field in a frame of its own),
    and runs the impl on it lent:
    `@ glue2 sink self → i { :drop w self  ( impl w )  = r 0 }`. -/
def SDT2 : Ty := .dtor 6 GT

def glue2 : Fn where
  params := [(.sink, SDT2)]
  resTy := .int
  resOwn := false
  lends := []
  rholds := []
  outHolds := []
  body := .letd 2 4 (.var 0) (.letcall 3 5 [2] (.assign 1 (.expr (.lit 0))))
  nvars := 4

/-- Agora #607: a struct whose field is a `Vec` of destructor values, and
    its glue: `@ glueV sink self → i { unpair self x z  :drop y x  = r 0 }`,
    the `letd` at the `Vec`'s own type, which drains it. -/
def GV : Ty := .prod (.vec DT) .int
def GVD : Ty := .dtor 7 GV

def glueV : Fn where
  params := [(.sink, GVD)]
  resTy := .int
  resOwn := false
  lends := []
  rholds := []
  outHolds := []
  body := .unpair 0 2 3 (.letd 4 0 (.var 2) (.assign 1 (.expr (.lit 0))))
  nvars := 5

/-- Agora #633: a struct with a destructor field and a view field (nurlc's
    `: P { Conn c s name }`), and its glue:
    `@ glueS sink self → i { unpair self x z  :drop y x  = r 0 }`. -/
def GS : Ty := .prod DT (.slice .int)
def GSD : Ty := .dtor 8 GS

def glueS : Fn where
  params := [(.sink, GSD)]
  resTy := .int
  resOwn := false
  lends := []
  rholds := []
  outHolds := []
  body := .unpair 0 2 3 (.letd 4 0 (.var 2) (.assign 1 (.expr (.lit 0))))
  nvars := 5

/-- Agora #750: an enum with a destructor payload and a view payload,
    `sum DT (slice int)` (nurlc's `| Conn c | Name s`), bound at the
    destructor type whose destructor is its glue: on the first variant the
    payload moves out to a `letd` of its own; the second, a view, needs no
    code:
    `@ ofnV sink self → i { ? ( isl self ) { :drop y ( takel self )  = r 0 } { = r 0 } }`. -/
def OV : Ty := .sum DT (.slice .int)
def OVD : Ty := .dtor 9 OV

def ofnV : Fn where
  params := [(.sink, OVD)]
  resTy := .int
  resOwn := false
  lends := []
  rholds := []
  outHolds := []
  body := .ite (.isl 0) (.letd 2 0 (.takel 0) (.assign 1 (.expr (.lit 0)))) (.assign 1 (.expr (.lit 0)))
  nvars := 3

/-- Agora #750: the struct `GS` (a destructor field and a view field) with a
    `% Drop` of its own: its impl takes it lent, at the fields' glue type
    `GSD`: `@ drop in self → i { = r 0 }` ... -/
def implS : Fn where
  params := [(.inp, GSD)]
  resTy := .int
  resOwn := false
  lends := []
  rholds := []
  outHolds := []
  body := .assign 1 (.expr (.lit 0))
  nvars := 2

/-- ... and its glue takes it owned, rebinds it under the fields' glue
    `glueS` and runs the impl on it lent:
    `@ glueS2 sink self → i { :drop w self  ( implS w )  = r 0 }`. -/
def GSD2 : Ty := .dtor 11 GS

def glueS2 : Fn where
  params := [(.sink, GSD2)]
  resTy := .int
  resOwn := false
  lends := []
  rholds := []
  outHolds := []
  body := .letd 2 8 (.var 0) (.letcall 3 10 [2] (.assign 1 (.expr (.lit 0))))
  nvars := 4

/-- Agora #805: the glue of the option a channel's receive hands out,
    `Option DT` as nurlc's `chan_recv` returns it: `sum int DT`, the payload
    in the right variant:
    `@ ofnR sink self → i { ? ( isl self ) { = r 0 } { :drop y ( taker self )  = r 0 } }`. -/
def RT : Ty := .sum .int DT
def RDT : Ty := .dtor 12 RT

def ofnR : Fn where
  params := [(.sink, RDT)]
  resTy := .int
  resOwn := false
  lends := []
  rholds := []
  outHolds := []
  body := .ite (.isl 0) (.assign 1 (.expr (.lit 0))) (.letd 2 0 (.taker 0) (.assign 1 (.expr (.lit 0))))
  nvars := 3

def P : Prog := [dfn, mk, ofn, gfn, glue, impl, glue2, glueV, glueS, ofnV, implS, glueS2, ofnR]

theorem dfn_not_thru : ¬ ThruFn P 0 := by
  intro h
  cases h with
  | here hf hb => simp [P] at hf; subst hf; simp [dfn, Stmt.hasThru] at hb
  | call hf hg _ => simp [P] at hf; subst hf; simp [dfn, Stmt.calls] at hg

theorem dtor_ok : DtorOK P 0 DT :=
  ⟨dfn, rfl, rfl, rfl, rfl, rfl, rfl, rfl, fun h => absurd h dfn_not_thru⟩

theorem drop_ok : DropFnOK P 0 T := Or.inl ⟨dtor_ok, by decide⟩

/-- `: a 1  : b 2  :drop x ( pair a b )` -/
def main : Stmt := .letv 0 (.expr (.lit 1)) (.letv 1 (.expr (.lit 2)) (.letd 2 0 (.pair 0 1) .skip))

def EP : Entry := ⟨T, .own, true, [], [] ++ [], false, false, false, false⟩

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


/-! ### The destructor's own FnOK -/

def R0 : Entry := ⟨.int, .bor, false, [], [], false, false, false, false⟩
def Epar : Entry := ⟨DT, .rootb, true, [], [], false, false, false, false⟩

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


/-! ### The maker: a function whose owned result is a destructor value -/

def Rr : Entry := ⟨DT, .own, false, [], [], false, false, false, false⟩
def EDd : Entry := Entry.arm { EP with ty := DT, held := [] }

theorem EDd_eq : EDd = ⟨DT, .own, true, [], [], false, false, false, false⟩ := by
  simp [EDd, EP, Entry.arm, DT, T, Ty.dtorViews, Ty.holdsView]

theorem sig_mk : sigCtx mk = A2.setE (fun _ => none) 0 Rr := by
  funext v; rcases v with _ | v <;> simp [↓sigCtx_noRegion (fn := mk) (by decide), mk, resMode, Rr, A2.setE, upd]

theorem mk_typed : ∃ Δ, StmtT P ξ (sigCtx mk) [] mk.body Δ ∧ NoRootb Δ ∧
    Δ 0 = some ⟨DT, .own, true, [], [], false, false, false, false⟩ := by
  rw [sig_mk]
  let S : Ctx := A2.setE (fun _ => none) 0 Rr
  have hS : NoRootb S := noRootb_empty.setE (by simp [Rr])
  let C1 : Ctx := A2.setE S 1 intE
  let C2 : Ctx := A2.setE C1 2 intE
  have hC2 : NoRootb C2 := (hS.setE (by simp [intE])).setE (by simp [intE])
  let C3 : Ctx := A2.setE C2 3 EDd
  have hC3 : NoRootb C3 := hC2.setE (by rw [EDd_eq]; simp)
  have hmv : RhsT C3 [] (.var 3) ⟨DT, .own, true, [], [], false, false, false, false⟩
      (A2.setE (kill .replace false 3 C3) 3 { EDd with live := false, dtor := false }) := by
    have := RhsT.moveOwn (Γ := C3) (F := []) (y := 3) (E := EDd) (by simp [C3, A2.setE]) (by rw [EDd_eq])
      (by rw [EDd_eq]) (by simp) (hC3.noPin _) (DtorSafe.of_none (fun v E h => (hC3 v E h).2.1) _ _ _)
    rw [EDd_eq] at this ⊢; exact this
  let G1 : Ctx := A2.setE (kill .replace false 3 C3) 3 { EDd with live := false, dtor := false }
  have hG1 : NoRootb G1 := (hC3.kill _ _ _).setE (by rw [EDd_eq]; simp)
  have ha := StmtT.assign (ξ := .none) (P := P) (Γ := C3) (F := []) (x := 0) (r := .var 3) (Ex := Rr)
    (E := ⟨DT, .own, true, [], [], false, false, false, false⟩) (Γ1 := G1)
    (by simp [C3, C2, C1, S, A2.setE, upd]) (by simp) (Or.inl ⟨rfl, rfl⟩) hmv rfl
    (by simp [roots, Entry.vdeps, Mode.ownSlot]) (by simp [G1, C3, C2, C1, S, A2.setE, upd, kill]) (hC3.noPin _)
    (DtorSafe.of_none (fun v E h => (hG1 v E h).2.1) _ _ _) rfl
  let Da : Ctx := A2.setE (kill .replace false 0 G1) 0 { (⟨DT, .own, true, [], [], false, false, false, false⟩ : Entry) with mode := Rr.mode }
  have hDa : NoRootb Da := (hG1.kill _ _ _).setE (by simp [Rr])
  have hpair : RhsT C2 [] (.pair 1 2) EP C2 :=
    RhsT.pair (Ey := intE) (Ez := intE) (by simp [C2, C1, A2.setE, upd]) rfl PushArg.int
      (by simp [C2, A2.setE]) rfl PushArg.int (by simp [intE, Mode.ownSlot])
  have hd := StmtT.letd (ξ := .none) (P := P) (Γ := C2) (Γ1 := C2) (F := []) (x := 3) (f := 0) (r := .pair 1 2)
    (s := .assign 0 (.var 3)) (E := EP) (t := T) (H := []) rfl (by simp [C2, C1, S, A2.setE, upd]) (by simp)
    hpair rfl (Or.inl ⟨rfl, Or.inl rfl⟩) rfl rfl (letd_fn drop_ok) (HeldUp.refl _ _) ha.ofNone (hDa.endOK _)
  have h2 := StmtT.letv (ξ := .none) (P := P) (x := 2) (r := .expr (.lit 2)) (E := intE) (F := []) (Γ := C1) (Γ1 := C1)
    rfl (by simp [C1, S, A2.setE, upd]) (by simp) (RhsT.expr ExprT.lit) hd.ofNone ((hDa.exitScope 3).endOK _)
  have h1 := StmtT.letv (ξ := .none) (P := P) (x := 1) (r := .expr (.lit 1)) (E := intE) (F := []) (Γ := S) (Γ1 := S)
    rfl (by simp [S, A2.setE]) (by simp) (RhsT.expr ExprT.lit) h2.ofNone (((hDa.exitScope 3).exitScope 2).endOK _)
  refine ⟨_, h1.ofNone, ((hDa.exitScope 3).exitScope 2).exitScope 1, ?_⟩
  simp [exitScope, A2.setE, upd, kill, killE, hits, Rr, Entry.vdeps, Mode.ownSlot]

theorem mk_ok : FnOK P mk := by
  obtain ⟨Δ, ht, hn, h0⟩ := mk_typed
  refine ⟨rfl, by decide, by decide, by simp [mk, DT, T, Ty.ok, Ty.isStruct], fun _ => rfl, by simp [mk],
    by simp [mk], by simp [mk], by simp [mk], by simp [mk], by simp [mk], ?_, Δ, ht,
    fun v E h => ⟨(hn v E h).2.1, (hn v E h).2.2⟩, ⟨_, h0, rfl, rfl, rfl, by simp, by simp, fun _ _ => rfl⟩,
    fun i hi => by simp [mk] at hi⟩
  refine ⟨fun i hi => by simp [mk] at hi, fun i hi => by simp [mk] at hi, fun _ _ => ⟨by decide, ?_⟩⟩
  exact ⟨0, T, Or.inl rfl, rfl, rfl, drop_ok⟩

/-! ### The glue's own FnOK (Agora #616) -/

theorem glue_not_thru : ¬ ThruFn P 4 := by
  intro h
  cases h with
  | here hf hb => simp [P] at hf; subst hf; simp [glue, Stmt.hasThru] at hb
  | call hf hg ht => simp [P] at hf; subst hf; simp [glue, Stmt.calls] at hg; subst hg; exact dfn_not_thru ht

theorem glue_glueOK : GlueOK P 4 GT :=
  ⟨glue, DT, .int, rfl, rfl, rfl, rfl, rfl, rfl, rfl, rfl, fun h => absurd h glue_not_thru, 2, 3, _, rfl, rfl⟩

theorem gluedrop_ok : DropFnOK P 4 GT := Or.inr (Or.inl glue_glueOK)

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
    rfl h0 rfl (Or.inl rfl) (Or.inr ⟨4, rfl, glue_glueOK⟩) (by simp)
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

/-! ### A struct with a `Vec` of destructor values for a field (Agora #607)

`prod (vec DT) int`: its glue takes it apart and hands the `Vec` to a
`letd` at its own type, whose frame drains it, each element's destructor
running in its own frame. -/

theorem glueV_not_thru : ¬ ThruFn P 7 := by
  intro h
  cases h with
  | here hf hb => simp [P] at hf; subst hf; simp [glueV, Stmt.hasThru] at hb
  | call hf hg ht => simp [P] at hf; subst hf; simp [glueV, Stmt.calls] at hg; subst hg; exact dfn_not_thru ht

theorem glueV_glueOK : GlueOK P 7 GV :=
  ⟨glueV, .vec DT, .int, rfl, rfl, rfl, rfl, rfl, rfl, rfl, rfl, fun h => absurd h glueV_not_thru, 2, 3, _, rfl, rfl⟩

theorem gvdrop_ok : DropFnOK P 7 GV := Or.inr (Or.inl glueV_glueOK)

def EGV : Entry := ⟨GVD, .own, true, [], [], false, false, false, false⟩

theorem glueV_body : ∃ Δ, StmtT P ξ (sigCtx glueV) [] glueV.body Δ ∧
    (∀ v E, Δ v = some E → E.mode ≠ .rootb ∧ E.dtor = false ∧ E.dbind = false) ∧
    Δ 1 = some { intE with mode := R0.mode } := by
  have h0 : sigCtx glueV 0 = some EGV := by simp [↓sigCtx_noRegion (fn := glueV) (by decide), glueV, paramE, EGV, GVD, GV, DT, T, Ty.hasFn]
  have h1 : sigCtx glueV 1 = some R0 := by simp [↓sigCtx_noRegion (fn := glueV) (by decide), glueV, R0, resMode]
  have hS : NoRootb (sigCtx glueV) := by
    intro v E h
    rcases v with _ | _ | v
    · rw [h0] at h; cases h; simp [EGV]
    · rw [h1] at h; cases h; simp [R0]
    · simp [↓sigCtx_noRegion (fn := glueV) (by decide), glueV] at h
  let Ka : Ctx := A2.setE (A2.setE (A2.setE (kill .replace false 0 (sigCtx glueV)) 0
    { EGV with live := false, dtor := false }) 2 (compE EGV (.vec DT))) 3 (compE EGV .int)
  have hKa : NoRootb Ka :=
    (((hS.kill _ _ _).setE (by simp [EGV])).setE (by simp [compE, DT])).setE (by simp [compE, intE])
  have hEx : compE EGV (.vec DT) = ⟨.vec DT, .own, true, [], [], false, false, false, false⟩ := by
    simp [compE, DT, EGV, ownHeld]
  let Kb : Ctx := A2.setE (kill .replace false 2 Ka) 2 { compE EGV (.vec DT) with live := false, dtor := false }
  have hKb : NoRootb Kb := (hKa.kill _ _ _).setE (by rw [hEx]; simp)
  have hmv : RhsT Ka [] (.var 2) ⟨(compE EGV (.vec DT)).ty, .own, true, [], (compE EGV (.vec DT)).held, false, false, false, false⟩ Kb :=
    RhsT.moveOwn (by simp [Ka, A2.setE, upd]) (by rw [hEx]) (by rw [hEx]) (by simp) (hKa.noPin _)
      (DtorSafe.of_none (fun v E h => (hKa v E h).2.1) _ _ _)
  let ED : Entry := Entry.arm { (⟨(compE EGV (.vec DT)).ty, .own, true, [], (compE EGV (.vec DT)).held, false, false, false, false⟩ : Entry)
    with ty := .vec DT, held := (compE EGV (.vec DT)).held }
  have hED : ED = ⟨.vec DT, .own, true, [], [], false, false, false, false⟩ := by
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
    (s := .assign 1 (.expr (.lit 0))) (t := T) (H := (compE EGV (.vec DT)).held) (τ := .vec DT) rfl
    (by simp [Ka, A2.setE, upd, A2.kill, ↓sigCtx_noRegion (fn := glueV) (by decide), glueV]) (by simp) hmv rfl
    (Or.inr ⟨0, rfl, by rw [hEx]⟩) rfl rfl (letd_fn drop_ok) (HeldUp.refl _ _) hasg.ofNone (hKd.endOK _)
    (by simp [Stmt.assigns])
  have hun := StmtT.unpair (ξ := .none) (P := P) (Γ := sigCtx glueV) (F := []) (y := 0) (x := 2) (z := 3)
    (s := .letd 4 0 (.var 2) (.assign 1 (.expr (.lit 0)))) (E := EGV) (a := .vec DT) (b := .int)
    rfl h0 rfl (Or.inl rfl) (Or.inr ⟨7, rfl, glueV_glueOK⟩) (by simp)
    (by simp [↓sigCtx_noRegion (fn := glueV) (by decide), glueV]) (by simp [↓sigCtx_noRegion (fn := glueV) (by decide), glueV]) (by decide) (by simp) (by simp) hlet.ofNone
    (hS.noPin _) (DtorSafe.of_none (fun v E h => (hS v E h).2.1) _ _ _)
    ((hKd.exitScope 4).endOK _) (((hKd.exitScope 4).exitScope 3).endOK _)
    (fun _ => by simp [Stmt.movedFirst, Stmt.assigns]) (fun h => by simp [Ty.holdsDtor] at h)
  refine ⟨_, hun.ofNone, (((hKd.exitScope 4).exitScope 3).exitScope 2), ?_⟩
  simp [exitScope, upd, A2.kill, Kd, A2.setE, killE, hits, intE, Entry.vdeps, R0]

theorem glueV_ok : FnOK P glueV := by
  obtain ⟨Δ, hb, hfl, hr⟩ := glueV_body
  refine ⟨rfl, by decide, by decide, rfl, by simp [glueV], ?_, by simp [glueV], by simp [glueV], by simp [glueV],
    by simp [glueV], by simp [glueV], ?_, Δ, hb, fun v E h => (hfl v E h).2, ?_, ?_⟩
  · intro pt hpt; simp [glueV] at hpt; subst hpt; simp [GVD, GV, DT, T, Ty.ok, Ty.isStruct, Ty.owning]
  · refine ⟨fun i hi hs _ => ?_, fun i hi b hb _ => ?_, fun h => by simp [glueV] at h⟩
    · simp [glueV] at hi; subst hi; simp [glueV, Stmt.movedFirst, Stmt.assigns]
    · simp [glueV] at hi; subst hi; simp [glueV] at hb
  · exact ⟨{ intE with mode := R0.mode }, by simpa [glueV] using hr, rfl, rfl, by simp [R0, resMode, glueV],
      by simp [intE], by simp [intE], by simp [glueV]⟩
  · intro i hi b hb; simp [glueV] at hi; subst hi; simp [glueV] at hb

/-! ### A struct with a destructor field and a view field (Agora #633)

`prod DT (slice int)`: its glue takes it apart as `glue` does; the view
field is a borrow, which ends with the glue's scope.  The callee sees its
parameter as holding nothing (`paramE`): what the view is valid through is
the caller's, which the call keeps. -/

theorem glueS_not_thru : ¬ ThruFn P 8 := by
  intro h
  cases h with
  | here hf hb => simp [P] at hf; subst hf; simp [glueS, Stmt.hasThru] at hb
  | call hf hg ht => simp [P] at hf; subst hf; simp [glueS, Stmt.calls] at hg; subst hg; exact dfn_not_thru ht

theorem glueS_glueOK : GlueOK P 8 GS :=
  ⟨glueS, DT, .slice .int, rfl, rfl, rfl, rfl, rfl, rfl, rfl, rfl, fun h => absurd h glueS_not_thru, 2, 3, _, rfl, rfl⟩

theorem gsdrop_ok : DropFnOK P 8 GS := Or.inr (Or.inl glueS_glueOK)

/-- AGORA-937: the parameter holds views (its slice), so it views its
    region `π 0`, at `glueS.nvars + 0 = 5`. -/
def EGS : Entry := ⟨GSD, .own, true, [], [⟨5, .self⟩], false, false, false, false⟩

theorem glueS_body : ∃ Δ, StmtT P ξ (sigCtx glueS) [] glueS.body Δ ∧
    (∀ v E, Δ v = some E → E.mode ≠ .rootb ∧ E.dtor = false ∧ E.dbind = false) ∧
    Δ 1 = some { intE with mode := R0.mode } := by
  have h0 : sigCtx glueS 0 = some EGS := by
    simp [sigCtx, glueS, paramE, EGS, GSD, GS, DT, T, Ty.hasFn, regionP, regioned, Ty.holdsView]
  have h1 : sigCtx glueS 1 = some R0 := by simp [sigCtx, glueS, R0, resMode]
  have hS : NoRootb (sigCtx glueS) := by
    intro v E h
    rcases v with _ | _ | v
    · rw [h0] at h; cases h; simp [EGS]
    · rw [h1] at h; cases h; simp [R0]
    · rcases sigCtx_cases h with ⟨hv, _⟩ | ⟨hv, _⟩ | ⟨_, _, _, _, rfl⟩
      · simp [glueS] at hv
      · simp [glueS] at hv
      · simp [regionE]
  let Ka : Ctx := A2.setE (A2.setE (A2.setE (kill .replace false 0 (sigCtx glueS)) 0
    { EGS with live := false, dtor := false }) 2 (compE EGS DT)) 3 (compE EGS (.slice .int))
  have hKa : NoRootb Ka :=
    (((hS.kill _ _ _).setE (by simp [EGS])).setE (by simp [compE, DT])).setE (by simp [compE])
  have hEx : compE EGS DT = ⟨DT, .own, true, [], [], false, false, false, false⟩ := by
    simp [compE, DT, ownHeld, T, Ty.holdsView]
  let Kb : Ctx := A2.setE (kill .replace false 2 Ka) 2 { compE EGS DT with live := false, dtor := false }
  have hKb : NoRootb Kb := (hKa.kill _ _ _).setE (by rw [hEx]; simp)
  have hmv : RhsT Ka [] (.var 2) ⟨(compE EGS DT).ty, .own, true, [], (compE EGS DT).held, false, false, false, false⟩ Kb :=
    RhsT.moveOwn (by simp [Ka, A2.setE, upd]) (by rw [hEx]) (by rw [hEx]) (by simp) (hKa.noPin _)
      (DtorSafe.of_none (fun v E h => (hKa v E h).2.1) _ _ _)
  let ED : Entry := Entry.arm { (⟨(compE EGS DT).ty, .own, true, [], (compE EGS DT).held, false, false, false, false⟩ : Entry)
    with ty := DT, held := (compE EGS DT).held }
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
    (s := .assign 1 (.expr (.lit 0))) (t := T) (H := (compE EGS DT).held) (τ := DT) rfl
    (by simp [Ka, A2.setE, upd, A2.kill, sigCtx, isRegionIdx, glueS]) (by simp) hmv rfl
    (Or.inl ⟨rfl, Or.inr ⟨0, by rw [hEx]; rfl⟩⟩) rfl rfl (letd_fn drop_ok) (HeldUp.refl _ _) hasg.ofNone (hKd.endOK _)
    (by simp [Stmt.assigns])
  have hun := StmtT.unpair (ξ := .none) (P := P) (Γ := sigCtx glueS) (F := []) (y := 0) (x := 2) (z := 3)
    (s := .letd 4 0 (.var 2) (.assign 1 (.expr (.lit 0)))) (E := EGS) (a := DT) (b := .slice .int)
    rfl h0 rfl (Or.inl rfl) (Or.inr ⟨8, rfl, glueS_glueOK⟩) (by simp)
    (by simp [sigCtx, isRegionIdx, glueS]) (by simp [sigCtx, isRegionIdx, glueS]) (by decide) (by simp) (by simp) hlet.ofNone
    (hS.noPin _) (DtorSafe.of_none (fun v E h => (hS v E h).2.1) _ _ _)
    ((hKd.exitScope 4).endOK _) (((hKd.exitScope 4).exitScope 3).endOK _)
    (fun _ => by simp [Stmt.movedFirst, Stmt.assigns]) (fun h => by simp [Ty.holdsDtor] at h)
  refine ⟨_, hun.ofNone, (((hKd.exitScope 4).exitScope 3).exitScope 2), ?_⟩
  simp [exitScope, upd, A2.kill, Kd, A2.setE, killE, hits, intE, Entry.vdeps, R0]

theorem glueS_ok : FnOK P glueS := by
  obtain ⟨Δ, hb, hfl, hr⟩ := glueS_body
  refine ⟨rfl, by decide, by decide, rfl, by simp [glueS], ?_, by simp [glueS], by simp [glueS], by simp [glueS],
    by simp [glueS], by simp [glueS], ?_, Δ, hb, fun v E h => (hfl v E h).2, ?_, ?_⟩
  · intro pt hpt; simp [glueS] at hpt; subst hpt
    simp [GSD, GS, DT, T, Ty.ok, Ty.isStruct, Ty.owning, Ty.holdsView]
  · refine ⟨fun i hi hs _ => ?_, fun i hi b hb _ => ?_, fun h => by simp [glueS] at h⟩
    · simp [glueS] at hi; subst hi; simp [glueS, Stmt.movedFirst, Stmt.assigns]
    · simp [glueS] at hi; subst hi; simp [glueS] at hb
  · exact ⟨{ intE with mode := R0.mode }, by simpa [glueS] using hr, rfl, rfl, by simp [R0, resMode, glueS],
      by simp [intE], by simp [intE], by simp [glueS]⟩
  · intro i hi b hb; simp [glueS] at hi; subst hi; simp [glueS] at hb

/-! ### A struct with its own `% Drop` beside a destructor field (Agora #616) -/

theorem impl_not_thru : ¬ ThruFn P 5 := by
  intro h
  cases h with
  | here hf hb => simp [P] at hf; subst hf; simp [impl, Stmt.hasThru] at hb
  | call hf hg _ => simp [P] at hf; subst hf; simp [impl, Stmt.calls] at hg

theorem impl_dtorOK : DtorOK P 5 GDT :=
  ⟨impl, rfl, rfl, rfl, rfl, rfl, rfl, rfl, fun h => absurd h impl_not_thru⟩

theorem impl_body : StmtT P ξ (sigCtx impl) [] impl.body
    (setE (kill .replace false 1 (sigCtx impl)) 1 { intE with mode := R0.mode }) := by
  have hc : sigCtx impl 1 = some R0 := by simp [↓sigCtx_noRegion (fn := impl) (by decide), impl, R0, resMode]
  have hflags : ∀ v E, sigCtx impl v = some E → E.dtor = false ∧ E.dbind = false := by
    intro v E h
    rcases v with _ | _ | v <;> simp [↓sigCtx_noRegion (fn := impl) (by decide), impl, paramE, resMode] at h <;> subst h <;> exact ⟨rfl, rfl⟩
  exact StmtT.assign (Ex := R0) (E := intE) hc (by simp) (Or.inr (Or.inr ⟨rfl, rfl⟩))
    (RhsT.expr ExprT.lit) rfl (by simp [intE, roots, Entry.vdeps, Mode.ownSlot]) (by simp [hc])
    (by
      intro p E hp hm d hd _
      rcases p with _ | _ | p <;> simp [↓sigCtx_noRegion (fn := impl) (by decide), impl, paramE, resMode, GDT, GT, DT, T, Ty.hasFn] at hp <;>
        subst hp <;> simp [Entry.vdeps, Mode.ownSlot] at hd <;> simp at hm)
    (DtorSafe.of_none (fun v E h => (hflags v E h).1) _ _ _) rfl

theorem impl_ok : FnOK P impl := by
  refine ⟨rfl, by decide, by decide, rfl, by simp [impl], ?_, by simp [impl], by simp [impl], by simp [impl],
    by simp [impl], by simp [impl], ?_, _, impl_body, ?_, ?_, ?_⟩
  · intro pt hpt; simp [impl] at hpt; subst hpt; simp [GDT, GT, DT, T, Ty.ok, Ty.isStruct]
  · refine ⟨fun i hi hs _ => ?_, fun i hi b hb _ => ?_, fun h => by simp [impl] at h⟩
    · simp [impl] at hi; subst hi; simp [impl] at hs
    · simp [impl] at hi; subst hi; simp [impl] at hb
  · intro v E h
    rcases v with _ | _ | v <;> simp [setE, upd, kill, killE, ↓sigCtx_noRegion (fn := impl) (by decide), impl, paramE, intE] at h <;>
      subst h <;> exact ⟨rfl, rfl⟩
  · exact ⟨{ intE with mode := R0.mode }, by simp [setE, upd, impl], rfl, rfl, by simp [R0, resMode, impl],
      by simp [intE], by simp [intE], by simp [impl]⟩
  · intro i hi b hb; simp [impl] at hi; subst hi; simp [impl] at hb

theorem glue2_not_thru : ¬ ThruFn P 6 := by
  intro h
  cases h with
  | here hf hb => simp [P] at hf; subst hf; simp [glue2, Stmt.hasThru] at hb
  | call hf hg ht =>
    simp [P] at hf; subst hf; simp [glue2, Stmt.calls] at hg
    rcases hg with rfl | rfl
    · exact glue_not_thru ht
    · exact impl_not_thru ht

theorem glue2_implOK : ImplGlueOK P 6 GT 4 5 :=
  ⟨glue2, 2, 3, .lit 0, rfl, rfl, rfl, rfl, rfl, rfl, rfl, rfl, fun h => absurd h glue2_not_thru,
    Or.inl glue_glueOK, impl_dtorOK, rfl⟩

theorem impldrop_ok : DropFnOK P 6 GT := Or.inr (Or.inr (Or.inl ⟨4, 5, glue2_implOK⟩))

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
  have hcall : CallT P Kb [] 5 [2] (callRes Kb impl [2]) Kb := by
    refine ⟨impl, rfl, by simp [impl], fun i hi => ?_, fun d hd => ?_,
      CallDtorSafe.of_inp (by simp [impl]) hnm, rfl, (callPost_dtor (t := GDT) rfl hnm).symm,
      fun h => absurd h impl_not_thru⟩
    · have hi0 : i = 0 := by simp [impl] at hi; omega
      subst hi0
      refine ⟨EW, by simp [hb2], by rw [hEW], ?_, fun h => ?_, fun h => ?_⟩
      · simp [impl, paramOK, hEW]
      · simp [impl, PMode.moves] at h
      · simp [impl] at h
    · rw [hnm] at hd; cases hd
  have hER : (callRes Kb impl [2]).mode ≠ .rootb ∧ (callRes Kb impl [2]).dtor = false ∧
      (callRes Kb impl [2]).dbind = false := by simp [callRes, resMode, impl]
  let Kc : Ctx := A2.setE Kb 3 (callRes Kb impl [2])
  have hKc : NoRootb Kc := hKb.setE hER
  have hc1 : Kc 1 = some R0 := by
    simp [Kc, Kb, Ka, A2.setE, upd, A2.kill, h1, killE, hits, R0, Entry.vdeps]
  let Kd : Ctx := A2.setE (kill .replace false 1 Kc) 1 { intE with mode := R0.mode }
  have hKd : NoRootb Kd := (hKc.kill _ _ _).setE (by simp [intE, R0])
  have hasg : StmtT P .none Kc [] (.assign 1 (.expr (.lit 0))) Kd :=
    StmtT.assign (Ex := R0) (E := intE) hc1 (by simp) (Or.inr (Or.inr ⟨rfl, rfl⟩))
      (RhsT.expr ExprT.lit) rfl (by simp [intE, roots, Entry.vdeps, Mode.ownSlot]) (by simp [hc1])
      (hKc.noPin _) (DtorSafe.of_none (fun v E h => (hKc v E h).2.1) _ _ _) rfl
  have hlc := StmtT.letcall (ξ := .none) (P := P) (Γ := Kb) (F := []) (x := 3) (f := 5) (args := [2])
    (s := .assign 1 (.expr (.lit 0))) rfl (by simp [Kb, Ka, A2.setE, upd, A2.kill, ↓sigCtx_noRegion (fn := glue2) (by decide), glue2]) (by simp)
    hcall hasg.ofNone (hKd.endOK _)
    (fun fn' hf' ho _ => by simp [P] at hf'; subst hf'; simp [impl] at ho)
  have hlet := StmtT.letd (ξ := .none) (P := P) (Γ := sigCtx glue2) (Γ1 := Ka) (F := []) (x := 2) (f := 4) (r := .var 0)
    (s := .letcall 3 5 [2] (.assign 1 (.expr (.lit 0)))) (t := GT) (H := ES2.held) (τ := GDT) rfl
    (by simp [↓sigCtx_noRegion (fn := glue2) (by decide), glue2]) (by simp) hmv rfl
    (Or.inl ⟨rfl, Or.inr ⟨6, rfl⟩⟩) rfl rfl
    ⟨⟨gluedrop_ok, fun g hg _ => by
      have hg6 : g = 6 := (Ty.dtor.inj hg).1.symm
      subst hg6
      exact ⟨5, 3, _, glue2_implOK, rfl⟩⟩,
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

/-! ### An enum's glue (Agora #632): `ofn`

`@ ofn sink self → i { ? ( isl self ) { :drop y ( takel self )  = r 0 } { = r 0 } }`:
the glue takes the enum owned and matches on its tag; the payload that
holds a destructor value moves out to a `letd`. -/

theorem ofn_not_thru : ¬ ThruFn P 2 := by
  intro h
  cases h with
  | here hf hb => simp [P] at hf; subst hf; simp [ofn, Stmt.hasThru] at hb
  | call hf hg ht => simp [P] at hf; subst hf; simp [ofn, Stmt.calls] at hg; subst hg; exact dfn_not_thru ht

theorem ofn_enumOK : EnumGlueOK P 2 OT :=
  ⟨ofn, DT, .int, _, _, rfl, rfl, rfl, rfl, rfl, rfl, rfl, rfl, fun h => absurd h ofn_not_thru, rfl, rfl, rfl,
    fun _ => ⟨2, 0, _, rfl⟩, fun h => absurd h (by decide)⟩

theorem odrop_ok : DropFnOK P 2 OT := Or.inr (Or.inr (Or.inr (Or.inl ofn_enumOK)))

theorem ofn_body : ∃ Δ, StmtT P ξ (sigCtx ofn) [] ofn.body Δ ∧
    (∀ v E, Δ v = some E → E.mode ≠ .rootb ∧ E.dtor = false ∧ E.dbind = false) ∧
    Δ 1 = some { intE with mode := R0.mode } := by
  let E0 : Entry := ⟨ODT, .own, true, [], [], false, false, false, false⟩
  let I : Entry := { intE with mode := R0.mode }
  have h0 : sigCtx ofn 0 = some E0 := by simp [↓sigCtx_noRegion (fn := ofn) (by decide), ofn, paramE, E0, ODT, OT, DT, T, Ty.hasFn]
  have h1 : sigCtx ofn 1 = some R0 := by simp [↓sigCtx_noRegion (fn := ofn) (by decide), ofn, R0, resMode]
  have h2 : ∀ v : Nat, v ≠ 0 → v ≠ 1 → sigCtx ofn v = none := by
    intro v hv0 hv1
    have hlt : ¬ v < 1 := fun h => hv0 (Nat.lt_one_iff.mp h)
    simp [↓sigCtx_noRegion (fn := ofn) (by decide), ofn, hlt, hv1]
  have hS : NoRootb (sigCtx ofn) := by
    intro v E h
    rcases v with _ | _ | v
    · rw [h0] at h; cases h; simp [E0]
    · rw [h1] at h; cases h; simp [R0]
    · rw [h2 _ (by simp) (by simp)] at h; cases h
  have hSd : NoDeps (sigCtx ofn) := by
    intro v E h
    rcases v with _ | _ | v
    · rw [h0] at h; cases h; rfl
    · rw [h1] at h; cases h; rfl
    · rw [h2 _ (by simp) (by simp)] at h; cases h
  -- the arm that takes the payload out
  let Ka : Ctx := A2.setE (kill .replace false 0 (sigCtx ofn)) 0 { E0 with live := false, dtor := false }
  have hKa : NoRootb Ka := (hS.kill _ _ _).setE (by simp [E0])
  have hKad : NoDeps Ka := (hSd.kill _ _ _).setE rfl
  have hEx : compE E0 DT = ⟨DT, .own, true, [], [], false, false, false, false⟩ := by
    simp [compE, E0, ownHeld, DT, T]
  have htk : RhsT (sigCtx ofn) [] (.takel 0) (compE E0 DT) Ka :=
    RhsT.takel (b := .int) h0 rfl rfl (Or.inr ⟨2, rfl, by decide⟩) (by simp) (hS.noPin _)
      (DtorSafe.of_none (fun v E h => (hS v E h).2.1) _ _ _)
  let ED : Entry := Entry.arm { compE E0 DT with ty := DT, held := (compE E0 DT).held }
  have hED : ED = ⟨DT, .own, true, [], [], false, false, false, false⟩ := by
    simp only [ED]; rw [hEx]; simp [Entry.arm, DT, T, Ty.dtorViews, Ty.holdsView]
  let Kb : Ctx := A2.setE Ka 2 ED
  have hKb : NoRootb Kb := hKa.setE (by rw [hED]; simp)
  have hKbd : NoDeps Kb := hKad.setE (by rw [hED]; rfl)
  have hc1 : Kb 1 = some R0 := by
    simp [Kb, Ka, A2.setE, upd, hSd.kill_eq, h1]
  let Kc : Ctx := A2.setE (kill .replace false 1 Kb) 1 I
  have hKc : NoRootb Kc := (hKb.kill _ _ _).setE (by simp [I, intE, R0])
  have hKcd : NoDeps Kc := (hKbd.kill _ _ _).setE rfl
  have hasg1 : StmtT P .none Kb [] (.assign 1 (.expr (.lit 0))) Kc :=
    StmtT.assign (Ex := R0) (E := intE) hc1 (by simp) (Or.inr (Or.inr ⟨rfl, rfl⟩))
      (RhsT.expr ExprT.lit) rfl (by simp [intE, roots, Entry.vdeps, Mode.ownSlot]) (by simp [hc1])
      (hKb.noPin _) (DtorSafe.of_none (fun v E h => (hKb v E h).2.1) _ _ _) rfl
  have harm1 := StmtT.letd (ξ := .none) (P := P) (Γ := sigCtx ofn) (Γ1 := Ka) (F := []) (x := 2) (f := 0) (r := .takel 0)
    (s := .assign 1 (.expr (.lit 0))) (t := T) (H := (compE E0 DT).held) (τ := DT) rfl
    (h2 2 (by decide) (by decide)) (by simp) htk (by rw [hEx])
    (Or.inl ⟨rfl, Or.inr ⟨0, by rw [hEx]; rfl⟩⟩) rfl rfl
    ⟨LetdFn.of drop_ok (fun g hg => by rw [hEx] at hg; exact (Ty.dtor.inj hg).1.symm),
      fun y Ey g u hr hy hgy => by
        have hy0 : y = 0 := by rcases hr with hr | hr <;> cases hr <;> rfl
        subst hy0
        rw [h0] at hy; cases hy
        cases hgy
        exact ofn_enumOK⟩
    (HeldUp.refl _ _) hasg1.ofNone (hKc.endOK _) (by simp [Stmt.assigns])
  -- the arm that takes nothing: the enum stays, and its scope frees it
  let Δ2 : Ctx := A2.setE (kill .replace false 1 (sigCtx ofn)) 1 I
  have hasg2 : StmtT P .none (sigCtx ofn) [] (.assign 1 (.expr (.lit 0))) Δ2 :=
    StmtT.assign (Ex := R0) (E := intE) h1 (by simp) (Or.inr (Or.inr ⟨rfl, rfl⟩))
      (RhsT.expr ExprT.lit) rfl (by simp [intE, roots, Entry.vdeps, Mode.ownSlot]) (by simp [h1])
      (hS.noPin _) (DtorSafe.of_none (fun v E h => (hS v E h).2.1) _ _ _) rfl
  let Δ1 : Ctx := exitScope 2 Kc
  have hΔ1r : NoRootb Δ1 := hKc.exitScope 2
  have hΔ1d : NoDeps Δ1 := by
    intro v E h
    simp only [Δ1, exitScope] at h
    by_cases hv : v = 2
    · subst hv; simp at h
    · rw [upd_ne _ _ hv] at h; exact (hKcd.kill _ _ _) v E h
  have hw : Weaker Δ2 Δ1 := by
    refine ⟨fun v => ?_, hΔ1d.wf hΔ1r, hΔ1d.names⟩
    have e1 : Δ1 v = if v = 2 then none else if v = 1 then some I else if v = 0 then
        some { E0 with live := false, dtor := false } else none := by
      simp only [Δ1, exitScope, hKcd.kill_eq]
      by_cases hv2 : v = 2
      · subst hv2; simp
      · rw [upd_ne _ _ hv2]; simp only [hv2, ↓reduceIte, Kc, A2.setE]
        by_cases hv1 : v = 1
        · subst hv1; simp
        · rw [upd_ne _ _ hv1, hKbd.kill_eq]; simp only [hv1, ↓reduceIte, Kb, A2.setE, upd_ne _ _ hv2, Ka]
          by_cases hv0 : v = 0
          · subst hv0; simp
          · rw [upd_ne _ _ hv0, hSd.kill_eq, h2 v hv0 hv1]; simp [hv0]
    have e2 : Δ2 v = if v = 1 then some I else if v = 0 then some E0 else none := by
      simp only [Δ2, A2.setE, hSd.kill_eq]
      by_cases hv1 : v = 1
      · subst hv1; simp
      · rw [upd_ne _ _ hv1]; simp only [hv1, ↓reduceIte]
        by_cases hv0 : v = 0
        · subst hv0; simp [h0]
        · simp only [hv0, ↓reduceIte]; exact h2 v hv0 hv1
    rw [e1, e2]
    by_cases hv2 : v = 2
    · subst hv2; simp
    by_cases hv1 : v = 1
    · subst hv1; simp; exact EntryWeaker.refl _
    by_cases hv0 : v = 0
    · subst hv0
      simp only [hv2, hv1, ↓reduceIte, reduceCtorEq, Option.some.injEq, true_and]
      intro E E' hE hE'
      subst hE; subst hE'
      exact ⟨rfl, rfl, fun hf => by simp [Entry.fixed, E0] at hf, fun hl => by simp at hl,
        fun hd => by simp [E0] at hd, rfl, fun hd => by simp at hd, fun hd => by simp [E0] at hd,
      fun _ _ _ hfr => by fresh_ew,
      fun _ _ hhf => by heldfresh_ew⟩
    · simp [hv2, hv1, hv0]
  have harm2 : StmtT P .none (sigCtx ofn) [] (.assign 1 (.expr (.lit 0))) Δ1 :=
    StmtT.sub (Weaker.refl (hSd.wf hS) hSd.names) hasg2 (Or.inr hw)
  refine ⟨Δ1, StmtT.ite rfl rfl (ExprT.isl h0 rfl rfl) harm1.ofNone harm2.ofNone, hΔ1r, ?_⟩
  show exitScope 2 Kc 1 = some I
  simp only [exitScope]
  rw [upd_ne _ _ (by decide), hKcd.kill_eq]
  simp [Kc, A2.setE]

theorem ofn_ok : FnOK P ofn := by
  obtain ⟨Δ, hb, hfl, hr⟩ := ofn_body
  refine ⟨rfl, by decide, by decide, rfl, by simp [ofn], ?_, by simp [ofn], by simp [ofn], by simp [ofn],
    by simp [ofn], by simp [ofn], ?_, Δ, hb, fun v E h => (hfl v E h).2, ?_, ?_⟩
  · intro pt hpt; simp [ofn] at hpt; subst hpt; simp [ODT, OT, DT, T, Ty.ok, Ty.isStruct, Ty.owning]
  · refine ⟨fun i hi hs _ => ?_, fun i hi b hb _ => ?_, fun h => by simp [ofn] at h⟩
    · simp [ofn] at hi; subst hi
      exact ⟨Or.inr ⟨2, OT, rfl, Or.inl ofn_enumOK⟩, by simp [ofn, Stmt.assigns]⟩
    · simp [ofn] at hi; subst hi; simp [ofn] at hb
  · exact ⟨{ intE with mode := R0.mode }, by simpa [ofn] using hr, rfl, rfl, by simp [R0, resMode, ofn],
      by simp [intE], by simp [intE], by simp [ofn]⟩
  · intro i hi b hb; simp [ofn] at hi; subst hi; simp [ofn] at hb

/-! ### An enum's glue (Agora #632): `gfn`

`@ gfn sink self → i { ? ( isl self ) { :drop y ( takel self )  = r 0 } { = r 0 } }`:
the glue takes the enum owned and matches on its tag; the payload that
holds a destructor value moves out to a `letd`. -/

theorem gfn_not_thru : ¬ ThruFn P 3 := by
  intro h
  cases h with
  | here hf hb => simp [P] at hf; subst hf; simp [gfn, Stmt.hasThru] at hb
  | call hf hg ht => simp [P] at hf; subst hf; simp [gfn, Stmt.calls] at hg; subst hg; exact glue_not_thru ht

theorem gfn_enumOK : EnumGlueOK P 3 ST :=
  ⟨gfn, AT, .int, _, _, rfl, rfl, rfl, rfl, rfl, rfl, rfl, rfl, fun h => absurd h gfn_not_thru, rfl, rfl, rfl,
    fun _ => ⟨2, 4, _, rfl⟩, fun h => absurd h (by decide)⟩

theorem gdrop_ok : DropFnOK P 3 ST := Or.inr (Or.inr (Or.inr (Or.inl gfn_enumOK)))

theorem gfn_body : ∃ Δ, StmtT P ξ (sigCtx gfn) [] gfn.body Δ ∧
    (∀ v E, Δ v = some E → E.mode ≠ .rootb ∧ E.dtor = false ∧ E.dbind = false) ∧
    Δ 1 = some { intE with mode := R0.mode } := by
  let E0 : Entry := ⟨SDT, .own, true, [], [], false, false, false, false⟩
  let I : Entry := { intE with mode := R0.mode }
  have h0 : sigCtx gfn 0 = some E0 := by simp [↓sigCtx_noRegion (fn := gfn) (by decide), gfn, paramE, E0, SDT, ST, AT, DT, T, Ty.hasFn]
  have h1 : sigCtx gfn 1 = some R0 := by simp [↓sigCtx_noRegion (fn := gfn) (by decide), gfn, R0, resMode]
  have h2 : ∀ v : Nat, v ≠ 0 → v ≠ 1 → sigCtx gfn v = none := by
    intro v hv0 hv1
    have hlt : ¬ v < 1 := fun h => hv0 (Nat.lt_one_iff.mp h)
    simp [↓sigCtx_noRegion (fn := gfn) (by decide), gfn, hlt, hv1]
  have hS : NoRootb (sigCtx gfn) := by
    intro v E h
    rcases v with _ | _ | v
    · rw [h0] at h; cases h; simp [E0]
    · rw [h1] at h; cases h; simp [R0]
    · rw [h2 _ (by simp) (by simp)] at h; cases h
  have hSd : NoDeps (sigCtx gfn) := by
    intro v E h
    rcases v with _ | _ | v
    · rw [h0] at h; cases h; rfl
    · rw [h1] at h; cases h; rfl
    · rw [h2 _ (by simp) (by simp)] at h; cases h
  -- the arm that takes the payload out
  let Ka : Ctx := A2.setE (kill .replace false 0 (sigCtx gfn)) 0 { E0 with live := false, dtor := false }
  have hKa : NoRootb Ka := (hS.kill _ _ _).setE (by simp [E0])
  have hKad : NoDeps Ka := (hSd.kill _ _ _).setE rfl
  have hEx : compE E0 AT = ⟨AT, .own, true, [], [], false, false, false, false⟩ := by
    simp [compE, E0, ownHeld, AT, DT, T]
  have htk : RhsT (sigCtx gfn) [] (.takel 0) (compE E0 AT) Ka :=
    RhsT.takel (b := .int) h0 rfl rfl (Or.inr ⟨3, rfl, by decide⟩) (by simp) (hS.noPin _)
      (DtorSafe.of_none (fun v E h => (hS v E h).2.1) _ _ _)
  let ED : Entry := Entry.arm { compE E0 AT with ty := GDT, held := (compE E0 AT).held }
  have hED : ED = ⟨GDT, .own, true, [], [], false, false, false, false⟩ := by
    simp only [ED]; rw [hEx]; simp [Entry.arm, GDT, GT, DT, T, Ty.dtorViews, Ty.holdsView]
  let Kb : Ctx := A2.setE Ka 2 ED
  have hKb : NoRootb Kb := hKa.setE (by rw [hED]; simp)
  have hKbd : NoDeps Kb := hKad.setE (by rw [hED]; rfl)
  have hc1 : Kb 1 = some R0 := by
    simp [Kb, Ka, A2.setE, upd, hSd.kill_eq, h1]
  let Kc : Ctx := A2.setE (kill .replace false 1 Kb) 1 I
  have hKc : NoRootb Kc := (hKb.kill _ _ _).setE (by simp [I, intE, R0])
  have hKcd : NoDeps Kc := (hKbd.kill _ _ _).setE rfl
  have hasg1 : StmtT P .none Kb [] (.assign 1 (.expr (.lit 0))) Kc :=
    StmtT.assign (Ex := R0) (E := intE) hc1 (by simp) (Or.inr (Or.inr ⟨rfl, rfl⟩))
      (RhsT.expr ExprT.lit) rfl (by simp [intE, roots, Entry.vdeps, Mode.ownSlot]) (by simp [hc1])
      (hKb.noPin _) (DtorSafe.of_none (fun v E h => (hKb v E h).2.1) _ _ _) rfl
  have harm1 := StmtT.letd (ξ := .none) (P := P) (Γ := sigCtx gfn) (Γ1 := Ka) (F := []) (x := 2) (f := 4) (r := .takel 0)
    (s := .assign 1 (.expr (.lit 0))) (t := GT) (H := (compE E0 AT).held) (τ := GDT) rfl
    (h2 2 (by decide) (by decide)) (by simp) htk (by rw [hEx])
    (Or.inl ⟨rfl, Or.inl (by rw [hEx]; rfl)⟩) rfl rfl
    ⟨LetdFn.of gluedrop_ok (fun g hg => by rw [hEx] at hg; exact Ty.noConfusion hg),
      fun y Ey g u hr hy hgy => by
        have hy0 : y = 0 := by rcases hr with hr | hr <;> cases hr <;> rfl
        subst hy0
        rw [h0] at hy; cases hy
        cases hgy
        exact gfn_enumOK⟩
    (HeldUp.refl _ _) hasg1.ofNone (hKc.endOK _) (by simp [Stmt.assigns])
  -- the arm that takes nothing: the enum stays, and its scope frees it
  let Δ2 : Ctx := A2.setE (kill .replace false 1 (sigCtx gfn)) 1 I
  have hasg2 : StmtT P .none (sigCtx gfn) [] (.assign 1 (.expr (.lit 0))) Δ2 :=
    StmtT.assign (Ex := R0) (E := intE) h1 (by simp) (Or.inr (Or.inr ⟨rfl, rfl⟩))
      (RhsT.expr ExprT.lit) rfl (by simp [intE, roots, Entry.vdeps, Mode.ownSlot]) (by simp [h1])
      (hS.noPin _) (DtorSafe.of_none (fun v E h => (hS v E h).2.1) _ _ _) rfl
  let Δ1 : Ctx := exitScope 2 Kc
  have hΔ1r : NoRootb Δ1 := hKc.exitScope 2
  have hΔ1d : NoDeps Δ1 := by
    intro v E h
    simp only [Δ1, exitScope] at h
    by_cases hv : v = 2
    · subst hv; simp at h
    · rw [upd_ne _ _ hv] at h; exact (hKcd.kill _ _ _) v E h
  have hw : Weaker Δ2 Δ1 := by
    refine ⟨fun v => ?_, hΔ1d.wf hΔ1r, hΔ1d.names⟩
    have e1 : Δ1 v = if v = 2 then none else if v = 1 then some I else if v = 0 then
        some { E0 with live := false, dtor := false } else none := by
      simp only [Δ1, exitScope, hKcd.kill_eq]
      by_cases hv2 : v = 2
      · subst hv2; simp
      · rw [upd_ne _ _ hv2]; simp only [hv2, ↓reduceIte, Kc, A2.setE]
        by_cases hv1 : v = 1
        · subst hv1; simp
        · rw [upd_ne _ _ hv1, hKbd.kill_eq]; simp only [hv1, ↓reduceIte, Kb, A2.setE, upd_ne _ _ hv2, Ka]
          by_cases hv0 : v = 0
          · subst hv0; simp
          · rw [upd_ne _ _ hv0, hSd.kill_eq, h2 v hv0 hv1]; simp [hv0]
    have e2 : Δ2 v = if v = 1 then some I else if v = 0 then some E0 else none := by
      simp only [Δ2, A2.setE, hSd.kill_eq]
      by_cases hv1 : v = 1
      · subst hv1; simp
      · rw [upd_ne _ _ hv1]; simp only [hv1, ↓reduceIte]
        by_cases hv0 : v = 0
        · subst hv0; simp [h0]
        · simp only [hv0, ↓reduceIte]; exact h2 v hv0 hv1
    rw [e1, e2]
    by_cases hv2 : v = 2
    · subst hv2; simp
    by_cases hv1 : v = 1
    · subst hv1; simp; exact EntryWeaker.refl _
    by_cases hv0 : v = 0
    · subst hv0
      simp only [hv2, hv1, ↓reduceIte, reduceCtorEq, Option.some.injEq, true_and]
      intro E E' hE hE'
      subst hE; subst hE'
      exact ⟨rfl, rfl, fun hf => by simp [Entry.fixed, E0] at hf, fun hl => by simp at hl,
        fun hd => by simp [E0] at hd, rfl, fun hd => by simp at hd, fun hd => by simp [E0] at hd,
      fun _ _ _ hfr => by fresh_ew,
      fun _ _ hhf => by heldfresh_ew⟩
    · simp [hv2, hv1, hv0]
  have harm2 : StmtT P .none (sigCtx gfn) [] (.assign 1 (.expr (.lit 0))) Δ1 :=
    StmtT.sub (Weaker.refl (hSd.wf hS) hSd.names) hasg2 (Or.inr hw)
  refine ⟨Δ1, StmtT.ite rfl rfl (ExprT.isl h0 rfl rfl) harm1.ofNone harm2.ofNone, hΔ1r, ?_⟩
  show exitScope 2 Kc 1 = some I
  simp only [exitScope]
  rw [upd_ne _ _ (by decide), hKcd.kill_eq]
  simp [Kc, A2.setE]

theorem gfn_ok : FnOK P gfn := by
  obtain ⟨Δ, hb, hfl, hr⟩ := gfn_body
  refine ⟨rfl, by decide, by decide, rfl, by simp [gfn], ?_, by simp [gfn], by simp [gfn], by simp [gfn],
    by simp [gfn], by simp [gfn], ?_, Δ, hb, fun v E h => (hfl v E h).2, ?_, ?_⟩
  · intro pt hpt; simp [gfn] at hpt; subst hpt; simp [SDT, ST, AT, DT, T, Ty.ok, Ty.isStruct, Ty.owning]
  · refine ⟨fun i hi hs _ => ?_, fun i hi b hb _ => ?_, fun h => by simp [gfn] at h⟩
    · simp [gfn] at hi; subst hi
      exact ⟨Or.inr ⟨3, ST, rfl, Or.inl gfn_enumOK⟩, by simp [gfn, Stmt.assigns]⟩
    · simp [gfn] at hi; subst hi; simp [gfn] at hb
  · exact ⟨{ intE with mode := R0.mode }, by simpa [gfn] using hr, rfl, rfl, by simp [R0, resMode, gfn],
      by simp [intE], by simp [intE], by simp [gfn]⟩
  · intro i hi b hb; simp [gfn] at hi; subst hi; simp [gfn] at hb

/-! ### An enum with a destructor payload and a view payload (Agora #750): `ofnV`

`sum DT (slice int)`: the glue takes the enum owned and matches on its tag;
the destructor payload moves out to a `letd`, the view payload is a borrow
that ends with the glue's scope.  The glue sees its parameter as holding
nothing (`paramE`): what the view is valid through is the caller's, which
the call keeps, as for a struct's (`glueS`). -/

theorem ofnV_not_thru : ¬ ThruFn P 9 := by
  intro h
  cases h with
  | here hf hb => simp [P] at hf; subst hf; simp [ofnV, Stmt.hasThru] at hb
  | call hf hg ht => simp [P] at hf; subst hf; simp [ofnV, Stmt.calls] at hg; subst hg; exact dfn_not_thru ht

theorem ofnV_enumOK : EnumGlueOK P 9 OV :=
  ⟨ofnV, DT, .slice .int, _, _, rfl, rfl, rfl, rfl, rfl, rfl, rfl, rfl, fun h => absurd h ofnV_not_thru, rfl, rfl, rfl,
    fun _ => ⟨2, 0, _, rfl⟩, fun h => absurd h (by decide)⟩

theorem ovdrop_ok : DropFnOK P 9 OV := Or.inr (Or.inr (Or.inr (Or.inl ofnV_enumOK)))

theorem ofnV_body : ∃ Δ, StmtT P ξ (sigCtx ofnV) [] ofnV.body Δ ∧
    (∀ v E, Δ v = some E → E.mode ≠ .rootb ∧ E.dtor = false ∧ E.dbind = false) ∧
    Δ 1 = some { intE with mode := R0.mode } := by
  -- AGORA-937: the parameter holds views (the slice payload), so it views
  -- its region `π 0`, at `ofnV.nvars + 0 = 3`
  let E0 : Entry := ⟨OVD, .own, true, [], [⟨3, .self⟩], false, false, false, false⟩
  let I : Entry := { intE with mode := R0.mode }
  have h0 : sigCtx ofnV 0 = some E0 := by
    simp [sigCtx, ofnV, paramE, E0, OVD, OV, DT, T, Ty.hasFn, regionP, regioned, Ty.holdsView]
  have h1 : sigCtx ofnV 1 = some R0 := by simp [sigCtx, ofnV, R0, resMode]
  have h3 : sigCtx ofnV 3 = some regionE := by
    simp [sigCtx, isRegionIdx, ofnV, regioned, OVD, OV, Ty.holdsView]
  have h2 : ∀ v : Nat, v ≠ 0 → v ≠ 1 → v ≠ 3 → sigCtx ofnV v = none := by
    intro v hv0 hv1 hv3
    cases h : sigCtx ofnV v with
    | none => rfl
    | some E =>
      exfalso
      rcases sigCtx_cases h with ⟨hv, _⟩ | ⟨hv, _⟩ | ⟨_, hle, hlt, _⟩
      · simp [ofnV] at hv; omega
      · simp [ofnV] at hv; omega
      · simp [ofnV] at hle hlt; omega
  have hS : NoRootb (sigCtx ofnV) := by
    intro v E h
    by_cases hv0 : v = 0
    · subst hv0; rw [h0] at h; cases h; simp [E0]
    by_cases hv1 : v = 1
    · subst hv1; rw [h1] at h; cases h; simp [R0]
    by_cases hv3 : v = 3
    · subst hv3; rw [h3] at h; cases h; simp [regionE]
    rw [h2 v hv0 hv1 hv3] at h; cases h
  have hSd : RegDeps 3 (sigCtx ofnV) := by
    intro v E h d hd
    by_cases hv0 : v = 0
    · subst hv0; rw [h0] at h; cases h; simp [E0, Entry.vdeps, Mode.ownSlot] at hd; subst hd; exact ⟨rfl, rfl⟩
    by_cases hv1 : v = 1
    · subst hv1; rw [h1] at h; cases h; simp [R0, Entry.vdeps, Mode.ownSlot] at hd
    by_cases hv3 : v = 3
    · subst hv3; rw [h3] at h; cases h; simp [regionE, Entry.vdeps, Mode.ownSlot] at hd
    rw [h2 v hv0 hv1 hv3] at h; cases h
  have hSwf : CtxWF (sigCtx ofnV) := hSd.wf hS ⟨regionE, h3, rfl⟩
  -- the arm that takes the destructor payload out
  let Ka : Ctx := A2.setE (kill .replace false 0 (sigCtx ofnV)) 0 { E0 with live := false, dtor := false }
  have hKa : NoRootb Ka := (hS.kill _ _ _).setE (by simp [E0])
  have hKad : RegDeps 3 Ka := (hSd.kill _ _ _).setE (by simp [E0, Entry.vdeps, Mode.ownSlot, Kind.isName])
  have hEx : compE E0 DT = ⟨DT, .own, true, [], [], false, false, false, false⟩ := by
    simp [compE, ownHeld, DT, T, Ty.holdsView]
  have htk : RhsT (sigCtx ofnV) [] (.takel 0) (compE E0 DT) Ka :=
    RhsT.takel (b := .slice .int) h0 rfl rfl (Or.inr ⟨9, rfl, by decide⟩) (by simp) (hS.noPin _)
      (DtorSafe.of_none (fun v E h => (hS v E h).2.1) _ _ _)
  let ED : Entry := Entry.arm { compE E0 DT with ty := DT, held := (compE E0 DT).held }
  have hED : ED = ⟨DT, .own, true, [], [], false, false, false, false⟩ := by
    simp only [ED]; rw [hEx]; simp [Entry.arm, DT, T, Ty.dtorViews, Ty.holdsView]
  let Kb : Ctx := A2.setE Ka 2 ED
  have hKb : NoRootb Kb := hKa.setE (by rw [hED]; simp)
  have hKbd : RegDeps 3 Kb := hKad.setE (by rw [hED]; simp [Entry.vdeps])
  have hc1 : Kb 1 = some R0 := by
    simp [Kb, Ka, A2.setE, upd, hSd.kill_eq .replace false (show (0 : Nat) ≠ 3 by decide), h1]
  let Kc : Ctx := A2.setE (kill .replace false 1 Kb) 1 I
  have hKc : NoRootb Kc := (hKb.kill _ _ _).setE (by simp [I, intE, R0])
  have hKcd : RegDeps 3 Kc := (hKbd.kill _ _ _).setE (by simp [I, intE, Entry.vdeps])
  have hasg1 : StmtT P .none Kb [] (.assign 1 (.expr (.lit 0))) Kc :=
    StmtT.assign (Ex := R0) (E := intE) hc1 (by simp) (Or.inr (Or.inr ⟨rfl, rfl⟩))
      (RhsT.expr ExprT.lit) rfl (by simp [intE, roots, Entry.vdeps, Mode.ownSlot]) (by simp [hc1])
      (hKb.noPin _) (DtorSafe.of_none (fun v E h => (hKb v E h).2.1) _ _ _) rfl
  have harm1 := StmtT.letd (ξ := .none) (P := P) (Γ := sigCtx ofnV) (Γ1 := Ka) (F := []) (x := 2) (f := 0) (r := .takel 0)
    (s := .assign 1 (.expr (.lit 0))) (t := T) (H := (compE E0 DT).held) (τ := DT) rfl
    (h2 2 (by decide) (by decide) (by decide)) (by simp) htk (by rw [hEx])
    (Or.inl ⟨rfl, Or.inr ⟨0, by rw [hEx]; rfl⟩⟩) rfl rfl
    ⟨LetdFn.of drop_ok (fun g hg => by rw [hEx] at hg; exact (Ty.dtor.inj hg).1.symm),
      fun y Ey g u hr hy hgy => by
        have hy0 : y = 0 := by rcases hr with hr | hr <;> cases hr <;> rfl
        subst hy0
        rw [h0] at hy; cases hy
        cases hgy
        exact ofnV_enumOK⟩
    (HeldUp.refl _ _) hasg1.ofNone (hKc.endOK _) (by simp [Stmt.assigns])
  -- the view arm takes nothing: the enum stays, and its scope frees it
  let Δ2 : Ctx := A2.setE (kill .replace false 1 (sigCtx ofnV)) 1 I
  have hasg2 : StmtT P .none (sigCtx ofnV) [] (.assign 1 (.expr (.lit 0))) Δ2 :=
    StmtT.assign (Ex := R0) (E := intE) h1 (by simp) (Or.inr (Or.inr ⟨rfl, rfl⟩))
      (RhsT.expr ExprT.lit) rfl (by simp [intE, roots, Entry.vdeps, Mode.ownSlot]) (by simp [h1])
      (hS.noPin _) (DtorSafe.of_none (fun v E h => (hS v E h).2.1) _ _ _) rfl
  let Δ1 : Ctx := exitScope 2 Kc
  have hΔ1r : NoRootb Δ1 := hKc.exitScope 2
  have hΔ1d : RegDeps 3 Δ1 := by
    intro v E h
    simp only [Δ1, exitScope] at h
    by_cases hv : v = 2
    · subst hv; simp at h
    · rw [upd_ne _ _ hv] at h; exact (hKcd.kill _ _ _) v E h
  have e1 : ∀ v, Δ1 v = if v = 2 then none else if v = 1 then some I else if v = 0 then
      some { E0 with live := false, dtor := false } else sigCtx ofnV v := by
    intro v
    simp only [Δ1, exitScope, hKcd.kill_eq .replace false (show (2 : Nat) ≠ 3 by decide)]
    by_cases hv2 : v = 2
    · subst hv2; simp
    · rw [upd_ne _ _ hv2]; simp only [hv2, ↓reduceIte, Kc, A2.setE]
      by_cases hv1 : v = 1
      · subst hv1; simp
      · rw [upd_ne _ _ hv1, hKbd.kill_eq .replace false (show (1 : Nat) ≠ 3 by decide)]
        simp only [hv1, ↓reduceIte, Kb, A2.setE, upd_ne _ _ hv2, Ka]
        by_cases hv0 : v = 0
        · subst hv0; simp
        · rw [upd_ne _ _ hv0, hSd.kill_eq .replace false (show (0 : Nat) ≠ 3 by decide)]; simp [hv0]
  have e2 : ∀ v, Δ2 v = if v = 1 then some I else sigCtx ofnV v := by
    intro v
    simp only [Δ2, A2.setE, hSd.kill_eq .replace false (show (1 : Nat) ≠ 3 by decide)]
    by_cases hv1 : v = 1
    · subst hv1; simp
    · rw [upd_ne _ _ hv1]; simp [hv1]
  have hΔ13 : Δ1 3 = some regionE := by rw [e1 3]; simpa using h3
  have hw : Weaker Δ2 Δ1 := by
    refine ⟨fun v => ?_, hΔ1d.wf hΔ1r ⟨regionE, hΔ13, rfl⟩, hΔ1d.names⟩
    rw [e1, e2]
    by_cases hv2 : v = 2
    · subst hv2; simp [h2 2 (by decide) (by decide) (by decide)]
    by_cases hv1 : v = 1
    · subst hv1; simp; exact EntryWeaker.refl _
    by_cases hv0 : v = 0
    · subst hv0
      simp only [hv2, hv1, ↓reduceIte, reduceCtorEq, Option.some.injEq, true_and, h0]
      intro E E' hE hE'
      subst hE; subst hE'
      exact ⟨rfl, rfl, fun hf => by simp [Entry.fixed, E0] at hf, fun hl => by simp at hl,
        fun hd => by simp [E0] at hd, rfl, fun hd => by simp at hd, fun hd => by simp [E0] at hd,
      fun _ _ _ hfr => by fresh_ew,
      fun _ _ hhf => by heldfresh_ew⟩
    · simp only [hv2, hv1, hv0, ↓reduceIte]
      exact ⟨by simp, fun E E' hE hE' => by rw [hE] at hE'; cases hE'; exact EntryWeaker.refl _⟩
  have harm2 : StmtT P .none (sigCtx ofnV) [] (.assign 1 (.expr (.lit 0))) Δ1 :=
    StmtT.sub (Weaker.refl hSwf hSd.names) hasg2 (Or.inr hw)
  refine ⟨Δ1, StmtT.ite rfl rfl (ExprT.isl h0 rfl rfl) harm1.ofNone harm2.ofNone, hΔ1r, ?_⟩
  show exitScope 2 Kc 1 = some I
  simp only [exitScope]
  rw [upd_ne _ _ (by decide), hKcd.kill_eq .replace false (show (2 : Nat) ≠ 3 by decide)]
  simp [Kc, A2.setE]

theorem ofnV_ok : FnOK P ofnV := by
  obtain ⟨Δ, hb, hfl, hr⟩ := ofnV_body
  refine ⟨rfl, by decide, by decide, rfl, by simp [ofnV], ?_, by simp [ofnV], by simp [ofnV], by simp [ofnV],
    by simp [ofnV], by simp [ofnV], ?_, Δ, hb, fun v E h => (hfl v E h).2, ?_, ?_⟩
  · intro pt hpt; simp [ofnV] at hpt; subst hpt
    simp [OVD, OV, DT, T, Ty.ok, Ty.isStruct, Ty.owning, Ty.holdsView]
  · refine ⟨fun i hi hs _ => ?_, fun i hi b hb _ => ?_, fun h => by simp [ofnV] at h⟩
    · simp [ofnV] at hi; subst hi
      exact ⟨Or.inr ⟨9, OV, rfl, Or.inl ofnV_enumOK⟩, by simp [ofnV, Stmt.assigns]⟩
    · simp [ofnV] at hi; subst hi; simp [ofnV] at hb
  · exact ⟨{ intE with mode := R0.mode }, by simpa [ofnV] using hr, rfl, rfl, by simp [R0, resMode, ofnV],
      by simp [intE], by simp [intE], by simp [ofnV]⟩
  · intro i hi b hb; simp [ofnV] at hi; subst hi; simp [ofnV] at hb

/-! ### A view-holding struct with its own `% Drop` (Agora #750): `implS`, `glueS2`

`GS = prod DT (slice int)` again, its glue `glueS2` rebinding it under the
fields' glue `glueS` and running the impl `implS` on it lent (Agora #616's
shape).  In the glue the rebound binding is armed (its type holds a view),
but it views nothing the glue can see: the glue's parameter holds nothing
(`paramE`). -/

/-- A context with no borrowed parameter and no entry that views anything
    but the glue's parameter region `r` (AGORA-937): an armed binding in it
    reads no view a scope's end in the glue could end. -/
def NoRootbD (r : Var) (Γ : Ctx) : Prop :=
  ∀ v E, Γ v = some E → E.mode ≠ .rootb ∧ ∀ d ∈ E.vdeps, d.root = r ∧ d.kind.isName = false

theorem NoRootbD.setE {r : Var} {Γ : Ctx} (h : NoRootbD r Γ) {x : Var} {E : Entry} (hm : E.mode ≠ .rootb)
    (hE : ∀ d ∈ E.vdeps, d.root = r ∧ d.kind.isName = false) : NoRootbD r (A2.setE Γ x E) := fun v E' hv => by
  by_cases hvx : v = x
  · subst hvx; simp [A2.setE] at hv; subst hv; exact ⟨hm, hE⟩
  · rw [A2.setE, upd_ne _ _ hvx] at hv; exact h v E' hv

theorem NoRootbD.regDeps {r : Var} {Γ : Ctx} (h : NoRootbD r Γ) : RegDeps r Γ :=
  fun v E hE => (h v E hE).2

theorem NoRootbD.kill {r : Var} {Γ : Ctx} (h : NoRootbD r Γ) (e : Eff) (hv : Bool) (x : Var) :
    NoRootbD r (A2.kill e hv x Γ) := fun v E' hv' => by
  refine ⟨?_, h.regDeps.kill e hv x v E' hv'⟩
  simp only [A2.kill] at hv'
  cases h0 : Γ v with
  | none => rw [h0] at hv'; cases hv'
  | some E0 =>
    rw [h0] at hv'; simp only [Option.map_some, Option.some.injEq] at hv'; subst hv'
    have := (h v E0 h0).1
    unfold killE; split
    · simpa using this
    · exact this

theorem NoRootbD.exitScope {r : Var} {Γ : Ctx} (h : NoRootbD r Γ) (x : Var) :
    NoRootbD r (A2.exitScope x Γ) := by
  intro v E' h'
  simp only [A2.exitScope, upd] at h'
  split at h'
  · cases h'
  · exact h.kill .replace false x v E' h'

theorem NoRootbD.noPin {r : Var} {Γ : Ctx} (h : NoRootbD r Γ) (x : Var) : NoPin Γ x :=
  fun p E hp hm => absurd hm (h p E hp).1

theorem NoRootbD.dtorSafe {r : Var} {Γ : Ctx} (h : NoRootbD r Γ) (e : Eff) (hv : Bool) {x : Var}
    (hx : x ≠ r) : DtorSafe Γ e hv x :=
  fun v E hE _ _ => by
    simp only [hitsMem, Bool.and_eq_false_iff]
    right
    simp only [List.any_eq_false, Bool.and_eq_true, beq_iff_eq, not_and]
    intro d hd hdx
    rw [((h v E hE).2 d hd).1] at hdx
    exact absurd hdx.1.symm hx

theorem NoRootbD.endOK {r : Var} {Γ : Ctx} (h : NoRootbD r Γ) {x : Var} (hx : x ≠ r) : EndOK Γ x :=
  ⟨h.noPin x, h.dtorSafe _ _ hx, fun v E hE _ _ _ d hd _ hdx => by
    rw [((h v E hE).2 d hd).1] at hdx; exact hx hdx.symm⟩

theorem implS_not_thru : ¬ ThruFn P 10 := by
  intro h
  cases h with
  | here hf hb => simp [P] at hf; subst hf; simp [implS, Stmt.hasThru] at hb
  | call hf hg _ => simp [P] at hf; subst hf; simp [implS, Stmt.calls] at hg

theorem implS_dtorOK : DtorOK P 10 GSD :=
  ⟨implS, rfl, rfl, rfl, rfl, rfl, rfl, rfl, fun h => absurd h implS_not_thru⟩

theorem implS_body : StmtT P ξ (sigCtx implS) [] implS.body
    (setE (kill .replace false 1 (sigCtx implS)) 1 { intE with mode := R0.mode }) := by
  -- AGORA-937 (item 2): the lent parameter holds views (a slice), so it has a region
  have hc : sigCtx implS 1 = some R0 := by simp [sigCtx, implS, R0, resMode]
  exact StmtT.assign (Ex := R0) (E := intE) hc (by simp) (Or.inr (Or.inr ⟨rfl, rfl⟩))
    (RhsT.expr ExprT.lit) rfl (by simp [intE, roots, Entry.vdeps, Mode.ownSlot]) (by simp [hc])
    (by
      intro p E hp hm d hd hb
      rcases sigCtx_cases hp with ⟨hpl, rfl⟩ | ⟨_, rfl⟩ | ⟨_, _, _, _, rfl⟩
      · rcases mem_regionP_vdeps hd with hd | ⟨rfl, _⟩
        · have hp0 : p = 0 := by simp [implS] at hpl; omega
          subst hp0
          simp [implS, paramE, Entry.vdeps, Mode.ownSlot, GSD, GS, DT, T, Ty.hasFn] at hd
        · simp [Kind.bound] at hb
      · simp [resMode, implS] at hm
      · simp [regionE] at hm)
    (DtorSafe.of_none (fun v E h => (sigCtx_flags h).1) _ _ _) rfl

theorem implS_ok : FnOK P implS := by
  refine ⟨rfl, by decide, by decide, rfl, by simp [implS], ?_, by simp [implS], by simp [implS], by simp [implS],
    by simp [implS], by simp [implS], ?_, _, implS_body, ?_, ?_, ?_⟩
  · intro pt hpt; simp [implS] at hpt; subst hpt
    simp [GSD, GS, DT, T, Ty.ok, Ty.isStruct, Ty.holdsView]
  · refine ⟨fun i hi hs _ => ?_, fun i hi b hb _ => ?_, fun h => by simp [implS] at h⟩
    · simp [implS] at hi; subst hi; simp [implS] at hs
    · simp [implS] at hi; subst hi; simp [implS] at hb
  · intro v E h
    simp only [setE, upd] at h
    split at h
    · cases h; exact ⟨rfl, rfl⟩
    · simp only [A2.kill] at h
      obtain ⟨E0, h0, rfl⟩ := Option.map_eq_some_iff.mp h
      rw [killE_dtor, killE_dbind]; exact sigCtx_flags h0
  · exact ⟨{ intE with mode := R0.mode }, by simp [setE, upd, implS], rfl, rfl, by simp [R0, resMode, implS],
      by simp [intE], by simp [intE], by simp [implS]⟩
  · intro i hi b hb; simp [implS] at hi; subst hi; simp [implS] at hb

theorem glueS2_not_thru : ¬ ThruFn P 11 := by
  intro h
  cases h with
  | here hf hb => simp [P] at hf; subst hf; simp [glueS2, Stmt.hasThru] at hb
  | call hf hg ht =>
    simp [P] at hf; subst hf; simp [glueS2, Stmt.calls] at hg
    rcases hg with rfl | rfl
    · exact glueS_not_thru ht
    · exact implS_not_thru ht

theorem glueS2_implOK : ImplGlueOK P 11 GS 8 10 :=
  ⟨glueS2, 2, 3, .lit 0, rfl, rfl, rfl, rfl, rfl, rfl, rfl, rfl, fun h => absurd h glueS2_not_thru,
    Or.inl glueS_glueOK, implS_dtorOK, rfl⟩

theorem gs2drop_ok : DropFnOK P 11 GS := Or.inr (Or.inr (Or.inl ⟨8, 10, glueS2_implOK⟩))

/-- AGORA-937: the parameter holds views (its slice), so it views its
    region `π 0`, at `glueS2.nvars + 0 = 4`. -/
def ES3 : Entry := ⟨GSD2, .own, true, [], [⟨4, .self⟩], false, false, false, false⟩

theorem glueS2_body : ∃ Δ, StmtT P ξ (sigCtx glueS2) [] glueS2.body Δ ∧
    (∀ v E, Δ v = some E → E.dtor = false ∧ E.dbind = false) ∧
    Δ 1 = some { intE with mode := R0.mode } := by
  have h0 : sigCtx glueS2 0 = some ES3 := by
    simp [sigCtx, glueS2, paramE, ES3, GSD2, GS, DT, T, Ty.hasFn, regionP, regioned, Ty.holdsView]
  have h1 : sigCtx glueS2 1 = some R0 := by simp [sigCtx, glueS2, R0, resMode]
  have hS : NoRootb (sigCtx glueS2) := by
    intro v E h
    rcases v with _ | _ | v
    · rw [h0] at h; cases h; simp [ES3]
    · rw [h1] at h; cases h; simp [R0]
    · rcases sigCtx_cases h with ⟨hv, _⟩ | ⟨hv, _⟩ | ⟨_, _, _, _, rfl⟩
      · simp [glueS2] at hv
      · simp [glueS2] at hv
      · simp [regionE]
  have hSD : NoRootbD 4 (sigCtx glueS2) := by
    intro v E h
    rcases v with _ | _ | v
    · rw [h0] at h; cases h; exact ⟨by simp [ES3], by simp [ES3, Entry.vdeps, Mode.ownSlot, Kind.isName]⟩
    · rw [h1] at h; cases h; exact ⟨by simp [R0], by simp [R0, Entry.vdeps, Mode.ownSlot]⟩
    · rcases sigCtx_cases h with ⟨hv, _⟩ | ⟨hv, _⟩ | ⟨_, _, _, _, rfl⟩
      · simp [glueS2] at hv
      · simp [glueS2] at hv
      · exact ⟨by simp [regionE], by simp [regionE, Entry.vdeps, Mode.ownSlot]⟩
  let Ka : Ctx := A2.setE (kill .replace false 0 (sigCtx glueS2)) 0 { ES3 with live := false, dtor := false }
  have hKa : NoRootb Ka := (hS.kill _ _ _).setE (by simp [ES3])
  have hKaD : NoRootbD 4 Ka := (hSD.kill _ _ _).setE (by simp [ES3]) (by simp [ES3, Entry.vdeps, Mode.ownSlot, Kind.isName])
  have hmv : RhsT (sigCtx glueS2) [] (.var 0) ⟨ES3.ty, .own, true, [], ES3.held, false, false, false, false⟩ Ka :=
    RhsT.moveOwn h0 rfl rfl (by simp) (hS.noPin _) (DtorSafe.of_none (fun v E h => (hS v E h).2.1) _ _ _)
  let EW : Entry := Entry.arm { (⟨ES3.ty, .own, true, [], ES3.held, false, false, false, false⟩ : Entry) with ty := GSD, held := ES3.held }
  -- armed: its type holds a view; but it views nothing the glue can end:
  -- only its parameter's region
  have hEW : EW = ⟨GSD, .own, true, [], [⟨4, .self⟩], true, true, false, false⟩ := by
    simp [EW, ES3, Entry.arm, GSD, GS, DT, T, Ty.dtorViews, Ty.holdsView]
  let Kb : Ctx := A2.setE Ka 2 EW
  have hKbD : NoRootbD 4 Kb := hKaD.setE (by rw [hEW]; simp) (by rw [hEW]; simp [Entry.vdeps, Mode.ownSlot, Kind.isName])
  have hb2 : Kb 2 = some EW := by simp [Kb, A2.setE]
  have hnm : mutNames Kb [2] = [] := by
    simp [mutNames, argNames, argE, hb2, hEW, Entry.vdeps, nameDeps, Mode.ownSlot, Kind.isName]
  have hcall : CallT P Kb [] 10 [2] (callRes Kb implS [2]) Kb := by
    refine ⟨implS, rfl, by simp [implS], fun i hi => ?_, fun d hd => ?_,
      CallDtorSafe.of_inp (by simp [implS]) hnm, rfl, (callPost_dtor (t := GSD) rfl hnm).symm,
      fun h => absurd h implS_not_thru⟩
    · have hi0 : i = 0 := by simp [implS] at hi; omega
      subst hi0
      refine ⟨EW, by simp [hb2], by rw [hEW], ?_, fun h => ?_, fun h => ?_⟩
      · simp [implS, paramOK, hEW]
      · simp [implS, PMode.moves] at h
      · simp [implS] at h
    · rw [hnm] at hd; cases hd
  have hER : (callRes Kb implS [2]).mode ≠ .rootb ∧
      ∀ d ∈ (callRes Kb implS [2]).vdeps, d.root = 4 ∧ d.kind.isName = false := by
    simp [callRes, resMode, implS, heldOfArgs, argNames, argE, hb2, hEW, Entry.vdeps, ownHeld, Mode.ownSlot,
      memDeps, nameDeps, Kind.isName, argMem, compAll, comp]
    intro d _ hd
    rcases hd with rfl | rfl | rfl | rfl <;> exact ⟨rfl, rfl⟩
  let Kc : Ctx := A2.setE Kb 3 (callRes Kb implS [2])
  have hKcD : NoRootbD 4 Kc := hKbD.setE hER.1 hER.2
  have hc1 : Kc 1 = some R0 := by
    simp [Kc, Kb, Ka, A2.setE, upd, A2.kill, h1, killE, hits, R0, Entry.vdeps]
  let Kd : Ctx := A2.setE (kill .replace false 1 Kc) 1 { intE with mode := R0.mode }
  have hKdD : NoRootbD 4 Kd := (hKcD.kill _ _ _).setE (by simp [R0]) (by simp [intE, Entry.vdeps])
  have hasg : StmtT P .none Kc [] (.assign 1 (.expr (.lit 0))) Kd :=
    StmtT.assign (Ex := R0) (E := intE) hc1 (by simp) (Or.inr (Or.inr ⟨rfl, rfl⟩))
      (RhsT.expr ExprT.lit) rfl (by simp [intE, roots, Entry.vdeps, Mode.ownSlot]) (by simp [hc1])
      (hKcD.noPin _) (hKcD.dtorSafe _ _ (by decide)) rfl
  have hlc := StmtT.letcall (ξ := .none) (P := P) (Γ := Kb) (F := []) (x := 3) (f := 10) (args := [2])
    (s := .assign 1 (.expr (.lit 0))) rfl (by simp [Kb, Ka, A2.setE, upd, A2.kill, sigCtx, isRegionIdx, glueS2]) (by simp)
    hcall hasg.ofNone (hKdD.endOK (by decide))
    (fun fn' hf' ho _ => by simp [P] at hf'; subst hf'; simp [implS] at ho)
  have hlet := StmtT.letd (ξ := .none) (P := P) (Γ := sigCtx glueS2) (Γ1 := Ka) (F := []) (x := 2) (f := 8) (r := .var 0)
    (s := .letcall 3 10 [2] (.assign 1 (.expr (.lit 0)))) (t := GS) (H := ES3.held) (τ := GSD) rfl
    (by simp [sigCtx, isRegionIdx, glueS2]) (by simp) hmv rfl
    (Or.inl ⟨rfl, Or.inr ⟨11, rfl⟩⟩) rfl rfl
    ⟨⟨gsdrop_ok, fun g hg _ => by
      have hg11 : g = 11 := (Ty.dtor.inj hg).1.symm
      subst hg11
      exact ⟨10, 3, _, glueS2_implOK, rfl⟩⟩,
      TakeOK.triv (fun y => ⟨(by intro h; cases h), (by intro h; cases h)⟩)⟩
    (HeldUp.refl _ _) hlc.ofNone ((hKdD.exitScope 3).endOK (by decide)) (by simp [Stmt.assigns])
  -- what is left: the moved parameter and the result; the armed binding has ended
  have hex : ∀ (Γ : Ctx) (x : Var), x ≠ 4 → NoRootbD 4 Γ → exitScope x Γ = upd Γ x none :=
    fun Γ x hx h => by simp only [exitScope, h.regDeps.kill_eq .replace false hx]
  rw [hex _ _ (by decide) ((hKdD.exitScope 3)), hex _ _ (by decide) hKdD] at hlet
  refine ⟨_, hlet.ofNone, ?_, ?_⟩
  · intro v E h
    by_cases hv2 : v = 2
    · subst hv2; simp [upd] at h
    rw [upd_ne _ _ hv2] at h
    by_cases hv3 : v = 3
    · subst hv3; simp [upd] at h
    rw [upd_ne _ _ hv3] at h
    by_cases hv1 : v = 1
    · subst hv1; simp [Kd, A2.setE] at h; subst h; exact ⟨rfl, rfl⟩
    have e1 : Kd v = Kc v := by
      show A2.setE (kill .replace false 1 Kc) 1 _ v = Kc v
      rw [A2.setE, upd_ne _ _ hv1, hKcD.regDeps.kill_eq .replace false (show (1 : Nat) ≠ 4 by decide)]
    have e2 : Kc v = Ka v := by
      show upd (upd Ka 2 (some EW)) 3 _ v = Ka v
      rw [upd_ne _ _ hv3, upd_ne _ _ hv2]
    rw [e1, e2] at h
    exact ⟨(hKa v E h).2.1, (hKa v E h).2.2⟩
  · simp [upd, Kd, A2.setE]

theorem glueS2_ok : FnOK P glueS2 := by
  obtain ⟨Δ, hb, hfl, hr⟩ := glueS2_body
  refine ⟨rfl, by decide, by decide, rfl, by simp [glueS2], ?_, by simp [glueS2], by simp [glueS2],
    by simp [glueS2], by simp [glueS2], by simp [glueS2], ?_, Δ, hb, hfl, ?_, ?_⟩
  · intro pt hpt; simp [glueS2] at hpt; subst hpt
    simp [GSD2, GS, DT, T, Ty.ok, Ty.isStruct, Ty.owning, Ty.holdsView]
  · refine ⟨fun i hi hs _ => ?_, fun i hi b hb _ => ?_, fun h => by simp [glueS2] at h⟩
    · simp [glueS2] at hi; subst hi; simp [glueS2, Stmt.movedFirst, Stmt.assigns]
    · simp [glueS2] at hi; subst hi; simp [glueS2] at hb
  · exact ⟨{ intE with mode := R0.mode }, by simpa [glueS2] using hr, rfl, rfl, by simp [R0, resMode, glueS2],
      by simp [intE], by simp [intE], by simp [glueS2]⟩
  · intro i hi b hb; simp [glueS2] at hi; subst hi; simp [glueS2] at hb

/-! ### Agora #805: the receive's option glue `ofnR` (`sum int DT`) -/

theorem ofnR_not_thru : ¬ ThruFn P 12 := by
  intro h
  cases h with
  | here hf hb => simp [P] at hf; subst hf; simp [ofnR, Stmt.hasThru] at hb
  | call hf hg ht => simp [P] at hf; subst hf; simp [ofnR, Stmt.calls] at hg; subst hg; exact dfn_not_thru ht

theorem ofnR_enumOK : EnumGlueOK P 12 RT :=
  ⟨ofnR, .int, DT, _, _, rfl, rfl, rfl, rfl, rfl, rfl, rfl, rfl, fun h => absurd h ofnR_not_thru, rfl, rfl, rfl,
    fun h => absurd h (by decide), fun _ => ⟨2, 0, _, rfl⟩⟩

theorem rdrop_ok : DropFnOK P 12 RT := Or.inr (Or.inr (Or.inr (Or.inl ofnR_enumOK)))

theorem ofnR_body : ∃ Δ, StmtT P ξ (sigCtx ofnR) [] ofnR.body Δ ∧
    (∀ v E, Δ v = some E → E.mode ≠ .rootb ∧ E.dtor = false ∧ E.dbind = false) ∧
    Δ 1 = some { intE with mode := R0.mode } := by
  let E0 : Entry := ⟨RDT, .own, true, [], [], false, false, false, false⟩
  let I : Entry := { intE with mode := R0.mode }
  have h0 : sigCtx ofnR 0 = some E0 := by simp [↓sigCtx_noRegion (fn := ofnR) (by decide), ofnR, paramE, E0, RDT, RT, DT, T, Ty.hasFn]
  have h1 : sigCtx ofnR 1 = some R0 := by simp [↓sigCtx_noRegion (fn := ofnR) (by decide), ofnR, R0, resMode]
  have h2 : ∀ v : Nat, v ≠ 0 → v ≠ 1 → sigCtx ofnR v = none := by
    intro v hv0 hv1
    have hlt : ¬ v < 1 := fun h => hv0 (Nat.lt_one_iff.mp h)
    simp [↓sigCtx_noRegion (fn := ofnR) (by decide), ofnR, hlt, hv1]
  have hS : NoRootb (sigCtx ofnR) := by
    intro v E h
    rcases v with _ | _ | v
    · rw [h0] at h; cases h; simp [E0]
    · rw [h1] at h; cases h; simp [R0]
    · rw [h2 _ (by simp) (by simp)] at h; cases h
  have hSd : NoDeps (sigCtx ofnR) := by
    intro v E h
    rcases v with _ | _ | v
    · rw [h0] at h; cases h; rfl
    · rw [h1] at h; cases h; rfl
    · rw [h2 _ (by simp) (by simp)] at h; cases h
  -- the arm that takes the payload out
  let Ka : Ctx := A2.setE (kill .replace false 0 (sigCtx ofnR)) 0 { E0 with live := false, dtor := false }
  have hKa : NoRootb Ka := (hS.kill _ _ _).setE (by simp [E0])
  have hKad : NoDeps Ka := (hSd.kill _ _ _).setE rfl
  have hEx : compE E0 DT = ⟨DT, .own, true, [], [], false, false, false, false⟩ := by
    simp [compE, E0, ownHeld, DT, T]
  have htk : RhsT (sigCtx ofnR) [] (.taker 0) (compE E0 DT) Ka :=
    RhsT.taker (a := .int) h0 rfl rfl (Or.inr ⟨12, rfl, by decide⟩) (by simp) (hS.noPin _)
      (DtorSafe.of_none (fun v E h => (hS v E h).2.1) _ _ _)
  let ED : Entry := Entry.arm { compE E0 DT with ty := DT, held := (compE E0 DT).held }
  have hED : ED = ⟨DT, .own, true, [], [], false, false, false, false⟩ := by
    simp only [ED]; rw [hEx]; simp [Entry.arm, DT, T, Ty.dtorViews, Ty.holdsView]
  let Kb : Ctx := A2.setE Ka 2 ED
  have hKb : NoRootb Kb := hKa.setE (by rw [hED]; simp)
  have hKbd : NoDeps Kb := hKad.setE (by rw [hED]; rfl)
  have hc1 : Kb 1 = some R0 := by
    simp [Kb, Ka, A2.setE, upd, hSd.kill_eq, h1]
  let Kc : Ctx := A2.setE (kill .replace false 1 Kb) 1 I
  have hKc : NoRootb Kc := (hKb.kill _ _ _).setE (by simp [I, intE, R0])
  have hKcd : NoDeps Kc := (hKbd.kill _ _ _).setE rfl
  have hasg1 : StmtT P .none Kb [] (.assign 1 (.expr (.lit 0))) Kc :=
    StmtT.assign (Ex := R0) (E := intE) hc1 (by simp) (Or.inr (Or.inr ⟨rfl, rfl⟩))
      (RhsT.expr ExprT.lit) rfl (by simp [intE, roots, Entry.vdeps, Mode.ownSlot]) (by simp [hc1])
      (hKb.noPin _) (DtorSafe.of_none (fun v E h => (hKb v E h).2.1) _ _ _) rfl
  have harm1 := StmtT.letd (ξ := .none) (P := P) (Γ := sigCtx ofnR) (Γ1 := Ka) (F := []) (x := 2) (f := 0) (r := .taker 0)
    (s := .assign 1 (.expr (.lit 0))) (t := T) (H := (compE E0 DT).held) (τ := DT) rfl
    (h2 2 (by decide) (by decide)) (by simp) htk (by rw [hEx])
    (Or.inl ⟨rfl, Or.inr ⟨0, by rw [hEx]; rfl⟩⟩) rfl rfl
    ⟨LetdFn.of drop_ok (fun g hg => by rw [hEx] at hg; exact (Ty.dtor.inj hg).1.symm),
      fun y Ey g u hr hy hgy => by
        have hy0 : y = 0 := by rcases hr with hr | hr <;> cases hr <;> rfl
        subst hy0
        rw [h0] at hy; cases hy
        cases hgy
        exact ofnR_enumOK⟩
    (HeldUp.refl _ _) hasg1.ofNone (hKc.endOK _) (by simp [Stmt.assigns])
  -- the arm that takes nothing: the enum stays, and its scope frees it
  let Δ2 : Ctx := A2.setE (kill .replace false 1 (sigCtx ofnR)) 1 I
  have hasg2 : StmtT P .none (sigCtx ofnR) [] (.assign 1 (.expr (.lit 0))) Δ2 :=
    StmtT.assign (Ex := R0) (E := intE) h1 (by simp) (Or.inr (Or.inr ⟨rfl, rfl⟩))
      (RhsT.expr ExprT.lit) rfl (by simp [intE, roots, Entry.vdeps, Mode.ownSlot]) (by simp [h1])
      (hS.noPin _) (DtorSafe.of_none (fun v E h => (hS v E h).2.1) _ _ _) rfl
  let Δ1 : Ctx := exitScope 2 Kc
  have hΔ1r : NoRootb Δ1 := hKc.exitScope 2
  have hΔ1d : NoDeps Δ1 := by
    intro v E h
    simp only [Δ1, exitScope] at h
    by_cases hv : v = 2
    · subst hv; simp at h
    · rw [upd_ne _ _ hv] at h; exact (hKcd.kill _ _ _) v E h
  have hw : Weaker Δ2 Δ1 := by
    refine ⟨fun v => ?_, hΔ1d.wf hΔ1r, hΔ1d.names⟩
    have e1 : Δ1 v = if v = 2 then none else if v = 1 then some I else if v = 0 then
        some { E0 with live := false, dtor := false } else none := by
      simp only [Δ1, exitScope, hKcd.kill_eq]
      by_cases hv2 : v = 2
      · subst hv2; simp
      · rw [upd_ne _ _ hv2]; simp only [hv2, ↓reduceIte, Kc, A2.setE]
        by_cases hv1 : v = 1
        · subst hv1; simp
        · rw [upd_ne _ _ hv1, hKbd.kill_eq]; simp only [hv1, ↓reduceIte, Kb, A2.setE, upd_ne _ _ hv2, Ka]
          by_cases hv0 : v = 0
          · subst hv0; simp
          · rw [upd_ne _ _ hv0, hSd.kill_eq, h2 v hv0 hv1]; simp [hv0]
    have e2 : Δ2 v = if v = 1 then some I else if v = 0 then some E0 else none := by
      simp only [Δ2, A2.setE, hSd.kill_eq]
      by_cases hv1 : v = 1
      · subst hv1; simp
      · rw [upd_ne _ _ hv1]; simp only [hv1, ↓reduceIte]
        by_cases hv0 : v = 0
        · subst hv0; simp [h0]
        · simp only [hv0, ↓reduceIte]; exact h2 v hv0 hv1
    rw [e1, e2]
    by_cases hv2 : v = 2
    · subst hv2; simp
    by_cases hv1 : v = 1
    · subst hv1; simp; exact EntryWeaker.refl _
    by_cases hv0 : v = 0
    · subst hv0
      simp only [hv2, hv1, ↓reduceIte, reduceCtorEq, Option.some.injEq, true_and]
      intro E E' hE hE'
      subst hE; subst hE'
      exact ⟨rfl, rfl, fun hf => by simp [Entry.fixed, E0] at hf, fun hl => by simp at hl,
        fun hd => by simp [E0] at hd, rfl, fun hd => by simp at hd, fun hd => by simp [E0] at hd,
      fun _ _ _ hfr => by fresh_ew,
      fun _ _ hhf => by heldfresh_ew⟩
    · simp [hv2, hv1, hv0]
  have harm2 : StmtT P .none (sigCtx ofnR) [] (.assign 1 (.expr (.lit 0))) Δ1 :=
    StmtT.sub (Weaker.refl (hSd.wf hS) hSd.names) hasg2 (Or.inr hw)
  refine ⟨Δ1, StmtT.ite rfl rfl (ExprT.isl h0 rfl rfl) harm2.ofNone harm1.ofNone, hΔ1r, ?_⟩
  show exitScope 2 Kc 1 = some I
  simp only [exitScope]
  rw [upd_ne _ _ (by decide), hKcd.kill_eq]
  simp [Kc, A2.setE]

theorem ofnR_ok : FnOK P ofnR := by
  obtain ⟨Δ, hb, hfl, hr⟩ := ofnR_body
  refine ⟨rfl, by decide, by decide, rfl, by simp [ofnR], ?_, by simp [ofnR], by simp [ofnR], by simp [ofnR],
    by simp [ofnR], by simp [ofnR], ?_, Δ, hb, fun v E h => (hfl v E h).2, ?_, ?_⟩
  · intro pt hpt; simp [ofnR] at hpt; subst hpt; simp [RDT, RT, DT, T, Ty.ok, Ty.isStruct, Ty.owning]
  · refine ⟨fun i hi hs _ => ?_, fun i hi b hb _ => ?_, fun h => by simp [ofnR] at h⟩
    · simp [ofnR] at hi; subst hi
      exact ⟨Or.inr ⟨12, RT, rfl, Or.inl ofnR_enumOK⟩, by simp [ofnR, Stmt.assigns]⟩
    · simp [ofnR] at hi; subst hi; simp [ofnR] at hb
  · exact ⟨{ intE with mode := R0.mode }, by simpa [ofnR] using hr, rfl, rfl, by simp [R0, resMode, ofnR],
      by simp [intE], by simp [intE], by simp [ofnR]⟩
  · intro i hi b hb; simp [ofnR] at hi; subst hi; simp [ofnR] at hb

theorem prog_ok : ProgOK P := by
  intro fn hfn
  simp only [P, List.mem_cons, List.mem_nil_iff, or_false] at hfn
  rcases hfn with rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl
  · exact dfn_ok
  · exact mk_ok
  · exact ofn_ok
  · exact gfn_ok
  · exact glue_ok
  · exact impl_ok
  · exact glue2_ok
  · exact glueV_ok
  · exact glueS_ok
  · exact ofnV_ok
  · exact implS_ok
  · exact glueS2_ok
  · exact ofnR_ok

/-! ### The caller: `: DT y ( mk )  :drop z y` -/

def main2 : Stmt := .letcall 0 1 [] (.letd 1 0 (.var 0) .skip)

def Ecr : Entry := ⟨DT, .own, true, [], [], false, false, false, false⟩

theorem main2_typed : ∃ Δ, StmtT P ξ (fun _ => none) [] main2 Δ := by
  have hpost : callPost (fun _ => none) mk [] = fun _ => none := by
    funext v; simp [callPost, callPostAux, mk, killNames, mutNames, argNames]
  have hres : callRes (fun _ => none) mk [] = Ecr := by
    simp [callRes, mk, resMode, Ecr, heldOfArgs, ownHeld, argNames, argMem, compAll]
  have hc : CallT P (fun _ => none) [] 1 [] Ecr (fun _ => none) := by
    refine ⟨mk, rfl, rfl, fun i hi => by simp [mk] at hi, ?_, CallDtorSafe.of_none (fun _ _ h => by cases h) _ _,
      hres.symm, hpost.symm, fun _ => by simp [callR]⟩
    intro d hd; simp [mutNames, argNames] at hd
  let K : Ctx := A2.setE (fun _ => none) 0 Ecr
  have hK : NoRootb K := noRootb_empty.setE (by simp [Ecr])
  have hmv := RhsT.moveOwn (Γ := K) (F := []) (y := 0) (E := Ecr) (by simp [K, A2.setE]) rfl rfl (by simp)
    (hK.noPin _) (DtorSafe.of_none (fun v E h => (hK v E h).2.1) _ _ _)
  let K1 : Ctx := A2.setE (kill .replace false 0 K) 0 { Ecr with live := false, dtor := false }
  have hK1 : NoRootb K1 := (hK.kill _ _ _).setE (by simp [Ecr])
  let ED2 : Entry := Entry.arm { (⟨Ecr.ty, .own, true, [], Ecr.held, false, false, false, false⟩ : Entry) with ty := DT, held := Ecr.held }
  have hED2 : ED2.mode ≠ .rootb ∧ ED2.dtor = false ∧ ED2.dbind = false := by
    simp [ED2, Ecr, Entry.arm, DT, T, Ty.dtorViews, Ty.holdsView]
  have hK2 : NoRootb (A2.setE K1 1 ED2) := hK1.setE hED2
  have hd := StmtT.letd (ξ := .none) (P := P) (Γ := K) (Γ1 := K1) (F := []) (x := 1) (f := 0) (r := .var 0) (s := .skip)
    (t := T) (H := Ecr.held) rfl (by simp [K, A2.setE]) (by simp) hmv rfl (Or.inl ⟨rfl, Or.inr ⟨_, rfl⟩⟩) rfl rfl (letd_fn drop_ok)
    (HeldUp.refl _ _) StmtT.skip (hK2.endOK _)
  exact ⟨_, StmtT.letcall (P := P) (Γ := fun _ => none) (F := []) (x := 0) (f := 1) (args := [])
    (s := .letd 1 0 (.var 0) .skip) (E := Ecr) (Γ1 := fun _ => none) rfl rfl (by simp) hc hd.ofNone
    ((hK2.exitScope 1).endOK _)
    (fun fn hf _ _ => by simp [P] at hf; subst hf; simp [Stmt.movedFirst, Stmt.assigns])⟩

theorem prog_codes : ProgCodes P := by
  intro fn hfn
  simp only [P, List.mem_cons, List.mem_nil_iff, or_false] at hfn
  rcases hfn with rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl <;>
    simp [dfn, mk, ofn, gfn, glue, impl, glue2, glueV, glueS, ofnV, implS, glueS2, ofnR, Stmt.codesOK,
      Rhs.codeOK]

theorem main2_safe {m' : Mem} {s' : Stmt} (hr : Steps P (emptyMem 2) main2 (.ok m' s')) :
    ¬ Stuck P m' s' := by
  obtain ⟨Δ, ht⟩ := main2_typed
  exact memory_safe prog_ok prog_codes ht rfl (by simp [main2, Stmt.codesOK, Rhs.codeOK]) (by decide) hr

theorem main_safe {m' : Mem} {s' : Stmt} (hr : Steps P (emptyMem 3) main (.ok m' s')) :
    ¬ Stuck P m' s' := by
  obtain ⟨Δ, ht⟩ := main_typed
  exact memory_safe prog_ok prog_codes ht rfl (by simp [main, Stmt.codesOK, Rhs.codeOK]) (by decide) hr



/-! ### An option of a destructor value (A2-drop.3b)

`: a 1  : b 2  :drop x ( pair a b )  :drop o ( Some x )`: the destructor
value moves into the option, and the option, which holds it, is bound by
`letd` at its own destructor type, its glue `ofn`.  A witness, not a new
capability: the destructor value is one level down, so 3a's one-level
`Ty.holdsDtor` sent the option to `letd` already. -/

def main3 : Stmt :=
  .letv 0 (.expr (.lit 1)) (.letv 1 (.expr (.lit 2))
    (.letd 2 0 (.pair 0 1) (.letd 3 2 (.inl 2 .int) .skip)))

def EO : Entry := ⟨OT, .own, true, [], [], false, false, false, false⟩

theorem main3_typed : ∃ Δ, StmtT P ξ (fun _ => none) [] main3 Δ := by
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
  -- the destructor value moves into the option
  let K4 : Ctx := A2.setE (kill .replace false 2 K3) 2 { ED with live := false, dtor := false }
  have hK4 : NoRootb K4 := (hK3.kill _ _ _).setE (by rw [hEDe]; simp)
  have hpush : PushArg K3 [] 2 ED ED.ty ED.held K4 := by
    rw [hEDe]
    have := PushArg.move (Γ := K3) (F := []) (y := 2) (E := ⟨DT, .own, true, [], [], false, false, false, false⟩) (t := DT)
      rfl rfl (by simp) (hK3.noPin _) (DtorSafe.of_none (fun v E h => (hK3 v E h).2.1) _ _ _)
    exact this
  have hinl : RhsT K3 [] (.inl 2 .int) EO K4 := by
    have := RhsT.inl (Γ := K3) (F := []) (y := 2) (b := .int) (Ey := ED) (Γ1 := K4) (D := ED.held)
      (by simp [K3, A2.setE]) (by rw [hEDe]) hpush rfl
    rw [hEDe] at this; exact this
  let EOd : Entry := Entry.arm { EO with ty := ODT, held := [] }
  have hEOd : EOd.mode ≠ .rootb ∧ EOd.dtor = false ∧ EOd.dbind = false := by
    simp [EOd, EO, Entry.arm, ODT, OT, DT, T, Ty.dtorViews, Ty.holdsView]
  have hK5 : NoRootb (A2.setE K4 3 EOd) := hK4.setE hEOd
  have hdo := StmtT.letd (ξ := .none) (P := P) (Γ := K3) (Γ1 := K4) (F := []) (x := 3) (f := 2) (r := .inl 2 .int)
    (s := .skip) (E := EO) (t := OT) (H := []) rfl (by simp [K3, K2, K1, A2.setE, upd]) (by simp) hinl rfl
    (Or.inl ⟨rfl, Or.inl rfl⟩) rfl rfl (letd_fn odrop_ok) (HeldUp.refl _ _) StmtT.skip (hK5.endOK _)
  have hd := StmtT.letd (ξ := .none) (P := P) (Γ := K2) (Γ1 := K2) (F := []) (x := 2) (f := 0) (r := .pair 0 1)
    (s := .letd 3 2 (.inl 2 .int) .skip) (E := EP) (t := T) (H := []) rfl (by simp [K2, K1, A2.setE, upd])
    (by simp) hpair rfl (Or.inl ⟨rfl, Or.inl rfl⟩) rfl rfl (letd_fn drop_ok) (HeldUp.refl _ _) hdo.ofNone ((hK5.exitScope 3).endOK _)
  have h1 := StmtT.letv (ξ := .none) (P := P) (x := 1) (r := .expr (.lit 2)) (E := intE) (F := []) (Γ := K1) (Γ1 := K1)
    rfl (by simp [K1, A2.setE]) (by simp) (RhsT.expr ExprT.lit) hd.ofNone
    (((hK5.exitScope 3).exitScope 2).endOK _)
  exact ⟨_, StmtT.letv (P := P) (x := 0) (r := .expr (.lit 1)) (E := intE) (F := []) (Γ := fun _ => none)
    (Γ1 := fun _ => none) rfl rfl (by simp) (RhsT.expr ExprT.lit) h1.ofNone
    ((((hK5.exitScope 3).exitScope 2).exitScope 1).endOK _)⟩

/-- The option program is memory safe. -/
theorem main3_safe {m' : Mem} {s' : Stmt} (hr : Steps P (emptyMem 4) main3 (.ok m' s')) :
    ¬ Stuck P m' s' := by
  obtain ⟨Δ, ht⟩ := main3_typed
  exact memory_safe prog_ok prog_codes ht rfl (by simp [main3, Stmt.codesOK, Rhs.codeOK]) (by decide) hr

/-! ### A `Vec` of destructor values (A2-drop.3b, the drain)

`: a 1  : b 2  :drop x ( pair a b )  :drop v ( vec_new DT )  ( vec_push v x )`:
the destructor value moves into the `Vec`, whose binding is `letd`'s, at
the type `vec DT`: its frame's end drains it (`A2.Dtor.scopeD_end_drains`),
each element's destructor running in its own frame. -/

def main5 : Stmt :=
  .letv 0 (.expr (.lit 1)) (.letv 1 (.expr (.lit 2))
    (.letd 2 0 (.pair 0 1) (.letd 3 0 (.new DT) (.push 3 2))))

theorem main5_typed : ∃ Δ, StmtT P ξ (fun _ => none) [] main5 Δ := by
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
  -- the `Vec` of destructor values, bound by `letd` at its own type
  let EN : Entry := ⟨.vec DT, .own, true, [], [], false, false, false, false⟩
  have hnew : RhsT K3 [] (.new DT) EN K3 := RhsT.new (by decide)
  let EV : Entry := Entry.arm { EN with ty := .vec DT, held := [] }
  have hEVe : EV = ⟨.vec DT, .own, true, [], [], false, false, false, false⟩ := by
    simp [EV, EN, Entry.arm, DT, T, Ty.dtorViews, Ty.holdsView]
  let K4 : Ctx := A2.setE K3 3 EV
  have hK4 : NoRootb K4 := hK3.setE (by rw [hEVe]; simp)
  -- the destructor value moves into it
  let K5 : Ctx := A2.setE (kill .replace false 2 K4) 2 { ED with live := false, dtor := false }
  have hK5 : NoRootb K5 := (hK4.kill _ _ _).setE (by rw [hEDe]; simp)
  have hmove : PushArg K4 [] 2 ED DT ED.held K5 :=
    PushArg.move (Γ := K4) (F := []) (y := 2) (E := ED) (t := DT) rfl (by rw [hEDe]) (by simp)
      (hK4.noPin _) (DtorSafe.of_none (fun v E h => (hK4 v E h).2.1) _ _ _)
  have hK53 : K5 3 = some EV := by
    simp [K5, K4, A2.setE, upd, A2.kill, killE, hits, hEVe, Entry.vdeps, Mode.ownSlot]
  have hpush := StmtT.push (ξ := .none) (P := P) (Γ := K4) (Γ1 := K5) (F := []) (x := 3) (y := 2) (Ex := EV) (Ey := ED)
    (Ex1 := EV) (t := DT) (D := ED.held) (by simp [K4, A2.setE]) (by rw [hEVe]) (by rw [hEVe])
    (Or.inl (by rw [hEVe])) (by simp) (by simp [K4, K3, A2.setE, upd]) (by rw [hEDe]) (by rw [hEDe])
    (by decide) hmove (by rw [hEDe]; simp [roots]) hK53 (by rw [hEVe])
    (DtorSafe.of_none (fun v E h => (hK5 v E h).2.1) _ _ _) (by rw [hEVe]; simp)
  have hK6 : NoRootb (A2.setE (kill .realloc DT.holdsView 3 K5) 3
      { EV with held := EV.held ++ ownHeld true DT ED.held }) :=
    (hK5.kill _ _ _).setE (by rw [hEVe]; simp)
  have hdv := StmtT.letd (ξ := .none) (P := P) (Γ := K3) (Γ1 := K3) (F := []) (x := 3) (f := 0) (r := .new DT)
    (s := .push 3 2) (E := EN) (t := T) (H := []) (τ := .vec DT) rfl (by simp [K3, K2, K1, A2.setE, upd])
    (by simp) hnew rfl (Or.inr ⟨0, rfl, rfl⟩) rfl rfl (letd_fn drop_ok) (HeldUp.refl _ _) hpush.ofNone (hK6.endOK _)
  have hd := StmtT.letd (ξ := .none) (P := P) (Γ := K2) (Γ1 := K2) (F := []) (x := 2) (f := 0) (r := .pair 0 1)
    (s := .letd 3 0 (.new DT) (.push 3 2)) (E := EP) (t := T) (H := []) rfl (by simp [K2, K1, A2.setE, upd])
    (by simp) hpair rfl (Or.inl ⟨rfl, Or.inl rfl⟩) rfl rfl (letd_fn drop_ok) (HeldUp.refl _ _) hdv.ofNone
    ((hK6.exitScope 3).endOK _)
  have h1 := StmtT.letv (ξ := .none) (P := P) (x := 1) (r := .expr (.lit 2)) (E := intE) (F := []) (Γ := K1) (Γ1 := K1)
    rfl (by simp [K1, A2.setE]) (by simp) (RhsT.expr ExprT.lit) hd.ofNone
    (((hK6.exitScope 3).exitScope 2).endOK _)
  exact ⟨_, StmtT.letv (P := P) (x := 0) (r := .expr (.lit 1)) (E := intE) (F := []) (Γ := fun _ => none)
    (Γ1 := fun _ => none) rfl rfl (by simp) (RhsT.expr ExprT.lit) h1.ofNone
    ((((hK6.exitScope 3).exitScope 2).exitScope 1).endOK _)⟩

/-- The program with a `Vec` of destructor values is memory safe. -/
theorem main5_safe {m' : Mem} {s' : Stmt} (hr : Steps P (emptyMem 4) main5 (.ok m' s')) :
    ¬ Stuck P m' s' := by
  obtain ⟨Δ, ht⟩ := main5_typed
  exact memory_safe prog_ok prog_codes ht rfl (by simp [main5, Stmt.codesOK, Rhs.codeOK]) (by decide) hr

/-- ... and `letv` refuses that `Vec`: it holds destructor values. -/
theorem main5_letv_refused {Γ Δ : Ctx} {F : List Var} {x : Var} {s : Stmt} :
    ¬ StmtT P ξ Γ F (.letv x (.new DT) s) Δ := by
  intro h
  obtain ⟨Γ0, E, Γ1, hr, hnd⟩ := A2.Dtor.letv_owned_no_dtor h
  cases hr with
  | new _ => exact absurd (hnd rfl) (by decide)

/-! ### A `Vec` of `Vec`s of destructor values (Agora #607)

`: a 1  : b 2  :drop x ( pair a b )  :drop v ( vec_new DT )  ( vec_push v x )
 :drop w ( vec_new ( Vec DT ) )  ( vec_push w v )`: the inner `Vec` moves into
the outer one, bound by `letd` at `vec (vec DT)`. Its frame's end takes the
inner `Vec` out to a `letd` of the same destructor (`Step.scopeDDrain`), whose
frame drains it in turn, each element's destructor running in its own frame. -/

def main11 : Stmt :=
  .letv 0 (.expr (.lit 1)) (.letv 1 (.expr (.lit 2))
    (.letd 2 0 (.pair 0 1) (.letd 3 0 (.new DT)
      (.seq (.push 3 2) (.letd 4 0 (.new (.vec DT)) (.push 4 3))))))

theorem main11_typed : ∃ Δ, StmtT P ξ (fun _ => none) [] main11 Δ := by
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
  -- the inner `Vec`, as in `main5`
  let EN : Entry := ⟨.vec DT, .own, true, [], [], false, false, false, false⟩
  have hnew : RhsT K3 [] (.new DT) EN K3 := RhsT.new (by decide)
  let EV : Entry := Entry.arm { EN with ty := .vec DT, held := [] }
  have hEVe : EV = ⟨.vec DT, .own, true, [], [], false, false, false, false⟩ := by
    simp [EV, EN, Entry.arm, DT, T, Ty.dtorViews, Ty.holdsView]
  let K4 : Ctx := A2.setE K3 3 EV
  have hK4 : NoRootb K4 := hK3.setE (by rw [hEVe]; simp)
  let K5 : Ctx := A2.setE (kill .replace false 2 K4) 2 { ED with live := false, dtor := false }
  have hK5 : NoRootb K5 := (hK4.kill _ _ _).setE (by rw [hEDe]; simp)
  have hmove : PushArg K4 [] 2 ED DT ED.held K5 :=
    PushArg.move (Γ := K4) (F := []) (y := 2) (E := ED) (t := DT) rfl (by rw [hEDe]) (by simp)
      (hK4.noPin _) (DtorSafe.of_none (fun v E h => (hK4 v E h).2.1) _ _ _)
  have hK53 : K5 3 = some EV := by
    simp [K5, K4, A2.setE, upd, A2.kill, killE, hits, hEVe, Entry.vdeps, Mode.ownSlot]
  have hpush := StmtT.push (ξ := .none) (P := P) (Γ := K4) (Γ1 := K5) (F := []) (x := 3) (y := 2) (Ex := EV) (Ey := ED)
    (Ex1 := EV) (t := DT) (D := ED.held) (by simp [K4, A2.setE]) (by rw [hEVe]) (by rw [hEVe])
    (Or.inl (by rw [hEVe])) (by simp) (by simp [K4, K3, A2.setE, upd]) (by rw [hEDe]) (by rw [hEDe])
    (by decide) hmove (by rw [hEDe]; simp [roots]) hK53 (by rw [hEVe])
    (DtorSafe.of_none (fun v E h => (hK5 v E h).2.1) _ _ _) (by rw [hEVe]; simp)
  let E3 : Entry := { EV with held := EV.held ++ ownHeld true DT ED.held }
  have hE3e : E3 = ⟨.vec DT, .own, true, [], [], false, false, false, false⟩ := by
    simp [E3, hEVe, hEDe, ownHeld]
  let K6 : Ctx := A2.setE (kill .realloc DT.holdsView 3 K5) 3 E3
  have hK6 : NoRootb K6 := (hK5.kill _ _ _).setE (by rw [hE3e]; simp)
  -- the outer `Vec`, bound by `letd` at `vec (vec DT)`
  let EN2 : Entry := ⟨.vec (.vec DT), .own, true, [], [], false, false, false, false⟩
  have hnew2 : RhsT K6 [] (.new (.vec DT)) EN2 K6 := RhsT.new (by decide)
  let EW : Entry := Entry.arm { EN2 with ty := .vec (.vec DT), held := [] }
  have hEWe : EW = ⟨.vec (.vec DT), .own, true, [], [], false, false, false, false⟩ := by
    simp [EW, EN2, Entry.arm, DT, T, Ty.dtorViews, Ty.holdsView]
  let K7 : Ctx := A2.setE K6 4 EW
  have hK7 : NoRootb K7 := hK6.setE (by rw [hEWe]; simp)
  -- the inner `Vec` moves into it
  let K8 : Ctx := A2.setE (kill .replace false 3 K7) 3 { E3 with live := false, dtor := false }
  have hK8 : NoRootb K8 := (hK7.kill _ _ _).setE (by rw [hE3e]; simp)
  have hmove2 : PushArg K7 [] 3 E3 (.vec DT) E3.held K8 :=
    PushArg.move (Γ := K7) (F := []) (y := 3) (E := E3) (t := .vec DT) rfl (by rw [hE3e]) (by simp)
      (hK7.noPin _) (DtorSafe.of_none (fun v E h => (hK7 v E h).2.1) _ _ _)
  have hK84 : K8 4 = some EW := by
    simp [K8, K7, A2.setE, upd, A2.kill, killE, hits, hEWe, Entry.vdeps, Mode.ownSlot]
  have hpush2 := StmtT.push (ξ := .none) (P := P) (Γ := K7) (Γ1 := K8) (F := []) (x := 4) (y := 3) (Ex := EW) (Ey := E3)
    (Ex1 := EW) (t := .vec DT) (D := E3.held) (by simp [K7, A2.setE]) (by rw [hEWe]) (by rw [hEWe])
    (Or.inl (by rw [hEWe])) (by simp) (by simp [K7, K6, A2.setE, upd]) (by rw [hE3e]) (by rw [hE3e])
    (by decide) hmove2 (by rw [hE3e]; simp [roots]) hK84 (by rw [hEWe])
    (DtorSafe.of_none (fun v E h => (hK8 v E h).2.1) _ _ _) (by rw [hEWe]; simp)
  have hK9 : NoRootb (A2.setE (kill .realloc (Ty.vec DT).holdsView 4 K8) 4
      { EW with held := EW.held ++ ownHeld true (.vec DT) E3.held }) :=
    (hK8.kill _ _ _).setE (by rw [hEWe]; simp)
  have hdw := StmtT.letd (ξ := .none) (P := P) (Γ := K6) (Γ1 := K6) (F := []) (x := 4) (f := 0) (r := .new (.vec DT))
    (s := .push 4 3) (E := EN2) (t := T) (H := []) (τ := .vec (.vec DT)) rfl
    (by simp [K6, K5, K4, K3, K2, K1, A2.setE, upd, A2.kill])
    (by simp) hnew2 rfl (Or.inr ⟨1, rfl, rfl⟩) rfl rfl (letd_fn drop_ok) (HeldUp.refl _ _) hpush2.ofNone
    (hK9.endOK _)
  have hseq := StmtT.seq (P := P) rfl hpush hdw
  have hdv := StmtT.letd (ξ := .none) (P := P) (Γ := K3) (Γ1 := K3) (F := []) (x := 3) (f := 0) (r := .new DT)
    (s := .seq (.push 3 2) (.letd 4 0 (.new (.vec DT)) (.push 4 3))) (E := EN) (t := T) (H := [])
    (τ := .vec DT) rfl (by simp [K3, K2, K1, A2.setE, upd])
    (by simp) hnew rfl (Or.inr ⟨0, rfl, rfl⟩) rfl rfl (letd_fn drop_ok) (HeldUp.refl _ _) hseq.ofNone
    ((hK9.exitScope 4).endOK _)
  have hd := StmtT.letd (ξ := .none) (P := P) (Γ := K2) (Γ1 := K2) (F := []) (x := 2) (f := 0) (r := .pair 0 1)
    (s := .letd 3 0 (.new DT) (.seq (.push 3 2) (.letd 4 0 (.new (.vec DT)) (.push 4 3)))) (E := EP) (t := T)
    (H := []) rfl (by simp [K2, K1, A2.setE, upd])
    (by simp) hpair rfl (Or.inl ⟨rfl, Or.inl rfl⟩) rfl rfl (letd_fn drop_ok) (HeldUp.refl _ _) hdv.ofNone
    (((hK9.exitScope 4).exitScope 3).endOK _)
  have h1 := StmtT.letv (ξ := .none) (P := P) (x := 1) (r := .expr (.lit 2)) (E := intE) (F := []) (Γ := K1) (Γ1 := K1)
    rfl (by simp [K1, A2.setE]) (by simp) (RhsT.expr ExprT.lit) hd.ofNone
    ((((hK9.exitScope 4).exitScope 3).exitScope 2).endOK _)
  exact ⟨_, StmtT.letv (P := P) (x := 0) (r := .expr (.lit 1)) (E := intE) (F := []) (Γ := fun _ => none)
    (Γ1 := fun _ => none) rfl rfl (by simp) (RhsT.expr ExprT.lit) h1.ofNone
    (((((hK9.exitScope 4).exitScope 3).exitScope 2).exitScope 1).endOK _)⟩

/-- The program with a `Vec` of `Vec`s of destructor values is memory safe. -/
theorem main11_safe {m' : Mem} {s' : Stmt} (hr : Steps P (emptyMem 5) main11 (.ok m' s')) :
    ¬ Stuck P m' s' := by
  obtain ⟨Δ, ht⟩ := main11_typed
  exact memory_safe prog_ok prog_codes ht rfl (by simp [main11, Stmt.codesOK, Rhs.codeOK]) (by decide) hr

/-- ... and leaks nothing when it ends (`no_leak_end`: nothing is left
    allocated).  That the drain runs each element's destructor, the inner
    `Vec`'s by a frame of its own, is read off the steps, as for `main5`:
    the theorem does not trace the run. -/
theorem main11_no_leak {m' : Mem} (hr : Steps P (emptyMem 5) main11 (.ok m' .skip)) :
    ∀ i, m'.alloc i = false := by
  obtain ⟨Δ, ht⟩ := main11_typed
  exact no_leak_end prog_ok prog_codes ht rfl (by simp [main11, Stmt.codesOK, Rhs.codeOK]) (by decide) hr

/-! ### A struct with a destructor field, dropped by its glue (Agora #616)

`: a 1  : b 2  :drop x ( pair a b )  : c 3  :drop g ( pair x c )`: the
destructor value `x` moves into the struct, which is bound by `letd` at
`GDT`, the destructor type whose destructor is the glue (`glue`).  At the
frame's end the struct moves into the glue (its parameter is `sink`), which
takes it apart: the field is a `letd`'s. -/

def main7 : Stmt :=
  .letv 0 (.expr (.lit 1)) (.letv 1 (.expr (.lit 2))
    (.letd 2 0 (.pair 0 1) (.letv 3 (.expr (.lit 3)) (.letd 4 4 (.pair 2 3) .skip))))

theorem main7_typed : ∃ Δ, StmtT P ξ (fun _ => none) [] main7 Δ := by
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
  let EGa : Entry := Entry.arm { EG0 with ty := GDT, held := EG0.held }
  have hEGa : EGa.mode ≠ .rootb ∧ EGa.dtor = false ∧ EGa.dbind = false := by
    simp [EGa, EG0, Entry.arm, GDT, GT, DT, T, Ty.dtorViews, Ty.holdsView]
  have hK6 : NoRootb (A2.setE K5 4 EGa) := hK5.setE hEGa
  have hg := StmtT.letd (ξ := .none) (P := P) (Γ := K4) (Γ1 := K5) (F := []) (x := 4) (f := 4) (r := .pair 2 3)
    (s := .skip) (E := EG0) (t := GT) (H := EG0.held) (τ := GDT) rfl
    (by simp [K4, K3, K2, K1, A2.setE, upd]) (by simp) hgp rfl
    (Or.inl ⟨rfl, Or.inl (by simp [EG0, hEDe, intE, GT])⟩) rfl rfl (letd_fn gluedrop_ok) (HeldUp.refl _ _) StmtT.skip
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

/-- The program with a struct dropped by its glue is memory safe. -/
theorem main7_safe {m' : Mem} {s' : Stmt} (hr : Steps P (emptyMem 5) main7 (.ok m' s')) :
    ¬ Stuck P m' s' := by
  obtain ⟨Δ, ht⟩ := main7_typed
  exact memory_safe prog_ok prog_codes ht rfl (by simp [main7, Stmt.codesOK, Rhs.codeOK]) (by decide) hr

/-- ... and the destructor `dfn`, which takes its value lent, is no
    destructor for that struct: one that holds a destructor value has glue. -/
theorem main7_lent_refused : ¬ DropFnOK P 0 GT := by
  rintro (⟨_, h⟩ | ⟨fn, a, b, hfn, _, hps, _⟩ | ⟨_, _, fn, _, _, _, hfn, _, hps, _⟩ |
    ⟨fn, _, _, _, _, hfn, _, hps, _⟩ | ⟨_, _, _, _, _, _, _, _, ht, _⟩)
  · exact absurd h (by decide)
  · simp [P] at hfn; subst hfn; simp [dfn] at hps
  · simp [P] at hfn; subst hfn; simp [dfn] at hps
  · simp [P] at hfn; subst hfn; simp [dfn] at hps
  · cases ht

/-! ### ... and with a `% Drop` of its own (Agora #616)

The same program, the struct bound at `SDT2`, whose glue (`glue2`) rebinds
it under the fields' glue and runs the impl on it lent. -/

def main8 : Stmt :=
  .letv 0 (.expr (.lit 1)) (.letv 1 (.expr (.lit 2))
    (.letd 2 0 (.pair 0 1) (.letv 3 (.expr (.lit 3)) (.letd 4 6 (.pair 2 3) .skip))))

theorem main8_typed : ∃ Δ, StmtT P ξ (fun _ => none) [] main8 Δ := by
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
  have hg := StmtT.letd (ξ := .none) (P := P) (Γ := K4) (Γ1 := K5) (F := []) (x := 4) (f := 6) (r := .pair 2 3)
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

/-- The program with a struct that has its own `% Drop` beside a destructor
    field is memory safe. -/
theorem main8_safe {m' : Mem} {s' : Stmt} (hr : Steps P (emptyMem 5) main8 (.ok m' s')) :
    ¬ Stuck P m' s' := by
  obtain ⟨Δ, ht⟩ := main8_typed
  exact memory_safe prog_ok prog_codes ht rfl (by simp [main8, Stmt.codesOK, Rhs.codeOK]) (by decide) hr

/-! ### A struct with a destructor field and a view field (Agora #633)

`: s ( new int )  : v ( view s )  : a 1  : b 2  :drop c ( pair a b )
:drop g ( pair c v )`: the struct holds the destructor value `c` and a view
of the older binding `s` (nurlc's `: P { Conn c s name }`); it is bound by
`letd` at `GSD`, armed: it views `s`.  At the frame's end it moves into its
glue `glueS` as a `sink` argument that holds that view (`glueCall_typed`),
which takes it apart, the destructor field going to a `letd` of its own. -/

def main10 : Stmt :=
  .letv 0 (.new .int) (.letv 1 (.view 0) (.letv 2 (.expr (.lit 1)) (.letv 3 (.expr (.lit 2))
    (.letd 4 0 (.pair 2 3) (.letd 5 8 (.pair 4 1) .skip)))))

/-- The end of a binding that views other bindings, in a context with no
    borrowed parameter and no other binding that runs a destructor. -/
theorem endOK_viewing {Γ : Ctx} (h : NoRootb Γ) {x : Var} {E : Entry} (hm : E.mode ≠ .rootb)
    (hx : x ∉ roots E.vdeps) : EndOK (A2.setE Γ x E) x := by
  refine ⟨fun p Ep hp hmp => ?_, fun v Ev hv hd _ => ?_, fun v Ev hv hd _ _ d hdd _ => ?_⟩
  · by_cases hpx : p = x
    · subst hpx; simp [A2.setE] at hp; subst hp; exact absurd hmp hm
    · rw [A2.setE, upd_ne _ _ hpx] at hp; exact absurd hmp (h p Ep hp).1
  · by_cases hvx : v = x
    · subst hvx; simp [A2.setE] at hv; subst hv
      simp [hitsMem]
      intro _ d hd hdv
      exact absurd (by rw [← hdv]; exact List.mem_map_of_mem hd) hx
    · rw [A2.setE, upd_ne _ _ hvx] at hv; rw [(h v Ev hv).2.1] at hd; cases hd
  · by_cases hvx : v = x
    · subst hvx; simp [A2.setE] at hv; subst hv
      intro hdx; exact hx (by rw [← hdx]; exact List.mem_map_of_mem hdd)
    · rw [A2.setE, upd_ne _ _ hvx] at hv; rw [(h v Ev hv).2.2] at hd; cases hd

theorem exitScope_setE_same (Γ : Ctx) (x : Var) (E : Entry) :
    A2.exitScope x (A2.setE Γ x E) = A2.exitScope x Γ := by
  funext w
  by_cases hwx : w = x
  · subst hwx; simp [A2.exitScope]
  · simp [A2.exitScope, upd_ne _ _ hwx, A2.kill, A2.setE]

def EN0 : Entry := ⟨.vec .int, .own, true, [], [], false, false, false, false⟩
def EVw : Entry := ⟨.slice .int, .bor, true, derive 0 EN0 .view, EN0.held, false, false, false, false⟩

theorem main10_typed : ∃ Δ, StmtT P ξ (fun _ => none) [] main10 Δ := by
  let K1 : Ctx := A2.setE (fun _ => none) 0 EN0
  have hK1 : NoRootb K1 := noRootb_empty.setE (by simp [EN0])
  let K2 : Ctx := A2.setE K1 1 EVw
  have hK2 : NoRootb K2 := hK1.setE (by simp [EVw])
  let K3 : Ctx := A2.setE K2 2 intE
  let K4 : Ctx := A2.setE K3 3 intE
  have hK4 : NoRootb K4 := (hK2.setE (by simp [intE])).setE (by simp [intE])
  have hview : RhsT K1 [] (.view 0) EVw K1 :=
    RhsT.view (E := EN0) (t := .int) (by simp [K1, A2.setE]) rfl rfl rfl
  let ED : Entry := Entry.arm { EP with ty := DT, held := [] }
  have hEDe : ED = ⟨DT, .own, true, [], [], false, false, false, false⟩ := by
    simp [ED, EP, Entry.arm, DT, T, Ty.dtorViews, Ty.holdsView]
  have hpair : RhsT K4 [] (.pair 2 3) EP K4 :=
    RhsT.pair (Ey := intE) (Ez := intE) (by simp [K4, K3, A2.setE, upd]) rfl PushArg.int
      (by simp [K4, A2.setE]) rfl PushArg.int (by simp [intE, Mode.ownSlot])
  let K5 : Ctx := A2.setE K4 4 ED
  have hK5 : NoRootb K5 := hK4.setE (by rw [hEDe]; simp)
  -- the struct literal: the destructor value moves in, the view is copied
  let K6 : Ctx := A2.setE (kill .replace false 4 K5) 4 { ED with live := false, dtor := false }
  have hK6 : NoRootb K6 := (hK5.kill _ _ _).setE (by rw [hEDe]; simp)
  have hmove : PushArg K5 [] 4 ED ED.ty ED.held K6 :=
    PushArg.move (Γ := K5) (F := []) (y := 4) (E := ED) (t := ED.ty) rfl (by rw [hEDe]) (by simp)
      (hK5.noPin _) (DtorSafe.of_none (fun v E h => (hK5 v E h).2.1) _ _ _)
  have hK61 : K6 1 = some EVw := by
    simp [K6, K5, K4, K3, K2, A2.setE, upd, A2.kill, killE, hits, EVw, EN0, derive, Mode.isRoot,
      rootKind, Entry.vdeps, Mode.ownSlot]
  let EG0 : Entry := ⟨.prod ED.ty EVw.ty, .own, true, [], ED.held ++ (derive 1 EVw .self ++ EVw.held),
    false, false, false, false⟩
  have hgp : RhsT K5 [] (.pair 4 1) EG0 K6 :=
    RhsT.pair (Ey := ED) (Ez := EVw) (by simp [K5, A2.setE]) (by rw [hEDe]) hmove
      hK61 rfl (PushArg.slice (s := .int) (Or.inl rfl)) (by simp [EVw, Mode.ownSlot])
  let EGa : Entry := Entry.arm { EG0 with ty := GSD, held := EG0.held }
  -- armed: it views `s` (binding 0), and nothing of its own
  have hEGa : EGa = ⟨GSD, .own, true, [], [⟨0, .view⟩], true, true, false, false⟩ := by
    simp [EGa, EG0, hEDe, Entry.arm, EVw, EN0, derive, Mode.isRoot, rootKind, comp, GSD, GS, DT, T,
      Ty.dtorViews, Ty.holdsView]
  have hEnd5 : EndOK (A2.setE K6 5 EGa) 5 :=
    endOK_viewing hK6 (by rw [hEGa]; simp) (by rw [hEGa]; simp [roots, Entry.vdeps, Mode.ownSlot])
  have hg := StmtT.letd (ξ := .none) (P := P) (Γ := K5) (Γ1 := K6) (F := []) (x := 5) (f := 8) (r := .pair 4 1)
    (s := .skip) (E := EG0) (t := GS) (H := EG0.held) (τ := GSD) rfl
    (by simp [K5, K4, K3, K2, K1, A2.setE, upd]) (by simp) hgp rfl
    (Or.inl ⟨rfl, Or.inl (by simp [EG0, hEDe, EVw, GS])⟩) rfl rfl (letd_fn gsdrop_ok) (HeldUp.refl _ _)
    StmtT.skip hEnd5
  rw [exitScope_setE_same] at hg
  have hK7 := hK6.exitScope 5
  have hd := StmtT.letd (ξ := .none) (P := P) (Γ := K4) (Γ1 := K4) (F := []) (x := 4) (f := 0) (r := .pair 2 3)
    (E := EP) (t := T) (H := []) rfl (by simp [K4, K3, K2, K1, A2.setE, upd])
    (by simp) hpair rfl (Or.inl ⟨rfl, Or.inl rfl⟩) rfl rfl (letd_fn drop_ok) (HeldUp.refl _ _) hg.ofNone
    (hK7.endOK _)
  have h3 := StmtT.letv (ξ := .none) (P := P) (x := 3) (r := .expr (.lit 2)) (E := intE) (F := []) (Γ := K3) (Γ1 := K3)
    rfl (by simp [K3, K2, K1, A2.setE, upd]) (by simp) (RhsT.expr ExprT.lit) hd.ofNone
    ((hK7.exitScope 4).endOK _)
  have h2 := StmtT.letv (ξ := .none) (P := P) (x := 2) (r := .expr (.lit 1)) (E := intE) (F := []) (Γ := K2) (Γ1 := K2)
    rfl (by simp [K2, K1, A2.setE, upd]) (by simp) (RhsT.expr ExprT.lit) h3.ofNone
    (((hK7.exitScope 4).exitScope 3).endOK _)
  have h1 := StmtT.letv (ξ := .none) (P := P) (x := 1) (r := .view 0) (E := EVw) (F := []) (Γ := K1) (Γ1 := K1)
    rfl (by simp [K1, A2.setE]) (by simp) hview h2.ofNone
    ((((hK7.exitScope 4).exitScope 3).exitScope 2).endOK _)
  exact ⟨_, StmtT.letv (P := P) (x := 0) (r := .new .int) (E := EN0) (F := []) (Γ := fun _ => none)
    (Γ1 := fun _ => none) rfl rfl (by simp) (RhsT.new (by decide)) h1.ofNone
    (((((hK7.exitScope 4).exitScope 3).exitScope 2).exitScope 1).endOK _)⟩

/-- The program with a struct that holds a destructor value and a view of an
    older binding, dropped by its glue, is memory safe. -/
theorem main10_safe {m' : Mem} {s' : Stmt} (hr : Steps P (emptyMem 6) main10 (.ok m' s')) :
    ¬ Stuck P m' s' := by
  obtain ⟨Δ, ht⟩ := main10_typed
  exact memory_safe prog_ok prog_codes ht rfl (by simp [main10, Stmt.codesOK, Rhs.codeOK]) (by decide) hr

/-! ### An enum with a destructor payload and a view payload (Agora #750)

`: s ( new int )  : v ( view s )  :drop o ( inr DT v )`: an enum of type
`sum DT (slice int)`, its view variant made here, holding a view of the
older binding `s`.  It is bound by `letd` at `OVD`, armed: it views `s`.
At the frame's end it moves into its glue `ofnV` as a `sink` argument that
holds that view (`glueCall_typed`), whose view arm runs no code. -/

def main12 : Stmt :=
  .letv 0 (.new .int) (.letv 1 (.view 0) (.letd 2 9 (.inr DT 1) .skip))

theorem main12_typed : ∃ Δ, StmtT P ξ (fun _ => none) [] main12 Δ := by
  let K1 : Ctx := A2.setE (fun _ => none) 0 EN0
  have hK1 : NoRootb K1 := noRootb_empty.setE (by simp [EN0])
  let K2 : Ctx := A2.setE K1 1 EVw
  have hK2 : NoRootb K2 := hK1.setE (by simp [EVw])
  have hview : RhsT K1 [] (.view 0) EVw K1 :=
    RhsT.view (E := EN0) (t := .int) (by simp [K1, A2.setE]) rfl rfl rfl
  let EO0 : Entry := ⟨.sum DT EVw.ty, .own, true, [], derive 1 EVw .self ++ EVw.held, false, false, false, false⟩
  -- the enum literal: the view is copied in
  have hinr : RhsT K2 [] (.inr DT 1) EO0 K2 :=
    RhsT.inr (Ey := EVw) (by simp [K2, A2.setE]) rfl (PushArg.slice (s := .int) (Or.inl rfl))
      (by simp [DT, T, Ty.ok, Ty.isStruct])
  let EOa : Entry := Entry.arm { EO0 with ty := OVD, held := EO0.held }
  -- armed: it views `s` (binding 0), and nothing of its own
  have hEOa : EOa = ⟨OVD, .own, true, [], [⟨0, .view⟩], true, true, false, false⟩ := by
    simp [EOa, EO0, Entry.arm, EVw, EN0, derive, Mode.isRoot, rootKind, comp, OVD, OV, DT, T,
      Ty.dtorViews, Ty.holdsView]
  have hEnd : EndOK (A2.setE K2 2 EOa) 2 :=
    endOK_viewing hK2 (by rw [hEOa]; simp) (by rw [hEOa]; simp [roots, Entry.vdeps, Mode.ownSlot])
  have hd := StmtT.letd (ξ := .none) (P := P) (Γ := K2) (Γ1 := K2) (F := []) (x := 2) (f := 9) (r := .inr DT 1)
    (s := .skip) (E := EO0) (t := OV) (H := EO0.held) (τ := OVD) rfl
    (by simp [K2, K1, A2.setE, upd]) (by simp) hinr rfl
    (Or.inl ⟨rfl, Or.inl (by simp [EO0, EVw, OV])⟩) rfl rfl (letd_fn ovdrop_ok) (HeldUp.refl _ _)
    StmtT.skip hEnd
  rw [exitScope_setE_same] at hd
  have h1 := StmtT.letv (ξ := .none) (P := P) (x := 1) (r := .view 0) (E := EVw) (F := []) (Γ := K1) (Γ1 := K1)
    rfl (by simp [K1, A2.setE]) (by simp) hview hd.ofNone ((hK2.exitScope 2).endOK _)
  exact ⟨_, StmtT.letv (P := P) (x := 0) (r := .new .int) (E := EN0) (F := []) (Γ := fun _ => none)
    (Γ1 := fun _ => none) rfl rfl (by simp) (RhsT.new (by decide)) h1.ofNone
    (((hK2.exitScope 2).exitScope 1).endOK _)⟩

/-- The program with an enum that has a destructor payload and a view
    payload, holding the view of an older binding, dropped by its glue, is
    memory safe. -/
theorem main12_safe {m' : Mem} {s' : Stmt} (hr : Steps P (emptyMem 3) main12 (.ok m' s')) :
    ¬ Stuck P m' s' := by
  obtain ⟨Δ, ht⟩ := main12_typed
  exact memory_safe prog_ok prog_codes ht rfl (by simp [main12, Stmt.codesOK, Rhs.codeOK]) (by decide) hr

/-! ### A view-holding struct with its own `% Drop` (Agora #750)

`main10`'s program, the struct bound at `GSD2`, whose glue `glueS2`
rebinds it under the fields' glue `glueS` and runs the impl `implS` on it
lent; the struct views `s`, and the frame's end moves it, view and all,
into `glueS2`. -/

def main13 : Stmt :=
  .letv 0 (.new .int) (.letv 1 (.view 0) (.letv 2 (.expr (.lit 1)) (.letv 3 (.expr (.lit 2))
    (.letd 4 0 (.pair 2 3) (.letd 5 11 (.pair 4 1) .skip)))))

theorem main13_typed : ∃ Δ, StmtT P ξ (fun _ => none) [] main13 Δ := by
  let K1 : Ctx := A2.setE (fun _ => none) 0 EN0
  have hK1 : NoRootb K1 := noRootb_empty.setE (by simp [EN0])
  let K2 : Ctx := A2.setE K1 1 EVw
  have hK2 : NoRootb K2 := hK1.setE (by simp [EVw])
  let K3 : Ctx := A2.setE K2 2 intE
  let K4 : Ctx := A2.setE K3 3 intE
  have hK4 : NoRootb K4 := (hK2.setE (by simp [intE])).setE (by simp [intE])
  have hview : RhsT K1 [] (.view 0) EVw K1 :=
    RhsT.view (E := EN0) (t := .int) (by simp [K1, A2.setE]) rfl rfl rfl
  let ED : Entry := Entry.arm { EP with ty := DT, held := [] }
  have hEDe : ED = ⟨DT, .own, true, [], [], false, false, false, false⟩ := by
    simp [ED, EP, Entry.arm, DT, T, Ty.dtorViews, Ty.holdsView]
  have hpair : RhsT K4 [] (.pair 2 3) EP K4 :=
    RhsT.pair (Ey := intE) (Ez := intE) (by simp [K4, K3, A2.setE, upd]) rfl PushArg.int
      (by simp [K4, A2.setE]) rfl PushArg.int (by simp [intE, Mode.ownSlot])
  let K5 : Ctx := A2.setE K4 4 ED
  have hK5 : NoRootb K5 := hK4.setE (by rw [hEDe]; simp)
  let K6 : Ctx := A2.setE (kill .replace false 4 K5) 4 { ED with live := false, dtor := false }
  have hK6 : NoRootb K6 := (hK5.kill _ _ _).setE (by rw [hEDe]; simp)
  have hmove : PushArg K5 [] 4 ED ED.ty ED.held K6 :=
    PushArg.move (Γ := K5) (F := []) (y := 4) (E := ED) (t := ED.ty) rfl (by rw [hEDe]) (by simp)
      (hK5.noPin _) (DtorSafe.of_none (fun v E h => (hK5 v E h).2.1) _ _ _)
  have hK61 : K6 1 = some EVw := by
    simp [K6, K5, K4, K3, K2, A2.setE, upd, A2.kill, killE, hits, EVw, EN0, derive, Mode.isRoot,
      rootKind, Entry.vdeps, Mode.ownSlot]
  let EG0 : Entry := ⟨.prod ED.ty EVw.ty, .own, true, [], ED.held ++ (derive 1 EVw .self ++ EVw.held),
    false, false, false, false⟩
  have hgp : RhsT K5 [] (.pair 4 1) EG0 K6 :=
    RhsT.pair (Ey := ED) (Ez := EVw) (by simp [K5, A2.setE]) (by rw [hEDe]) hmove
      hK61 rfl (PushArg.slice (s := .int) (Or.inl rfl)) (by simp [EVw, Mode.ownSlot])
  let EGa : Entry := Entry.arm { EG0 with ty := GSD2, held := EG0.held }
  -- armed: it views `s` (binding 0), and nothing of its own
  have hEGa : EGa = ⟨GSD2, .own, true, [], [⟨0, .view⟩], true, true, false, false⟩ := by
    simp [EGa, EG0, hEDe, Entry.arm, EVw, EN0, derive, Mode.isRoot, rootKind, comp, GSD2, GS, DT, T,
      Ty.dtorViews, Ty.holdsView]
  have hEnd5 : EndOK (A2.setE K6 5 EGa) 5 :=
    endOK_viewing hK6 (by rw [hEGa]; simp) (by rw [hEGa]; simp [roots, Entry.vdeps, Mode.ownSlot])
  have hg := StmtT.letd (ξ := .none) (P := P) (Γ := K5) (Γ1 := K6) (F := []) (x := 5) (f := 11) (r := .pair 4 1)
    (s := .skip) (E := EG0) (t := GS) (H := EG0.held) (τ := GSD2) rfl
    (by simp [K5, K4, K3, K2, K1, A2.setE, upd]) (by simp) hgp rfl
    (Or.inl ⟨rfl, Or.inl (by simp [EG0, hEDe, EVw, GS])⟩) rfl rfl (letd_fn gs2drop_ok) (HeldUp.refl _ _)
    StmtT.skip hEnd5
  rw [exitScope_setE_same] at hg
  have hK7 := hK6.exitScope 5
  have hd := StmtT.letd (ξ := .none) (P := P) (Γ := K4) (Γ1 := K4) (F := []) (x := 4) (f := 0) (r := .pair 2 3)
    (E := EP) (t := T) (H := []) rfl (by simp [K4, K3, K2, K1, A2.setE, upd])
    (by simp) hpair rfl (Or.inl ⟨rfl, Or.inl rfl⟩) rfl rfl (letd_fn drop_ok) (HeldUp.refl _ _) hg.ofNone
    (hK7.endOK _)
  have h3 := StmtT.letv (ξ := .none) (P := P) (x := 3) (r := .expr (.lit 2)) (E := intE) (F := []) (Γ := K3) (Γ1 := K3)
    rfl (by simp [K3, K2, K1, A2.setE, upd]) (by simp) (RhsT.expr ExprT.lit) hd.ofNone
    ((hK7.exitScope 4).endOK _)
  have h2 := StmtT.letv (ξ := .none) (P := P) (x := 2) (r := .expr (.lit 1)) (E := intE) (F := []) (Γ := K2) (Γ1 := K2)
    rfl (by simp [K2, K1, A2.setE, upd]) (by simp) (RhsT.expr ExprT.lit) h3.ofNone
    (((hK7.exitScope 4).exitScope 3).endOK _)
  have h1 := StmtT.letv (ξ := .none) (P := P) (x := 1) (r := .view 0) (E := EVw) (F := []) (Γ := K1) (Γ1 := K1)
    rfl (by simp [K1, A2.setE]) (by simp) hview h2.ofNone
    ((((hK7.exitScope 4).exitScope 3).exitScope 2).endOK _)
  exact ⟨_, StmtT.letv (P := P) (x := 0) (r := .new .int) (E := EN0) (F := []) (Γ := fun _ => none)
    (Γ1 := fun _ => none) rfl rfl (by simp) (RhsT.new (by decide)) h1.ofNone
    (((((hK7.exitScope 4).exitScope 3).exitScope 2).exitScope 1).endOK _)⟩

/-- The program with a struct that has its own `% Drop` beside a destructor
    field and a view of an older binding is memory safe. -/
theorem main13_safe {m' : Mem} {s' : Stmt} (hr : Steps P (emptyMem 6) main13 (.ok m' s')) :
    ¬ Stuck P m' s' := by
  obtain ⟨Δ, ht⟩ := main13_typed
  exact memory_safe prog_ok prog_codes ht rfl (by simp [main13, Stmt.codesOK, Rhs.codeOK]) (by decide) hr

/-! ### A destructor value two levels down (A2-drop.3b)

`: c 3  :drop o ( inr ( prod DT int ) c )`: an enum of type
`sum (prod DT int) int`, its second variant made here.  Its first variant's
payload is a struct, of no destructor type of its own, holding a destructor
value.  A2-drop.3a's one-level `Ty.holdsDtor` asked only whether a field or
payload was itself a destructor type, so it did not see this one, and `letv`
bound such an enum with no glue.  Deep, the enum holds a destructor value:
`letv` refuses it (`main4_letv_refused`), and `letd` binds it at its own
destructor type, its glue `gfn` (`main4_safe`). -/

def main4 : Stmt := .letv 0 (.expr (.lit 3)) (.letd 1 3 (.inr AT 0) .skip)

def ES : Entry := ⟨ST, .own, true, [], [], false, false, false, false⟩

theorem main4_typed : ∃ Δ, StmtT P ξ (fun _ => none) [] main4 Δ := by
  let K1 : Ctx := A2.setE (fun _ => none) 0 intE
  have hK1 : NoRootb K1 := noRootb_empty.setE (by simp [intE])
  have hinr : RhsT K1 [] (.inr AT 0) ES K1 :=
    RhsT.inr (Ey := intE) (by simp [K1, A2.setE]) rfl PushArg.int
      (by simp [AT, DT, T, Ty.ok, Ty.isStruct])
  let ESd : Entry := Entry.arm { ES with ty := SDT, held := [] }
  have hESd : ESd.mode ≠ .rootb ∧ ESd.dtor = false ∧ ESd.dbind = false := by
    simp [ESd, ES, Entry.arm, SDT, ST, AT, DT, T, Ty.dtorViews, Ty.holdsView]
  have hK2 : NoRootb (A2.setE K1 1 ESd) := hK1.setE hESd
  have hd := StmtT.letd (ξ := .none) (P := P) (Γ := K1) (Γ1 := K1) (F := []) (x := 1) (f := 3) (r := .inr AT 0)
    (s := .skip) (E := ES) (t := ST) (H := []) rfl (by simp [K1, A2.setE]) (by simp) hinr rfl
    (Or.inl ⟨rfl, Or.inl rfl⟩) rfl rfl (letd_fn gdrop_ok) (HeldUp.refl _ _) StmtT.skip (hK2.endOK _)
  exact ⟨_, StmtT.letv (P := P) (x := 0) (r := .expr (.lit 3)) (E := intE) (F := []) (Γ := fun _ => none)
    (Γ1 := fun _ => none) rfl rfl (by simp) (RhsT.expr ExprT.lit) hd.ofNone ((hK2.exitScope 1).endOK _)⟩

/-- A2-drop.3b: the program binding a destructor value two levels down is
    memory safe. -/
theorem main4_safe {m' : Mem} {s' : Stmt} (hr : Steps P (emptyMem 2) main4 (.ok m' s')) :
    ¬ Stuck P m' s' := by
  obtain ⟨Δ, ht⟩ := main4_typed
  exact memory_safe prog_ok prog_codes ht rfl (by simp [main4, Stmt.codesOK, Rhs.codeOK]) (by decide) hr

/-- …and `letv` refuses that enum, in any context: deep, `Ty.holdsDtor`
    sees the destructor value under the struct. -/
theorem main4_letv_refused {Γ Δ : Ctx} {F : List Var} {x : Var} {s : Stmt} :
    ¬ StmtT P ξ Γ F (.letv x (.inr AT 0) s) Δ := by
  intro h
  obtain ⟨_, E, _, hr, hnd⟩ := A2.Dtor.letv_owned_no_dtor h
  cases hr
  simp [AT, DT, Ty.holdsDtor] at hnd

/-- An enum of a destructor type lends its payloads (`getl` / `getr`, through
    the type), the destructor staying with the whole value… -/
theorem enum_lends {Γ : Ctx} {F : List Var} {E0 : Entry} {f : Nat} {a b : Ty}
    (h0 : Γ 0 = some E0) (hl : E0.live = true) (ht : E0.ty = .dtor f (.sum a b)) :
    RhsT Γ F (.getl 0) (projE 0 E0 a) Γ ∧ RhsT Γ F (.getr 0) (projE 0 E0 b) Γ :=
  ⟨RhsT.getl_unfresh h0 hl (by rw [ht]; rfl), RhsT.getr_unfresh h0 hl (by rw [ht]; rfl)⟩

/-- …but a payload that holds no destructor value is not taken out of it
    (`takel` / `taker`): the enum's destructor would never run.  (Agora #632:
    one that holds a destructor value is taken out only where the enum's
    destructor is its glue, `TakeOK`.) -/
theorem enum_take_refused {Γ Γ' : Ctx} {F : List Var} {E E0 : Entry} {f : Nat} {a b : Ty}
    (h0 : Γ 0 = some E0) (ht : E0.ty = .dtor f (.sum a b)) :
    (a.holdsDtor = false → ¬ RhsT Γ F (.takel 0) E Γ') ∧
      (b.holdsDtor = false → ¬ RhsT Γ F (.taker 0) E Γ') := by
  refine ⟨fun ha h => ?_, fun hb h => ?_⟩
  · cases h with
    | takel hy _ _ hty _ _ _ =>
      rw [h0] at hy; cases hy; rw [ht] at hty
      rcases hty with hty | ⟨g, hty, hd⟩
      · cases hty
      · cases hty; rw [ha] at hd; cases hd
  · cases h with
    | taker hy _ _ hty _ _ _ =>
      rw [h0] at hy; cases hy; rw [ht] at hty
      rcases hty with hty | ⟨g, hty, hd⟩
      · cases hty
      · cases hty; rw [hb] at hd; cases hd

/-! ### A `Vec` of destructor values that hold views of an older binding (Agora #782)

`: s ( new int )  : v ( view s )  : a 1  : b 2  :drop c ( pair a b )
:drop p ( pair c v )  :drop w ( vec_new GSD )  ( vec_push w p )`: `main10`'s
struct, which views the older binding `s`, moves into a `Vec` bound by
`letd` at `vec GSD`.  The `Vec`'s binding records that view up front
(`HeldUp`: a view of `s`, a root bound before it): it is armed
(`Ty.dtorViews`), so nothing ends `s` while it lives, and the push gains it
no view (`StmtT.push`).  Its frame's end drains it (`Step.scopeDDrain`),
each element moved out to a `letd` armed with that view, whose frame moves
it into its glue `glueS`. -/

def main14 : Stmt :=
  .letv 0 (.new .int) (.letv 1 (.view 0) (.letv 2 (.expr (.lit 1)) (.letv 3 (.expr (.lit 2))
    (.letd 4 0 (.pair 2 3) (.letd 5 8 (.pair 4 1) (.letd 6 8 (.new GSD) (.push 6 5)))))))

/-- The witness's contexts: no borrowed parameter, and each binding that
    runs a destructor or is `letd`'s is one of `A`, viewing in memory only
    roots of `R`. -/
def Calm (A R : List Var) (Γ : Ctx) : Prop :=
  ∀ v E, Γ v = some E → E.mode ≠ .rootb ∧ ((E.dtor = true ∨ E.dbind = true) →
    v ∈ A ∧ ∀ d ∈ E.vdeps, d.kind.isName = false → d.root ∈ R)

theorem calm_of_noRootb {Γ : Ctx} (h : NoRootb Γ) (A R : List Var) : Calm A R Γ := fun v E hv => by
  obtain ⟨hm, hd, hb⟩ := h v E hv
  exact ⟨hm, fun h' => by rw [hd, hb] at h'; simp at h'⟩

theorem Calm.noRootb {R : List Var} {Γ : Ctx} (h : Calm [] R Γ) : NoRootb Γ := fun v E hv => by
  obtain ⟨hm, h'⟩ := h v E hv
  refine ⟨hm, ?_, ?_⟩
  · cases hd : E.dtor
    · rfl
    · exact absurd (h' (Or.inl hd)).1 (by simp)
  · cases hd : E.dbind
    · rfl
    · exact absurd (h' (Or.inr hd)).1 (by simp)

theorem Calm.setE {A R : List Var} {Γ : Ctx} (h : Calm A R Γ) {x : Var} {E : Entry}
    (hm : E.mode ≠ .rootb)
    (hE : (E.dtor = true ∨ E.dbind = true) → x ∈ A ∧ ∀ d ∈ E.vdeps, d.kind.isName = false → d.root ∈ R) :
    Calm A R (A2.setE Γ x E) := by
  intro v Ev hv
  by_cases hvx : v = x
  · subst hvx; simp only [A2.setE, upd_same, Option.some.injEq] at hv; subst hv; exact ⟨hm, hE⟩
  · simp only [A2.setE, upd_ne _ _ hvx] at hv; exact h v Ev hv

theorem Calm.kill {A R : List Var} {Γ : Ctx} (h : Calm A R Γ) (e : Eff) (hv : Bool) (x : Var) :
    Calm A R (A2.kill e hv x Γ) := by
  intro v E hE
  simp only [A2.kill] at hE
  cases hg : Γ v with
  | none => rw [hg] at hE; cases hE
  | some E0 =>
    rw [hg] at hE; simp only [Option.map_some, Option.some.injEq] at hE; subst hE
    obtain ⟨hm, h'⟩ := h v E0 hg
    rw [killE_mode, killE_dtor, killE_dbind, killE_vdeps]; exact ⟨hm, h'⟩

theorem Calm.exitScope {A R : List Var} {Γ : Ctx} (h : Calm A R Γ) (x : Var) (A' : List Var)
    (hA : ∀ v ∈ A, v ≠ x → v ∈ A') : Calm A' R (A2.exitScope x Γ) := by
  intro v E hv
  by_cases hvx : v = x
  · subst hvx; simp [A2.exitScope] at hv
  · simp only [A2.exitScope, upd_ne _ _ hvx] at hv
    obtain ⟨hm, h'⟩ := (h.kill .replace false x) v E hv
    exact ⟨hm, fun hd => ⟨hA v (h' hd).1 hvx, (h' hd).2⟩⟩

theorem Calm.noPin {A R : List Var} {Γ : Ctx} (h : Calm A R Γ) (x : Var) : NoPin Γ x :=
  fun p E hp hm => absurd hm (h p E hp).1

theorem Calm.dtorSafe {A R : List Var} {Γ : Ctx} (h : Calm A R Γ) {x : Var} (hx : x ∉ R) (e : Eff)
    (hv : Bool) : DtorSafe Γ e hv x := by
  intro v E hE hd _
  have hR := ((h v E hE).2 (Or.inl hd)).2
  cases hg : (E.ty != .int || E.mode == .rootb)
  · simp [hitsMem, hg]
  · unfold hitsMem; rw [hg, Bool.true_and, List.any_eq_false]
    intro d hdd hc
    simp only [Bool.and_eq_true, beq_iff_eq, Bool.not_eq_true'] at hc
    exact hx (by rw [← hc.1.1]; exact hR d hdd hc.1.2)

theorem Calm.dbindSafe {A R : List Var} {Γ : Ctx} (h : Calm A R Γ) {x : Var} (hx : x ∉ R) :
    DbindSafe Γ x :=
  fun v E hE hd _ _ d hdd hnm hdx => hx (by rw [← hdx]; exact ((h v E hE).2 (Or.inr hd)).2 d hdd hnm)

theorem Calm.endOK {A R : List Var} {Γ : Ctx} (h : Calm A R Γ) {x : Var} (hx : x ∉ R) : EndOK Γ x :=
  ⟨h.noPin x, h.dtorSafe hx _ _, h.dbindSafe hx⟩

theorem main14_typed : ∃ Δ, StmtT P ξ (fun _ => none) [] main14 Δ := by
  -- as in `main10`, up to the struct's binding
  let K1 : Ctx := A2.setE (fun _ => none) 0 EN0
  have hK1 : NoRootb K1 := noRootb_empty.setE (by simp [EN0])
  let K2 : Ctx := A2.setE K1 1 EVw
  have hK2 : NoRootb K2 := hK1.setE (by simp [EVw])
  let K3 : Ctx := A2.setE K2 2 intE
  let K4 : Ctx := A2.setE K3 3 intE
  have hK4 : NoRootb K4 := (hK2.setE (by simp [intE])).setE (by simp [intE])
  have hview : RhsT K1 [] (.view 0) EVw K1 :=
    RhsT.view (E := EN0) (t := .int) (by simp [K1, A2.setE]) rfl rfl rfl
  let ED : Entry := Entry.arm { EP with ty := DT, held := [] }
  have hEDe : ED = ⟨DT, .own, true, [], [], false, false, false, false⟩ := by
    simp [ED, EP, Entry.arm, DT, T, Ty.dtorViews, Ty.holdsView]
  have hpair : RhsT K4 [] (.pair 2 3) EP K4 :=
    RhsT.pair (Ey := intE) (Ez := intE) (by simp [K4, K3, A2.setE, upd]) rfl PushArg.int
      (by simp [K4, A2.setE]) rfl PushArg.int (by simp [intE, Mode.ownSlot])
  let K5 : Ctx := A2.setE K4 4 ED
  have hK5 : NoRootb K5 := hK4.setE (by rw [hEDe]; simp)
  let K6 : Ctx := A2.setE (kill .replace false 4 K5) 4 { ED with live := false, dtor := false }
  have hK6 : NoRootb K6 := (hK5.kill _ _ _).setE (by rw [hEDe]; simp)
  have hmove : PushArg K5 [] 4 ED ED.ty ED.held K6 :=
    PushArg.move (Γ := K5) (F := []) (y := 4) (E := ED) (t := ED.ty) rfl (by rw [hEDe]) (by simp)
      (hK5.noPin _) (DtorSafe.of_none (fun v E h => (hK5 v E h).2.1) _ _ _)
  have hK61 : K6 1 = some EVw := by
    simp [K6, K5, K4, K3, K2, A2.setE, upd, A2.kill, killE, hits, EVw, EN0, derive, Mode.isRoot,
      rootKind, Entry.vdeps, Mode.ownSlot]
  let EG0 : Entry := ⟨.prod ED.ty EVw.ty, .own, true, [], ED.held ++ (derive 1 EVw .self ++ EVw.held),
    false, false, false, false⟩
  have hgp : RhsT K5 [] (.pair 4 1) EG0 K6 :=
    RhsT.pair (Ey := ED) (Ez := EVw) (by simp [K5, A2.setE]) (by rw [hEDe]) hmove
      hK61 rfl (PushArg.slice (s := .int) (Or.inl rfl)) (by simp [EVw, Mode.ownSlot])
  let EGa : Entry := Entry.arm { EG0 with ty := GSD, held := EG0.held }
  have hEGa : EGa = ⟨GSD, .own, true, [], [⟨0, .view⟩], true, true, false, false⟩ := by
    simp [EGa, EG0, hEDe, Entry.arm, EVw, EN0, derive, Mode.isRoot, rootKind, comp, GSD, GS, DT, T,
      Ty.dtorViews, Ty.holdsView]
  -- the struct's binding, armed: it views `s` (binding 0)
  let K7 : Ctx := A2.setE K6 5 EGa
  have hC7 : Calm [5, 6] [0] K7 := (calm_of_noRootb hK6 _ _).setE (by rw [hEGa]; simp)
    (fun _ => by rw [hEGa]; simp [Entry.vdeps, Mode.ownSlot])
  -- the `Vec`, bound by `letd` at `vec GSD`, recording the view of `s` up front
  let EN : Entry := ⟨.vec GSD, .own, true, [], [], false, false, false, false⟩
  have hnew : RhsT K7 [] (.new GSD) EN K7 := RhsT.new (by decide)
  have hK70 : K7 0 = some EN0 := by
    simp [K7, K6, K5, K4, K3, K2, K1, A2.setE, upd, A2.kill, killE, hits, EN0, Entry.vdeps, Mode.ownSlot]
  have hH : HeldUp K7 EN [⟨0, .view⟩] := ⟨List.nil_subset _, fun d hd => by
    simp only [List.mem_singleton] at hd; subst hd
    exact Or.inr ⟨rfl, EN0, hK70, rfl⟩⟩
  let EW : Entry := Entry.arm { EN with ty := .vec GSD, held := [⟨0, .view⟩] }
  -- armed: its elements' destructors read what it views
  have hEWe : EW = ⟨.vec GSD, .own, true, [], [⟨0, .view⟩], true, true, false, false⟩ := by
    simp [EW, EN, Entry.arm, GSD, GS, DT, T, Ty.dtorViews, Ty.holdsView]
  let K8 : Ctx := A2.setE K7 6 EW
  have hC8 : Calm [5, 6] [0] K8 := hC7.setE (by rw [hEWe]; simp)
    (fun _ => by rw [hEWe]; simp [Entry.vdeps, Mode.ownSlot])
  -- the struct moves into it
  let K9 : Ctx := A2.setE (kill .replace false 5 K8) 5 { EGa with live := false, dtor := false }
  have hC9 : Calm [5, 6] [0] K9 := (hC8.kill _ _ _).setE (by rw [hEGa]; simp)
    (fun _ => by rw [hEGa]; simp [Entry.vdeps, Mode.ownSlot])
  have hmove2 : PushArg K8 [] 5 EGa GSD EGa.held K9 :=
    PushArg.move (Γ := K8) (F := []) (y := 5) (E := EGa) (t := GSD) rfl (by rw [hEGa]) (by simp)
      (hC8.noPin _) (hC8.dtorSafe (by simp) _ _)
  have hK96 : K9 6 = some EW := by
    simp [K9, K8, A2.setE, upd, A2.kill, killE, hits, hEWe, Entry.vdeps, Mode.ownSlot]
  have hpush := StmtT.push (ξ := .none) (P := P) (Γ := K8) (Γ1 := K9) (F := []) (x := 6) (y := 5) (Ex := EW) (Ey := EGa)
    (Ex1 := EW) (t := GSD) (D := EGa.held) (by simp [K8, A2.setE]) (by rw [hEWe]) (by rw [hEWe])
    (Or.inl (by rw [hEWe])) (by simp) (by simp [K8, K7, A2.setE, upd]) (by rw [hEGa]) (by rw [hEGa])
    (by decide) hmove2 (by rw [hEGa]; simp [roots]) hK96 (by rw [hEWe])
    (hC9.dtorSafe (by simp) _ _)
    -- what the struct views, the `Vec`'s binding views already
    (fun _ => by rw [hEWe, hEGa]; simp [ownHeld, GSD, GS, Ty.holdsView])
  let E10 : Entry := { EW with held := EW.held ++ ownHeld true GSD EGa.held }
  have hE10 : E10 = ⟨.vec GSD, .own, true, [], [⟨0, .view⟩, ⟨0, .view⟩], true, true, false, false⟩ := by
    simp [E10, hEWe, hEGa, ownHeld, GSD, GS, Ty.holdsView]
  have hC10 : Calm [5, 6] [0] (A2.setE (kill .realloc GSD.holdsView 6 K9) 6 E10) :=
    (hC9.kill _ _ _).setE (by rw [hE10]; simp) (fun _ => by rw [hE10]; simp [Entry.vdeps, Mode.ownSlot])
  have hdw := StmtT.letd (ξ := .none) (P := P) (Γ := K7) (Γ1 := K7) (F := []) (x := 6) (f := 8) (r := .new GSD)
    (s := .push 6 5) (E := EN) (t := GS) (H := [⟨0, .view⟩]) (τ := .vec GSD) rfl
    (by simp [K7, K6, K5, K4, K3, K2, K1, A2.setE, upd, A2.kill])
    (by simp) hnew rfl (Or.inr ⟨0, rfl, rfl⟩) rfl rfl (letd_fn gsdrop_ok) hH hpush.ofNone
    (hC10.endOK (by simp))
  have hC11 := hC10.exitScope 6 [5] (by simp)
  have hg := StmtT.letd (ξ := .none) (P := P) (Γ := K5) (Γ1 := K6) (F := []) (x := 5) (f := 8) (r := .pair 4 1)
    (s := .letd 6 8 (.new GSD) (.push 6 5)) (E := EG0) (t := GS) (H := EG0.held) (τ := GSD) rfl
    (by simp [K5, K4, K3, K2, K1, A2.setE, upd]) (by simp) hgp rfl
    (Or.inl ⟨rfl, Or.inl (by simp [EG0, hEDe, EVw, GS])⟩) rfl rfl (letd_fn gsdrop_ok) (HeldUp.refl _ _)
    hdw.ofNone (hC11.endOK (by simp))
  have hK12 : NoRootb _ := (hC11.exitScope 5 [] (by simp)).noRootb
  have hd := StmtT.letd (ξ := .none) (P := P) (Γ := K4) (Γ1 := K4) (F := []) (x := 4) (f := 0) (r := .pair 2 3)
    (E := EP) (t := T) (H := []) rfl (by simp [K4, K3, K2, K1, A2.setE, upd])
    (by simp) hpair rfl (Or.inl ⟨rfl, Or.inl rfl⟩) rfl rfl (letd_fn drop_ok) (HeldUp.refl _ _) hg.ofNone
    (hK12.endOK _)
  have h3 := StmtT.letv (ξ := .none) (P := P) (x := 3) (r := .expr (.lit 2)) (E := intE) (F := []) (Γ := K3) (Γ1 := K3)
    rfl (by simp [K3, K2, K1, A2.setE, upd]) (by simp) (RhsT.expr ExprT.lit) hd.ofNone
    ((hK12.exitScope 4).endOK _)
  have h2 := StmtT.letv (ξ := .none) (P := P) (x := 2) (r := .expr (.lit 1)) (E := intE) (F := []) (Γ := K2) (Γ1 := K2)
    rfl (by simp [K2, K1, A2.setE, upd]) (by simp) (RhsT.expr ExprT.lit) h3.ofNone
    (((hK12.exitScope 4).exitScope 3).endOK _)
  have h1 := StmtT.letv (ξ := .none) (P := P) (x := 1) (r := .view 0) (E := EVw) (F := []) (Γ := K1) (Γ1 := K1)
    rfl (by simp [K1, A2.setE]) (by simp) hview h2.ofNone
    ((((hK12.exitScope 4).exitScope 3).exitScope 2).endOK _)
  exact ⟨_, StmtT.letv (P := P) (x := 0) (r := .new .int) (E := EN0) (F := []) (Γ := fun _ => none)
    (Γ1 := fun _ => none) rfl rfl (by simp) (RhsT.new (by decide)) h1.ofNone
    (((((hK12.exitScope 4).exitScope 3).exitScope 2).exitScope 1).endOK _)⟩

/-- The program with a `Vec` of destructor values that hold a view of an
    older binding is memory safe. -/
theorem main14_safe {m' : Mem} {s' : Stmt} (hr : Steps P (emptyMem 7) main14 (.ok m' s')) :
    ¬ Stuck P m' s' := by
  obtain ⟨Δ, ht⟩ := main14_typed
  exact memory_safe prog_ok prog_codes ht rfl (by simp [main14, Stmt.codesOK, Rhs.codeOK]) (by decide) hr

/-- ... and leaks nothing when it ends (`no_leak_end`).  That the drain runs
    each element's glue, in a frame armed with the view, is read off the
    steps, as for `main11`: the theorem does not trace the run. -/
theorem main14_no_leak {m' : Mem} (hr : Steps P (emptyMem 7) main14 (.ok m' .skip)) :
    ∀ i, m'.alloc i = false := by
  obtain ⟨Δ, ht⟩ := main14_typed
  exact no_leak_end prog_ok prog_codes ht rfl (by simp [main14, Stmt.codesOK, Rhs.codeOK]) (by decide) hr

end A2.DtorWitness
