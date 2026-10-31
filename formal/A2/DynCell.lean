import A2.Soundness

/-!
  A2 — a value owned or not per call, as the calculus has it
  (`A2/DYN_DESIGN.md`).

      @ pick String p b c → String { ^ ? c p ( mk ) }

  nurlc returns `pick`'s result with an ownership bit (per call: the fresh
  String is the caller's to drop, `p` is not).  The calculus has no such
  bit, and needs none: the fresh value goes into an *owner cell* the caller
  provides — an `inout` option, `none` until the callee fills it — and the
  result is a borrow, of the cell's payload or of `p`.  The summary lends
  both.  The bit is "is the cell `some`?", the caller's scope drops the
  cell, and a consumer that takes the value when it is fresh takes the
  cell's payload.

  This module types the encoding, callee and caller, with A2's own rules,
  and applies `memory_safe` and `no_leak_end` to it: per-call ownership is
  inside what the theorems cover, once nurlc's lowering is read as this
  encoding (phase C / D).
-/

namespace A2.DynCell

/-- A `String` (a `Vec` of bytes) and an optional one (`inl` is `none`). -/
def str : Ty := .vec .int
def opt : Ty := .sum .int str

/-- `pick cell p c`: the cell (`inout`, may be replaced) is variable 0, `p`
    is 1, the flag `c` is 2, the result slot is 3, and the fresh String is
    the local 4.

        ? c { = r p } { : y ( mk )  = cell ( some y )  = r ( payload cell ) } -/
def pickBody : Stmt :=
  .ite (.var 2)
    (.assign 3 (.var 1))
    (.letv 4 (.new .int) (.seq (.assign 0 (.inr .int 4)) (.assign 3 (.getr 0))))

def pick : Fn where
  params   := [(.inout .replace, opt), (.inp, str), (.inp, .int)]
  resTy    := str
  resOwn   := false
  lends    := [(1, .self), (0, .inner)]
  rholds   := []
  outHolds := []
  body     := pickBody
  nvars    := 5

def P : Prog := [pick]

/-! ### The callee's contexts -/

def Ecell : Entry := ⟨opt, .inout .replace, true, [], [], false, false⟩
def Ep : Entry := ⟨str, .rootb, true, [], [], false, false⟩
def Ec : Entry := ⟨.int, .rootb, true, [], [], false, false⟩
def Enew : Entry := ⟨str, .own, true, [], [], false, false⟩

/-- What the result slot ends as on each path, and at the join. -/
def ErT : Entry := ⟨str, .bor, true, [⟨1, .self⟩], [], false, false⟩
def ErF : Entry := ⟨str, .bor, true, [⟨0, .inner⟩], [], false, false⟩
def ErJ : Entry := ⟨str, .bor, true, [⟨1, .self⟩, ⟨0, .inner⟩], [], false, false⟩

/-- The callee's context with the result slot `r3`. -/
def ctx (r3 : Entry) : Ctx := fun v =>
  if v = 0 then some Ecell else if v = 1 then some Ep else if v = 2 then some Ec
  else if v = 3 then some r3 else none

theorem sig_eq : sigCtx pick = ctx ⟨str, .bor, false, [], [], false, false⟩ := by
  funext v
  simp only [sigCtx, ctx, pick, paramE, resMode]
  rcases v with _ | _ | _ | _ | v <;> simp [Ecell, Ep, Ec, opt, str, Ty.hasFn]

/-- Every root a result slot's entry names is the cell or `p`, and it names
    nothing by name. -/
def RootsOK (R : Entry) : Prop :=
  (∀ r ∈ roots R.vdeps, r = 0 ∨ r = 1) ∧ ∀ d ∈ R.vdeps, d.kind.isName = false

/-- No binding of the example runs a destructor (A2-drop.2). -/
theorem ctx_flags {R : Entry} (hR : R.dtor = false ∧ R.dbind = false) :
    ∀ v E, ctx R v = some E → E.dtor = false ∧ E.dbind = false := by
  intro v E hE
  rcases v with _ | _ | _ | _ | v <;> simp [ctx] at hE <;> subst hE <;> first | exact ⟨rfl, rfl⟩ | exact hR

