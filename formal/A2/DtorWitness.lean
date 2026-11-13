import A2.DynCell

/-! # A2-drop.3a: the destructor on the type, checked

Two kinds of fact, both checked here (`check.sh` prints their axioms):

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
    (h : StmtT P Γ F (.letd x f r s) Δ) :
    ∃ Γ0 E Γ1, RhsT Γ0 F r E Γ1 ∧ TakeOK P Γ0 r := by
  generalize hst : Stmt.letd x f r s = st at h
  induction h with
  | letd _ _ _ hr _ _ _ _ hok _ _ _ _ => cases hst; exact ⟨_, _, _, hr, hok.2⟩
  | sub _ _ _ ih => exact ih hst
  | _ => cases hst

theorem assign_take_is_glue {P : Prog} {Γ Δ : Ctx} {F : List Var} {x : Var} {r : Rhs}
    (h : StmtT P Γ F (.assign x r) Δ) :
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
    {m : Mem} {v : Val} (ht : StmtT P Γ F (.scopeD x f .skip) Δ)
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
    (h : StmtT P Γ F (.letd x f r s) Δ) :
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
    of such values (Agora #782: whose elements may hold views); `f` is a `DtorOK` destructor
    of `Ty.dtor f t`, a struct's or an enum's. -/
theorem scopeD_typed {P : Prog} {Γ Δ : Ctx} {F : List Var} {x : Var} {f : Nat} {s : Stmt}
    (h : StmtT P Γ F (.scopeD x f s) Δ) :
    ∃ (E : Entry) (t : Ty), Γ x = some E ∧ E.mode = .own ∧ ScopeDTy f t E.ty ∧
      DropFnOK P f t ∧ t.isStruct = true := by
  generalize hst : Stmt.scopeD x f s = st at h
  induction h with
  | scopeD hE _ _ _ _ _ _ _ _ =>
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
    `scopeD_end_empty`'s steps drain it), or (Agora #607, `n > 0`) of such
    `Vec`s, each of which the drain binds by a frame of the same `f`. -/
theorem scopeD_frame_value {P : Prog} {Γ Δ : Ctx} {F : List Var} {x : Var} {f : Nat} {s : Stmt}
    {m : Mem} {v : Val} (ht : StmtT P Γ F (.scopeD x f s) Δ) (hi : MInv m Γ)
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

/-- No entry views anything. -/
def NoDeps (Γ : Ctx) : Prop := ∀ v E, Γ v = some E → E.vdeps = []

theorem NoDeps.setE {Γ : Ctx} (h : NoDeps Γ) {x : Var} {E : Entry} (hE : E.vdeps = []) :
    NoDeps (A2.setE Γ x E) := fun v E' hv => by
  by_cases hvx : v = x
  · subst hvx; simp [A2.setE] at hv; subst hv; exact hE
  · rw [A2.setE, upd_ne _ _ hvx] at hv; exact h v E' hv

theorem NoDeps.kill {Γ : Ctx} (h : NoDeps Γ) (e : Eff) (hv : Bool) (x : Var) :
    NoDeps (A2.kill e hv x Γ) := fun v E' hv' => by
  simp only [A2.kill] at hv'
  cases h0 : Γ v with
  | none => rw [h0] at hv'; cases hv'
  | some E0 =>
    rw [h0] at hv'; simp only [Option.map_some, Option.some.injEq] at hv'; subst hv'
    have := h v E0 h0
    unfold killE; split
    · simpa [Entry.vdeps] using this
    · exact this

theorem NoDeps.kill_eq {Γ : Ctx} (h : NoDeps Γ) (e : Eff) (hv : Bool) (x : Var) :
    A2.kill e hv x Γ = Γ := by
  funext v
  cases h0 : Γ v with
  | none => simp [A2.kill, h0]
  | some E =>
    simp only [A2.kill, h0, Option.map_some, Option.some.injEq]
    unfold killE
    have : hits e hv x E = false := by simp [hits, h v E h0]
    rw [this]; rfl

theorem NoDeps.wf {Γ : Ctx} (h : NoDeps Γ) (hf : NoRootb Γ) : CtxWF Γ :=
  ⟨fun v E hE _ _ r hr => by rw [h v E hE] at hr; simp [roots] at hr,
    fun v E hE hd => (by rw [(hf v E hE).2.2] at hd; cases hd),
    fun v E hE hd => (by rw [(hf v E hE).2.1] at hd; cases hd),
    fun v E hE hd => (by rw [(hf v E hE).2.2] at hd; cases hd)⟩

theorem NoDeps.names {Γ : Ctx} (h : NoDeps Γ) : NameWF Γ :=
  fun v E hE _ _ => by simp [NameOK, DepsNamed, h v E hE]


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
    destructor is its glue (Agora #632): it takes the option owned and, on
    `Some`, moves the payload out to a `letd` of its own:
    `@ ofn sink self → i { ? ( isl self ) { :drop y ( takel self )  = r 0 } { = r 0 } }`. -/
def OT : Ty := .sum DT .int
def ODT : Ty := .dtor 2 OT

def ofn : Fn where
  params := [(.sink, ODT)]
  resTy := .int
  resOwn := false
  lends := []
  rholds := []
  outHolds := []
  body := .ite (.isl 0) (.letd 2 0 (.takel 0) (.assign 1 (.expr (.lit 0)))) (.assign 1 (.expr (.lit 0)))
  nvars := 3

/-- A2-drop.3b: an enum one variant of which holds a struct holding a
    destructor value, `sum (prod DT int) int`: the destructor value is two
    levels down, under a struct of no destructor type of its own.  Its glue
    (Agora #632) moves that struct out to a `letd` at the struct's glue type
    (`GDT`, whose glue takes it apart). -/
def AT : Ty := .prod DT .int
def ST : Ty := .sum AT .int
def SDT : Ty := .dtor 3 ST

def gfn : Fn where
  params := [(.sink, SDT)]
  resTy := .int
  resOwn := false
  lends := []
  rholds := []
  outHolds := []
  body := .ite (.isl 0) (.letd 2 4 (.takel 0) (.assign 1 (.expr (.lit 0)))) (.assign 1 (.expr (.lit 0)))
  nvars := 3

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

/-- Agora #607: a struct whose field is a `Vec` of destructor values, and
    its glue: `@ glueV sink self → i { unpair self x z  :drop y x  = r 0 }`,
    the `letd` at the `Vec`'s own type, which drains it. -/
def GV : Ty := .prod (.vec DT) .int
def GVD : Ty := .dtor 7 GV

def glueV : Fn where
  params := [(.sink, GVD)]
  resTy := .int
  resOwn := false
  lends := []
  rholds := []
  outHolds := []
  body := .unpair 0 2 3 (.letd 4 0 (.var 2) (.assign 1 (.expr (.lit 0))))
  nvars := 5

/-- Agora #633: a struct with a destructor field and a view field (nurlc's
    `: P { Conn c s name }`), and its glue:
    `@ glueS sink self → i { unpair self x z  :drop y x  = r 0 }`. -/
def GS : Ty := .prod DT (.slice .int)
def GSD : Ty := .dtor 8 GS

def glueS : Fn where
  params := [(.sink, GSD)]
  resTy := .int
  resOwn := false
  lends := []
  rholds := []
  outHolds := []
  body := .unpair 0 2 3 (.letd 4 0 (.var 2) (.assign 1 (.expr (.lit 0))))
  nvars := 5

/-- Agora #750: an enum with a destructor payload and a view payload,
    `sum DT (slice int)` (nurlc's `| Conn c | Name s`), bound at the
    destructor type whose destructor is its glue: on the first variant the
    payload moves out to a `letd` of its own; the second, a view, needs no
    code:
    `@ ofnV sink self → i { ? ( isl self ) { :drop y ( takel self )  = r 0 } { = r 0 } }`. -/
def OV : Ty := .sum DT (.slice .int)
def OVD : Ty := .dtor 9 OV

def ofnV : Fn where
  params := [(.sink, OVD)]
  resTy := .int
  resOwn := false
  lends := []
  rholds := []
  outHolds := []
  body := .ite (.isl 0) (.letd 2 0 (.takel 0) (.assign 1 (.expr (.lit 0)))) (.assign 1 (.expr (.lit 0)))
  nvars := 3

/-- Agora #750: the struct `GS` (a destructor field and a view field) with a
    `% Drop` of its own: its impl takes it lent, at the fields' glue type
    `GSD`: `@ drop in self → i { = r 0 }` ... -/
def implS : Fn where
  params := [(.inp, GSD)]
  resTy := .int
  resOwn := false
  lends := []
  rholds := []
  outHolds := []
  body := .assign 1 (.expr (.lit 0))
  nvars := 2

/-- ... and its glue takes it owned, rebinds it under the fields' glue
    `glueS` and runs the impl on it lent:
    `@ glueS2 sink self → i { :drop w self  ( implS w )  = r 0 }`. -/
def GSD2 : Ty := .dtor 11 GS

def glueS2 : Fn where
  params := [(.sink, GSD2)]
  resTy := .int
  resOwn := false
  lends := []
  rholds := []
  outHolds := []
  body := .letd 2 8 (.var 0) (.letcall 3 10 [2] (.assign 1 (.expr (.lit 0))))
  nvars := 4

/-- Agora #805: the glue of the option a channel's receive hands out,
    `Option DT` as nurlc's `chan_recv` returns it: `sum int DT`, the payload
    in the right variant:
    `@ ofnR sink self → i { ? ( isl self ) { = r 0 } { :drop y ( taker self )  = r 0 } }`. -/
def RT : Ty := .sum .int DT
def RDT : Ty := .dtor 12 RT

def ofnR : Fn where
  params := [(.sink, RDT)]
  resTy := .int
  resOwn := false
  lends := []
  rholds := []
  outHolds := []
  body := .ite (.isl 0) (.assign 1 (.expr (.lit 0))) (.letd 2 0 (.taker 0) (.assign 1 (.expr (.lit 0))))
  nvars := 3

def P : Prog := [dfn, mk, ofn, gfn, glue, impl, glue2, glueV, glueS, ofnV, implS, glueS2, ofnR]

theorem dfn_not_thru : ¬ ThruFn P 0 := by
  intro h
  cases h with
  | here hf hb => simp [P] at hf; subst hf; simp [dfn, Stmt.hasThru] at hb
  | call hf hg _ => simp [P] at hf; subst hf; simp [dfn, Stmt.calls] at hg

theorem dtor_ok : DtorOK P 0 DT :=
  ⟨dfn, rfl, rfl, rfl, rfl, rfl, rfl, rfl, dfn_not_thru⟩

theorem drop_ok : DropFnOK P 0 T := Or.inl ⟨dtor_ok, by decide⟩

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
    simp [ED, EP, Entry.arm, DT, T, Ty.dtorViews, Ty.holdsView]
  have hK3 : NoRootb (A2.setE K2 2 ED) := hK2.setE hED
  have hpair : RhsT K2 [] (.pair 0 1) EP K2 :=
    RhsT.pair (Ey := intE) (Ez := intE) (by simp [K2, K1, A2.setE, upd]) rfl PushArg.int
      (by simp [K2, K1, A2.setE, upd]) rfl PushArg.int (by simp [intE, Mode.ownSlot])
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


/-! ### The maker: a function whose owned result is a destructor value -/

def Rr : Entry := ⟨DT, .own, false, [], [], false, false⟩
def EDd : Entry := Entry.arm { EP with ty := DT, held := [] }

theorem EDd_eq : EDd = ⟨DT, .own, true, [], [], false, false⟩ := by
  simp [EDd, EP, Entry.arm, DT, T, Ty.dtorViews, Ty.holdsView]

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
      (by simp [C2, A2.setE, upd]) rfl PushArg.int (by simp [intE, Mode.ownSlot])
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
  ⟨glue, DT, .int, rfl, rfl, rfl, rfl, rfl, rfl, rfl, rfl, glue_not_thru, 2, 3, _, rfl, rfl⟩

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
    simp only [ED]; rw [hEx]; simp [Entry.arm, DT, T, Ty.dtorViews, Ty.holdsView]
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

/-! ### A struct with a `Vec` of destructor values for a field (Agora #607)

`prod (vec DT) int`: its glue takes it apart and hands the `Vec` to a
`letd` at its own type, whose frame drains it, each element's destructor
running in its own frame. -/

theorem glueV_not_thru : ¬ ThruFn P 7 := by
  intro h
  cases h with
  | here hf hb => simp [P] at hf; subst hf; simp [glueV, Stmt.hasThru] at hb
  | call hf hg ht => simp [P] at hf; subst hf; simp [glueV, Stmt.calls] at hg; subst hg; exact dfn_not_thru ht

theorem glueV_glueOK : GlueOK P 7 GV :=
  ⟨glueV, .vec DT, .int, rfl, rfl, rfl, rfl, rfl, rfl, rfl, rfl, glueV_not_thru, 2, 3, _, rfl, rfl⟩

theorem gvdrop_ok : DropFnOK P 7 GV := Or.inr (Or.inl glueV_glueOK)

def EGV : Entry := ⟨GVD, .own, true, [], [], false, false⟩

theorem glueV_body : ∃ Δ, StmtT P (sigCtx glueV) [] glueV.body Δ ∧
    (∀ v E, Δ v = some E → E.mode ≠ .rootb ∧ E.dtor = false ∧ E.dbind = false) ∧
    Δ 1 = some { intE with mode := R0.mode } := by
  have h0 : sigCtx glueV 0 = some EGV := by simp [sigCtx, glueV, paramE, EGV, GVD, GV, DT, T, Ty.hasFn]
  have h1 : sigCtx glueV 1 = some R0 := by simp [sigCtx, glueV, R0, resMode]
  have hS : NoRootb (sigCtx glueV) := by
    intro v E h
    rcases v with _ | _ | v
    · rw [h0] at h; cases h; simp [EGV]
    · rw [h1] at h; cases h; simp [R0]
    · simp [sigCtx, glueV] at h
  let Ka : Ctx := A2.setE (A2.setE (A2.setE (kill .replace false 0 (sigCtx glueV)) 0
    { EGV with live := false, dtor := false }) 2 (compE EGV (.vec DT))) 3 (compE EGV .int)
  have hKa : NoRootb Ka :=
    (((hS.kill _ _ _).setE (by simp [EGV])).setE (by simp [compE, DT])).setE (by simp [compE, intE])
  have hEx : compE EGV (.vec DT) = ⟨.vec DT, .own, true, [], [], false, false⟩ := by
    simp [compE, DT, EGV, ownHeld]
  let Kb : Ctx := A2.setE (kill .replace false 2 Ka) 2 { compE EGV (.vec DT) with live := false, dtor := false }
  have hKb : NoRootb Kb := (hKa.kill _ _ _).setE (by rw [hEx]; simp)
  have hmv : RhsT Ka [] (.var 2) ⟨(compE EGV (.vec DT)).ty, .own, true, [], (compE EGV (.vec DT)).held, false, false⟩ Kb :=
    RhsT.moveOwn (by simp [Ka, A2.setE, upd]) (by rw [hEx]) (by rw [hEx]) (by simp) (hKa.noPin _)
      (DtorSafe.of_none (fun v E h => (hKa v E h).2.1) _ _ _)
  let ED : Entry := Entry.arm { (⟨(compE EGV (.vec DT)).ty, .own, true, [], (compE EGV (.vec DT)).held, false, false⟩ : Entry)
    with ty := .vec DT, held := (compE EGV (.vec DT)).held }
  have hED : ED = ⟨.vec DT, .own, true, [], [], false, false⟩ := by
    simp only [ED]; rw [hEx]; simp [Entry.arm, DT, T, Ty.dtorViews, Ty.holdsView]
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
    (s := .assign 1 (.expr (.lit 0))) (t := T) (H := (compE EGV (.vec DT)).held) (τ := .vec DT) rfl
    (by simp [Ka, A2.setE, upd, A2.kill, sigCtx, glueV]) (by simp) hmv rfl
    (Or.inr ⟨0, rfl, by rw [hEx]⟩) rfl rfl (letd_fn drop_ok) (HeldUp.refl _ _) hasg (hKd.endOK _)
    (by simp [Stmt.assigns])
  have hun := StmtT.unpair (P := P) (Γ := sigCtx glueV) (F := []) (y := 0) (x := 2) (z := 3)
    (s := .letd 4 0 (.var 2) (.assign 1 (.expr (.lit 0)))) (E := EGV) (a := .vec DT) (b := .int)
    rfl h0 rfl (Or.inl rfl) (Or.inr ⟨7, rfl, glueV_glueOK⟩) (by simp)
    (by simp [sigCtx, glueV]) (by simp [sigCtx, glueV]) (by decide) (by simp) (by simp) hlet
    (hS.noPin _) (DtorSafe.of_none (fun v E h => (hS v E h).2.1) _ _ _)
    ((hKd.exitScope 4).endOK _) (((hKd.exitScope 4).exitScope 3).endOK _)
    (fun _ => by simp [Stmt.movedFirst, Stmt.assigns]) (fun h => by simp [Ty.holdsDtor] at h)
  refine ⟨_, hun, (((hKd.exitScope 4).exitScope 3).exitScope 2), ?_⟩
  simp [exitScope, upd, A2.kill, Kd, A2.setE, killE, hits, intE, Entry.vdeps, R0]

theorem glueV_ok : FnOK P glueV := by
  obtain ⟨Δ, hb, hfl, hr⟩ := glueV_body
  refine ⟨rfl, by decide, by decide, rfl, by simp [glueV], ?_, by simp [glueV], by simp [glueV], by simp [glueV],
    by simp [glueV], by simp [glueV], ?_, Δ, hb, fun v E h => (hfl v E h).2, ?_, ?_⟩
  · intro pt hpt; simp [glueV] at hpt; subst hpt; simp [GVD, GV, DT, T, Ty.ok, Ty.isStruct, Ty.owning, Ty.vecD]
  · refine ⟨fun i hi hs _ => ?_, fun i hi b hb _ => ?_, fun h => by simp [glueV] at h⟩
    · simp [glueV] at hi; subst hi; simp [glueV, Stmt.movedFirst, Stmt.assigns]
    · simp [glueV] at hi; subst hi; simp [glueV] at hb
  · exact ⟨{ intE with mode := R0.mode }, by simpa [glueV] using hr, rfl, rfl, by simp [R0, resMode, glueV],
      by simp [intE], by simp [intE], by simp [glueV]⟩
  · intro i hi b hb; simp [glueV] at hi; subst hi; simp [glueV] at hb

/-! ### A struct with a destructor field and a view field (Agora #633)

`prod DT (slice int)`: its glue takes it apart as `glue` does; the view
field is a borrow, which ends with the glue's scope.  The callee sees its
parameter as holding nothing (`paramE`): what the view is valid through is
the caller's, which the call keeps. -/

theorem glueS_not_thru : ¬ ThruFn P 8 := by
  intro h
  cases h with
  | here hf hb => simp [P] at hf; subst hf; simp [glueS, Stmt.hasThru] at hb
  | call hf hg ht => simp [P] at hf; subst hf; simp [glueS, Stmt.calls] at hg; subst hg; exact dfn_not_thru ht

theorem glueS_glueOK : GlueOK P 8 GS :=
  ⟨glueS, DT, .slice .int, rfl, rfl, rfl, rfl, rfl, rfl, rfl, rfl, glueS_not_thru, 2, 3, _, rfl, rfl⟩

theorem gsdrop_ok : DropFnOK P 8 GS := Or.inr (Or.inl glueS_glueOK)

def EGS : Entry := ⟨GSD, .own, true, [], [], false, false⟩

theorem glueS_body : ∃ Δ, StmtT P (sigCtx glueS) [] glueS.body Δ ∧
    (∀ v E, Δ v = some E → E.mode ≠ .rootb ∧ E.dtor = false ∧ E.dbind = false) ∧
    Δ 1 = some { intE with mode := R0.mode } := by
  have h0 : sigCtx glueS 0 = some EGS := by simp [sigCtx, glueS, paramE, EGS, GSD, GS, DT, T, Ty.hasFn]
  have h1 : sigCtx glueS 1 = some R0 := by simp [sigCtx, glueS, R0, resMode]
  have hS : NoRootb (sigCtx glueS) := by
    intro v E h
    rcases v with _ | _ | v
    · rw [h0] at h; cases h; simp [EGS]
    · rw [h1] at h; cases h; simp [R0]
    · simp [sigCtx, glueS] at h
  let Ka : Ctx := A2.setE (A2.setE (A2.setE (kill .replace false 0 (sigCtx glueS)) 0
    { EGS with live := false, dtor := false }) 2 (compE EGS DT)) 3 (compE EGS (.slice .int))
  have hKa : NoRootb Ka :=
    (((hS.kill _ _ _).setE (by simp [EGS])).setE (by simp [compE, DT])).setE (by simp [compE])
  have hEx : compE EGS DT = ⟨DT, .own, true, [], [], false, false⟩ := by
    simp [compE, DT, EGS, ownHeld]
  let Kb : Ctx := A2.setE (kill .replace false 2 Ka) 2 { compE EGS DT with live := false, dtor := false }
  have hKb : NoRootb Kb := (hKa.kill _ _ _).setE (by rw [hEx]; simp)
  have hmv : RhsT Ka [] (.var 2) ⟨(compE EGS DT).ty, .own, true, [], (compE EGS DT).held, false, false⟩ Kb :=
    RhsT.moveOwn (by simp [Ka, A2.setE, upd]) (by rw [hEx]) (by rw [hEx]) (by simp) (hKa.noPin _)
      (DtorSafe.of_none (fun v E h => (hKa v E h).2.1) _ _ _)
  let ED : Entry := Entry.arm { (⟨(compE EGS DT).ty, .own, true, [], (compE EGS DT).held, false, false⟩ : Entry)
    with ty := DT, held := (compE EGS DT).held }
  have hED : ED = ⟨DT, .own, true, [], [], false, false⟩ := by
    simp only [ED]; rw [hEx]; simp [Entry.arm, DT, T, Ty.dtorViews, Ty.holdsView]
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
    (s := .assign 1 (.expr (.lit 0))) (t := T) (H := (compE EGS DT).held) (τ := DT) rfl
    (by simp [Ka, A2.setE, upd, A2.kill, sigCtx, glueS]) (by simp) hmv rfl
    (Or.inl ⟨rfl, Or.inr ⟨0, by rw [hEx]; rfl⟩⟩) rfl rfl (letd_fn drop_ok) (HeldUp.refl _ _) hasg (hKd.endOK _)
    (by simp [Stmt.assigns])
  have hun := StmtT.unpair (P := P) (Γ := sigCtx glueS) (F := []) (y := 0) (x := 2) (z := 3)
    (s := .letd 4 0 (.var 2) (.assign 1 (.expr (.lit 0)))) (E := EGS) (a := DT) (b := .slice .int)
    rfl h0 rfl (Or.inl rfl) (Or.inr ⟨8, rfl, glueS_glueOK⟩) (by simp)
    (by simp [sigCtx, glueS]) (by simp [sigCtx, glueS]) (by decide) (by simp) (by simp) hlet
    (hS.noPin _) (DtorSafe.of_none (fun v E h => (hS v E h).2.1) _ _ _)
    ((hKd.exitScope 4).endOK _) (((hKd.exitScope 4).exitScope 3).endOK _)
    (fun _ => by simp [Stmt.movedFirst, Stmt.assigns]) (fun h => by simp [Ty.holdsDtor] at h)
  refine ⟨_, hun, (((hKd.exitScope 4).exitScope 3).exitScope 2), ?_⟩
  simp [exitScope, upd, A2.kill, Kd, A2.setE, killE, hits, intE, Entry.vdeps, R0]

theorem glueS_ok : FnOK P glueS := by
  obtain ⟨Δ, hb, hfl, hr⟩ := glueS_body
  refine ⟨rfl, by decide, by decide, rfl, by simp [glueS], ?_, by simp [glueS], by simp [glueS], by simp [glueS],
    by simp [glueS], by simp [glueS], ?_, Δ, hb, fun v E h => (hfl v E h).2, ?_, ?_⟩
  · intro pt hpt; simp [glueS] at hpt; subst hpt
    simp [GSD, GS, DT, T, Ty.ok, Ty.isStruct, Ty.owning, Ty.vecD, Ty.holdsView]
  · refine ⟨fun i hi hs _ => ?_, fun i hi b hb _ => ?_, fun h => by simp [glueS] at h⟩
    · simp [glueS] at hi; subst hi; simp [glueS, Stmt.movedFirst, Stmt.assigns]
    · simp [glueS] at hi; subst hi; simp [glueS] at hb
  · exact ⟨{ intE with mode := R0.mode }, by simpa [glueS] using hr, rfl, rfl, by simp [R0, resMode, glueS],
      by simp [intE], by simp [intE], by simp [glueS]⟩
  · intro i hi b hb; simp [glueS] at hi; subst hi; simp [glueS] at hb

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
  ⟨glue2, 2, 3, .lit 0, rfl, rfl, rfl, rfl, rfl, rfl, rfl, rfl, glue2_not_thru,
    Or.inl glue_glueOK, impl_dtorOK, rfl⟩

theorem impldrop_ok : DropFnOK P 6 GT := Or.inr (Or.inr (Or.inl ⟨4, 5, glue2_implOK⟩))

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
    simp [EW, ES2, Entry.arm, GDT, GT, DT, T, Ty.dtorViews, Ty.holdsView]
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
    ⟨⟨gluedrop_ok, fun g hg _ => by
      have hg6 : g = 6 := (Ty.dtor.inj hg).1.symm
      subst hg6
      exact ⟨5, 3, _, glue2_implOK, rfl⟩⟩,
      TakeOK.triv (fun y => ⟨(by intro h; cases h), (by intro h; cases h)⟩)⟩
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

/-! ### An enum's glue (Agora #632): `ofn`

`@ ofn sink self → i { ? ( isl self ) { :drop y ( takel self )  = r 0 } { = r 0 } }`:
the glue takes the enum owned and matches on its tag; the payload that
holds a destructor value moves out to a `letd`. -/

theorem ofn_not_thru : ¬ ThruFn P 2 := by
  intro h
  cases h with
  | here hf hb => simp [P] at hf; subst hf; simp [ofn, Stmt.hasThru] at hb
  | call hf hg ht => simp [P] at hf; subst hf; simp [ofn, Stmt.calls] at hg; subst hg; exact dfn_not_thru ht

theorem ofn_enumOK : EnumGlueOK P 2 OT :=
  ⟨ofn, DT, .int, _, _, rfl, rfl, rfl, rfl, rfl, rfl, rfl, rfl, ofn_not_thru, rfl, rfl, rfl,
    fun _ => ⟨2, 0, _, rfl⟩, fun h => absurd h (by decide)⟩

theorem odrop_ok : DropFnOK P 2 OT := Or.inr (Or.inr (Or.inr (Or.inl ofn_enumOK)))

theorem ofn_body : ∃ Δ, StmtT P (sigCtx ofn) [] ofn.body Δ ∧
    (∀ v E, Δ v = some E → E.mode ≠ .rootb ∧ E.dtor = false ∧ E.dbind = false) ∧
    Δ 1 = some { intE with mode := R0.mode } := by
  let E0 : Entry := ⟨ODT, .own, true, [], [], false, false⟩
  let I : Entry := { intE with mode := R0.mode }
  have h0 : sigCtx ofn 0 = some E0 := by simp [sigCtx, ofn, paramE, E0, ODT, OT, DT, T, Ty.hasFn]
  have h1 : sigCtx ofn 1 = some R0 := by simp [sigCtx, ofn, R0, resMode]
  have h2 : ∀ v : Nat, v ≠ 0 → v ≠ 1 → sigCtx ofn v = none := by
    intro v hv0 hv1
    have hlt : ¬ v < 1 := fun h => hv0 (Nat.lt_one_iff.mp h)
    simp [sigCtx, ofn, hlt, hv1]
  have hS : NoRootb (sigCtx ofn) := by
    intro v E h
    rcases v with _ | _ | v
    · rw [h0] at h; cases h; simp [E0]
    · rw [h1] at h; cases h; simp [R0]
    · rw [h2 _ (by simp) (by simp)] at h; cases h
  have hSd : NoDeps (sigCtx ofn) := by
    intro v E h
    rcases v with _ | _ | v
    · rw [h0] at h; cases h; rfl
    · rw [h1] at h; cases h; rfl
    · rw [h2 _ (by simp) (by simp)] at h; cases h
  -- the arm that takes the payload out
  let Ka : Ctx := A2.setE (kill .replace false 0 (sigCtx ofn)) 0 { E0 with live := false, dtor := false }
  have hKa : NoRootb Ka := (hS.kill _ _ _).setE (by simp [E0])
  have hKad : NoDeps Ka := (hSd.kill _ _ _).setE rfl
  have hEx : compE E0 DT = ⟨DT, .own, true, [], [], false, false⟩ := by
    simp [compE, E0, ownHeld, DT, T]
  have htk : RhsT (sigCtx ofn) [] (.takel 0) (compE E0 DT) Ka :=
    RhsT.takel (b := .int) h0 rfl rfl (Or.inr ⟨2, rfl, by decide⟩) (by simp) (hS.noPin _)
      (DtorSafe.of_none (fun v E h => (hS v E h).2.1) _ _ _)
  let ED : Entry := Entry.arm { compE E0 DT with ty := DT, held := (compE E0 DT).held }
  have hED : ED = ⟨DT, .own, true, [], [], false, false⟩ := by
    simp only [ED]; rw [hEx]; simp [Entry.arm, DT, T, Ty.dtorViews, Ty.holdsView]
  let Kb : Ctx := A2.setE Ka 2 ED
  have hKb : NoRootb Kb := hKa.setE (by rw [hED]; simp)
  have hKbd : NoDeps Kb := hKad.setE (by rw [hED]; rfl)
  have hc1 : Kb 1 = some R0 := by
    simp [Kb, Ka, A2.setE, upd, hSd.kill_eq, h1]
  let Kc : Ctx := A2.setE (kill .replace false 1 Kb) 1 I
  have hKc : NoRootb Kc := (hKb.kill _ _ _).setE (by simp [I, intE, R0])
  have hKcd : NoDeps Kc := (hKbd.kill _ _ _).setE rfl
  have hasg1 : StmtT P Kb [] (.assign 1 (.expr (.lit 0))) Kc :=
    StmtT.assign (Ex := R0) (E := intE) hc1 (by simp) (Or.inr (Or.inr ⟨rfl, rfl⟩))
      (RhsT.expr ExprT.lit) rfl (by simp [intE, roots, Entry.vdeps, Mode.ownSlot]) (by simp [hc1])
      (hKb.noPin _) (DtorSafe.of_none (fun v E h => (hKb v E h).2.1) _ _ _) rfl
  have harm1 := StmtT.letd (P := P) (Γ := sigCtx ofn) (Γ1 := Ka) (F := []) (x := 2) (f := 0) (r := .takel 0)
    (s := .assign 1 (.expr (.lit 0))) (t := T) (H := (compE E0 DT).held) (τ := DT) rfl
    (h2 2 (by decide) (by decide)) (by simp) htk (by rw [hEx])
    (Or.inl ⟨rfl, Or.inr ⟨0, by rw [hEx]; rfl⟩⟩) rfl rfl
    ⟨LetdFn.of drop_ok (fun g hg => by rw [hEx] at hg; exact (Ty.dtor.inj hg).1.symm),
      fun y Ey g u hr hy hgy => by
        have hy0 : y = 0 := by rcases hr with hr | hr <;> cases hr <;> rfl
        subst hy0
        rw [h0] at hy; cases hy
        cases hgy
        exact ofn_enumOK⟩
    (HeldUp.refl _ _) hasg1 (hKc.endOK _) (by simp [Stmt.assigns])
  -- the arm that takes nothing: the enum stays, and its scope frees it
  let Δ2 : Ctx := A2.setE (kill .replace false 1 (sigCtx ofn)) 1 I
  have hasg2 : StmtT P (sigCtx ofn) [] (.assign 1 (.expr (.lit 0))) Δ2 :=
    StmtT.assign (Ex := R0) (E := intE) h1 (by simp) (Or.inr (Or.inr ⟨rfl, rfl⟩))
      (RhsT.expr ExprT.lit) rfl (by simp [intE, roots, Entry.vdeps, Mode.ownSlot]) (by simp [h1])
      (hS.noPin _) (DtorSafe.of_none (fun v E h => (hS v E h).2.1) _ _ _) rfl
  let Δ1 : Ctx := exitScope 2 Kc
  have hΔ1r : NoRootb Δ1 := hKc.exitScope 2
  have hΔ1d : NoDeps Δ1 := by
    intro v E h
    simp only [Δ1, exitScope] at h
    by_cases hv : v = 2
    · subst hv; simp at h
    · rw [upd_ne _ _ hv] at h; exact (hKcd.kill _ _ _) v E h
  have hw : Weaker Δ2 Δ1 := by
    refine ⟨fun v => ?_, hΔ1d.wf hΔ1r, hΔ1d.names⟩
    have e1 : Δ1 v = if v = 2 then none else if v = 1 then some I else if v = 0 then
        some { E0 with live := false, dtor := false } else none := by
      simp only [Δ1, exitScope, hKcd.kill_eq]
      by_cases hv2 : v = 2
      · subst hv2; simp
      · rw [upd_ne _ _ hv2]; simp only [hv2, ↓reduceIte, Kc, A2.setE]
        by_cases hv1 : v = 1
        · subst hv1; simp
        · rw [upd_ne _ _ hv1, hKbd.kill_eq]; simp only [hv1, ↓reduceIte, Kb, A2.setE, upd_ne _ _ hv2, Ka]
          by_cases hv0 : v = 0
          · subst hv0; simp
          · rw [upd_ne _ _ hv0, hSd.kill_eq, h2 v hv0 hv1]; simp [hv0]
    have e2 : Δ2 v = if v = 1 then some I else if v = 0 then some E0 else none := by
      simp only [Δ2, A2.setE, hSd.kill_eq]
      by_cases hv1 : v = 1
      · subst hv1; simp
      · rw [upd_ne _ _ hv1]; simp only [hv1, ↓reduceIte]
        by_cases hv0 : v = 0
        · subst hv0; simp [h0]
        · simp only [hv0, ↓reduceIte]; exact h2 v hv0 hv1
    rw [e1, e2]
    by_cases hv2 : v = 2
    · subst hv2; simp
    by_cases hv1 : v = 1
    · subst hv1; simp; exact EntryWeaker.refl _
    by_cases hv0 : v = 0
    · subst hv0
      simp only [hv2, hv1, ↓reduceIte, reduceCtorEq, false_iff, Option.some.injEq, true_and]
      intro E E' hE hE'
      subst hE; subst hE'
      exact ⟨rfl, rfl, fun hf => by simp [Entry.fixed, E0] at hf, fun hl => by simp at hl,
        fun hd => by simp [E0] at hd, rfl, fun hd => by simp at hd, fun hd => by simp [E0] at hd⟩
    · simp [hv2, hv1, hv0]
  have harm2 : StmtT P (sigCtx ofn) [] (.assign 1 (.expr (.lit 0))) Δ1 :=
    StmtT.sub (Weaker.refl (hSd.wf hS) hSd.names) hasg2 (Or.inr hw)
  refine ⟨Δ1, StmtT.ite rfl rfl (ExprT.isl h0 rfl rfl) harm1 harm2, hΔ1r, ?_⟩
  show exitScope 2 Kc 1 = some I
  simp only [exitScope]
  rw [upd_ne _ _ (by decide), hKcd.kill_eq]
  simp [Kc, A2.setE]

theorem ofn_ok : FnOK P ofn := by
  obtain ⟨Δ, hb, hfl, hr⟩ := ofn_body
  refine ⟨rfl, by decide, by decide, rfl, by simp [ofn], ?_, by simp [ofn], by simp [ofn], by simp [ofn],
    by simp [ofn], by simp [ofn], ?_, Δ, hb, fun v E h => (hfl v E h).2, ?_, ?_⟩
  · intro pt hpt; simp [ofn] at hpt; subst hpt; simp [ODT, OT, DT, T, Ty.ok, Ty.isStruct, Ty.owning, Ty.vecD]
  · refine ⟨fun i hi hs _ => ?_, fun i hi b hb _ => ?_, fun h => by simp [ofn] at h⟩
    · simp [ofn] at hi; subst hi
      exact ⟨Or.inr ⟨2, OT, rfl, Or.inl ofn_enumOK⟩, by simp [ofn, Stmt.assigns]⟩
    · simp [ofn] at hi; subst hi; simp [ofn] at hb
  · exact ⟨{ intE with mode := R0.mode }, by simpa [ofn] using hr, rfl, rfl, by simp [R0, resMode, ofn],
      by simp [intE], by simp [intE], by simp [ofn]⟩
  · intro i hi b hb; simp [ofn] at hi; subst hi; simp [ofn] at hb

/-! ### An enum's glue (Agora #632): `gfn`

`@ gfn sink self → i { ? ( isl self ) { :drop y ( takel self )  = r 0 } { = r 0 } }`:
the glue takes the enum owned and matches on its tag; the payload that
holds a destructor value moves out to a `letd`. -/

theorem gfn_not_thru : ¬ ThruFn P 3 := by
  intro h
  cases h with
  | here hf hb => simp [P] at hf; subst hf; simp [gfn, Stmt.hasThru] at hb
  | call hf hg ht => simp [P] at hf; subst hf; simp [gfn, Stmt.calls] at hg; subst hg; exact glue_not_thru ht

theorem gfn_enumOK : EnumGlueOK P 3 ST :=
  ⟨gfn, AT, .int, _, _, rfl, rfl, rfl, rfl, rfl, rfl, rfl, rfl, gfn_not_thru, rfl, rfl, rfl,
    fun _ => ⟨2, 4, _, rfl⟩, fun h => absurd h (by decide)⟩

theorem gdrop_ok : DropFnOK P 3 ST := Or.inr (Or.inr (Or.inr (Or.inl gfn_enumOK)))

theorem gfn_body : ∃ Δ, StmtT P (sigCtx gfn) [] gfn.body Δ ∧
    (∀ v E, Δ v = some E → E.mode ≠ .rootb ∧ E.dtor = false ∧ E.dbind = false) ∧
    Δ 1 = some { intE with mode := R0.mode } := by
  let E0 : Entry := ⟨SDT, .own, true, [], [], false, false⟩
  let I : Entry := { intE with mode := R0.mode }
  have h0 : sigCtx gfn 0 = some E0 := by simp [sigCtx, gfn, paramE, E0, SDT, ST, AT, GDT, GT, DT, T, Ty.hasFn]
  have h1 : sigCtx gfn 1 = some R0 := by simp [sigCtx, gfn, R0, resMode]
  have h2 : ∀ v : Nat, v ≠ 0 → v ≠ 1 → sigCtx gfn v = none := by
    intro v hv0 hv1
    have hlt : ¬ v < 1 := fun h => hv0 (Nat.lt_one_iff.mp h)
    simp [sigCtx, gfn, hlt, hv1]
  have hS : NoRootb (sigCtx gfn) := by
    intro v E h
    rcases v with _ | _ | v
    · rw [h0] at h; cases h; simp [E0]
    · rw [h1] at h; cases h; simp [R0]
    · rw [h2 _ (by simp) (by simp)] at h; cases h
  have hSd : NoDeps (sigCtx gfn) := by
    intro v E h
    rcases v with _ | _ | v
    · rw [h0] at h; cases h; rfl
    · rw [h1] at h; cases h; rfl
    · rw [h2 _ (by simp) (by simp)] at h; cases h
  -- the arm that takes the payload out
  let Ka : Ctx := A2.setE (kill .replace false 0 (sigCtx gfn)) 0 { E0 with live := false, dtor := false }
  have hKa : NoRootb Ka := (hS.kill _ _ _).setE (by simp [E0])
  have hKad : NoDeps Ka := (hSd.kill _ _ _).setE rfl
  have hEx : compE E0 AT = ⟨AT, .own, true, [], [], false, false⟩ := by
    simp [compE, E0, ownHeld, AT, GDT, GT, DT, T]
  have htk : RhsT (sigCtx gfn) [] (.takel 0) (compE E0 AT) Ka :=
    RhsT.takel (b := .int) h0 rfl rfl (Or.inr ⟨3, rfl, by decide⟩) (by simp) (hS.noPin _)
      (DtorSafe.of_none (fun v E h => (hS v E h).2.1) _ _ _)
  let ED : Entry := Entry.arm { compE E0 AT with ty := GDT, held := (compE E0 AT).held }
  have hED : ED = ⟨GDT, .own, true, [], [], false, false⟩ := by
    simp only [ED]; rw [hEx]; simp [Entry.arm, AT, GDT, GT, DT, T, Ty.dtorViews, Ty.holdsView]
  let Kb : Ctx := A2.setE Ka 2 ED
  have hKb : NoRootb Kb := hKa.setE (by rw [hED]; simp)
  have hKbd : NoDeps Kb := hKad.setE (by rw [hED]; rfl)
  have hc1 : Kb 1 = some R0 := by
    simp [Kb, Ka, A2.setE, upd, hSd.kill_eq, h1]
  let Kc : Ctx := A2.setE (kill .replace false 1 Kb) 1 I
  have hKc : NoRootb Kc := (hKb.kill _ _ _).setE (by simp [I, intE, R0])
  have hKcd : NoDeps Kc := (hKbd.kill _ _ _).setE rfl
  have hasg1 : StmtT P Kb [] (.assign 1 (.expr (.lit 0))) Kc :=
    StmtT.assign (Ex := R0) (E := intE) hc1 (by simp) (Or.inr (Or.inr ⟨rfl, rfl⟩))
      (RhsT.expr ExprT.lit) rfl (by simp [intE, roots, Entry.vdeps, Mode.ownSlot]) (by simp [hc1])
      (hKb.noPin _) (DtorSafe.of_none (fun v E h => (hKb v E h).2.1) _ _ _) rfl
  have harm1 := StmtT.letd (P := P) (Γ := sigCtx gfn) (Γ1 := Ka) (F := []) (x := 2) (f := 4) (r := .takel 0)
    (s := .assign 1 (.expr (.lit 0))) (t := GT) (H := (compE E0 AT).held) (τ := GDT) rfl
    (h2 2 (by decide) (by decide)) (by simp) htk (by rw [hEx])
    (Or.inl ⟨rfl, Or.inl (by rw [hEx]; rfl)⟩) rfl rfl
    ⟨LetdFn.of gluedrop_ok (fun g hg => by rw [hEx] at hg; exact Ty.noConfusion hg),
      fun y Ey g u hr hy hgy => by
        have hy0 : y = 0 := by rcases hr with hr | hr <;> cases hr <;> rfl
        subst hy0
        rw [h0] at hy; cases hy
        cases hgy
        exact gfn_enumOK⟩
    (HeldUp.refl _ _) hasg1 (hKc.endOK _) (by simp [Stmt.assigns])
  -- the arm that takes nothing: the enum stays, and its scope frees it
  let Δ2 : Ctx := A2.setE (kill .replace false 1 (sigCtx gfn)) 1 I
  have hasg2 : StmtT P (sigCtx gfn) [] (.assign 1 (.expr (.lit 0))) Δ2 :=
    StmtT.assign (Ex := R0) (E := intE) h1 (by simp) (Or.inr (Or.inr ⟨rfl, rfl⟩))
      (RhsT.expr ExprT.lit) rfl (by simp [intE, roots, Entry.vdeps, Mode.ownSlot]) (by simp [h1])
      (hS.noPin _) (DtorSafe.of_none (fun v E h => (hS v E h).2.1) _ _ _) rfl
  let Δ1 : Ctx := exitScope 2 Kc
  have hΔ1r : NoRootb Δ1 := hKc.exitScope 2
  have hΔ1d : NoDeps Δ1 := by
    intro v E h
    simp only [Δ1, exitScope] at h
    by_cases hv : v = 2
    · subst hv; simp at h
    · rw [upd_ne _ _ hv] at h; exact (hKcd.kill _ _ _) v E h
  have hw : Weaker Δ2 Δ1 := by
    refine ⟨fun v => ?_, hΔ1d.wf hΔ1r, hΔ1d.names⟩
    have e1 : Δ1 v = if v = 2 then none else if v = 1 then some I else if v = 0 then
        some { E0 with live := false, dtor := false } else none := by
      simp only [Δ1, exitScope, hKcd.kill_eq]
      by_cases hv2 : v = 2
      · subst hv2; simp
      · rw [upd_ne _ _ hv2]; simp only [hv2, ↓reduceIte, Kc, A2.setE]
        by_cases hv1 : v = 1
        · subst hv1; simp
        · rw [upd_ne _ _ hv1, hKbd.kill_eq]; simp only [hv1, ↓reduceIte, Kb, A2.setE, upd_ne _ _ hv2, Ka]
          by_cases hv0 : v = 0
          · subst hv0; simp
          · rw [upd_ne _ _ hv0, hSd.kill_eq, h2 v hv0 hv1]; simp [hv0]
    have e2 : Δ2 v = if v = 1 then some I else if v = 0 then some E0 else none := by
      simp only [Δ2, A2.setE, hSd.kill_eq]
      by_cases hv1 : v = 1
      · subst hv1; simp
      · rw [upd_ne _ _ hv1]; simp only [hv1, ↓reduceIte]
        by_cases hv0 : v = 0
        · subst hv0; simp [h0]
        · simp only [hv0, ↓reduceIte]; exact h2 v hv0 hv1
    rw [e1, e2]
    by_cases hv2 : v = 2
    · subst hv2; simp
    by_cases hv1 : v = 1
    · subst hv1; simp; exact EntryWeaker.refl _
    by_cases hv0 : v = 0
    · subst hv0
      simp only [hv2, hv1, ↓reduceIte, reduceCtorEq, false_iff, Option.some.injEq, true_and]
      intro E E' hE hE'
      subst hE; subst hE'
      exact ⟨rfl, rfl, fun hf => by simp [Entry.fixed, E0] at hf, fun hl => by simp at hl,
        fun hd => by simp [E0] at hd, rfl, fun hd => by simp at hd, fun hd => by simp [E0] at hd⟩
    · simp [hv2, hv1, hv0]
  have harm2 : StmtT P (sigCtx gfn) [] (.assign 1 (.expr (.lit 0))) Δ1 :=
    StmtT.sub (Weaker.refl (hSd.wf hS) hSd.names) hasg2 (Or.inr hw)
  refine ⟨Δ1, StmtT.ite rfl rfl (ExprT.isl h0 rfl rfl) harm1 harm2, hΔ1r, ?_⟩
  show exitScope 2 Kc 1 = some I
  simp only [exitScope]
  rw [upd_ne _ _ (by decide), hKcd.kill_eq]
  simp [Kc, A2.setE]

theorem gfn_ok : FnOK P gfn := by
  obtain ⟨Δ, hb, hfl, hr⟩ := gfn_body
  refine ⟨rfl, by decide, by decide, rfl, by simp [gfn], ?_, by simp [gfn], by simp [gfn], by simp [gfn],
    by simp [gfn], by simp [gfn], ?_, Δ, hb, fun v E h => (hfl v E h).2, ?_, ?_⟩
  · intro pt hpt; simp [gfn] at hpt; subst hpt; simp [SDT, ST, AT, GDT, GT, DT, T, Ty.ok, Ty.isStruct, Ty.owning, Ty.vecD]
  · refine ⟨fun i hi hs _ => ?_, fun i hi b hb _ => ?_, fun h => by simp [gfn] at h⟩
    · simp [gfn] at hi; subst hi
      exact ⟨Or.inr ⟨3, ST, rfl, Or.inl gfn_enumOK⟩, by simp [gfn, Stmt.assigns]⟩
    · simp [gfn] at hi; subst hi; simp [gfn] at hb
  · exact ⟨{ intE with mode := R0.mode }, by simpa [gfn] using hr, rfl, rfl, by simp [R0, resMode, gfn],
      by simp [intE], by simp [intE], by simp [gfn]⟩
  · intro i hi b hb; simp [gfn] at hi; subst hi; simp [gfn] at hb

/-! ### An enum with a destructor payload and a view payload (Agora #750): `ofnV`

`sum DT (slice int)`: the glue takes the enum owned and matches on its tag;
the destructor payload moves out to a `letd`, the view payload is a borrow
that ends with the glue's scope.  The glue sees its parameter as holding
nothing (`paramE`): what the view is valid through is the caller's, which
the call keeps, as for a struct's (`glueS`). -/

theorem ofnV_not_thru : ¬ ThruFn P 9 := by
  intro h
  cases h with
  | here hf hb => simp [P] at hf; subst hf; simp [ofnV, Stmt.hasThru] at hb
  | call hf hg ht => simp [P] at hf; subst hf; simp [ofnV, Stmt.calls] at hg; subst hg; exact dfn_not_thru ht

theorem ofnV_enumOK : EnumGlueOK P 9 OV :=
  ⟨ofnV, DT, .slice .int, _, _, rfl, rfl, rfl, rfl, rfl, rfl, rfl, rfl, ofnV_not_thru, rfl, rfl, rfl,
    fun _ => ⟨2, 0, _, rfl⟩, fun h => absurd h (by decide)⟩

theorem ovdrop_ok : DropFnOK P 9 OV := Or.inr (Or.inr (Or.inr (Or.inl ofnV_enumOK)))

theorem ofnV_body : ∃ Δ, StmtT P (sigCtx ofnV) [] ofnV.body Δ ∧
    (∀ v E, Δ v = some E → E.mode ≠ .rootb ∧ E.dtor = false ∧ E.dbind = false) ∧
    Δ 1 = some { intE with mode := R0.mode } := by
  let E0 : Entry := ⟨OVD, .own, true, [], [], false, false⟩
  let I : Entry := { intE with mode := R0.mode }
  have h0 : sigCtx ofnV 0 = some E0 := by simp [sigCtx, ofnV, paramE, E0, OVD, OV, DT, T, Ty.hasFn]
  have h1 : sigCtx ofnV 1 = some R0 := by simp [sigCtx, ofnV, R0, resMode]
  have h2 : ∀ v : Nat, v ≠ 0 → v ≠ 1 → sigCtx ofnV v = none := by
    intro v hv0 hv1
    have hlt : ¬ v < 1 := fun h => hv0 (Nat.lt_one_iff.mp h)
    simp [sigCtx, ofnV, hlt, hv1]
  have hS : NoRootb (sigCtx ofnV) := by
    intro v E h
    rcases v with _ | _ | v
    · rw [h0] at h; cases h; simp [E0]
    · rw [h1] at h; cases h; simp [R0]
    · rw [h2 _ (by simp) (by simp)] at h; cases h
  have hSd : NoDeps (sigCtx ofnV) := by
    intro v E h
    rcases v with _ | _ | v
    · rw [h0] at h; cases h; rfl
    · rw [h1] at h; cases h; rfl
    · rw [h2 _ (by simp) (by simp)] at h; cases h
  -- the arm that takes the destructor payload out
  let Ka : Ctx := A2.setE (kill .replace false 0 (sigCtx ofnV)) 0 { E0 with live := false, dtor := false }
  have hKa : NoRootb Ka := (hS.kill _ _ _).setE (by simp [E0])
  have hKad : NoDeps Ka := (hSd.kill _ _ _).setE rfl
  have hEx : compE E0 DT = ⟨DT, .own, true, [], [], false, false⟩ := by
    simp [compE, E0, ownHeld, DT, T]
  have htk : RhsT (sigCtx ofnV) [] (.takel 0) (compE E0 DT) Ka :=
    RhsT.takel (b := .slice .int) h0 rfl rfl (Or.inr ⟨9, rfl, by decide⟩) (by simp) (hS.noPin _)
      (DtorSafe.of_none (fun v E h => (hS v E h).2.1) _ _ _)
  let ED : Entry := Entry.arm { compE E0 DT with ty := DT, held := (compE E0 DT).held }
  have hED : ED = ⟨DT, .own, true, [], [], false, false⟩ := by
    simp only [ED]; rw [hEx]; simp [Entry.arm, DT, T, Ty.dtorViews, Ty.holdsView]
  let Kb : Ctx := A2.setE Ka 2 ED
  have hKb : NoRootb Kb := hKa.setE (by rw [hED]; simp)
  have hKbd : NoDeps Kb := hKad.setE (by rw [hED]; rfl)
  have hc1 : Kb 1 = some R0 := by
    simp [Kb, Ka, A2.setE, upd, hSd.kill_eq, h1]
  let Kc : Ctx := A2.setE (kill .replace false 1 Kb) 1 I
  have hKc : NoRootb Kc := (hKb.kill _ _ _).setE (by simp [I, intE, R0])
  have hKcd : NoDeps Kc := (hKbd.kill _ _ _).setE rfl
  have hasg1 : StmtT P Kb [] (.assign 1 (.expr (.lit 0))) Kc :=
    StmtT.assign (Ex := R0) (E := intE) hc1 (by simp) (Or.inr (Or.inr ⟨rfl, rfl⟩))
      (RhsT.expr ExprT.lit) rfl (by simp [intE, roots, Entry.vdeps, Mode.ownSlot]) (by simp [hc1])
      (hKb.noPin _) (DtorSafe.of_none (fun v E h => (hKb v E h).2.1) _ _ _) rfl
  have harm1 := StmtT.letd (P := P) (Γ := sigCtx ofnV) (Γ1 := Ka) (F := []) (x := 2) (f := 0) (r := .takel 0)
    (s := .assign 1 (.expr (.lit 0))) (t := T) (H := (compE E0 DT).held) (τ := DT) rfl
    (h2 2 (by decide) (by decide)) (by simp) htk (by rw [hEx])
    (Or.inl ⟨rfl, Or.inr ⟨0, by rw [hEx]; rfl⟩⟩) rfl rfl
    ⟨LetdFn.of drop_ok (fun g hg => by rw [hEx] at hg; exact (Ty.dtor.inj hg).1.symm),
      fun y Ey g u hr hy hgy => by
        have hy0 : y = 0 := by rcases hr with hr | hr <;> cases hr <;> rfl
        subst hy0
        rw [h0] at hy; cases hy
        cases hgy
        exact ofnV_enumOK⟩
    (HeldUp.refl _ _) hasg1 (hKc.endOK _) (by simp [Stmt.assigns])
  -- the view arm takes nothing: the enum stays, and its scope frees it
  let Δ2 : Ctx := A2.setE (kill .replace false 1 (sigCtx ofnV)) 1 I
  have hasg2 : StmtT P (sigCtx ofnV) [] (.assign 1 (.expr (.lit 0))) Δ2 :=
    StmtT.assign (Ex := R0) (E := intE) h1 (by simp) (Or.inr (Or.inr ⟨rfl, rfl⟩))
      (RhsT.expr ExprT.lit) rfl (by simp [intE, roots, Entry.vdeps, Mode.ownSlot]) (by simp [h1])
      (hS.noPin _) (DtorSafe.of_none (fun v E h => (hS v E h).2.1) _ _ _) rfl
  let Δ1 : Ctx := exitScope 2 Kc
  have hΔ1r : NoRootb Δ1 := hKc.exitScope 2
  have hΔ1d : NoDeps Δ1 := by
    intro v E h
    simp only [Δ1, exitScope] at h
    by_cases hv : v = 2
    · subst hv; simp at h
    · rw [upd_ne _ _ hv] at h; exact (hKcd.kill _ _ _) v E h
  have hw : Weaker Δ2 Δ1 := by
    refine ⟨fun v => ?_, hΔ1d.wf hΔ1r, hΔ1d.names⟩
    have e1 : Δ1 v = if v = 2 then none else if v = 1 then some I else if v = 0 then
        some { E0 with live := false, dtor := false } else none := by
      simp only [Δ1, exitScope, hKcd.kill_eq]
      by_cases hv2 : v = 2
      · subst hv2; simp
      · rw [upd_ne _ _ hv2]; simp only [hv2, ↓reduceIte, Kc, A2.setE]
        by_cases hv1 : v = 1
        · subst hv1; simp
        · rw [upd_ne _ _ hv1, hKbd.kill_eq]; simp only [hv1, ↓reduceIte, Kb, A2.setE, upd_ne _ _ hv2, Ka]
          by_cases hv0 : v = 0
          · subst hv0; simp
          · rw [upd_ne _ _ hv0, hSd.kill_eq, h2 v hv0 hv1]; simp [hv0]
    have e2 : Δ2 v = if v = 1 then some I else if v = 0 then some E0 else none := by
      simp only [Δ2, A2.setE, hSd.kill_eq]
      by_cases hv1 : v = 1
      · subst hv1; simp
      · rw [upd_ne _ _ hv1]; simp only [hv1, ↓reduceIte]
        by_cases hv0 : v = 0
        · subst hv0; simp [h0]
        · simp only [hv0, ↓reduceIte]; exact h2 v hv0 hv1
    rw [e1, e2]
    by_cases hv2 : v = 2
    · subst hv2; simp
    by_cases hv1 : v = 1
    · subst hv1; simp; exact EntryWeaker.refl _
    by_cases hv0 : v = 0
    · subst hv0
      simp only [hv2, hv1, ↓reduceIte, reduceCtorEq, false_iff, Option.some.injEq, true_and]
      intro E E' hE hE'
      subst hE; subst hE'
      exact ⟨rfl, rfl, fun hf => by simp [Entry.fixed, E0] at hf, fun hl => by simp at hl,
        fun hd => by simp [E0] at hd, rfl, fun hd => by simp at hd, fun hd => by simp [E0] at hd⟩
    · simp [hv2, hv1, hv0]
  have harm2 : StmtT P (sigCtx ofnV) [] (.assign 1 (.expr (.lit 0))) Δ1 :=
    StmtT.sub (Weaker.refl (hSd.wf hS) hSd.names) hasg2 (Or.inr hw)
  refine ⟨Δ1, StmtT.ite rfl rfl (ExprT.isl h0 rfl rfl) harm1 harm2, hΔ1r, ?_⟩
  show exitScope 2 Kc 1 = some I
  simp only [exitScope]
  rw [upd_ne _ _ (by decide), hKcd.kill_eq]
  simp [Kc, A2.setE]

theorem ofnV_ok : FnOK P ofnV := by
  obtain ⟨Δ, hb, hfl, hr⟩ := ofnV_body
  refine ⟨rfl, by decide, by decide, rfl, by simp [ofnV], ?_, by simp [ofnV], by simp [ofnV], by simp [ofnV],
    by simp [ofnV], by simp [ofnV], ?_, Δ, hb, fun v E h => (hfl v E h).2, ?_, ?_⟩
  · intro pt hpt; simp [ofnV] at hpt; subst hpt
    simp [OVD, OV, DT, T, Ty.ok, Ty.isStruct, Ty.owning, Ty.vecD, Ty.holdsView]
  · refine ⟨fun i hi hs _ => ?_, fun i hi b hb _ => ?_, fun h => by simp [ofnV] at h⟩
    · simp [ofnV] at hi; subst hi
      exact ⟨Or.inr ⟨9, OV, rfl, Or.inl ofnV_enumOK⟩, by simp [ofnV, Stmt.assigns]⟩
    · simp [ofnV] at hi; subst hi; simp [ofnV] at hb
  · exact ⟨{ intE with mode := R0.mode }, by simpa [ofnV] using hr, rfl, rfl, by simp [R0, resMode, ofnV],
      by simp [intE], by simp [intE], by simp [ofnV]⟩
  · intro i hi b hb; simp [ofnV] at hi; subst hi; simp [ofnV] at hb

/-! ### A view-holding struct with its own `% Drop` (Agora #750): `implS`, `glueS2`

`GS = prod DT (slice int)` again, its glue `glueS2` rebinding it under the
fields' glue `glueS` and running the impl `implS` on it lent (Agora #616's
shape).  In the glue the rebound binding is armed (its type holds a view),
but it views nothing the glue can see: the glue's parameter holds nothing
(`paramE`). -/

/-- A context with no borrowed parameter and no entry that views anything:
    an armed binding in it reads no view a scope's end could end. -/
def NoRootbD (Γ : Ctx) : Prop := ∀ v E, Γ v = some E → E.mode ≠ .rootb ∧ E.vdeps = []

theorem NoRootbD.setE {Γ : Ctx} (h : NoRootbD Γ) {x : Var} {E : Entry} (hm : E.mode ≠ .rootb)
    (hE : E.vdeps = []) : NoRootbD (A2.setE Γ x E) := fun v E' hv => by
  by_cases hvx : v = x
  · subst hvx; simp [A2.setE] at hv; subst hv; exact ⟨hm, hE⟩
  · rw [A2.setE, upd_ne _ _ hvx] at hv; exact h v E' hv

theorem NoRootbD.kill {Γ : Ctx} (h : NoRootbD Γ) (e : Eff) (hv : Bool) (x : Var) :
    NoRootbD (A2.kill e hv x Γ) := fun v E' hv' => by
  simp only [A2.kill] at hv'
  cases h0 : Γ v with
  | none => rw [h0] at hv'; cases hv'
  | some E0 =>
    rw [h0] at hv'; simp only [Option.map_some, Option.some.injEq] at hv'; subst hv'
    have := h v E0 h0
    unfold killE; split
    · simpa [Entry.vdeps] using this
    · exact this

theorem NoRootbD.exitScope {Γ : Ctx} (h : NoRootbD Γ) (x : Var) : NoRootbD (A2.exitScope x Γ) := by
  intro v E' h'
  simp only [A2.exitScope, upd] at h'
  split at h'
  · cases h'
  · exact h.kill .replace false x v E' h'

theorem NoRootbD.noPin {Γ : Ctx} (h : NoRootbD Γ) (x : Var) : NoPin Γ x :=
  fun p E hp hm => absurd hm (h p E hp).1

theorem NoRootbD.dtorSafe {Γ : Ctx} (h : NoRootbD Γ) (e : Eff) (hv : Bool) (x : Var) : DtorSafe Γ e hv x :=
  fun v E hE _ _ => by simp [hitsMem, (h v E hE).2]

theorem NoRootbD.endOK {Γ : Ctx} (h : NoRootbD Γ) (x : Var) : EndOK Γ x :=
  ⟨h.noPin x, h.dtorSafe _ _ _, fun v E hE _ _ _ d hd => by rw [(h v E hE).2] at hd; cases hd⟩

theorem implS_not_thru : ¬ ThruFn P 10 := by
  intro h
  cases h with
  | here hf hb => simp [P] at hf; subst hf; simp [implS, Stmt.hasThru] at hb
  | call hf hg _ => simp [P] at hf; subst hf; simp [implS, Stmt.calls] at hg

theorem implS_dtorOK : DtorOK P 10 GSD :=
  ⟨implS, rfl, rfl, rfl, rfl, rfl, rfl, rfl, implS_not_thru⟩

theorem implS_body : StmtT P (sigCtx implS) [] implS.body
    (setE (kill .replace false 1 (sigCtx implS)) 1 { intE with mode := R0.mode }) := by
  have hc : sigCtx implS 1 = some R0 := by simp [sigCtx, implS, R0, resMode]
  have hflags : ∀ v E, sigCtx implS v = some E → E.dtor = false ∧ E.dbind = false := by
    intro v E h
    rcases v with _ | _ | v <;> simp [sigCtx, implS, paramE, resMode] at h <;> subst h <;> exact ⟨rfl, rfl⟩
  exact StmtT.assign (Ex := R0) (E := intE) hc (by simp) (Or.inr (Or.inr ⟨rfl, rfl⟩))
    (RhsT.expr ExprT.lit) rfl (by simp [intE, roots, Entry.vdeps, Mode.ownSlot]) (by simp [hc])
    (by
      intro p E hp hm d hd _
      rcases p with _ | _ | p <;> simp [sigCtx, implS, paramE, resMode, GSD, GS, DT, T, Ty.hasFn] at hp <;>
        subst hp <;> simp [Entry.vdeps, Mode.ownSlot] at hd <;> simp at hm)
    (DtorSafe.of_none (fun v E h => (hflags v E h).1) _ _ _) rfl

theorem implS_ok : FnOK P implS := by
  refine ⟨rfl, by decide, by decide, rfl, by simp [implS], ?_, by simp [implS], by simp [implS], by simp [implS],
    by simp [implS], by simp [implS], ?_, _, implS_body, ?_, ?_, ?_⟩
  · intro pt hpt; simp [implS] at hpt; subst hpt
    simp [GSD, GS, DT, T, Ty.ok, Ty.isStruct, Ty.vecD, Ty.holdsView]
  · refine ⟨fun i hi hs _ => ?_, fun i hi b hb _ => ?_, fun h => by simp [implS] at h⟩
    · simp [implS] at hi; subst hi; simp [implS] at hs
    · simp [implS] at hi; subst hi; simp [implS] at hb
  · intro v E h
    rcases v with _ | _ | v <;> simp [setE, upd, kill, killE, sigCtx, implS, paramE, resMode, intE] at h <;>
      subst h <;> exact ⟨rfl, rfl⟩
  · exact ⟨{ intE with mode := R0.mode }, by simp [setE, upd, implS], rfl, rfl, by simp [R0, resMode, implS],
      by simp [intE], by simp [intE], by simp [implS]⟩
  · intro i hi b hb; simp [implS] at hi; subst hi; simp [implS] at hb

theorem glueS2_not_thru : ¬ ThruFn P 11 := by
  intro h
  cases h with
  | here hf hb => simp [P] at hf; subst hf; simp [glueS2, Stmt.hasThru] at hb
  | call hf hg ht =>
    simp [P] at hf; subst hf; simp [glueS2, Stmt.calls] at hg
    rcases hg with rfl | rfl
    · exact glueS_not_thru ht
    · exact implS_not_thru ht

theorem glueS2_implOK : ImplGlueOK P 11 GS 8 10 :=
  ⟨glueS2, 2, 3, .lit 0, rfl, rfl, rfl, rfl, rfl, rfl, rfl, rfl, glueS2_not_thru,
    Or.inl glueS_glueOK, implS_dtorOK, rfl⟩

theorem gs2drop_ok : DropFnOK P 11 GS := Or.inr (Or.inr (Or.inl ⟨8, 10, glueS2_implOK⟩))

def ES3 : Entry := ⟨GSD2, .own, true, [], [], false, false⟩

theorem glueS2_body : ∃ Δ, StmtT P (sigCtx glueS2) [] glueS2.body Δ ∧
    (∀ v E, Δ v = some E → E.dtor = false ∧ E.dbind = false) ∧
    Δ 1 = some { intE with mode := R0.mode } := by
  have h0 : sigCtx glueS2 0 = some ES3 := by simp [sigCtx, glueS2, paramE, ES3, GSD2, GS, DT, T, Ty.hasFn]
  have h1 : sigCtx glueS2 1 = some R0 := by simp [sigCtx, glueS2, R0, resMode]
  have hS : NoRootb (sigCtx glueS2) := by
    intro v E h
    rcases v with _ | _ | v
    · rw [h0] at h; cases h; simp [ES3]
    · rw [h1] at h; cases h; simp [R0]
    · simp [sigCtx, glueS2] at h
  have hSD : NoRootbD (sigCtx glueS2) := by
    intro v E h
    rcases v with _ | _ | v
    · rw [h0] at h; cases h; exact ⟨by simp [ES3], rfl⟩
    · rw [h1] at h; cases h; exact ⟨by simp [R0], rfl⟩
    · simp [sigCtx, glueS2] at h
  let Ka : Ctx := A2.setE (kill .replace false 0 (sigCtx glueS2)) 0 { ES3 with live := false, dtor := false }
  have hKa : NoRootb Ka := (hS.kill _ _ _).setE (by simp [ES3])
  have hKaD : NoRootbD Ka := (hSD.kill _ _ _).setE (by simp [ES3]) rfl
  have hmv : RhsT (sigCtx glueS2) [] (.var 0) ⟨ES3.ty, .own, true, [], ES3.held, false, false⟩ Ka :=
    RhsT.moveOwn h0 rfl rfl (by simp) (hS.noPin _) (DtorSafe.of_none (fun v E h => (hS v E h).2.1) _ _ _)
  let EW : Entry := Entry.arm { (⟨ES3.ty, .own, true, [], ES3.held, false, false⟩ : Entry) with ty := GSD, held := ES3.held }
  -- armed: its type holds a view; but it views nothing the glue can see
  have hEW : EW = ⟨GSD, .own, true, [], [], true, true⟩ := by
    simp [EW, ES3, Entry.arm, GSD, GS, DT, T, Ty.dtorViews, Ty.holdsView]
  let Kb : Ctx := A2.setE Ka 2 EW
  have hKbD : NoRootbD Kb := hKaD.setE (by rw [hEW]; simp) (by rw [hEW]; rfl)
  have hb2 : Kb 2 = some EW := by simp [Kb, A2.setE]
  have hnm : mutNames Kb [2] = [] := by
    simp [mutNames, argNames, argE, hb2, hEW, Entry.vdeps, nameDeps, Mode.ownSlot]
  have hcall : CallT P Kb [] 10 [2] (callRes Kb implS [2]) Kb := by
    refine ⟨implS, rfl, by simp [implS], fun i hi => ?_, fun d hd => ?_,
      CallDtorSafe.of_inp (by simp [implS]) hnm, rfl, (callPost_dtor (t := GSD) rfl hnm).symm,
      fun h => absurd h implS_not_thru⟩
    · have hi0 : i = 0 := by simp [implS] at hi; omega
      subst hi0
      refine ⟨EW, by simp [hb2], by rw [hEW], ?_, fun h => ?_, fun h => ?_⟩
      · simp [implS, paramOK, hEW]
      · simp [implS, PMode.moves] at h
      · simp [implS] at h
    · rw [hnm] at hd; cases hd
  have hER : (callRes Kb implS [2]).mode ≠ .rootb ∧ (callRes Kb implS [2]).vdeps = [] := by
    simp [callRes, resMode, implS, heldOfArgs, argNames, argE, hb2, hEW, Entry.vdeps, ownHeld, Mode.ownSlot,
      memDeps, nameDeps, roots, allKinds]
  let Kc : Ctx := A2.setE Kb 3 (callRes Kb implS [2])
  have hKcD : NoRootbD Kc := hKbD.setE hER.1 hER.2
  have hc1 : Kc 1 = some R0 := by
    simp [Kc, Kb, Ka, A2.setE, upd, A2.kill, h1, killE, hits, R0, Entry.vdeps]
  let Kd : Ctx := A2.setE (kill .replace false 1 Kc) 1 { intE with mode := R0.mode }
  have hKdD : NoRootbD Kd := (hKcD.kill _ _ _).setE (by simp [intE, R0]) rfl
  have hasg : StmtT P Kc [] (.assign 1 (.expr (.lit 0))) Kd :=
    StmtT.assign (Ex := R0) (E := intE) hc1 (by simp) (Or.inr (Or.inr ⟨rfl, rfl⟩))
      (RhsT.expr ExprT.lit) rfl (by simp [intE, roots, Entry.vdeps, Mode.ownSlot]) (by simp [hc1])
      (hKcD.noPin _) (hKcD.dtorSafe _ _ _) rfl
  have hlc := StmtT.letcall (P := P) (Γ := Kb) (F := []) (x := 3) (f := 10) (args := [2])
    (s := .assign 1 (.expr (.lit 0))) rfl (by simp [Kb, Ka, A2.setE, upd, A2.kill, sigCtx, glueS2]) (by simp)
    hcall hasg (hKdD.endOK _)
    (fun fn' hf' ho _ => by simp [P] at hf'; subst hf'; simp [implS] at ho)
  have hlet := StmtT.letd (P := P) (Γ := sigCtx glueS2) (Γ1 := Ka) (F := []) (x := 2) (f := 8) (r := .var 0)
    (s := .letcall 3 10 [2] (.assign 1 (.expr (.lit 0)))) (t := GS) (H := ES3.held) (τ := GSD) rfl
    (by simp [sigCtx, glueS2]) (by simp) hmv rfl
    (Or.inl ⟨rfl, Or.inr ⟨11, rfl⟩⟩) rfl rfl
    ⟨⟨gsdrop_ok, fun g hg _ => by
      have hg11 : g = 11 := (Ty.dtor.inj hg).1.symm
      subst hg11
      exact ⟨10, 3, _, glueS2_implOK, rfl⟩⟩,
      TakeOK.triv (fun y => ⟨(by intro h; cases h), (by intro h; cases h)⟩)⟩
    (HeldUp.refl _ _) hlc ((hKdD.exitScope 3).endOK _) (by simp [Stmt.assigns])
  -- what is left: the moved parameter and the result; the armed binding has ended
  have hex : ∀ (Γ : Ctx) (x : Var), NoRootbD Γ → exitScope x Γ = upd Γ x none := fun Γ x h => by
    simp only [exitScope, NoDeps.kill_eq (fun v E hE => (h v E hE).2)]
  have hKcd : NoRootbD (kill .replace false 1 Kc) := hKcD.kill _ _ _
  rw [hex _ _ ((hKdD.exitScope 3)), hex _ _ hKdD] at hlet
  refine ⟨_, hlet, ?_, ?_⟩
  · intro v E h
    by_cases hv2 : v = 2
    · subst hv2; simp [upd] at h
    rw [upd_ne _ _ hv2] at h
    by_cases hv3 : v = 3
    · subst hv3; simp [upd] at h
    rw [upd_ne _ _ hv3] at h
    by_cases hv1 : v = 1
    · subst hv1; simp [Kd, A2.setE] at h; subst h; exact ⟨rfl, rfl⟩
    have e1 : Kd v = Kc v := by
      show A2.setE (kill .replace false 1 Kc) 1 _ v = Kc v
      rw [A2.setE, upd_ne _ _ hv1, NoDeps.kill_eq (fun v E hE => (hKcD v E hE).2)]
    have e2 : Kc v = Ka v := by
      show upd (upd Ka 2 (some EW)) 3 _ v = Ka v
      rw [upd_ne _ _ hv3, upd_ne _ _ hv2]
    rw [e1, e2] at h
    exact ⟨(hKa v E h).2.1, (hKa v E h).2.2⟩
  · simp [upd, Kd, A2.setE]

theorem glueS2_ok : FnOK P glueS2 := by
  obtain ⟨Δ, hb, hfl, hr⟩ := glueS2_body
  refine ⟨rfl, by decide, by decide, rfl, by simp [glueS2], ?_, by simp [glueS2], by simp [glueS2],
    by simp [glueS2], by simp [glueS2], by simp [glueS2], ?_, Δ, hb, hfl, ?_, ?_⟩
  · intro pt hpt; simp [glueS2] at hpt; subst hpt
    simp [GSD2, GS, DT, T, Ty.ok, Ty.isStruct, Ty.owning, Ty.vecD, Ty.holdsView]
  · refine ⟨fun i hi hs _ => ?_, fun i hi b hb _ => ?_, fun h => by simp [glueS2] at h⟩
    · simp [glueS2] at hi; subst hi; simp [glueS2, Stmt.movedFirst, Stmt.assigns]
    · simp [glueS2] at hi; subst hi; simp [glueS2] at hb
  · exact ⟨{ intE with mode := R0.mode }, by simpa [glueS2] using hr, rfl, rfl, by simp [R0, resMode, glueS2],
      by simp [intE], by simp [intE], by simp [glueS2]⟩
  · intro i hi b hb; simp [glueS2] at hi; subst hi; simp [glueS2] at hb

/-! ### Agora #805: the receive's option glue `ofnR` (`sum int DT`) -/

theorem ofnR_not_thru : ¬ ThruFn P 12 := by
  intro h
  cases h with
  | here hf hb => simp [P] at hf; subst hf; simp [ofnR, Stmt.hasThru] at hb
  | call hf hg ht => simp [P] at hf; subst hf; simp [ofnR, Stmt.calls] at hg; subst hg; exact dfn_not_thru ht

theorem ofnR_enumOK : EnumGlueOK P 12 RT :=
  ⟨ofnR, .int, DT, _, _, rfl, rfl, rfl, rfl, rfl, rfl, rfl, rfl, ofnR_not_thru, rfl, rfl, rfl,
    fun h => absurd h (by decide), fun _ => ⟨2, 0, _, rfl⟩⟩

theorem rdrop_ok : DropFnOK P 12 RT := Or.inr (Or.inr (Or.inr (Or.inl ofnR_enumOK)))

theorem ofnR_body : ∃ Δ, StmtT P (sigCtx ofnR) [] ofnR.body Δ ∧
    (∀ v E, Δ v = some E → E.mode ≠ .rootb ∧ E.dtor = false ∧ E.dbind = false) ∧
    Δ 1 = some { intE with mode := R0.mode } := by
  let E0 : Entry := ⟨RDT, .own, true, [], [], false, false⟩
  let I : Entry := { intE with mode := R0.mode }
  have h0 : sigCtx ofnR 0 = some E0 := by simp [sigCtx, ofnR, paramE, E0, RDT, RT, DT, T, Ty.hasFn]
  have h1 : sigCtx ofnR 1 = some R0 := by simp [sigCtx, ofnR, R0, resMode]
  have h2 : ∀ v : Nat, v ≠ 0 → v ≠ 1 → sigCtx ofnR v = none := by
    intro v hv0 hv1
    have hlt : ¬ v < 1 := fun h => hv0 (Nat.lt_one_iff.mp h)
    simp [sigCtx, ofnR, hlt, hv1]
  have hS : NoRootb (sigCtx ofnR) := by
    intro v E h
    rcases v with _ | _ | v
    · rw [h0] at h; cases h; simp [E0]
    · rw [h1] at h; cases h; simp [R0]
    · rw [h2 _ (by simp) (by simp)] at h; cases h
  have hSd : NoDeps (sigCtx ofnR) := by
    intro v E h
    rcases v with _ | _ | v
    · rw [h0] at h; cases h; rfl
    · rw [h1] at h; cases h; rfl
    · rw [h2 _ (by simp) (by simp)] at h; cases h
  -- the arm that takes the payload out
  let Ka : Ctx := A2.setE (kill .replace false 0 (sigCtx ofnR)) 0 { E0 with live := false, dtor := false }
  have hKa : NoRootb Ka := (hS.kill _ _ _).setE (by simp [E0])
  have hKad : NoDeps Ka := (hSd.kill _ _ _).setE rfl
  have hEx : compE E0 DT = ⟨DT, .own, true, [], [], false, false⟩ := by
    simp [compE, E0, ownHeld, DT, T]
  have htk : RhsT (sigCtx ofnR) [] (.taker 0) (compE E0 DT) Ka :=
    RhsT.taker (a := .int) h0 rfl rfl (Or.inr ⟨12, rfl, by decide⟩) (by simp) (hS.noPin _)
      (DtorSafe.of_none (fun v E h => (hS v E h).2.1) _ _ _)
  let ED : Entry := Entry.arm { compE E0 DT with ty := DT, held := (compE E0 DT).held }
  have hED : ED = ⟨DT, .own, true, [], [], false, false⟩ := by
    simp only [ED]; rw [hEx]; simp [Entry.arm, DT, T, Ty.dtorViews, Ty.holdsView]
  let Kb : Ctx := A2.setE Ka 2 ED
  have hKb : NoRootb Kb := hKa.setE (by rw [hED]; simp)
  have hKbd : NoDeps Kb := hKad.setE (by rw [hED]; rfl)
  have hc1 : Kb 1 = some R0 := by
    simp [Kb, Ka, A2.setE, upd, hSd.kill_eq, h1]
  let Kc : Ctx := A2.setE (kill .replace false 1 Kb) 1 I
  have hKc : NoRootb Kc := (hKb.kill _ _ _).setE (by simp [I, intE, R0])
  have hKcd : NoDeps Kc := (hKbd.kill _ _ _).setE rfl
  have hasg1 : StmtT P Kb [] (.assign 1 (.expr (.lit 0))) Kc :=
    StmtT.assign (Ex := R0) (E := intE) hc1 (by simp) (Or.inr (Or.inr ⟨rfl, rfl⟩))
      (RhsT.expr ExprT.lit) rfl (by simp [intE, roots, Entry.vdeps, Mode.ownSlot]) (by simp [hc1])
      (hKb.noPin _) (DtorSafe.of_none (fun v E h => (hKb v E h).2.1) _ _ _) rfl
  have harm1 := StmtT.letd (P := P) (Γ := sigCtx ofnR) (Γ1 := Ka) (F := []) (x := 2) (f := 0) (r := .taker 0)
    (s := .assign 1 (.expr (.lit 0))) (t := T) (H := (compE E0 DT).held) (τ := DT) rfl
    (h2 2 (by decide) (by decide)) (by simp) htk (by rw [hEx])
    (Or.inl ⟨rfl, Or.inr ⟨0, by rw [hEx]; rfl⟩⟩) rfl rfl
    ⟨LetdFn.of drop_ok (fun g hg => by rw [hEx] at hg; exact (Ty.dtor.inj hg).1.symm),
      fun y Ey g u hr hy hgy => by
        have hy0 : y = 0 := by rcases hr with hr | hr <;> cases hr <;> rfl
        subst hy0
        rw [h0] at hy; cases hy
        cases hgy
        exact ofnR_enumOK⟩
    (HeldUp.refl _ _) hasg1 (hKc.endOK _) (by simp [Stmt.assigns])
  -- the arm that takes nothing: the enum stays, and its scope frees it
  let Δ2 : Ctx := A2.setE (kill .replace false 1 (sigCtx ofnR)) 1 I
  have hasg2 : StmtT P (sigCtx ofnR) [] (.assign 1 (.expr (.lit 0))) Δ2 :=
    StmtT.assign (Ex := R0) (E := intE) h1 (by simp) (Or.inr (Or.inr ⟨rfl, rfl⟩))
      (RhsT.expr ExprT.lit) rfl (by simp [intE, roots, Entry.vdeps, Mode.ownSlot]) (by simp [h1])
      (hS.noPin _) (DtorSafe.of_none (fun v E h => (hS v E h).2.1) _ _ _) rfl
  let Δ1 : Ctx := exitScope 2 Kc
  have hΔ1r : NoRootb Δ1 := hKc.exitScope 2
  have hΔ1d : NoDeps Δ1 := by
    intro v E h
    simp only [Δ1, exitScope] at h
    by_cases hv : v = 2
    · subst hv; simp at h
    · rw [upd_ne _ _ hv] at h; exact (hKcd.kill _ _ _) v E h
  have hw : Weaker Δ2 Δ1 := by
    refine ⟨fun v => ?_, hΔ1d.wf hΔ1r, hΔ1d.names⟩
    have e1 : Δ1 v = if v = 2 then none else if v = 1 then some I else if v = 0 then
        some { E0 with live := false, dtor := false } else none := by
      simp only [Δ1, exitScope, hKcd.kill_eq]
      by_cases hv2 : v = 2
      · subst hv2; simp
      · rw [upd_ne _ _ hv2]; simp only [hv2, ↓reduceIte, Kc, A2.setE]
        by_cases hv1 : v = 1
        · subst hv1; simp
        · rw [upd_ne _ _ hv1, hKbd.kill_eq]; simp only [hv1, ↓reduceIte, Kb, A2.setE, upd_ne _ _ hv2, Ka]
          by_cases hv0 : v = 0
          · subst hv0; simp
          · rw [upd_ne _ _ hv0, hSd.kill_eq, h2 v hv0 hv1]; simp [hv0]
    have e2 : Δ2 v = if v = 1 then some I else if v = 0 then some E0 else none := by
      simp only [Δ2, A2.setE, hSd.kill_eq]
      by_cases hv1 : v = 1
      · subst hv1; simp
      · rw [upd_ne _ _ hv1]; simp only [hv1, ↓reduceIte]
        by_cases hv0 : v = 0
        · subst hv0; simp [h0]
        · simp only [hv0, ↓reduceIte]; exact h2 v hv0 hv1
    rw [e1, e2]
    by_cases hv2 : v = 2
    · subst hv2; simp
    by_cases hv1 : v = 1
    · subst hv1; simp; exact EntryWeaker.refl _
    by_cases hv0 : v = 0
    · subst hv0
      simp only [hv2, hv1, ↓reduceIte, reduceCtorEq, false_iff, Option.some.injEq, true_and]
      intro E E' hE hE'
      subst hE; subst hE'
      exact ⟨rfl, rfl, fun hf => by simp [Entry.fixed, E0] at hf, fun hl => by simp at hl,
        fun hd => by simp [E0] at hd, rfl, fun hd => by simp at hd, fun hd => by simp [E0] at hd⟩
    · simp [hv2, hv1, hv0]
  have harm2 : StmtT P (sigCtx ofnR) [] (.assign 1 (.expr (.lit 0))) Δ1 :=
    StmtT.sub (Weaker.refl (hSd.wf hS) hSd.names) hasg2 (Or.inr hw)
  refine ⟨Δ1, StmtT.ite rfl rfl (ExprT.isl h0 rfl rfl) harm2 harm1, hΔ1r, ?_⟩
  show exitScope 2 Kc 1 = some I
  simp only [exitScope]
  rw [upd_ne _ _ (by decide), hKcd.kill_eq]
  simp [Kc, A2.setE]

theorem ofnR_ok : FnOK P ofnR := by
  obtain ⟨Δ, hb, hfl, hr⟩ := ofnR_body
  refine ⟨rfl, by decide, by decide, rfl, by simp [ofnR], ?_, by simp [ofnR], by simp [ofnR], by simp [ofnR],
    by simp [ofnR], by simp [ofnR], ?_, Δ, hb, fun v E h => (hfl v E h).2, ?_, ?_⟩
  · intro pt hpt; simp [ofnR] at hpt; subst hpt; simp [RDT, RT, DT, T, Ty.ok, Ty.isStruct, Ty.owning, Ty.vecD]
  · refine ⟨fun i hi hs _ => ?_, fun i hi b hb _ => ?_, fun h => by simp [ofnR] at h⟩
    · simp [ofnR] at hi; subst hi
      exact ⟨Or.inr ⟨12, RT, rfl, Or.inl ofnR_enumOK⟩, by simp [ofnR, Stmt.assigns]⟩
    · simp [ofnR] at hi; subst hi; simp [ofnR] at hb
  · exact ⟨{ intE with mode := R0.mode }, by simpa [ofnR] using hr, rfl, rfl, by simp [R0, resMode, ofnR],
      by simp [intE], by simp [intE], by simp [ofnR]⟩
  · intro i hi b hb; simp [ofnR] at hi; subst hi; simp [ofnR] at hb

theorem prog_ok : ProgOK P := by
  intro fn hfn
  simp only [P, List.mem_cons, List.mem_nil_iff, or_false] at hfn
  rcases hfn with rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl
  · exact dfn_ok
  · exact mk_ok
  · exact ofn_ok
  · exact gfn_ok
  · exact glue_ok
  · exact impl_ok
  · exact glue2_ok
  · exact glueV_ok
  · exact glueS_ok
  · exact ofnV_ok
  · exact implS_ok
  · exact glueS2_ok
  · exact ofnR_ok

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
    simp [ED2, Ecr, Entry.arm, DT, T, Ty.dtorViews, Ty.holdsView]
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
  rcases hfn with rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl <;>
    simp [dfn, mk, ofn, gfn, glue, impl, glue2, glueV, glueS, ofnV, implS, glueS2, ofnR, Stmt.codesOK,
      Rhs.codeOK]

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
    simp [ED, EP, Entry.arm, DT, T, Ty.dtorViews, Ty.holdsView]
  let K3 : Ctx := A2.setE K2 2 ED
  have hK3 : NoRootb K3 := hK2.setE (by rw [hEDe]; simp)
  have hpair : RhsT K2 [] (.pair 0 1) EP K2 :=
    RhsT.pair (Ey := intE) (Ez := intE) (by simp [K2, K1, A2.setE, upd]) rfl PushArg.int
      (by simp [K2, K1, A2.setE, upd]) rfl PushArg.int (by simp [intE, Mode.ownSlot])
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
      (by simp [K3, A2.setE, upd]) (by rw [hEDe]) hpush rfl
    rw [hEDe] at this; exact this
  let EOd : Entry := Entry.arm { EO with ty := ODT, held := [] }
  have hEOd : EOd.mode ≠ .rootb ∧ EOd.dtor = false ∧ EOd.dbind = false := by
    simp [EOd, EO, Entry.arm, ODT, OT, DT, T, Ty.dtorViews, Ty.holdsView]
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
    simp [ED, EP, Entry.arm, DT, T, Ty.dtorViews, Ty.holdsView]
  let K3 : Ctx := A2.setE K2 2 ED
  have hK3 : NoRootb K3 := hK2.setE (by rw [hEDe]; simp)
  have hpair : RhsT K2 [] (.pair 0 1) EP K2 :=
    RhsT.pair (Ey := intE) (Ez := intE) (by simp [K2, K1, A2.setE, upd]) rfl PushArg.int
      (by simp [K2, K1, A2.setE, upd]) rfl PushArg.int (by simp [intE, Mode.ownSlot])
  -- the `Vec` of destructor values, bound by `letd` at its own type
  let EN : Entry := ⟨.vec DT, .own, true, [], [], false, false⟩
  have hnew : RhsT K3 [] (.new DT) EN K3 := RhsT.new (by decide)
  let EV : Entry := Entry.arm { EN with ty := .vec DT, held := [] }
  have hEVe : EV = ⟨.vec DT, .own, true, [], [], false, false⟩ := by
    simp [EV, EN, Entry.arm, DT, T, Ty.dtorViews, Ty.holdsView]
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
    (by simp) hnew rfl (Or.inr ⟨0, rfl, rfl⟩) rfl rfl (letd_fn drop_ok) (HeldUp.refl _ _) hpush (hK6.endOK _)
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

/-! ### A `Vec` of `Vec`s of destructor values (Agora #607)

`: a 1  : b 2  :drop x ( pair a b )  :drop v ( vec_new DT )  ( vec_push v x )
 :drop w ( vec_new ( Vec DT ) )  ( vec_push w v )`: the inner `Vec` moves into
the outer one, bound by `letd` at `vec (vec DT)`. Its frame's end takes the
inner `Vec` out to a `letd` of the same destructor (`Step.scopeDDrain`), whose
frame drains it in turn, each element's destructor running in its own frame. -/

def main11 : Stmt :=
  .letv 0 (.expr (.lit 1)) (.letv 1 (.expr (.lit 2))
    (.letd 2 0 (.pair 0 1) (.letd 3 0 (.new DT)
      (.seq (.push 3 2) (.letd 4 0 (.new (.vec DT)) (.push 4 3))))))

theorem main11_typed : ∃ Δ, StmtT P (fun _ => none) [] main11 Δ := by
  let K1 : Ctx := A2.setE (fun _ => none) 0 intE
  let K2 : Ctx := A2.setE K1 1 intE
  have hK1 : NoRootb K1 := noRootb_empty.setE (by simp [intE])
  have hK2 : NoRootb K2 := hK1.setE (by simp [intE])
  let ED : Entry := Entry.arm { EP with ty := DT, held := [] }
  have hEDe : ED = ⟨DT, .own, true, [], [], false, false⟩ := by
    simp [ED, EP, Entry.arm, DT, T, Ty.dtorViews, Ty.holdsView]
  let K3 : Ctx := A2.setE K2 2 ED
  have hK3 : NoRootb K3 := hK2.setE (by rw [hEDe]; simp)
  have hpair : RhsT K2 [] (.pair 0 1) EP K2 :=
    RhsT.pair (Ey := intE) (Ez := intE) (by simp [K2, K1, A2.setE, upd]) rfl PushArg.int
      (by simp [K2, K1, A2.setE, upd]) rfl PushArg.int (by simp [intE, Mode.ownSlot])
  -- the inner `Vec`, as in `main5`
  let EN : Entry := ⟨.vec DT, .own, true, [], [], false, false⟩
  have hnew : RhsT K3 [] (.new DT) EN K3 := RhsT.new (by decide)
  let EV : Entry := Entry.arm { EN with ty := .vec DT, held := [] }
  have hEVe : EV = ⟨.vec DT, .own, true, [], [], false, false⟩ := by
    simp [EV, EN, Entry.arm, DT, T, Ty.dtorViews, Ty.holdsView]
  let K4 : Ctx := A2.setE K3 3 EV
  have hK4 : NoRootb K4 := hK3.setE (by rw [hEVe]; simp)
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
  let E3 : Entry := { EV with held := EV.held ++ ownHeld true DT ED.held }
  have hE3e : E3 = ⟨.vec DT, .own, true, [], [], false, false⟩ := by
    simp [E3, hEVe, hEDe, ownHeld]
  let K6 : Ctx := A2.setE (kill .realloc DT.holdsView 3 K5) 3 E3
  have hK6 : NoRootb K6 := (hK5.kill _ _ _).setE (by rw [hE3e]; simp)
  -- the outer `Vec`, bound by `letd` at `vec (vec DT)`
  let EN2 : Entry := ⟨.vec (.vec DT), .own, true, [], [], false, false⟩
  have hnew2 : RhsT K6 [] (.new (.vec DT)) EN2 K6 := RhsT.new (by decide)
  let EW : Entry := Entry.arm { EN2 with ty := .vec (.vec DT), held := [] }
  have hEWe : EW = ⟨.vec (.vec DT), .own, true, [], [], false, false⟩ := by
    simp [EW, EN2, Entry.arm, DT, T, Ty.dtorViews, Ty.holdsView]
  let K7 : Ctx := A2.setE K6 4 EW
  have hK7 : NoRootb K7 := hK6.setE (by rw [hEWe]; simp)
  -- the inner `Vec` moves into it
  let K8 : Ctx := A2.setE (kill .replace false 3 K7) 3 { E3 with live := false, dtor := false }
  have hK8 : NoRootb K8 := (hK7.kill _ _ _).setE (by rw [hE3e]; simp)
  have hmove2 : PushArg K7 [] 3 E3 (.vec DT) E3.held K8 :=
    PushArg.move (Γ := K7) (F := []) (y := 3) (E := E3) (t := .vec DT) rfl (by rw [hE3e]) (by simp)
      (hK7.noPin _) (DtorSafe.of_none (fun v E h => (hK7 v E h).2.1) _ _ _)
  have hK84 : K8 4 = some EW := by
    simp [K8, K7, A2.setE, upd, A2.kill, killE, hits, hEWe, Entry.vdeps, Mode.ownSlot]
  have hpush2 := StmtT.push (P := P) (Γ := K7) (Γ1 := K8) (F := []) (x := 4) (y := 3) (Ex := EW) (Ey := E3)
    (Ex1 := EW) (t := .vec DT) (D := E3.held) (by simp [K7, A2.setE, upd]) (by rw [hEWe]) (by rw [hEWe])
    (Or.inl (by rw [hEWe])) (by simp) (by simp [K7, K6, A2.setE, upd]) (by rw [hE3e]) (by rw [hE3e])
    (by decide) hmove2 (by rw [hE3e]; simp [roots]) hK84 (by rw [hEWe])
    (DtorSafe.of_none (fun v E h => (hK8 v E h).2.1) _ _ _) (by rw [hEWe]; simp)
  have hK9 : NoRootb (A2.setE (kill .realloc (Ty.vec DT).holdsView 4 K8) 4
      { EW with held := EW.held ++ ownHeld true (.vec DT) E3.held }) :=
    (hK8.kill _ _ _).setE (by rw [hEWe]; simp)
  have hdw := StmtT.letd (P := P) (Γ := K6) (Γ1 := K6) (F := []) (x := 4) (f := 0) (r := .new (.vec DT))
    (s := .push 4 3) (E := EN2) (t := T) (H := []) (τ := .vec (.vec DT)) rfl
    (by simp [K6, K5, K4, K3, K2, K1, A2.setE, upd, A2.kill])
    (by simp) hnew2 rfl (Or.inr ⟨1, rfl, rfl⟩) rfl rfl (letd_fn drop_ok) (HeldUp.refl _ _) hpush2
    (hK9.endOK _)
  have hseq := StmtT.seq (P := P) rfl hpush hdw
  have hdv := StmtT.letd (P := P) (Γ := K3) (Γ1 := K3) (F := []) (x := 3) (f := 0) (r := .new DT)
    (s := .seq (.push 3 2) (.letd 4 0 (.new (.vec DT)) (.push 4 3))) (E := EN) (t := T) (H := [])
    (τ := .vec DT) rfl (by simp [K3, K2, K1, A2.setE, upd])
    (by simp) hnew rfl (Or.inr ⟨0, rfl, rfl⟩) rfl rfl (letd_fn drop_ok) (HeldUp.refl _ _) hseq
    ((hK9.exitScope 4).endOK _)
  have hd := StmtT.letd (P := P) (Γ := K2) (Γ1 := K2) (F := []) (x := 2) (f := 0) (r := .pair 0 1)
    (s := .letd 3 0 (.new DT) (.seq (.push 3 2) (.letd 4 0 (.new (.vec DT)) (.push 4 3)))) (E := EP) (t := T)
    (H := []) rfl (by simp [K2, K1, A2.setE, upd])
    (by simp) hpair rfl (Or.inl ⟨rfl, Or.inl rfl⟩) rfl rfl (letd_fn drop_ok) (HeldUp.refl _ _) hdv
    (((hK9.exitScope 4).exitScope 3).endOK _)
  have h1 := StmtT.letv (P := P) (x := 1) (r := .expr (.lit 2)) (E := intE) (F := []) (Γ := K1) (Γ1 := K1)
    rfl (by simp [K1, A2.setE, upd]) (by simp) (RhsT.expr ExprT.lit) hd
    ((((hK9.exitScope 4).exitScope 3).exitScope 2).endOK _)
  exact ⟨_, StmtT.letv (P := P) (x := 0) (r := .expr (.lit 1)) (E := intE) (F := []) (Γ := fun _ => none)
    (Γ1 := fun _ => none) rfl rfl (by simp) (RhsT.expr ExprT.lit) h1
    (((((hK9.exitScope 4).exitScope 3).exitScope 2).exitScope 1).endOK _)⟩

/-- The program with a `Vec` of `Vec`s of destructor values is memory safe. -/
theorem main11_safe {m' : Mem} {s' : Stmt} (hr : Steps P (emptyMem 5) main11 (.ok m' s')) :
    ¬ Stuck P m' s' := by
  obtain ⟨Δ, ht⟩ := main11_typed
  exact memory_safe prog_ok prog_codes ht rfl (by simp [main11, Stmt.codesOK, Rhs.codeOK]) (by decide) hr

/-- ... and leaks nothing when it ends (`no_leak_end`: nothing is left
    allocated).  That the drain runs each element's destructor, the inner
    `Vec`'s by a frame of its own, is read off the steps, as for `main5`:
    the theorem does not trace the run. -/
theorem main11_no_leak {m' : Mem} (hr : Steps P (emptyMem 5) main11 (.ok m' .skip)) :
    ∀ i, m'.alloc i = false := by
  obtain ⟨Δ, ht⟩ := main11_typed
  exact no_leak_end prog_ok prog_codes ht rfl (by simp [main11, Stmt.codesOK, Rhs.codeOK]) (by decide) hr

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
    simp [ED, EP, Entry.arm, DT, T, Ty.dtorViews, Ty.holdsView]
  let K3 : Ctx := A2.setE K2 2 ED
  have hK3 : NoRootb K3 := hK2.setE (by rw [hEDe]; simp)
  have hpair : RhsT K2 [] (.pair 0 1) EP K2 :=
    RhsT.pair (Ey := intE) (Ez := intE) (by simp [K2, K1, A2.setE, upd]) rfl PushArg.int
      (by simp [K2, K1, A2.setE, upd]) rfl PushArg.int (by simp [intE, Mode.ownSlot])
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
      hK53 rfl PushArg.int (by simp [intE, Mode.ownSlot])
  let EGa : Entry := Entry.arm { EG0 with ty := GDT, held := EG0.held }
  have hEGa : EGa.mode ≠ .rootb ∧ EGa.dtor = false ∧ EGa.dbind = false := by
    simp [EGa, EG0, Entry.arm, GDT, GT, DT, T, Ty.dtorViews, Ty.holdsView]
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
  rintro (⟨_, h⟩ | ⟨fn, a, b, hfn, _, hps, _⟩ | ⟨_, _, fn, _, _, _, hfn, _, hps, _⟩ |
    ⟨fn, _, _, _, _, hfn, _, hps, _⟩ | ⟨_, _, _, _, _, _, _, _, ht, _⟩)
  · exact absurd h (by decide)
  · simp [P] at hfn; subst hfn; simp [dfn] at hps
  · simp [P] at hfn; subst hfn; simp [dfn] at hps
  · simp [P] at hfn; subst hfn; simp [dfn] at hps
  · cases ht

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
    simp [ED, EP, Entry.arm, DT, T, Ty.dtorViews, Ty.holdsView]
  let K3 : Ctx := A2.setE K2 2 ED
  have hK3 : NoRootb K3 := hK2.setE (by rw [hEDe]; simp)
  have hpair : RhsT K2 [] (.pair 0 1) EP K2 :=
    RhsT.pair (Ey := intE) (Ez := intE) (by simp [K2, K1, A2.setE, upd]) rfl PushArg.int
      (by simp [K2, K1, A2.setE, upd]) rfl PushArg.int (by simp [intE, Mode.ownSlot])
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
      hK53 rfl PushArg.int (by simp [intE, Mode.ownSlot])
  let EGa : Entry := Entry.arm { EG0 with ty := SDT2, held := EG0.held }
  have hEGa : EGa.mode ≠ .rootb ∧ EGa.dtor = false ∧ EGa.dbind = false := by
    simp [EGa, EG0, Entry.arm, SDT2, GT, DT, T, Ty.dtorViews, Ty.holdsView]
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

/-! ### A struct with a destructor field and a view field (Agora #633)

`: s ( new int )  : v ( view s )  : a 1  : b 2  :drop c ( pair a b )
:drop g ( pair c v )`: the struct holds the destructor value `c` and a view
of the older binding `s` (nurlc's `: P { Conn c s name }`); it is bound by
`letd` at `GSD`, armed: it views `s`.  At the frame's end it moves into its
glue `glueS` as a `sink` argument that holds that view (`glueCall_typed`),
which takes it apart, the destructor field going to a `letd` of its own. -/

def main10 : Stmt :=
  .letv 0 (.new .int) (.letv 1 (.view 0) (.letv 2 (.expr (.lit 1)) (.letv 3 (.expr (.lit 2))
    (.letd 4 0 (.pair 2 3) (.letd 5 8 (.pair 4 1) .skip)))))

/-- The end of a binding that views other bindings, in a context with no
    borrowed parameter and no other binding that runs a destructor. -/
theorem endOK_viewing {Γ : Ctx} (h : NoRootb Γ) {x : Var} {E : Entry} (hm : E.mode ≠ .rootb)
    (hx : x ∉ roots E.vdeps) : EndOK (A2.setE Γ x E) x := by
  refine ⟨fun p Ep hp hmp => ?_, fun v Ev hv hd _ => ?_, fun v Ev hv hd _ _ d hdd _ => ?_⟩
  · by_cases hpx : p = x
    · subst hpx; simp [A2.setE] at hp; subst hp; exact absurd hmp hm
    · rw [A2.setE, upd_ne _ _ hpx] at hp; exact absurd hmp (h p Ep hp).1
  · by_cases hvx : v = x
    · subst hvx; simp [A2.setE] at hv; subst hv
      simp [hitsMem]
      intro _ d hd hdv
      exact absurd (by rw [← hdv]; exact List.mem_map_of_mem hd) hx
    · rw [A2.setE, upd_ne _ _ hvx] at hv; rw [(h v Ev hv).2.1] at hd; cases hd
  · by_cases hvx : v = x
    · subst hvx; simp [A2.setE] at hv; subst hv
      intro hdx; exact hx (by rw [← hdx]; exact List.mem_map_of_mem hdd)
    · rw [A2.setE, upd_ne _ _ hvx] at hv; rw [(h v Ev hv).2.2] at hd; cases hd

theorem exitScope_setE_same (Γ : Ctx) (x : Var) (E : Entry) :
    A2.exitScope x (A2.setE Γ x E) = A2.exitScope x Γ := by
  funext w
  by_cases hwx : w = x
  · subst hwx; simp [A2.exitScope]
  · simp [A2.exitScope, upd_ne _ _ hwx, A2.kill, A2.setE]

def EN0 : Entry := ⟨.vec .int, .own, true, [], [], false, false⟩
def EVw : Entry := ⟨.slice .int, .bor, true, derive 0 EN0 .view, EN0.held, false, false⟩

theorem main10_typed : ∃ Δ, StmtT P (fun _ => none) [] main10 Δ := by
  let K1 : Ctx := A2.setE (fun _ => none) 0 EN0
  have hK1 : NoRootb K1 := noRootb_empty.setE (by simp [EN0])
  let K2 : Ctx := A2.setE K1 1 EVw
  have hK2 : NoRootb K2 := hK1.setE (by simp [EVw])
  let K3 : Ctx := A2.setE K2 2 intE
  let K4 : Ctx := A2.setE K3 3 intE
  have hK4 : NoRootb K4 := (hK2.setE (by simp [intE])).setE (by simp [intE])
  have hview : RhsT K1 [] (.view 0) EVw K1 :=
    RhsT.view (E := EN0) (t := .int) (by simp [K1, A2.setE]) rfl rfl rfl
  let ED : Entry := Entry.arm { EP with ty := DT, held := [] }
  have hEDe : ED = ⟨DT, .own, true, [], [], false, false⟩ := by
    simp [ED, EP, Entry.arm, DT, T, Ty.dtorViews, Ty.holdsView]
  have hpair : RhsT K4 [] (.pair 2 3) EP K4 :=
    RhsT.pair (Ey := intE) (Ez := intE) (by simp [K4, K3, A2.setE, upd]) rfl PushArg.int
      (by simp [K4, A2.setE]) rfl PushArg.int (by simp [intE, Mode.ownSlot])
  let K5 : Ctx := A2.setE K4 4 ED
  have hK5 : NoRootb K5 := hK4.setE (by rw [hEDe]; simp)
  -- the struct literal: the destructor value moves in, the view is copied
  let K6 : Ctx := A2.setE (kill .replace false 4 K5) 4 { ED with live := false, dtor := false }
  have hK6 : NoRootb K6 := (hK5.kill _ _ _).setE (by rw [hEDe]; simp)
  have hmove : PushArg K5 [] 4 ED ED.ty ED.held K6 :=
    PushArg.move (Γ := K5) (F := []) (y := 4) (E := ED) (t := ED.ty) rfl (by rw [hEDe]) (by simp)
      (hK5.noPin _) (DtorSafe.of_none (fun v E h => (hK5 v E h).2.1) _ _ _)
  have hK61 : K6 1 = some EVw := by
    simp [K6, K5, K4, K3, K2, A2.setE, upd, A2.kill, killE, hits, EVw, EN0, derive, Mode.isRoot,
      rootKind, Entry.vdeps, Mode.ownSlot]
  let EG0 : Entry := ⟨.prod ED.ty EVw.ty, .own, true, [], ED.held ++ (derive 1 EVw .self ++ EVw.held),
    false, false⟩
  have hgp : RhsT K5 [] (.pair 4 1) EG0 K6 :=
    RhsT.pair (Ey := ED) (Ez := EVw) (by simp [K5, A2.setE]) (by rw [hEDe]) hmove
      hK61 rfl (PushArg.slice (s := .int) (Or.inl rfl)) (by simp [EVw, Mode.ownSlot])
  let EGa : Entry := Entry.arm { EG0 with ty := GSD, held := EG0.held }
  -- armed: it views `s` (binding 0), and nothing of its own
  have hEGa : EGa = ⟨GSD, .own, true, [], [⟨0, .view⟩], true, true⟩ := by
    simp [EGa, EG0, hEDe, Entry.arm, EVw, EN0, derive, Mode.isRoot, rootKind, comp, GSD, GS, DT, T,
      Ty.dtorViews, Ty.holdsView]
  have hEnd5 : EndOK (A2.setE K6 5 EGa) 5 :=
    endOK_viewing hK6 (by rw [hEGa]; simp) (by rw [hEGa]; simp [roots, Entry.vdeps, Mode.ownSlot])
  have hg := StmtT.letd (P := P) (Γ := K5) (Γ1 := K6) (F := []) (x := 5) (f := 8) (r := .pair 4 1)
    (s := .skip) (E := EG0) (t := GS) (H := EG0.held) (τ := GSD) rfl
    (by simp [K5, K4, K3, K2, K1, A2.setE, upd]) (by simp) hgp rfl
    (Or.inl ⟨rfl, Or.inl (by simp [EG0, hEDe, EVw, GS])⟩) rfl rfl (letd_fn gsdrop_ok) (HeldUp.refl _ _)
    StmtT.skip hEnd5
  rw [exitScope_setE_same] at hg
  have hK7 := hK6.exitScope 5
  have hd := StmtT.letd (P := P) (Γ := K4) (Γ1 := K4) (F := []) (x := 4) (f := 0) (r := .pair 2 3)
    (E := EP) (t := T) (H := []) rfl (by simp [K4, K3, K2, K1, A2.setE, upd])
    (by simp) hpair rfl (Or.inl ⟨rfl, Or.inl rfl⟩) rfl rfl (letd_fn drop_ok) (HeldUp.refl _ _) hg
    (hK7.endOK _)
  have h3 := StmtT.letv (P := P) (x := 3) (r := .expr (.lit 2)) (E := intE) (F := []) (Γ := K3) (Γ1 := K3)
    rfl (by simp [K3, K2, K1, A2.setE, upd]) (by simp) (RhsT.expr ExprT.lit) hd
    ((hK7.exitScope 4).endOK _)
  have h2 := StmtT.letv (P := P) (x := 2) (r := .expr (.lit 1)) (E := intE) (F := []) (Γ := K2) (Γ1 := K2)
    rfl (by simp [K2, K1, A2.setE, upd]) (by simp) (RhsT.expr ExprT.lit) h3
    (((hK7.exitScope 4).exitScope 3).endOK _)
  have h1 := StmtT.letv (P := P) (x := 1) (r := .view 0) (E := EVw) (F := []) (Γ := K1) (Γ1 := K1)
    rfl (by simp [K1, A2.setE]) (by simp) hview h2
    ((((hK7.exitScope 4).exitScope 3).exitScope 2).endOK _)
  exact ⟨_, StmtT.letv (P := P) (x := 0) (r := .new .int) (E := EN0) (F := []) (Γ := fun _ => none)
    (Γ1 := fun _ => none) rfl rfl (by simp) (RhsT.new (by decide)) h1
    (((((hK7.exitScope 4).exitScope 3).exitScope 2).exitScope 1).endOK _)⟩

/-- The program with a struct that holds a destructor value and a view of an
    older binding, dropped by its glue, is memory safe. -/
theorem main10_safe {m' : Mem} {s' : Stmt} (hr : Steps P (emptyMem 6) main10 (.ok m' s')) :
    ¬ Stuck P m' s' := by
  obtain ⟨Δ, ht⟩ := main10_typed
  exact memory_safe prog_ok prog_codes ht rfl (by simp [main10, Stmt.codesOK, Rhs.codeOK]) (by decide) hr

/-! ### An enum with a destructor payload and a view payload (Agora #750)

`: s ( new int )  : v ( view s )  :drop o ( inr DT v )`: an enum of type
`sum DT (slice int)`, its view variant made here, holding a view of the
older binding `s`.  It is bound by `letd` at `OVD`, armed: it views `s`.
At the frame's end it moves into its glue `ofnV` as a `sink` argument that
holds that view (`glueCall_typed`), whose view arm runs no code. -/

def main12 : Stmt :=
  .letv 0 (.new .int) (.letv 1 (.view 0) (.letd 2 9 (.inr DT 1) .skip))

theorem main12_typed : ∃ Δ, StmtT P (fun _ => none) [] main12 Δ := by
  let K1 : Ctx := A2.setE (fun _ => none) 0 EN0
  have hK1 : NoRootb K1 := noRootb_empty.setE (by simp [EN0])
  let K2 : Ctx := A2.setE K1 1 EVw
  have hK2 : NoRootb K2 := hK1.setE (by simp [EVw])
  have hview : RhsT K1 [] (.view 0) EVw K1 :=
    RhsT.view (E := EN0) (t := .int) (by simp [K1, A2.setE]) rfl rfl rfl
  let EO0 : Entry := ⟨.sum DT EVw.ty, .own, true, [], derive 1 EVw .self ++ EVw.held, false, false⟩
  -- the enum literal: the view is copied in
  have hinr : RhsT K2 [] (.inr DT 1) EO0 K2 :=
    RhsT.inr (Ey := EVw) (by simp [K2, A2.setE]) rfl (PushArg.slice (s := .int) (Or.inl rfl))
      (by simp [DT, T, Ty.ok, Ty.isStruct])
  let EOa : Entry := Entry.arm { EO0 with ty := OVD, held := EO0.held }
  -- armed: it views `s` (binding 0), and nothing of its own
  have hEOa : EOa = ⟨OVD, .own, true, [], [⟨0, .view⟩], true, true⟩ := by
    simp [EOa, EO0, Entry.arm, EVw, EN0, derive, Mode.isRoot, rootKind, comp, OVD, OV, DT, T,
      Ty.dtorViews, Ty.holdsView]
  have hEnd : EndOK (A2.setE K2 2 EOa) 2 :=
    endOK_viewing hK2 (by rw [hEOa]; simp) (by rw [hEOa]; simp [roots, Entry.vdeps, Mode.ownSlot])
  have hd := StmtT.letd (P := P) (Γ := K2) (Γ1 := K2) (F := []) (x := 2) (f := 9) (r := .inr DT 1)
    (s := .skip) (E := EO0) (t := OV) (H := EO0.held) (τ := OVD) rfl
    (by simp [K2, K1, A2.setE, upd]) (by simp) hinr rfl
    (Or.inl ⟨rfl, Or.inl (by simp [EO0, EVw, OV])⟩) rfl rfl (letd_fn ovdrop_ok) (HeldUp.refl _ _)
    StmtT.skip hEnd
  rw [exitScope_setE_same] at hd
  have h1 := StmtT.letv (P := P) (x := 1) (r := .view 0) (E := EVw) (F := []) (Γ := K1) (Γ1 := K1)
    rfl (by simp [K1, A2.setE]) (by simp) hview hd ((hK2.exitScope 2).endOK _)
  exact ⟨_, StmtT.letv (P := P) (x := 0) (r := .new .int) (E := EN0) (F := []) (Γ := fun _ => none)
    (Γ1 := fun _ => none) rfl rfl (by simp) (RhsT.new (by decide)) h1
    (((hK2.exitScope 2).exitScope 1).endOK _)⟩

/-- The program with an enum that has a destructor payload and a view
    payload, holding the view of an older binding, dropped by its glue, is
    memory safe. -/
theorem main12_safe {m' : Mem} {s' : Stmt} (hr : Steps P (emptyMem 3) main12 (.ok m' s')) :
    ¬ Stuck P m' s' := by
  obtain ⟨Δ, ht⟩ := main12_typed
  exact memory_safe prog_ok prog_codes ht rfl (by simp [main12, Stmt.codesOK, Rhs.codeOK]) (by decide) hr

/-! ### A view-holding struct with its own `% Drop` (Agora #750)

`main10`'s program, the struct bound at `GSD2`, whose glue `glueS2`
rebinds it under the fields' glue `glueS` and runs the impl `implS` on it
lent; the struct views `s`, and the frame's end moves it, view and all,
into `glueS2`. -/

def main13 : Stmt :=
  .letv 0 (.new .int) (.letv 1 (.view 0) (.letv 2 (.expr (.lit 1)) (.letv 3 (.expr (.lit 2))
    (.letd 4 0 (.pair 2 3) (.letd 5 11 (.pair 4 1) .skip)))))

theorem main13_typed : ∃ Δ, StmtT P (fun _ => none) [] main13 Δ := by
  let K1 : Ctx := A2.setE (fun _ => none) 0 EN0
  have hK1 : NoRootb K1 := noRootb_empty.setE (by simp [EN0])
  let K2 : Ctx := A2.setE K1 1 EVw
  have hK2 : NoRootb K2 := hK1.setE (by simp [EVw])
  let K3 : Ctx := A2.setE K2 2 intE
  let K4 : Ctx := A2.setE K3 3 intE
  have hK4 : NoRootb K4 := (hK2.setE (by simp [intE])).setE (by simp [intE])
  have hview : RhsT K1 [] (.view 0) EVw K1 :=
    RhsT.view (E := EN0) (t := .int) (by simp [K1, A2.setE]) rfl rfl rfl
  let ED : Entry := Entry.arm { EP with ty := DT, held := [] }
  have hEDe : ED = ⟨DT, .own, true, [], [], false, false⟩ := by
    simp [ED, EP, Entry.arm, DT, T, Ty.dtorViews, Ty.holdsView]
  have hpair : RhsT K4 [] (.pair 2 3) EP K4 :=
    RhsT.pair (Ey := intE) (Ez := intE) (by simp [K4, K3, A2.setE, upd]) rfl PushArg.int
      (by simp [K4, A2.setE]) rfl PushArg.int (by simp [intE, Mode.ownSlot])
  let K5 : Ctx := A2.setE K4 4 ED
  have hK5 : NoRootb K5 := hK4.setE (by rw [hEDe]; simp)
  let K6 : Ctx := A2.setE (kill .replace false 4 K5) 4 { ED with live := false, dtor := false }
  have hK6 : NoRootb K6 := (hK5.kill _ _ _).setE (by rw [hEDe]; simp)
  have hmove : PushArg K5 [] 4 ED ED.ty ED.held K6 :=
    PushArg.move (Γ := K5) (F := []) (y := 4) (E := ED) (t := ED.ty) rfl (by rw [hEDe]) (by simp)
      (hK5.noPin _) (DtorSafe.of_none (fun v E h => (hK5 v E h).2.1) _ _ _)
  have hK61 : K6 1 = some EVw := by
    simp [K6, K5, K4, K3, K2, A2.setE, upd, A2.kill, killE, hits, EVw, EN0, derive, Mode.isRoot,
      rootKind, Entry.vdeps, Mode.ownSlot]
  let EG0 : Entry := ⟨.prod ED.ty EVw.ty, .own, true, [], ED.held ++ (derive 1 EVw .self ++ EVw.held),
    false, false⟩
  have hgp : RhsT K5 [] (.pair 4 1) EG0 K6 :=
    RhsT.pair (Ey := ED) (Ez := EVw) (by simp [K5, A2.setE]) (by rw [hEDe]) hmove
      hK61 rfl (PushArg.slice (s := .int) (Or.inl rfl)) (by simp [EVw, Mode.ownSlot])
  let EGa : Entry := Entry.arm { EG0 with ty := GSD2, held := EG0.held }
  -- armed: it views `s` (binding 0), and nothing of its own
  have hEGa : EGa = ⟨GSD2, .own, true, [], [⟨0, .view⟩], true, true⟩ := by
    simp [EGa, EG0, hEDe, Entry.arm, EVw, EN0, derive, Mode.isRoot, rootKind, comp, GSD2, GS, DT, T,
      Ty.dtorViews, Ty.holdsView]
  have hEnd5 : EndOK (A2.setE K6 5 EGa) 5 :=
    endOK_viewing hK6 (by rw [hEGa]; simp) (by rw [hEGa]; simp [roots, Entry.vdeps, Mode.ownSlot])
  have hg := StmtT.letd (P := P) (Γ := K5) (Γ1 := K6) (F := []) (x := 5) (f := 11) (r := .pair 4 1)
    (s := .skip) (E := EG0) (t := GS) (H := EG0.held) (τ := GSD2) rfl
    (by simp [K5, K4, K3, K2, K1, A2.setE, upd]) (by simp) hgp rfl
    (Or.inl ⟨rfl, Or.inl (by simp [EG0, hEDe, EVw, GS])⟩) rfl rfl (letd_fn gs2drop_ok) (HeldUp.refl _ _)
    StmtT.skip hEnd5
  rw [exitScope_setE_same] at hg
  have hK7 := hK6.exitScope 5
  have hd := StmtT.letd (P := P) (Γ := K4) (Γ1 := K4) (F := []) (x := 4) (f := 0) (r := .pair 2 3)
    (E := EP) (t := T) (H := []) rfl (by simp [K4, K3, K2, K1, A2.setE, upd])
    (by simp) hpair rfl (Or.inl ⟨rfl, Or.inl rfl⟩) rfl rfl (letd_fn drop_ok) (HeldUp.refl _ _) hg
    (hK7.endOK _)
  have h3 := StmtT.letv (P := P) (x := 3) (r := .expr (.lit 2)) (E := intE) (F := []) (Γ := K3) (Γ1 := K3)
    rfl (by simp [K3, K2, K1, A2.setE, upd]) (by simp) (RhsT.expr ExprT.lit) hd
    ((hK7.exitScope 4).endOK _)
  have h2 := StmtT.letv (P := P) (x := 2) (r := .expr (.lit 1)) (E := intE) (F := []) (Γ := K2) (Γ1 := K2)
    rfl (by simp [K2, K1, A2.setE, upd]) (by simp) (RhsT.expr ExprT.lit) h3
    (((hK7.exitScope 4).exitScope 3).endOK _)
  have h1 := StmtT.letv (P := P) (x := 1) (r := .view 0) (E := EVw) (F := []) (Γ := K1) (Γ1 := K1)
    rfl (by simp [K1, A2.setE]) (by simp) hview h2
    ((((hK7.exitScope 4).exitScope 3).exitScope 2).endOK _)
  exact ⟨_, StmtT.letv (P := P) (x := 0) (r := .new .int) (E := EN0) (F := []) (Γ := fun _ => none)
    (Γ1 := fun _ => none) rfl rfl (by simp) (RhsT.new (by decide)) h1
    (((((hK7.exitScope 4).exitScope 3).exitScope 2).exitScope 1).endOK _)⟩

/-- The program with a struct that has its own `% Drop` beside a destructor
    field and a view of an older binding is memory safe. -/
theorem main13_safe {m' : Mem} {s' : Stmt} (hr : Steps P (emptyMem 6) main13 (.ok m' s')) :
    ¬ Stuck P m' s' := by
  obtain ⟨Δ, ht⟩ := main13_typed
  exact memory_safe prog_ok prog_codes ht rfl (by simp [main13, Stmt.codesOK, Rhs.codeOK]) (by decide) hr

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
      (by simp [AT, DT, T, Ty.ok, Ty.isStruct])
  let ESd : Entry := Entry.arm { ES with ty := SDT, held := [] }
  have hESd : ESd.mode ≠ .rootb ∧ ESd.dtor = false ∧ ESd.dbind = false := by
    simp [ESd, ES, Entry.arm, SDT, ST, AT, DT, T, Ty.dtorViews, Ty.holdsView]
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

/-- …but a payload that holds no destructor value is not taken out of it
    (`takel` / `taker`): the enum's destructor would never run.  (Agora #632:
    one that holds a destructor value is taken out only where the enum's
    destructor is its glue, `TakeOK`.) -/
theorem enum_take_refused {Γ Γ' : Ctx} {F : List Var} {E E0 : Entry} {f : Nat} {a b : Ty}
    (h0 : Γ 0 = some E0) (ht : E0.ty = .dtor f (.sum a b)) :
    (a.holdsDtor = false → ¬ RhsT Γ F (.takel 0) E Γ') ∧
      (b.holdsDtor = false → ¬ RhsT Γ F (.taker 0) E Γ') := by
  refine ⟨fun ha h => ?_, fun hb h => ?_⟩
  · cases h with
    | takel hy _ _ hty _ _ _ =>
      rw [h0] at hy; cases hy; rw [ht] at hty
      rcases hty with hty | ⟨g, hty, hd⟩
      · cases hty
      · cases hty; rw [ha] at hd; cases hd
  · cases h with
    | taker hy _ _ hty _ _ _ =>
      rw [h0] at hy; cases hy; rw [ht] at hty
      rcases hty with hty | ⟨g, hty, hd⟩
      · cases hty
      · cases hty; rw [hb] at hd; cases hd

/-! ### A `Vec` of destructor values that hold views of an older binding (Agora #782)

`: s ( new int )  : v ( view s )  : a 1  : b 2  :drop c ( pair a b )
:drop p ( pair c v )  :drop w ( vec_new GSD )  ( vec_push w p )`: `main10`'s
struct, which views the older binding `s`, moves into a `Vec` bound by
`letd` at `vec GSD`.  The `Vec`'s binding records that view up front
(`HeldUp`: a view of `s`, a root bound before it): it is armed
(`Ty.dtorViews`), so nothing ends `s` while it lives, and the push gains it
no view (`StmtT.push`).  Its frame's end drains it (`Step.scopeDDrain`),
each element moved out to a `letd` armed with that view, whose frame moves
it into its glue `glueS`. -/

def main14 : Stmt :=
  .letv 0 (.new .int) (.letv 1 (.view 0) (.letv 2 (.expr (.lit 1)) (.letv 3 (.expr (.lit 2))
    (.letd 4 0 (.pair 2 3) (.letd 5 8 (.pair 4 1) (.letd 6 8 (.new GSD) (.push 6 5)))))))

/-- The witness's contexts: no borrowed parameter, and each binding that
    runs a destructor or is `letd`'s is one of `A`, viewing in memory only
    roots of `R`. -/
def Calm (A R : List Var) (Γ : Ctx) : Prop :=
  ∀ v E, Γ v = some E → E.mode ≠ .rootb ∧ ((E.dtor = true ∨ E.dbind = true) →
    v ∈ A ∧ ∀ d ∈ E.vdeps, d.kind.isName = false → d.root ∈ R)

theorem calm_of_noRootb {Γ : Ctx} (h : NoRootb Γ) (A R : List Var) : Calm A R Γ := fun v E hv => by
  obtain ⟨hm, hd, hb⟩ := h v E hv
  exact ⟨hm, fun h' => by rw [hd, hb] at h'; simp at h'⟩

theorem Calm.noRootb {R : List Var} {Γ : Ctx} (h : Calm [] R Γ) : NoRootb Γ := fun v E hv => by
  obtain ⟨hm, h'⟩ := h v E hv
  refine ⟨hm, ?_, ?_⟩
  · cases hd : E.dtor
    · rfl
    · exact absurd (h' (Or.inl hd)).1 (by simp)
  · cases hd : E.dbind
    · rfl
    · exact absurd (h' (Or.inr hd)).1 (by simp)

theorem Calm.setE {A R : List Var} {Γ : Ctx} (h : Calm A R Γ) {x : Var} {E : Entry}
    (hm : E.mode ≠ .rootb)
    (hE : (E.dtor = true ∨ E.dbind = true) → x ∈ A ∧ ∀ d ∈ E.vdeps, d.kind.isName = false → d.root ∈ R) :
    Calm A R (A2.setE Γ x E) := by
  intro v Ev hv
  by_cases hvx : v = x
  · subst hvx; simp only [A2.setE, upd_same, Option.some.injEq] at hv; subst hv; exact ⟨hm, hE⟩
  · simp only [A2.setE, upd_ne _ _ hvx] at hv; exact h v Ev hv

theorem Calm.kill {A R : List Var} {Γ : Ctx} (h : Calm A R Γ) (e : Eff) (hv : Bool) (x : Var) :
    Calm A R (A2.kill e hv x Γ) := by
  intro v E hE
  simp only [A2.kill] at hE
  cases hg : Γ v with
  | none => rw [hg] at hE; cases hE
  | some E0 =>
    rw [hg] at hE; simp only [Option.map_some, Option.some.injEq] at hE; subst hE
    obtain ⟨hm, h'⟩ := h v E0 hg
    rw [killE_mode, killE_dtor, killE_dbind, killE_vdeps]; exact ⟨hm, h'⟩

theorem Calm.exitScope {A R : List Var} {Γ : Ctx} (h : Calm A R Γ) (x : Var) (A' : List Var)
    (hA : ∀ v ∈ A, v ≠ x → v ∈ A') : Calm A' R (A2.exitScope x Γ) := by
  intro v E hv
  by_cases hvx : v = x
  · subst hvx; simp [A2.exitScope] at hv
  · simp only [A2.exitScope, upd_ne _ _ hvx] at hv
    obtain ⟨hm, h'⟩ := (h.kill .replace false x) v E hv
    exact ⟨hm, fun hd => ⟨hA v (h' hd).1 hvx, (h' hd).2⟩⟩

theorem Calm.noPin {A R : List Var} {Γ : Ctx} (h : Calm A R Γ) (x : Var) : NoPin Γ x :=
  fun p E hp hm => absurd hm (h p E hp).1

theorem Calm.dtorSafe {A R : List Var} {Γ : Ctx} (h : Calm A R Γ) {x : Var} (hx : x ∉ R) (e : Eff)
    (hv : Bool) : DtorSafe Γ e hv x := by
  intro v E hE hd _
  have hR := ((h v E hE).2 (Or.inl hd)).2
  cases hg : (E.ty != .int || E.mode == .rootb)
  · simp [hitsMem, hg]
  · unfold hitsMem; rw [hg, Bool.true_and, List.any_eq_false]
    intro d hdd hc
    simp only [Bool.and_eq_true, beq_iff_eq, Bool.not_eq_true'] at hc
    exact hx (by rw [← hc.1.1]; exact hR d hdd hc.1.2)

theorem Calm.dbindSafe {A R : List Var} {Γ : Ctx} (h : Calm A R Γ) {x : Var} (hx : x ∉ R) :
    DbindSafe Γ x :=
  fun v E hE hd _ _ d hdd hnm hdx => hx (by rw [← hdx]; exact ((h v E hE).2 (Or.inr hd)).2 d hdd hnm)

theorem Calm.endOK {A R : List Var} {Γ : Ctx} (h : Calm A R Γ) {x : Var} (hx : x ∉ R) : EndOK Γ x :=
  ⟨h.noPin x, h.dtorSafe hx _ _, h.dbindSafe hx⟩

theorem main14_typed : ∃ Δ, StmtT P (fun _ => none) [] main14 Δ := by
  -- as in `main10`, up to the struct's binding
  let K1 : Ctx := A2.setE (fun _ => none) 0 EN0
  have hK1 : NoRootb K1 := noRootb_empty.setE (by simp [EN0])
  let K2 : Ctx := A2.setE K1 1 EVw
  have hK2 : NoRootb K2 := hK1.setE (by simp [EVw])
  let K3 : Ctx := A2.setE K2 2 intE
  let K4 : Ctx := A2.setE K3 3 intE
  have hK4 : NoRootb K4 := (hK2.setE (by simp [intE])).setE (by simp [intE])
  have hview : RhsT K1 [] (.view 0) EVw K1 :=
    RhsT.view (E := EN0) (t := .int) (by simp [K1, A2.setE]) rfl rfl rfl
  let ED : Entry := Entry.arm { EP with ty := DT, held := [] }
  have hEDe : ED = ⟨DT, .own, true, [], [], false, false⟩ := by
    simp [ED, EP, Entry.arm, DT, T, Ty.dtorViews, Ty.holdsView]
  have hpair : RhsT K4 [] (.pair 2 3) EP K4 :=
    RhsT.pair (Ey := intE) (Ez := intE) (by simp [K4, K3, A2.setE, upd]) rfl PushArg.int
      (by simp [K4, A2.setE]) rfl PushArg.int (by simp [intE, Mode.ownSlot])
  let K5 : Ctx := A2.setE K4 4 ED
  have hK5 : NoRootb K5 := hK4.setE (by rw [hEDe]; simp)
  let K6 : Ctx := A2.setE (kill .replace false 4 K5) 4 { ED with live := false, dtor := false }
  have hK6 : NoRootb K6 := (hK5.kill _ _ _).setE (by rw [hEDe]; simp)
  have hmove : PushArg K5 [] 4 ED ED.ty ED.held K6 :=
    PushArg.move (Γ := K5) (F := []) (y := 4) (E := ED) (t := ED.ty) rfl (by rw [hEDe]) (by simp)
      (hK5.noPin _) (DtorSafe.of_none (fun v E h => (hK5 v E h).2.1) _ _ _)
  have hK61 : K6 1 = some EVw := by
    simp [K6, K5, K4, K3, K2, A2.setE, upd, A2.kill, killE, hits, EVw, EN0, derive, Mode.isRoot,
      rootKind, Entry.vdeps, Mode.ownSlot]
  let EG0 : Entry := ⟨.prod ED.ty EVw.ty, .own, true, [], ED.held ++ (derive 1 EVw .self ++ EVw.held),
    false, false⟩
  have hgp : RhsT K5 [] (.pair 4 1) EG0 K6 :=
    RhsT.pair (Ey := ED) (Ez := EVw) (by simp [K5, A2.setE]) (by rw [hEDe]) hmove
      hK61 rfl (PushArg.slice (s := .int) (Or.inl rfl)) (by simp [EVw, Mode.ownSlot])
  let EGa : Entry := Entry.arm { EG0 with ty := GSD, held := EG0.held }
  have hEGa : EGa = ⟨GSD, .own, true, [], [⟨0, .view⟩], true, true⟩ := by
    simp [EGa, EG0, hEDe, Entry.arm, EVw, EN0, derive, Mode.isRoot, rootKind, comp, GSD, GS, DT, T,
      Ty.dtorViews, Ty.holdsView]
  -- the struct's binding, armed: it views `s` (binding 0)
  let K7 : Ctx := A2.setE K6 5 EGa
  have hC7 : Calm [5, 6] [0] K7 := (calm_of_noRootb hK6 _ _).setE (by rw [hEGa]; simp)
    (fun _ => by rw [hEGa]; simp [Entry.vdeps, Mode.ownSlot])
  -- the `Vec`, bound by `letd` at `vec GSD`, recording the view of `s` up front
  let EN : Entry := ⟨.vec GSD, .own, true, [], [], false, false⟩
  have hnew : RhsT K7 [] (.new GSD) EN K7 := RhsT.new (by decide)
  have hK70 : K7 0 = some EN0 := by
    simp [K7, K6, K5, K4, K3, K2, K1, A2.setE, upd, A2.kill, killE, hits, EN0, Entry.vdeps, Mode.ownSlot]
  have hH : HeldUp K7 EN [⟨0, .view⟩] := ⟨List.nil_subset _, fun d hd => by
    simp only [List.mem_singleton] at hd; subst hd
    exact Or.inr ⟨rfl, EN0, hK70, rfl⟩⟩
  let EW : Entry := Entry.arm { EN with ty := .vec GSD, held := [⟨0, .view⟩] }
  -- armed: its elements' destructors read what it views
  have hEWe : EW = ⟨.vec GSD, .own, true, [], [⟨0, .view⟩], true, true⟩ := by
    simp [EW, EN, Entry.arm, GSD, GS, DT, T, Ty.dtorViews, Ty.holdsView]
  let K8 : Ctx := A2.setE K7 6 EW
  have hC8 : Calm [5, 6] [0] K8 := hC7.setE (by rw [hEWe]; simp)
    (fun _ => by rw [hEWe]; simp [Entry.vdeps, Mode.ownSlot])
  -- the struct moves into it
  let K9 : Ctx := A2.setE (kill .replace false 5 K8) 5 { EGa with live := false, dtor := false }
  have hC9 : Calm [5, 6] [0] K9 := (hC8.kill _ _ _).setE (by rw [hEGa]; simp)
    (fun _ => by rw [hEGa]; simp [Entry.vdeps, Mode.ownSlot])
  have hmove2 : PushArg K8 [] 5 EGa GSD EGa.held K9 :=
    PushArg.move (Γ := K8) (F := []) (y := 5) (E := EGa) (t := GSD) rfl (by rw [hEGa]) (by simp)
      (hC8.noPin _) (hC8.dtorSafe (by simp) _ _)
  have hK96 : K9 6 = some EW := by
    simp [K9, K8, A2.setE, upd, A2.kill, killE, hits, hEWe, Entry.vdeps, Mode.ownSlot]
  have hpush := StmtT.push (P := P) (Γ := K8) (Γ1 := K9) (F := []) (x := 6) (y := 5) (Ex := EW) (Ey := EGa)
    (Ex1 := EW) (t := GSD) (D := EGa.held) (by simp [K8, A2.setE]) (by rw [hEWe]) (by rw [hEWe])
    (Or.inl (by rw [hEWe])) (by simp) (by simp [K8, K7, A2.setE, upd]) (by rw [hEGa]) (by rw [hEGa])
    (by decide) hmove2 (by rw [hEGa]; simp [roots]) hK96 (by rw [hEWe])
    (hC9.dtorSafe (by simp) _ _)
    -- what the struct views, the `Vec`'s binding views already
    (fun _ => by rw [hEWe, hEGa]; simp [ownHeld, GSD, GS, Ty.holdsView])
  let E10 : Entry := { EW with held := EW.held ++ ownHeld true GSD EGa.held }
  have hE10 : E10 = ⟨.vec GSD, .own, true, [], [⟨0, .view⟩, ⟨0, .view⟩], true, true⟩ := by
    simp [E10, hEWe, hEGa, ownHeld, GSD, GS, Ty.holdsView]
  have hC10 : Calm [5, 6] [0] (A2.setE (kill .realloc GSD.holdsView 6 K9) 6 E10) :=
    (hC9.kill _ _ _).setE (by rw [hE10]; simp) (fun _ => by rw [hE10]; simp [Entry.vdeps, Mode.ownSlot])
  have hdw := StmtT.letd (P := P) (Γ := K7) (Γ1 := K7) (F := []) (x := 6) (f := 8) (r := .new GSD)
    (s := .push 6 5) (E := EN) (t := GS) (H := [⟨0, .view⟩]) (τ := .vec GSD) rfl
    (by simp [K7, K6, K5, K4, K3, K2, K1, A2.setE, upd, A2.kill])
    (by simp) hnew rfl (Or.inr ⟨0, rfl, rfl⟩) rfl rfl (letd_fn gsdrop_ok) hH hpush
    (hC10.endOK (by simp))
  have hC11 := hC10.exitScope 6 [5] (by simp)
  have hg := StmtT.letd (P := P) (Γ := K5) (Γ1 := K6) (F := []) (x := 5) (f := 8) (r := .pair 4 1)
    (s := .letd 6 8 (.new GSD) (.push 6 5)) (E := EG0) (t := GS) (H := EG0.held) (τ := GSD) rfl
    (by simp [K5, K4, K3, K2, K1, A2.setE, upd]) (by simp) hgp rfl
    (Or.inl ⟨rfl, Or.inl (by simp [EG0, hEDe, EVw, GS])⟩) rfl rfl (letd_fn gsdrop_ok) (HeldUp.refl _ _)
    hdw (hC11.endOK (by simp))
  have hK12 : NoRootb _ := (hC11.exitScope 5 [] (by simp)).noRootb
  have hd := StmtT.letd (P := P) (Γ := K4) (Γ1 := K4) (F := []) (x := 4) (f := 0) (r := .pair 2 3)
    (E := EP) (t := T) (H := []) rfl (by simp [K4, K3, K2, K1, A2.setE, upd])
    (by simp) hpair rfl (Or.inl ⟨rfl, Or.inl rfl⟩) rfl rfl (letd_fn drop_ok) (HeldUp.refl _ _) hg
    (hK12.endOK _)
  have h3 := StmtT.letv (P := P) (x := 3) (r := .expr (.lit 2)) (E := intE) (F := []) (Γ := K3) (Γ1 := K3)
    rfl (by simp [K3, K2, K1, A2.setE, upd]) (by simp) (RhsT.expr ExprT.lit) hd
    ((hK12.exitScope 4).endOK _)
  have h2 := StmtT.letv (P := P) (x := 2) (r := .expr (.lit 1)) (E := intE) (F := []) (Γ := K2) (Γ1 := K2)
    rfl (by simp [K2, K1, A2.setE, upd]) (by simp) (RhsT.expr ExprT.lit) h3
    (((hK12.exitScope 4).exitScope 3).endOK _)
  have h1 := StmtT.letv (P := P) (x := 1) (r := .view 0) (E := EVw) (F := []) (Γ := K1) (Γ1 := K1)
    rfl (by simp [K1, A2.setE]) (by simp) hview h2
    ((((hK12.exitScope 4).exitScope 3).exitScope 2).endOK _)
  exact ⟨_, StmtT.letv (P := P) (x := 0) (r := .new .int) (E := EN0) (F := []) (Γ := fun _ => none)
    (Γ1 := fun _ => none) rfl rfl (by simp) (RhsT.new (by decide)) h1
    (((((hK12.exitScope 4).exitScope 3).exitScope 2).exitScope 1).endOK _)⟩

/-- The program with a `Vec` of destructor values that hold a view of an
    older binding is memory safe. -/
theorem main14_safe {m' : Mem} {s' : Stmt} (hr : Steps P (emptyMem 7) main14 (.ok m' s')) :
    ¬ Stuck P m' s' := by
  obtain ⟨Δ, ht⟩ := main14_typed
  exact memory_safe prog_ok prog_codes ht rfl (by simp [main14, Stmt.codesOK, Rhs.codeOK]) (by decide) hr

/-- ... and leaks nothing when it ends (`no_leak_end`).  That the drain runs
    each element's glue, in a frame armed with the view, is read off the
    steps, as for `main11`: the theorem does not trace the run. -/
theorem main14_no_leak {m' : Mem} (hr : Steps P (emptyMem 7) main14 (.ok m' .skip)) :
    ∀ i, m'.alloc i = false := by
  obtain ⟨Δ, ht⟩ := main14_typed
  exact no_leak_end prog_ok prog_codes ht rfl (by simp [main14, Stmt.codesOK, Rhs.codeOK]) (by decide) hr

end A2.DtorWitness
