import A2.ClosureDropWitness

/-! # AGORA-395: a closure that changes elements through a borrow, called through its package

    : ( @ v i ) f \ i n → v {
        : ( Vec ( Vec i ) ) loc ( vec_new … )
        ( vec_push loc ( vec_new [i] ) )
        ( vec_push [i] ( vec_at loc 0 ) n )   -- a push THROUGH a borrow of loc's element
    }
    ( f 7 )

A closure's code that changes elements through a borrow (`ThruFn`, Agora
#295) of its own local, called through its package (`StmtT.callc`).  Before
AGORA-395 `Implements` refused such code outright (`¬ ThruFn P f`) and
`StmtT.callc` refused such an interface.  Now the code implements an
interface that is through-changing itself, its environment holding no views
and taken lent; a call through the package passes no argument that holds
views (`CallT`'s `ThruFn P σ → callR … = []`), and `Stmt.calls` names the
interface, so `ThruFn` follows the call.

A program of two functions:

* `sig` (0): the interface, which takes the receiver lent; its body is
  through-changing too, as `Implements` asks;
* `code` (1): the closure's code, on an integer environment `n` (the `7`):
  the body above, `n` pushed through the borrow `( vec_at loc 0 )`
  (`StmtT.editB`: the element type `int` holds no views);

both typed (`prog_ok`), the code implementing the interface with `ThruFn`
true (`code_impl`), and the caller

    : n 7  : f \ [n] …  ( f.0 )

typed from nothing (`main_typed`), with `memory_safe` and `no_leak_end`
applied (`main_safe`, `main_no_leak`).
-/

namespace A2.ThruClosureWitness
open A2.DynCell (NoRootb noRootb_empty)

def vi : Ty := .vec .int
def vvi : Ty := .vec vi
/-- The closure's type: one method, whose interface is function 0. -/
def CT : Ty := .fn [0] .any

/-- The body shared by the code and the interface, `n` the number pushed:
    `loc` is 2, the inner `Vec` 3, the borrow 4. -/
def thru (n : Var) : Stmt :=
  .letv 2 (.new vi) (.letv 3 (.new .int) (.seq (.push 2 3)
    (.letv 4 (.at 2 (.lit 0)) (.edit true 4 (.push n)))))

/-- The interface: it takes the receiver lent, and changes elements through
    a borrow of a local of its own (`n` its local 5). -/
def sig : Fn where
  params := [(.inp, CT)]
  resTy := .int
  resOwn := false
  lends := []
  rholds := []
  outHolds := []
  body := .seq (.letv 5 (.expr (.lit 7)) (thru 5)) (.assign 1 (.expr (.lit 0)))
  nvars := 6

/-- The closure's code: it takes the environment `n` lent. -/
def code : Fn where
  params := [(.inp, .int)]
  resTy := .int
  resOwn := false
  lends := []
  rholds := []
  outHolds := []
  body := .seq (thru 0) (.assign 1 (.expr (.lit 0)))
  nvars := 5

def P : Prog := [sig, code]

theorem sig_thru : ThruFn P 0 := ThruFn.here rfl rfl
theorem code_thru : ThruFn P 1 := ThruFn.here rfl rfl

/-! ### Contexts whose borrowed parameters hold nothing -/

def R0 : Entry := ⟨.int, .bor, false, [], [], false, false, false⟩
def Eloc : Entry := ⟨vvi, .own, true, [], [], false, false, false⟩
def Ein : Entry := ⟨vi, .own, true, [], [], false, false, false⟩
def Eb : Entry := ⟨vi, .bor, true, [⟨2, .inner⟩], [], false, false, false⟩

/-- No borrowed parameter depends on anything (so none pins a binding), and
    no binding runs a destructor. -/
def Calm (Γ : Ctx) : Prop :=
  ∀ v E, Γ v = some E → (E.mode = .rootb → E.vdeps = []) ∧ E.dtor = false ∧ E.dbind = false

theorem Calm.noPin {Γ : Ctx} (h : Calm Γ) (x : Var) : NoPin Γ x :=
  fun p E hp hm d hd => by rw [(h p E hp).1 hm] at hd; cases hd

theorem Calm.dtor {Γ : Ctx} (h : Calm Γ) (e : Eff) (hv : Bool) (x : Var) : DtorSafe Γ e hv x :=
  DtorSafe.of_none (fun v E hv => (h v E hv).2.1) _ _ _

theorem Calm.endOK {Γ : Ctx} (h : Calm Γ) (x : Var) : EndOK Γ x :=
  ⟨h.noPin x, h.dtor _ _ _, DbindSafe.of_none (fun v E hv => (h v E hv).2.2) x⟩

theorem Calm.setE {Γ : Ctx} (h : Calm Γ) {x : Var} {E : Entry}
    (hE : (E.mode = .rootb → E.vdeps = []) ∧ E.dtor = false ∧ E.dbind = false) :
    Calm (A2.setE Γ x E) := by
  intro v E' hv
  simp only [A2.setE, upd] at hv
  split at hv
  · cases hv; exact hE
  · exact h v E' hv

theorem Calm.kill {Γ : Ctx} (h : Calm Γ) (e : Eff) (hv : Bool) (x : Var) :
    Calm (A2.kill e hv x Γ) := by
  intro v E' h'
  simp only [A2.kill] at h'
  cases hg : Γ v with
  | none => rw [hg] at h'; cases h'
  | some E =>
    rw [hg] at h'; simp only [Option.map_some, Option.some.injEq] at h'; subst h'
    have := h v E hg
    unfold killE; split <;> exact this

theorem Calm.exitScope {Γ : Ctx} (h : Calm Γ) (x : Var) : Calm (A2.exitScope x Γ) := by
  intro v E' h'
  simp only [A2.exitScope, upd] at h'
  split at h'
  · cases h'
  · exact h.kill .replace false x v E' h'

theorem Calm.killNames {Γ : Ctx} (h : Calm Γ) : ∀ ds : List Dep, Calm (A2.killNames ds Γ)
  | [] => h
  | d :: ds => by
    simp only [A2.killNames, List.foldr_cons]
    exact Calm.kill (Calm.killNames h ds) _ _ _

theorem Calm.killThru {Γ : Ctx} (h : Calm Γ) (op : Edit) (tx : Ty) (P : List Dep) :
    Calm (A2.killThru op tx P Γ) := h.killNames _

/-- A number, borrowed or not, that depends on nothing is ended by nothing. -/
theorem killE_int {E : Entry} (ht : E.ty = .int) (hr : E.mode = .rootb → E.vdeps = [])
    (e : Eff) (hv : Bool) (x : Var) : killE e hv x E = E := by
  unfold killE hits
  by_cases hm : E.mode = .rootb
  · simp [hr hm]
  · simp [ht, hm]

theorem calm_sig : Calm (sigCtx sig) := by
  intro v E h
  rcases v with _ | _ | v <;> simp [sigCtx, sig, paramE, symNames, CT, Ty.hasFn, resMode] at h <;>
    subst h <;> simp [Entry.vdeps, Mode.ownSlot]

theorem calm_code : Calm (sigCtx code) := by
  intro v E h
  rcases v with _ | _ | v <;> simp [sigCtx, code, paramE, Ty.hasFn, resMode] at h <;>
    subst h <;> simp [Entry.vdeps, Mode.ownSlot]

/-! ### The result slot stays as it was -/

theorem r0_kill {Γ : Ctx} (h : Γ 1 = some R0) (e : Eff) (hv : Bool) (x : Var) :
    A2.kill e hv x Γ 1 = some R0 := by
  simp [A2.kill, h, killE_int (E := R0) rfl (by simp [R0])]

theorem r0_killNames {Γ : Ctx} (h : Γ 1 = some R0) : ∀ ds : List Dep, A2.killNames ds Γ 1 = some R0
  | [] => h
  | d :: ds => by
    simp only [A2.killNames, List.foldr_cons]
    exact r0_kill (r0_killNames h ds) _ _ _

theorem r0_setE {Γ : Ctx} {x : Var} {E : Entry} (hx : x ≠ 1) (h : Γ 1 = some R0) :
    A2.setE Γ x E 1 = some R0 := by
  simp [A2.setE, upd, h, Ne.symm hx]

theorem r0_exit {Γ : Ctx} {x : Var} (hx : x ≠ 1) (h : Γ 1 = some R0) :
    A2.exitScope x Γ 1 = some R0 := by
  simp only [A2.exitScope, upd, Ne.symm hx, ite_false]
  exact r0_kill h _ _ _

/-! ### The body: a push through a borrow of a local's element -/

/-- The push through `( vec_at loc 0 )`, whose path is `loc`'s elements,
    may drop them: `loc` is a live owner, not what is pushed. -/
theorem thru_ok {Γ : Ctx} (hc : Calm Γ) {n : Var} {E : Entry} (h2 : Γ 2 = some E) (hl : E.live = true)
    (hm : E.mode = .own) (hn : n ≠ 2) : ThruOK Γ [] (.push n) vi [⟨2, .inner⟩] := by
  intro d hd
  simp only [memDeps, Kind.isName, Bool.not_false, List.filter_cons_of_pos, List.filter_nil,
    List.mem_singleton] at hd
  subst hd
  refine ⟨by simp, fun y hy => ?_, _, h2, hl, Or.inl hm, hc.dtor _ _ _, by simp⟩
  simp [Edit.stored] at hy
  subst hy
  exact fun h => hn h.symm

/-- `thru n` typed in a calm context where `n` is a live number, the result
    slot `1` untouched — in any program: it calls nothing (the destructor
    witness `A2.ThruDtorWitness` types the same body). -/
theorem thru_typed {Q : Prog} {Γ : Ctx} (hc : Calm Γ) {n : Var} {En : Entry} (hn : Γ n = some En)
    (hnl : En.live = true) (hnt : En.ty = .int) (hn2 : n ≠ 2) (hn3 : n ≠ 3) (hn4 : n ≠ 4)
    (h2 : Γ 2 = none) (h3 : Γ 3 = none) (h4 : Γ 4 = none) (h1 : Γ 1 = some R0) :
    ∃ Δ, StmtT Q .none Γ [] (thru n) Δ ∧ Calm Δ ∧ Δ 1 = some R0 := by
  -- `: ( Vec ( Vec i ) ) loc`
  let G2 := A2.setE Γ 2 Eloc
  have hG2 : Calm G2 := hc.setE (by simp [Eloc])
  -- `vec_new [i]`
  let G3 := A2.setE G2 3 Ein
  have hG3 : Calm G3 := hG2.setE (by simp [Ein])
  have h3n : G3 n = some En := by simp [G3, G2, A2.setE, upd, hn2, hn3, hn]
  -- the inner `Vec` moved into `loc`
  let G3' := A2.setE (A2.kill .replace false 3 G3) 3 { Ein with live := false, dtor := false }
  have hG3' : Calm G3' := (hG3.kill _ _ _).setE (by simp [Ein])
  have hpush : StmtT Q .none G3 [] (.push 2 3)
      (A2.setE (A2.kill .realloc vi.holdsView 2 G3') 2 { Eloc with held := Eloc.held ++ ownHeld true vi Ein.held }) :=
    StmtT.push (Ex := Eloc) (Ey := Ein) (Ex1 := Eloc) (t := vi) (by simp [G3, G2, A2.setE, upd]) rfl rfl
      (Or.inl rfl) (by simp) (by simp [G3, A2.setE]) rfl rfl (by decide)
      (PushArg.move (by simp [vi, Ty.owning]) rfl (by simp) (hG3.noPin _) (hG3.dtor _ _ _))
      (by simp [Ein, roots]) (by simp [G3', G3, G2, A2.setE, upd, A2.kill, killE, hits, Eloc, Entry.vdeps,
        Mode.ownSlot]) rfl (hG3'.dtor _ _ _) (fun h => by simp [Eloc] at h)
  let G4 := A2.setE (A2.kill .realloc vi.holdsView 2 G3') 2 { Eloc with held := Eloc.held ++ ownHeld true vi Ein.held }
  have hG4 : Calm G4 := (hG3'.kill _ _ _).setE (by simp [Eloc])
  have hG42 : G4 2 = some Eloc := by simp [G4, A2.setE, Eloc, ownHeld, vi, Ty.holdsView]
  have hke := killE_int hnt (hc n En hn).1
  have hG4n : G4 n = some En := by
    simp [G4, G3', A2.setE, upd, A2.kill, hn2, hn3, h3n, hke]
  -- `( vec_at loc 0 )`
  let G5 := A2.setE G4 4 Eb
  have hG5 : Calm G5 := hG4.setE (by simp [Eb])
  have hat : RhsT G4 [] (.at 2 (.lit 0)) Eb G4 := by
    have := RhsT.at (Γ := G4) (F := []) (E := Eloc) (t := vi) (i := .lit 0) hG42 rfl rfl ExprT.lit
    simpa [elemE, Eloc, Eb, vi, vvi, derive, Mode.isRoot, rootKind] using this
  -- the push through the borrow
  have hed := StmtT.editB (b := true) (P := Q) (ξ := .none) (Γ := G5) (Γ1 := G5) (F := []) (x := 4) (op := .push n)
    (Ex := Eb) (Ex1 := Eb) (t := .int) (D := []) (by simp [G5, A2.setE]) rfl rfl rfl rfl (by simp)
    (EditArg.push (Ey := En) (by simp [G5, A2.setE, hn4, hG4n]) hnl hnt PushArg.int)
    (fun y hy => by simp [Edit.stored] at hy; subst hy; exact hn4)
    (by simp [G5, A2.setE]) rfl (by simp [Eb, memDeps, Kind.isName])
    (thru_ok hG5 (E := Eloc) (by simp [G5, A2.setE, hG42]) rfl rfl hn2)
    (fun h => by simp [Edit.drops] at h)
  have hD5 : Calm (A2.setE (A2.killThru (.push n) (Ty.vec .int) [⟨2, .inner⟩] G5) 4 Eb) :=
    (hG5.killThru _ _ _).setE (by simp [Eb])
  have hl4 := StmtT.letv (P := Q) (ξ := .none) (x := 4) (Γ := G4) (Γ1 := G4) (F := []) (E := Eb)
    (s := .edit true 4 (.push n)) rfl (by simp [G4, A2.setE, upd, G3', A2.kill, G3, G2, h4]) (by simp) hat
    hed.ofNone (hD5.endOK _) (fun h => by simp [Eb] at h)
  have hs := StmtT.seq (P := Q) (ξ := .none) rfl hpush hl4
  have hl3 := StmtT.letv (P := Q) (ξ := .none) (x := 3) (Γ := G2) (Γ1 := G2) (F := []) (E := Ein)
    rfl (by simp [G2, A2.setE, h3]) (by simp) (RhsT.new (t := .int) rfl) hs.ofNone
    ((hD5.exitScope 4).endOK _) (fun _ => rfl)
  have hl2 := StmtT.letv (P := Q) (ξ := .none) (x := 2) (Γ := Γ) (Γ1 := Γ) (F := []) (E := Eloc)
    rfl h2 (by simp) (RhsT.new (t := vi) rfl) hl3.ofNone
    (((hD5.exitScope 4).exitScope 3).endOK _) (fun _ => rfl)
  refine ⟨_, hl2, ((hD5.exitScope 4).exitScope 3).exitScope 2, ?_⟩
  have hG51 : G5 1 = some R0 := by
    simp [G5, G4, G3', G3, G2, A2.setE, upd, A2.kill, h1, killE_int (E := R0) rfl (by simp [R0])]
  exact r0_exit (by decide) (r0_exit (by decide) (r0_exit (by decide)
    (r0_setE (by decide) (r0_killNames hG51 _))))

/-- The result set last: `= r 0`. -/
theorem assign_typed {Q : Prog} {Γ : Ctx} (hc : Calm Γ) (h1 : Γ 1 = some R0) :
    StmtT Q .none Γ [] (.assign 1 (.expr (.lit 0)))
      (A2.setE (kill .replace false 1 Γ) 1 { intE with mode := R0.mode }) :=
  StmtT.assign (Ex := R0) (E := intE) h1 (by simp) (Or.inr (Or.inr ⟨rfl, rfl⟩))
    (RhsT.expr ExprT.lit) rfl (by simp [intE, roots, Entry.vdeps, Mode.ownSlot]) (by simp [h1])
    (hc.noPin _) (hc.dtor _ _ _) rfl

theorem body_typed {Q : Prog} {Γ : Ctx} {s : Stmt}
    (h : ∃ Δ, StmtT Q .none Γ [] s Δ ∧ Calm Δ ∧ Δ 1 = some R0) :
    ∃ Δ, StmtT Q .none Γ [] (.seq s (.assign 1 (.expr (.lit 0)))) Δ ∧
      (∀ v E, Δ v = some E → E.dtor = false ∧ E.dbind = false) ∧
      Δ 1 = some { intE with mode := R0.mode } := by
  obtain ⟨Δ, ht, hcΔ, h1⟩ := h
  refine ⟨_, StmtT.seq rfl ht (assign_typed hcΔ h1), fun v E hv => ((hcΔ.kill _ _ _).setE
    (by simp [intE, R0]) v E hv).2, by simp [A2.setE, upd]⟩

theorem code_body : ∃ Δ, StmtT P .none (sigCtx code) [] code.body Δ ∧
    (∀ v E, Δ v = some E → E.dtor = false ∧ E.dbind = false) ∧
    Δ 1 = some { intE with mode := R0.mode } :=
  body_typed (thru_typed calm_code (En := ⟨.int, .rootb, true, [], [], false, false, false⟩)
    (by simp [sigCtx, code, paramE, Ty.hasFn]) rfl rfl (by decide) (by decide) (by decide)
    (by simp [sigCtx, code]) (by simp [sigCtx, code]) (by simp [sigCtx, code])
    (by simp [sigCtx, code, R0, resMode]))

theorem sig_body : ∃ Δ, StmtT P .none (sigCtx sig) [] sig.body Δ ∧
    (∀ v E, Δ v = some E → E.dtor = false ∧ E.dbind = false) ∧
    Δ 1 = some { intE with mode := R0.mode } := by
  apply body_typed
  let G := A2.setE (sigCtx sig) 5 intE
  have hG : Calm G := calm_sig.setE (by simp [intE])
  obtain ⟨Δ, ht, hcΔ, h1⟩ := thru_typed hG (n := 5) (En := intE) (by simp [G, A2.setE]) rfl rfl
    (by decide) (by decide) (by decide) (by simp [G, A2.setE, sigCtx, sig])
    (by simp [G, A2.setE, sigCtx, sig]) (by simp [G, A2.setE, sigCtx, sig])
    (by simp [G, A2.setE, sigCtx, sig, R0, resMode])
  refine ⟨_, StmtT.letv (P := P) (ξ := .none) (x := 5) (Γ := sigCtx sig) (Γ1 := sigCtx sig) (F := [])
    (E := intE) rfl (by simp [sigCtx, sig]) (by simp) (RhsT.expr ExprT.lit) ht.ofNone (hcΔ.endOK _)
    (fun h => by simp [intE] at h), hcΔ.exitScope 5, ?_⟩
  simp [A2.exitScope, upd, A2.kill, h1, killE, hits, R0]

/-! ### Both functions are well-typed -/

theorem code_ok : FnOK P code := by
  obtain ⟨Δ, hb, hfl, hr⟩ := code_body
  refine ⟨rfl, by decide, by decide, rfl, by simp [code], ?_, by simp [code], by simp [code], by simp [code],
    by simp [code], by simp [code], ?_, Δ, hb, hfl, ?_, ?_⟩
  · intro pt hpt; simp [code] at hpt; subst hpt; simp [Ty.ok]
  · exact dtorParamsOK_of (by simp [code, Ty.holdsDtor]) (by simp [code])
  · exact ⟨{ intE with mode := R0.mode }, by simpa [code] using hr, rfl, rfl, by simp [R0, resMode, code],
      by simp [intE], by simp [intE], by simp [code]⟩
  · intro i hi b hb; simp [code] at hi; subst hi; simp [code] at hb

theorem sig_ok : FnOK P sig := by
  obtain ⟨Δ, hb, hfl, hr⟩ := sig_body
  refine ⟨rfl, by decide, by decide, rfl, by simp [sig], ?_, by simp [sig], by simp [sig], by simp [sig],
    by simp [sig], by simp [sig], ?_, Δ, hb, hfl, ?_, ?_⟩
  · intro pt hpt; simp [sig] at hpt; subst hpt; simp [CT, Ty.ok]
  · exact dtorParamsOK_of (by simp [sig, CT, Ty.holdsDtor]) (by simp [sig])
  · exact ⟨{ intE with mode := R0.mode }, by simpa [sig] using hr, rfl, rfl, by simp [R0, resMode, sig],
      by simp [intE], by simp [intE], by simp [sig]⟩
  · intro i hi b hb; simp [sig] at hi; subst hi; simp [sig] at hb

theorem prog_ok : ProgOK P := by
  intro fn hfn
  simp only [P, List.mem_cons, List.mem_nil_iff, or_false] at hfn
  rcases hfn with rfl | rfl
  · exact sig_ok
  · exact code_ok

theorem prog_codes : ProgCodes P := by
  intro fn hfn
  simp only [P, List.mem_cons, List.mem_nil_iff, or_false] at hfn
  rcases hfn with rfl | rfl <;> simp [sig, code, thru, Stmt.codesOK, Rhs.codeOK]

/-- **AGORA-395: through-changing code implements a through-changing
    interface.**  The code changes elements through a borrow (`ThruFn P 1`),
    and so does its interface (`ThruFn P 0`); the environment, an integer,
    holds no views, and the interface takes the receiver lent: the last
    conjunct of `Implements` holds with its premise true. -/
theorem code_impl : Implements P 1 .int [] 0 :=
  ⟨code, sig, rfl, rfl, rfl, fun h => absurd rfl h, rfl, rfl, fun _ h => h, fun _ h => h, fun _ h => h,
    fun _ => ⟨sig_thru, rfl, rfl⟩⟩

theorem pack_codes : CodeOK P [1] .int [0] [] := by
  refine ⟨rfl, fun j f σ hf hσ => ?_⟩
  rcases j with _ | j
  · simp at hf hσ; subst hf hσ; exact code_impl
  · simp at hf

/-! ### The caller: the closure called through its package -/

/-- `: n 7  : f \ [n] …  ( f.0 )`: `n` is 0, the package 1, the result 2. -/
def main : Stmt :=
  .letv 0 (.expr (.lit 7)) (.letv 1 (.pack [1] .int [0] 0 []) (.callc 2 1 0 0 [] .skip))

/-- A call that takes only the receiver, lent, of a receiver that names
    nothing and holds no views (`callR` is empty: AGORA-395, a
    through-changing interface asks it). -/
theorem callT_recv {P : Prog} {Γ : Ctx} {F : List Var} {σ : Nat} {sig : Fn} {c : Var}
    {Ec : Entry} (hσ : P[σ]? = some sig) (hps : sig.params = [(.inp, Ec.ty)]) (hc : Γ c = some Ec)
    (hl : Ec.live = true) (hn : Ec.vdeps = []) (hR : callR Γ [c] = []) :
    CallT P Γ F σ [c] (callRes Γ sig [c]) Γ := by
  have hmut : mutNames Γ [c] = [] := by
    simp [mutNames, argNames, nameDeps, argE, hc, hn]
  have hpost : callPost Γ sig [c] = Γ := by
    simp [callPost, hps, callPostAux, hmut, killNames]
  refine ⟨sig, hσ, by simp [hps], fun i hi => ?_, fun d hd => ?_, ?_, rfl, hpost.symm, fun _ => hR⟩
  · have hi' : i = 0 := by rw [hps] at hi; simpa using hi
    subst hi'
    refine ⟨Ec, by simpa using hc, hl, ?_, fun h => ?_, fun h => ?_⟩
    · simp only [hps, List.getElem_cons_zero]; rfl
    · simp [hps, PMode.moves] at h
    · simp only [hps, List.getElem_cons_zero] at h; rcases h with h | h <;> cases h
  · rw [hmut] at hd; cases hd
  · exact CallDtorSafe.of_inp (fun p hp => by rw [hps] at hp; simp at hp; rw [hp]) hmut

/-- **AGORA-395: the caller, which calls through-changing code through its
    package, is typed**: the call by `StmtT.callc`, its interface (function
    0) through-changing, the receiver holding no views. -/
theorem main_typed : ∃ Δ, StmtT P ξ (fun _ => none) [] main Δ := by
  let K1 : Ctx := A2.setE (fun _ => none) 0 intE
  have hK1 : NoRootb K1 := noRootb_empty.setE (by simp [intE])
  let EC : Entry := ⟨CT, .own, true, [], [] ++ capDeps [], false, false, false⟩
  have hpack : RhsT K1 [] (.pack [1] .int [0] 0 []) EC K1 :=
    RhsT.pack (q := .any) (Ey := intE) (by simp [K1, A2.setE]) rfl rfl PushArg.int
      ⟨List.nodup_nil, fun _ h => by cases h⟩ (Cross.fits_any _ _ rfl)
  let K2 : Ctx := A2.setE K1 1 EC
  have hK2 : NoRootb K2 := hK1.setE (by simp [EC])
  have h21 : K2 1 = some EC := by simp [K2, A2.setE]
  have hcT : CallT P K2 [] 0 [1] (callRes K2 sig [1]) K2 :=
    callT_recv rfl rfl h21 rfl (by simp [EC, Entry.vdeps, Mode.ownSlot, capDeps])
      (by simp [callR, argE, h21, EC, CT, capDeps, memDeps, roots])
  let ER : Entry := recvRes 1 EC (callRes K2 sig [1])
  have hER : ER.mode ≠ .rootb ∧ ER.dtor = false ∧ ER.dbind = false := by
    simp [ER, recvRes, callRes, resMode, sig]
  have hK3 : NoRootb (A2.setE K2 2 ER) := hK2.setE hER
  have hcall := StmtT.callc (ξ := .none) (P := P) (Γ := K2) (Γ1 := K2) (F := []) (x := 2) (c := 1) (j := 0)
    (zs := []) (k := .skip) (Ec := EC) (E := callRes K2 sig [1]) (ms := [0]) (q := .any) (σ := 0)
    (sig := sig) rfl (by simp [K2, K1, A2.setE, upd]) (by simp) h21 rfl rfl rfl rfl
    (fun o ho => by simp [sig] at ho) hcT (fun _ h => by cases h) StmtT.skip (hK3.endOK _)
    (fun ho => by simp [sig] at ho)
  have h1 := StmtT.letv (ξ := .none) (P := P) (x := 1) (r := .pack [1] .int [0] 0 []) (E := EC) (F := [])
    (Γ := K1) (Γ1 := K1) rfl (by simp [K1, A2.setE]) (by simp) hpack hcall.ofNone
    ((hK3.exitScope 2).endOK _) (fun _ => rfl)
  exact ⟨_, StmtT.letv (P := P) (x := 0) (r := .expr (.lit 7)) (E := intE) (F := []) (Γ := fun _ => none)
    (Γ1 := fun _ => none) rfl rfl (by simp) (RhsT.expr ExprT.lit) h1.ofNone
    (((hK3.exitScope 2).exitScope 1).endOK _)⟩

theorem main_codes : main.codesOK P := by
  simp only [main, Stmt.codesOK, Rhs.codeOK, true_and, and_true]
  exact pack_codes

/-- **AGORA-395: the program that calls a closure whose code changes
    elements through a borrow of its own local, through its package, is
    memory safe.** -/
theorem main_safe {m' : Mem} {s' : Stmt} (hr : Steps P (emptyMem 3) main (.ok m' s')) :
    ¬ Stuck P m' s' := by
  obtain ⟨Δ, ht⟩ := main_typed (ξ := .none)
  exact memory_safe prog_ok prog_codes ht rfl main_codes (by decide) hr

/-- ... and when it ends, everything it allocated is freed: `loc` and its
    element, in the code's frame, and the package's environment. -/
theorem main_no_leak {m' : Mem} (hr : Steps P (emptyMem 3) main (.ok m' .skip)) :
    ∀ i, m'.alloc i = false := by
  obtain ⟨Δ, ht⟩ := main_typed (ξ := .none)
  exact no_leak_end prog_ok prog_codes ht rfl main_codes (by decide) hr

end A2.ThruClosureWitness
