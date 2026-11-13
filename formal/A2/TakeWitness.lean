import A2.Soundness

/-!
  A2 — a take out of an `inout .replace` place (Agora #826).

      @ g inout(replace) String p → i { : q (take p)  ^ 0 }
      : String w ( vec_new )  : i r ( g w )  : i n ( vec_len w )

  nurlc lets a callee hand its `inout` parameter of a handle type on, by
  name (`( eat p )`, Agora #776): the caller's slot is emptied to the type's
  empty value, the caller reads its argument after the call (`vec_len w`
  reads 0), and the callee is summarised as replacing the parameter, so the
  caller's borrows of it end at the call.  The calculus has the step: `take
  p` (`RhsT.take`, `EvalR.take`) moves `p`'s `Vec` out to an owned binding
  and leaves a fresh empty `Vec` in `p`'s place, which stays live.  Here `q`
  is that binding, dropped where its scope ends.

  This module types the callee and the caller with A2's own rules, and
  applies `memory_safe` and `no_leak_end` to the caller: the moved `Vec` is
  freed with `q`, the fresh empty one with `w`.
-/

namespace A2.TakeWitness

/-- A `String` (a `Vec` of bytes). -/
def str : Ty := .vec .int

/-- `g p`: the parameter `p` (`inout .replace`) is variable 0, the result
    slot 1, the binding `q` 2.

        : q (take p)  = r 0 -/
def gBody : Stmt :=
  .seq (.letv 2 (.take 0) .skip) (.assign 1 (.expr (.lit 0)))

def g : Fn where
  params   := [(.inout .replace, str)]
  resTy    := .int
  resOwn   := false
  lends    := []
  rholds   := []
  outHolds := []
  body     := gBody
  nvars    := 3

def P : Prog := [g]

/-! ### The callee -/

def Ep : Entry := ⟨str, .inout .replace, true, [], [], false, false⟩
def Eq : Entry := ⟨str, .own, true, [], [], false, false⟩
def R0 : Entry := ⟨.int, .bor, false, [], [], false, false⟩

/-- The callee's context with the result slot `r1`. -/
def ctx (r1 : Entry) : Ctx := fun v =>
  if v = 0 then some Ep else if v = 1 then some r1 else none

theorem sig_eq : sigCtx g = ctx R0 := by
  funext v
  simp only [sigCtx, ctx, g, paramE, resMode]
  rcases v with _ | _ | v <;> simp [Ep, R0, str, Ty.hasFn]

/-- No borrowed parameter, and no binding that runs a destructor. -/
theorem ctx_noPin {R : Entry} (hR : R.mode ≠ .rootb) (x : Var) : NoPin (ctx R) x := by
  intro p E hp hm d hd _
  rcases p with _ | _ | p <;> simp [ctx] at hp <;> subst hp
  · simp [Entry.vdeps, Ep, Mode.ownSlot] at hd
  · exact absurd hm hR

theorem ctx_dtor {R : Entry} (hR : R.dtor = false) : ∀ v E, ctx R v = some E → E.dtor = false := by
  intro v E hE
  rcases v with _ | _ | v <;> simp [ctx] at hE <;> subst hE <;> first | rfl | exact hR

/-- `: q (take p)`: `p`'s String moves to `q`; `p` keeps a fresh empty one,
    and its entry is as it was. -/
theorem take_typed : RhsT (ctx R0) [] (.take 0) Eq (ctx R0) := by
  have h := RhsT.take (Γ := ctx R0) (F := []) (y := 0) (E := Ep) (t := .int) (by simp [ctx]) rfl rfl rfl
    (Or.inr ⟨.replace, rfl, by simp [Eff.le]⟩) rfl (by simp) (ctx_noPin (by simp [R0]) _)
    (DtorSafe.of_none (ctx_dtor rfl) _ _ _)
  have he : setE (kill .replace false 0 (ctx R0)) 0 ⟨Ep.ty, Ep.mode, true, [], [], false, false⟩ = ctx R0 := by
    funext v
    rcases v with _ | _ | v <;> simp [ctx, setE, upd, kill, killE, hits, Ep, R0, Entry.vdeps, Mode.ownSlot]
  rw [he] at h
  exact h

/-- `q`'s scope: it ends, and its String is dropped. -/
theorem letq_typed : StmtT P (ctx R0) [] (.letv 2 (.take 0) .skip) (ctx R0) := by
  have hl := StmtT.letv (P := P) (Γ := ctx R0) (F := []) (x := 2) (r := .take 0) (s := .skip) (E := Eq)
    (Γ1 := ctx R0) rfl (by simp [ctx]) (by simp) take_typed StmtT.skip
    ⟨fun p E hp hm => by
        by_cases h2 : p = 2
        · subst h2; simp [setE, upd] at hp; subst hp; simp [Eq] at hm
        · simp only [setE, upd_ne _ _ h2] at hp; exact ctx_noPin (by simp [R0]) 2 p E hp hm,
      DtorSafe.of_none (fun v E hE => by
        by_cases h2 : v = 2
        · subst h2; simp [setE, upd] at hE; subst hE; rfl
        · simp only [setE, upd_ne _ _ h2] at hE; exact ctx_dtor rfl v E hE) _ _ _,
      DbindSafe.of_none (fun v E hE => by
        by_cases h2 : v = 2
        · subst h2; simp [setE, upd] at hE; subst hE; rfl
        · simp only [setE, upd_ne _ _ h2] at hE
          rcases v with _ | _ | v <;> simp [ctx] at hE <;> subst hE <;> rfl) _⟩
  have he : exitScope 2 (setE (ctx R0) 2 Eq) = ctx R0 := by
    funext v
    rcases v with _ | _ | _ | v <;>
      simp [exitScope, ctx, setE, upd, kill, killE, hits, Ep, R0, Entry.vdeps, Mode.ownSlot]
  rw [he] at hl; exact hl

/-- The body: the take, then the answer. -/
theorem body_typed : StmtT P (sigCtx g) [] g.body (ctx intE) := by
  rw [sig_eq]
  have ha := StmtT.assign (P := P) (Γ := ctx R0) (F := []) (x := 1) (r := .expr (.lit 0)) (Ex := R0)
    (E := intE) (Γ1 := ctx R0) (by simp [ctx]) (by simp) (Or.inr (Or.inr ⟨rfl, rfl⟩))
    (RhsT.expr ExprT.lit) rfl (by simp [intE, roots, Entry.vdeps, Mode.ownSlot]) (by simp [ctx])
    (ctx_noPin (by simp [R0]) _) (DtorSafe.of_none (ctx_dtor rfl) _ _ _) rfl
  have he : setE (kill .replace false 1 (ctx R0)) 1 { intE with mode := R0.mode } = ctx intE := by
    funext v
    rcases v with _ | _ | v <;> simp [ctx, setE, upd, kill, killE, hits, Ep, R0, intE, Entry.vdeps, Mode.ownSlot]
  rw [he] at ha
  exact StmtT.seq rfl letq_typed ha

/-- `g` meets its summary: it lends nothing and replaces its parameter,
    which ends live and holding nothing. -/
theorem g_ok : FnOK P g := by
  refine ⟨rfl, by decide, by decide, rfl, by simp [g], ?_, by simp [g], by simp [g], by simp [g], by simp [g],
    by simp [g], dtorParamsOK_of (by simp [g] <;> decide) (by simp [g]), ctx intE, body_typed,
    fun v E hE => ?_, ⟨intE, by simp [ctx, g], rfl, rfl, rfl, by simp [intE], by simp [intE], by simp [g]⟩, ?_⟩
  · intro pt hpt
    simp only [g, List.mem_cons, List.mem_nil_iff, or_false] at hpt
    subst hpt; simp [str, Ty.ok, Ty.owning]
  · rcases v with _ | _ | v <;> simp [ctx] at hE <;> subst hE <;> exact ⟨rfl, rfl⟩
  · intro i hi b hb
    rcases i with _ | i
    · exact ⟨Ep, by simp [ctx], rfl, by simp [Ep], by simp [Ep]⟩
    · simp [g] at hi

theorem prog_ok : ProgOK P := by
  intro fn hfn
  simp only [P, List.mem_cons, List.mem_nil_iff, or_false] at hfn
  subst hfn; exact g_ok

theorem prog_codes : ProgCodes P := by
  intro fn hfn
  simp only [P, List.mem_cons, List.mem_nil_iff, or_false] at hfn
  subst hfn; simp [g, gBody, Stmt.codesOK, Rhs.codeOK]

/-! ### The caller

        : String w ( vec_new )  : i r ( g w )  : i n ( vec_len w )

    `w` is handed `inout`; after the call it holds the empty String `g` left
    in its place, which its scope drops. -/

/-- The caller: `w` is 0, `r` 1, `n` 2. -/
def main : Stmt :=
  .letv 0 (.new .int) (.letcall 1 0 [0] (.letv 2 (.expr (.len 0)) .skip))

def Ew : Entry := ⟨str, .own, true, [], [], false, false⟩

/-- The caller's context at the call. -/
def K1 : Ctx := setE (fun _ => none) 0 Ew

/-- A context with no borrowed parameter and no binding that runs a
    destructor. -/
def NoRootb (Γ : Ctx) : Prop := ∀ v E, Γ v = some E → E.mode ≠ .rootb ∧ E.dtor = false ∧ E.dbind = false

theorem NoRootb.endOK {Γ : Ctx} (h : NoRootb Γ) (x : Var) : EndOK Γ x :=
  ⟨fun p E hp hm => absurd hm (h p E hp).1, DtorSafe.of_none (fun v E hv => (h v E hv).2.1) _ _ _,
    DbindSafe.of_none (fun v E hv => (h v E hv).2.2) x⟩

theorem NoRootb.setE {Γ : Ctx} (h : NoRootb Γ) {x : Var} {E : Entry}
    (hE : E.mode ≠ .rootb ∧ E.dtor = false ∧ E.dbind = false) : NoRootb (A2.setE Γ x E) := by
  intro v E' hv
  simp only [A2.setE, upd] at hv
  split at hv
  · cases hv; exact hE
  · exact h v E' hv

theorem NoRootb.exitScope {Γ : Ctx} (h : NoRootb Γ) (x : Var) : NoRootb (A2.exitScope x Γ) := by
  intro v E' h'
  simp only [A2.exitScope, upd] at h'
  split at h'
  · cases h'
  · simp only [A2.kill] at h'
    cases hg : Γ v with
    | none => rw [hg] at h'; cases h'
    | some E =>
      rw [hg] at h'; simp only [Option.map_some, Option.some.injEq] at h'; subst h'
      rw [killE_mode, killE_dtor, killE_dbind]; exact h v E hg

theorem noRootb_empty : NoRootb (fun _ => none) := fun _ _ h => by cases h

theorem K1_noRootb : NoRootb K1 := noRootb_empty.setE (by simp [Ew])

theorem callRes_eq : callRes K1 g [0] = intE := by
  simp [callRes, g, argE, K1, A2.setE, upd, heldOfArgs, allKinds, roots, memDeps, argNames,
    nameDeps, Entry.vdeps, Mode.ownSlot, ownHeld, resMode, intE, Ew, str]

theorem callPost_eq : callPost K1 g [0] = K1 := by
  funext v
  simp only [callPost, callPostAux, g, killNames, mutNames, argNames]
  rcases v with _ | v <;>
    simp [argE, K1, A2.setE, upd, A2.kill, Ew, Entry.vdeps, Mode.ownSlot, str, Ty.holdsView, Ty.elem, nameDeps]

/-- `g` changes no elements through a borrow and calls nothing. -/
theorem g_not_thru : ¬ ThruFn P 0 := by
  intro h
  cases h with
  | here hf hb => simp [P] at hf; subst hf; simp [g, gBody, Stmt.hasThru] at hb
  | call hf hg _ => simp [P] at hf; subst hf; simp [g, gBody, Stmt.calls] at hg

/-- The call: `w` is handed `inout`, which `g` may replace. -/
theorem call_ok : CallT P K1 [] 0 [0] intE K1 := by
  refine ⟨g, rfl, rfl, ?_, ?_, CallDtorSafe.of_none (fun v E hE => by
      rcases v with _ | v <;> simp [K1, A2.setE, upd] at hE <;> subst hE <;> exact ⟨rfl, rfl⟩) _ _,
    callRes_eq.symm, callPost_eq.symm, fun h => absurd h g_not_thru⟩
  · intro i hi
    rcases i with _ | i
    · refine ⟨Ew, by simp [K1, A2.setE, upd], rfl, ⟨rfl, Or.inl rfl, rfl⟩, fun _ => ?_,
        fun _ => fun p E hp hm => absurd hm (K1_noRootb p E hp).1⟩
      refine ⟨by simp, by simp [Ew, roots, memDeps, Entry.vdeps, Mode.ownSlot], (fun h => by cases h),
        (fun _ _ d hd => by simp [Ew, Entry.vdeps, Mode.ownSlot] at hd), fun j hj hji => ?_⟩
      rcases j with _ | j
      · exact absurd rfl hji
      · simp [g] at hj
    · simp [g] at hi
  · intro d hd
    simp [mutNames, argNames, argE, K1, A2.setE, upd, Ew, nameDeps, Entry.vdeps, Mode.ownSlot, str] at hd

/-- The caller is well-typed from the empty context. -/
theorem main_typed : ∃ Δ, StmtT P (fun _ => none) [] main Δ := by
  have hK2 : NoRootb (A2.setE K1 1 intE) := K1_noRootb.setE (by simp [intE])
  have hK3 : NoRootb (A2.setE (A2.setE K1 1 intE) 2 intE) := hK2.setE (by simp [intE])
  -- `: i n ( vec_len w )`: `w` is live after the call
  have hn := StmtT.letv (P := P) (Γ := A2.setE K1 1 intE) (F := []) (x := 2) (r := .expr (.len 0))
    (s := .skip) (E := intE) (Γ1 := A2.setE K1 1 intE) rfl (by simp [K1, A2.setE, upd]) (by simp)
    (RhsT.expr (ExprT.len (E := Ew) (t := .int) (by simp [K1, A2.setE, upd]) rfl rfl)) StmtT.skip
    (hK3.endOK _)
  have hc := StmtT.letcall (P := P) (Γ := K1) (F := []) (x := 1) (f := 0) (args := [0])
    (s := .letv 2 (.expr (.len 0)) .skip) (E := intE) (Γ1 := K1) rfl (by simp [K1, A2.setE, upd])
    (by simp) call_ok hn ((hK3.exitScope 2).endOK _)
    (fun fn hf ho _ => by simp [P] at hf; subst hf; simp [g] at ho)
  exact ⟨_, StmtT.letv (P := P) (x := 0) (r := .new .int) (E := Ew) (F := []) (Γ := fun _ => none)
    (Γ1 := fun _ => none) rfl rfl (by simp) (RhsT.new rfl) hc
    (((hK3.exitScope 2).exitScope 1).endOK _)⟩

/-- A run of the caller, from the empty store, never touches memory it may
    not: `vec_len w` reads the empty String the take left. -/
theorem main_safe {m' : Mem} {s' : Stmt} (hr : Steps P (emptyMem 3) main (.ok m' s')) :
    ¬ Stuck P m' s' := by
  obtain ⟨Δ, ht⟩ := main_typed
  exact memory_safe prog_ok prog_codes ht rfl (by simp [main, Stmt.codesOK, Rhs.codeOK])
    (by decide) hr

/-- ... and when it ends, both Strings are freed: the one `g` took, with
    `q`, and the empty one it left, with `w`. -/
theorem main_no_leak {m' : Mem} (hr : Steps P (emptyMem 3) main (.ok m' .skip)) :
    ∀ i, m'.alloc i = false := by
  obtain ⟨Δ, ht⟩ := main_typed
  exact no_leak_end prog_ok prog_codes ht rfl (by simp [main, Stmt.codesOK, Rhs.codeOK])
    (by decide) hr

end A2.TakeWitness
