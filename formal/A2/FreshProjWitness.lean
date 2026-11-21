import A2.InoutViewArgWitness

/-! # AGORA-909: a call that hands a view to a function pushing through a field of its `inout` parameter

    : Bag { ( Vec i ) items i n }
    @ add inout Bag b ( Slice i ) s → i {
        ( vec_push . b items 7 )            -- a push THROUGH a field read of a parameter
        ^ 0
    }
    : ~ Bag b …  : src ( vec_new [i] )  : s ( slice_from_vec src )
    : r ( add b s )                         -- the call passes an argument that holds views
    ( slice_at s 0 )                        -- and `s` is read after it

A field read `. b items` (`RhsT.fst`) of a binding of the frame's own (`b` is
`inout`) whose type holds no views and that holds nothing is a fresh borrow,
as an element borrow of one is (`RhsT.at`, Agora #909 design e): its path,
`projDeps`, is `[⟨b, .inner⟩]`. So the push is an `edit false`, `add` is not
through-changing (`g_not_thru`), and `CallT`'s `callR` premise asks nothing.
The call passes `s`, and `s` is read after it.

What stays refused (`proj_fresh_src`): a field or payload read is fresh only
of a binding of the frame's own or of a fresh, held-fresh borrow, of a type
that holds no views, holding nothing. So a read of a borrowed parameter
(`fst_rootb_not_fresh`), of a borrow that is not fresh (`proj_stale_not_fresh`)
or of a type that holds views (`nested_view_not_fresh`) is not, and a nested
projection is fresh exactly where every step is (`proj_of_proj_fresh`;
`A2/FreshNestWitness.lean` types `. . o bag items`). A fresh payload borrow
ends when its enum is given a new value, and that kill does not read the bit
(`payload_fresh_killed`).
-/

namespace A2.FreshProjWitness
open A2.ThruClosureWitness (vi Calm killE_int)
open A2.TakeWitness (NoRootb noRootb_empty)
open A2.InoutViewArgWitness (sl killE_nodeps keep_kill keep_killNames keep_setE keep_exit)

/-- `Bag`: its items and a number. -/
def bag : Ty := .prod vi .int

/-- `add b s`: `b` is 0, `s` 1, the result slot 2, the field borrow 3,
    the number `7` 4. -/
def gBody : Stmt :=
  .seq (.letv 3 (.fst 0) (.letv 4 (.expr (.lit 7)) (.edit false 3 (.push 4))))
    (.assign 2 (.expr (.lit 0)))

def g : Fn where
  params   := [(.inout .replace, bag), (.inp, sl)]
  resTy    := .int
  resOwn   := false
  lends    := []
  rholds   := []
  outHolds := []
  body     := gBody
  nvars    := 5

def P : Prog := [g]

/-! ### The callee -/

def Ep : Entry := ⟨bag, .inout .replace, true, [], [], false, false, false, false⟩
def Es : Entry := ⟨sl, .rootb, true, [], [], false, false, false, false⟩
def R0 : Entry := ⟨.int, .bor, false, [], [], false, false, false, false⟩
/-- The field borrow, fresh: its path is `b`'s fields. -/
def Ee : Entry := ⟨vi, .bor, true, [⟨0, .inner⟩], [], false, false, true, true⟩

/-- The callee's context, with result slot `r2`. -/
def ctx (r2 : Entry) : Ctx := fun v =>
  if v = 0 then some Ep else if v = 1 then some Es else if v = 2 then some r2 else none

theorem sig_eq : sigCtx g = ctx R0 := by
  funext v
  simp only [↓sigCtx_noRegion (fn := g) (by decide), ctx, g, paramE, resMode]
  rcases v with _ | _ | _ | v <;> simp [Ep, Es, R0, bag, vi, sl, Ty.hasFn]

theorem calm_ctx {r : Entry} (hr : r.mode = .bor) (hd : r.dtor = false) (hb : r.dbind = false) :
    Calm (ctx r) := by
  intro v E h
  rcases v with _ | _ | _ | v <;> simp [ctx] at h <;> subst h <;>
    simp [Ep, Es, Entry.vdeps, Mode.ownSlot, hr, hd, hb]

/-- `. b items`: fresh, `b` is an `inout` parameter (`Mode.frame`) of a type
    that holds no views and holds nothing. -/
theorem fst_typed : RhsT (ctx R0) [] (.fst 0) Ee (ctx R0) := by
  have h0 : ctx R0 0 = some Ep := by simp [ctx]
  have := RhsT.fst (Γ := ctx R0) (F := []) (E := Ep) (a := vi) (b := .int) (f := true) h0 rfl rfl
    (fun _ => ⟨Or.inl (Or.inr ⟨.replace, rfl⟩), rfl, rfl, fun s h => by cases h⟩)
  simpa [projE, projDeps, Ep, Ee, vi, Mode.ownSlot] using this

theorem Ep_nodeps : Ep.vdeps = [] := by simp [Ep, Entry.vdeps, Mode.ownSlot]
theorem Es_nodeps : Es.vdeps = [] := by simp [Es, Entry.vdeps, Mode.ownSlot]
theorem R0_nodeps : R0.vdeps = [] := by simp [R0, Entry.vdeps, Mode.ownSlot]

/-! ### The push through `( vec_at vv 0 )`: an `edit false` -/

def G3 : Ctx := A2.setE (ctx R0) 3 Ee
def G4 : Ctx := A2.setE G3 4 intE
def Δe : Ctx := A2.setE (A2.killThru (.push 4) vi [⟨0, .inner⟩] G4) 3 Ee

theorem calm_G4 : Calm G4 := ((calm_ctx rfl rfl rfl).setE (by simp [Ee])).setE (by simp [intE])
theorem G4_0 : G4 0 = some Ep := by simp [G4, G3, A2.setE, upd, ctx]

theorem thru_ok : ThruOK G4 [] (.push 4) vi [⟨0, .inner⟩] := by
  intro d hd
  simp only [memDeps, Kind.isName, Bool.not_false, List.filter_cons_of_pos, List.filter_nil,
    List.mem_singleton] at hd
  subst hd
  refine ⟨by simp, fun y hy => ?_, _, G4_0, rfl, Or.inr ⟨.replace, rfl, by decide⟩, calm_G4.dtor _ _ _, by simp⟩
  simp [Edit.stored] at hy; subst hy; decide

theorem edit_typed : StmtT P .none G4 [] (.edit false 3 (.push 4)) Δe := by
  have h3 : G4 3 = some Ee := by simp [G4, G3, A2.setE, upd]
  have h4 : G4 4 = some intE := by simp [G4, A2.setE]
  have := StmtT.editB (b := false) (P := P) (ξ := .none) (Γ := G4) (Γ1 := G4) (F := []) (x := 3)
    (op := .push 4) (Ex := Ee) (Ex1 := Ee) (t := .int) (D := []) h3 rfl rfl rfl rfl
    (by simp) (EditArg.push (Ey := intE) h4 rfl rfl PushArg.int)
    (fun y hy => by simp [Edit.stored] at hy; subst hy; decide)
    h3 rfl (by simp [Ee, memDeps, Kind.isName]) thru_ok
    (fun h => by simp [Edit.drops] at h) (fun _ => rfl)
  simpa [Δe, Ee] using this

theorem calm_Δe : Calm Δe := (calm_G4.killThru _ _ _).setE (by simp [Ee])

/-! ### The body -/

def Δ3 : Ctx := A2.exitScope 3 (A2.exitScope 4 Δe)

theorem calm_Δ3 : Calm Δ3 := (calm_Δe.exitScope 4).exitScope 3

theorem Δe_keep {v : Var} {E : Entry} (hv : ctx R0 v = some E) (h : E.vdeps = []) (h3 : v ≠ 3) (h4 : v ≠ 4) :
    Δe v = some E := by
  have : G4 v = some E := keep_setE (Ne.symm h4) (keep_setE (Ne.symm h3) hv)
  exact keep_setE (Ne.symm h3) (keep_killNames this h _)

theorem Δ3_keep {v : Var} {E : Entry} (hv : ctx R0 v = some E) (h : E.vdeps = []) (h3 : v ≠ 3) (h4 : v ≠ 4) :
    Δ3 v = some E :=
  keep_exit (Ne.symm h3) (keep_exit (Ne.symm h4) (Δe_keep hv h h3 h4) h) h

theorem inner_typed : StmtT P .none (ctx R0) []
    (.letv 3 (.fst 0) (.letv 4 (.expr (.lit 7)) (.edit false 3 (.push 4)))) Δ3 := by
  have hl4 := StmtT.letv (P := P) (ξ := .none) (x := 4) (Γ := G3) (Γ1 := G3) (F := []) (E := intE)
    (r := .expr (.lit 7)) (s := .edit false 3 (.push 4)) rfl (by simp [G3, A2.setE, upd, ctx]) (by simp) (RhsT.expr ExprT.lit)
    edit_typed.ofNone (calm_Δe.endOK _) (fun h => by simp [intE] at h)
  exact StmtT.letv (P := P) (ξ := .none) (x := 3) (Γ := ctx R0) (Γ1 := ctx R0) (F := []) (E := Ee)
    rfl (by simp [ctx]) (by simp) fst_typed hl4.ofNone ((calm_Δe.exitScope 4).endOK _) (fun h => by simp [Ee] at h)

def Δf : Ctx := A2.setE (A2.kill .replace false 2 Δ3) 2 { intE with mode := R0.mode }

theorem body_typed : StmtT P .none (sigCtx g) [] g.body Δf := by
  rw [sig_eq]
  have h2 : Δ3 2 = some R0 := Δ3_keep (by simp [ctx]) R0_nodeps (by decide) (by decide)
  have ha := StmtT.assign (ξ := .none) (P := P) (Γ := Δ3) (F := []) (x := 2) (r := .expr (.lit 0)) (Ex := R0)
    (E := intE) (Γ1 := Δ3) h2 (by simp) (Or.inr (Or.inr ⟨rfl, rfl⟩))
    (RhsT.expr ExprT.lit) rfl (by simp [intE, roots, Entry.vdeps, Mode.ownSlot]) (by simp [h2])
    (calm_Δ3.noPin _) (calm_Δ3.dtor _ _ _) rfl
  exact StmtT.seq rfl inner_typed ha

theorem calm_Δf : Calm Δf := (calm_Δ3.kill _ _ _).setE (by simp [intE, R0])

theorem g_not_thru : ¬ ThruFn P 0 := by
  intro h
  cases h with
  | here hf hb => simp [P] at hf; subst hf; simp [g, gBody, Stmt.hasThru] at hb
  | call hf hg _ => simp [P] at hf; subst hf; simp [g, gBody, Stmt.calls] at hg

theorem g_ok : FnOK P g := by
  have hΔ0 : Δf 0 = some Ep :=
    keep_setE (by decide) (keep_kill (Δ3_keep (by simp [ctx]) Ep_nodeps (by decide) (by decide)) Ep_nodeps _ _ _)
  refine ⟨rfl, by decide, by decide, rfl, by simp [g], ?_, by simp [g], by simp [g], by simp [g], by simp [g],
    by simp [g], dtorParamsOK_of (by simp [g] <;> decide) (by simp [g]), Δf, body_typed,
    fun v E hE => ⟨(calm_Δf v E hE).2.1, (calm_Δf v E hE).2.2⟩,
    ⟨{ intE with mode := R0.mode }, by simp [Δf, A2.setE, g], rfl, rfl, by simp [R0, resMode, g],
      by simp [intE], by simp [intE], by simp [g]⟩, ?_⟩
  · intro pt hpt
    simp only [g, List.mem_cons, List.mem_nil_iff, or_false] at hpt
    rcases hpt with rfl | rfl <;> simp [bag, vi, sl, Ty.ok, Ty.owning, Ty.holdsView]
  · intro i hi b hb
    rcases i with _ | i
    · exact ⟨Ep, hΔ0, rfl, by simp [Ep], by simp [Ep]⟩
    · rcases i with _ | i
      · simp [g] at hb
      · simp [g] at hi; omega

theorem prog_ok : ProgOK P := by
  intro fn hfn
  simp only [P, List.mem_cons, List.mem_nil_iff, or_false] at hfn
  subst hfn; exact g_ok

theorem prog_codes : ProgCodes P := by
  intro fn hfn
  simp only [P, List.mem_cons, List.mem_nil_iff, or_false] at hfn
  subst hfn; simp [g, gBody, Stmt.codesOK, Rhs.codeOK]

/-! ### The caller: `( add b s )` with `s` a view of `src`, read after the call -/

/-- `: items ( new i )  : n 5  : b { items n }  : src ( new i )  : k 8
    ( vec_push src k )  : s ( view src )  : r ( add b s )  : x ( slice_at s 0 )`:
    `items` 0, `n` 1, `b` 2, `src` 3, `s` 4, `r` 5, `x` 6, `k` 7. `src` holds
    an element before it is viewed, so the read after the call is in bounds
    and a run can end normally. -/
def main : Stmt :=
  .letv 0 (.new .int) (.letv 1 (.expr (.lit 5)) (.letv 2 (.pair 0 1) (.letv 3 (.new .int)
    (.letv 7 (.expr (.lit 8)) (.seq (.push 3 7)
      (.letv 4 (.view 3) (.letcall 5 0 [2, 4] (.letv 6 (.sat 4 (.lit 0)) .skip))))))))

def Ev : Entry := ⟨vi, .own, true, [], [], false, false, false, false⟩
def Ev0 : Entry := { Ev with live := false, dtor := false }
def Eb : Entry := ⟨bag, .own, true, [], [], false, false, false, false⟩
def Esv : Entry := ⟨sl, .bor, true, [⟨3, .view⟩], [], false, false, false, false⟩

def K1 : Ctx := A2.setE (fun _ => none) 0 Ev
def K2 : Ctx := A2.setE K1 1 intE
def K2' : Ctx := A2.setE (A2.kill .replace false 0 K2) 0 Ev0
def K3 : Ctx := A2.setE K2' 2 Eb
def K4 : Ctx := A2.setE K3 3 Ev
def K4p : Ctx := A2.setE K4 7 intE
def K5 : Ctx := A2.setE K4p 4 Esv

theorem K2'_noRootb : NoRootb K2' := by
  intro v E h
  simp only [K2', K2, K1, A2.setE, upd, A2.kill] at h
  rcases v with _ | _ | v <;> simp [killE, hits, Entry.vdeps, Ev, Ev0, intE] at h <;> subst h <;>
    simp

theorem K5_noRootb : NoRootb K5 :=
  (((K2'_noRootb.setE (by simp [Eb])).setE (by simp [Ev])).setE (by simp [intE])).setE (by simp [Esv])

theorem K5_2 : K5 2 = some Eb := by simp [K5, K4p, K4, K3, A2.setE, upd]
theorem K5_4 : K5 4 = some Esv := by simp [K5, A2.setE]

theorem callPost_eq : callPost K5 g [2, 4] = K5 := by
  funext v
  simp only [callPost, callPostAux, g, killNames, mutNames, argNames]
  rcases v with _ | _ | _ | _ | _ | v <;>
    simp [argE, K5, K4p, K4, K3, K2', K2, K1, A2.setE, upd, A2.kill, killE, hits, Ev, Ev0, Eb, Esv, intE,
      Entry.vdeps, Mode.ownSlot, bag, vi, sl, Ty.holdsView, Ty.elem, nameDeps, Eff.kills, Kind.bound]

/-- **The call is typed**: `b` is handed `inout`, and no other argument
    reaches it in memory (`s` reaches `src`); `add` is not through-changing,
    so passing the view `s` asks nothing. -/
theorem call_ok : CallT P K5 [] 0 [2, 4] (callRes K5 g [2, 4]) K5 := by
  refine ⟨g, rfl, rfl, ?_, ?_, CallDtorSafe.of_none (fun v E hE => ⟨(K5_noRootb v E hE).2.1,
      (K5_noRootb v E hE).2.2⟩) _ _, rfl, callPost_eq.symm, fun h => absurd h g_not_thru⟩
  · intro i hi
    rcases i with _ | _ | i
    · refine ⟨Eb, K5_2, rfl, ⟨rfl, Or.inl rfl, rfl⟩, fun _ => ?_,
        fun _ => fun p E hp hm => absurd hm (K5_noRootb p E hp).1⟩
      refine ⟨by simp, by simp [Eb, roots, memDeps, Entry.vdeps, Mode.ownSlot], (fun h => by cases h),
        (fun _ _ d hd => by simp [Eb, Entry.vdeps, Mode.ownSlot] at hd), fun j hj hji => ?_⟩
      rcases j with _ | _ | j
      · exact absurd rfl hji
      · refine ⟨by decide, ?_, ?_, ?_⟩
        · simp [argE, K5_4, Esv, roots, memDeps, Entry.vdeps, Mode.ownSlot, Kind.isName]
        · intro h; simp [g] at h
        · intro b _ d hd hr
          simp [argE, K5_4, Esv, Entry.vdeps, Mode.ownSlot] at hd; subst hd; simp at hr
      · simp [g] at hj; omega
    · exact ⟨Esv, K5_4, rfl, rfl, fun h => by simp [g, PMode.moves] at h,
        fun h => by simp [g] at h⟩
    · simp [g] at hi; omega
  · intro d hd
    simp [mutNames, argNames, argE, K5_2, K5_4, Eb, Esv, nameDeps, Entry.vdeps, Mode.ownSlot, bag, vi,
      Kind.isName] at hd

theorem main_typed : ∃ Δ, StmtT P ξ (fun _ => none) [] main Δ := by
  let ER := callRes K5 g [2, 4]
  have hER : ER.mode ≠ .rootb ∧ ER.dtor = false ∧ ER.dbind = false := by
    simp [ER, callRes, resMode, g]
  have hL : NoRootb (A2.setE K5 5 ER) := K5_noRootb.setE hER
  have hL4 : A2.setE K5 5 ER 4 = some Esv := by simp [A2.setE, upd, K5_4]
  have hsat : RhsT (A2.setE K5 5 ER) [] (.sat 4 (.lit 0)) intE (A2.setE K5 5 ER) := by
    have := RhsT.sat (Γ := A2.setE K5 5 ER) (F := []) (y := 4) (E := Esv) (t := .int) (i := .lit 0)
      hL4 rfl rfl ExprT.lit
    simpa [elemE, intE] using this
  have hL6 : NoRootb (A2.setE (A2.setE K5 5 ER) 6 intE) := hL.setE (by simp [intE])
  have h6 := StmtT.letv (ξ := .none) (P := P) (x := 6) (r := .sat 4 (.lit 0)) (s := .skip) (E := intE) (F := [])
    (Γ := A2.setE K5 5 ER) (Γ1 := A2.setE K5 5 ER) rfl
    (by simp [A2.setE, upd, K5, K4p, K4, K3, K2', K2, K1, A2.kill]) (by simp) hsat StmtT.skip (hL6.endOK _)
  have hc := StmtT.letcall (ξ := .none) (P := P) (Γ := K5) (F := []) (x := 5) (f := 0) (args := [2, 4])
    (s := .letv 6 (.sat 4 (.lit 0)) .skip) (E := ER) (Γ1 := K5) rfl
    (by simp [K5, K4p, K4, K3, K2', K2, K1, A2.setE, upd, A2.kill])
    (by simp) call_ok h6.ofNone ((hL6.exitScope 6).endOK _)
    (fun fn hf ho _ => by simp [P] at hf; subst hf; simp [g] at ho)
  have hK4 : NoRootb K4 := (K2'_noRootb.setE (by simp [Eb])).setE (by simp [Ev])
  have hK4p : NoRootb K4p := hK4.setE (by simp [intE])
  have hK3 : NoRootb K3 := K2'_noRootb.setE (by simp [Eb])
  have hview : RhsT K4p [] (.view 3) Esv K4p := by
    have := RhsT.view (Γ := K4p) (F := []) (y := 3) (E := Ev) (t := .int) (by simp [K4p, K4, A2.setE, upd])
      rfl rfl rfl
    simpa [derive, Mode.isRoot, rootKind, Ev, Esv, vi, sl] using this
  have h4 := StmtT.letv (ξ := .none) (P := P) (x := 4) (r := .view 3) (E := Esv) (F := []) (Γ := K4p) (Γ1 := K4p)
    rfl (by simp [K4p, K4, K3, K2', K2, K1, A2.setE, upd, A2.kill]) (by simp) hview hc.ofNone
    (((hL6.exitScope 6).exitScope 5).endOK _)
  -- `( vec_push src k )`: a number, so nothing moves and nothing ends
  have hpk : A2.setE (A2.kill .realloc Ty.int.holdsView 3 K4p) 3 { Ev with held := Ev.held ++ ownHeld true .int [] }
      = K4p := by
    funext v
    rcases v with _ | _ | _ | _ | _ | _ | _ | _ | v <;>
      simp [K4p, K4, K3, K2', K2, K1, A2.setE, upd, A2.kill, killE, hits, Ev, Ev0, Eb, intE, Entry.vdeps,
        Mode.ownSlot, ownHeld, Ty.holdsView]
  have hpush : StmtT P .none K4p [] (.push 3 7) K4p := by
    have := StmtT.push (ξ := .none) (P := P) (Γ := K4p) (Γ1 := K4p) (F := []) (x := 3) (y := 7) (Ex := Ev)
      (Ey := intE) (Ex1 := Ev) (t := .int) (D := []) (by simp [K4p, K4, A2.setE, upd]) rfl rfl (Or.inl rfl)
      (by simp) (by simp [K4p, A2.setE]) rfl rfl (by decide) PushArg.int (by simp [roots])
      (by simp [K4p, K4, A2.setE, upd]) rfl (DtorSafe.of_none (fun v E h => (hK4p v E h).2.1) _ _ _)
      (fun h => by simp [Ev] at h)
    rwa [hpk] at this
  have hseq := StmtT.seq (ξ := .none) rfl hpush h4.ofNone
  have h7 := StmtT.letv (ξ := .none) (P := P) (x := 7) (r := .expr (.lit 8)) (E := intE) (F := []) (Γ := K4)
    (Γ1 := K4) rfl (by simp [K4, K3, K2', K2, K1, A2.setE, upd, A2.kill]) (by simp) (RhsT.expr ExprT.lit)
    hseq.ofNone (((((hL6.exitScope 6).exitScope 5).exitScope 4)).endOK _)
  have h3 := StmtT.letv (ξ := .none) (P := P) (x := 3) (r := .new .int) (E := Ev) (F := []) (Γ := K3) (Γ1 := K3)
    rfl (by simp [K3, K2', K2, K1, A2.setE, upd, A2.kill]) (by simp) (RhsT.new rfl) h7.ofNone
    (((((hL6.exitScope 6).exitScope 5).exitScope 4).exitScope 7).endOK _)
  have hK2 : NoRootb K2 := (noRootb_empty.setE (by simp [Ev])).setE (by simp [intE])
  have hpair : RhsT K2 [] (.pair 0 1) Eb K2' := by
    have := RhsT.pair (Γ := K2) (F := []) (y := 0) (z := 1) (Ey := Ev) (Ez := intE)
      (by simp [K2, K1, A2.setE, upd]) rfl
      (PushArg.move (by simp [Ev, vi, Ty.owning]) rfl (by simp) (A2.DynCell.NoRootb.noPin
        (fun v E h => hK2 v E h) _) (DtorSafe.of_none (fun v E h => (hK2 v E h).2.1) _ _ _))
      (by simp [A2.setE, upd, A2.kill, killE, hits, K2, intE, Entry.vdeps, Mode.ownSlot]) rfl PushArg.int
      (fun h => by simp [intE, Mode.ownSlot] at h)
    simpa [Eb, Ev, Ev0, K2', intE, bag] using this
  have h2 := StmtT.letv (ξ := .none) (P := P) (x := 2) (r := .pair 0 1) (E := Eb) (F := []) (Γ := K2) (Γ1 := K2')
    rfl (by simp [K2, K1, A2.setE, upd]) (by simp) hpair h3.ofNone
    ((((((hL6.exitScope 6).exitScope 5).exitScope 4).exitScope 7).exitScope 3).endOK _)
  have h1 := StmtT.letv (ξ := .none) (P := P) (x := 1) (r := .expr (.lit 5)) (E := intE) (F := []) (Γ := K1)
    (Γ1 := K1) rfl (by simp [K1, A2.setE, upd]) (by simp) (RhsT.expr ExprT.lit) h2.ofNone
    (((((((hL6.exitScope 6).exitScope 5).exitScope 4).exitScope 7).exitScope 3).exitScope 2).endOK _)
  exact ⟨_, StmtT.letv (P := P) (x := 0) (r := .new .int) (E := Ev) (F := []) (Γ := fun _ => none)
    (Γ1 := fun _ => none) rfl rfl (by simp) (RhsT.new rfl) h1.ofNone
    ((((((((hL6.exitScope 6).exitScope 5).exitScope 4).exitScope 7).exitScope 3).exitScope 2).exitScope 1).endOK
      _)⟩

theorem main_codes : main.codesOK P := by simp [main, Stmt.codesOK, Rhs.codeOK]

/-- **The program is memory safe**: a callee that pushes through a field
    read of its `inout` parameter, called with an argument that holds a
    view, which is read after the call. -/
theorem main_safe {m' : Mem} {s' : Stmt} (hr : Steps P (emptyMem 8) main (.ok m' s')) :
    ¬ Stuck P m' s' := by
  obtain ⟨Δ, ht⟩ := main_typed (ξ := .none)
  exact memory_safe prog_ok prog_codes ht rfl main_codes (by decide) hr

/-- ... and leaks nothing when it ends. -/
theorem main_no_leak {m' : Mem} (hr : Steps P (emptyMem 8) main (.ok m' .skip)) :
    ∀ i, m'.alloc i = false := by
  obtain ⟨Δ, ht⟩ := main_typed (ξ := .none)
  exact no_leak_end prog_ok prog_codes ht rfl main_codes (by decide) hr

/-! ### What stays refused, and how the bit composes -/

/-- What a fresh field or payload read may be taken from: a binding of the
    frame's own, or a fresh, held-fresh borrow. -/
def ProjSrc (E : Entry) : Prop := E.mode.frame ∨ (E.mode = .bor ∧ E.fresh = true ∧ E.heldFresh = true)

/-- **A fresh field or payload read is of a `ProjSrc` that holds nothing, of
    a type that holds no views**: whatever the derivation, the bit is set
    only there. -/
theorem proj_fresh_src {Γ Γ1 : Ctx} {F : List Var} {y : Var} {r : Rhs} {E : Entry}
    (hr : r = .fst y ∨ r = .snd y ∨ r = .getl y ∨ r = .getr y) (ht : RhsT Γ F r E Γ1)
    (hf : E.fresh = true) : ∃ Ey, Γ y = some Ey ∧ ProjSrc Ey ∧ Ey.ty.holdsView = false ∧ Ey.held = [] := by
  rcases hr with rfl | rfl | rfl | rfl
  · cases ht with
    | @fst _ Ey _ _ f hy _ _ hff =>
      cases f
      · simp at hf
      · exact ⟨Ey, hy, (hff rfl).1, (hff rfl).2.1, (hff rfl).2.2.1⟩
  · cases ht with
    | @snd _ Ey _ _ f hy _ _ hff =>
      cases f
      · simp at hf
      · exact ⟨Ey, hy, (hff rfl).1, (hff rfl).2.1, (hff rfl).2.2.1⟩
  · cases ht with
    | @getl _ Ey _ _ f hy _ _ hff =>
      cases f
      · simp at hf
      · exact ⟨Ey, hy, (hff rfl).1, (hff rfl).2.1, (hff rfl).2.2.1⟩
  · cases ht with
    | @getr _ Ey _ _ f hy _ _ hff =>
      cases f
      · simp at hf
      · exact ⟨Ey, hy, (hff rfl).1, (hff rfl).2.1, (hff rfl).2.2.1⟩

/-- **A read of anything else is never fresh.** -/
theorem proj_not_src_not_fresh {Γ Γ1 : Ctx} {F : List Var} {y : Var} {r : Rhs} {E Ey : Entry}
    (hr : r = .fst y ∨ r = .snd y ∨ r = .getl y ∨ r = .getr y) (ht : RhsT Γ F r E Γ1)
    (hy : Γ y = some Ey) (hn : ¬ (ProjSrc Ey ∧ Ey.ty.holdsView = false)) : E.fresh = false := by
  cases hE : E.fresh
  · rfl
  · obtain ⟨Ey', hy', hs, hv, _⟩ := proj_fresh_src hr ht hE
    rw [hy] at hy'; cases hy'; exact absurd ⟨hs, hv⟩ hn

/-- **A field read of a borrowed parameter is never fresh** (the
    `at_rootb_not_fresh` analogue; so is `snd`, `getl` and `getr`'s). -/
theorem fst_rootb_not_fresh {Γ Γ1 : Ctx} {F : List Var} {y : Var} {E Ey : Entry}
    (ht : RhsT Γ F (.fst y) E Γ1) (hy : Γ y = some Ey) (hm : Ey.mode = .rootb) : E.fresh = false :=
  proj_not_src_not_fresh (Or.inl rfl) ht hy (by
    rintro ⟨(h | ⟨_, h⟩) | ⟨h, _⟩, _⟩ <;> rw [hm] at h <;> cases h)

/-- **Nor is a read of a borrow that is not fresh or not held-fresh**: a
    projection of a projection that was not fresh is not either. -/
theorem proj_stale_not_fresh {Γ Γ1 : Ctx} {F : List Var} {y : Var} {r : Rhs} {E Ey : Entry}
    (hr : r = .fst y ∨ r = .snd y ∨ r = .getl y ∨ r = .getr y) (ht : RhsT Γ F r E Γ1)
    (hy : Γ y = some Ey) (hm : Ey.mode = .bor) (hf : Ey.fresh = false ∨ Ey.heldFresh = false) :
    E.fresh = false :=
  proj_not_src_not_fresh hr ht hy (by
    rintro ⟨(h | ⟨_, h⟩) | ⟨_, h1, h2⟩, _⟩
    · rw [hm] at h; cases h
    · rw [hm] at h; cases h
    · rcases hf with h | h <;> simp_all)

/-- **A nested projection composes**: a read through a binding that a field
    or payload read made is fresh only when that read was. `. . b x items` is
    fresh exactly where every step is. -/
theorem proj_of_proj_fresh {Γ Γ1 : Ctx} {F : List Var} {y z : Var} {r : Rhs} {E Ez : Entry}
    {t : Ty} {f : Bool} (hr : r = .fst y ∨ r = .snd y ∨ r = .getl y ∨ r = .getr y) (ht : RhsT Γ F r E Γ1)
    (hy : Γ y = some { projE z Ez t with fresh := f, heldFresh := f }) (hE : E.fresh = true) : f = true := by
  obtain ⟨Ey, hy', hs, _, _⟩ := proj_fresh_src hr ht hE
  rw [hy] at hy'; cases hy'
  rcases hs with (h | ⟨_, h⟩) | ⟨_, h, _⟩ <;> cases t <;> simp_all [projE, intE]

/-- **A read of a binding of a type that holds views is never fresh**: such
    a borrow lifts with what the arguments hold. Concretely, a `Bag` that
    holds a slice beside its items. -/
theorem proj_view_not_fresh {Γ Γ1 : Ctx} {F : List Var} {y : Var} {r : Rhs} {E Ey : Entry}
    (hr : r = .fst y ∨ r = .snd y ∨ r = .getl y ∨ r = .getr y) (ht : RhsT Γ F r E Γ1)
    (hy : Γ y = some Ey) (hv : Ey.ty.holdsView = true) : E.fresh = false :=
  proj_not_src_not_fresh hr ht hy (by rintro ⟨_, h⟩; simp_all)

/-- `Bag { ( Vec i ) items ( Slice i ) s }`, inside a `Box`. -/
def bagV : Ty := .prod vi sl
def boxV : Ty := .prod bagV .int

theorem nested_view_not_fresh {Γ1 Γ2 : Ctx} {F : List Var} {y : Var} {Ey E : Entry}
    (hy : Γ1 y = some Ey) (hty : Ey.ty = bagV) (ht : RhsT Γ1 F (.fst y) E Γ2) : E.fresh = false :=
  proj_view_not_fresh (Or.inl rfl) ht hy (by rw [hty]; rfl)

/-- **A fresh payload borrow ends when its enum is given a new value**, and
    the kill does not read the bit: whatever `f` is, a `.replace` of the
    enum's own slot hits the borrow (`hits_fresh_irrel` is the general form). -/
theorem payload_fresh_killed {y : Var} {E : Entry} {a : Ty} (hos : E.mode.ownSlot = true)
    (ha : a ≠ .int) (hv f : Bool) :
    (killE .replace hv y { projE y E a with fresh := f }).live = false := by
  cases a <;> first
    | exact absurd rfl ha
    | (simp only [projE, projDeps, hos, ↓reduceIte]
       simp [killE, hits, Entry.vdeps, Mode.ownSlot, Eff.kills])

end A2.FreshProjWitness
