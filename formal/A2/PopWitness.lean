import A2.DynCell

/-!
  A2 — a pop and a remove through a borrow (AGORA-888).

      : ( Vec ( Vec i ) ) vv …   -- vv holds one Vec of three numbers
      : ( Vec i ) b ( vec_at vv 0 )
      : i e … ( vec_pop b ) …     -- the last number moves out
      ( vec_remove b 0 )          -- the first goes, the rest close up
      : ~ ( Vec ( Vec i ) ) c vv  -- a cursor over vv
      ( vec_pop c )               -- an element Vec dropped through it

  nurlc lets `vec_pop` and `vec_remove` change a `Vec` through a borrow of
  it, as it lets `vec_push`, `vec_truncate` and `vec_set`; every view of the
  owner's elements ends there (MEMORY.md §2.10).  The calculus has the
  changes through a borrow it needs: a truncation and an element set
  (`StmtT.editB`), and the length's last index (`Expr.dec`).  So:

  - a pop of a number is the number read (`vec_at b ( - ( vec_len b ) 1 )`)
    and the truncation to that index;
  - a pop whose element is dropped is the truncation alone, whatever the
    element type (here a `Vec` of numbers, freed through a cursor);
  - a remove of a number is each later element set one place down, then
    the truncation (here the three-element `Vec`: `b[0] := b[1]`).

  An empty `Vec` is truncated to 0, which leaves it as it is, as nurlc's
  `vec_pop` answers `none` there.  This module types the encoded program
  with A2's own rules and applies `memory_safe` and `no_leak_end` to it.
  What stays out (`CLAIM.md`): moving an element that owns memory out
  through a borrow — a pop of a `Vec` of Strings whose result is kept.
-/

namespace A2.PopWitness

open A2.DynCell (NoRootb noRootb_empty)

def P : Prog := []

/-- The numbers' `Vec`, and the `Vec` of them. -/
def str : Ty := .vec .int
def vstr : Ty := .vec str

/-! ### The program

    `vv` is 0, `w` 1, the number `z` 2, the borrow `b` 3, the popped
    number `e` 4, the moved one `f` 5 and the cursor `c` 6. -/

/-- `( vec_pop b )` whose element is dropped, or read before: the
    truncation to the last index. -/
def popB (x : Var) : Stmt := .edit true x (.trunc (.dec (.len x)))

def body : Stmt :=
  .letv 3 (.at 0 (.lit 0))
    (.letv 4 (.at 3 (.dec (.len 3)))                    -- the popped number
      (.seq (popB 3)                                   -- `vec_pop b`
        (.letv 5 (.at 3 (.lit 1))                      -- `vec_remove b 0`:
          (.seq (.edit true 3 (.set (.lit 0) 5))       --   b[0] := b[1]
            (popB 3)))))                               --   and one less

def cursor : Stmt := .letv 6 (.borrow 0) (popB 6)      -- an element dropped

def main : Stmt :=
  .letv 0 (.new str) (.letv 1 (.new .int) (.letv 2 (.expr (.lit 7))
    (.seq (.push 1 2) (.seq (.push 1 2) (.seq (.push 1 2)
      (.seq (.push 0 1) (.seq body cursor)))))))

/-! ### Entries -/

def Evv : Entry := ⟨vstr, .own, true, [], [], false, false, false, false⟩
def Ew : Entry := ⟨str, .own, true, [], [], false, false, false, false⟩
def Eb : Entry := ⟨str, .bor, true, [⟨0, .inner⟩], [], false, false, false, false⟩
def Ec : Entry := ⟨vstr, .bor, true, [⟨0, .self⟩], [], false, false, false, false⟩

/-! ### Contexts with no borrowed parameter and no destructor binding -/

theorem NoRootb.killNames {Γ : Ctx} (h : NoRootb Γ) : ∀ ds : List Dep, NoRootb (A2.killNames ds Γ)
  | [] => h
  | d :: ds => by
    simp only [A2.killNames, List.foldr_cons]
    exact A2.DynCell.NoRootb.kill (NoRootb.killNames h ds) _ _ _

