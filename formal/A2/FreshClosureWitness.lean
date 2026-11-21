import A2.FreshWitness

/-! # Agora #909: a closure over a view, whose code changes elements through a fresh borrow

    : ( Vec i ) v ( vec_new [i] )  : ( Slice i ) s ( slice_from_vec [i] v )
    : ( @ v i ) f \ [s] … → v {
        : ( Vec ( Vec i ) ) loc ( vec_new … )
        ( vec_push loc ( vec_new [i] ) )
        ( vec_push [i] ( vec_at loc 0 ) 7 )   -- a push THROUGH a borrow of loc's element
    }
    ( f )

A closure whose environment holds a view (`s`, of `v`), called through its
package (`StmtT.callc`).  Its code changes elements through a borrow of its
own local.  Before, `Implements` let through-changing code (`ThruFn`) take
only an environment that holds no views, and `CallT` let a call into it
pass no argument that holds views: the receiver here holds one.  Now the
borrow `( vec_at loc 0 )` is fresh and the push an `edit false`
(`FreshWitness.thruL`), so the code is not through-changing (`code_not_thru`,
`sig_not_thru`) and neither premise asks anything.

`prog_ok`, `main_typed`, and `memory_safe` / `no_leak_end` applied
(`main_safe`, `main_no_leak`).
-/

namespace A2.FreshClosureWitness
open A2.DynCell (NoRootb noRootb_empty)
open A2.ThruClosureWitness (Calm R0 body_typed)
open A2.DtorWitness (EN0 EVw)
open A2.FreshWitness (thruL thruL_typed)

def sl : Ty := .slice .int
/-- The closure's type: one method, whose interface is function 0. -/
def CT : Ty := .fn [0] .any

/-- The body of the code and the interface: `7` (its local 5) pushed through
    a fresh borrow of its own local's element, then `0` returned. -/
def fbody : Stmt := .seq (.letv 5 (.expr (.lit 7)) (thruL 5)) (.assign 1 (.expr (.lit 0)))

/-- The interface: it takes the receiver lent. -/
def sig : Fn where
  params := [(.inp, CT)]
  resTy := .int
  resOwn := false
  lends := []
  rholds := []
  outHolds := []
  body := fbody
  nvars := 6

/-- The closure's code: it takes the environment, a slice, lent. -/
def code : Fn where
  params := [(.inp, sl)]
  resTy := .int
  resOwn := false
  lends := []
  rholds := []
  outHolds := []
  body := fbody
  nvars := 6

def P : Prog := [sig, code]

theorem sig_not_thru : ¬ ThruFn P 0 := by
  intro h
  cases h with
  | here hf hb => simp [P] at hf; subst hf; simp [sig, fbody, thruL, Stmt.hasThru] at hb
  | call hf hg _ => simp [P] at hf; subst hf; simp [sig, fbody, thruL, Stmt.calls] at hg

theorem code_not_thru : ¬ ThruFn P 1 := by
  intro h
  cases h with
  | here hf hb => simp [P] at hf; subst hf; simp [code, fbody, thruL, Stmt.hasThru] at hb
  | call hf hg _ => simp [P] at hf; subst hf; simp [code, fbody, thruL, Stmt.calls] at hg

