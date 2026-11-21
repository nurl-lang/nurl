# A2 — AGORA-937 stage 3: a through-changing call that passes views of real memory

## Status

Design only, no rule change yet. Turn-ons 1–4 (github#2141) let a callee's
own typing hand a regioned `sink`/`inout` parameter to through-changing code.
At a caller where no binding is a region (every context `MInv` is stated of,
`MInv.noRegion`), `CallT` still requires that such a call pass no argument
holding views (`callR_nil_of_regions`).
`A2/HeldViewThruWitness.lean`'s `call_alone_refused` is that refusal: AGORA-933's
`( f1 vv )`, with `vv` a `Vec` of slices of the caller's `w`. nurlc accepts
the call and ends the caller's views into `w`'s elements (github#2100,
github#2142). Stage 3 is to type it.

## Why the premise is there today

A call is proved by placing the body in the caller's store and typing it
there (`RSetup.StmtT.ren`, `CallH.typedIn`). The lift makes two choices that
need `callR = []` for a through-changing body:

1. **Regions are substituted.** `subD` replaces a dependency on `π p` by what
   argument `p` holds (`σ`), verbatim. A callee change through a borrow that
   reaches `π p` then becomes, in the lifted context, a change through the
   caller's root `r`. Its kill on `r` is coarser than the callee's kill on
   `π p` (`A2/ThruLiftKinds.lean`: `comp_view_overkills`,
   `comp_inner_push_overkills`). So it can end a lifted callee binding that
   the body still reads, and the lifted body does not type. `StmtT.ren` is
   proved as an equality of contexts, and that equality fails.
2. **The arguments' roots are frozen.** Every lifted entry may depend on
   anything the arguments hold (`RSetup.A = allKinds R ++ N`). That is sound
   only because nothing in the body can change `R` (`Fc`). A
   through-changing body changes memory under `R` by definition.

Names never had this problem: a name dependency is lifted as itself
(`RSetup.N`), and `Eff.kills e _ (.name _ _) = false` below `.replace`.

## The design: a region is lifted as a ghost binding, as a name is

- **Ghost region bindings.** Where the call places the body, each region
  `π p` of a regioned parameter is lifted to a fresh caller-level binding
  `G p` of mode `.region`, not substituted. A callee dependency `⟨π p, k⟩`
  becomes `⟨G p, k⟩`. Body kills on `π p` then hit exactly the lifted
  bindings that depend on `G p`, as the callee's kills do. So `StmtT.ren`'s
  equality holds as it does for names, and obstacle 1 is gone.
- **R is no longer frozen for these roots.** The lifted entries reach the
  argument's memory through `G p`, not through `allKinds R`. So `RSetup.R`
  for the call excludes the roots reached only through regioned parameters,
  and the body may change memory under them. That removes obstacle 2.
- **Regions for lent parameters too.** Today only `sink` and `inout`
  parameters that hold views get a region (`regioned`). AGORA-933's `f1`
  takes `vv` lent (`.inp`). A lent parameter is lifted to its argument's own
  entry (`liftE`'s `.rootb` case, `S.pe`), so its provenance is the
  caller's. Stage 3 gives a view-holding lent parameter a region as well.
  `paramE` gives a `.rootb` entry no `held` today, so the `.rootb` lift has
  to keep the region dependency instead of taking `S.pe` wholesale.
- **The caller's views of the changed roots end, in two steps.** Let `Rj` be
  the real (non-region) roots in `callR`.
  - *At entry:* the frame's bindings, except the arguments, get
    `kill .drop hv r` for each `r ∈ Rj`. They must be dead while the body
    runs, because `MInv` speaks of every live binding of the combined
    context and the body moves buffers under `r`. The callee cannot reach
    the frame, so this changes nothing the lifted body types, and a later
    kill on `r` ends nothing more (`kill_after_replace` and its `.drop`
    twin).
  - *At exit:* `callPost` also kills the arguments' dependencies on `Rj`.
    During the body they are read through the lifted parameters and are
    valid there.
  - A2's `Eff` has no depth: a `.drop` on `r` ends `.view` borrows of `r`'s
    buffer too, though the callee changes only its elements' insides. So A2
    ends `sw` (a view of `w`'s own buffer), which nurlc keeps
    (`sink_vec_of_slices_grown_by_its_callee_keeps_the_callers_view_of_the_outer_buffer_runs_clean`).
    A2 types fewer programs than nurlc accepts here, which is no hole. A
    depth-aware effect is a later refinement.
- **`CallT`'s premise.** `ThruFn P f → ∀ r ∈ callR Γ args`, either `r` is a
  region (today's case) or, for a real root:
  - `r ∉ F` (not frozen);
  - no argument other than those holding views of `r` reaches `r` in memory;
  - no dependency on `r` goes through a share (`.share`: a payload is frozen).

  The result `Γ'` is `callPost` with the exit kill.
- **The invariant.** `MInv.noRegion` becomes a statement about the
  frame-free part. The combined context holds `G p` bindings, which have no
  store slot. So `MInv` gets a ghost store `g : Var → Option RegionSnap`
  (claude-accurate's option 3, agora #4123):
  - a region's ghost value is the set of buffer addresses `D` its
    argument's views point into (the `d` of each `view d o l` it holds), not
    a copy of those values: the body changes those nodes in place, so a
    stored value would go stale. A view reached through `⟨G p, k⟩` is
    `Landed` where the node *currently* at some `d ∈ D` puts it, and that
    node is found in memory (`RootNode` for a region is "the node at an
    address of `D`"), wherever its owner's slot is. That is `RootNode`'s
    existing view case generalised: a borrowed slot whose value has
    `view d o l` at its top reaches `DataAt m d n`. So a region reaches
    `∃ d ∈ D, DataAt m d n`, and `Lands`/`Landed`/`ViewAt` apply unchanged;
  - `dom` reads `m.st v` or `g v`;
  - a region binding's clause says its addresses are live nodes of `m`,
    and that no live frame binding *other than the call's arguments and the
    owners of that memory* reaches inside them, which is what the entry
    kill establishes (`thruPre_dead`; `pre_s2_dead`). The arguments stay
    live because the body reads them through its parameters. The owners stay
    live because an owner's validity is its own tree's (`SlotOK`'s owned
    case: `WFv` and the views it holds), not that of views into it. On
    AGORA-933's witness that is `vv` and `w` (`pre_vv_kept`, `pre_w_kept`).
    Step 3c proves their slots stay valid while the body changes nodes
    inside `w`'s elements;
  - `Step` is unchanged. `StepI` is `Step` plus ghost writes at
    `letcall`/`callc*`, and the erasure is the first projection. So
    `Step`, `Mem` and the crown's statement stay byte-identical.
- **The result.** At exit the result's and the `inout` arguments'
  dependencies on `G p` are substituted by `σ`, as `callRes` already does
  for `π p` (`heldOfArgs`, `CallH.res_at`).

## Steps, each landing with its full proof

- **3a.** The entry and exit kills as definitions, with their algebra:
  - the context invariants they keep (`CtxWF`, `NameWF`, `DomTy`, `DomMode`, `FreshOK`);
  - idempotence against later kills on the same roots;
  - the AGORA-933 witness: after the entry kill `s2` is dead and `vv` is live.

  No rule changes.
- **3b, part 1 (done: `A2/RegionMem.lean`).** What a region reaches:
  - `ViewAddr` (the buffer addresses of the views a value stores);
  - `RegionNode`, `RegionLanded` and `RegionViewAt` (as `RootNode`, `Landed` and `ViewAt`, with "the node at an address of `D`" for the root's node);
  - the entry fact `ViewsOK.region_viewAt`: an argument's valid views are valid through its region;
  - `ViewsOK.region_node`, `RegionNode.unique` and `RegionLanded.comp`/`mono`.
- **3b, part 2 (done: `RegionLanded.landed`, `ViewsOK.region_landed`).**
  What lands through a region lands through the argument's own roots at the
  composed kind (`⟨r, comp a k⟩` for a held `⟨r, a⟩`). This opens a cheaper
  route for the invariant than the ghost store below. Only the *typing*
  needs the ghost region; the overkill is a typing problem. So `MInv` can be
  stated, unchanged, of the context in which each region dependency is
  replaced with kinds composed (`subD` today copies the argument's kinds
  verbatim, which is too coarse for `Lands`). `noRegion` stays, and `Mem`
  and `Step` need no instrumentation. 3c then carries the invariant over
  that substituted context while the typing keeps the ghost binding. That
  route is tried first; the ghost store is the fallback.
- **3c, part 1 (done: `subDc`, `LandedR.subDc`/`_list`).** The
  kinds-composed substitution, and its transfer: with each region read as
  its addresses (`LandedR`), what lands through a dependency, or through one
  of a list as `ValOK`/`ViewsOK` ask, lands through its substitution.
  This is the per-dependency step of carrying `MInv` over the substituted
  context.
- **3c, part 2 (done: `comp_assoc`, `subDc_comp`, `subDc_derive`).**
  Deriving a borrow commutes with the substitution, so the substituted
  context's derived borrows are those of the substituted entries. The rest
  of 3c is the steps whose post-context is not a pointwise image: a change
  through a borrow that reaches a region kills on the ghost binding, which
  in the substituted world is no kill on a root. There the invariant needs
  the stability facts: the owners' trees stay well-formed, the arguments'
  views of the region's own buffers stay valid, and nothing else live
  reaches inside.
- **3c, part 3 (done: `Repl.keeps_enclosing`, `DataAt.keeps_enclosing`,
  `RegionViewAt.keeps_len`).** The first stability fact. A change through a
  borrow rewrites one node of its owner's tree. Strictly inside a region's
  node, that node keeps its address and its length. So an argument's view
  of the region's buffer stays in bounds while the body changes an element's
  inside.
- **3c, part 4 (done: `Repl.keeps_enclosing'`, `RegionViewAt.keep_inner`,
  `thruPre_live_nohit`).** The other two stability facts.
  - An argument's view of a region's buffer survives a change strictly
    inside the region's node, the node still well-formed (`DSH_repl_wf`).
    A region node in another slot or a payload is untouched.
  - After the entry kill, no live frame binding but the arguments depends,
    by a kind a drop ends, on a root the arguments hold views of.

  What remains of 3c is the wiring: the lift of a regioned parameter as a
  ghost binding, `RSetup.A` without the roots reached only through regions,
  `StmtT.ren`'s edit cases through a region-reaching borrow, and the call
  case of preservation over the `subDc`-substituted context.
- **What is left, in order (as of 3c part 4).**
  1. *The ghost lift is today's lift with a wider renaming.* Map each region
     `π p` to a fresh caller index `G p` (`ρ`), set `isPi` to nothing, and
     drop from `R` the roots reached only through regions. Then a region is
     an ordinary renamed root, `subD` is the identity, and `S.R = []` holds
     for a call whose arguments hold views only through regions. The ghost
     setup's `σ` must be empty too. `RSetup.OK.σ_sub` asks
     `S.σ v ⊆ allKinds S.R`, and today's `callS.σ` maps a parameter to the
     roots its argument holds, which are no longer in `R`. The real
     region-to-caller mapping is kept apart, for `subDc` (item 4) and the
     exit substitution (`callRes`). This setup does **not** meet
     `RSetup.AbsOK` as it stands. Its fourth clause reads
     `E.mode = .region ↔ S.isPi v = true` (`A2/Rename.lean`, `AbsOK`), and
     `StmtT.ren` asks `AbsOK Γa`. The other choice, keeping `isPi` true at
     region indices, breaks `StmtT.ren`'s `∀ v ∈ s.vars, S.isPi v = false`
     for no statement, since the body names no region. But it keeps `subD`
     substituting, which is what the ghost lift must not do. **Chosen
     resolution:** an `RSetup.ghost` flag (default `false`, so every
     existing setup and proof is unchanged).
     - Under `ghost`, `AbsOK`'s fourth clause reads "a region's index is
       renamed to a caller binding of mode `.region`": `isPi v = false`,
       and `S.Φ (S.ρ v)` is a region entry.
     - The lemmas that use the clause take the `ghost = false` case as
       today: `AbsOK.notPi`, `notPiFresh`, `ne_region`, and their users in
       `Rename.lean` and `Call.lean`.
     - In the `ghost` case, a region is an ordinary renamed root, so the
       lift lemmas need no region case there.

     With that, `StmtT.ren` types the body where the call places it, with
     the region a binding of mode `.region` in the caller's context.
     *Done, refined (`RSetup.isReg`):* `AbsOK`'s fourth clause now reads
     `E.mode = .region ↔ S.isReg v = true`, with region indices recorded
     whether or not they are substituted. A sixth clause reads
     `S.isPi v = (S.isReg v && !S.ghost)`. So "the statement names no region"
     can be stated as `isReg v = false`, which keeps its meaning under
     `ghost`. The next step moves `StmtT.ren`'s `∀ v ∈ s.vars, S.isPi v =
     false` to `isReg` and drops `S.ghost = false`. `AbsOK.exitScope` and
     `liftX_under(D)` already take `isReg`, through `AbsOK.notReg_of_notPi`
     for now.

     *Done:* `StmtT.ren`'s premise is `∀ v ∈ s.vars, S.isReg v = false`
     (`CallH.typedIn` gives it by `callS_isReg_lt`). Its uses that need
     `isPi` go through `AbsOK.notPi_of_notReg`, which holds with or without
     `ghost`. So a statement setting a body variable `x` knows that `x`'s
     entry is no region (`AbsOK`'s fourth clause). That is what the
     region-is-dead clause needs at `setE'`.

     *Done: `S.ghost = false` is gone.* `StmtT.ren` holds for every
     setting, ghost or not:
     - AbsOK's fourth clause adds `E.mode = .region → E.ty = .int`, which
       every step keeps, since it keeps a binding's type. With it,
       `liftE_weaker` needs no "not a region": a region binding never takes
       the fresh branch. A region-is-*dead* clause would not have worked,
       because `StmtT.panic`'s post-context has arbitrary liveness.
     - `callR_canon` now concludes that every root the lifted inner call's
       arguments hold views of is a region binding, which is `CallT`'s
       premise. Substituted, there is none (as before). Lifted as a ghost
       binding, it is `G p`, a `.region` entry of the caller's context.

     So the body of a call whose setting lifts regions as ghost bindings
     types where the call places it.

     *Done (`RSetup.ghostify`, `OK.ghostify`, `AbsOK.ghostify`,
     `StmtT.ren_ghost`):* any call setting can be made ghost: regions
     renamed, nothing substituted, and only a part `R'` of its roots frozen.
     The result is a setting (`RSetup.OK`) and keeps its contexts' fitness
     (`AbsOK`). So the renaming lemma places a callee body under it. The
     only new obligation is `pe_held`: what a borrowed parameter's caller
     entry holds must be of `R'` or by name. A lent argument holding views
     of a root left out of `R'`, as AGORA-933's `f1`'s `vv` does, fails it.
     That is item 3's lent-parameter region, needed for `f1`. A call whose
     view-holding arguments all go to regioned (`sink`/`inout`) parameters
     needs nothing more. What is left is the call site: a
     ghost setting for a call that passes real views (`R` without the
     region-reached roots), and the invariant over the `subDc` context
     (item 4).

     *Earlier, structurally:* `RSetup.ghost` exists, and `AbsOK`'s fourth clause
     reads `E.mode = .region ∧ S.ghost = false ↔ S.isPi v = true`.
     `AbsOK.ghost_notPi` holds. `StmtT.ren`, `callT_ren`, `liftX_up`,
     `liftX_blk`, `callR_canon` and `canon_weaker_sub` take `S.ghost = false`
     for now, and every existing setup meets it (`rfl`). The next step proves
     their ghost cases and drops that premise.
  2. *The callee's own rule.* `ThruOK` asks each root of a change's path to
     be live and to allow the effect (`canDo`: `own` or `inout`). A region
     (`regionE`: never live) fails it. So AGORA-933's grower `f` is not
     typed even in its own frame. The relaxation, a region root allowed
     where no share is on the way, is a typing-rule change that is sound
     only with the call-site premise. It lands with 3d, with a
     `fnOK_mono`-style lemma showing that what typed before still types.
  3. *Regions for lent parameters.* `f1` takes `vv` lent (`.inp`), and only
     `sink`/`inout` parameters get a region (`regioned`). Extending
     `regioned` changes `sigCtx` (as turn-on 1 did). The lift of a lent
     parameter changes as well: `liftE`'s `.rootb` branch returns the
     caller's entry `S.pe` and drops the parameter's own `held`. A regioned
     lent parameter's `held` holds `⟨π p, .view⟩` (`regionP`), so the
     `.rootb` lift has to carry that dependency, as `⟨G p, .view⟩`, or the
     witness loses its ghost dependency (see the first open question
     below). `AbsOK`'s first clause changes with it. It asks a `.rootb`
     binding for `held = (if E.ty.hasFn then S.sym else [])`, which becomes
     that list followed by the region's `⟨π p, .view⟩` for a regioned lent
     parameter. The lift lemmas of `.rootb` bindings (`liftE`'s first
     branch, `canon` of a parameter) are then re-proved with that
     dependency. This also lands with 3d.
  4. *The invariant over the `subDc` context.* Preservation of the call
     with `MInv m (subDc Γg)`. Steps that commute with the substitution
     (`subDc_derive`; kills on callee bindings, which no `σ` names)
     transfer as they are. A change through a region-reaching borrow uses
     `RegionViewAt.keep_inner` for the arguments, `thruPre_live_nohit` for
     the frame, and `DSH_repl_wf` for the owners.
  5. *3d.* `CallT`'s premise, `callPost`'s exit kill, `call_alone_refused`
     becoming a typing witness, and the CLAIM row.
- **3b, part 3 (fallback).** The ghost store: `RegionSnap`, building on `Region.lean`'s
  `Val.viewsOf`/`regionSnap`; `StepI`; the erasure lemma; and `MInvI`
  extending `MInv` with the region clause. Existing `MInv` lemmas stay
  untouched; only region-aware ones take `g`.
- **3c.** The lift with ghost regions behind an `RSetup` flag: `liftE`/`canon`
  map `π p ↦ G p`, the lent-parameter region, and `StmtT.ren` with real
  `Rj`. This is the bulk: `A2/Rename.lean`, `A2/Call.lean`, `A2/CallMem.lean`
  and `A2/CallInv.lean`.
- **3d.** Turn it on:
  - `CallT`'s premise and `callPost` change;
  - `call_alone_refused` becomes a typing witness, with `s2` dead after the call;
  - the CLAIM's "Not typed yet" entry goes;
  - `fnOK_mono`-style lemmas show every program typed before is typed after.

## A depth-aware effect, needed before items 2, 3 and 5

A probe on main 50f28c57 (agora #4290) showed that AGORA-933's `f1` cannot
be typed with today's effects, even in its own frame.
- A lent parameter is always live (`MInv.rootbLive`) and anchored
  (`sigCtx_anch`).
- With a region, `vv` holds `⟨π p, .view⟩`.
- `f1`'s grow through an element of `vv`'s slice is an edit through a
  borrow that reaches the region at kind `.inner`. Its effect on the region
  is `.drop` (`Edit.effAt`), and `Eff.kills .drop _ .view = true`, so the
  edit ends `vv`, against `rootbLive`.
- At run time `vv`'s view of `w`'s buffer stays valid: only an element's
  inside moves (`RegionViewAt.keep_inner`).

A2's effects have no depth, so the calculus needs one that says "strictly
inside the elements". There are two ways.

1. **A new effect `Eff.dropIn`.** It ends `.inner` and `.share` borrows,
   and leaves `.view`, `.self` and names alone. An edit through a borrow
   whose dependency on a root is `.inner` has that effect there
   (`Edit.effAt`). Its cost is the order on effects:
   - `Eff.kills_mono` needs `e.le b → kills e ⊆ kills b`;
   - `dropIn` and `realloc` kill incomparable sets (`{inner, share}` vs.
     `{view, self/hv}`), so `Eff.le` can no longer be a rank (`Eff.rank`,
     7 uses) and becomes a partial order (inclusion of kills; done:
     `Eff.leb`);
   - `canDo` (14 files), the `inout` bounds and every `Eff` case split
     (41 files) are touched, and each bound check is re-proved.
2. **Two roots per region.** `π p` is the viewed buffer, and `π' p` is the
   inside of its elements. A borrow read strictly inside an element depends
   on `π' p`, not on `π p` at `.inner`. A change there is any effect on
   `π' p`, which does not touch `vv`'s `⟨π p, .view⟩`. Its cost:
   - `Eff` is untouched;
   - `derive` (or the element-read rules, `RhsT.at`/`sat`) must switch root
     for the inner part, and their lifts and `subD` follow;
   - two region indices per parameter (`isRegionIdx`, `sigCtx`, `σ`);
   - replacing or dropping an element through `π p` (a `.drop` there) must
     also end what depends on `π' p`, the inside of the element it
     replaced. Either such an edit has an effect on both roots, or a
     borrow inside an element keeps a dependency on `π p` too. Option 1
     gets this for free: `dropIn` and `drop` both end `.inner` borrows of
     the one root.

   This is more local, but it changes how borrows are derived, which every
   rule reads.

Recommendation: (1). It is the cause, a missing depth in the effect
semantics, rather than a second root that encodes it. It also lets the
frame's `sw` (a view of `w`'s own buffer) and the argument `vv` stay live
after the call in A2, as they do in nurlc. The coarse `.drop` in the entry
and exit kills (`thruPre`) then becomes `dropIn` on roots reached through
`.view`. The work comes first, as its own change with full proofs: no rule
uses `dropIn` yet, and `Eff.le` keeps every existing inequality.

### Done: option 1 (`Eff.dropIn`)

It landed as a change of its own, with full proofs (`formal/rules/t937-dropin.md`).
Building it turned up a point the analysis above missed:

- **`.inner` does not always mean strictly inside the elements.** A field of
  an owned struct is lent `⟨y, .inner⟩` (`projDeps`), but it lies at the
  struct's top. A push through it changes the field's length, and a borrow
  of the whole struct holds `⟨y, .view⟩` (`rootKind`). So `dropIn` can be
  sound only where the root's node is its only top part: a `Vec` root.
  `Edit.effAt` therefore takes a fourth argument, whether the root's type
  is a `Vec` (`Edit.inEff`, `Ty.isVec`), and any other root keeps `.drop`
  (`DropInWitness.struct_root_drops`).
- **The soundness proof** is `MInv.edit_dropE`. `.dropIn` there needs two
  keeps:
  - `VKeep ⟨o, .view⟩` (`vkeep_view_below`): the root's node keeps its
    address and length when the rewrite is below it;
  - `HKeep ⟨o, .view⟩`, which is `HKeep ⟨o, .self⟩` (`HKeep.view_of_self`),
    since `Lands .view` and `Lands .self` are the same condition.
- **Where the elements hold views** (`EditBV`, `TakeB`), `.dropIn` ends what
  `.drop` ends (`kill_dropIn_true`), so those proofs are unchanged.
- **`Eff.le`** is `Eff.leb`, inclusion of kills. `Eff.kills_mono` still
  holds, and the order on the old four effects is unchanged.

### Done: item 2 (lent-parameter regions)

`regioned` now covers lent parameters (`formal/rules/t937-lent-regions.md`).
The four Call.lean proofs the probe broke were symptoms of three things:

- **Anchoring.** A lent parameter's non-name dependency had to have its root
  in `F`, the frozen roots. A region is not frozen: item 3 must allow a
  change through it. So typing asks `RootbAnchR` instead (`AnchoredIn`:
  in `F`, or a `.view` of a `.region` binding), and a kill spares such a view
  when its target is no region (`RegionSpared`, `killE_rootbR`). Every kill
  typing makes is of a binding that owns its slot, so each site proves it
  from the rule's own mode premise. Frames bind no region, so they keep
  `RootbAnch`; the conversion `RootbAnchR.toAnch` runs one way only.
- **The lift of a lent parameter.** `liftE` replaces a `.rootb` entry with
  the argument's own (`S.pe`), which already holds what the parameter views.
  So `canon_param` adds `σ` for `sink`/`inout` regioned parameters only
  (`PMode.isInp`).
- **`AbsOK` clause 1.** A lent entry's held may start with views of regions
  (`RegViews`). The lemmas that lift a kill (`hits_lift` … `canon_killHv`)
  ask `S.isReg x = false`. That is not the same as `isPi x = false` in a
  ghost setting, which substitutes no region.

Witnesses: every one whose lent parameter holds views now sees its region.
AGORA-909's own example (`ParamViewWitness`) still types its store as an
`edit false`.

### Done: item 3 (a change through a region)

`formal/rules/t937-thru-region.md`. Item 3 turned out separable from 3d after
all. `editB`/`takeB` ask `ThruOKR`: a root may be a region whose effect ends no
view. With `Entry.rvec` that effect is `.dropIn` (#2161). Placing such a change
where the call puts it has two cases:

- **A ghost region** stays a region, so the lift is exact.
  `canon_kill'` allows a region kill that ends no view.
- **A substituted region** stands for nothing. The change is an `edit true`,
  placed by a call that passes no views, so σ = []. The region drops out of the
  lifted path. `editB`'s nonempty-path premise was unused and is gone.
  The callee's kill on the region only weakens its context
  (`weaker_kill_region`), and the call's context is stronger
  (`canon_weaker_sub`, `StmtT.sub`).

Witness: `A2/RegionChangeWitness.lean`.

### 3d groundwork: the call's lift is precise and composes kinds

A call's setting (`callS.σ`) used to stand a region for `allKinds` of the
roots its argument holds, every root at every kind, and the lift (`subD`)
copied those kinds verbatim. It now stands a region for the argument's own
memory dependencies, plus each root by its handle (`⟨r, .self⟩`, so that a
composed kind covers every way, `RSetup.OK.σ_self`). The lift composes kinds
(`RSetup.subD` is `subDc`'s map, `mem_subD` gives `σC`). `derive_subE` then
holds by `comp_assoc`, with no closure of σ under kinds (`σ_kinds` is gone).
No rule changes. This is what `subDc_hits_exact` below needs of σ.

### 3d route (2026-11-22): no frozen roots; the substituted lift is exact

Since item 2 (`regioned` is `holdsView` in every mode), a call reaches every
root in `callR` through a region. The argument's type is the parameter's,
and a value whose type holds no views stores none. So `callS.R`, and with
it the `allKinds R` part of `RSetup.A`, over-approximates what the regions
now track exactly. That over-approximation is what makes the substituted
(non-ghost) lift overkill:
- `heldA` adds `S.A` to every lifted entry that is not held-fresh;
- `allKinds` holds `.inner` and `.share`;
- so the caller's `.dropIn` on a region-reached root `w` would end every
  such entry, which the callee keeps.

The route that needs no split invariant (typing context with ghost regions
vs `MInv` over the substituted one):
1. `RSetup.OK.σ_sub` (`σ ⊆ allKinds R`) becomes a frame clause: σ's roots
   are frame roots, which is what `σ_frame` derives today. `pe_held` admits
   `d ∈ S.σ u` for a region `u` (a lent argument holding views holds what
   its region stands for).
2. `callS.R := []`. Every `S.R = []` premise is then met by every call, and
   `σ_nil_of_R` goes. The edit cases of `StmtT.ren` that used it (a change
   through a region placed by a call that passed no views) become the real
   3d proof:
   - the caller's change on `w` is a `.dropIn` at `⟨w, .inner⟩`, the only
     kind a ThruOKR region path has;
   - it hits the lifted callee entries exactly (`subDc_hits_exact`);
   - it hits no frame entry, which is the entry kill (`thruPre`), as
     `N_mut`'s last clause is for names.
3. `CallT`'s premise: an argument to a through-changing call holds real
   roots only at `.view`, each a live owned `Vec` root not in `F`; plus the
   exit kill.

Why `A` must shrink, not only `heldA`: a callee's own view-holding local
`z` (say a `Vec` of slices of the region's buffer) is lifted with `held ⊇
S.A` (`ownHeld`, `heldA_own`). `allKinds R` holds `⟨w, .inner⟩`, so the
caller's `.dropIn` on `w` would end `z`. The callee keeps `z`, since its
own `⟨π p, .view⟩` is no `.dropIn` hit, and so does memory
(`RegionViewAt.keep_inner`). The over-approximation itself, not the lift's
kinds, is the overkill. Closing a precise list under composition gives
`allKinds` back (`comp .self k = k`), so the bound `held ⊆ rds ρ held ++ S.A`
(`held_lift` and about 125 uses of `S.A` in `Rename.lean`) has to become
"…, or what a region stands for, composed" (`σC`), a predicate rather than
a list.

Measured on 3896bd20:
- `RSetup.A := S.N` breaks 9 sites in `Rename.lean`, plus `pe_held`;
- `heldA := N` instead breaks about 80 (`heldA_own` is used through
  `liftE`'s equations), so step 1 changes `A`/`R`, not `heldA`.

### 3d groundwork: what the kinds-composed lift kills (`A2/SubDcKill.lean`)

For 3d, a call passes an argument that views real memory `w`, so σ ≠ [], and
the call must place the callee's change through the region. The verbatim
lift (`subD`) reaches `w` at the argument's own `.view`, so it is a `.drop`
there. That ends the argument's view, which the callee keeps
(`verbatim_overkills`), so neither equality nor weakening places it.

The kinds-composed lift (`subDc`) reaches `w` at `comp a .inner = .inner`,
which is a `.dropIn`.

- For an argument at `a = .view` (its slices view `w`'s own buffer), the
  caller's kill on `w` hits exactly the entries the callee's kill on the
  region hits (`dropIn_comp_exact`, `subDc_hits_exact`).
- For `a = .inner` (it views something inside `w`) it does not: A2's kinds
  have one level of depth (`dropIn_comp_inner_overkills`). The 3d premise
  must refuse such arguments to a through-changing call, or the kinds need
  another level.

**What item 3 needed from item 1.** A region root's binding has type
`.int` (`regionE`, `AbsOK` clause 4), so `Ty.isVec` is false there, and
`f1`'s change through `vv`'s slice still gives `π p` the effect `.drop`.
Item 3 must give a region root `.dropIn` when what it stands for is a
`Vec`'s buffer. That is sound for regions by `RegionViewAt.keep_inner`,
whose region nodes are `DataAt` nodes, so always nodes. The likely form is
an `rvec` read off the parameter's type, or `E.mode = .region` with the
parameter's type a `Vec` of views.

## Open questions for review

1. Does lifting a lent parameter's region keep `liftE`'s `.rootb` case's
   other duties (the caller's `pe`, `rootbLive`)? Or should a lent parameter
   holding views become a `.bor` binding of its argument in the lift?
2. Is the entry kill better stated on the combined context at `callMem` time
   (`CallH.minv`), or as a `CallPre` context the call steps through?
3. ~~Is a depth-aware `.drop` worth adding before 3d?~~ Yes; it is needed,
   not just more precise (`MInv.rootbLive`), and it is done (`Eff.dropIn`, above).