theorem NoRootb.killThru {Γ : Ctx} (h : NoRootb Γ) (op : Edit) (tx : Ty) (P : List Dep) :
    NoRootb (A2.killThru op tx P Γ) := NoRootb.killNames h _

theorem nrDtor {Γ : Ctx} (h : NoRootb Γ) (e : Eff) (hv : Bool) (x : Var) : DtorSafe Γ e hv x :=
  DtorSafe.of_none (fun v E hv => (h v E hv).2.1) _ _ _
theorem nrPin {Γ : Ctx} (h : NoRootb Γ) (x : Var) : NoPin Γ x := A2.DynCell.NoRootb.noPin h x
theorem nrEnd {Γ : Ctx} (h : NoRootb Γ) (x : Var) : EndOK Γ x := A2.DynCell.NoRootb.endOK h x

syntax "noroot" : tactic
macro_rules
  | `(tactic| noroot) => `(tactic| first
      | exact noRootb_empty
      | (apply A2.DynCell.NoRootb.exitScope; noroot)
      | (apply A2.DynCell.NoRootb.kill; noroot)
      | (apply NoRootb.killThru; noroot)
      | (refine A2.DynCell.NoRootb.setE ?_ (by simp [str, vstr, intE, Evv, Ew, Eb, Ec]); noroot))

syntax "look" : tactic
macro_rules
  | `(tactic| look) => `(tactic| simp [A2.setE, upd, A2.kill, killE, hits, A2.exitScope, Entry.vdeps,
      Mode.ownSlot, derive, Mode.isRoot, rootKind, projE, projDeps, str, vstr, intE, Evv, Ew, Eb, Ec,
      Eff.kills, comp, roots, A2.killThru, A2.killNames, thruDeps, memDeps, Kind.isName, Kind.bound,
      Edit.effAt, argE, elemE, ownHeld, Ty.holdsView, Ty.elem, List.foldr_cons, List.foldr_nil,
      List.map_cons, List.map_nil, List.filter_cons, List.filter_nil])

/-! ### Typing -/

/-- A change through a borrow `x` whose path is one owner `0`'s, which may
    drop elements, typed by `StmtT.editB`. -/
theorem thru_ok {Γ : Ctx} (hn : NoRootb Γ) {op : Edit} {k : Kind} {tx : Ty}
    (h0 : Γ 0 = some ⟨vstr, .own, true, [], [], false, false, false, false⟩) (hst : ∀ y, op.stored = some y → y ≠ 0)
    (hkn : k.isName = false) (hk : k ≠ .share) (hdrop : op.effAt k (decide (vstr = tx)) = .drop) :
    ThruOK Γ [] op tx [⟨0, k⟩] := by
  intro d hd
  simp only [memDeps, hkn, Bool.not_false, List.filter_cons_of_pos, List.filter_nil,
    List.mem_singleton] at hd
  subst hd
  refine ⟨by simp, fun y hy => (hst y hy).symm, _, h0, rfl, Or.inl rfl, ?_, hk⟩
  simp only at hdrop ⊢
  rw [hdrop]; exact nrDtor hn _ _ _

syntax "fin" : tactic
macro_rules
  | `(tactic| fin) => `(tactic| first
      | rfl
      | decide
      | exact PushArg.int
      | exact Or.inl rfl
      | exact nrPin (by noroot) _
      | exact nrDtor (by noroot) _ _ _
      | (look; done)
      | (simp [str, vstr, intE, Evv, Ew, Eb, Ec, roots, memDeps, Kind.isName, Edit.stored, ownHeld]; done))

