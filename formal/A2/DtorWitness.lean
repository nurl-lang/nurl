import A2.DynCell

/-! # A2-drop.3a: the destructor on the type, checked

Two kinds of fact, both checked here (`check.sh` prints their axioms):

* **The guarantee of the typing** (`A2.Dtor.*`): every binder of an owned
  value of a destructor type (or of a struct or an enum holding one) either
  is a `letd`, whose scope is a `scopeD` frame, or hands the value to one
  first thing (`Stmt.movedFirst`); a `letd`'s value is of the destructor type,
  whose function is its destructor (`DropFnOK`: one that takes it lent,
  `DtorOK`, or a struct's glue, which takes it owned and takes it apart,
  `GlueOK`, Agora #616), and the binding is assigned nothing
  in its scope (`Stmt.assigns`).  A typed `scopeD` frame whose binding still
  owns its value at its end has exactly one step: it calls that destructor
  on the binding (lent, or moved into a glue), then ends the binding
  (`Step.scopeDEnd`).
* **A witness** (`A2.DtorWitness`): a program with a destructor type, its
  destructor, a function handing back an owned value of that type, and two
  callers (`main`: a `letd` of a struct literal; `main2`: a call's result
  handed to its `letd`), all typed, with `memory_safe` applied: the premises
  the cut adds are satisfiable.  A2-drop.3b adds two more: an option of a
  destructor value (`main3`, typed under 3a's rules too), and an enum
  holding a destructor value two levels down (`main4`, which only the deep
  `Ty.holdsDtor` sends to `letd`), and a `Vec` of destructor values with a
  destructor value pushed into it, bound by `letd` (`main5`: that the
  binder's premises are satisfiable; the drain's steps are theorems about
  any frame, `A2.Dtor.scopeD_frame_value`, `scopeD_end_drains`,
  `scopeD_drain_binds`, `scopeD_end_empty`, `scopeD_panic_drains`).
  A call's owned destructor result has a destructor frame from the start
  (`result_frame_is_scopeD`, Agora #611).
  Agora #616: a struct holding a destructor value has glue for its
  destructor, which takes it apart with each destructor field in a frame
  of its own (`A2.Dtor.struct_dtor_is_glue`, `glue_takes_apart`; `main7`);
  one with a `% Drop` of its own has glue that rebinds it under the fields'
  glue and runs the impl on it lent (`ImplGlueOK`, `impl_glue_body`,
  `letd_retype`; the functions `impl` and `glue2`, `main8`).
  A2-drop.3c and 3d: no closure's environment and no block's payload holds
  a destructor value (`A2.Dtor.pkgs_env_dtor_free`, `blk_pkgs_env_dtor_free`,
  `blocks_dtor_free`).
-/

namespace A2.Dtor

/-- `skip` has no step. -/
theorem skip_no_step {P : Prog} {m : Mem} {r : Res} (h : Step P m .skip r) : False := by
  cases h with
  | waitPanic hw => exact hw

/-- A typed `letv` binds no owned value of a destructor type (nor of a struct
    or an enum holding one). (In the context its rule was applied in, under
    any `sub`sumptions.) -/
theorem letv_owned_no_dtor {P : Prog} {Γ Δ : Ctx} {F : List Var} {x : Var} {r : Rhs} {s : Stmt}
    (h : StmtT P Γ F (.letv x r s) Δ) :
    ∃ Γ0 E Γ1, RhsT Γ0 F r E Γ1 ∧ (E.mode = .own → E.ty.holdsDtor = false) := by
  generalize hst : Stmt.letv x r s = st at h
  induction h with
  | letv _ _ _ hr _ _ hnd => cases hst; exact ⟨_, _, _, hr, hnd⟩
  | sub _ _ _ ih => exact ih hst
  | _ => cases hst

/-- A typed call's owned result of a destructor type is handed to its `letd`
    first thing, and the result binding is assigned nothing. -/
theorem letcall_hands_over {P : Prog} {Γ Δ : Ctx} {F : List Var} {x : Var} {f : Nat}
    {args : List Var} {s : Stmt} (h : StmtT P Γ F (.letcall x f args s) Δ) :
    ∀ fn, P[f]? = some fn → fn.resOwn = true → fn.resTy.holdsDtor = true →
      x ∈ s.movedFirst ∧ x ∉ s.assigns := by
  generalize hst : Stmt.letcall x f args s = st at h
  induction h with
  | letcall _ _ _ _ _ _ hdk => cases hst; exact hdk
  | sub _ _ _ ih => exact ih hst
  | _ => cases hst

/-- A typed `unpair`'s field of a destructor type is handed to its `letd`
    first thing. -/
theorem unpair_hands_over {P : Prog} {Γ Δ : Ctx} {F : List Var} {y x z : Var} {s : Stmt}
    (h : StmtT P Γ F (.unpair y x z s) Δ) :
    ∃ a b : Ty, (a.holdsDtor = true → x ∈ s.movedFirst ∧ x ∉ s.assigns) ∧
      (b.holdsDtor = true → z ∈ s.movedFirst ∧ z ∉ s.assigns) := by
  generalize hst : Stmt.unpair y x z s = st at h
  induction h with
  | unpair _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ hdx hdz => cases hst; exact ⟨_, _, hdx, hdz⟩
  | sub _ _ _ ih => exact ih hst
  | _ => cases hst

/-- Agora #616: what a typed `unpair` takes apart, in the context it is
    typed in: `y` is of a struct type `prod a b`, under its destructor type
    if it has one, and each field whose type holds a destructor value is
    handed to its `letd` first thing, and assigned nothing. -/
theorem unpair_typed {P : Prog} {Γ Δ : Ctx} {F : List Var} {y x z : Var} {s : Stmt}
    (h : StmtT P Γ F (.unpair y x z s) Δ) :
    ∃ (E : Entry) (a b : Ty), Γ y = some E ∧ E.ty.undtor = .prod a b ∧
      (a.holdsDtor = true → x ∈ s.movedFirst ∧ x ∉ s.assigns) ∧
      (b.holdsDtor = true → z ∈ s.movedFirst ∧ z ∉ s.assigns) := by
  generalize hst : Stmt.unpair y x z s = st at h
  induction h with
  | unpair _ hy _ _ hty _ _ _ _ _ _ _ _ _ _ _ hdx hdz =>
    cases hst; exact ⟨_, _, _, hy, unpair_undtor hty, hdx, hdz⟩
  | @sub Γa _ _ _ _ _ hw _ _ ih =>
    obtain ⟨E', a, b, hy', hty, hdx, hdz⟩ := ih hst
    obtain ⟨hn, hE⟩ := hw.1 y
    cases hg : Γa y with
    | none => rw [hn.mp hg] at hy'; cases hy'
    | some E =>
      have hw' := hE E E' hg hy'
      exact ⟨E, a, b, rfl, by rw [← hw'.ty]; exact hty, hdx, hdz⟩
  | _ => cases hst

/-- **Agora #616: a destructor value changes its destructor type only where
    its own destructor's work is done.**  A `letd x f` that binds a value of
    another destructor type `Ty.dtor g t` (`g ≠ f`): `g` is the glue of a
    struct with an impl `i`, `f` is that struct's fields' glue, and the
    `letd`'s scope starts with the call of `i` on `x`.  (Read off the steps,
    not part of this statement: the impl then runs on the value, or panics
    with the value in `f`'s frame, and `f`'s frame drops the fields.) -/
theorem letd_retype {P : Prog} {f : Nat} {t a : Ty} {x : Var} {s : Stmt} (h : LetdFn P f t a x s)
    {g : Nat} (ha : a = .dtor g t) (hne : g ≠ f) :
    ∃ i r k, ImplGlueOK P g t f i ∧ s = .letcall r i [x] k ∧ GlueOK P f t ∧ DtorOK P i (.dtor f t) := by
  obtain ⟨i, r, k, hig, hs⟩ := h.2 g ha hne
  have hig' := hig
  obtain ⟨_, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, hgl, hdt, _⟩ := hig'
  exact ⟨i, r, k, hig, hs, hgl, hdt⟩

/-- **Agora #616: the glue of a struct with a `% Drop` of its own.**  It
    takes the struct owned, rebinds it under the fields' glue `h` first
    thing (nothing can panic before: from there the struct is in `h`'s
    frame, which takes it apart with a frame per destructor field, at its
    end and on a panic), runs the impl `i` on it lent, and sets its result. -/
theorem impl_glue_body {P : Prog} {f : Nat} {t : Ty} {h i : Nat} (hg : ImplGlueOK P f t h i) :
    ∃ fn w r e, P[f]? = some fn ∧ fn.params = [(.sink, .dtor f t)] ∧
      fn.body = .letd w h (.var 0) (.letcall r i [w] (.assign 1 (.expr e))) ∧
      GlueOK P h t ∧ DtorOK P i (.dtor h t) := by
  obtain ⟨fn, _, _, w, r, e, hfn, _, _, hps, _, _, _, _, _, _, hgl, hdt, hb⟩ := hg
  exact ⟨fn, w, r, e, hfn, hps, hb, hgl, hdt⟩

/-- Agora #616: the destructor of a struct that holds a destructor value is
    its glue, which takes the struct apart (`GlueOK`), after the struct's
    own impl if it has one (`ImplGlueOK`); a destructor that takes it lent
    (`DtorOK`) is refused for it. -/
theorem struct_dtor_is_glue {P : Prog} {f : Nat} {a b : Ty} (h : DropFnOK P f (.prod a b))
    (hd : (Ty.prod a b).holdsDtor = true) :
    GlueOK P f (.prod a b) ∨ ∃ h i, ImplGlueOK P f (.prod a b) h i := by
  rcases h with ⟨_, h⟩ | h
  · rw [h a b rfl] at hd; cases hd
  · exact h

/-- **Agora #616: a struct's glue runs each field's destructor in a frame
    of its own.**  In a typed program, the glue `f` of the struct `prod a b`
    takes one value of the destructor type `Ty.dtor f (prod a b)` owned,
    and its body takes it apart first thing into `x` and `z` and does
    nothing after but hand values on and set its result (`Stmt.pureGlue`);
    a field of a destructor type or of a struct with glue is so in a frame
    that runs its destructor (an enum field's lent glue is the open half of
    Agora #616); a field whose
    type holds a destructor value is handed to its `letd` first thing and
    assigned nothing, so its destructor runs at that `letd`'s frame's end
    (`scopeD_end_runs_dtor`), and on a panic in what runs before it
    (`scopeD_panic_runs_dtor`): an earlier field's destructor that panics
    does not skip a later field's. -/
theorem glue_takes_apart {P : Prog} (hP : ProgOK P) {f : Nat} {a b : Ty} (h : GlueOK P f (.prod a b)) :
    ∃ fn x z s, P[f]? = some fn ∧ fn.params = [(.sink, .dtor f (.prod a b))] ∧
      fn.body = .unpair 0 x z s ∧ s.pureGlue = true ∧
      (a.holdsDtor = true → x ∈ s.movedFirst ∧ x ∉ s.assigns) ∧
      (b.holdsDtor = true → z ∈ s.movedFirst ∧ z ∉ s.assigns) := by
  obtain ⟨fn, a', b', hfn, hab, _, hps, _, _, _, _, _, _, x, z, s, hbody, hpure⟩ := h
  cases hab
  obtain ⟨Δ, hb, _⟩ := (hP fn (List.mem_of_getElem? hfn)).2.2.2.2.2.2.2.2.2.2.2.2
  rw [hbody] at hb
  obtain ⟨E, a1, b1, hy, hty, hdx, hdz⟩ := unpair_typed hb
  have hE : E.ty = .dtor f (.prod a b) := by
    simp [sigCtx, hps, paramE] at hy
    rw [← hy]
  rw [hE] at hty
  simp [Ty.undtor] at hty
  obtain ⟨rfl, rfl⟩ := hty
  exact ⟨fn, x, z, s, hfn, hps, hbody, hpure, hdx, hdz⟩

/-- A typed `letd` binds a value of the destructor type `Ty.dtor f t` (`t` a
    struct or an enum), `f` is its destructor (`DropFnOK`: one that takes it
    lent, or a struct's glue), and the binding is assigned nothing in its scope. -/
theorem letd_dtor {P : Prog} {Γ Δ : Ctx} {F : List Var} {x : Var} {f : Nat} {r : Rhs} {s : Stmt}
    (h : StmtT P Γ F (.letd x f r s) Δ) :
    ∃ t, t.isStruct = true ∧ DropFnOK P f t ∧ x ∉ s.assigns := by
  generalize hst : Stmt.letd x f r s = st at h
  induction h with
  | letd _ _ _ _ _ _ hst' _ hok _ _ _ hna => cases hst; exact ⟨_, hst', hok.1, hna⟩
  | sub _ _ _ ih => exact ih hst
  | _ => cases hst

/-- A typed function's `sink` parameter of a type holding a destructor value
    is handed to its `letd` first thing in its body, and assigned nothing; an
    `inout` one is assigned nothing; an owned result of such a type is set at
    most once on any path, and is of a destructor type itself, with no views
    and no closure, whose function is a `DtorOK` destructor (the result's
    frame runs it on a panic in the callee, `result_frame_is_scopeD`). -/
theorem fnOK_dtor_params {P : Prog} {fn : Fn} (h : FnOK P fn) :
    (∀ i (hi : i < fn.params.length), fn.params[i].1 = .sink → fn.params[i].2.holdsDtor = true →
      i ∈ fn.body.movedFirst ∧ i ∉ fn.body.assigns) ∧
    (∀ i (hi : i < fn.params.length) b, fn.params[i].1 = .inout b → fn.params[i].2.holdsDtor = true →
      i ∉ fn.body.assigns) ∧
    (fn.resOwn = true → fn.resTy.holdsDtor = true → fn.body.asgMax fn.params.length ≤ 1 ∧
      ∃ g t, (fn.resTy = .dtor g t ∨ fn.resTy = .vec (.dtor g t)) ∧ t.holdsView = false ∧
        t.hasFn = false ∧ DropFnOK P g t) :=
  h.2.2.2.2.2.2.2.2.2.2.2.1

/-- A call's owned result of a destructor type, or that is a `Vec` of
    destructor values, has a destructor frame from the start: the call's
    inside is `scopeD r g …` on the result slot `r`, with `g` the result
    type's destructor (the shape of `callIn`; what the frame then does is
    `scopeD_panic_runs_dtor` / `scopeD_panic_drains` for a slot that owns,
    and `Step.scopeDMoved` once the result has moved to the caller). -/
theorem result_frame_is_scopeD (fn : Fn) (args : List Var) (base : Nat) (x : Var) {g : Nat} {t : Ty}
    (ho : fn.resOwn = true) (hty : fn.resTy = .dtor g t ∨ fn.resTy = .vec (.dtor g t)) :
    ∃ s, callIn fn args base x = .scopeD (base + fn.params.length) g s := by
  have hf : ∀ r s, resFrame fn r s = .scopeD r g s := fun r s => by
    unfold resFrame; rcases hty with h | h <;> rw [ho, h]
  exact ⟨_, hf _ _⟩

/-- **The scope end of a destructor frame runs the destructor.** In a typed
    `scopeD x f` frame, `f` is the destructor (`DropFnOK`) of a destructor type
    `Ty.dtor f t` (which is `x`'s type when `x` owns a value that is no node,
    `scopeD_frame_value`).  When its body is done and `x` still owns its
    value, a struct or an enum (no `Vec`'s node), the frame's one step calls
    `f` on `x`, then ends `x`'s scope: a destructor that takes `x` lent
    (`DtorOK`) leaves the tree for `scope x` to free; a struct's glue
    (`GlueOK`, Agora #616) takes `x` owned, so the call moves the value in
    and `scope x` ends a binding that is moved out. -/
theorem scopeD_end_runs_dtor {P : Prog} {Γ Δ : Ctx} {F : List Var} {x : Var} {f : Nat}
    {m : Mem} {v : Val} (ht : StmtT P Γ F (.scopeD x f .skip) Δ)
    (hx : m.st x = some ⟨true, some v⟩) (hv : v.isNode = false) :
    (∃ t, DropFnOK P f t) ∧
      Step P m (.scopeD x f .skip) (.ok { m with nv := m.nv + 1 } (.scope x (.letcall m.nv f [x] .skip))) ∧
      ∀ r, Step P m (.scopeD x f .skip) r →
        r = .ok { m with nv := m.nv + 1 } (.scope x (.letcall m.nv f [x] .skip)) := by
  refine ⟨?_, Step.scopeDEnd hx hv, fun r h => ?_⟩
  · generalize hst : Stmt.scopeD x f .skip = st at ht
    induction ht with
    | scopeD hE _ _ _ _ _ _ _ =>
      cases hst
      obtain ⟨E, t, _, _, _, _, h5, _⟩ := hE
      exact ⟨t, h5⟩
    | sub _ _ _ ih => exact ih hst
    | _ => cases hst
  · cases h with
    | scopeDIn hs => exact (skip_no_step hs).elim
    | scopeDEnd _ _ => rfl
    | scopeDMoved hm => rw [hx] at hm; cases hm
    | scopeDDrain h => rw [hx] at h; cases h; cases hv
    | scopeDEmpty h => rw [hx] at h; cases h; cases hv
    | scopeDP hs _ _ => exact (skip_no_step hs).elim
    | scopeDPDrain hs _ => exact (skip_no_step hs).elim
    | scopeDPMoved hs _ => exact (skip_no_step hs).elim
    | waitPanic hw => exact hw.elim

/-- …and on the panic path: a panic out of the body with `x` still owning
    its value stops at the frame, runs `f` on `x`, frees it, and raises again. -/
theorem scopeD_panic_runs_dtor {P : Prog} {x : Var} {f : Nat} {m m1 : Mem} {s : Stmt} {v : Val}
    (hs : Step P m s (.panic m1)) (hx : m1.st x = some ⟨true, some v⟩) (hv : v.isNode = false) :
    Step P m (.scopeD x f s)
      (.ok { m1 with nv := m1.nv + 1 } (.seq (.scope x (.letcall m1.nv f [x] .skip)) .panic)) :=
  Step.scopeDP hs hx hv

/-- **A2-drop.3b: the scope end of a `Vec` of destructor values drains it.**
    When the frame's body is done and `x` still owns a `Vec` with an element,
    the frame's one step hands element 0 to a fresh destructor binding
    (`vec_remove x 0`), under the same frame ... -/
theorem scopeD_end_drains {P : Prog} {x : Var} {f : Nat} {m : Mem} {t : Ty} {c d : Nat} {e : Val}
    {es : List Val} (hx : m.st x = some ⟨true, some (.node t c d (e :: es))⟩) :
    Step P m (.scopeD x f .skip)
        (.ok { m with nv := m.nv + 1 } (.scopeD x f (.letd m.nv f (.popFront x) .skip))) ∧
      ∀ r, Step P m (.scopeD x f .skip) r →
        r = .ok { m with nv := m.nv + 1 } (.scopeD x f (.letd m.nv f (.popFront x) .skip)) := by
  refine ⟨Step.scopeDDrain hx, fun r h => ?_⟩
  cases h with
  | scopeDIn hs => exact (skip_no_step hs).elim
  | scopeDEnd h hv => rw [hx] at h; cases h; cases hv
  | scopeDMoved hm => rw [hx] at hm; cases hm
  | scopeDDrain _ => rfl
  | scopeDEmpty h => rw [hx] at h; cases h
  | scopeDP hs _ _ => exact (skip_no_step hs).elim
  | scopeDPDrain hs _ => exact (skip_no_step hs).elim
  | scopeDPMoved hs _ => exact (skip_no_step hs).elim
  | waitPanic hw => exact hw.elim

/-- ... and the step after it (stated for any unbound `y`; the drain's is
    the fresh `m.nv`): that binding's own frame is next, the element in it,
    the `Vec` one element shorter (the elements after it, in their order).
    One step, not the run: that the element's frame then runs its destructor
    is `scopeD_end_runs_dtor` of a value that is no node, which a typed
    `Vec`'s elements are (`scopeD_frame_value`). -/
theorem scopeD_drain_binds {P : Prog} {x y : Var} {f : Nat} {m : Mem} {t : Ty} {c d : Nat} {e : Val}
    {es : List Val} (hx : m.st x = some ⟨true, some (.node t c d (e :: es))⟩) (hy : m.st y = none)
    (hc : m.alloc c = true) (hd : m.alloc d = true) :
    Step P m (.scopeD x f (.letd y f (.popFront x) .skip))
      (.ok ((m.set x ⟨true, some (.node t c d es)⟩).set y ⟨e.owns, some e⟩)
        (.scopeD x f (.scopeD y f .skip))) :=
  Step.scopeDIn (Step.letd hy (EvalR.popFront hx hc hd))

/-- ... and with every element gone the empty `Vec` is freed as any binding's
    value is: the frame's one step leaves `scope x`. -/
theorem scopeD_end_empty {P : Prog} {x : Var} {f : Nat} {m : Mem} {t : Ty} {c d : Nat}
    (hx : m.st x = some ⟨true, some (.node t c d [])⟩) :
    Step P m (.scopeD x f .skip) (.ok m (.scope x .skip)) ∧
      ∀ r, Step P m (.scopeD x f .skip) r → r = .ok m (.scope x .skip) := by
  refine ⟨Step.scopeDEmpty hx, fun r h => ?_⟩
  cases h with
  | scopeDIn hs => exact (skip_no_step hs).elim
  | scopeDEnd h hv => rw [hx] at h; cases h; cases hv
  | scopeDMoved hm => rw [hx] at hm; cases hm
  | scopeDDrain h => rw [hx] at h; cases h
  | scopeDEmpty _ => rfl
  | scopeDP hs _ _ => exact (skip_no_step hs).elim
  | scopeDPDrain hs _ => exact (skip_no_step hs).elim
  | scopeDPMoved hs _ => exact (skip_no_step hs).elim
  | waitPanic hw => exact hw.elim

/-- …and on the panic path, one step: a panic out of the body with `x`
    still owning a `Vec` stops at the frame, and leaves the frame at its end
    again (to drain what is left, `scopeD_end_drains`) followed by the panic.
    The body may be the drain's own (an element's frame whose destructor
    panicked), so the same step takes the drain on past that element. -/
theorem scopeD_panic_drains {P : Prog} {x : Var} {f : Nat} {m m1 : Mem} {s : Stmt} {t : Ty}
    {c d : Nat} {es : List Val} (hs : Step P m s (.panic m1))
    (hx : m1.st x = some ⟨true, some (.node t c d es)⟩) :
    Step P m (.scopeD x f s) (.ok m1 (.seq (.scopeD x f .skip) .panic)) :=
  Step.scopeDPDrain hs hx

/-- A2-drop.3b: what a typed `letd` binds: a destructor value (a struct or
    an enum made here, or a value of a destructor type moved in), or a
    `Vec` of destructor values, whose elements hold no views (`LetdTy`); its
    scope is a destructor frame of that type (`scopeD_end_runs_dtor`,
    `scopeD_end_drains`).  Agora #616: a value of ANOTHER destructor type
    `Ty.dtor g t` moves in only where that is `g`'s drop (`LetdFn`): `g` is
    a struct's glue with an impl, `f` its fields' glue, and the scope starts
    with the impl's call on the new binding (`letd_retype`). -/
theorem letd_binds {P : Prog} {Γ Δ : Ctx} {F : List Var} {x : Var} {f : Nat} {r : Rhs} {s : Stmt}
    (h : StmtT P Γ F (.letd x f r s) Δ) :
    ∃ Γ0 E Γ1 t τ, RhsT Γ0 F r E Γ1 ∧ LetdTy f t E.ty τ ∧ t.isStruct = true ∧ LetdFn P f t E.ty x s := by
  generalize hst : Stmt.letd x f r s = st at h
  induction h with
  | letd _ _ _ hr _ hty hst' _ hok _ _ _ _ => cases hst; exact ⟨_, _, _, _, _, hr, hty, hst', hok⟩
  | sub _ _ _ ih => exact ih hst
  | _ => cases hst

/-- A2-drop.3b: a typed `vec_free` releases elements that own no destructor
    value: in the context it is typed in, its `Vec`'s element type is free
    of one.  A `Vec` of destructor values is not freed, it is drained at its
    binding's end. -/
theorem free_dtor_free {P : Prog} {Γ Δ : Ctx} {F : List Var} {x : Var}
    (h : StmtT P Γ F (.free x) Δ) :
    ∃ (E : Entry) (t : Ty), Γ x = some E ∧ E.ty = .vec t ∧ t.dtorFree = true := by
  generalize hst : Stmt.free x = st at h
  induction h with
  | free hx _ _ hty _ _ hdf => cases hst; exact ⟨_, _, hx, hty, hdf⟩
  | @sub Γa _ _ _ _ _ hw _ _ ih =>
    obtain ⟨E', t, hx', hty, hdf⟩ := ih hst
    obtain ⟨hn, hE⟩ := hw.1 x
    cases hg : Γa x with
    | none => rw [hn.mp hg] at hx'; cases hx'
    | some E => exact ⟨E, t, rfl, by rw [← (hE E E' hg hx').ty]; exact hty, hdf⟩
  | _ => cases hst

/-- A2-drop.3b: a typed change of a `Vec`'s elements that drops some
    (`vec_truncate`, `vec_clear`, `vec_set`) drops no destructor value: in
    the context it is typed in, the `Vec`'s element type is free of one. -/
theorem edit_drops_dtor_free {P : Prog} {Γ Δ : Ctx} {F : List Var} {b : Bool} {x : Var} {op : Edit}
    (h : StmtT P Γ F (.edit b x op) Δ) (hd : op.drops = true) :
    ∃ (E : Entry) (t : Ty), Γ x = some E ∧ E.ty = .vec t ∧ t.dtorFree = true := by
  generalize hst : Stmt.edit b x op = st at h
  induction h with
  | editB hx _ _ hty _ _ _ _ _ _ _ _ hdf => cases hst; exact ⟨_, _, hx, hty, hdf hd⟩
  | editBV hx _ _ hty _ _ _ _ _ _ _ _ _ _ hdf => cases hst; exact ⟨_, _, hx, hty, hdf hd⟩
  | @sub Γa _ _ _ _ _ hw _ _ ih =>
    obtain ⟨E', t, hx', hty, hdf⟩ := ih hst
    obtain ⟨hn, hE⟩ := hw.1 x
    cases hg : Γa x with
    | none => rw [hn.mp hg] at hx'; cases hx'
    | some E => exact ⟨E, t, rfl, by rw [← (hE E E' hg hx').ty]; exact hty, hdf⟩
  | _ => cases hst

/-- A2-drop.3b: the element a typed `withElem` checks out owns no destructor
    value (its binding is no `letd`'s): in the context it is typed in, the
    `Vec`'s element type is free of one. -/
theorem withElem_dtor_free {P : Prog} {Γ Δ : Ctx} {F : List Var} {v x : Var} {i : Expr} {s : Stmt}
    (h : StmtT P Γ F (.withElem v i x s) Δ) :
    ∃ (Ev : Entry) (t : Ty), Γ v = some Ev ∧ Ev.ty = .vec t ∧ t.dtorFree = true := by
  generalize hst : Stmt.withElem v i x s = st at h
  induction h with
  | @withElem Γ _ _ _ _ _ _ _ _ Ev _ _ _ _ hv _ _ _ _ hr _ _ _ _ hdf _ _ =>
    cases hst
    cases hr with
    | @pop _ E0 t hy _ hty _ _ _ =>
      simp only [A2.kill, hv, Option.map_some, Option.some.injEq] at hy
      subst hy
      rw [killE_ty] at hty
      refine ⟨Ev, t, hv, hty, ?_⟩
      cases t <;> first | rfl | exact hdf
  | @sub Γa _ _ _ _ _ hw _ _ ih =>
    obtain ⟨E', t, hx', hty, hdf⟩ := ih hst
    obtain ⟨hn, hE⟩ := hw.1 v
    cases hg : Γa v with
    | none => rw [hn.mp hg] at hx'; cases hx'
    | some E => exact ⟨E, t, rfl, by rw [← (hE E E' hg hx').ty]; exact hty, hdf⟩
  | _ => cases hst

/-- A2-drop.3b: a typed destructor frame's binding, in the context the frame
    is typed in: an owner of the destructor type `Ty.dtor f t`, or of a `Vec`
    of such values whose elements hold no views; `f` is a `DtorOK` destructor
    of `Ty.dtor f t`, a struct's or an enum's. -/
theorem scopeD_typed {P : Prog} {Γ Δ : Ctx} {F : List Var} {x : Var} {f : Nat} {s : Stmt}
    (h : StmtT P Γ F (.scopeD x f s) Δ) :
    ∃ (E : Entry) (t : Ty), Γ x = some E ∧ E.mode = .own ∧ ScopeDTy f t E.ty ∧
      DropFnOK P f t ∧ t.isStruct = true := by
  generalize hst : Stmt.scopeD x f s = st at h
  induction h with
  | scopeD hE _ _ _ _ _ _ _ =>
    cases hst
    obtain ⟨E, t, hx, hmo, hty, _, hok, hstr⟩ := hE
    exact ⟨E, t, hx, hmo, hty, hok, hstr⟩
  | @sub Γa _ _ _ _ _ hw _ _ ih =>
    obtain ⟨E', t, hx', hmo, hty, hok, hstr⟩ := ih hst
    obtain ⟨hn, hE⟩ := hw.1 x
    cases hg : Γa x with
    | none => rw [hn.mp hg] at hx'; cases hx'
    | some E =>
      have hw' := hE E E' hg hx'
      exact ⟨E, t, rfl, by rw [← hw'.mode]; exact hmo, by rw [← hw'.ty]; exact hty, hok, hstr⟩
  | _ => cases hst

/-- **A2-drop.3b: what a typed destructor frame's binding owns says which
    step its end takes.** In a state the invariant holds of, a value that is
    no node is of the destructor type `Ty.dtor f t` (`scopeD_end_runs_dtor`'s
    step runs `f`, a destructor of that type, on it), and a node is a `Vec`
    of such values, whose elements are of that type (`scopeD_end_drains` /
    `scopeD_end_empty`'s steps drain it). -/
theorem scopeD_frame_value {P : Prog} {Γ Δ : Ctx} {F : List Var} {x : Var} {f : Nat} {s : Stmt}
    {m : Mem} {v : Val} (ht : StmtT P Γ F (.scopeD x f s) Δ) (hi : MInv m Γ)
    (hx : m.st x = some ⟨true, some v⟩) :
    ∃ (E : Entry) (t : Ty), Γ x = some E ∧ DropFnOK P f t ∧
      ((v.isNode = false ∧ E.ty = .dtor f t) ∨
        (∃ c d es, v = .node (.dtor f t) c d es ∧ E.ty = .vec (.dtor f t) ∧
          ∀ e ∈ es, WFv (.dtor f t) e ∧ e.isNode = false)) := by
  obtain ⟨E, t, hE, hmo, hty, hok, hstr⟩ := scopeD_typed ht
  have hw := hi.own_wfv hE (by rw [hmo]; rfl) hx
  refine ⟨E, t, hE, hok, ?_⟩
  rcases hty.shape hstr hw with ⟨hn, he⟩ | ⟨c, d, es, hv, he, _⟩
  · exact Or.inl ⟨hn, he⟩
  · refine Or.inr ⟨c, d, es, hv, he, fun e hmem => ?_⟩
    rw [he, hv] at hw
    cases hw with
    | node hes =>
      have hwe := hes e hmem
      refine ⟨hwe, ?_⟩
      rcases (ScopeDTy.shape (f := f) (t := t) (Or.inl rfl) hstr hwe) with ⟨hn, _⟩ | ⟨_, _, _, _, h', _⟩
      · exact hn
      · cases h'

/-- A2-drop.3c: a typed closure or trait-object literal's environment holds
    no destructor value, at any depth: a package's drop releases its
    environment running no code, so one that would hold a destructor value is
    refused (`Cross.Fits`). -/
theorem pack_env_dtor_free {Γ Γ1 : Ctx} {F : List Var} {fs : List Nat} {te : Ty} {ms : List Nat}
    {y : Var} {cs : List (Var × PMode × Ty)} {E : Entry}
    (h : RhsT Γ F (.pack fs te ms y cs) E Γ1) : te.holdsDtor = false ∧ te.dtorFree = true := by
  cases h with
  | pack _ _ _ _ _ hq =>
    refine ⟨hq.2.2.2, ?_⟩
    have := hq.2.2.2
    rw [Ty.holdsDtor_eq_not_free] at this
    simpa using this

/-- ... and so does every package in a well-formed tree, however deep it
    lies (a field, an element, another package's environment). -/
theorem _root_.A2.WFv.pkg_env_dtor_free {τ : Ty} {v : Val} (hw : WFv τ v)
    {fs : List Nat} {te : Ty} {ms : List Nat} {e : Val} {cs : List (Var × PMode × Ty)}
    (hs : Sub (.pkg fs te ms e cs) v) : te.holdsDtor = false := by
  induction hw with
  | int => cases hs
  | view => cases hs
  | node _ ih =>
    cases hs with
    | child he h => exact ih _ he h
  | pair _ _ iha ihb =>
    cases hs with
    | fst h => exact iha h
    | snd h => exact ihb h
  | inl _ ih => cases hs with | inl h => exact ih h
  | inr _ ih => cases hs with | inr h => exact ih h
  | pkg _ hq ih =>
    cases hs with
    | refl => exact hq.2.2.2
    | pkg h => exact ih h
  | arc _ _ => cases hs
  | lk => cases hs
  | cell => cases hs
  | dtor _ _ ih => exact ih hs

/-- **A2-drop.3c: in a running configuration no package an owner's slot
    holds, at any depth of its tree, has an environment that holds a
    destructor value** (one in a block's payload: `blk_pkgs_env_dtor_free`).
    So the environment a closure's or a trait object's drop releases, where
    an owner's tree is dropped (a binding's end, a `Vec`'s element, an
    assignment's old value, a panic's unwind), holds no destructor value. -/
theorem pkgs_env_dtor_free {m : Mem} {Γ : Ctx} (hi : MInv m Γ) {x : Var} {E : Entry}
    (hx : Γ x = some E) (hm : E.mode.ownSlot = true) {o : Bool} {T : Val}
    (hsl : m.st x = some ⟨o, some T⟩)
    {fs : List Nat} {te : Ty} {ms : List Nat} {e : Val} {cs : List (Var × PMode × Ty)}
    (hs : Sub (.pkg fs te ms e cs) T) : te.holdsDtor = false :=
  (hi.own_wfv hx hm hsl).pkg_env_dtor_free hs

/-- The payload types of the shares (`Arc`, lock, cell) that occur in a
    type, at any depth: in fields, payloads and elements, under views and
    destructor types, and inside other payloads. -/
def payloads : Ty → List Ty
  | .arc t => t :: payloads t
  | .lk t => t :: payloads t
  | .cell t => t :: payloads t
  | .vec t => payloads t
  | .slice t => payloads t
  | .dtor _ t => payloads t
  | .prod a b => payloads a ++ payloads b
  | .sum a b => payloads a ++ payloads b
  | .int => []
  | .fn _ _ => []

/-- A2-drop.3d: a well-formed type's share payloads own no destructor value. -/
theorem ok_payloads_free {t : Ty} (h : t.ok = true) : ∀ u ∈ payloads t, u.dtorFree = true := by
  induction t with
  | int => simp [payloads]
  | fn _ _ => simp [payloads]
  | vec t ih => simpa only [payloads] using ih (Ty.ok_vec_elem h)
  | slice t ih => simpa only [payloads] using ih (Ty.ok_slice h).1
  | arc t ih =>
    simp only [payloads, List.mem_cons]
    rintro u (rfl | hu)
    · exact Ty.ok_arc_free h
    · exact ih (Ty.ok_arc h).1 u hu
  | lk t ih =>
    simp only [payloads, List.mem_cons]
    rintro u (rfl | hu)
    · exact Ty.ok_lk_free h
    · exact ih (Ty.ok_lk h).1 u hu
  | cell t ih =>
    simp only [payloads, List.mem_cons]
    rintro u (rfl | hu)
    · exact Ty.ok_cell_free h
    · exact ih (Ty.ok_cell h).1 u hu
  | dtor _ t ih =>
    simp only [Ty.ok, Bool.and_eq_true] at h
    simpa only [payloads] using ih h.2
  | prod a b iha ihb =>
    simp only [payloads, List.mem_append]
    rintro u (hu | hu)
    · exact iha (Ty.ok_prod h).1 u hu
    · exact ihb (Ty.ok_prod h).2 u hu
  | sum a b iha ihb =>
    simp only [payloads, List.mem_append]
    rintro u (hu | hu)
    · exact iha (Ty.ok_sum h).1 u hu
    · exact ihb (Ty.ok_sum h).2 u hu

/-- A2-drop.3d, of types: in a running configuration, the payload type of
    every share in a binding's type (an `Arc`'s, a lock's, a cell's, a
    channel's queue; not those inside a closure type, whose environment the
    type does not name) owns no destructor value.  So a check-out binding
    (`withLock`, `withCell`: the lock's payload type) is of a type that
    holds none.  The fact about the blocks themselves is `blocks_dtor_free`. -/
theorem shares_dtor_free {m : Mem} {Γ : Ctx} (hi : MInv m Γ) {x : Var} {E : Entry}
    (hx : Γ x = some E) : ∀ u ∈ payloads E.ty, u.dtorFree = true :=
  ok_payloads_free (hi.tyok hx)

/-- **A2-drop.3d: in a running configuration no block's payload owns a
    destructor value** (the invariant carries it, `MInv.blocks`): every
    block, whatever holds its shares (a binding, a closure's environment,
    another block's payload).  So the sweep that frees a block when its last
    share goes, which runs no code, releases no destructor value. -/
theorem blocks_dtor_free {m : Mem} {Γ : Ctx} (hi : MInv m Γ) {k : Nat} {bl : Blk}
    (hk : m.blk k = some bl) : bl.ty.dtorFree = true :=
  (hi.blocks k bl hk).2.2.2.2

/-- A2-drop.3c, in a block: a package in a block's payload (a channel of
    closures, a `Locked` closure, an `Arc` of a `sync` one), however deep,
    has an environment that holds no destructor value. -/
theorem blk_pkgs_env_dtor_free {m : Mem} {Γ : Ctx} (hi : MInv m Γ) {k : Nat} {bl : Blk}
    (hk : m.blk k = some bl) {p : Val} (hp : bl.pay = some p)
    {fs : List Nat} {te : Ty} {ms : List Nat} {e : Val} {cs : List (Var × PMode × Ty)}
    (hs : Sub (.pkg fs te ms e cs) p) : te.holdsDtor = false :=
  (((hi.blocks k bl hk).2.2.1 p hp).1).pkg_env_dtor_free hs

/-- A2-drop.3d: `arc_new`, a lock's and a library handle's constructor take
    a value that owns no destructor value. -/
theorem share_new_dtor_free {Γ Γ1 : Ctx} {F : List Var} {t : Ty} {y : Var} {E : Entry} :
    (RhsT Γ F (.arcNew t y) E Γ1 → t.dtorFree = true) ∧
    (RhsT Γ F (.lockNew t y) E Γ1 → t.dtorFree = true) ∧
    (RhsT Γ F (.cellNew t y) E Γ1 → t.dtorFree = true) := by
  refine ⟨fun h => ?_, fun h => ?_, fun h => ?_⟩
  · cases h with | arcNew _ _ _ hdf _ _ _ => exact hdf
  · cases h with | lockNew _ _ _ hdf _ _ => exact hdf
  · cases h with | cellNew _ _ _ hdf _ _ => exact hdf

/-- A2-drop.3b: in a running configuration, a binding whose type is a `Vec`
    has elements that own no destructor value, or are of a destructor type
    themselves: the drained `Vec` (`Ty.vecD`), which only a binding's own type
    may be (`vecs_dtor_free`: anywhere else in a type a `Vec`'s elements own
    none).  A `Vec` of the second kind is `letd`'s (`letv` refuses it), and
    its frame's end drains it (`scopeD_end_drains`); what any other `Vec`'s
    drop releases holds no destructor value: no closure's environment does
    (`pkgs_env_dtor_free`) and no block's payload (`blocks_dtor_free`). -/
theorem vec_elems_dtor_free {m : Mem} {Γ : Ctx} (hi : MInv m Γ) {x : Var} {E : Entry} {t : Ty}
    (hx : Γ x = some E) (ht : E.ty = .vec t) : t.dtorFree = true ∨ t.hasDtor = true := by
  have h := hi.tyok hx; rw [ht] at h; exact Ty.ok_vec_free h

/-- The element types of the `Vec`s that occur in a type, at any depth:
    in fields and payloads, under views, shares and destructor types. -/
def vecElems : Ty → List Ty
  | .vec t => t :: vecElems t
  | .slice t => vecElems t
  | .arc t => vecElems t
  | .lk t => vecElems t
  | .cell t => vecElems t
  | .dtor _ t => vecElems t
  | .prod a b => vecElems a ++ vecElems b
  | .sum a b => vecElems a ++ vecElems b
  | .int => []
  | .fn _ _ => []

/-- A well-formed type that is not itself a drained `Vec` has no `Vec` of
    destructor values anywhere in it. -/
theorem ok_vecElems_free {t : Ty} (h : t.ok = true) (hd : t.vecD = false) :
    ∀ u ∈ vecElems t, u.dtorFree = true := by
  induction t with
  | int => simp [vecElems]
  | fn _ _ => simp [vecElems]
  | vec t ih =>
    have he := Ty.ok_vec_elem h
    have hnd := Ty.ok_vec_notVecD h
    simp only [Ty.vecD_vec, Bool.not_eq_false'] at hd
    simp only [vecElems, List.mem_cons]
    rintro u (rfl | hu)
    · exact hd
    · exact ih he hnd u hu
  | slice t ih =>
    simp only [Ty.ok, Bool.and_eq_true, Bool.not_eq_true'] at h; simpa only [vecElems] using ih h.1.1 h.2
  | arc t ih =>
    simp only [Ty.ok, Bool.and_eq_true, Bool.not_eq_true'] at h; simpa only [vecElems] using ih h.1.1.1 h.1.2
  | lk t ih =>
    simp only [Ty.ok, Bool.and_eq_true, Bool.not_eq_true'] at h; simpa only [vecElems] using ih h.1.1.1 h.1.2
  | cell t ih =>
    simp only [Ty.ok, Bool.and_eq_true, Bool.not_eq_true'] at h; simpa only [vecElems] using ih h.1.1.1 h.1.2
  | dtor _ t ih =>
    simp only [Ty.ok, Bool.and_eq_true] at h
    have hnd : t.vecD = false := by cases t <;> simp_all [Ty.isStruct]
    simpa only [vecElems] using ih h.2 hnd
  | prod a b iha ihb =>
    simp only [Ty.ok, Bool.and_eq_true, Bool.not_eq_true'] at h
    simp only [vecElems, List.mem_append]
    rintro u (hu | hu)
    · exact iha h.1.1.1 h.1.2 u hu
    · exact ihb h.1.1.2 h.2 u hu
  | sum a b iha ihb =>
    simp only [Ty.ok, Bool.and_eq_true, Bool.not_eq_true'] at h
    simp only [vecElems, List.mem_append]
    rintro u (hu | hu)
    · exact iha h.1.1.1 h.1.2 u hu
    · exact ihb h.1.1.2 h.2 u hu

/-- A2-drop.3b, the deep form: in a running configuration, every `Vec`
    occurring anywhere in a binding's type but at its top (a field's, a
    payload's, a share's payload's, an element's, …) has elements free of
    destructor values: the drained `Vec` is a binding's own type only. -/
theorem vecs_dtor_free {m : Mem} {Γ : Ctx} (hi : MInv m Γ) {x : Var} {E : Entry}
    (hx : Γ x = some E) : (E.ty.vecD = false → ∀ u ∈ vecElems E.ty, u.dtorFree = true) ∧
      (∀ t, E.ty = .vec t → ∀ u ∈ vecElems t, u.dtorFree = true) := by
  have hok := hi.tyok hx
  refine ⟨fun hd => ok_vecElems_free hok hd, fun t ht => ?_⟩
  rw [ht] at hok
  exact ok_vecElems_free (Ty.ok_vec_elem hok) (Ty.ok_vec_notVecD hok)

/-- A2-drop.3b: `vec_new` makes a `Vec` whose elements own no destructor
    value, or a drained one, of a destructor type's elements. -/
theorem new_dtor_free {Γ Γ1 : Ctx} {F : List Var} {t : Ty} {E : Entry}
    (h : RhsT Γ F (.new t) E Γ1) : t.dtorFree = true ∨ t.hasDtor = true := by
  cases h with | new h => exact Ty.ok_vec_free h

/-- A2-drop.3b: `Ty.holdsDtor` is deep, unfolded: a struct or an enum one
    field or payload of which holds a destructor value holds one.  (A fact
    about the definition; what it gives programs is `letv_owned_dtor_free`.) -/
theorem holdsDtor_deep {a b : Ty} (h : a.holdsDtor = true) :
    (Ty.prod a b).holdsDtor = true ∧ (Ty.prod b a).holdsDtor = true ∧
    (Ty.sum a b).holdsDtor = true ∧ (Ty.sum b a).holdsDtor = true := by
  simp [Ty.holdsDtor, h]

/-- A2-drop.3b: a typed `letv`'s owned value is of a type free of
    destructor values at any depth (`letv_owned_no_dtor`, with
    `Ty.holdsDtor_eq_not_free`): a destructor value two levels down, in a
    struct or an enum of no destructor type of its own, is bound by `letd`
    as what holds it is (`A2.DtorWitness.main4_safe`). -/
theorem letv_owned_dtor_free {P : Prog} {Γ Δ : Ctx} {F : List Var} {x : Var} {r : Rhs} {s : Stmt}
    (h : StmtT P Γ F (.letv x r s) Δ) :
    ∃ Γ0 E Γ1, RhsT Γ0 F r E Γ1 ∧ (E.mode = .own → E.ty.dtorFree = true) := by
  obtain ⟨Γ0, E, Γ1, hr, hnd⟩ := letv_owned_no_dtor h
  refine ⟨Γ0, E, Γ1, hr, fun hm => ?_⟩
  have h1 := hnd hm
  rw [Ty.holdsDtor_eq_not_free] at h1
  simpa using h1

end A2.Dtor


namespace A2.DtorWitness
open A2.DynCell (NoRootb noRootb_empty)

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
    destructor is its glue: `@ drop in self → i { = r 0 }` here (the
    elaboration's glue also lends the payload to `dfn`; the calculus checks
    a glue as it checks any destructor). -/
def OT : Ty := .sum DT .int
def ODT : Ty := .dtor 2 OT

def ofn : Fn where
  params := [(.inp, ODT)]
  resTy := .int
  resOwn := false
  lends := []
  rholds := []
  outHolds := []
  body := .assign 1 (.expr (.lit 0))
  nvars := 2

/-- A2-drop.3b: an enum one variant of which holds a struct holding a
    destructor value, `sum (prod DT int) int`: the destructor value is two
    levels down, under a struct of no destructor type of its own.  Its glue,
    `@ drop in self → i { = r 0 }` (the calculus checks a glue as it checks
    any destructor). -/
def AT : Ty := .prod DT .int
def ST : Ty := .sum AT .int
def SDT : Ty := .dtor 3 ST

def gfn : Fn where
  params := [(.inp, SDT)]
  resTy := .int
  resOwn := false
  lends := []
  rholds := []
  outHolds := []
  body := .assign 1 (.expr (.lit 0))
  nvars := 2

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

def P : Prog := [dfn, mk, ofn, gfn, glue, impl, glue2]

theorem dfn_not_thru : ¬ ThruFn P 0 := by
  intro h
  cases h with
  | here hf hb => simp [P] at hf; subst hf; simp [dfn, Stmt.hasThru] at hb
  | call hf hg _ => simp [P] at hf; subst hf; simp [dfn, Stmt.calls] at hg

theorem dtor_ok : DtorOK P 0 DT :=
  ⟨dfn, rfl, rfl, rfl, rfl, rfl, rfl, rfl, dfn_not_thru⟩

theorem drop_ok : DropFnOK P 0 T := Or.inl ⟨dtor_ok, fun _ _ _ => by decide⟩

/-- `: a 1  : b 2  :drop x ( pair a b )` -/
def main : Stmt := .letv 0 (.expr (.lit 1)) (.letv 1 (.expr (.lit 2)) (.letd 2 0 (.pair 0 1) .skip))

def EP : Entry := ⟨T, .own, true, [], [] ++ [], false, false⟩

theorem main_typed : ∃ Δ, StmtT P (fun _ => none) [] main Δ := by
  let K1 : Ctx := A2.setE (fun _ => none) 0 intE
  let K2 : Ctx := A2.setE K1 1 intE
  have hK1 : NoRootb K1 := noRootb_empty.setE (by simp [intE])
  have hK2 : NoRootb K2 := hK1.setE (by simp [intE])
  let ED : Entry := Entry.arm { EP with ty := DT, held := [] }
  have hED : ED.mode ≠ .rootb ∧ ED.dtor = false ∧ ED.dbind = false := by
    simp [ED, EP, Entry.arm, DT, T, Ty.dtorViews, Ty.hasDtor, Ty.holdsView]
  have hK3 : NoRootb (A2.setE K2 2 ED) := hK2.setE hED
  have hpair : RhsT K2 [] (.pair 0 1) EP K2 :=
    RhsT.pair (Ey := intE) (Ez := intE) (by simp [K2, K1, A2.setE, upd]) rfl PushArg.int
      (by simp [K2, K1, A2.setE, upd]) rfl PushArg.int (by simp [intE, Mode.ownSlot]) rfl rfl
  have hd := StmtT.letd (P := P) (Γ := K2) (Γ1 := K2) (F := []) (x := 2) (f := 0) (r := .pair 0 1)
    (s := .skip) (E := EP) (t := T) (H := []) rfl (by simp [K2, K1, A2.setE, upd]) (by simp) hpair rfl
    (Or.inl ⟨rfl, Or.inl rfl⟩) rfl rfl (letd_fn drop_ok) (HeldUp.refl _ _) StmtT.skip (hK3.endOK _)
  have h1 := StmtT.letv (P := P) (x := 1) (r := .expr (.lit 2)) (E := intE) (F := []) (Γ := K1) (Γ1 := K1)
    rfl (by simp [K1, A2.setE, upd]) (by simp) (RhsT.expr ExprT.lit) hd ((hK3.exitScope 2).endOK _)
  exact ⟨_, StmtT.letv (P := P) (x := 0) (r := .expr (.lit 1)) (E := intE) (F := []) (Γ := fun _ => none)
    (Γ1 := fun _ => none) rfl rfl (by simp) (RhsT.expr ExprT.lit) h1
    (((hK3.exitScope 2).exitScope 1).endOK _)⟩


/-! ### The destructor's own FnOK -/

def R0 : Entry := ⟨.int, .bor, false, [], [], false, false⟩
def Epar : Entry := ⟨DT, .rootb, true, [], [], false, false⟩

theorem dfn_body : StmtT P (sigCtx dfn) [] dfn.body
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

theorem dfn_ok : FnOK P dfn := by
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


theorem ofn_not_thru : ¬ ThruFn P 2 := by
  intro h
  cases h with
  | here hf hb => simp [P] at hf; subst hf; simp [ofn, Stmt.hasThru] at hb
  | call hf hg _ => simp [P] at hf; subst hf; simp [ofn, Stmt.calls] at hg

theorem odtor_ok : DtorOK P 2 ODT :=
  ⟨ofn, rfl, rfl, rfl, rfl, rfl, rfl, rfl, ofn_not_thru⟩

theorem odrop_ok : DropFnOK P 2 OT := Or.inl ⟨odtor_ok, fun _ _ h => by cases h⟩

theorem ofn_body : StmtT P (sigCtx ofn) [] ofn.body
    (setE (kill .replace false 1 (sigCtx ofn)) 1 { intE with mode := R0.mode }) := by
  have hc : sigCtx ofn 1 = some R0 := by simp [sigCtx, ofn, R0, resMode]
  have hflags : ∀ v E, sigCtx ofn v = some E → E.dtor = false ∧ E.dbind = false := by
    intro v E h
    rcases v with _ | _ | v <;> simp [sigCtx, ofn, paramE, resMode] at h <;> subst h <;> exact ⟨rfl, rfl⟩
  exact StmtT.assign (Ex := R0) (E := intE) hc (by simp) (Or.inr (Or.inr ⟨rfl, rfl⟩))
    (RhsT.expr ExprT.lit) rfl (by simp [intE, roots, Entry.vdeps, Mode.ownSlot]) (by simp [hc])
    (by
      intro p E hp hm d hd _
      rcases p with _ | _ | p <;> simp [sigCtx, ofn, paramE, resMode, ODT, OT, DT, T, Ty.hasFn] at hp <;>
        subst hp <;> simp [Entry.vdeps, Mode.ownSlot] at hd <;> simp at hm)
    (DtorSafe.of_none (fun v E h => (hflags v E h).1) _ _ _) rfl

theorem ofn_ok : FnOK P ofn := by
  refine ⟨rfl, by decide, by decide, rfl, by simp [ofn], ?_, by simp [ofn], by simp [ofn], by simp [ofn],
    by simp [ofn], by simp [ofn], ?_, _, ofn_body, ?_, ?_, ?_⟩
  · intro pt hpt; simp [ofn] at hpt; subst hpt; simp [ODT, OT, DT, T, Ty.ok, Ty.isStruct]
  · refine ⟨fun i hi hs _ => ?_, fun i hi b hb _ => ?_, fun h => by simp [ofn] at h⟩
    · simp [ofn] at hi; subst hi; simp [ofn] at hs
    · simp [ofn] at hi; subst hi; simp [ofn] at hb
  · intro v E h
    rcases v with _ | _ | v <;> simp [setE, upd, kill, killE, sigCtx, ofn, paramE, resMode, intE] at h <;>
      subst h <;> exact ⟨rfl, rfl⟩
  · exact ⟨{ intE with mode := R0.mode }, by simp [setE, upd, ofn], rfl, rfl, by simp [R0, resMode, ofn], by simp [intE], by simp [intE],
      by simp [ofn]⟩
  · intro i hi b hb; simp [ofn] at hi; subst hi; simp [ofn] at hb

theorem gfn_not_thru : ¬ ThruFn P 3 := by
  intro h
  cases h with
  | here hf hb => simp [P] at hf; subst hf; simp [gfn, Stmt.hasThru] at hb
  | call hf hg _ => simp [P] at hf; subst hf; simp [gfn, Stmt.calls] at hg

theorem gdtor_ok : DtorOK P 3 SDT :=
  ⟨gfn, rfl, rfl, rfl, rfl, rfl, rfl, rfl, gfn_not_thru⟩

theorem gdrop_ok : DropFnOK P 3 ST := Or.inl ⟨gdtor_ok, fun _ _ h => by cases h⟩

theorem gfn_body : StmtT P (sigCtx gfn) [] gfn.body
    (setE (kill .replace false 1 (sigCtx gfn)) 1 { intE with mode := R0.mode }) := by
  have hc : sigCtx gfn 1 = some R0 := by simp [sigCtx, gfn, R0, resMode]
  have hflags : ∀ v E, sigCtx gfn v = some E → E.dtor = false ∧ E.dbind = false := by
    intro v E h
    rcases v with _ | _ | v <;> simp [sigCtx, gfn, paramE, resMode] at h <;> subst h <;> exact ⟨rfl, rfl⟩
  exact StmtT.assign (Ex := R0) (E := intE) hc (by simp) (Or.inr (Or.inr ⟨rfl, rfl⟩))
    (RhsT.expr ExprT.lit) rfl (by simp [intE, roots, Entry.vdeps, Mode.ownSlot]) (by simp [hc])
    (by
      intro p E hp hm d hd _
      rcases p with _ | _ | p <;> simp [sigCtx, gfn, paramE, resMode, SDT, ST, AT, DT, T, Ty.hasFn] at hp <;>
        subst hp <;> simp [Entry.vdeps, Mode.ownSlot] at hd <;> simp at hm)
    (DtorSafe.of_none (fun v E h => (hflags v E h).1) _ _ _) rfl

theorem gfn_ok : FnOK P gfn := by
  refine ⟨rfl, by decide, by decide, rfl, by simp [gfn], ?_, by simp [gfn], by simp [gfn], by simp [gfn],
    by simp [gfn], by simp [gfn], ?_, _, gfn_body, ?_, ?_, ?_⟩
  · intro pt hpt; simp [gfn] at hpt; subst hpt; simp [SDT, ST, AT, DT, T, Ty.ok, Ty.isStruct]
  · refine ⟨fun i hi hs _ => ?_, fun i hi b hb _ => ?_, fun h => by simp [gfn] at h⟩
    · simp [gfn] at hi; subst hi; simp [gfn] at hs
    · simp [gfn] at hi; subst hi; simp [gfn] at hb
  · intro v E h
    rcases v with _ | _ | v <;> simp [setE, upd, kill, killE, sigCtx, gfn, paramE, resMode, intE] at h <;>
      subst h <;> exact ⟨rfl, rfl⟩
  · exact ⟨{ intE with mode := R0.mode }, by simp [setE, upd, gfn], rfl, rfl, by simp [R0, resMode, gfn], by simp [intE], by simp [intE],
      by simp [gfn]⟩
  · intro i hi b hb; simp [gfn] at hi; subst hi; simp [gfn] at hb

/-! ### The maker: a function whose owned result is a destructor value -/

def Rr : Entry := ⟨DT, .own, false, [], [], false, false⟩
def EDd : Entry := Entry.arm { EP with ty := DT, held := [] }

theorem EDd_eq : EDd = ⟨DT, .own, true, [], [], false, false⟩ := by
  simp [EDd, EP, Entry.arm, DT, T, Ty.dtorViews, Ty.hasDtor, Ty.holdsView]

theorem sig_mk : sigCtx mk = A2.setE (fun _ => none) 0 Rr := by
  funext v; rcases v with _ | v <;> simp [sigCtx, mk, resMode, Rr, A2.setE, upd]

theorem mk_typed : ∃ Δ, StmtT P (sigCtx mk) [] mk.body Δ ∧ NoRootb Δ ∧
    Δ 0 = some ⟨DT, .own, true, [], [], false, false⟩ := by
  rw [sig_mk]
  let S : Ctx := A2.setE (fun _ => none) 0 Rr
  have hS : NoRootb S := noRootb_empty.setE (by simp [Rr])
  let C1 : Ctx := A2.setE S 1 intE
  let C2 : Ctx := A2.setE C1 2 intE
  have hC2 : NoRootb C2 := (hS.setE (by simp [intE])).setE (by simp [intE])
  let C3 : Ctx := A2.setE C2 3 EDd
  have hC3 : NoRootb C3 := hC2.setE (by rw [EDd_eq]; simp)
  have hmv : RhsT C3 [] (.var 3) ⟨DT, .own, true, [], [], false, false⟩
      (A2.setE (kill .replace false 3 C3) 3 { EDd with live := false, dtor := false }) := by
    have := RhsT.moveOwn (Γ := C3) (F := []) (y := 3) (E := EDd) (by simp [C3, A2.setE, upd]) (by rw [EDd_eq])
      (by rw [EDd_eq]) (by simp) (hC3.noPin _) (DtorSafe.of_none (fun v E h => (hC3 v E h).2.1) _ _ _)
    rw [EDd_eq] at this ⊢; exact this
  let G1 : Ctx := A2.setE (kill .replace false 3 C3) 3 { EDd with live := false, dtor := false }
  have hG1 : NoRootb G1 := (hC3.kill _ _ _).setE (by rw [EDd_eq]; simp)
  have ha := StmtT.assign (P := P) (Γ := C3) (F := []) (x := 0) (r := .var 3) (Ex := Rr)
    (E := ⟨DT, .own, true, [], [], false, false⟩) (Γ1 := G1)
    (by simp [C3, C2, C1, S, A2.setE, upd]) (by simp) (Or.inl ⟨rfl, rfl⟩) hmv rfl
    (by simp [roots, Entry.vdeps, Mode.ownSlot]) (by simp [G1, C3, C2, C1, S, A2.setE, upd, kill]) (hC3.noPin _)
    (DtorSafe.of_none (fun v E h => (hG1 v E h).2.1) _ _ _) rfl
  let Da : Ctx := A2.setE (kill .replace false 0 G1) 0 { (⟨DT, .own, true, [], [], false, false⟩ : Entry) with mode := Rr.mode }
  have hDa : NoRootb Da := (hG1.kill _ _ _).setE (by simp [Rr])
  have hpair : RhsT C2 [] (.pair 1 2) EP C2 :=
    RhsT.pair (Ey := intE) (Ez := intE) (by simp [C2, C1, A2.setE, upd]) rfl PushArg.int
      (by simp [C2, A2.setE, upd]) rfl PushArg.int (by simp [intE, Mode.ownSlot]) rfl rfl
  have hd := StmtT.letd (P := P) (Γ := C2) (Γ1 := C2) (F := []) (x := 3) (f := 0) (r := .pair 1 2)
    (s := .assign 0 (.var 3)) (E := EP) (t := T) (H := []) rfl (by simp [C2, C1, S, A2.setE, upd]) (by simp)
    hpair rfl (Or.inl ⟨rfl, Or.inl rfl⟩) rfl rfl (letd_fn drop_ok) (HeldUp.refl _ _) ha (hDa.endOK _)
  have h2 := StmtT.letv (P := P) (x := 2) (r := .expr (.lit 2)) (E := intE) (F := []) (Γ := C1) (Γ1 := C1)
    rfl (by simp [C1, S, A2.setE, upd]) (by simp) (RhsT.expr ExprT.lit) hd ((hDa.exitScope 3).endOK _)
  have h1 := StmtT.letv (P := P) (x := 1) (r := .expr (.lit 1)) (E := intE) (F := []) (Γ := S) (Γ1 := S)
    rfl (by simp [S, A2.setE, upd]) (by simp) (RhsT.expr ExprT.lit) h2 (((hDa.exitScope 3).exitScope 2).endOK _)
  refine ⟨_, h1, ((hDa.exitScope 3).exitScope 2).exitScope 1, ?_⟩
  simp [Da, G1, C3, C2, C1, S, exitScope, A2.setE, upd, kill, killE, hits, Rr, Entry.vdeps, Mode.ownSlot]

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
  ⟨glue, DT, .int, rfl, rfl, by decide, rfl, rfl, rfl, rfl, rfl, rfl, glue_not_thru, 2, 3, _, rfl, rfl⟩

theorem gluedrop_ok : DropFnOK P 4 GT := Or.inr (Or.inl glue_glueOK)

def EG : Entry := ⟨GDT, .own, true, [], [], false, false⟩

theorem glue_body : ∃ Δ, StmtT P (sigCtx glue) [] glue.body Δ ∧
    (∀ v E, Δ v = some E → E.mode ≠ .rootb ∧ E.dtor = false ∧ E.dbind = false) ∧
    Δ 1 = some { intE with mode := R0.mode } := by
  have h0 : sigCtx glue 0 = some EG := by simp [sigCtx, glue, paramE, EG, GDT, GT, DT, T, Ty.hasFn]
  have h1 : sigCtx glue 1 = some R0 := by simp [sigCtx, glue, R0, resMode]
  have hS : NoRootb (sigCtx glue) := by
    intro v E h
    rcases v with _ | _ | v
    · rw [h0] at h; cases h; simp [EG]
    · rw [h1] at h; cases h; simp [R0]
    · simp [sigCtx, glue] at h
  let Ka : Ctx := A2.setE (A2.setE (A2.setE (kill .replace false 0 (sigCtx glue)) 0
    { EG with live := false, dtor := false }) 2 (compE EG DT)) 3 (compE EG .int)
  have hKa : NoRootb Ka :=
    (((hS.kill _ _ _).setE (by simp [EG])).setE (by simp [compE, DT])).setE (by simp [compE, intE])
  have hEx : compE EG DT = ⟨DT, .own, true, [], [], false, false⟩ := by
    simp [compE, DT, EG, ownHeld]
  let Kb : Ctx := A2.setE (kill .replace false 2 Ka) 2 { compE EG DT with live := false, dtor := false }
  have hKb : NoRootb Kb := (hKa.kill _ _ _).setE (by rw [hEx]; simp)
  have hmv : RhsT Ka [] (.var 2) ⟨(compE EG DT).ty, .own, true, [], (compE EG DT).held, false, false⟩ Kb :=
    RhsT.moveOwn (by simp [Ka, A2.setE, upd]) (by rw [hEx]) (by rw [hEx]) (by simp) (hKa.noPin _)
      (DtorSafe.of_none (fun v E h => (hKa v E h).2.1) _ _ _)
  let ED : Entry := Entry.arm { (⟨(compE EG DT).ty, .own, true, [], (compE EG DT).held, false, false⟩ : Entry)
    with ty := DT, held := (compE EG DT).held }
  have hED : ED = ⟨DT, .own, true, [], [], false, false⟩ := by
    simp only [ED]; rw [hEx]; simp [Entry.arm, DT, T, Ty.dtorViews, Ty.hasDtor, Ty.holdsView]
  let Kc : Ctx := A2.setE Kb 4 ED
  have hKc : NoRootb Kc := hKb.setE (by rw [hED]; simp)
  have hc1 : Kc 1 = some R0 := by
    simp [Kc, Kb, Ka, A2.setE, upd, A2.kill, h1, killE, hits, R0, Entry.vdeps]
  let Kd : Ctx := A2.setE (kill .replace false 1 Kc) 1 { intE with mode := R0.mode }
  have hKd : NoRootb Kd := (hKc.kill _ _ _).setE (by simp [intE, R0])
  have hasg : StmtT P Kc [] (.assign 1 (.expr (.lit 0))) Kd :=
    StmtT.assign (Ex := R0) (E := intE) hc1 (by simp) (Or.inr (Or.inr ⟨rfl, rfl⟩))
      (RhsT.expr ExprT.lit) rfl (by simp [intE, roots, Entry.vdeps, Mode.ownSlot]) (by simp [hc1])
      (hKc.noPin _) (DtorSafe.of_none (fun v E h => (hKc v E h).2.1) _ _ _) rfl
  have hlet := StmtT.letd (P := P) (Γ := Ka) (Γ1 := Kb) (F := []) (x := 4) (f := 0) (r := .var 2)
    (s := .assign 1 (.expr (.lit 0))) (t := T) (H := (compE EG DT).held) (τ := DT) rfl
    (by simp [Ka, A2.setE, upd, A2.kill, sigCtx, glue]) (by simp) hmv rfl
    (Or.inl ⟨rfl, Or.inr ⟨0, by rw [hEx]; rfl⟩⟩) rfl rfl (letd_fn drop_ok) (HeldUp.refl _ _) hasg (hKd.endOK _)
    (by simp [Stmt.assigns])
  have hun := StmtT.unpair (P := P) (Γ := sigCtx glue) (F := []) (y := 0) (x := 2) (z := 3)
    (s := .letd 4 0 (.var 2) (.assign 1 (.expr (.lit 0)))) (E := EG) (a := DT) (b := .int)
    rfl h0 rfl (Or.inl rfl) (Or.inr ⟨4, rfl, glue_glueOK⟩) (by simp)
    (by simp [sigCtx, glue]) (by simp [sigCtx, glue]) (by decide) (by simp) (by simp) hlet
    (hS.noPin _) (DtorSafe.of_none (fun v E h => (hS v E h).2.1) _ _ _)
    ((hKd.exitScope 4).endOK _) (((hKd.exitScope 4).exitScope 3).endOK _)
    (fun _ => by simp [Stmt.movedFirst, Stmt.assigns]) (fun h => by simp [Ty.holdsDtor] at h)
  refine ⟨_, hun, (((hKd.exitScope 4).exitScope 3).exitScope 2), ?_⟩
  simp [exitScope, upd, A2.kill, Kd, A2.setE, killE, hits, intE, Entry.vdeps, R0]

theorem glue_ok : FnOK P glue := by
  obtain ⟨Δ, hb, hfl, hr⟩ := glue_body
  refine ⟨rfl, by decide, by decide, rfl, by simp [glue], ?_, by simp [glue], by simp [glue], by simp [glue],
    by simp [glue], by simp [glue], ?_, Δ, hb, fun v E h => (hfl v E h).2, ?_, ?_⟩
  · intro pt hpt; simp [glue] at hpt; subst hpt; simp [GDT, GT, DT, T, Ty.ok, Ty.isStruct, Ty.owning, Ty.vecD]
  · refine ⟨fun i hi hs _ => ?_, fun i hi b hb _ => ?_, fun h => by simp [glue] at h⟩
    · simp [glue] at hi; subst hi; simp [glue, Stmt.movedFirst, Stmt.assigns]
    · simp [glue] at hi; subst hi; simp [glue] at hb
  · exact ⟨{ intE with mode := R0.mode }, by simpa [glue] using hr, rfl, rfl, by simp [R0, resMode, glue],
      by simp [intE], by simp [intE], by simp [glue]⟩
  · intro i hi b hb; simp [glue] at hi; subst hi; simp [glue] at hb

/-! ### A struct with its own `% Drop` beside a destructor field (Agora #616) -/

theorem impl_not_thru : ¬ ThruFn P 5 := by
  intro h
  cases h with
  | here hf hb => simp [P] at hf; subst hf; simp [impl, Stmt.hasThru] at hb
  | call hf hg _ => simp [P] at hf; subst hf; simp [impl, Stmt.calls] at hg

theorem impl_dtorOK : DtorOK P 5 GDT :=
  ⟨impl, rfl, rfl, rfl, rfl, rfl, rfl, rfl, impl_not_thru⟩

theorem impl_body : StmtT P (sigCtx impl) [] impl.body
    (setE (kill .replace false 1 (sigCtx impl)) 1 { intE with mode := R0.mode }) := by
  have hc : sigCtx impl 1 = some R0 := by simp [sigCtx, impl, R0, resMode]
  have hflags : ∀ v E, sigCtx impl v = some E → E.dtor = false ∧ E.dbind = false := by
    intro v E h
    rcases v with _ | _ | v <;> simp [sigCtx, impl, paramE, resMode] at h <;> subst h <;> exact ⟨rfl, rfl⟩
  exact StmtT.assign (Ex := R0) (E := intE) hc (by simp) (Or.inr (Or.inr ⟨rfl, rfl⟩))
    (RhsT.expr ExprT.lit) rfl (by simp [intE, roots, Entry.vdeps, Mode.ownSlot]) (by simp [hc])
    (by
      intro p E hp hm d hd _
      rcases p with _ | _ | p <;> simp [sigCtx, impl, paramE, resMode, GDT, GT, DT, T, Ty.hasFn] at hp <;>
        subst hp <;> simp [Entry.vdeps, Mode.ownSlot] at hd <;> simp at hm)
    (DtorSafe.of_none (fun v E h => (hflags v E h).1) _ _ _) rfl

theorem impl_ok : FnOK P impl := by
  refine ⟨rfl, by decide, by decide, rfl, by simp [impl], ?_, by simp [impl], by simp [impl], by simp [impl],
    by simp [impl], by simp [impl], ?_, _, impl_body, ?_, ?_, ?_⟩
  · intro pt hpt; simp [impl] at hpt; subst hpt; simp [GDT, GT, DT, T, Ty.ok, Ty.isStruct, Ty.vecD]
  · refine ⟨fun i hi hs _ => ?_, fun i hi b hb _ => ?_, fun h => by simp [impl] at h⟩
    · simp [impl] at hi; subst hi; simp [impl] at hs
    · simp [impl] at hi; subst hi; simp [impl] at hb
  · intro v E h
    rcases v with _ | _ | v <;> simp [setE, upd, kill, killE, sigCtx, impl, paramE, resMode, intE] at h <;>
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
  ⟨glue2, DT, .int, 2, 3, .lit 0, rfl, rfl, by decide, rfl, rfl, rfl, rfl, rfl, rfl, glue2_not_thru,
    glue_glueOK, impl_dtorOK, rfl⟩

theorem impldrop_ok : DropFnOK P 6 GT := Or.inr (Or.inr ⟨4, 5, glue2_implOK⟩)

def ES2 : Entry := ⟨SDT2, .own, true, [], [], false, false⟩

theorem glue2_body : ∃ Δ, StmtT P (sigCtx glue2) [] glue2.body Δ ∧
    (∀ v E, Δ v = some E → E.mode ≠ .rootb ∧ E.dtor = false ∧ E.dbind = false) ∧
    Δ 1 = some { intE with mode := R0.mode } := by
  have h0 : sigCtx glue2 0 = some ES2 := by simp [sigCtx, glue2, paramE, ES2, SDT2, GT, DT, T, Ty.hasFn]
  have h1 : sigCtx glue2 1 = some R0 := by simp [sigCtx, glue2, R0, resMode]
  have hS : NoRootb (sigCtx glue2) := by
    intro v E h
    rcases v with _ | _ | v
    · rw [h0] at h; cases h; simp [ES2]
    · rw [h1] at h; cases h; simp [R0]
    · simp [sigCtx, glue2] at h
  let Ka : Ctx := A2.setE (kill .replace false 0 (sigCtx glue2)) 0 { ES2 with live := false, dtor := false }
  have hKa : NoRootb Ka := (hS.kill _ _ _).setE (by simp [ES2])
  have hmv : RhsT (sigCtx glue2) [] (.var 0) ⟨ES2.ty, .own, true, [], ES2.held, false, false⟩ Ka :=
    RhsT.moveOwn h0 rfl rfl (by simp) (hS.noPin _) (DtorSafe.of_none (fun v E h => (hS v E h).2.1) _ _ _)
  let EW : Entry := Entry.arm { (⟨ES2.ty, .own, true, [], ES2.held, false, false⟩ : Entry) with ty := GDT, held := ES2.held }
  have hEW : EW = ⟨GDT, .own, true, [], [], false, false⟩ := by
    simp [EW, ES2, Entry.arm, GDT, GT, DT, T, Ty.dtorViews, Ty.hasDtor, Ty.holdsView]
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
  have hasg : StmtT P Kc [] (.assign 1 (.expr (.lit 0))) Kd :=
    StmtT.assign (Ex := R0) (E := intE) hc1 (by simp) (Or.inr (Or.inr ⟨rfl, rfl⟩))
      (RhsT.expr ExprT.lit) rfl (by simp [intE, roots, Entry.vdeps, Mode.ownSlot]) (by simp [hc1])
      (hKc.noPin _) (DtorSafe.of_none (fun v E h => (hKc v E h).2.1) _ _ _) rfl
  have hlc := StmtT.letcall (P := P) (Γ := Kb) (F := []) (x := 3) (f := 5) (args := [2])
    (s := .assign 1 (.expr (.lit 0))) rfl (by simp [Kb, Ka, A2.setE, upd, A2.kill, sigCtx, glue2]) (by simp)
    hcall hasg (hKd.endOK _)
    (fun fn' hf' ho _ => by simp [P] at hf'; subst hf'; simp [impl] at ho)
  have hlet := StmtT.letd (P := P) (Γ := sigCtx glue2) (Γ1 := Ka) (F := []) (x := 2) (f := 4) (r := .var 0)
    (s := .letcall 3 5 [2] (.assign 1 (.expr (.lit 0)))) (t := GT) (H := ES2.held) (τ := GDT) rfl
    (by simp [sigCtx, glue2]) (by simp) hmv rfl
    (Or.inl ⟨rfl, Or.inr ⟨6, rfl⟩⟩) rfl rfl
    ⟨gluedrop_ok, fun g hg _ => by
      have hg6 : g = 6 := (Ty.dtor.inj hg).1.symm
      subst hg6
      exact ⟨5, 3, _, glue2_implOK, rfl⟩⟩
    (HeldUp.refl _ _) hlc ((hKd.exitScope 3).endOK _) (by simp [Stmt.assigns])
  refine ⟨_, hlet, ((hKd.exitScope 3).exitScope 2), ?_⟩
  simp [exitScope, upd, A2.kill, Kd, A2.setE, killE, hits, intE, Entry.vdeps, R0]

theorem glue2_ok : FnOK P glue2 := by
  obtain ⟨Δ, hb, hfl, hr⟩ := glue2_body
  refine ⟨rfl, by decide, by decide, rfl, by simp [glue2], ?_, by simp [glue2], by simp [glue2], by simp [glue2],
    by simp [glue2], by simp [glue2], ?_, Δ, hb, fun v E h => (hfl v E h).2, ?_, ?_⟩
  · intro pt hpt; simp [glue2] at hpt; subst hpt; simp [SDT2, GT, DT, T, Ty.ok, Ty.isStruct, Ty.owning, Ty.vecD]
  · refine ⟨fun i hi hs _ => ?_, fun i hi b hb _ => ?_, fun h => by simp [glue2] at h⟩
    · simp [glue2] at hi; subst hi; simp [glue2, Stmt.movedFirst, Stmt.assigns]
    · simp [glue2] at hi; subst hi; simp [glue2] at hb
  · exact ⟨{ intE with mode := R0.mode }, by simpa [glue2] using hr, rfl, rfl, by simp [R0, resMode, glue2],
      by simp [intE], by simp [intE], by simp [glue2]⟩
  · intro i hi b hb; simp [glue2] at hi; subst hi; simp [glue2] at hb

theorem prog_ok : ProgOK P := by
  intro fn hfn
  simp only [P, List.mem_cons, List.mem_nil_iff, or_false] at hfn
  rcases hfn with rfl | rfl | rfl | rfl | rfl | rfl | rfl
  · exact dfn_ok
  · exact mk_ok
  · exact ofn_ok
  · exact gfn_ok
  · exact glue_ok
  · exact impl_ok
  · exact glue2_ok

/-! ### The caller: `: DT y ( mk )  :drop z y` -/

def main2 : Stmt := .letcall 0 1 [] (.letd 1 0 (.var 0) .skip)

def Ecr : Entry := ⟨DT, .own, true, [], [], false, false⟩

theorem main2_typed : ∃ Δ, StmtT P (fun _ => none) [] main2 Δ := by
  have hpost : callPost (fun _ => none) mk [] = fun _ => none := by
    funext v; simp [callPost, callPostAux, mk, killNames, mutNames, argNames]
  have hres : callRes (fun _ => none) mk [] = Ecr := by
    simp [callRes, mk, resMode, Ecr, heldOfArgs, ownHeld, allKinds, argNames]
  have hc : CallT P (fun _ => none) [] 1 [] Ecr (fun _ => none) := by
    refine ⟨mk, rfl, rfl, fun i hi => by simp [mk] at hi, ?_, CallDtorSafe.of_none (fun _ _ h => by cases h) _ _,
      hres.symm, hpost.symm, fun _ => by simp [callR]⟩
    intro d hd; simp [mutNames, argNames] at hd
  let K : Ctx := A2.setE (fun _ => none) 0 Ecr
  have hK : NoRootb K := noRootb_empty.setE (by simp [Ecr])
  have hmv := RhsT.moveOwn (Γ := K) (F := []) (y := 0) (E := Ecr) (by simp [K, A2.setE, upd]) rfl rfl (by simp)
    (hK.noPin _) (DtorSafe.of_none (fun v E h => (hK v E h).2.1) _ _ _)
  let K1 : Ctx := A2.setE (kill .replace false 0 K) 0 { Ecr with live := false, dtor := false }
  have hK1 : NoRootb K1 := (hK.kill _ _ _).setE (by simp [Ecr])
  let ED2 : Entry := Entry.arm { (⟨Ecr.ty, .own, true, [], Ecr.held, false, false⟩ : Entry) with ty := DT, held := Ecr.held }
  have hED2 : ED2.mode ≠ .rootb ∧ ED2.dtor = false ∧ ED2.dbind = false := by
    simp [ED2, Ecr, Entry.arm, DT, T, Ty.dtorViews, Ty.hasDtor, Ty.holdsView]
  have hK2 : NoRootb (A2.setE K1 1 ED2) := hK1.setE hED2
  have hd := StmtT.letd (P := P) (Γ := K) (Γ1 := K1) (F := []) (x := 1) (f := 0) (r := .var 0) (s := .skip)
    (t := T) (H := Ecr.held) rfl (by simp [K, A2.setE, upd]) (by simp) hmv rfl (Or.inl ⟨rfl, Or.inr ⟨_, rfl⟩⟩) rfl rfl (letd_fn drop_ok)
    (HeldUp.refl _ _) StmtT.skip (hK2.endOK _)
  exact ⟨_, StmtT.letcall (P := P) (Γ := fun _ => none) (F := []) (x := 0) (f := 1) (args := [])
    (s := .letd 1 0 (.var 0) .skip) (E := Ecr) (Γ1 := fun _ => none) rfl rfl (by simp) hc hd
    ((hK2.exitScope 1).endOK _)
    (fun fn hf _ _ => by simp [P] at hf; subst hf; simp [Stmt.movedFirst, Stmt.assigns])⟩

theorem prog_codes : ProgCodes P := by
  intro fn hfn
  simp only [P, List.mem_cons, List.mem_nil_iff, or_false] at hfn
  rcases hfn with rfl | rfl | rfl | rfl | rfl | rfl | rfl <;>
    simp [dfn, mk, ofn, gfn, glue, impl, glue2, Stmt.codesOK, Rhs.codeOK]

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

def EO : Entry := ⟨OT, .own, true, [], [], false, false⟩

theorem main3_typed : ∃ Δ, StmtT P (fun _ => none) [] main3 Δ := by
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
      (by simp [K2, K1, A2.setE, upd]) rfl PushArg.int (by simp [intE, Mode.ownSlot]) rfl rfl
  -- the destructor value moves into the option
  let K4 : Ctx := A2.setE (kill .replace false 2 K3) 2 { ED with live := false, dtor := false }
  have hK4 : NoRootb K4 := (hK3.kill _ _ _).setE (by rw [hEDe]; simp)
  have hpush : PushArg K3 [] 2 ED ED.ty ED.held K4 := by
    rw [hEDe]
    have := PushArg.move (Γ := K3) (F := []) (y := 2) (E := ⟨DT, .own, true, [], [], false, false⟩) (t := DT)
      rfl rfl (by simp) (hK3.noPin _) (DtorSafe.of_none (fun v E h => (hK3 v E h).2.1) _ _ _)
    exact this
  have hinl : RhsT K3 [] (.inl 2 .int) EO K4 := by
    have := RhsT.inl (Γ := K3) (F := []) (y := 2) (b := .int) (Ey := ED) (Γ1 := K4) (D := ED.held)
      (by simp [K3, A2.setE, upd]) (by rw [hEDe]) hpush rfl (by rw [hEDe]; rfl) rfl
    rw [hEDe] at this; exact this
  let EOd : Entry := Entry.arm { EO with ty := ODT, held := [] }
  have hEOd : EOd.mode ≠ .rootb ∧ EOd.dtor = false ∧ EOd.dbind = false := by
    simp [EOd, EO, Entry.arm, ODT, OT, DT, T, Ty.dtorViews, Ty.hasDtor, Ty.holdsView]
  have hK5 : NoRootb (A2.setE K4 3 EOd) := hK4.setE hEOd
  have hdo := StmtT.letd (P := P) (Γ := K3) (Γ1 := K4) (F := []) (x := 3) (f := 2) (r := .inl 2 .int)
    (s := .skip) (E := EO) (t := OT) (H := []) rfl (by simp [K3, K2, K1, A2.setE, upd]) (by simp) hinl rfl
    (Or.inl ⟨rfl, Or.inl rfl⟩) rfl rfl (letd_fn odrop_ok) (HeldUp.refl _ _) StmtT.skip (hK5.endOK _)
  have hd := StmtT.letd (P := P) (Γ := K2) (Γ1 := K2) (F := []) (x := 2) (f := 0) (r := .pair 0 1)
    (s := .letd 3 2 (.inl 2 .int) .skip) (E := EP) (t := T) (H := []) rfl (by simp [K2, K1, A2.setE, upd])
    (by simp) hpair rfl (Or.inl ⟨rfl, Or.inl rfl⟩) rfl rfl (letd_fn drop_ok) (HeldUp.refl _ _) hdo ((hK5.exitScope 3).endOK _)
  have h1 := StmtT.letv (P := P) (x := 1) (r := .expr (.lit 2)) (E := intE) (F := []) (Γ := K1) (Γ1 := K1)
    rfl (by simp [K1, A2.setE, upd]) (by simp) (RhsT.expr ExprT.lit) hd
    (((hK5.exitScope 3).exitScope 2).endOK _)
  exact ⟨_, StmtT.letv (P := P) (x := 0) (r := .expr (.lit 1)) (E := intE) (F := []) (Γ := fun _ => none)
    (Γ1 := fun _ => none) rfl rfl (by simp) (RhsT.expr ExprT.lit) h1
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

theorem main5_typed : ∃ Δ, StmtT P (fun _ => none) [] main5 Δ := by
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
      (by simp [K2, K1, A2.setE, upd]) rfl PushArg.int (by simp [intE, Mode.ownSlot]) rfl rfl
  -- the `Vec` of destructor values, bound by `letd` at its own type
  let EN : Entry := ⟨.vec DT, .own, true, [], [], false, false⟩
  have hnew : RhsT K3 [] (.new DT) EN K3 := RhsT.new (by decide)
  let EV : Entry := Entry.arm { EN with ty := .vec DT, held := [] }
  have hEVe : EV = ⟨.vec DT, .own, true, [], [], false, false⟩ := by
    simp [EV, EN, Entry.arm, DT, T, Ty.dtorViews, Ty.hasDtor]
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
  have hpush := StmtT.push (P := P) (Γ := K4) (Γ1 := K5) (F := []) (x := 3) (y := 2) (Ex := EV) (Ey := ED)
    (Ex1 := EV) (t := DT) (D := ED.held) (by simp [K4, A2.setE, upd]) (by rw [hEVe]) (by rw [hEVe])
    (Or.inl (by rw [hEVe])) (by simp) (by simp [K4, K3, A2.setE, upd]) (by rw [hEDe]) (by rw [hEDe])
    (by decide) hmove (by rw [hEDe]; simp [roots]) hK53 (by rw [hEVe])
    (DtorSafe.of_none (fun v E h => (hK5 v E h).2.1) _ _ _) (by rw [hEVe]; simp)
  have hK6 : NoRootb (A2.setE (kill .realloc DT.holdsView 3 K5) 3
      { EV with held := EV.held ++ ownHeld true DT ED.held }) :=
    (hK5.kill _ _ _).setE (by rw [hEVe]; simp)
  have hdv := StmtT.letd (P := P) (Γ := K3) (Γ1 := K3) (F := []) (x := 3) (f := 0) (r := .new DT)
    (s := .push 3 2) (E := EN) (t := T) (H := []) (τ := .vec DT) rfl (by simp [K3, K2, K1, A2.setE, upd])
    (by simp) hnew rfl (Or.inr ⟨rfl, rfl, rfl⟩) rfl rfl (letd_fn drop_ok) (HeldUp.refl _ _) hpush (hK6.endOK _)
  have hd := StmtT.letd (P := P) (Γ := K2) (Γ1 := K2) (F := []) (x := 2) (f := 0) (r := .pair 0 1)
    (s := .letd 3 0 (.new DT) (.push 3 2)) (E := EP) (t := T) (H := []) rfl (by simp [K2, K1, A2.setE, upd])
    (by simp) hpair rfl (Or.inl ⟨rfl, Or.inl rfl⟩) rfl rfl (letd_fn drop_ok) (HeldUp.refl _ _) hdv
    ((hK6.exitScope 3).endOK _)
  have h1 := StmtT.letv (P := P) (x := 1) (r := .expr (.lit 2)) (E := intE) (F := []) (Γ := K1) (Γ1 := K1)
    rfl (by simp [K1, A2.setE, upd]) (by simp) (RhsT.expr ExprT.lit) hd
    (((hK6.exitScope 3).exitScope 2).endOK _)
  exact ⟨_, StmtT.letv (P := P) (x := 0) (r := .expr (.lit 1)) (E := intE) (F := []) (Γ := fun _ => none)
    (Γ1 := fun _ => none) rfl rfl (by simp) (RhsT.expr ExprT.lit) h1
    ((((hK6.exitScope 3).exitScope 2).exitScope 1).endOK _)⟩

/-- The program with a `Vec` of destructor values is memory safe. -/
theorem main5_safe {m' : Mem} {s' : Stmt} (hr : Steps P (emptyMem 4) main5 (.ok m' s')) :
    ¬ Stuck P m' s' := by
  obtain ⟨Δ, ht⟩ := main5_typed
  exact memory_safe prog_ok prog_codes ht rfl (by simp [main5, Stmt.codesOK, Rhs.codeOK]) (by decide) hr

/-- ... and `letv` refuses that `Vec`: it holds destructor values. -/
theorem main5_letv_refused {Γ Δ : Ctx} {F : List Var} {x : Var} {s : Stmt} :
    ¬ StmtT P Γ F (.letv x (.new DT) s) Δ := by
  intro h
  obtain ⟨Γ0, E, Γ1, hr, hnd⟩ := A2.Dtor.letv_owned_no_dtor h
  cases hr with
  | new _ => exact absurd (hnd rfl) (by decide)

/-! ### A struct with a destructor field, dropped by its glue (Agora #616)

`: a 1  : b 2  :drop x ( pair a b )  : c 3  :drop g ( pair x c )`: the
destructor value `x` moves into the struct, which is bound by `letd` at
`GDT`, the destructor type whose destructor is the glue (`glue`).  At the
frame's end the struct moves into the glue (its parameter is `sink`), which
takes it apart: the field is a `letd`'s. -/

def main7 : Stmt :=
  .letv 0 (.expr (.lit 1)) (.letv 1 (.expr (.lit 2))
    (.letd 2 0 (.pair 0 1) (.letv 3 (.expr (.lit 3)) (.letd 4 4 (.pair 2 3) .skip))))

theorem main7_typed : ∃ Δ, StmtT P (fun _ => none) [] main7 Δ := by
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
      (by simp [K2, K1, A2.setE, upd]) rfl PushArg.int (by simp [intE, Mode.ownSlot]) rfl rfl
  let K4 : Ctx := A2.setE K3 3 intE
  have hK4 : NoRootb K4 := hK3.setE (by simp [intE])
  let K5 : Ctx := A2.setE (kill .replace false 2 K4) 2 { ED with live := false, dtor := false }
  have hK5 : NoRootb K5 := (hK4.kill _ _ _).setE (by rw [hEDe]; simp)
  have hmove : PushArg K4 [] 2 ED ED.ty ED.held K5 :=
    PushArg.move (Γ := K4) (F := []) (y := 2) (E := ED) (t := ED.ty) rfl (by rw [hEDe]) (by simp)
      (hK4.noPin _) (DtorSafe.of_none (fun v E h => (hK4 v E h).2.1) _ _ _)
  have hK53 : K5 3 = some intE := by
    simp [K5, K4, A2.setE, upd, A2.kill, killE, hits, intE, Entry.vdeps, Mode.ownSlot]
  let EG0 : Entry := ⟨.prod ED.ty intE.ty, .own, true, [], ED.held ++ [], false, false⟩
  have hgp : RhsT K4 [] (.pair 2 3) EG0 K5 :=
    RhsT.pair (Ey := ED) (Ez := intE) (by simp [K4, K3, A2.setE, upd]) (by rw [hEDe]) hmove
      hK53 rfl PushArg.int (by simp [intE, Mode.ownSlot]) (by rw [hEDe]; rfl) rfl
  let EGa : Entry := Entry.arm { EG0 with ty := GDT, held := EG0.held }
  have hEGa : EGa.mode ≠ .rootb ∧ EGa.dtor = false ∧ EGa.dbind = false := by
    simp [EGa, EG0, Entry.arm, GDT, GT, DT, T, Ty.dtorViews, Ty.hasDtor, Ty.holdsView]
  have hK6 : NoRootb (A2.setE K5 4 EGa) := hK5.setE hEGa
  have hg := StmtT.letd (P := P) (Γ := K4) (Γ1 := K5) (F := []) (x := 4) (f := 4) (r := .pair 2 3)
    (s := .skip) (E := EG0) (t := GT) (H := EG0.held) (τ := GDT) rfl
    (by simp [K4, K3, K2, K1, A2.setE, upd]) (by simp) hgp rfl
    (Or.inl ⟨rfl, Or.inl (by simp [EG0, hEDe, intE, GT])⟩) rfl rfl (letd_fn gluedrop_ok) (HeldUp.refl _ _) StmtT.skip
    (hK6.endOK _)
  have h3 := StmtT.letv (P := P) (x := 3) (r := .expr (.lit 3)) (E := intE) (F := []) (Γ := K3) (Γ1 := K3)
    rfl (by simp [K3, K2, K1, A2.setE, upd]) (by simp) (RhsT.expr ExprT.lit) hg ((hK6.exitScope 4).endOK _)
  have hd := StmtT.letd (P := P) (Γ := K2) (Γ1 := K2) (F := []) (x := 2) (f := 0) (r := .pair 0 1)
    (E := EP) (t := T) (H := []) rfl (by simp [K2, K1, A2.setE, upd])
    (by simp) hpair rfl (Or.inl ⟨rfl, Or.inl rfl⟩) rfl rfl (letd_fn drop_ok) (HeldUp.refl _ _) h3
    (((hK6.exitScope 4).exitScope 3).endOK _)
  have h1 := StmtT.letv (P := P) (x := 1) (r := .expr (.lit 2)) (E := intE) (F := []) (Γ := K1) (Γ1 := K1)
    rfl (by simp [K1, A2.setE, upd]) (by simp) (RhsT.expr ExprT.lit) hd
    ((((hK6.exitScope 4).exitScope 3).exitScope 2).endOK _)
  exact ⟨_, StmtT.letv (P := P) (x := 0) (r := .expr (.lit 1)) (E := intE) (F := []) (Γ := fun _ => none)
    (Γ1 := fun _ => none) rfl rfl (by simp) (RhsT.expr ExprT.lit) h1
    (((((hK6.exitScope 4).exitScope 3).exitScope 2).exitScope 1).endOK _)⟩

/-- The program with a struct dropped by its glue is memory safe. -/
theorem main7_safe {m' : Mem} {s' : Stmt} (hr : Steps P (emptyMem 5) main7 (.ok m' s')) :
    ¬ Stuck P m' s' := by
  obtain ⟨Δ, ht⟩ := main7_typed
  exact memory_safe prog_ok prog_codes ht rfl (by simp [main7, Stmt.codesOK, Rhs.codeOK]) (by decide) hr

/-- ... and the destructor `dfn`, which takes its value lent, is no
    destructor for that struct: one that holds a destructor value has glue. -/
theorem main7_lent_refused : ¬ DropFnOK P 0 GT := by
  rintro (⟨_, h⟩ | ⟨fn, a, b, hfn, _, _, hps, _⟩ | ⟨_, _, fn, _, _, _, _, _, hfn, _, _, hps, _⟩)
  · exact absurd (h DT .int rfl) (by decide)
  · simp [P] at hfn; subst hfn; simp [dfn] at hps
  · simp [P] at hfn; subst hfn; simp [dfn] at hps

/-! ### ... and with a `% Drop` of its own (Agora #616)

The same program, the struct bound at `SDT2`, whose glue (`glue2`) rebinds
it under the fields' glue and runs the impl on it lent. -/

def main8 : Stmt :=
  .letv 0 (.expr (.lit 1)) (.letv 1 (.expr (.lit 2))
    (.letd 2 0 (.pair 0 1) (.letv 3 (.expr (.lit 3)) (.letd 4 6 (.pair 2 3) .skip))))

theorem main8_typed : ∃ Δ, StmtT P (fun _ => none) [] main8 Δ := by
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
      (by simp [K2, K1, A2.setE, upd]) rfl PushArg.int (by simp [intE, Mode.ownSlot]) rfl rfl
  let K4 : Ctx := A2.setE K3 3 intE
  have hK4 : NoRootb K4 := hK3.setE (by simp [intE])
  let K5 : Ctx := A2.setE (kill .replace false 2 K4) 2 { ED with live := false, dtor := false }
  have hK5 : NoRootb K5 := (hK4.kill _ _ _).setE (by rw [hEDe]; simp)
  have hmove : PushArg K4 [] 2 ED ED.ty ED.held K5 :=
    PushArg.move (Γ := K4) (F := []) (y := 2) (E := ED) (t := ED.ty) rfl (by rw [hEDe]) (by simp)
      (hK4.noPin _) (DtorSafe.of_none (fun v E h => (hK4 v E h).2.1) _ _ _)
  have hK53 : K5 3 = some intE := by
    simp [K5, K4, A2.setE, upd, A2.kill, killE, hits, intE, Entry.vdeps, Mode.ownSlot]
  let EG0 : Entry := ⟨.prod ED.ty intE.ty, .own, true, [], ED.held ++ [], false, false⟩
  have hgp : RhsT K4 [] (.pair 2 3) EG0 K5 :=
    RhsT.pair (Ey := ED) (Ez := intE) (by simp [K4, K3, A2.setE, upd]) (by rw [hEDe]) hmove
      hK53 rfl PushArg.int (by simp [intE, Mode.ownSlot]) (by rw [hEDe]; rfl) rfl
  let EGa : Entry := Entry.arm { EG0 with ty := SDT2, held := EG0.held }
  have hEGa : EGa.mode ≠ .rootb ∧ EGa.dtor = false ∧ EGa.dbind = false := by
    simp [EGa, EG0, Entry.arm, SDT2, GT, DT, T, Ty.dtorViews, Ty.hasDtor, Ty.holdsView]
  have hK6 : NoRootb (A2.setE K5 4 EGa) := hK5.setE hEGa
  have hg := StmtT.letd (P := P) (Γ := K4) (Γ1 := K5) (F := []) (x := 4) (f := 6) (r := .pair 2 3)
    (s := .skip) (E := EG0) (t := GT) (H := EG0.held) (τ := SDT2) rfl
    (by simp [K4, K3, K2, K1, A2.setE, upd]) (by simp) hgp rfl
    (Or.inl ⟨rfl, Or.inl (by simp [EG0, hEDe, intE, GT])⟩) rfl rfl (letd_fn impldrop_ok) (HeldUp.refl _ _) StmtT.skip
    (hK6.endOK _)
  have h3 := StmtT.letv (P := P) (x := 3) (r := .expr (.lit 3)) (E := intE) (F := []) (Γ := K3) (Γ1 := K3)
    rfl (by simp [K3, K2, K1, A2.setE, upd]) (by simp) (RhsT.expr ExprT.lit) hg ((hK6.exitScope 4).endOK _)
  have hd := StmtT.letd (P := P) (Γ := K2) (Γ1 := K2) (F := []) (x := 2) (f := 0) (r := .pair 0 1)
    (E := EP) (t := T) (H := []) rfl (by simp [K2, K1, A2.setE, upd])
    (by simp) hpair rfl (Or.inl ⟨rfl, Or.inl rfl⟩) rfl rfl (letd_fn drop_ok) (HeldUp.refl _ _) h3
    (((hK6.exitScope 4).exitScope 3).endOK _)
  have h1 := StmtT.letv (P := P) (x := 1) (r := .expr (.lit 2)) (E := intE) (F := []) (Γ := K1) (Γ1 := K1)
    rfl (by simp [K1, A2.setE, upd]) (by simp) (RhsT.expr ExprT.lit) hd
    ((((hK6.exitScope 4).exitScope 3).exitScope 2).endOK _)
  exact ⟨_, StmtT.letv (P := P) (x := 0) (r := .expr (.lit 1)) (E := intE) (F := []) (Γ := fun _ => none)
    (Γ1 := fun _ => none) rfl rfl (by simp) (RhsT.expr ExprT.lit) h1
    (((((hK6.exitScope 4).exitScope 3).exitScope 2).exitScope 1).endOK _)⟩

/-- The program with a struct that has its own `% Drop` beside a destructor
    field is memory safe. -/
theorem main8_safe {m' : Mem} {s' : Stmt} (hr : Steps P (emptyMem 5) main8 (.ok m' s')) :
    ¬ Stuck P m' s' := by
  obtain ⟨Δ, ht⟩ := main8_typed
  exact memory_safe prog_ok prog_codes ht rfl (by simp [main8, Stmt.codesOK, Rhs.codeOK]) (by decide) hr

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

def ES : Entry := ⟨ST, .own, true, [], [], false, false⟩

theorem main4_typed : ∃ Δ, StmtT P (fun _ => none) [] main4 Δ := by
  let K1 : Ctx := A2.setE (fun _ => none) 0 intE
  have hK1 : NoRootb K1 := noRootb_empty.setE (by simp [intE])
  have hinr : RhsT K1 [] (.inr AT 0) ES K1 :=
    RhsT.inr (Ey := intE) (by simp [K1, A2.setE]) rfl PushArg.int
      (by simp [AT, DT, T, Ty.ok, Ty.isStruct]) rfl rfl
  let ESd : Entry := Entry.arm { ES with ty := SDT, held := [] }
  have hESd : ESd.mode ≠ .rootb ∧ ESd.dtor = false ∧ ESd.dbind = false := by
    simp [ESd, ES, Entry.arm, SDT, ST, AT, DT, T, Ty.dtorViews, Ty.hasDtor, Ty.holdsView]
  have hK2 : NoRootb (A2.setE K1 1 ESd) := hK1.setE hESd
  have hd := StmtT.letd (P := P) (Γ := K1) (Γ1 := K1) (F := []) (x := 1) (f := 3) (r := .inr AT 0)
    (s := .skip) (E := ES) (t := ST) (H := []) rfl (by simp [K1, A2.setE]) (by simp) hinr rfl
    (Or.inl ⟨rfl, Or.inl rfl⟩) rfl rfl (letd_fn gdrop_ok) (HeldUp.refl _ _) StmtT.skip (hK2.endOK _)
  exact ⟨_, StmtT.letv (P := P) (x := 0) (r := .expr (.lit 3)) (E := intE) (F := []) (Γ := fun _ => none)
    (Γ1 := fun _ => none) rfl rfl (by simp) (RhsT.expr ExprT.lit) hd ((hK2.exitScope 1).endOK _)⟩

/-- A2-drop.3b: the program binding a destructor value two levels down is
    memory safe. -/
theorem main4_safe {m' : Mem} {s' : Stmt} (hr : Steps P (emptyMem 2) main4 (.ok m' s')) :
    ¬ Stuck P m' s' := by
  obtain ⟨Δ, ht⟩ := main4_typed
  exact memory_safe prog_ok prog_codes ht rfl (by simp [main4, Stmt.codesOK, Rhs.codeOK]) (by decide) hr

/-- …and `letv` refuses that enum, in any context: deep, `Ty.holdsDtor`
    sees the destructor value under the struct. -/
theorem main4_letv_refused {Γ Δ : Ctx} {F : List Var} {x : Var} {s : Stmt} :
    ¬ StmtT P Γ F (.letv x (.inr AT 0) s) Δ := by
  intro h
  obtain ⟨_, E, _, hr, hnd⟩ := A2.Dtor.letv_owned_no_dtor h
  cases hr
  simp [AT, DT, Ty.holdsDtor] at hnd

/-- An enum of a destructor type lends its payloads (`getl` / `getr`, through
    the type), the destructor staying with the whole value… -/
theorem enum_lends {Γ : Ctx} {F : List Var} {E0 : Entry} {f : Nat} {a b : Ty}
    (h0 : Γ 0 = some E0) (hl : E0.live = true) (ht : E0.ty = .dtor f (.sum a b)) :
    RhsT Γ F (.getl 0) (projE 0 E0 a) Γ ∧ RhsT Γ F (.getr 0) (projE 0 E0 b) Γ :=
  ⟨RhsT.getl h0 hl (by rw [ht]; rfl), RhsT.getr h0 hl (by rw [ht]; rfl)⟩

/-- …but no payload is taken out of it (`takel` / `taker`): the enum's
    destructor would never run. -/
theorem enum_take_refused {Γ Γ' : Ctx} {F : List Var} {E E0 : Entry} {f : Nat} {a b : Ty}
    (h0 : Γ 0 = some E0) (ht : E0.ty = .dtor f (.sum a b)) :
    ¬ RhsT Γ F (.takel 0) E Γ' ∧ ¬ RhsT Γ F (.taker 0) E Γ' := by
  refine ⟨fun h => ?_, fun h => ?_⟩
  · cases h with
    | takel hy _ _ hty _ _ _ => rw [h0] at hy; cases hy; rw [ht] at hty; cases hty
  · cases h with
    | taker hy _ _ hty _ _ _ => rw [h0] at hy; cases hy; rw [ht] at hty; cases hty

end A2.DtorWitness
