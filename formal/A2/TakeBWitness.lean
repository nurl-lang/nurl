import A2.PopWitness

/-!
  A2 — an element that owns memory moved out through a borrow (AGORA-889).

      : ( Vec ( Vec String ) ) vv …   -- vv holds one Vec of two Strings
      : ( Vec String ) b ( vec_at vv 0 )
      : String y ( vec_pop b )         -- the last String moves out, kept
      : String z ( vec_remove b 0 )    -- the first one moves out, kept
      : i ly ( vec_len y )             -- both are read after
      : i lz ( vec_len z )

  nurlc lets `vec_pop` and `vec_remove` take an element out through a
  borrow, and the result is the caller's.  The calculus does it with
  `Stmt.takeB` (`Step.takeB`): the element leaves the node `b` names, in
  `vv`'s tree, and becomes the new owner's; it is typed as `editB`'s
  truncation is on every owner `b` may reach (`StmtT.takeB`), so every view
  of `vv`'s elements ends there (MEMORY.md §2.10).  A pop is the remove of
  the last index (`Expr.dec`); nurlc's `vec_pop` of an empty `Vec` answers
  `none`, where the witness's index is out of range and the step panics.

  A String is a `Vec` of bytes (`str`, numbers).  This module types the
  program with A2's own rules and applies `memory_safe` and `no_leak_end`:
  the moved-out Strings are their bindings' and are released at their
  scopes' ends, the rest with `vv`.
-/

namespace A2.TakeBWitness

open A2.DynCell (NoRootb noRootb_empty)
open A2.PopWitness (nrDtor nrPin nrEnd NoRootb.killThru)

def P : Prog := []

/-- A String (a `Vec` of bytes), a `Vec` of them, and a `Vec` of those. -/
def str : Ty := .vec .int
def vstr : Ty := .vec str
def vvstr : Ty := .vec vstr

/-! ### The program

    `vv` is 0, the Strings' `Vec` `w` 1, the Strings 2 and 3, the borrow
    `b` 4, the popped String `y` 5, the removed one `z` 6, and the lengths
    read 7 and 8. -/

def body : Stmt :=
  .letv 4 (.at 0 (.lit 0))                                 -- `b`
    (.takeB 4 (.dec (.len 4)) 5                            -- `: String y ( vec_pop b )`
      (.takeB 4 (.lit 0) 6                                 -- `: String z ( vec_remove b 0 )`
        (.letv 7 (.expr (.len 5)) (.letv 8 (.expr (.len 6)) .skip))))

def main : Stmt :=
  .letv 0 (.new vstr) (.letv 1 (.new str) (.letv 2 (.new .int) (.letv 3 (.new .int)
    (.seq (.push 1 2) (.seq (.push 1 3) (.seq (.push 0 1) body))))))

/-! ### Entries -/

def Evv : Entry := ⟨vvstr, .own, true, [], [], false, false⟩
def Ew : Entry := ⟨vstr, .own, true, [], [], false, false⟩
def Es : Entry := ⟨str, .own, true, [], [], false, false⟩
def Eb : Entry := ⟨vstr, .bor, true, [⟨0, .inner⟩], [], false, false⟩

syntax "noroot9" : tactic
macro_rules
  | `(tactic| noroot9) => `(tactic| first
      | exact noRootb_empty
      | (apply A2.DynCell.NoRootb.exitScope; noroot9)
      | (apply A2.DynCell.NoRootb.kill; noroot9)
      | (apply NoRootb.killThru; noroot9)
      | (refine A2.DynCell.NoRootb.setE ?_ (by simp [str, vstr, vvstr, intE, Evv, Ew, Es, Eb, compE,
          ownHeld, Ty.holdsView]); noroot9))

syntax "look9" : tactic
macro_rules
  | `(tactic| look9) => `(tactic| simp [A2.setE, upd, A2.kill, killE, hits, A2.exitScope, Entry.vdeps,
      Mode.ownSlot, derive, Mode.isRoot, rootKind, projE, projDeps, str, vstr, vvstr, intE, Evv, Ew, Es,
      Eb, Eff.kills, comp, roots, A2.killThru, A2.killNames, thruDeps, memDeps, Kind.isName, Kind.bound,
      Edit.effAt, argE, elemE, compE, ownHeld, Ty.holdsView, Ty.elem, List.foldr_cons, List.foldr_nil,
      List.map_cons, List.map_nil, List.filter_cons, List.filter_nil])