/-- `vec_pop x` (the truncation to the last index) through the borrow `x`. -/
theorem pop_typed {ξ : Exits} {Γ : Ctx} (hn : NoRootb Γ) {x : Var} {E : Entry} {u : Ty} {k : Kind}
    (hx : Γ x = some E) (hE : E = ⟨.vec u, .bor, true, [⟨0, k⟩], [], false, false, false, false⟩)
    (h0 : Γ 0 = some ⟨vstr, .own, true, [], [], false, false, false, false⟩) (hu : u.holdsView = false)
    (hud : u.dtorFree = true) (hkn : k.isName = false) (hk : k ≠ .share) :
    StmtT P ξ Γ [] (popB x) (A2.setE (A2.killThru (.trunc (.dec (.len x))) (.vec u) [⟨0, k⟩] Γ) x E) := by
  subst hE
  have h := StmtT.editB (b := true) (P := P) (ξ := ξ) (F := []) (op := .trunc (.dec (.len x))) (t := u) (D := [])
    hx rfl rfl rfl hu (by simp)
    (EditArg.trunc (ExprT.dec (ExprT.len hx rfl rfl))) (fun _ h => by cases h) hx rfl
    (by simp [memDeps, hkn]) (thru_ok hn h0 (fun _ h => by cases h) hkn hk rfl) (fun _ => hud)
  exact h

/-- `x[0] := f` through the borrow `x`, `f` a number. -/
theorem set_typed {ξ : Exits} {Γ : Ctx} (hn : NoRootb Γ) {x f : Var} {E : Entry}
    (hx : Γ x = some E) (hE : E = Eb) (hf : Γ f = some intE)
    (h0 : Γ 0 = some ⟨vstr, .own, true, [], [], false, false, false, false⟩) (hfx : f ≠ x) (hf0 : f ≠ 0) :
    StmtT P ξ Γ [] (.edit true x (.set (.lit 0) f))
      (A2.setE (A2.killThru (.set (.lit 0) f) str [⟨0, .inner⟩] Γ) x Eb) := by
  subst hE
  have h := StmtT.editB (b := true) (P := P) (ξ := ξ) (F := []) (op := .set (.lit 0) f) (t := .int) (D := [])
    hx rfl rfl rfl rfl (by simp)
    (EditArg.set ExprT.lit hf rfl rfl PushArg.int) (fun y hy => by simp [Edit.stored] at hy; subst hy; exact hfx)
    hx rfl (by simp [Eb, memDeps, Kind.isName])
    (thru_ok hn h0 (fun y hy => by simp [Edit.stored] at hy; subst hy; exact hf0) rfl (by simp) rfl)
    (fun _ => rfl)
  exact h