theorem fbody_typed {fn : Fn} (hb : fn.body = fbody) (hc : Calm (sigCtx fn)) (h1 : sigCtx fn 1 = some R0)
    (h2 : sigCtx fn 2 = none) (h3 : sigCtx fn 3 = none) (h4 : sigCtx fn 4 = none)
    (h5 : sigCtx fn 5 = none) :
    ∃ Δ, StmtT P .none (sigCtx fn) [] fn.body Δ ∧
      (∀ v E, Δ v = some E → E.dtor = false ∧ E.dbind = false) ∧
      Δ 1 = some { intE with mode := R0.mode } := by
  rw [hb]
  apply body_typed
  let G := A2.setE (sigCtx fn) 5 intE
  have hG : Calm G := hc.setE (by simp [intE])
  obtain ⟨Δ, ht, hcΔ, h1'⟩ := thruL_typed (Q := P) hG (n := 5) (En := intE) (by simp [G, A2.setE]) rfl rfl
    (by decide) (by decide) (by decide) (by simp [G, A2.setE, h2])
    (by simp [G, A2.setE, h3]) (by simp [G, A2.setE, h4])
    (by simp [G, A2.setE, h1])
  refine ⟨_, StmtT.letv (P := P) (ξ := .none) (x := 5) (Γ := sigCtx fn) (Γ1 := sigCtx fn) (F := [])
    (E := intE) rfl h5 (by simp) (RhsT.expr ExprT.lit) ht.ofNone (hcΔ.endOK _)
    (fun h => by simp [intE] at h), hcΔ.exitScope 5, ?_⟩
  simp [A2.exitScope, upd, A2.kill, h1', killE, hits, R0]

theorem calm_sig : Calm (sigCtx sig) := by
  intro v E h
  rcases v with _ | _ | v <;> simp [↓sigCtx_noRegion (fn := sig) (by decide), sig, paramE, symNames, CT, Ty.hasFn, resMode] at h <;>
    subst h <;> simp [Entry.vdeps, Mode.ownSlot]

theorem calm_code : Calm (sigCtx code) := by
  intro v E h
  rcases v with _ | _ | v <;> simp [↓sigCtx_noRegion (fn := code) (by decide), code, paramE, sl, Ty.hasFn, resMode] at h <;>
    subst h <;> simp [Entry.vdeps, Mode.ownSlot]

theorem sig_body : ∃ Δ, StmtT P .none (sigCtx sig) [] sig.body Δ ∧
    (∀ v E, Δ v = some E → E.dtor = false ∧ E.dbind = false) ∧
    Δ 1 = some { intE with mode := R0.mode } := fbody_typed (fn := sig) rfl calm_sig (by simp [↓sigCtx_noRegion (fn := sig) (by decide), sig, R0, resMode])
  (by simp [↓sigCtx_noRegion (fn := sig) (by decide), sig]) (by simp [↓sigCtx_noRegion (fn := sig) (by decide), sig]) (by simp [↓sigCtx_noRegion (fn := sig) (by decide), sig]) (by simp [↓sigCtx_noRegion (fn := sig) (by decide), sig])

theorem code_body : ∃ Δ, StmtT P .none (sigCtx code) [] code.body Δ ∧
    (∀ v E, Δ v = some E → E.dtor = false ∧ E.dbind = false) ∧
    Δ 1 = some { intE with mode := R0.mode } := fbody_typed (fn := code) rfl calm_code (by simp [↓sigCtx_noRegion (fn := code) (by decide), code, R0, resMode])
  (by simp [↓sigCtx_noRegion (fn := code) (by decide), code]) (by simp [↓sigCtx_noRegion (fn := code) (by decide), code]) (by simp [↓sigCtx_noRegion (fn := code) (by decide), code]) (by simp [↓sigCtx_noRegion (fn := code) (by decide), code])

theorem code_ok : FnOK P code := by
  obtain ⟨Δ, hb, hfl, hr⟩ := code_body
  refine ⟨rfl, by decide, by decide, rfl, by simp [code], ?_, by simp [code], by simp [code], by simp [code],
    by simp [code], by simp [code], ?_, Δ, hb, hfl, ?_, ?_⟩
  · intro pt hpt; simp [code] at hpt; subst hpt; simp [sl, Ty.ok, Ty.holdsView]
  · exact dtorParamsOK_of (by simp [code, sl, Ty.holdsDtor]) (by simp [code])
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
  rcases hfn with rfl | rfl <;> simp [sig, code, fbody, thruL, Stmt.codesOK, Rhs.codeOK]

/-- **The code implements its interface on an environment that holds
    views**: it is not through-changing, so `Implements` asks nothing of
    the environment. -/
theorem code_impl : Implements P 1 sl [] 0 :=
  ⟨code, sig, rfl, rfl, rfl, fun h => absurd rfl h, rfl, rfl, fun _ h => h, fun _ h => h, fun _ h => h,
    fun h => absurd h code_not_thru⟩

theorem pack_codes : CodeOK P [1] sl [0] [] := by
  refine ⟨rfl, fun j f σ hf hσ => ?_⟩
  rcases j with _ | j
  · simp at hf hσ; subst hf hσ; exact code_impl
  · simp at hf

/-! ### The caller: the closure over a view, called through its package -/

/-- `: v ( new int )  : s ( view v )  : f \ [s] …  ( f.0 )`: `v` is 0, `s` 1,
    the package 2, the result 3. -/
def main : Stmt :=
  .letv 0 (.new .int) (.letv 1 (.view 0) (.letv 2 (.pack [1] sl [0] 1 []) (.callc 3 2 0 0 [] .skip)))

/-- A call that takes only the receiver, lent, of a receiver that names
    nothing (it may hold views: the interface is not through-changing). -/
theorem callT_recv {P : Prog} {Γ : Ctx} {F : List Var} {σ : Nat} {sig : Fn} {c : Var}
    {Ec : Entry} (hσ : P[σ]? = some sig) (hps : sig.params = [(.inp, Ec.ty)]) (hc : Γ c = some Ec)
    (hl : Ec.live = true) (hmut : mutNames Γ [c] = []) (hR : ThruFn P σ → callR Γ [c] = []) :
    CallT P Γ F σ [c] (callRes Γ sig [c]) Γ := by
  have hpost : callPost Γ sig [c] = Γ := by
    simp [callPost, hps, callPostAux, hmut, killNames]
  refine ⟨sig, hσ, by simp [hps], fun i hi => ?_, fun d hd => ?_, ?_, rfl, hpost.symm, fun ht => callR_regions_of_nil (hR ht)⟩
  · have hi' : i = 0 := by rw [hps] at hi; simpa using hi
    subst hi'
    refine ⟨Ec, by simpa using hc, hl, ?_, fun h => ?_, fun h => ?_⟩
    · simp only [hps, List.getElem_cons_zero]; rfl
    · simp [hps, PMode.moves] at h
    · simp only [hps, List.getElem_cons_zero] at h; rcases h with h | h <;> cases h
  · rw [hmut] at hd; cases hd
  · exact CallDtorSafe.of_inp (fun p hp => by rw [hps] at hp; simp at hp; rw [hp]) hmut

theorem main_typed : ∃ Δ, StmtT P ξ (fun _ => none) [] main Δ := by
  let K1 : Ctx := A2.setE (fun _ => none) 0 EN0
  have hK1 : NoRootb K1 := noRootb_empty.setE (by simp [EN0])
  let K2 : Ctx := A2.setE K1 1 EVw
  have hK2 : NoRootb K2 := hK1.setE (by simp [EVw])
  have hview : RhsT K1 [] (.view 0) EVw K1 :=
    RhsT.view (E := EN0) (t := .int) (by simp [K1, A2.setE]) rfl rfl rfl
  have h21 : K2 1 = some EVw := by simp [K2, A2.setE]
  let EC : Entry := ⟨CT, .own, true, [], (derive 1 EVw .self ++ EVw.held) ++ capDeps [], false, false, false, false⟩
  have hpack : RhsT K2 [] (.pack [1] sl [0] 1 []) EC K2 :=
    RhsT.pack (q := .any) (Ey := EVw) h21 rfl rfl (PushArg.slice (s := .int) (Or.inl rfl))
      ⟨List.nodup_nil, fun _ h => by cases h⟩ (Cross.fits_any _ _ rfl)
  let K3 : Ctx := A2.setE K2 2 EC
  have hK3 : NoRootb K3 := hK2.setE (by simp [EC])
  have h32 : K3 2 = some EC := by simp [K3, A2.setE]
  have hcT : CallT P K3 [] 0 [2] (callRes K3 sig [2]) K3 :=
    callT_recv rfl rfl h32 rfl
      (by simp [mutNames, argNames, nameDeps, argE, h32, EC, EVw, EN0, derive, Mode.isRoot, rootKind,
        Entry.vdeps, Mode.ownSlot, capDeps, comp, Kind.isName])
      (fun h => absurd h sig_not_thru)
  let ER : Entry := recvRes 2 EC (callRes K3 sig [2])
  have hER : ER.mode ≠ .rootb ∧ ER.dtor = false ∧ ER.dbind = false := by
    simp [ER, recvRes, callRes, resMode, sig]
  have hK4 : NoRootb (A2.setE K3 3 ER) := hK3.setE hER
  have hcall := StmtT.callc (ξ := .none) (P := P) (Γ := K3) (Γ1 := K3) (F := []) (x := 3) (c := 2) (j := 0)
    (zs := []) (k := .skip) (Ec := EC) (E := callRes K3 sig [2]) (ms := [0]) (q := .any) (σ := 0)
    (sig := sig) rfl (by simp [K3, K2, K1, A2.setE, upd]) (by simp) h32 rfl rfl rfl rfl
    (fun o ho => by simp [sig] at ho) hcT (fun _ h => by cases h) StmtT.skip (hK4.endOK _)
    (fun ho => by simp [sig] at ho)
  have h2 := StmtT.letv (ξ := .none) (P := P) (x := 2) (r := .pack [1] sl [0] 1 []) (E := EC) (F := [])
    (Γ := K2) (Γ1 := K2) rfl (by simp [K2, K1, A2.setE, upd]) (by simp) hpack hcall.ofNone
    ((hK4.exitScope 3).endOK _) (fun _ => rfl)
  have h1 := StmtT.letv (ξ := .none) (P := P) (x := 1) (r := .view 0) (E := EVw) (F := []) (Γ := K1) (Γ1 := K1)
    rfl (by simp [K1, A2.setE]) (by simp) hview h2.ofNone (((hK4.exitScope 3).exitScope 2).endOK _)
  exact ⟨_, StmtT.letv (P := P) (x := 0) (r := .new .int) (E := EN0) (F := []) (Γ := fun _ => none)
    (Γ1 := fun _ => none) rfl rfl (by simp) (RhsT.new (by decide)) h1.ofNone
    ((((hK4.exitScope 3).exitScope 2).exitScope 1).endOK _)⟩

theorem main_codes : main.codesOK P := by
  simp only [main, Stmt.codesOK, Rhs.codeOK, true_and, and_true]
  exact pack_codes

/-- **The program that calls, through its package, a closure whose
    environment holds a view and whose code changes elements through a
    fresh borrow of its own local, is memory safe.** -/
theorem main_safe {m' : Mem} {s' : Stmt} (hr : Steps P (emptyMem 4) main (.ok m' s')) :
    ¬ Stuck P m' s' := by
  obtain ⟨Δ, ht⟩ := main_typed (ξ := .none)
  exact memory_safe prog_ok prog_codes ht rfl main_codes (by decide) hr

/-- ... and leaks nothing when it ends. -/
theorem main_no_leak {m' : Mem} (hr : Steps P (emptyMem 4) main (.ok m' .skip)) :
    ∀ i, m'.alloc i = false := by
  obtain ⟨Δ, ht⟩ := main_typed (ξ := .none)
  exact no_leak_end prog_ok prog_codes ht rfl main_codes (by decide) hr

end A2.FreshClosureWitness