syntax "fin9" : tactic
macro_rules
  | `(tactic| fin9) => `(tactic| first
      | rfl
      | decide
      | exact PushArg.int
      | exact Or.inl rfl
      | exact nrPin (by noroot9) _
      | exact nrDtor (by noroot9) _ _ _
      | (look9; done)
      | (simp [str, vstr, vvstr, intE, Evv, Ew, Es, Eb, roots, memDeps, Kind.isName, Edit.stored,
          ownHeld]; done))

/-! ### Typing -/

/-- The truncation's effect through `b`, whose path is `vv`'s elements, may
    drop them: `vv` is a live owner. -/
theorem thru_ok {Γ : Ctx} (hn : NoRootb Γ) {i : Expr} (h0 : Γ 0 = some Evv) :
    ThruOK Γ [] (.trunc i) vstr [⟨0, .inner⟩] := by
  intro d hd
  simp only [memDeps, Kind.isName, Bool.not_false, List.filter_cons_of_pos, List.filter_nil,
    List.mem_singleton] at hd
  subst hd
  refine ⟨by simp, fun y hy => ?_, _, h0, rfl, Or.inl rfl, nrDtor hn _ _ _, by simp⟩
  simp [Edit.stored] at hy

/-- `: String y ( vec_remove b i )` through the borrow `b`. -/
theorem take_typed {ξ : Exits} {Γ Δ : Ctx} (hn : NoRootb Γ) {y : Var} {i : Expr} {s : Stmt}
    (hb : Γ 4 = some Eb) (h0 : Γ 0 = some Evv) (hy : Γ y = none) (hie : ExprT Γ i)
    (hsrc : s.src = true)
    (hs : StmtT P (ξ.under y) (A2.setE (A2.setE (A2.killThru (.trunc i) vstr [⟨0, .inner⟩] Γ) 4 Eb) y
      (compE Eb str)) [] s Δ) (hend : EndOK Δ y) :
    StmtT P ξ Γ [] (.takeB 4 i y s) (A2.exitScope y Δ) :=
  StmtT.takeB hsrc hy (by simp) hb rfl rfl rfl rfl (by simp) hie (by simp [Eb, memDeps, Kind.isName])
    (thru_ok hn h0) rfl hs hend