theorem main_typed : ∃ Δ, StmtT P .none (fun _ => none) [] main Δ := by
  apply Exists.intro
  -- `: ( Vec ( Vec i ) ) vv`
  refine' StmtT.letv (x := 0) rfl rfl (by simp) (RhsT.new (t := str) rfl) ?_ ?_
  rotate_left
  · -- `: ( Vec i ) w`
    refine' StmtT.letv (x := 1) rfl (by look) (by simp) (RhsT.new (t := .int) rfl) ?_ ?_
    rotate_left
    · -- `: i z 7`
      refine' StmtT.letv (x := 2) rfl (by look) (by simp) (RhsT.expr ExprT.lit) ?_ ?_
      rotate_left
      · -- three numbers into `w`
        refine' StmtT.seq rfl ?_ ?_
        rotate_left 2
        · apply StmtT.push (Ex := Ew) (Ey := intE) (Ex1 := Ew) (t := .int) (D := [])
          all_goals fin
        refine' StmtT.seq rfl ?_ ?_
        rotate_left 2
        · apply StmtT.push (Ex := Ew) (Ey := intE) (Ex1 := Ew) (t := .int) (D := [])
          all_goals fin
        refine' StmtT.seq rfl ?_ ?_
        rotate_left 2
        · apply StmtT.push (Ex := Ew) (Ey := intE) (Ex1 := Ew) (t := .int) (D := [])
          all_goals fin
        -- `w` into `vv`
        refine' StmtT.seq rfl ?_ ?_
        rotate_left 2
        · apply StmtT.push (Ex := Evv) (Ey := Ew) (Ex1 := Evv) (t := str) (D := [])
          · look
          · rfl
          · rfl
          · exact Or.inl rfl
          · simp
          · look
          · rfl
          · rfl
          · decide
          · exact PushArg.move (by simp [str, Ty.owning]) rfl (by simp) (nrPin (by noroot) _)
              (nrDtor (by noroot) _ _ _)
          all_goals fin
        refine' StmtT.seq rfl ?_ ?_
        rotate_left 2
        · -- `: ( Vec i ) b ( vec_at vv 0 )`
          refine' StmtT.letv (x := 3) (E := Eb) rfl (by look) (by simp)
            (RhsT.at (E := Evv) (t := str) (by look) rfl rfl ExprT.lit) ?_ ?_
          rotate_left
          · -- `: i e ( vec_at b ( - ( vec_len b ) 1 ) )`: the number `vec_pop b` hands out
            refine' StmtT.letv (x := 4) (E := intE) rfl (by look) (by simp)
              (RhsT.at (E := Eb) (t := .int) (by look) rfl rfl
                (ExprT.dec (ExprT.len (E := Eb) (t := .int) (by look) rfl rfl))) ?_ ?_
            rotate_left
            · -- `vec_pop b`: the truncation through the borrow
              refine' StmtT.seq rfl ?_ ?_
              rotate_left 2
              · exact pop_typed (u := .int) (k := .inner) (by noroot) (by look) rfl (by look) rfl rfl rfl (by simp)
              -- `vec_remove b 0`: `: i f ( vec_at b 1 )`, `b[0] := f`, one less
              refine' StmtT.letv (x := 5) (E := intE) rfl (by look) (by simp)
                (RhsT.at (E := Eb) (t := .int) (by look) rfl rfl ExprT.lit) ?_ ?_
              rotate_left
              · refine' StmtT.seq rfl ?_ ?_
                rotate_left 2
                · exact set_typed (by noroot) (by look) rfl (by look) (by look) (by decide) (by decide)
                exact pop_typed (u := .int) (k := .inner) (by noroot) (by look) rfl (by look) rfl rfl rfl (by simp)
              · exact nrEnd (by noroot) _
            · exact nrEnd (by noroot) _
          · exact nrEnd (by noroot) _
        · -- `: ~ c vv`, `vec_pop c`: an element `Vec` dropped through the cursor
          refine' StmtT.letv (x := 6) (E := Ec) rfl (by look) (by simp)
            (RhsT.borrow (E := Evv) (t := str) (by look) rfl rfl) ?_ ?_
          rotate_left
          · exact pop_typed (u := str) (k := .self) (by noroot) (by look) rfl (by look) rfl rfl rfl (by simp)
          · exact nrEnd (by noroot) _
      · exact nrEnd (by noroot) _
    · exact nrEnd (by noroot) _
  · exact nrEnd (by noroot) _

theorem prog_ok : ProgOK P := by
  intro fn hfn; simp [P] at hfn

theorem prog_codes : ProgCodes P := by
  intro fn hfn; simp [P] at hfn

/-- A run of the program, from the empty store, never touches memory it may
    not: the reads through `b` after each change see the shortened `Vec`. -/
theorem main_safe {m' : Mem} {s' : Stmt} (hr : Steps P (emptyMem 7) main (.ok m' s')) :
    ¬ Stuck P m' s' := by
  obtain ⟨Δ, ht⟩ := main_typed
  exact memory_safe prog_ok prog_codes ht rfl
    (by simp [main, body, cursor, popB, Stmt.codesOK, Rhs.codeOK]) (by decide) hr

/-- ... and when it ends, everything it allocated is freed: the element
    `Vec` dropped through the cursor with what `vv` held, and `vv`. -/
theorem main_no_leak {m' : Mem} (hr : Steps P (emptyMem 7) main (.ok m' .skip)) :
    ∀ i, m'.alloc i = false := by
  obtain ⟨Δ, ht⟩ := main_typed
  exact no_leak_end prog_ok prog_codes ht rfl
    (by simp [main, body, cursor, popB, Stmt.codesOK, Rhs.codeOK]) (by decide) hr

end A2.PopWitness