theorem ctx_wf {R : Entry} (hR : RootsOK R) (hRf : R.dtor = false ∧ R.dbind = false) : CtxWF (ctx R) := by
  refine ⟨fun v E hv _ _ r hr => ?_, fun v E hv hd => absurd hd (by rw [(ctx_flags hRf v E hv).2]; simp),
    fun v E hv ha => absurd ha (by rw [(ctx_flags hRf v E hv).1]; simp),
    fun v E hv hd => absurd hd (by rw [(ctx_flags hRf v E hv).2]; simp)⟩
  simp only [ctx] at hv
  split at hv
  · cases hv; simp [roots, Entry.vdeps, Ecell, Mode.ownSlot] at hr
  split at hv
  · cases hv; simp [roots, Entry.vdeps, Ep, Mode.ownSlot] at hr
  split at hv
  · cases hv; simp [roots, Entry.vdeps, Ec, Mode.ownSlot] at hr
  split at hv
  · cases hv
    rcases hR.1 r hr with rfl | rfl
    · exact ⟨Ecell, by simp [ctx], rfl⟩
    · exact ⟨Ep, by simp [ctx], rfl⟩
  · cases hv

theorem ctx_names {R : Entry} (hR : RootsOK R) : NameWF (ctx R) := by
  intro v E hv _ _ d hd b t hk
  simp only [ctx] at hv
  split at hv
  · cases hv; simp [Entry.vdeps, Ecell, Mode.ownSlot] at hd
  split at hv
  · cases hv; simp [Entry.vdeps, Ep, Mode.ownSlot] at hd
  split at hv
  · cases hv; simp [Entry.vdeps, Ec, Mode.ownSlot] at hd
  split at hv
  · cases hv; have := hR.2 d hd; rw [hk] at this; cases this
  · cases hv