theorem main_typed : ∃ Δ, StmtT P .none (fun _ => none) [] main Δ := by
  apply Exists.intro
  -- `: ( Vec ( Vec String ) ) vv`
  refine' StmtT.letv (x := 0) rfl rfl (by simp) (RhsT.new (t := vstr) rfl) ?_ ?_
  rotate_left
  · -- `: ( Vec String ) w`
    refine' StmtT.letv (x := 1) rfl (by look9) (by simp) (RhsT.new (t := str) rfl) ?_ ?_
    rotate_left
    · -- two Strings
      refine' StmtT.letv (x := 2) rfl (by look9) (by simp) (RhsT.new (t := .int) rfl) ?_ ?_
      rotate_left
      · refine' StmtT.letv (x := 3) rfl (by look9) (by simp) (RhsT.new (t := .int) rfl) ?_ ?_
        rotate_left
        · -- the Strings into `w`
          refine' StmtT.seq rfl ?_ ?_
          rotate_left 2
          · apply StmtT.push (Ex := Ew) (Ey := Es) (Ex1 := Ew) (t := str) (D := [])
            · look9
            · rfl
            · rfl
            · exact Or.inl rfl
            · simp
            · look9
            · rfl
            · rfl
            · decide
            · exact PushArg.move (by simp [str, Ty.owning]) rfl (by simp) (nrPin (by noroot9) _)
                (nrDtor (by noroot9) _ _ _)
            all_goals fin9
          refine' StmtT.seq rfl ?_ ?_
          rotate_left 2
          · apply StmtT.push (Ex := Ew) (Ey := Es) (Ex1 := Ew) (t := str) (D := [])
            · look9
            · rfl
            · rfl
            · exact Or.inl rfl
            · simp
            · look9
            · rfl
            · rfl
            · decide
            · exact PushArg.move (by simp [str, Ty.owning]) rfl (by simp) (nrPin (by noroot9) _)
                (nrDtor (by noroot9) _ _ _)
            all_goals fin9
          -- `w` into `vv`
          refine' StmtT.seq rfl ?_ ?_
          rotate_left 2
          · apply StmtT.push (Ex := Evv) (Ey := Ew) (Ex1 := Evv) (t := vstr) (D := [])
            · look9
            · rfl
            · rfl
            · exact Or.inl rfl
            · simp
            · look9
            · rfl
            · rfl
            · decide
            · exact PushArg.move (by simp [vstr, Ty.owning]) rfl (by simp) (nrPin (by noroot9) _)
                (nrDtor (by noroot9) _ _ _)
            all_goals fin9
          -- `: ( Vec String ) b ( vec_at vv 0 )`
          refine' StmtT.letv (x := 4) (E := Eb) rfl (by look9) (by simp)
            (RhsT.at (E := Evv) (t := vstr) (by look9) rfl rfl ExprT.lit) ?_ ?_
          rotate_left
          · -- `: String y ( vec_pop b )`: the last String moves out through `b`
            refine' take_typed (y := 5) ?_ ?_ ?_ ?_
              (ExprT.dec (ExprT.len (E := Eb) (t := str) ?_ rfl rfl)) rfl ?_ ?_
            rotate_left
            · noroot9
            · look9
            · look9
            · look9
            · look9
            · -- `: String z ( vec_remove b 0 )`: the first one moves out
              refine' take_typed (y := 6) ?_ ?_ ?_ ?_ ExprT.lit rfl ?_ ?_
              rotate_left
              · noroot9
              · look9
              · look9
              · look9
              · -- both read after
                refine' StmtT.letv (x := 7) (E := intE) rfl (by look9) (by simp)
                  (RhsT.expr (ExprT.len (E := compE Eb str) (t := .int) (by look9) rfl rfl)) ?_ ?_
                rotate_left
                · refine' StmtT.letv (x := 8) (E := intE) rfl (by look9) (by simp)
                    (RhsT.expr (ExprT.len (E := compE Eb str) (t := .int) (by look9) rfl rfl)) ?_ ?_
                  rotate_left
                  · exact StmtT.skip
                  · exact nrEnd (by noroot9) _
                · exact nrEnd (by noroot9) _
              · exact nrEnd (by noroot9) _
            · exact nrEnd (by noroot9) _
          · exact nrEnd (by noroot9) _
        · exact nrEnd (by noroot9) _
      · exact nrEnd (by noroot9) _
    · exact nrEnd (by noroot9) _
  · exact nrEnd (by noroot9) _

theorem prog_ok : ProgOK P := by
  intro fn hfn; simp [P] at hfn

theorem prog_codes : ProgCodes P := by
  intro fn hfn; simp [P] at hfn

/-- A run of the program, from the empty store, never touches memory it may
    not: each String moved out is its new owner's, and `b` sees `vv`'s
    element shortened. -/
theorem main_safe {m' : Mem} {s' : Stmt} (hr : Steps P (emptyMem 9) main (.ok m' s')) :
    ¬ Stuck P m' s' := by
  obtain ⟨Δ, ht⟩ := main_typed
  exact memory_safe prog_ok prog_codes ht rfl
    (by simp [main, body, Stmt.codesOK, Rhs.codeOK]) (by decide) hr

/-- ... and when it ends, everything it allocated is freed: the Strings
    moved out with their bindings' scopes, the rest with `vv`. -/
theorem main_no_leak {m' : Mem} (hr : Steps P (emptyMem 9) main (.ok m' .skip)) :
    ∀ i, m'.alloc i = false := by
  obtain ⟨Δ, ht⟩ := main_typed
  exact no_leak_end prog_ok prog_codes ht rfl
    (by simp [main, body, Stmt.codesOK, Rhs.codeOK]) (by decide) hr

end A2.TakeBWitness
