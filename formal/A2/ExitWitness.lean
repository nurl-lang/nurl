import A2.Soundness

/-!
  A2 — early exits (Agora #871): `break`, `continue` and an early `^`, typed
  with A2's own rules, and run safe and leak-free by the crown theorems.

  nurlc's loops and returns are blocks and exits of the calculus: `while T
  { … }` is `block (loop (…))` and its `break` an `exit` of that block; a
  `while c { … }` with a `continue` is `while c (block (…))` and the
  `continue` an `exit 0` of the round's block; a function whose body has an
  early `^ e` is `block (…)` and the `^ e` an assignment to the result
  followed by an `exit` of it.  The exit is taken from its block in one
  step (`Step.blockExit`), leaving the frames of the scopes between: each
  frame's own end then drops what it owns.

  * `mainB`: a `while T` loop whose round binds an owned `Vec`, left by a
    `break` while the `Vec` is live; a `Vec` bound before the loop is read
    after it.
  * `mainC`: a `while` loop whose round binds an owned `Vec` and is left by
    a `continue` while it is live.
  * `mainR`: a function whose body binds an owned `Vec` and returns early,
    from inside that binding's scope, and a caller.
-/

namespace A2.ExitWitness

/-- A `String` (a `Vec` of bytes). -/
def str : Ty := .vec .int

/-- An owned `String`. -/
def Ew : Entry := ⟨str, .own, true, [], [], false, false, false, false⟩

/-- A context of plain bindings: no borrowed parameter, nothing that runs a
    destructor, nothing that depends on anything. -/
def Plain (Γ : Ctx) : Prop :=
  ∀ v E, Γ v = some E → E.mode ≠ .rootb ∧ E.dtor = false ∧ E.dbind = false ∧ E.vdeps = []

theorem plain_empty : Plain (fun _ => none) := fun _ _ h => by cases h

theorem Plain.setE {Γ : Ctx} (h : Plain Γ) {x : Var} {E : Entry}
    (hE : E.mode ≠ .rootb ∧ E.dtor = false ∧ E.dbind = false ∧ E.vdeps = []) : Plain (A2.setE Γ x E) := by
  intro v E' hv
  simp only [A2.setE, upd] at hv
  split at hv
  · cases hv; exact hE
  · exact h v E' hv

theorem Plain.endOK {Γ : Ctx} (h : Plain Γ) (x : Var) : EndOK Γ x :=
  ⟨fun p E hp hm => absurd hm (h p E hp).1, DtorSafe.of_none (fun v E hv => (h v E hv).2.1) _ _ _,
    DbindSafe.of_none (fun v E hv => (h v E hv).2.2.1) x⟩

theorem Plain.wf {Γ : Ctx} (h : Plain Γ) : CtxWF Γ where
  live v E hv _ _ r hr := by rw [(h v E hv).2.2.2] at hr; cases hr
  dtor v E hv hd _ _ := by rw [(h v E hv).2.2.1] at hd; cases hd
  arm v E hv hd := by rw [(h v E hv).2.1] at hd; cases hd
  view v E hv hd := by rw [(h v E hv).2.2.1] at hd; cases hd

theorem Plain.names {Γ : Ctx} (h : Plain Γ) : NameWF Γ :=
  fun v E hv _ _ d hd => by rw [(h v E hv).2.2.2] at hd; cases hd

theorem ew_plain : Ew.mode ≠ .rootb ∧ Ew.dtor = false ∧ Ew.dbind = false ∧ Ew.vdeps = [] := by
  simp [Ew, Entry.vdeps, Mode.ownSlot]

theorem int_plain : intE.mode ≠ .rootb ∧ intE.dtor = false ∧ intE.dbind = false ∧ intE.vdeps = [] := by
  simp [intE, Entry.vdeps, Mode.ownSlot]

/-- An exit typed from `Γ` with `Γ` its own output: the panic rule's
    premises, which a context meets of itself. -/
theorem exit_typed {P : Prog} {ξ : Exits} {Γ : Ctx} {n : Nat} (hp : Plain Γ) (hx : ξ.up n Γ) :
    StmtT P ξ Γ [] (.exit n) Γ :=
  StmtT.exit hx hp.wf hp.names (fun _ => rfl) (fun _ E h => ⟨E, h, rfl, rfl, fun _ => rfl⟩)
    (DKeep.refl _ _) (DStay.refl _ _) id

/-- A binding's scope ends where the binding was not: `exitScope` of a fresh
    plain binding gives the context back. -/
theorem exitScope_setE_plain {Γ : Ctx} (hp : Plain Γ) {x : Var} (hx : Γ x = none) (E : Entry) :
    exitScope x (A2.setE Γ x E) = Γ := by
  funext v
  by_cases hv : v = x
  · subst hv; simp [exitScope, hx]
  · simp only [exitScope, A2.setE, upd_ne _ _ hv, A2.kill]
    cases h : Γ v with
    | none => rfl
    | some E0 =>
      simp only [Option.map_some, Option.some.injEq]
      exact killE_nohit (by rw [(hp v E0 h).2.2.2]; simp)

/-- No function: the programs are their main statements. -/
def P0 : Prog := []

theorem p0_ok : ProgOK P0 := fun _ h => by cases h
theorem p0_codes : ProgCodes P0 := fun _ h => by cases h

/-! ### `break` out of `while T`

        : String v ( vec_new )
        while T { : String w ( vec_new )  break }
        : i n ( vec_len v )

    `v` is 0, `w` 1, `n` 2. -/

def mainB : Stmt :=
  .letv 0 (.new .int)
    (.seq (.block (.loop (.letv 1 (.new .int) (.exit 0))))
      (.letv 2 (.expr (.len 0)) .skip))

def KB1 : Ctx := A2.setE (fun _ => none) 0 Ew
def KB2 : Ctx := A2.setE KB1 1 Ew

theorem kb1_plain : Plain KB1 := plain_empty.setE ew_plain
theorem kb2_plain : Plain KB2 := kb1_plain.setE ew_plain

theorem kb2_exit : exitScope 1 KB2 = KB1 :=
  exitScope_setE_plain kb1_plain (by simp [KB1, A2.setE, upd]) Ew

/-- The loop's round: `w` bound, then the `break`, an `exit 0` of the block
    around the loop, from inside `w`'s scope: `w`'s scope ends there (its
    end is allowed, `EndOK`), and the context it leaves to is the block's
    end. -/
theorem roundB_typed :
    StmtT P0 ((Exits.none.under 0).blk KB1) KB1 [] (.letv 1 (.new .int) (.exit 0)) KB1 := by
  have he : StmtT P0 (((Exits.none.under 0).blk KB1).under 1) KB2 [] (.exit 0) KB2 :=
    exit_typed kb2_plain (Or.inl ⟨kb2_plain.endOK 1, by
      show exitScope 1 KB2 = KB1 ∨ Weaker (exitScope 1 KB2) KB1
      exact Or.inl kb2_exit⟩)
  have h := StmtT.letv (P := P0) (ξ := ((Exits.none.under 0).blk KB1)) (Γ := KB1) (Γ1 := KB1) (F := [])
    (x := 1) (r := .new .int) (s := .exit 0) (E := Ew) rfl (by simp [KB1, A2.setE, upd]) (by simp)
    (RhsT.new rfl) he (kb2_plain.endOK 1)
  rw [kb2_exit] at h
  exact h

/-- `while T`: the round keeps the loop's context, and the loop is left only
    by the `break`, to the block's end. -/
theorem loopB_typed : StmtT P0 (Exits.none.under 0) KB1 [] (.block (.loop (.letv 1 (.new .int) (.exit 0)))) KB1 :=
  StmtT.block (StmtT.loop rfl roundB_typed kb1_plain.wf kb1_plain.names (fun _ => rfl)
    (fun _ E h => ⟨E, h, rfl, rfl, fun _ => rfl⟩) (DKeep.refl _ _) (DStay.refl _ _) id)

/-- The program: `v` is still live, and read, after the loop. -/
theorem mainB_typed : ∃ Δ, StmtT P0 .none (fun _ => none) [] mainB Δ := by
  have hK3 : Plain (A2.setE KB1 2 intE) := kb1_plain.setE int_plain
  have hn := StmtT.letv (ξ := .none) (P := P0) (Γ := KB1) (F := []) (x := 2) (r := .expr (.len 0))
    (s := .skip) (E := intE) (Γ1 := KB1) rfl (by simp [KB1, A2.setE, upd]) (by simp)
    (RhsT.expr (ExprT.len (E := Ew) (t := .int) (by simp [KB1, A2.setE, upd]) rfl rfl)) StmtT.skip
    (hK3.endOK _)
  have hs : StmtT P0 (Exits.none.under 0) KB1 [] (.seq (.block (.loop (.letv 1 (.new .int) (.exit 0))))
      (.letv 2 (.expr (.len 0)) .skip)) (exitScope 2 (A2.setE KB1 2 intE)) :=
    StmtT.seq rfl loopB_typed hn.ofNone
  rw [exitScope_setE_plain kb1_plain (by simp [KB1, A2.setE, upd]) intE] at hs
  exact ⟨_, StmtT.letv (P := P0) (x := 0) (r := .new .int) (E := Ew) (F := []) (Γ := fun _ => none)
    (Γ1 := fun _ => none) rfl rfl (by simp) (RhsT.new rfl) hs (kb1_plain.endOK 0)⟩

/-- The `break` is a step: from the block around the loop, with the round's
    scope of `w` open, the exit leaves that scope's frame, whose end drops
    `w`. -/
theorem breakB_steps {m : Mem} {k : Stmt} :
    Step P0 m (.block (.seq (.scope 1 (.exit 0)) k)) (.ok m (.scope 1 .skip)) :=
  Step.blockExit (ExitAt.seq (ExitAt.scope ExitAt.exit))

theorem mainB_safe {m' : Mem} {s' : Stmt} (hr : Steps P0 (emptyMem 3) mainB (.ok m' s')) :
    ¬ Stuck P0 m' s' := by
  obtain ⟨Δ, ht⟩ := mainB_typed
  exact memory_safe p0_ok p0_codes ht rfl (by simp [mainB, Stmt.codesOK, Rhs.codeOK]) (by decide) hr

theorem mainB_no_leak {m' : Mem} (hr : Steps P0 (emptyMem 3) mainB (.ok m' .skip)) :
    ∀ i, m'.alloc i = false := by
  obtain ⟨Δ, ht⟩ := mainB_typed
  exact no_leak_end p0_ok p0_codes ht rfl (by simp [mainB, Stmt.codesOK, Rhs.codeOK]) (by decide) hr

/-! ### `continue`

        : i c 1
        while c { : String w ( vec_new )  = c 0  continue }

    `c` is 0, `w` 1; the round is a block, and the `continue` an `exit 0`
    of it. -/

def mainC : Stmt :=
  .letv 0 (.expr (.lit 1))
    (.while (.var 0) (.block (.letv 1 (.new .int) (.seq (.assign 0 (.expr (.lit 0))) (.exit 0)))))

def KC1 : Ctx := A2.setE (fun _ => none) 0 intE
def KC2 : Ctx := A2.setE KC1 1 Ew

theorem kc1_plain : Plain KC1 := plain_empty.setE int_plain
theorem kc2_plain : Plain KC2 := kc1_plain.setE ew_plain

theorem kc2_exit : exitScope 1 KC2 = KC1 :=
  exitScope_setE_plain kc1_plain (by simp [KC1, A2.setE, upd]) Ew

/-- `= c 0`: an integer binding given a new integer. -/
theorem assignC_typed {ξ : Exits} : StmtT P0 ξ KC2 [] (.assign 0 (.expr (.lit 0))) KC2 := by
  have h := StmtT.assign (ξ := ξ) (P := P0) (Γ := KC2) (Γ1 := KC2) (F := []) (x := 0) (r := .expr (.lit 0))
    (Ex := intE) (E := intE) (by simp [KC2, KC1, A2.setE, upd]) (by simp) (Or.inr (Or.inr ⟨rfl, rfl⟩))
    (RhsT.expr ExprT.lit) rfl (by simp [intE, roots, Entry.vdeps, Mode.ownSlot])
    (by simp [KC2, KC1, A2.setE, upd]) (kc2_plain.endOK 0).1 (kc2_plain.endOK 0).2.1 rfl
  have he : A2.setE (A2.kill .replace false 0 KC2) 0 { intE with mode := intE.mode } = KC2 := by
    funext v
    rcases v with _ | _ | v <;>
      simp [KC2, KC1, A2.setE, upd, A2.kill, killE, hits, intE, Ew, Entry.vdeps, Mode.ownSlot]
  rw [he] at h
  exact h

/-- The round: `w` bound, `c` set, then the `continue`, an `exit 0` of the
    round's block from inside `w`'s scope, to the round's end. -/
theorem roundC_typed :
    StmtT P0 (Exits.none.under 0) KC1 [] (.block (.letv 1 (.new .int) (.seq (.assign 0 (.expr (.lit 0))) (.exit 0))))
      KC1 := by
  have he : StmtT P0 (((Exits.none.under 0).blk KC1).under 1) KC2 [] (.exit 0) KC2 :=
    exit_typed kc2_plain (Or.inl ⟨kc2_plain.endOK 1, by
      show exitScope 1 KC2 = KC1 ∨ Weaker (exitScope 1 KC2) KC1
      exact Or.inl kc2_exit⟩)
  have h := StmtT.letv (P := P0) (ξ := ((Exits.none.under 0).blk KC1)) (Γ := KC1) (Γ1 := KC1) (F := [])
    (x := 1) (r := .new .int) (E := Ew) rfl (by simp [KC1, A2.setE, upd]) (by simp)
    (RhsT.new rfl) (StmtT.seq rfl assignC_typed he) (kc2_plain.endOK 1)
  rw [kc2_exit] at h
  exact StmtT.block h

theorem mainC_typed : ∃ Δ, StmtT P0 .none (fun _ => none) [] mainC Δ := by
  have hw : StmtT P0 (Exits.none.under 0) KC1 [] (.while (.var 0)
      (.block (.letv 1 (.new .int) (.seq (.assign 0 (.expr (.lit 0))) (.exit 0))))) KC1 :=
    StmtT.while rfl (ExprT.var (E := intE) (by simp [KC1, A2.setE, upd]) rfl rfl) roundC_typed
  exact ⟨_, StmtT.letv (P := P0) (x := 0) (r := .expr (.lit 1)) (E := intE) (F := []) (Γ := fun _ => none)
    (Γ1 := fun _ => none) rfl rfl (by simp) (RhsT.expr ExprT.lit) hw (kc1_plain.endOK 0)⟩

theorem mainC_safe {m' : Mem} {s' : Stmt} (hr : Steps P0 (emptyMem 2) mainC (.ok m' s')) :
    ¬ Stuck P0 m' s' := by
  obtain ⟨Δ, ht⟩ := mainC_typed
  exact memory_safe p0_ok p0_codes ht rfl (by simp [mainC, Stmt.codesOK, Rhs.codeOK]) (by decide) hr

theorem mainC_no_leak {m' : Mem} (hr : Steps P0 (emptyMem 2) mainC (.ok m' .skip)) :
    ∀ i, m'.alloc i = false := by
  obtain ⟨Δ, ht⟩ := mainC_typed
  exact no_leak_end p0_ok p0_codes ht rfl (by simp [mainC, Stmt.codesOK, Rhs.codeOK]) (by decide) hr

/-! ### An early `^` from inside a scope

        @ g → i { : String w ( vec_new )  ^ 7  … }
        : i r ( g )

    `g`'s body is a block: the `^ 7` sets the result slot (variable 0) and
    takes an `exit 0` of it from inside `w`'s scope (`w` is 1), whose frame's
    end drops `w`.  The caller calls `g`: the call places the body, renamed,
    in the caller's frames (`Rename`), exits and all. -/

def gRBody : Stmt :=
  .block (.letv 1 (.new .int) (.seq (.assign 0 (.expr (.lit 7))) (.exit 0)))

def gR : Fn where
  params   := []
  resTy    := .int
  resOwn   := false
  lends    := []
  rholds   := []
  outHolds := []
  body     := gRBody
  nvars    := 2

def PR : Prog := [gR]

def R0 : Entry := ⟨.int, .bor, false, [], [], false, false, false, false⟩

/-- `g`'s context with the result slot `r0`. -/
def ctxR (r0 : Entry) : Ctx := fun v => if v = 0 then some r0 else none

theorem sigR_eq : sigCtx gR = ctxR R0 := by
  funext v
  simp only [sigCtx, ctxR, gR, resMode]
  rcases v with _ | v <;> simp [R0]

theorem r0_plain : R0.mode ≠ .rootb ∧ R0.dtor = false ∧ R0.dbind = false ∧ R0.vdeps = [] := by
  simp [R0, Entry.vdeps, Mode.ownSlot]

theorem ctxR_plain {r0 : Entry} (h : r0.mode ≠ .rootb ∧ r0.dtor = false ∧ r0.dbind = false ∧ r0.vdeps = []) :
    Plain (ctxR r0) := by
  intro v E hv
  rcases v with _ | v <;> simp [ctxR] at hv
  subst hv; exact h

def KR1 : Ctx := A2.setE (ctxR R0) 1 Ew
def KR2 : Ctx := A2.setE (ctxR intE) 1 Ew

theorem kr1_plain : Plain KR1 := (ctxR_plain r0_plain).setE ew_plain
theorem kr2_plain : Plain KR2 := (ctxR_plain int_plain).setE ew_plain

theorem kr2_exit : exitScope 1 KR2 = ctxR intE :=
  exitScope_setE_plain (ctxR_plain int_plain) (by simp [ctxR]) Ew

/-- `^ 7`'s assignment: the result slot gets its integer. -/
theorem assignR_typed {ξ : Exits} : StmtT PR ξ KR1 [] (.assign 0 (.expr (.lit 7))) KR2 := by
  have h := StmtT.assign (ξ := ξ) (P := PR) (Γ := KR1) (Γ1 := KR1) (F := []) (x := 0) (r := .expr (.lit 7))
    (Ex := R0) (E := intE) (by simp [KR1, ctxR, A2.setE, upd]) (by simp) (Or.inr (Or.inr ⟨rfl, rfl⟩))
    (RhsT.expr ExprT.lit) rfl (by simp [intE, roots, Entry.vdeps, Mode.ownSlot])
    (by simp [KR1, ctxR, A2.setE, upd]) (kr1_plain.endOK 0).1 (kr1_plain.endOK 0).2.1 rfl
  have he : A2.setE (A2.kill .replace false 0 KR1) 0 { intE with mode := R0.mode } = KR2 := by
    funext v
    rcases v with _ | _ | v <;>
      simp [KR1, KR2, ctxR, A2.setE, upd, A2.kill, killE, hits, intE, R0, Ew, Entry.vdeps, Mode.ownSlot]
  rw [he] at h
  exact h

/-- The body: `w` bound, the result set, then the `exit 0` of the body's
    block from inside `w`'s scope, to the block's end, where the result is
    set and `w` gone. -/
theorem bodyR_typed : StmtT PR .none (sigCtx gR) [] gR.body (ctxR intE) := by
  rw [sigR_eq]
  have he : StmtT PR ((Exits.none.blk (ctxR intE)).under 1) KR2 [] (.exit 0) KR2 :=
    exit_typed kr2_plain (Or.inl ⟨kr2_plain.endOK 1, by
      show exitScope 1 KR2 = ctxR intE ∨ Weaker (exitScope 1 KR2) (ctxR intE)
      exact Or.inl kr2_exit⟩)
  have h := StmtT.letv (P := PR) (ξ := Exits.none.blk (ctxR intE)) (Γ := ctxR R0) (Γ1 := ctxR R0) (F := [])
    (x := 1) (r := .new .int) (E := Ew) rfl (by simp [ctxR]) (by simp)
    (RhsT.new rfl) (StmtT.seq rfl assignR_typed he) (kr2_plain.endOK 1)
  rw [kr2_exit] at h
  exact StmtT.block h

/-- `g` meets its summary: it lends and holds nothing, and its result is set
    on its one way out, the early `^`. -/
theorem gR_ok : FnOK PR gR := by
  refine ⟨rfl, by decide, by decide, rfl, by simp [gR], by simp [gR], by simp [gR], by simp [gR], by simp [gR],
    by simp [gR], by simp [gR], dtorParamsOK_of (by simp [gR]) (by simp [gR]), ctxR intE, bodyR_typed,
    fun v E hE => ?_, ⟨intE, by simp [ctxR, gR], rfl, rfl, rfl, by simp [intE], by simp [intE], by simp [gR]⟩,
    fun i hi => by simp [gR] at hi⟩
  rcases v with _ | v <;> simp [ctxR] at hE
  subst hE; exact ⟨rfl, rfl⟩

theorem pR_ok : ProgOK PR := by
  intro fn hfn
  simp only [PR, List.mem_cons, List.mem_nil_iff, or_false] at hfn
  subst hfn; exact gR_ok

theorem pR_codes : ProgCodes PR := by
  intro fn hfn
  simp only [PR, List.mem_cons, List.mem_nil_iff, or_false] at hfn
  subst hfn; simp [gR, gRBody, Stmt.codesOK, Rhs.codeOK]

theorem gR_not_thru : ¬ ThruFn PR 0 := by
  intro h
  cases h with
  | here hf hb => simp [PR] at hf; subst hf; simp [gR, gRBody, Stmt.hasThru] at hb
  | call hf hg _ => simp [PR] at hf; subst hf; simp [gR, gRBody, Stmt.calls] at hg

theorem callResR_eq : callRes (fun _ => none) gR [] = intE := by
  simp [callRes, gR, heldOfArgs, allKinds, roots, memDeps, argNames, nameDeps, Entry.vdeps, Mode.ownSlot,
    ownHeld, resMode, intE]

theorem callPostR_eq : callPost (fun _ => none) gR [] = fun _ => none := by
  funext v
  simp [callPost, callPostAux, gR, killNames, mutNames, argNames]

theorem callR_ok : CallT PR (fun _ => none) [] 0 [] intE (fun _ => none) :=
  ⟨gR, rfl, rfl, fun i hi => by simp [gR] at hi, fun d hd => by simp [mutNames, argNames] at hd,
    CallDtorSafe.of_none (fun v E hE => by cases hE) _ _, callResR_eq.symm, callPostR_eq.symm,
    fun h => absurd h gR_not_thru⟩

/-- The caller: `: i r ( g )`, `r` is 0. -/
def mainR : Stmt := .letcall 0 0 [] .skip

theorem mainR_typed : ∃ Δ, StmtT PR .none (fun _ => none) [] mainR Δ :=
  ⟨_, StmtT.letcall (P := PR) (Γ := fun _ => none) (F := []) (x := 0) (f := 0) (args := []) (s := .skip)
    (E := intE) (Γ1 := fun _ => none) rfl rfl (by simp) callR_ok StmtT.skip
    ((plain_empty.setE int_plain).endOK 0) (fun fn hf ho _ => by simp [PR] at hf; subst hf; simp [gR] at ho)⟩

/-- The early `^` is a step of the callee's block: the exit leaves `w`'s
    frame, whose end drops `w`. -/
theorem returnR_steps {m : Mem} {k : Stmt} :
    Step PR m (.block (.scope 1 (.seq (.exit 0) k))) (.ok m (.scope 1 .skip)) :=
  Step.blockExit (ExitAt.scope (ExitAt.seq ExitAt.exit))

theorem mainR_safe {m' : Mem} {s' : Stmt} (hr : Steps PR (emptyMem 1) mainR (.ok m' s')) :
    ¬ Stuck PR m' s' := by
  obtain ⟨Δ, ht⟩ := mainR_typed
  exact memory_safe pR_ok pR_codes ht rfl (by simp [mainR, Stmt.codesOK]) (by decide) hr

theorem mainR_no_leak {m' : Mem} (hr : Steps PR (emptyMem 1) mainR (.ok m' .skip)) :
    ∀ i, m'.alloc i = false := by
  obtain ⟨Δ, ht⟩ := mainR_typed
  exact no_leak_end pR_ok pR_codes ht rfl (by simp [mainR, Stmt.codesOK]) (by decide) hr

end A2.ExitWitness