/-- A result slot that may lend more is weaker: the join of the two paths. -/
theorem ctx_weaker {R R' : Entry} (hR' : RootsOK R') (ht : R'.ty = R.ty) (hm : R'.mode = R.mode)
    (hb : R.mode = .bor) (hl : R'.live = true → R.live = true)
    (hp : R.path ⊆ R'.path) (hh : R.held ⊆ R'.held) (hf : R.dtor = false ∧ R.dbind = false)
    (hf' : R'.dtor = false ∧ R'.dbind = false) :
    Weaker (ctx R) (ctx R') := by
  refine ⟨fun v => ⟨?_, ?_⟩, ctx_wf hR' hf', ctx_names hR'⟩
  · rcases v with _ | _ | _ | _ | v <;> simp [ctx]
  · intro E E' h h'
    rcases v with _ | _ | _ | _ | v <;> simp [ctx] at h h' <;> subst h <;> subst h'
    · exact EntryWeaker.refl _
    · exact EntryWeaker.refl _
    · exact EntryWeaker.refl _
    · refine ⟨ht, hm, fun hf0 => ?_, fun hl' => ⟨hl hl', fun _ => hp, hh⟩,
        fun h => absurd h (by rw [hf.1]; simp), by rw [hf.2, hf'.2], fun h => absurd h (by rw [hf'.1]; simp),
        fun h => absurd h (by rw [hf.2]; simp)⟩
      simp [Entry.fixed, hb] at hf0

theorem roots_R0 : RootsOK ⟨str, .bor, false, [], [], false, false⟩ := by
  constructor <;> simp [roots, Entry.vdeps, Mode.ownSlot]
theorem roots_ErT : RootsOK ErT := by
  constructor <;> simp [ErT, roots, Entry.vdeps, Mode.ownSlot, Kind.isName]
theorem roots_ErF : RootsOK ErF := by
  constructor <;> simp [ErF, roots, Entry.vdeps, Mode.ownSlot, Kind.isName]
theorem roots_ErJ : RootsOK ErJ := by
  constructor <;> simp [ErJ, roots, Entry.vdeps, Mode.ownSlot, Kind.isName]

/-- No borrowed parameter of `ctx R` holds a closure, so nothing is pinned. -/
theorem ctx_noPin {R : Entry} (hR : R.mode ≠ .rootb) (x : Var) : NoPin (ctx R) x := by
  intro p E hp hm d hd _
  rcases p with _ | _ | _ | _ | p <;> simp [ctx] at hp <;> subst hp
  · simp [Entry.vdeps, Ecell, Mode.ownSlot] at hd
  · simp [Entry.vdeps, Ep, Mode.ownSlot] at hd
  · simp [Entry.vdeps, Ec, Mode.ownSlot] at hd
  · exact absurd hm hR

/-! ### The callee: both paths, and the join -/

/-- The path that lends `p`. -/
theorem then_arm : StmtT P (ctx ⟨str, .bor, false, [], [], false, false⟩) [] (.assign 3 (.var 1)) (ctx ErT) := by
  have h := StmtT.assign (P := P) (Γ := ctx ⟨str, .bor, false, [], [], false, false⟩) (F := []) (x := 3)
    (r := .var 1) (Ex := ⟨str, .bor, false, [], [], false, false⟩)
    (E := ⟨str, .bor, true, derive 1 Ep .self, Ep.held, false, false⟩) (Γ1 := ctx ⟨str, .bor, false, [], [], false, false⟩)
    (by simp [ctx]) (by simp) (Or.inr (Or.inr ⟨rfl, rfl⟩))
    (RhsT.copyRoot (E := Ep) (by simp [ctx]) rfl rfl) rfl
    (by simp [derive, Ep, roots, Entry.vdeps, Mode.isRoot, Mode.ownSlot, rootKind, str])
    (by simp [ctx]) (ctx_noPin (by simp) _)
    (DtorSafe.of_none (fun v E h => (ctx_flags ⟨rfl, rfl⟩ v E h).1) _ _ _) rfl
  have he : setE (kill .replace false 3 (ctx ⟨str, .bor, false, [], [], false, false⟩)) 3
      { (⟨str, .bor, true, derive 1 Ep .self, Ep.held, false, false⟩ : Entry) with mode := Mode.bor } = ctx ErT := by
    funext v
    rcases v with _ | _ | _ | _ | v <;>
      simp [ctx, setE, upd, kill, killE, hits, Ecell, Ep, Ec, ErT, derive, Mode.isRoot, rootKind, str,
        Entry.vdeps, Mode.ownSlot]
  rw [he] at h; exact h

/-- The fresh-value path's contexts: the callee's, with the local 4. -/
def ctxL (R L : Entry) : Ctx := setE (ctx R) 4 L

def EnewD : Entry := ⟨str, .own, false, [], [], false, false⟩

theorem ctxL_noPin {R L : Entry} (hR : R.mode ≠ .rootb) (hL : L.mode ≠ .rootb) (x : Var) :
    NoPin (ctxL R L) x := by
  intro p E hp hm d hd _
  rcases p with _ | _ | _ | _ | _ | p <;> simp [ctxL, ctx, setE, upd] at hp <;> subst hp
  · simp [Entry.vdeps, Ecell, Mode.ownSlot] at hd
  · simp [Entry.vdeps, Ep, Mode.ownSlot] at hd
  · simp [Entry.vdeps, Ec, Mode.ownSlot] at hd
  · exact absurd hm hR
  · exact absurd hm hL

/-- No binding of the example runs a destructor (A2-drop.2). -/
theorem ctx_dtor {R : Entry} (hR : R.dtor = false) : ∀ v E, ctx R v = some E → E.dtor = false := by
  intro v E hE
  rcases v with _ | _ | _ | _ | v <;> simp [ctx] at hE <;> subst hE <;> first | rfl | exact hR

theorem ctxL_dtor {R L : Entry} (hR : R.dtor = false) (hL : L.dtor = false) :
    ∀ v E, ctxL R L v = some E → E.dtor = false := by
  intro v E hE
  by_cases h4 : v = 4
  · subst h4; simp [ctxL, setE, upd] at hE; subst hE; exact hL
  · simp only [ctxL, setE, upd_ne _ _ h4] at hE; exact ctx_dtor hR v E hE

/-- The path that makes a fresh String: it goes into the cell, and the
    result borrows the cell's payload. -/
theorem else_arm : StmtT P (ctx ⟨str, .bor, false, [], [], false, false⟩) []
    (.letv 4 (.new .int) (.seq (.assign 0 (.inr .int 4)) (.assign 3 (.getr 0)))) (ctx ErF) := by
  let R0 : Entry := ⟨str, .bor, false, [], [], false, false⟩
  -- `= cell ( some y )`: the fresh String moves into the cell
  have hpush : PushArg (ctxL R0 Enew) [] 4 Enew Enew.ty Enew.held
      (setE (kill .replace false 4 (ctxL R0 Enew)) 4 { Enew with live := false, dtor := false }) :=
    PushArg.move (by simp [Enew, str, Ty.owning]) rfl (by simp) (ctxL_noPin (by simp [R0]) (by simp [Enew]) _)
      (DtorSafe.of_none (ctxL_dtor rfl rfl) _ _ _)
  have h1 : setE (kill .replace false 4 (ctxL R0 Enew)) 4 { Enew with live := false, dtor := false } = ctxL R0 EnewD := by
    funext v
    rcases v with _ | _ | _ | _ | _ | v <;>
      simp [ctxL, ctx, setE, upd, kill, killE, hits, Ecell, Ep, Ec, Enew, EnewD, R0, Entry.vdeps, Mode.ownSlot]
  rw [h1] at hpush
  have hinr : RhsT (ctxL R0 Enew) [] (.inr .int 4) ⟨.sum .int Enew.ty, .own, true, [], Enew.held, false, false⟩
      (ctxL R0 EnewD) :=
    RhsT.inr (by simp [ctxL, setE, upd]) rfl hpush rfl
  have ha := StmtT.assign (P := P) (Γ := ctxL R0 Enew) (F := []) (x := 0) (r := .inr .int 4)
    (Ex := Ecell) (E := ⟨.sum .int Enew.ty, .own, true, [], Enew.held, false, false⟩) (Γ1 := ctxL R0 EnewD)
    (by simp [ctxL, ctx, setE, upd]) (by simp) (Or.inr (Or.inl ⟨rfl, rfl⟩)) hinr
    (by simp [Enew, Ecell, opt, str]) (by simp [Enew, roots, Entry.vdeps, Mode.ownSlot])
    (by simp [ctxL, ctx, setE, upd]) (ctxL_noPin (by simp [R0]) (by simp [Enew]) _)
    (DtorSafe.of_none (ctxL_dtor rfl rfl) _ _ _) rfl
  have h2 : setE (kill .replace false 0 (ctxL R0 EnewD)) 0
      { (⟨.sum .int Enew.ty, .own, true, [], Enew.held, false, false⟩ : Entry) with mode := Ecell.mode } = ctxL R0 EnewD := by
    funext v
    rcases v with _ | _ | _ | _ | _ | v <;>
      simp [ctxL, ctx, setE, upd, kill, killE, hits, Ecell, Ep, Ec, Enew, EnewD, R0, opt, str, Entry.vdeps,
        Mode.ownSlot]
  rw [h2] at ha
  -- `= r ( payload cell )`: the result borrows what the cell holds
  have hb := StmtT.assign (P := P) (Γ := ctxL R0 EnewD) (F := []) (x := 3) (r := .getr 0)
    (Ex := R0) (E := projE 0 Ecell str) (Γ1 := ctxL R0 EnewD)
    (by simp [ctxL, ctx, setE, upd, R0]) (by simp) (Or.inr (Or.inr ⟨rfl, rfl⟩))
    (RhsT.getr (E := Ecell) (a := .int) (b := str) (by simp [ctxL, ctx, setE, upd]) rfl rfl) rfl
    (by simp [projE, projDeps, Ecell, str, roots, Entry.vdeps, Mode.ownSlot])
    (by simp [ctxL, ctx, setE, upd]) (ctxL_noPin (by simp [R0]) (by simp [EnewD]) _)
    (DtorSafe.of_none (ctxL_dtor rfl rfl) _ _ _) rfl
  have h3 : setE (kill .replace false 3 (ctxL R0 EnewD)) 3 { projE 0 Ecell str with mode := R0.mode } =
      ctxL ErF EnewD := by
    funext v
    rcases v with _ | _ | _ | _ | _ | v <;>
      simp [ctxL, ctx, setE, upd, kill, killE, hits, Ecell, Ep, Ec, EnewD, R0, ErF, projE, projDeps, str,
        Entry.vdeps, Mode.ownSlot]
  rw [h3] at hb
  have hs := StmtT.seq (P := P) rfl ha hb
  have hl := StmtT.letv (P := P) (Γ := ctx R0) (F := []) (x := 4) (r := .new .int)
    (s := .seq (.assign 0 (.inr .int 4)) (.assign 3 (.getr 0))) (E := Enew) (Γ1 := ctx R0)
    rfl (by simp [ctx]) (by simp) (RhsT.new rfl) hs
    ⟨ctxL_noPin (by simp [ErF]) (by simp [EnewD]) _, DtorSafe.of_none (ctxL_dtor rfl rfl) _ _ _,
      DbindSafe.of_none (fun v E hE => by
        by_cases h4 : v = 4
        · subst h4; simp [ctxL, setE, upd] at hE; subst hE; rfl
        · simp only [ctxL, setE, upd_ne _ _ h4] at hE; exact (ctx_flags ⟨rfl, rfl⟩ v E hE).2) _⟩
  have h4 : exitScope 4 (ctxL ErF EnewD) = ctx ErF := by
    funext v
    rcases v with _ | _ | _ | _ | _ | v <;>
      simp [exitScope, ctxL, ctx, setE, upd, kill, killE, hits, Ecell, Ep, Ec, ErF, Entry.vdeps,
        Mode.ownSlot]
  rw [h4] at hl; exact hl

/-- The two paths meet: the result lends the cell's payload or `p`. -/
theorem body_typed : StmtT P (sigCtx pick) [] pick.body (ctx ErJ) := by
  rw [sig_eq]
  have hw := Weaker.refl (ctx_wf roots_R0 ⟨rfl, rfl⟩) (ctx_names roots_R0)
  refine StmtT.ite rfl rfl (ExprT.var (E := Ec) (by simp [ctx]) rfl rfl) ?_ ?_
  · exact StmtT.sub hw then_arm (Or.inr (ctx_weaker roots_ErJ rfl rfl rfl (fun _ => rfl)
      (by simp [ErT, ErJ]) (by simp [ErT, ErJ]) ⟨rfl, rfl⟩ ⟨rfl, rfl⟩))
  · exact StmtT.sub hw else_arm (Or.inr (ctx_weaker roots_ErJ rfl rfl rfl (fun _ => rfl)
      (by simp [ErF, ErJ]) (by simp [ErF, ErJ]) ⟨rfl, rfl⟩ ⟨rfl, rfl⟩))

/-- `pick` meets its summary: it lends `p` and the cell, nothing else. -/
theorem pick_ok : FnOK P pick := by
  refine ⟨rfl, by decide, by decide, rfl, by simp [pick], ?_, ?_, by simp [pick], by simp [pick], ?_,
    by simp [pick], ctx ErJ, body_typed, ctx_flags ⟨rfl, rfl⟩, ⟨ErJ, by simp [ctx, pick], rfl, rfl, rfl, ?_, by simp [ErJ],
      by simp [pick]⟩, ?_⟩
  · intro pt hpt
    simp only [pick, List.mem_cons, List.mem_nil_iff, or_false] at hpt
    rcases hpt with rfl | rfl | rfl <;> simp [opt, str, Ty.ok, Ty.owning]
  · intro jk hjk
    simp only [pick, List.mem_cons, List.mem_nil_iff, or_false] at hjk
    rcases hjk with rfl | rfl
    · exact ⟨⟨by decide, Or.inl rfl⟩, rfl⟩
    · exact ⟨⟨by decide, Or.inr ⟨_, rfl⟩⟩, rfl⟩
  · intro jk hjk
    simp only [pick, List.append_nil, List.mem_cons, List.mem_nil_iff, or_false] at hjk
    rcases hjk with rfl | rfl <;> intro b t h
    · simp [pick] at h
    · simp only [pick] at h
      simp only [List.getElem?_cons_zero, Option.some.injEq, Prod.mk.injEq] at h
      obtain ⟨-, rfl⟩ := h; rfl
  · intro d hd
    simp only [ErJ, List.mem_cons, List.mem_nil_iff, or_false] at hd
    rcases hd with rfl | rfl <;> simp [pick]
  · intro i hi b hb
    rcases i with _ | _ | _ | i
    · exact ⟨Ecell, by simp [ctx], rfl, by simp [Ecell], by simp [Ecell]⟩
    · simp [pick] at hb
    · simp [pick] at hb
    · simp [pick] at hi; omega

theorem prog_ok : ProgOK P := by
  intro fn hfn
  simp only [P, List.mem_cons, List.mem_nil_iff, or_false] at hfn
  subst hfn; exact pick_ok

theorem prog_codes : ProgCodes P := by
  intro fn hfn
  simp only [P, List.mem_cons, List.mem_nil_iff, or_false] at hfn
  subst hfn; simp [pick, pickBody, Stmt.codesOK, Rhs.codeOK]

/-! ### The caller

        : i z 0  : ?String cell none  : String s ( mk )  : i c 1
        : String x ( pick cell s c )        -- lends `s`, or the cell's payload
        : i n ( vec_len x )

    The caller's `cell` drops the fresh String, if `pick` made one, when its
    scope ends; `x` depends on both `s` and `cell`, so it ends with either. -/

/-- The caller: `z` is 0, `cell` 1, `s` 2, `c` 3, `x` 4, `n` 5. -/
def main : Stmt :=
  .letv 0 (.expr (.lit 0)) (.letv 1 (.inl 0 str) (.letv 2 (.new .int)
    (.letv 3 (.expr (.lit 1)) (.letcall 4 0 [1, 2, 3] (.letv 5 (.expr (.len 4)) .skip)))))

/-- A context with no borrowed parameter and no binding that runs a
    destructor: nothing in it can be pinned, and ending a binding ends no
    destructor's view. -/
def NoRootb (Γ : Ctx) : Prop := ∀ v E, Γ v = some E → E.mode ≠ .rootb ∧ E.dtor = false ∧ E.dbind = false

theorem NoRootb.noPin {Γ : Ctx} (h : NoRootb Γ) (x : Var) : NoPin Γ x :=
  fun p E hp hm => absurd hm (h p E hp).1

theorem NoRootb.endOK {Γ : Ctx} (h : NoRootb Γ) (x : Var) : EndOK Γ x :=
  ⟨h.noPin x, DtorSafe.of_none (fun v E hv => (h v E hv).2.1) _ _ _,
    DbindSafe.of_none (fun v E hv => (h v E hv).2.2) x⟩

theorem NoRootb.setE {Γ : Ctx} (h : NoRootb Γ) {x : Var} {E : Entry}
    (hE : E.mode ≠ .rootb ∧ E.dtor = false ∧ E.dbind = false) :
    NoRootb (A2.setE Γ x E) := by
  intro v E' hv
  simp only [A2.setE, upd] at hv
  split at hv
  · cases hv; exact hE
  · exact h v E' hv

theorem NoRootb.kill {Γ : Ctx} (h : NoRootb Γ) (e : Eff) (hv : Bool) (x : Var) :
    NoRootb (A2.kill e hv x Γ) := by
  intro v E' h'
  simp only [A2.kill] at h'
  cases hg : Γ v with
  | none => rw [hg] at h'; cases h'
  | some E =>
    rw [hg] at h'; simp only [Option.map_some, Option.some.injEq] at h'; subst h'
    rw [killE_mode, killE_dtor, killE_dbind]; exact h v E hg

theorem NoRootb.exitScope {Γ : Ctx} (h : NoRootb Γ) (x : Var) : NoRootb (A2.exitScope x Γ) := by
  intro v E' h'
  simp only [A2.exitScope, upd] at h'
  split at h'
  · cases h'
  · exact h.kill .replace false x v E' h'

def Ecl : Entry := ⟨opt, .own, true, [], [], false, false⟩
def Ex : Entry := ⟨str, .bor, true, [⟨2, .self⟩, ⟨1, .inner⟩], [], false, false⟩

/-- The caller's context at the call. -/
def K4 : Ctx := A2.setE (A2.setE (A2.setE (A2.setE (fun _ => none) 0 intE) 1 Ecl) 2 Enew) 3 intE

theorem noRootb_empty : NoRootb (fun _ => none) := fun _ _ h => by cases h

theorem K4_noRootb : NoRootb K4 :=
  (((noRootb_empty.setE (by simp [intE])).setE (by simp [Ecl])).setE (by simp [Enew])).setE
    (by simp [intE])

theorem callRes_eq : callRes K4 pick [1, 2, 3] = Ex := by
  simp [callRes, pick, argDeps, argE, K4, A2.setE, upd, derive, Mode.isRoot, Ecl, Enew, intE, rootKind,
    heldOfArgs, allKinds, roots, memDeps, argNames, nameDeps, Entry.vdeps, Mode.ownSlot, opt, str,
    ownHeld, resMode, Ex]

theorem callPost_eq : callPost K4 pick [1, 2, 3] = K4 := by
  funext v
  simp only [callPost, callPostAux, pick, killNames, mutNames, argNames]
  rcases v with _ | _ | _ | _ | v <;>
    simp [argE, K4, A2.setE, upd, A2.kill, killE, hits, Ecl, Enew, intE, Entry.vdeps, Mode.ownSlot, opt, str,
      Ty.holdsView, Ty.elem, nameDeps]

/-- The call: `cell` is handed `inout`, `s` and `c` are lent. -/
theorem call_ok : CallT P K4 [] 0 [1, 2, 3] Ex K4 := by
  refine ⟨pick, rfl, rfl, ?_, ?_, CallDtorSafe.of_none (fun v E hE => by
      rcases v with _ | _ | _ | _ | v <;> simp [K4, A2.setE, upd] at hE <;> subst hE <;> exact ⟨rfl, rfl⟩) _ _,
    callRes_eq.symm, callPost_eq.symm⟩
  · intro i hi
    rcases i with _ | _ | _ | i
    · refine ⟨Ecl, by simp [K4, A2.setE, upd], rfl, ⟨rfl, Or.inl rfl, rfl⟩, fun _ => ?_,
        fun _ => K4_noRootb.noPin _⟩
      refine ⟨by simp, by simp [Ecl, roots, memDeps, Entry.vdeps, Mode.ownSlot], (fun h => by cases h),
        (fun _ _ d hd => by simp [Ecl, Entry.vdeps, Mode.ownSlot] at hd), fun j hj hji => ?_⟩
      rcases j with _ | _ | _ | j
      · exact absurd rfl hji
      · refine ⟨by simp, ?_, (fun h => by cases h), ?_⟩
        · simp [argE, K4, A2.setE, upd, Enew, roots, memDeps, Entry.vdeps, Mode.ownSlot]
        · intro _ _ d hd; simp [argE, K4, A2.setE, upd, Enew, Entry.vdeps, Mode.ownSlot] at hd
      · refine ⟨by simp, ?_, (fun h => by cases h), ?_⟩
        · simp [argE, K4, A2.setE, upd, intE, roots, memDeps, Entry.vdeps, Mode.ownSlot]
        · intro _ _ d hd; simp [argE, K4, A2.setE, upd, intE, Entry.vdeps, Mode.ownSlot] at hd
      · simp [pick] at hj; omega
    · refine ⟨Enew, by simp [K4, A2.setE, upd], rfl, rfl, ?_, ?_⟩
      · intro h; simp [pick, PMode.moves] at h
      · intro h; simp [pick] at h
    · refine ⟨intE, by simp [K4, A2.setE, upd], rfl, rfl, ?_, ?_⟩
      · intro h; simp [pick, PMode.moves] at h
      · intro h; simp [pick] at h
    · simp [pick] at hi; omega
  · intro d hd
    simp [mutNames, argNames, argE, K4, A2.setE, upd, Ecl, Enew, intE, nameDeps, Entry.vdeps, Mode.ownSlot,
      opt, str] at hd

/-- The caller is well-typed from the empty context. -/
theorem main_typed : ∃ Δ, StmtT P (fun _ => none) [] main Δ := by
  -- the contexts the caller's bindings make, none with a borrowed parameter
  have hK5 : NoRootb (A2.setE K4 4 Ex) := K4_noRootb.setE (by simp [Ex])
  have hK6 : NoRootb (A2.setE (A2.setE K4 4 Ex) 5 intE) := hK5.setE (by simp [intE])
  have hK1 : NoRootb (A2.setE (fun _ => none) 0 intE) := noRootb_empty.setE (by simp [intE])
  have hK2 : NoRootb (A2.setE (A2.setE (fun _ => none) 0 intE) 1 Ecl) := hK1.setE (by simp [Ecl])
  have hK3 : NoRootb (A2.setE (A2.setE (A2.setE (fun _ => none) 0 intE) 1 Ecl) 2 Enew) :=
    hK2.setE (by simp [Enew])
  -- innermost first: `: i n ( vec_len x )`
  have hn := StmtT.letv (P := P) (Γ := A2.setE K4 4 Ex) (F := []) (x := 5) (r := .expr (.len 4))
    (s := .skip) (E := intE) (Γ1 := A2.setE K4 4 Ex) rfl (by simp [K4, A2.setE, upd]) (by simp)
    (RhsT.expr (ExprT.len (E := Ex) (t := .int) (by simp [A2.setE, upd]) rfl rfl)) StmtT.skip
    (hK6.endOK _)
  have hc := StmtT.letcall (P := P) (Γ := K4) (F := []) (x := 4) (f := 0) (args := [1, 2, 3])
    (s := .letv 5 (.expr (.len 4)) .skip) (E := Ex) (Γ1 := K4) rfl (by simp [K4, A2.setE, upd])
    (by simp) call_ok hn ((hK6.exitScope 5).endOK _)
  have h3 := StmtT.letv (P := P) (x := 3) (r := .expr (.lit 1)) (E := intE) (F := [])
    (Γ := A2.setE (A2.setE (A2.setE (fun _ => none) 0 intE) 1 Ecl) 2 Enew)
    (Γ1 := A2.setE (A2.setE (A2.setE (fun _ => none) 0 intE) 1 Ecl) 2 Enew)
    rfl (by simp [A2.setE, upd]) (by simp) (RhsT.expr ExprT.lit) hc
    (((hK6.exitScope 5).exitScope 4).endOK _)
  have h2 := StmtT.letv (P := P) (x := 2) (r := .new .int) (E := Enew) (F := [])
    (Γ := A2.setE (A2.setE (fun _ => none) 0 intE) 1 Ecl)
    (Γ1 := A2.setE (A2.setE (fun _ => none) 0 intE) 1 Ecl)
    rfl (by simp [A2.setE, upd]) (by simp) (RhsT.new rfl) h3
    ((((hK6.exitScope 5).exitScope 4).exitScope 3).endOK _)
  have hpush : PushArg (A2.setE (fun _ => none) 0 intE) [] 0 intE intE.ty [] (A2.setE (fun _ => none) 0 intE) :=
    PushArg.int
  have h1 := StmtT.letv (P := P) (x := 1) (r := .inl 0 str) (E := Ecl) (F := [])
    (Γ := A2.setE (fun _ => none) 0 intE) (Γ1 := A2.setE (fun _ => none) 0 intE)
    rfl (by simp [A2.setE, upd]) (by simp) (RhsT.inl (by simp [A2.setE, upd]) rfl hpush rfl) h2
    (((((hK6.exitScope 5).exitScope 4).exitScope 3).exitScope 2).endOK _)
  exact ⟨_, StmtT.letv (P := P) (x := 0) (r := .expr (.lit 0)) (E := intE) (F := []) (Γ := fun _ => none)
    (Γ1 := fun _ => none) rfl rfl (by simp) (RhsT.expr ExprT.lit) h1
    ((((((hK6.exitScope 5).exitScope 4).exitScope 3).exitScope 2).exitScope 1).endOK _)⟩

/-- A run of the caller, from the empty store, never touches memory it may
    not, whichever path `pick` takes. -/
theorem main_safe {m' : Mem} {s' : Stmt} (hr : Steps P (emptyMem 6) main (.ok m' s')) :
    ¬ Stuck P m' s' := by
  obtain ⟨Δ, ht⟩ := main_typed
  exact memory_safe prog_ok prog_codes ht rfl (by simp [main, Stmt.codesOK, Rhs.codeOK])
    (by decide) hr

/-- ... and when it ends, the fresh String, if `pick` made one, has been
    freed with the cell: nothing leaks. -/
theorem main_no_leak {m' : Mem} (hr : Steps P (emptyMem 6) main (.ok m' .skip)) :
    ∀ i, m'.alloc i = false := by
  obtain ⟨Δ, ht⟩ := main_typed
  exact no_leak_end prog_ok prog_codes ht rfl (by simp [main, Stmt.codesOK, Rhs.codeOK])
    (by decide) hr

end A2.DynCell
