module

public import A2.NoRootb

@[expose] public section

/-! # A2-drop.3a: the destructor on the type, checked

Two kinds of fact (`check.sh` prints their axioms); the first is here, the
witness is `A2/DtorWitness.lean` (apart so that a certificate loads no
witness program, AGORA-1013):

* **The guarantee of the typing** (`A2.Dtor.*`): every binder of an owned
  value of a destructor type (or of a struct or an enum holding one) either
  is a `letd`, whose scope is a `scopeD` frame, or hands the value to one
  first thing (`Stmt.movedFirst`); a `letd`'s value is of the destructor type,
  whose function is its destructor (`DropFnOK`: one that takes it lent,
  `DtorOK`, or the glue of a struct or an enum, which takes it owned and
  takes it apart, `GlueOK` / `ImplGlueOK` / `EnumGlueOK`, Agora #616, #632),
  and the binding is assigned nothing
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
  `letd_retype`; the functions `impl` and `glue2`, `main8`).  Agora #633:
  such a struct may hold views of older bindings, moved into its glue as a
  `sink` argument holding them (`glueS`, `main10`).  Agora #750: so may an
  enum with glue (`ofnV`, of `sum DT (slice int)`; `main12`, its view
  variant), and a struct whose glue runs its own `% Drop` impl first
  (`implS`, `glueS2`; `main13`).  Agora #782: a `Vec` of such view-holding
  structs, its `letd` recording the view of the older binding up front
  (`main14`, with `memory_safe` and `no_leak_end`).  Agora #805: the glue
  of the option a channel's receive hands out, `sum int DT` (`ofnR`, its
  payload in the right variant; the receive's witness is
  `A3.ChanDtorWitness.mainR`).
  A2-drop.3c and 3d: no block's payload and no environment of a closure
  that does not drop (Agora #609: of a class other than `dropd`) holds
  a destructor value (`A2.Dtor.pkgs_env_dtor_free`, `blk_pkgs_env_dtor_free`,
  `blocks_dtor_free`).
-/

namespace A2.Dtor

/-- `skip` has no step, when no orphan awaits its destructor (Agora #610:
    `Step.reap` fires from any source statement, `skip` too; no store a run
    reaches between its steps has an orphan, `A2.no_orphan`). -/
theorem skip_no_step {P : Prog} {m : Mem} {r : Res} (hno : ¬ Orphan m) (h : Step P m .skip r) : False := by
  cases h with
  | waitPanic hw => exact hw
  | reap _ hk _ => exact hno ⟨_, _, _, _, _, hk⟩

/-- A typed `letv` binds no owned value of a destructor type (nor of a struct
    or an enum holding one). (In the context its rule was applied in, under
    any `sub`sumptions.) -/
theorem letv_owned_no_dtor {P : Prog} {Γ Δ : Ctx} {F : List Var} {x : Var} {r : Rhs} {s : Stmt}
    (h : StmtT P ξ Γ F (.letv x r s) Δ) :
    ∃ Γ0 E Γ1, RhsT Γ0 F r E Γ1 ∧ (E.mode = .own → E.ty.holdsDtor = false) := by
  generalize hst : Stmt.letv x r s = st at h
  induction h with
  | letv _ _ _ hr _ _ hnd => cases hst; exact ⟨_, _, _, hr, hnd⟩
  | sub _ _ _ ih => exact ih hst
  | _ => cases hst

/-- A typed call's owned result of a destructor type is handed to its `letd`
    first thing, and the result binding is assigned nothing. -/
theorem letcall_hands_over {P : Prog} {Γ Δ : Ctx} {F : List Var} {x : Var} {f : Nat}
    {args : List Var} {s : Stmt} (h : StmtT P ξ Γ F (.letcall x f args s) Δ) :
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
    (h : StmtT P ξ Γ F (.unpair y x z s) Δ) :
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
    (h : StmtT P ξ Γ F (.unpair y x z s) Δ) :
    ∃ (E : Entry) (a b : Ty), Γ y = some E ∧ E.ty.undtor = .prod a b ∧
      (a.holdsDtor = true → x ∈ s.movedFirst ∧ x ∉ s.assigns) ∧
      (b.holdsDtor = true → z ∈ s.movedFirst ∧ z ∉ s.assigns) := by
  generalize hst : Stmt.unpair y x z s = st at h
  induction h with
  | unpair _ hy _ _ hty _ _ _ _ _ _ _ _ _ _ _ hdx hdz =>
    cases hst; exact ⟨_, _, _, hy, unpair_undtor hty, hdx, hdz⟩
  | @sub _ Γa _ _ _ _ _ hw _ _ ih =>
    obtain ⟨E', a, b, hy', hty, hdx, hdz⟩ := ih hst
    obtain ⟨hn, hE⟩ := hw.1 y
    cases hg : Γa y with
    | none => rw [hn.mp hg] at hy'; cases hy'
    | some E =>
      have hw' := hE E E' hg hy'
      exact ⟨E, a, b, rfl, by rw [← hw'.ty]; exact hty, hdx, hdz⟩
  | _ => cases hst

/-- AGORA-900: a typed move-out through a borrow (`takeB`) of an element
    that holds a destructor value hands it to its `letd` first thing, and
    the binding is assigned nothing: `x` borrows a `Vec` of `t`, and if `t`
    holds a destructor value, `y` is moved first in its scope. -/
theorem takeB_typed {P : Prog} {Γ Δ : Ctx} {F : List Var} {x y : Var} {i : Expr} {s : Stmt}
    (h : StmtT P ξ Γ F (.takeB x i y s) Δ) :
    ∃ (E : Entry) (t : Ty), Γ x = some E ∧ E.ty = .vec t ∧
      (t.holdsDtor = true → y ∈ s.movedFirst ∧ y ∉ s.assigns) := by
  generalize hst : Stmt.takeB x i y s = st at h
  induction h with
  | takeB _ _ _ hx _ _ hty _ _ _ _ hdk _ _ _ => cases hst; exact ⟨_, _, hx, hty, hdk⟩
  | takeBV _ _ _ hx _ _ hty _ _ _ _ _ _ hdk _ _ _ => cases hst; exact ⟨_, _, hx, hty, hdk⟩
  | @sub _ Γa _ _ _ _ _ hw _ _ ih =>
    obtain ⟨E', t, hx', hty, hdk⟩ := ih hst
    obtain ⟨hn, hE⟩ := hw.1 x
    cases hg : Γa x with
    | none => rw [hn.mp hg] at hx'; cases hx'
    | some E =>
      have hw' := hE E E' hg hx'
      exact ⟨E, t, rfl, by rw [← hw'.ty]; exact hty, hdk⟩
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
    ∃ i r k, ImplGlueOK P g t f i ∧ s = .letcall r i [x] k ∧ (GlueOK P f t ∨ EnumGlueOK P f t) ∧
      DtorOK P i (.dtor f t) := by
  obtain ⟨i, r, k, hig, hs⟩ := h.2 g ha hne
  have hig' := hig
  obtain ⟨_, _, _, _, _, _, _, _, _, _, _, _, _, hgl, hdt, _⟩ := hig'
  exact ⟨i, r, k, hig, hs, hgl, hdt⟩

/-- **Agora #616, #632: the glue of a struct or an enum with a `% Drop` of
    its own.**  It takes the value owned, rebinds it under the fields' glue `h` first
    thing (nothing can panic before: from there the struct is in `h`'s
    frame, which takes it apart with a frame per destructor field, at its
    end and on a panic), runs the impl `i` on it lent, and sets its result. -/
theorem impl_glue_body {P : Prog} {f : Nat} {t : Ty} {h i : Nat} (hg : ImplGlueOK P f t h i) :
    ∃ fn w r e, P[f]? = some fn ∧ fn.params = [(.sink, .dtor f t)] ∧
      fn.body = .letd w h (.var 0) (.letcall r i [w] (.assign 1 (.expr e))) ∧
      (GlueOK P h t ∨ EnumGlueOK P h t) ∧ DtorOK P i (.dtor h t) := by
  obtain ⟨fn, w, r, e, hfn, _, hps, _, _, _, _, _, _, hgl, hdt, hb⟩ := hg
  exact ⟨fn, w, r, e, hfn, hps, hb, hgl, hdt⟩

/-- Agora #616: the destructor of a struct that holds a destructor value is
    its glue, which takes the struct apart (`GlueOK`), after the struct's
    own impl if it has one (`ImplGlueOK`); a destructor that takes it lent
    (`DtorOK`) is refused for it. -/
theorem struct_dtor_is_glue {P : Prog} {f : Nat} {a b : Ty} (h : DropFnOK P f (.prod a b))
    (hd : (Ty.prod a b).holdsDtor = true) :
    GlueOK P f (.prod a b) ∨ ∃ h i, ImplGlueOK P f (.prod a b) h i := by
  rcases h with ⟨_, h⟩ | h | h | ⟨_, _, _, _, _, _, ht, _⟩ | ⟨_, _, _, _, _, _, _, _, ht, _⟩
  · rw [h] at hd; cases hd
  · exact Or.inl h
  · exact Or.inr h
  · cases ht
  · cases ht

/-- Agora #632: the destructor of an enum that holds a destructor value is
    its glue (`EnumGlueOK`), which takes the enum owned, after the enum's
    own impl if it has one (`ImplGlueOK`); a destructor that takes it lent
    is refused for it. -/
theorem enum_dtor_is_glue {P : Prog} {f : Nat} {a b : Ty} (h : DropFnOK P f (.sum a b))
    (hd : (Ty.sum a b).holdsDtor = true) :
    EnumGlueOK P f (.sum a b) ∨ ∃ h i, ImplGlueOK P f (.sum a b) h i := by
  rcases h with ⟨_, h⟩ | ⟨_, _, _, _, ht, _⟩ | h | h | ⟨_, _, _, _, _, _, _, _, ht, _⟩
  · rw [h] at hd; cases hd
  · cases ht
  · exact Or.inr h
  · exact Or.inl h
  · cases ht

/-- **Agora #632: an enum's glue takes the payload out to a frame of its
    own.**  The glue `f` of the enum `sum a b` takes one value of the
    destructor type `Ty.dtor f (sum a b)` owned and matches on its tag; in
    the arm of a variant whose payload type holds a destructor value, the
    payload moves out to a `letd` first thing (`takel` / `taker`: its frame
    runs the destructor, at its end and on a panic), and the arms do
    nothing else (`Stmt.pureGlue`). -/
theorem enum_glue_body {P : Prog} {f : Nat} {a b : Ty} (h : EnumGlueOK P f (.sum a b)) :
    ∃ fn sa sb, P[f]? = some fn ∧ fn.params = [(.sink, .dtor f (.sum a b))] ∧
      fn.body = .ite (.isl 0) sa sb ∧ sa.pureGlue = true ∧ sb.pureGlue = true ∧
      (a.holdsDtor = true → ∃ y g k, sa = .letd y g (.takel 0) k) ∧
      (b.holdsDtor = true → ∃ z g k, sb = .letd z g (.taker 0) k) := by
  obtain ⟨fn, a', b', sa, sb, hfn, hab, hps, _, _, _, _, _, _, hb, hpa, hpb, ha, hb'⟩ := h
  cases hab
  exact ⟨fn, sa, sb, hfn, hps, hb, hpa, hpb, ha, hb'⟩

/-- **Agora #632: a payload leaves an enum of a destructor type only where
    that is the enum's drop.**  The two statements that bind a right-hand
    side's owned value, `letd` and `assign` (`letv` refuses an owned value
    that holds a destructor value, `letv_owned_no_dtor`), are typed, in the
    context `Γ0` their rule was applied in, with the right-hand side typed
    there and the gate `TakeOK P Γ0 r`: a `takel y` / `taker y` on a `y`
    whose type in `Γ0` is `Ty.dtor g u` has `g` the enum's glue. -/
theorem take_is_glue {P : Prog} {Γ Δ : Ctx} {F : List Var} {x : Var} {f : Nat} {r : Rhs} {s : Stmt}
    (h : StmtT P ξ Γ F (.letd x f r s) Δ) :
    ∃ Γ0 E Γ1, RhsT Γ0 F r E Γ1 ∧ TakeOK P Γ0 r := by
  generalize hst : Stmt.letd x f r s = st at h
  induction h with
  | letd _ _ _ hr _ _ _ _ hok _ _ _ _ => cases hst; exact ⟨_, _, _, hr, hok.2⟩
  | sub _ _ _ ih => exact ih hst
  | _ => cases hst

theorem assign_take_is_glue {P : Prog} {Γ Δ : Ctx} {F : List Var} {x : Var} {r : Rhs}
    (h : StmtT P ξ Γ F (.assign x r) Δ) :
    ∃ Γ0 E Γ1, RhsT Γ0 F r E Γ1 ∧ TakeOK P Γ0 r := by
  generalize hst : Stmt.assign x r = st at h
  induction h with
  | assign _ _ _ hr _ _ _ _ _ _ htk => cases hst; exact ⟨_, _, _, hr, htk⟩
  | sub _ _ _ ih => exact ih hst
  | _ => cases hst

/-- **Agora #616: a struct's glue runs each field's destructor in a frame
    of its own.**  In a typed program, the glue `f` of the struct `prod a b`
    takes one value of the destructor type `Ty.dtor f (prod a b)` owned,
    and its body takes it apart first thing into `x` and `z` and does
    nothing after but hand values on and set its result (`Stmt.pureGlue`);
    a field of a destructor type or of a struct with glue is so in a frame
    that runs its destructor (an enum field's is the enum's glue, Agora #632); a field whose
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
  obtain ⟨fn, a', b', hfn, hab, hps, _, _, _, _, _, _, x, z, s, hbody, hpure⟩ := h
  cases hab
  obtain ⟨Δ, hb, _⟩ := (hP fn (List.mem_of_getElem? hfn)).2.2.2.2.2.2.2.2.2.2.2.2
  rw [hbody] at hb
  obtain ⟨E, a1, b1, hy, hty, hdx, hdz⟩ := unpair_typed hb
  have hE : E.ty = .dtor f (.prod a b) := by
    rw [sigCtx_of (show fn.params[0]? = some (.sink, .dtor f (.prod a b)) by rw [hps]; rfl)] at hy
    cases hy; simp [paramE]
  rw [hE] at hty
  simp [Ty.undtor] at hty
  obtain ⟨rfl, rfl⟩ := hty
  exact ⟨fn, x, z, s, hfn, hps, hbody, hpure, hdx, hdz⟩

/-- A typed `letd` binds a value of the destructor type `Ty.dtor f t` (`t` a
    struct or an enum), `f` is its destructor (`DropFnOK`: one that takes it
    lent, or a struct's glue), and the binding is assigned nothing in its scope. -/
theorem letd_dtor {P : Prog} {Γ Δ : Ctx} {F : List Var} {x : Var} {f : Nat} {r : Rhs} {s : Stmt}
    (h : StmtT P ξ Γ F (.letd x f r s) Δ) :
    ∃ t, t.isStruct = true ∧ DropFnOK P f t ∧ x ∉ s.assigns := by
  generalize hst : Stmt.letd x f r s = st at h
  induction h with
  | letd _ _ _ _ _ _ hst' _ hok _ _ _ hna => cases hst; exact ⟨_, hst', hok.1.1, hna⟩
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
      (i ∈ fn.body.movedFirst ∨ ∃ f u, P[f]? = some fn ∧ (EnumGlueOK P f u ∨ ClosureGlueOK P f u)) ∧
        i ∉ fn.body.assigns) ∧
    (∀ i (hi : i < fn.params.length) b, fn.params[i].1 = .inout b → fn.params[i].2.holdsDtor = true →
      i ∉ fn.body.assigns) ∧
    (fn.resOwn = true → fn.resTy.holdsDtor = true → fn.body.asgMax fn.params.length ≤ 1 ∧
      ∃ g t, ResDTy g t fn.resTy ∧ t.holdsView = false ∧
        t.hasFn = false ∧ DropFnOK P g t) :=
  h.2.2.2.2.2.2.2.2.2.2.2.1

/-- A call's owned result of a destructor type, or that is a `Vec` of
    destructor values, has a destructor frame from the start: the call's
    inside is `scopeD r g …` on the result slot `r`, with `g` the result
    type's destructor (the shape of `callIn`; what the frame then does is
    `scopeD_panic_runs_dtor` / `scopeD_panic_drains` for a slot that owns,
    and `Step.scopeDMoved` once the result has moved to the caller).  Agora
    #607: so does one that is a `Vec` of such `Vec`s, at any depth. -/
theorem result_frame_is_scopeD (fn : Fn) (args : List Var) (base : Nat) (x : Var) {g : Nat} {t : Ty}
    (ho : fn.resOwn = true) (hty : ResDTy g t fn.resTy) :
    ∃ s, callIn fn args base x = .scopeD (base + fn.params.length) g s := by
  have hf : ∀ r s, resFrame fn r s = .scopeD r g s := fun r s => by
    unfold resFrame; rw [ho, hty.dhead]
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
    {m : Mem} {v : Val} (ht : StmtT P ξ Γ F (.scopeD x f .skip) Δ)
    (hx : m.st x = some ⟨true, some v⟩) (hv : v.isNode = false)
    -- (Agora #610: with no orphan to reap first; no store a run reaches has one, `A2.no_orphan`)
    (hno : ¬ Orphan m) :
    (∃ t, DropFnOK P f t) ∧
      Step P m (.scopeD x f .skip) (.ok { m with nv := m.nv + 1 } (.scope x (.letcall m.nv f [x] .skip))) ∧
      ∀ r, Step P m (.scopeD x f .skip) r →
        r = .ok { m with nv := m.nv + 1 } (.scope x (.letcall m.nv f [x] .skip)) := by
  refine ⟨?_, Step.scopeDEnd hx hv, fun r h => ?_⟩
  · generalize hst : Stmt.scopeD x f .skip = st at ht
    induction ht with
    | scopeD hE _ _ _ _ _ _ _ _ =>
      cases hst
      obtain ⟨E, t, _, _, _, _, h5, _⟩ := hE
      exact ⟨t, h5⟩
    | sub _ _ _ ih => exact ih hst
    | _ => cases hst
  · cases h with
    | reap hrs _ _ => cases hrs
    | scopeDIn hs => exact (skip_no_step hno hs).elim
    | scopeDEnd _ _ => rfl
    | scopeDMoved hm => rw [hx] at hm; cases hm
    | scopeDDrain h => rw [hx] at h; cases h; cases hv
    | scopeDEmpty h => rw [hx] at h; cases h; cases hv
    | scopeDP hs _ _ => exact (skip_no_step hno hs).elim
    | scopeDPDrain hs _ => exact (skip_no_step hno hs).elim
    | scopeDPMoved hs _ => exact (skip_no_step hno hs).elim
    | waitPanic hw => exact hw.elim

/-- …and on the panic path: a panic out of the body with `x` still owning
    its value stops at the frame, which is left at its end, followed by the
    panic.  The step after it is taken from the store the marking sweep
    leaves, `m1.sweepD` (`Steps.step`, `Settle`); with no orphan there
    (`Settle.done`), the only step from it is the frame's end, which calls
    `f` on `x` (and `scope x` frees it), the panic raised again after.
    (Agora #790: an orphan there is reaped first, at that end's `skip`,
    inside the frame: a panic of its destructor comes back to the frame,
    which still runs `f`, `A2.ArcPanicWitness.reaped_panic_runs_dtor`.) -/
theorem scopeD_panic_runs_dtor {P : Prog} {x : Var} {f : Nat} {m m1 : Mem} {s : Stmt} {v : Val}
    (hs : Step P m s (.panic m1)) (hx : m1.st x = some ⟨true, some v⟩) (hv : v.isNode = false) :
    Step P m (.scopeD x f s) (.ok m1 (.seq (.scopeD x f .skip) .panic)) ∧
      (¬ Orphan m1.sweepD → ∀ r, Step P m1.sweepD (.seq (.scopeD x f .skip) .panic) r ↔
        r = .ok { m1.sweepD with nv := m1.sweepD.nv + 1 }
          (.seq (.scope x (.letcall m1.sweepD.nv f [x] .skip)) .panic)) := by
  have hx' : m1.sweepD.st x = some ⟨true, some v⟩ := by rw [Mem.sweepD_st]; exact hx
  refine ⟨Step.scopeDP hs hx hv, fun hno r => ⟨fun h => ?_, fun h => h ▸ Step.seqL (Step.scopeDEnd hx' hv)⟩⟩
  have hend : ∀ r', Step P m1.sweepD (.scopeD x f .skip) r' →
      r' = .ok { m1.sweepD with nv := m1.sweepD.nv + 1 } (.scope x (.letcall m1.sweepD.nv f [x] .skip)) := by
    intro r' h
    cases h with
    | reap hrs _ _ => cases hrs
    | scopeDIn hs => exact (skip_no_step hno hs).elim
    | scopeDEnd _ _ => rfl
    | scopeDMoved hm => rw [hx'] at hm; cases hm
    | scopeDDrain h => rw [hx'] at h; cases h; cases hv
    | scopeDEmpty h => rw [hx'] at h; cases h; cases hv
    | scopeDP hs _ _ => exact (skip_no_step hno hs).elim
    | scopeDPDrain hs _ => exact (skip_no_step hno hs).elim
    | scopeDPMoved hs _ => exact (skip_no_step hno hs).elim
    | waitPanic hw => exact hw.elim
  cases h with
  | reap hrs _ _ => cases hrs
  | seqL h => cases hend _ h; rfl
  | seqP h => cases hend _ h
  | waitPanic hw => exact hw.elim

/-- **A2-drop.3b: the scope end of a `Vec` of destructor values drains it.**
    When the frame's body is done and `x` still owns a `Vec` with an element,
    the frame's one step hands element 0 to a fresh destructor binding
    (`vec_remove x 0`), under the same frame ... -/
theorem scopeD_end_drains {P : Prog} {x : Var} {f : Nat} {m : Mem} {t : Ty} {c d : Nat} {e : Val}
    {es : List Val} (hx : m.st x = some ⟨true, some (.node t c d (e :: es))⟩)
    -- (Agora #610: with no orphan to reap first; no store a run reaches has one, `A2.no_orphan`)
    (hno : ¬ Orphan m) :
    Step P m (.scopeD x f .skip)
        (.ok { m with nv := m.nv + 1 } (.scopeD x f (.letd m.nv f (.remove x (.lit 0)) .skip))) ∧
      ∀ r, Step P m (.scopeD x f .skip) r →
        r = .ok { m with nv := m.nv + 1 } (.scopeD x f (.letd m.nv f (.remove x (.lit 0)) .skip)) := by
  refine ⟨Step.scopeDDrain hx, fun r h => ?_⟩
  cases h with
  | reap hrs _ _ => cases hrs
  | scopeDIn hs => exact (skip_no_step hno hs).elim
  | scopeDEnd h hv => rw [hx] at h; cases h; cases hv
  | scopeDMoved hm => rw [hx] at hm; cases hm
  | scopeDDrain _ => rfl
  | scopeDEmpty h => rw [hx] at h; cases h
  | scopeDP hs _ _ => exact (skip_no_step hno hs).elim
  | scopeDPDrain hs _ => exact (skip_no_step hno hs).elim
  | scopeDPMoved hs _ => exact (skip_no_step hno hs).elim
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
    Step P m (.scopeD x f (.letd y f (.remove x (.lit 0)) .skip))
      (.ok ((m.set x ⟨true, some (.node t c d es)⟩).set y ⟨e.owns, some e⟩)
        (.scopeD x f (.scopeD y f .skip))) :=
  Step.scopeDIn (Step.letd hy (EvalR.remove (n := 0) (by simp) hx hc hd Eval.lit))

/-- ... and with every element gone the empty `Vec` is freed as any binding's
    value is: the frame's one step leaves `scope x`. -/
theorem scopeD_end_empty {P : Prog} {x : Var} {f : Nat} {m : Mem} {t : Ty} {c d : Nat}
    (hx : m.st x = some ⟨true, some (.node t c d [])⟩)
    -- (Agora #610: with no orphan to reap first; no store a run reaches has one, `A2.no_orphan`)
    (hno : ¬ Orphan m) :
    Step P m (.scopeD x f .skip) (.ok m (.scope x .skip)) ∧
      ∀ r, Step P m (.scopeD x f .skip) r → r = .ok m (.scope x .skip) := by
  refine ⟨Step.scopeDEmpty hx, fun r h => ?_⟩
  cases h with
  | reap hrs _ _ => cases hrs
  | scopeDIn hs => exact (skip_no_step hno hs).elim
  | scopeDEnd h hv => rw [hx] at h; cases h; cases hv
  | scopeDMoved hm => rw [hx] at hm; cases hm
  | scopeDDrain h => rw [hx] at h; cases h
  | scopeDEmpty _ => rfl
  | scopeDP hs _ _ => exact (skip_no_step hno hs).elim
  | scopeDPDrain hs _ => exact (skip_no_step hno hs).elim
  | scopeDPMoved hs _ => exact (skip_no_step hno hs).elim
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
    `Vec` of destructor values (`LetdTy`; Agora #782: whose elements may hold views); its
    scope is a destructor frame of that type (`scopeD_end_runs_dtor`,
    `scopeD_end_drains`).  Agora #616: a value of ANOTHER destructor type
    `Ty.dtor g t` moves in only where that is `g`'s drop (`LetdFn`): `g` is
    a struct's glue with an impl, `f` its fields' glue, and the scope starts
    with the impl's call on the new binding (`letd_retype`). -/
theorem letd_binds {P : Prog} {Γ Δ : Ctx} {F : List Var} {x : Var} {f : Nat} {r : Rhs} {s : Stmt}
    (h : StmtT P ξ Γ F (.letd x f r s) Δ) :
    ∃ Γ0 E Γ1 t τ, RhsT Γ0 F r E Γ1 ∧ LetdTy f t E.ty τ ∧ t.isStruct = true ∧ LetdFn P f t E.ty x s ∧
      TakeOK P Γ0 r := by
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
    (h : StmtT P ξ Γ F (.free x) Δ) :
    ∃ (E : Entry) (t : Ty), Γ x = some E ∧ E.ty = .vec t ∧ t.dtorFree = true := by
  generalize hst : Stmt.free x = st at h
  induction h with
  | free hx _ _ hty _ _ hdf => cases hst; exact ⟨_, _, hx, hty, hdf⟩
  | @sub _ Γa _ _ _ _ _ hw _ _ ih =>
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
    (h : StmtT P ξ Γ F (.edit b x op) Δ) (hd : op.drops = true) :
    ∃ (E : Entry) (t : Ty), Γ x = some E ∧ E.ty = .vec t ∧ t.dtorFree = true := by
  generalize hst : Stmt.edit b x op = st at h
  induction h with
  | editB hx _ _ hty _ _ _ _ _ _ _ hdf => cases hst; exact ⟨_, _, hx, hty, hdf hd⟩
  | editBV hx _ _ hty _ _ _ _ _ _ _ _ _ _ hdf => cases hst; exact ⟨_, _, hx, hty, hdf hd⟩
  | @sub _ Γa _ _ _ _ _ hw _ _ ih =>
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
    (h : StmtT P ξ Γ F (.withElem v i x s) Δ) :
    ∃ (Ev : Entry) (t : Ty), Γ v = some Ev ∧ Ev.ty = .vec t ∧ t.dtorFree = true := by
  generalize hst : Stmt.withElem v i x s = st at h
  induction h with
  | @withElem _ Γ _ _ _ _ _ _ _ _ Ev _ _ _ _ hv _ _ _ _ hr _ _ _ _ _ hdf _ _ =>
    cases hst
    cases hr with
    | @pop _ E0 t hy _ hty _ _ _ =>
      simp only [A2.kill, hv, Option.map_some, Option.some.injEq] at hy
      subst hy
      rw [killE_ty] at hty
      refine ⟨Ev, t, hv, hty, ?_⟩
      cases t <;> first | rfl | exact hdf
  | @sub _ Γa _ _ _ _ _ hw _ _ ih =>
    obtain ⟨E', t, hx', hty, hdf⟩ := ih hst
    obtain ⟨hn, hE⟩ := hw.1 v
    cases hg : Γa v with
    | none => rw [hn.mp hg] at hx'; cases hx'
    | some E => exact ⟨E, t, rfl, by rw [← (hE E E' hg hx').ty]; exact hty, hdf⟩
  | _ => cases hst

/-- A2-drop.3b: a typed destructor frame's binding, in the context the frame
    is typed in: an owner of the destructor type `Ty.dtor f t`, or of a `Vec`
    of such values (Agora #782: whose elements may hold views); `f` is a `DtorOK` destructor
    of `Ty.dtor f t`, a struct's or an enum's. -/
theorem scopeD_typed {P : Prog} {Γ Δ : Ctx} {F : List Var} {x : Var} {f : Nat} {s : Stmt}
    (h : StmtT P ξ Γ F (.scopeD x f s) Δ) :
    ∃ (E : Entry) (t : Ty), Γ x = some E ∧ E.mode = .own ∧ ScopeDTy f t E.ty ∧
      DropFnOK P f t ∧ t.isStruct = true := by
  generalize hst : Stmt.scopeD x f s = st at h
  induction h with
  | scopeD hE _ _ _ _ _ _ _ _ =>
    cases hst
    obtain ⟨E, t, hx, hmo, hty, _, hok, hstr⟩ := hE
    exact ⟨E, t, hx, hmo, hty, hok, hstr⟩
  | @sub _ Γa _ _ _ _ _ hw _ _ ih =>
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
    `scopeD_end_empty`'s steps drain it), or (Agora #607, `n > 0`) of such
    `Vec`s, each of which the drain binds by a frame of the same `f`. -/
theorem scopeD_frame_value {P : Prog} {Γ Δ : Ctx} {F : List Var} {x : Var} {f : Nat} {s : Stmt}
    {m : Mem} {v : Val} (ht : StmtT P ξ Γ F (.scopeD x f s) Δ) (hi : MInv m Γ)
    (hx : m.st x = some ⟨true, some v⟩) :
    ∃ (E : Entry) (t : Ty), Γ x = some E ∧ DropFnOK P f t ∧
      ((v.isNode = false ∧ E.ty = .dtor f t) ∨
        (∃ n c d es, v = .node (Ty.nest n (.dtor f t)) c d es ∧ E.ty = .vec (Ty.nest n (.dtor f t)) ∧
          ∀ e ∈ es, WFv (Ty.nest n (.dtor f t)) e ∧ (n = 0 → e.isNode = false))) := by
  obtain ⟨E, t, hE, hmo, hty, hok, hstr⟩ := scopeD_typed ht
  have hw := hi.own_wfv hE (by rw [hmo]; rfl) hx
  refine ⟨E, t, hE, hok, ?_⟩
  rcases hty.shape hstr hw with ⟨hn, he⟩ | ⟨n, c, d, es, hv, he⟩
  · exact Or.inl ⟨hn, he⟩
  · refine Or.inr ⟨n, c, d, es, hv, he, fun e hmem => ?_⟩
    rw [he, hv] at hw
    cases hw with
    | node hes =>
      have hwe := hes e hmem
      refine ⟨hwe, fun hn0 => ?_⟩
      subst hn0
      rcases (ScopeDTy.shape (f := f) (t := t) (Or.inl rfl) hstr hwe) with ⟨hn, _⟩ | ⟨_, _, _, _, _, h'⟩
      · exact hn
      · cases h'

/-- A2-drop.3c: a typed closure or trait-object literal of a class that does
    not drop (Agora #609: every class but `dropd`) has an environment that
    holds no destructor value, at any depth: such a package's drop releases
    its environment running no code (`Cross.Fits`). -/
theorem pack_env_dtor_free {Γ Γ1 : Ctx} {F : List Var} {fs : List Nat} {te : Ty} {ms : List Nat}
    {y : Var} {cs : List (Var × PMode × Ty)} {E : Entry}
    (h : RhsT Γ F (.pack fs te ms y cs) E Γ1) (hE : E.ty.holdsDtor = false) :
    te.holdsDtor = false ∧ te.dtorFree = true := by
  cases h with
  | pack _ _ _ _ _ hq =>
    have := hq.2.2.2.1 (by simpa [Ty.holdsDtor] using hE)
    refine ⟨this, ?_⟩
    rw [Ty.holdsDtor_eq_not_free] at this
    simpa using this

/-- Agora #609: no closure of the dropping class occurs in the type, in a
    field, a payload, an element or under a destructor type (a share's
    payload and a view's element hold none: `Ty.ok`). -/
def _root_.A2.Ty.noDropd : Ty → Bool
  | .vec t => t.noDropd
  | .prod a b => a.noDropd && b.noDropd
  | .sum a b => a.noDropd && b.noDropd
  | .fn _ q => !q.drops
  | .dtor _ t => t.noDropd
  | _ => true

theorem _root_.A2.Ty.noDropd_of_free {t : Ty} (h : t.holdsDtor = false) : t.noDropd = true := by
  induction t <;> simp_all [Ty.holdsDtor, Ty.noDropd]

/-- ... and so does every package in a well-formed tree of a type with no
    closure of the dropping class in it, however deep the package lies (a
    field, an element, another package's environment, under a destructor
    type). -/
theorem _root_.A2.WFv.pkg_env_dtor_free {τ : Ty} {v : Val} (hw : WFv τ v) (hdf : τ.noDropd = true)
    {fs : List Nat} {te : Ty} {ms : List Nat} {e : Val} {cs : List (Var × PMode × Ty)}
    (hs : Sub (.pkg fs te ms e cs) v) : te.holdsDtor = false := by
  induction hw with
  | int => cases hs
  | view => cases hs
  | node _ ih =>
    cases hs with
    | child he h => exact ih _ he (by simpa [Ty.noDropd] using hdf) h
  | pair _ _ iha ihb =>
    simp only [Ty.noDropd, Bool.and_eq_true] at hdf
    cases hs with
    | fst h => exact iha hdf.1 h
    | snd h => exact ihb hdf.2 h
  | inl _ ih =>
    simp only [Ty.noDropd, Bool.and_eq_true] at hdf
    cases hs with | inl h => exact ih hdf.1 h
  | inr _ ih =>
    simp only [Ty.noDropd, Bool.and_eq_true] at hdf
    cases hs with | inr h => exact ih hdf.2 h
  | pkg _ hq ih =>
    have hte := hq.2.2.2.1 (by simpa [Ty.noDropd] using hdf)
    cases hs with
    | refl => exact hte
    | pkg h => exact ih (Ty.noDropd_of_free hte) h
  | arc _ _ => cases hs
  | rguard _ _ => cases hs
  | lk => cases hs
  | cell => cases hs
  | dtor _ _ ih => exact ih (by simpa [Ty.noDropd] using hdf) hs

/-- **A2-drop.3c: in a running configuration no package an owner's slot
    holds, at any depth of a tree whose type has no closure of the dropping
    class in it, has an environment that holds a destructor value** (one in
    a block's payload: `blk_pkgs_env_dtor_free`).  So the environment a
    closure's or a trait object's drop releases with no code holds no
    destructor value.  (Agora #609: a closure of the dropping class is a
    destructor value itself, `Ty.holdsDtor`, bound by `letd` with its glue,
    which calls its drop method: `closure_dtor_is_glue`.) -/
theorem pkgs_env_dtor_free {m : Mem} {Γ : Ctx} (hi : MInv m Γ) {x : Var} {E : Entry}
    (hx : Γ x = some E) (hm : E.mode.ownSlot = true) (hdf : E.ty.noDropd = true) {o : Bool} {T : Val}
    (hsl : m.st x = some ⟨o, some T⟩)
    {fs : List Nat} {te : Ty} {ms : List Nat} {e : Val} {cs : List (Var × PMode × Ty)}
    (hs : Sub (.pkg fs te ms e cs) T) : te.holdsDtor = false :=
  (hi.own_wfv hx hm hsl).pkg_env_dtor_free hdf hs

/-- Agora #609: the destructor of a closure of the dropping class is its
    glue, which hands the closure to its drop method (`ClosureGlueOK`); a
    destructor that takes it lent is refused for it. -/
theorem closure_dtor_is_glue {P : Prog} {f : Nat} {ms : List Nat} (h : DropFnOK P f (.fn ms .dropd)) :
    ClosureGlueOK P f (.fn ms .dropd) := by
  rcases h with ⟨_, h⟩ | ⟨_, _, _, _, ht, _⟩ | ⟨_, _, _, _, _, _, _, _, _, _, _, _, _, _, _, hg, _⟩ |
    ⟨_, _, _, _, _, _, ht, _⟩ | h
  · cases h
  · cases ht
  · rcases hg with ⟨_, _, _, _, ht, _⟩ | ⟨_, _, _, _, _, _, ht, _⟩ <;> cases ht
  · cases ht
  · exact h

/-- **Agora #609: what a drop method's code does with the environment.**
    Code that implements an interface taking the receiver owned (a closure's
    drop method, `ClosureGlueOK`) takes the environment as its own `sink`
    parameter; if the environment holds a destructor value, the code hands
    it on first thing (to a `letd`, or taken apart, `Stmt.movedFirst`) or is
    itself the glue of the environment's type (an enum's, a closure's), and
    assigns it nothing: each destructor value in it reaches a frame of its
    own before anything else of the code runs. -/
theorem drop_method_code {P : Prog} (hP : ProgOK P) {f σ : Nat} {te : Ty} {cs : List (Var × PMode × Ty)}
    (hi : Implements P f te cs σ) {sig : Fn} (hσ : P[σ]? = some sig) {pt : Ty}
    (hsp : sig.params.head? = some (.sink, pt)) (hd : te.holdsDtor = true) :
    ∃ fn, P[f]? = some fn ∧ fn.params.head? = some (.sink, te) ∧
      (0 ∈ fn.body.movedFirst ∨ ∃ g u, P[g]? = some fn ∧ (EnumGlueOK P g u ∨ ClosureGlueOK P g u)) ∧
      0 ∉ fn.body.assigns := by
  obtain ⟨fn, sig', hf, hσ', hps, _⟩ := hi
  rw [hσ] at hσ'; cases hσ'
  have hrm : sig.recvMode = .sink := by unfold Fn.recvMode; rw [hsp]
  rw [hrm] at hps
  have h0 := (fnOK_dtor_params (hP fn (List.mem_of_getElem? hf))).1 0 (by rw [hps]; simp)
    (by simp [hps]) (by simp [hps, hd])
  exact ⟨fn, hf, by rw [hps]; rfl, h0.1, h0.2⟩

/-- The payload types of the shares (`Arc`, lock, cell) that occur in a
    type, at any depth: in fields, payloads and elements, under views and
    destructor types, and inside other payloads (Agora #837: a read guard's
    lock payload among them, which its view lends). -/
def payloads : Ty → List Ty
  | .arc t => t :: payloads t
  | .lk t => t :: payloads t
  | .cell t => t :: payloads t
  | .rguard t => t :: payloads t
  | .vec t => payloads t
  | .slice t => payloads t
  | .dtor _ t => payloads t
  | .prod a b => payloads a ++ payloads b
  | .sum a b => payloads a ++ payloads b
  | .int => []
  | .fn _ _ => []

/-- ... and those of the lock and cell shares alone: what a check-out
    binding (`withLock`, `withCell`) may be of. -/
def lockPayloads : Ty → List Ty
  | .arc t => lockPayloads t
  | .lk t => t :: lockPayloads t
  | .cell t => t :: lockPayloads t
  | .rguard t => t :: lockPayloads t
  | .vec t => lockPayloads t
  | .slice t => lockPayloads t
  | .dtor _ t => lockPayloads t
  | .prod a b => lockPayloads a ++ lockPayloads b
  | .sum a b => lockPayloads a ++ lockPayloads b
  | .int => []
  | .fn _ _ => []

/-- A2-drop.3d, Agora #610: a well-formed type's share payloads own no
    destructor value, or (an `Arc`'s) are one at their top, or a drained `Vec` of them (Agora #755).
    (Agora #804 added a third case, a read guard's view `prod (lk u) u`,
    `Ty.rview`, while a guard was an `arc` share; since Agora #837 a guard is
    a type of its own, `Ty.rguard u`, whose payload `u` is a lock's.) -/
theorem ok_payloads_free {t : Ty} (h : t.ok = true) :
    ∀ u ∈ payloads t, u.dtorFree = true ∨ u.dnest = true := by
  induction t with
  | int => simp [payloads]
  | fn _ _ => simp [payloads]
  | vec t ih => simpa only [payloads] using ih (Ty.ok_vec_elem h)
  | slice t ih => simpa only [payloads] using ih (Ty.ok_slice h).1
  | arc t ih =>
    simp only [payloads, List.mem_cons]
    rintro u (rfl | hu)
    · exact Ty.ok_arc_dtor h
    · exact ih (Ty.ok_arc h).1 u hu
  | rguard t ih =>
    have hl := (Ty.ok_rguard h).1
    simp only [payloads, List.mem_cons]
    rintro u (rfl | hu)
    · exact Ty.lkPay_free_or_dnest (Ty.ok_lk_pay hl)
    · exact ih (Ty.ok_lk hl).1 u hu
  | lk t ih =>
    simp only [payloads, List.mem_cons]
    rintro u (rfl | hu)
    · exact Ty.lkPay_free_or_dnest (Ty.ok_lk_pay h)
    · exact ih (Ty.ok_lk h).1 u hu
  | cell t ih =>
    simp only [payloads, List.mem_cons]
    rintro u (rfl | hu)
    · exact Ty.lkPay_free_or_dnest (Ty.ok_cell_pay h)
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

/-- A2-drop.3d: a well-formed type's lock and cell payloads own no
    destructor value, or (Agora #755, `Locked D`) are one at their top that
    holds no cell share (`Ty.lkPay`; Agora #803: before, no share). -/
theorem ok_lockPayloads_free {t : Ty} (h : t.ok = true) : ∀ u ∈ lockPayloads t, u.lkPay = true := by
  induction t with
  | int => simp [lockPayloads]
  | fn _ _ => simp [lockPayloads]
  | vec t ih => simpa only [lockPayloads] using ih (Ty.ok_vec_elem h)
  | slice t ih => simpa only [lockPayloads] using ih (Ty.ok_slice h).1
  | arc t ih => simpa only [lockPayloads] using ih (Ty.ok_arc h).1
  | rguard t ih =>
    have hl := (Ty.ok_rguard h).1
    simp only [lockPayloads, List.mem_cons]
    rintro u (rfl | hu)
    · exact Ty.ok_lk_pay hl
    · exact ih (Ty.ok_lk hl).1 u hu
  | lk t ih =>
    simp only [lockPayloads, List.mem_cons]
    rintro u (rfl | hu)
    · exact Ty.ok_lk_pay h
    · exact ih (Ty.ok_lk h).1 u hu
  | cell t ih =>
    simp only [lockPayloads, List.mem_cons]
    rintro u (rfl | hu)
    · exact Ty.ok_cell_pay h
    · exact ih (Ty.ok_cell h).1 u hu
  | dtor _ t ih =>
    simp only [Ty.ok, Bool.and_eq_true] at h
    simpa only [lockPayloads] using ih h.2
  | prod a b iha ihb =>
    simp only [lockPayloads, List.mem_append]
    rintro u (hu | hu)
    · exact iha (Ty.ok_prod h).1 u hu
    · exact ihb (Ty.ok_prod h).2 u hu
  | sum a b iha ihb =>
    simp only [lockPayloads, List.mem_append]
    rintro u (hu | hu)
    · exact iha (Ty.ok_sum h).1 u hu
    · exact ihb (Ty.ok_sum h).2 u hu

/-- A2-drop.3d, of types: in a running configuration, the payload type of
    every share in a binding's type (an `Arc`'s, a lock's, a cell's, a
    channel's queue; not those inside a closure type, whose environment the
    type does not name) owns no destructor value, or (Agora #610, an
    `Arc`'s) is one at its top or (Agora #755) a drained `Vec` of them; a
    lock's and a cell's owns none or (Agora #755, `Locked D`) is one at its
    top that holds no cell share (`Ty.lkPay`; Agora #803: before, no
    share), so a check-out binding
    (`withLock`, `withCell`: the lock's payload type) is of a type that holds
    none, or is that destructor value, given no other value in the body
    (`StmtT.withLock`'s `hna`).  The fact about the blocks themselves is
    `blocks_dtor_free`. -/
theorem shares_dtor_free {m : Mem} {Γ : Ctx} (hi : MInv m Γ) {x : Var} {E : Entry}
    (hx : Γ x = some E) : (∀ u ∈ payloads E.ty, u.dtorFree = true ∨ u.dnest = true) ∧
      ∀ u ∈ lockPayloads E.ty, u.lkPay = true :=
  ⟨ok_payloads_free (hi.tyok hx), ok_lockPayloads_free (hi.tyok hx)⟩

/-- **A2-drop.3d, Agora #610: in a running configuration no view owns a
    destructor value (Agora #804: a view owns nothing, its payload is its
    lock block's, read in place, of a read guard's view type or owning none,
    and it is never an orphan to be nor marked `dead`, so no destructor runs
    from it), a lock block's owns none or (Agora #755,
    `Locked D`) is one at its top that holds no cell share (Agora #803;
    before, no share), and a block whose payload
    owns one (an `arc` block, or a `dead` one: an orphan whose payload
    awaits its destructor) is of a destructor type that holds no closure,
    or (Agora #755) of a drained `Vec` of such values at any depth**
    (the invariant carries it, `MInv.blocks`): every block, whatever holds
    its shares.  The sweep marks such an `arc` block `dead` when nothing
    reaches it, rather than freeing it (`Mem.sweepD`; Agora #755: such a
    lock block too, its payload in), and the thread whose
    step it ends hands the payload to a destructor frame (`Settle`,
    `Step.reap`). -/
theorem blocks_dtor_free {m : Mem} {Γ : Ctx} (hi : MInv m Γ) {k : Nat} {bl : Blk}
    (hk : m.blk k = some bl) :
    (bl.kind ≠ .dead → bl.kind ≠ .arc → bl.kind ≠ .view →
        bl.ty.dtorFree = true ∨ (bl.kind = .lock ∧ bl.ty.lkPay = true)) ∧
      (bl.ty.dtorFree = false → bl.kind ≠ .view → ∃ n f u, bl.ty = Ty.nest n (.dtor f u) ∧ u.hasFn = false) ∧
      (bl.kind = .arc → bl.ty.dtorFree = true ∨ bl.ty.dnest = true) ∧
      -- Agora #804: a view owns nothing, its payload (its lock block's, read
      -- in place) is of a read guard's view type or owns no destructor
      -- value, and it is never an orphan to be nor marked `dead`: the
      -- marking sweep keeps it as it is or removes it, so no destructor ever
      -- runs from a view
      (bl.kind = .view → bl.tree = .int 0 ∧ (bl.ty.dtorFree = true ∨ bl.ty.rview = true) ∧
        ∀ R, ¬ Cand R m.blk k ∧ (sweepBlkD R m.blk k = some bl ∨ sweepBlkD R m.blk k = none)) := by
  have hb := (hi.blocks k bl hk).2.2.2.2.1
  have harc := fun ha => Blk.DtorOK.arc hb ha
  obtain ⟨h1, _, h3⟩ := hb
  refine ⟨fun a b c => ?_, h3, harc, fun hv => ?_⟩
  · rcases h1 a b with h | h | ⟨h, _⟩
    · exact Or.inl h
    · exact Or.inr h
    · exact absurd h c
  · obtain ⟨t, kd, p⟩ := bl
    simp only at hv; subst hv
    have hnc : ∀ R, ¬ Cand R m.blk k := fun R ⟨⟨n, f, u, p', kd, hkd, hk'⟩, _⟩ => by
      rw [hk] at hk'; cases hk'; rcases hkd with h | h <;> cases h
    refine ⟨rfl, ?_, fun R => ⟨hnc R, ?_⟩⟩
    · rcases h1 (by simp) (by simp) with h | ⟨h, _⟩ | ⟨_, h⟩
      · exact Or.inl h
      · cases h
      · exact Or.inr h
    · unfold sweepBlkD
      by_cases hr : Reached (RootsD R m.blk) m.blk k
      · left; simp [hr, hk]
      · right
        have hnp : ¬ Pinned R m.blk k := by
          rintro (⟨hc, _⟩ | ⟨n, f, u, p', hk'⟩)
          · exact hnc R hc
          · rw [hk] at hk'; cases hk'
        simp [hr, hnp]

/-- **Agora #804, the block-level fact behind an `Arc`'s type**: in a running
    configuration every `arc` block (made by `arc_new`, shared by its
    clones, or a global's) is of a type that owns no destructor value, or is
    one at its top, or a drained `Vec` of them.  A share's type says less
    (`Ty.ok_arc_dtor`: a read guard's is a share of a view, `Ty.rview`), but
    only a view is of a read guard's view type.  (Since Agora #837 a share's
    type says it too, `Ty.ok_arc_dtor`: a read guard is of a type of its
    own, `Ty.rguard`.) -/
theorem arc_blocks_dtor {m : Mem} {Γ : Ctx} (hi : MInv m Γ) {k : Nat} {bl : Blk}
    (hk : m.blk k = some bl) (ha : bl.kind = .arc) : bl.ty.dtorFree = true ∨ bl.ty.dnest = true :=
  (hi.blocks k bl hk).2.2.2.2.1.arc ha

/-- A2-drop.3c, in a block: a package in the payload of a block of a type
    that owns no destructor value (a channel of closures, a `Locked`
    closure, an `Arc` of a `sync` one), however deep, has an environment
    that holds no destructor value. -/
theorem blk_pkgs_env_dtor_free {m : Mem} {Γ : Ctx} (hi : MInv m Γ) {k : Nat} {bl : Blk}
    (hk : m.blk k = some bl) (hfree : bl.ty.dtorFree = true) {p : Val} (hp : bl.pay = some p)
    {fs : List Nat} {te : Ty} {ms : List Nat} {e : Val} {cs : List (Var × PMode × Ty)}
    (hs : Sub (.pkg fs te ms e cs) p) : te.holdsDtor = false :=
  (((hi.blocks k bl hk).2.2.1 p hp).1).pkg_env_dtor_free
    (Ty.noDropd_of_free (by rw [Ty.holdsDtor_eq_not_free]; simpa using hfree)) hs

/-- A2-drop.3d: a lock's and a library handle's constructor take a value
    that owns no destructor value or (Agora #755, `Locked D`) is one at its
    top that holds no cell share (Agora #803; before, no share); (Agora
    #610) `arc_new` takes one that
    owns none or is one at its top, or (Agora #755) a drained `Vec` of them. -/
theorem share_new_dtor_free {Γ Γ1 : Ctx} {F : List Var} {t : Ty} {y : Var} {E : Entry} :
    (RhsT Γ F (.arcNew t y) E Γ1 → t.dtorFree = true ∨ t.dnest = true) ∧
    (RhsT Γ F (.lockNew t y) E Γ1 → t.lkPay = true) ∧
    (RhsT Γ F (.cellNew t y) E Γ1 → t.lkPay = true) := by
  refine ⟨fun h => ?_, fun h => ?_, fun h => ?_⟩
  · cases h with | arcNew _ _ _ hdf _ _ _ _ => exact hdf
  · cases h with | lockNew _ _ _ hdf _ _ _ => exact hdf
  · cases h with | cellNew _ _ _ hdf _ _ _ => exact hdf

/-- A2-drop.3b: in a running configuration, a binding whose type is a `Vec`
    has elements that own no destructor value, or are of a destructor type
    themselves, or (Agora #607) drained `Vec`s in turn (`Ty.dnest`): the drained `Vec` (`Ty.vecD`), which a binding's own type
    may be, or (Agora #607) a struct's field or an enum's payload, which glue
    hands to a `letd` (`vecs_dtor_free`).  A `Vec` of the second kind is `letd`'s (`letv` refuses it), and
    its frame's end drains it (`scopeD_end_drains`); what any other `Vec`'s
    drop releases holds no destructor value: no environment of a closure
    that does not drop does (`pkgs_env_dtor_free`) and no block's payload (`blocks_dtor_free`). -/
theorem vec_elems_dtor_free {m : Mem} {Γ : Ctx} (hi : MInv m Γ) {x : Var} {E : Entry} {t : Ty}
    (hx : Γ x = some E) (ht : E.ty = .vec t) : t.dtorFree = true ∨ t.dnest = true := by
  have h := hi.tyok hx; rw [ht] at h; exact Ty.ok_vec_free h

/-- The element types of the `Vec`s that occur in a type, at any depth:
    in fields and payloads, under views, shares and destructor types. -/
def vecElems : Ty → List Ty
  | .vec t => t :: vecElems t
  | .slice t => vecElems t
  | .arc t => vecElems t
  | .rguard t => vecElems t
  | .lk t => vecElems t
  | .cell t => vecElems t
  | .dtor _ t => vecElems t
  | .prod a b => vecElems a ++ vecElems b
  | .sum a b => vecElems a ++ vecElems b
  | .int => []
  | .fn _ _ => []

/-- Every `Vec` in a well-formed type has elements that own no destructor
    value, or are of a destructor type themselves, or `Vec`s of them in turn (a
    drained `Vec`, `Ty.dnest`). -/
theorem ok_vecElems {t : Ty} (h : t.ok = true) :
    ∀ u ∈ vecElems t, u.dtorFree = true ∨ u.dnest = true := by
  induction t with
  | int => simp [vecElems]
  | fn _ _ => simp [vecElems]
  | vec t ih =>
    simp only [vecElems, List.mem_cons]
    rintro u (rfl | hu)
    · exact Ty.ok_vec_free h
    · exact ih (Ty.ok_vec_elem h) u hu
  | slice t ih =>
    simp only [Ty.ok, Bool.and_eq_true, Bool.not_eq_true'] at h; simpa only [vecElems] using ih h.1
  | arc t ih =>
    simp only [Ty.ok, Bool.and_eq_true, Bool.not_eq_true'] at h; simpa only [vecElems] using ih h.1.1.1
  | rguard t ih =>
    simp only [Ty.ok, Bool.and_eq_true, Bool.not_eq_true'] at h; simpa only [vecElems] using ih h.1.1.1.1
  | lk t ih =>
    simp only [Ty.ok, Bool.and_eq_true, Bool.not_eq_true'] at h; simpa only [vecElems] using ih h.1.1.1
  | cell t ih =>
    simp only [Ty.ok, Bool.and_eq_true, Bool.not_eq_true'] at h; simpa only [vecElems] using ih h.1.1.1
  | dtor _ t ih =>
    simp only [Ty.ok, Bool.and_eq_true] at h
    simpa only [vecElems] using ih h.2
  | prod a b iha ihb =>
    have h' := Ty.ok_prod h
    simp only [vecElems, List.mem_append]
    rintro u (hu | hu)
    · exact iha h'.1 u hu
    · exact ihb h'.2 u hu
  | sum a b iha ihb =>
    have h' := Ty.ok_sum h
    simp only [vecElems, List.mem_append]
    rintro u (hu | hu)
    · exact iha h'.1 u hu
    · exact ihb h'.2 u hu

/-- A2-drop.3b, the deep form: in a running configuration, every `Vec`
    occurring anywhere in a binding's type has elements free of destructor
    values, or of a destructor type, or `Vec`s of them in turn: a drained `Vec`.  (Agora #607: a
    drained `Vec` is a binding's own type, a struct's field or an enum's
    payload, which the struct's or the enum's glue hands to a `letd`, or an
    element type's field in turn, or (Agora #755) an `Arc`'s payload; a
    lock's or a cell's payload holds none: `Ty.ok` asks `dtorFree` there,
    `ok_lockPayloads_free`.  A view's
    element type may name one inside a struct; a view owns nothing.) -/
theorem vecs_dtor_free {m : Mem} {Γ : Ctx} (hi : MInv m Γ) {x : Var} {E : Entry}
    (hx : Γ x = some E) : ∀ u ∈ vecElems E.ty, u.dtorFree = true ∨ u.dnest = true :=
  ok_vecElems (hi.tyok hx)

/-- A2-drop.3b: `vec_new` makes a `Vec` whose elements own no destructor
    value, or a drained one, of a destructor type's elements or (Agora #607)
    of drained `Vec`s. -/
theorem new_dtor_free {Γ Γ1 : Ctx} {F : List Var} {t : Ty} {E : Entry}
    (h : RhsT Γ F (.new t) E Γ1) : t.dtorFree = true ∨ t.dnest = true := by
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
    (h : StmtT P ξ Γ F (.letv x r s) Δ) :
    ∃ Γ0 E Γ1, RhsT Γ0 F r E Γ1 ∧ (E.mode = .own → E.ty.dtorFree = true) := by
  obtain ⟨Γ0, E, Γ1, hr, hnd⟩ := letv_owned_no_dtor h
  refine ⟨Γ0, E, Γ1, hr, fun hm => ?_⟩
  have h1 := hnd hm
  rw [Ty.holdsDtor_eq_not_free] at h1
  simpa using h1

end A2.Dtor
