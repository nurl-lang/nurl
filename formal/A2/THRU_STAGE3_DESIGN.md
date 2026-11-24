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
memory dependencies (at first plus each root by its handle, `σ_self`, which
a precise `recvRes` made unnecessary: see below). The lift composes kinds
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
   exit kill. `subDc_hits_exact` takes a region whose σ has one root `w`.
   An argument holding views of several roots changes each of them
   (`⟨π p, .inner⟩` lifts to `⟨wᵢ, .inner⟩` for every `i`). So either the
   premise asks for one root per argument, or the lemma is generalised to
   each root `wᵢ` with σ filtered to `wᵢ`. Entries with `.view`/`.self`
   deps on a `wⱼ`, `j ≠ i`, are not hit by the kill on `wᵢ` either way.
   The generalisation is preferred: it adds no ceremony for the author. *Done:*
   `subDc_hits_exact_root` (for each root an argument views) and
   `subDc_hits_none_root` (another region, whose argument does not reach
   `w`, is not hit by the kill on `w`).
   The premise must also ask that no *other* argument reaches a root `w`
   that the changed region's argument views. Otherwise the callee's change
   through `π p₁` lifts to a kill on `w` that also hits entries resting on
   a second region `π p₂` whose argument views `w`. That is a real alias
   the callee cannot see, so the kill is not an overkill to argue away but
   the reason to refuse. AGORA-933's `f1(vv)` passes one argument, so the
   premise is met there.

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

*Done: a parameter holds its region by its handle.* `regionP` adds
`⟨π p, .self⟩`, not `⟨π p, .view⟩`. The lift composes kinds, so the
region's dependency reaches each of the argument's own dependencies in
the argument's own way (`comp a .self = a`). With `.view`, an argument's
`.self` came back as a `.view`, so a lent parameter's caller entry (`pe`)
was not covered by its region, substituted. That was one of the two
reasons the lift lemmas needed `S.A`'s `allKinds R`. A kill spares a handle
wherever it spares a view (`Eff.kills_self_of_view`), so `RegionSpared` is
unchanged. `RegViews` and `RegionView` now ask for `.self`.

Measured on 3896bd20:
- `RSetup.A := S.N` breaks 9 sites in `Rename.lean`, plus `pe_held`;
- `heldA := N` instead breaks about 80 (`heldA_own` is used through
  `liftE`'s equations), so step 1 changes `A`/`R`, not `heldA`.

### 3d groundwork: a precise `recvRes`, and σ exactly the argument's

A call through a package returned `allKinds (recvRoots c Ec)`: every kind
of every root the package reaches. To lift that, σ had to reach each root
by its handle too (`σ_self`), and those extra `⟨r, .self⟩` entries are not
harmless at a lent parameter's exit. `kills .realloc true .self` holds but
`.inner` does not, so a caller's result resting on `⟨r, .inner⟩` would die
on a push to `r`. The exit (`exitsP`, `callPost`) reroots onto the
argument's own entry (`pe`), so the lift must give that back exactly.

`recvRes` now adds `recvDeps c Ec`: each memory dependency of the
receiver, composed with every kind (`⟨r, comp a k⟩`). That is what the
package's environment reaches anyway (`deps_open`'s `comp d'.kind k`, and
a share of each root, `comp a .share = .share`). The rule is more precise,
and its lift is exact by `comp_assoc` (`allKinds_recvRoots_subE`). So
`σ_self` and the `.self` entries are gone: a region stands for exactly the
argument's memory dependencies. nurlc is unchanged, and it is at most as
permissive as the model.

### 3d: a change inside a region's elements, where the call places it

With the frozen split, the lift of a change through a region is exact:
- `hits_subE_region`: the caller's `.dropIn` on a root `r` that the
  region `u` stands for hits a lifted, substituted callee binding exactly
  where the callee's `.dropIn` on `u` hits it.
- `canon_kill_region`: so the callee's kill on `u`, placed, is the caller's
  kill on `r`.
- `dtorSafe_region`: and no binding that may run a destructor views `r`
  where the change ends it (`hitsMem_dropIn`: a `.dropIn` ends no name).

The premises are what 3d's call rule will ask:
- σ of `u` is at `.view` or `.self`;
- no other region stands for anything of `r`;
- nothing the lift adds is on `r` in memory (`r` is not frozen);
- a lent argument reaches `r` only at a view or its handle;
- no frame binding is hit (the call's entry kill).

*Done: the rename places it.*
- `RSetup.ThruReady` collects the premises above, plus "the call freezes
  nothing" (`Rf = []`, so a non-fresh borrow's lifted path, which adds
  `S.A`, adds only names).
- `canon_kill_region_all` / `canon_killNames_region`: the callee's changes
  inside its regions' elements are the caller's on every root they stand
  for. Several roots of one region kill the same bindings; kills commute
  and are idempotent (`killNames_congr`).
- `mem_memDeps_subE_liftE_bor`: what a lifted borrow's path reaches in
  memory, a region's standing for its roots, composed.
- `editB_ren_facts_thru` / `editB_ren_thru`: a change through a region
  whose argument views real memory, where the call places it. `ThruOKR`
  at each root holds by `dtorSafe_region`. The post-context is weaker than
  the callee's placed one: exact on regions standing for roots, a
  weakening on regions standing for nothing.
- `StmtT.ren` now takes `s.Thru P → S.ThruOrReady P s`: the call passes no
  views (`S.R = []`), or it is `ThruReady` and the statement calls no
  through-changing function. `editB` and `takeB` place a change either
  way. `editBV`/`takeBV` and the lift ask only that the call freeze
  nothing.

What is left: `CallT`'s premise, so that a call gives `ThruReady`, then the
exit kill and the witness.

### 3d: what a call must give for `ThruReady`, and what stands in its way

`callS.Φ` is the post-context (`callPost`). So the frame the body runs in
already carries the call's kills, and one kill serves as both entry and
exit kill: a `dropIn` (hv `false`) on each real root `w` that a regioned
argument views, when the callee changes through a borrow
(`fn.body.hasThru`; `ThruOrReady` already excludes through-changing calls
inside). Such a kill spares `.view`, `.self` and names, so the arguments
(views of `w`'s buffer) stay live. Every binding live after it is unhit
(`killHv_live_nohit`), which is `ThruReady`'s frame clause. That clause is
now stated on live bindings only. A destructor's memory is a separate
clause (`DtorSafe … .dropIn false w`, a premise), because the kill ends
bindings but leaves their `dtor`.

`ThruReady` asks for `w ∉ Fc`, and today's model makes that impossible:

1. `zN` freezes every frame binding but the `inout` arguments and the
   roots closures name, so `w ∈ Fc`.
2. A lent parameter's anchors are frozen (`Anchored`, `StmtT.rbind`,
   `WrapCond`, `pe_Fc`), `held` included. A regioned parameter's lift holds
   `⟨w, .view⟩`, so `w` must be frozen.
3. Frozen means unchanged: `rootKeep_frame` keeps a lent parameter's node
   because the frozen owners' slots do not change (`hF`). And
   `killE_rootb` gets from the root being unfrozen that no kill ends a lent
   parameter (`MInv.kill_pin`).

Two routes:

- **U, unfreeze `w`.** Leave `w` out of `zN`, and let the held views of a
  `Vec`-typed lent parameter anchor at an unfrozen root. `ValOK.href`
  lands a lent `Vec`'s node through its path, which names the frozen
  argument. Every kill site of every rule then has to show that it ends no
  lent parameter, since an unfrozen root can be killed by any rule.
- **F, a frozen root may change strictly inside its elements.** `ThruOK`'s
  `d.root ∉ F` becomes "`d.root ∉ F`, or the change at `d.root` is a
  `dropIn` and hits no lent parameter". `Anchored`, `zN`, `WrapCond` and
  `pe_Fc` stay as they are. Existing derivations take the first disjunct.
  The new obligations fall only on the change through a borrow:
  - `MInv.kill_norootb`, `MInv.killNames_norootb` (done): the kill keeps
    the invariant when it ends no lent parameter, frozen root or not;
  - a frozen owner's slot changes strictly inside its elements. A lent
    parameter that lands in that tree depends on it only at kinds such a
    change spares (`.view`, `.self`, names). Its node keeps its address and
    length (`Repl.keeps_enclosing`). The views into it stay in bounds
    (`RegionViewAt.keeps_len`, `keep_inner`). So `rootKeep_frame` holds with
    `hF` weakened to "unchanged, or changed strictly inside, sparing every
    loan".

**F was taken first**, because its obligations stay local; it is set aside below (`CatchOK`). In the rename, `w ∈ Fc`
(`zN`), and `ThruReady`'s `e.root ∉ Fc` becomes "the caller's `F` does not
hold `w`, and no lent binding of the placed context is hit by a `dropIn` on
`w`". The lifted lent parameters reach `w` only at `.view`/`.self`/names
(the premise, and σ's `comp .view .self = .view`). The frame's own lent
parameters are anchored in the caller's `F`, which `w` is not in.

**Route F, memory side (done).** These need no rule change:
- `rootb_anchor_ne` / `rootKeep_frame_ne`: where no lent parameter reaches
  `x` by its path, nor (but for a `Vec`, `bor_lands_vec`) by what it holds,
  every lent parameter's node lies in a frozen owner other than `x`, or in a
  live block's payload (kept by `BlkLe`), so a frozen `x` may change. The
  premise is on every lent parameter, so a chain of them through one
  another never reaches `x` either;
- `MInv.change_ne` (with `keep_notx_ne`, `root_namer_ne`, `namer_ne`,
  `PkgKeep.of_edit_ne`/`of_repl_ne`, `NewSlot.edit_ne`): `MInv.change` with
  a frozen `x` that the change ends no loan of (`hnr`);
- `MInv.edit_dropE_ne`: an owner's tree changed by a drop or strictly inside
  its elements, owner frozen;
- `MInv.killNames_mixed`: kills each at an unfrozen root by an effect below
  `replace`, or ending no loan (an unfrozen `replace` still has to show the
  latter).

**What blocks the rule change: `Frz`.** `preserve` concludes `Frz F m m'`:
every frozen slot is unchanged across a step. Its users are the
`recover` frame (`catchOK`: the frame's slots against the store `m0` it
remembers), the call frames (`CallH.frz`, `Closure`), and `frozen`. Route F's
`ThruOK` (`FrozenOK`: "`∉ F`, or a `dropIn` with `LentAway`", for a borrow
whose elements hold no views, so `editBV` stays unfrozen) builds through
`EditB`, `EditBV` and `TakeB` (branch `t937-frozenok-wip`). It stops at
`Preservation`, where `Frz` is proved from `x ∉ F`. Before it can land, one
of two things has to happen:
- `Frz` weakens to "unchanged, or (for a root changed inside) the same top
  node address and length". Then `catchOK`, `CallH.frz` and `frozen` must be
  re-proved against the weaker form.
- Or the frozen set `F` of the judgement is split: `F` for slots that stay
  unchanged, and a set the call places for roots changed only inside, which
  `zN` leaves out of `F`. That is route U's unfreezing, with its kill-site
  obligation confined to the new set.

**Finding: route F cannot be a generic rule.** `CatchOK` (`catchR`) asks
that every slot outside the inner statement's spine equals the remembered
store `m0`'s, and a `recover` freezes `range m0.nv`. A `ThruOK` that lets a
frozen root change inside (`FrozenOK`) cannot tell a root a `recover`
froze from one a call lent. So `catchR` preservation would fail for an
inner statement that changes such a root. That such a statement is never
reached does not help, since preservation is proved for every typed
statement. The memory lemmas above stay useful for route U.

**Route U, taken.** `zN` leaves out the real roots the regioned arguments
view, so `w ∉ Fc`. This is consistent with `Frz` and `CatchOK`, because a
`recover` inside the callee still freezes `w`. Two things change:

1. **Anchors.** A `Vec`-typed lent parameter's `held` may anchor at an
   unfrozen root, at `.view`/`.self`. Its path anchors stay frozen, and its
   node lands through its path in a frozen owner other than `w`
   (`bor_lands_vec`, `rootKeep_frame_ne`).
2. **Kill sites.** A kill at a root that some lent parameter holds views of
   (`LentHeld Γ r`, a root unfrozen and held at `.view`/`.self`) must end
   no loan. Each kill site then shows "no lent parameter hit"
   (`MInv.kill_norootb`) in place of `killE_rootb`. How each kind of kill
   site meets this is below: by `Inv` clauses, not by new rule premises.

**How the kill sites are met.** A rule premise is needed
only where the statement decides it. Elsewhere an `Inv` clause on the
statement's variables does it:

- *Named kills* (`assign`, a move, scope exit, a call's `sink`/`inout`
  argument) kill a variable of the statement. Clause: a `LentHeld` root is
  no variable of the statement. When the call is placed, the statement is
  the renamed body, whose variables are the callee's (`≥ base`, or
  `inout` arguments). `w` is neither.
- *Edits through a borrow* go through a variable of the statement.
  Clause: such a variable, a live `Vec`-typed borrow, depends on a
  `LentHeld` root only at `.inner`. Then `Edit.effAt` there is `dropIn`
  (`inEff .inner true`; a push is `realloc` only at `.self`). The derived
  borrows keep `.inner` (`borrow`, `vec_at`, `slice_at`, `fst`/`snd`: what
  derives from `.inner` stays `.inner`). A slice read from a regioned
  parameter's element (`vec_at q i` is `.bor` with `q`'s held as its path,
  `⟨w, .view⟩`) is no `Vec`, so nothing edits through it.
- *`editBV`* kills with `hv` = the root's type holds views (`killThruV`),
  and a `dropIn` with `hv` ends `.view`/`.self`. So the call asks that `w`'s
  elements hold no views (`¬ (argE Γ w).ty.holdsView`), and `editBV` never
  reaches a `LentHeld` root.
- *`killNames`*: closures that change a `LentHeld` root by name. The call
  asks `w ∉ roots (mutNames Γ args)`, which `zN` already reads, and
  closures made inside the callee name its own bindings.

So `ThruOK` needs no new premise. The `Inv` clauses carry it, and the
call establishes them (`CallInv`).

**PR A (done): the memory lemmas allow held anchors.** Where the statement
runs, the anchors stay strict (`Anchored`, `RootbAnchF`: `Inv.anch`,
`StmtT.rbind`, `WrapCond`, `StmtT.catchR`), so no rule changes. The lemmas
that `MInv` rests on assume the relaxed `RootbAnch` (`AnchoredH`: in `F`, or
a `HeldAnch`, a lent `Vec`'s held `.view`/`.self`, not on its path):
- `rootb_anchor` reads a lent slot's node through a dependency that is no held
  anchor (`bor_lands_anch`), so the frozen owner it finds is unchanged;
- every kill a memory lemma makes spares the held anchors at its root
  (`HeldSpared`): `killE_rootb`, `MInv.change`, `kill_pin`, `kill_more`,
  `killNames_more`/`_mixed`, `killHv_more`, `edit_dropE`/`_grow`/`_dropV`/
  `_growV`;
- a named kill takes `NoHeld` (no held anchor at the binding) and a change
  through a borrow `ThruSpared` (for `editBV`, `NoHeld` at its roots);
- `Preservation`, `Progress`, `CallMem`, `CallInv` and `EnvHand` supply them
  from the strict anchors at the leaf and `x ∉ F` (`NoHeld.of_anchF`,
  `ThruSpared.of_anchF`, `RootbAnchF.of_rootb`).

**PR B1 (done): the change through a borrow says it ends no lent view.**
`ThruOK`/`ThruOKR` gain `HeldOK` (the effect at each root, `hv = false`,
spares every `.view`/`.self` a lent parameter holds there). The rename
carries it (`HeldOK.canon`: a lifted parameter's held is the callee's,
renamed; the frame's are spared by the `inout` bound, `Φsat`), and a region
image gets it free (`dropIn`). Preservation now takes `ThruSpared` from the
typing (`ThruOK.spared`), not from the strict anchors, so PR B2 needs no
`Vec`-paths clause: the edits are covered by the rule.

PR B2 relaxes `Inv.anch` to `HeldAnch` at a root that is no variable of the
statement, which gives the named kills `NoHeld`. PR B3 makes the call that
sets them up (`zN`, `CallThruOK`, the exit kill, `CallInv`).

**PR B2, in progress (branch `t937-b2-wip`): how far the relaxation reaches.**
Done so far:
- **The clause.** `Inv.anch` is `AnchoredS Γ E F s.vars`. An anchor is in `F`, or it is a `HeldAnch` whose root is none of the statement's variables and whose type holds no views (`∃ Er, Γ r = some Er ∧ Er.ty.holdsView = false`).
- **Why the type part.** `editBV` kills each root at `hv` = its type holds views (`killThruV`), so it needs `NoHeld` only at those roots (`NoHeldV`). At the others the rule's `HeldOK` spares the held anchors (`HeldSpared.of_thru`). A held root's type holds no views, so `NoHeldV` follows from the clause (`NoHeldV.of_anchS`). The call establishes it in B3 from `CallThruOK`'s "`w`'s elements hold no views".
- **Transport.**
  - `AnchoredS.anti`: fewer variables.
  - `AnchoredS.extend` / `setE_none`: a fresh binding. A held root is bound, so it is not the new one.
  - `AnchoredS.of_ty` / `of_tyV`: the types kept, or kept outside `V` (the unwind, `Stmt.spine_sub_vars`).
  - `AnchoredS.union`: `seqL`, through `Keep`.
- **Kills in the context.** These take the relaxed R-form (`RootbAnchRH`: in `F`, a region view, or a `HeldAnch`) and a `HeldSpared` at the killed root:
  - `killE_rootbRH`;
  - `CtxRel.killH`, `movedH`, `killNamesH`, `killHvH`, `editBH`, `editBVH`, `editBV_truncH`;
  - `PushArg` / `EditArg.ctxRelH`.

  At a named root, `HeldSpared` comes from `NoHeld.of_anchS`. At a root changed through a borrow, it comes from the rule (`HeldSpared.of_heldOK`, `of_thru`). The strict forms are derived from them (`HeldSpared.of_anchR`).
- **The unwind lemmas** (`rootb_anchor_sp`, `rootKeep_frame_sp`) take `AnchoredH`, as PR A's `rootb_anchor` does.

**Finding: two more consumers of strict anchors run at a leaf.**
- **`SrcCase`** (`StmtT.ctxRel`, SrcKeep): a source body's typing, walked with `RootbAnchR`. It is used by `withLock` and `withElem`.
- **A call's `CallA.anch`.** `post_rootb`, and the frame setup in `CallMem` / `CallInv`, read it strictly. Inside a route-U callee's body, the lifted parameter holds a held anchor at `w`, and a nested call there needs a `CallA` all the same.

Both need the relaxed premise:
- the R-form, plus held roots none of the statement's variables, with their types (an `AnchoredS` with regions);
- every kill site they walk kills a variable of the statement (`NoHeld`) or a root through a borrow (`HeldOK`);
- a call's arguments are variables of the statement, so `post_rootb` holds.

For `CallA` this moves into B3's design: the frame setup must place the outer frame's held anchors (unfrozen `w`, not the callee's variable) in the new frame's rename.

**Finding 2: `s.vars` is the wrong set for the clause.** A step can bring a variable into the statement that was none of its variables before, and is not fresh:
- `callc` places a closure's body together with its captured names (`cs.map (·.1)`, in `heldFor` and the body's rename). A closure that captures `w` for reading, called inside a route-U body, makes `w` a variable of the statement. Nothing kills it there: the frame freezes the captured names (`frozen (heldFor …)`), so inside it `w ∈ F`.
- `catchR` (`catchIn`): the inner invariant has `F ++ range m0.nv`. An outer held root below `m0.nv` is frozen inside, and nothing says the body names it not.

So "a held root is no variable of the statement" does not survive a step, even where no kill of `w` is possible. The set must be the names the statement can kill: its variables outside the frames that put them in `F`. A `Stmt.killVars` would leave out a `frozen z k`'s `z`, a `catchR`'s frozen range, and what a placed frame freezes. Inside such a frame the anchor is in `F`, and outside it the root is no killable name. Then:
- the per-step obligation is "a step's new killable names are old ones or fresh (`≥ m.nv`)" (`Step.killVars_sub`), proved over `Step`'s 67 rules;
- a call's renamed body names the callee's variables (`≥ base`) or `inout` arguments, which are old killable names.

The work on `t937-b2-wip` stands with `V` swapped from `s.vars` to `s.killVars`:
- the transport lemmas, the H variants of the kill lemmas, `NoHeldV` and the type part;
- the Preservation cases fixed so far.

`Stmt.spine_sub_vars` becomes `spine_sub_killVars`: a running scope is killable.

**Done (2b745946b).** `Stmt.killVars` is `Stmt.vars` without a `frozen` frame's list, and `Inv.anch` is now `AnchoredS Γ E F s.killVars`. The lemmas and the Preservation cases above are moved onto it, and `respine` takes the killable-name subset by a default tactic.

**Finding 3: the step lemma needs an invariant on closures.** `frozenIn` and `catchIn` need a step's new killable names to be old ones or fresh (`≥ m.nv`). Every rule but the closure calls gives that:
- a named call renames the callee's variables to `≥ base`, and its `inout` parameters to their arguments, which are killable names of the `letcall`;
- `reap` and the frame setups bind fresh variables.

`callc` renames the closure's `inout` captures (`cs.map (·.1)` with an `inout` mode) to the captured names themselves. These are killable now (the closure may assign them), and they were no names of the statement before. So the clause needs an invariant that no closure a binding of the statement names captures a held root `inout`: in `Γ`, no binding in `s.killVars` holds a mutating name dependency on a held root. This is B3's `w ∉ roots (mutNames Γ args)` at the call, carried as an invariant:
- a new mutating name dependency on `w` is made only by a closure literal that captures `w`, which names `w`, which the clause forbids;
- dependencies flow by copy and move, which keeps the roots.

This makes B2's last two cases depend on B3's invariant. The order is therefore:
1. the closure-capture clause (`Inv` field, preserved, and established at the call with `CallThruOK`);
2. `Step.killVars_sub` with that clause for `callc` / `callcE`;
3. `frozenIn` and `catchR`;
4. `SrcCase` relaxed (`withLock`, `withElem`);
5. the call side (`CallA`, CallMem, CallInv), with the rest of B3.

**Open design question for the closure-capture clause.** Folding it into `AnchoredS` (for the held disjunct: no `q ∈ V` holds a mutating name dependency on the root) needs no new `Inv` field. But every transport would then have to keep the name dependencies of the statement's bindings, not only their types. `Inv.weaker` breaks that: `EntryWeaker.live` lets a weaker entry hold more (`E.held ⊆ E'.held`), so the clause may fail in the typing while nothing changes at run time. The candidates:
1. state it over what the run-time value of `q` may change: a package's `inout` captures, `cs` with a mutating mode. Then it is a fact of the store (`m`), kept by `MInv`-style lemmas, and weakening does not touch it;
2. state it over the context before weakening: `Inv` would carry the strict context;
3. forbid weakening to add mutating name dependencies, a restriction of `EntryWeaker`.

(1) is the closest to what `callc` reads (`m.st c = some ⟨o, some (.pkg … cs)⟩`), and the call establishes it from `CallThruOK`'s `w ∉ roots (mutNames Γ args)` together with the package invariant that a package's captures are its entry's name dependencies.

**B2 and B3 are complete (2026-11-23).** The library has no `sorry`, and every theorem `Check.lean` prints depends only on `propext`, `Classical.choice` and `Quot.sound`.
- **The invariant:** a borrowed parameter's held views may be anchored outside `F` at roots none of the statement's killable names (`AnchoredS`). The store holds no package that captures such a root other than read-only (`HeldCapsInp`, `CapsInpAt`, slots and blocks).
- **Every step keeps both:** `Step.killVars_sub` and `CapInout.not_held` (claude-expert), CapsStore (claude-accurate), `EvalR.capsInp`, and `Step.slotsCaps`.
- **The call side:**
  - `CallA.anch` is `RootbAnchRS`;
  - `NamesFree`'s new conjunct says closures' by-name changes spare held views;
  - the call frames set up the clause from the caller's.
- **Source typing:** `StmtT.ctxRelS`.

What follows is the record of the work as it went.

**Where the WIP branch stands (2026-11-23).** With every proof file moved onto the relaxed anchors, the whole library builds. The places still open are marked `sorry -- WIP scaffold (AGORA-937 B2, never merged)`, so the gaps are an exact list. Nothing is merged while any is there.
- **The closure-capture clause (AGORA-963), 7 places:**
  - Preservation's `frozenIn` and `catchR`;
  - Closure.lean: the closure call's frame, the kill at the captures, and the new statement;
  - EnvHand.lean: the anchors the package-call lemmas take, two places.
- *(Proved since: `SrcCase` takes `RootbAnchRS Γ F s.killVars`, and SrcKeep's `StmtT.ctxRelS` keeps the borrowed parameters on the relaxed anchors.*
  - *Every name a source statement kills is a killable name that is no region, so no held root (`RootbAnchRS.noHeld`). That is what the `…H` kills ask (`HeldSpared`).*
  - *A changed `Vec`'s path roots hold views, so they are no held root either (`NoHeldV.of_anchRS`).*
  - *The `NoHeld` callbacks of `PushArg` / `EditArg` / `editBH` / `editBVH` take a no-region premise: a callee frame's region may carry held self-views, and only the `move` case asks.*
  - *The strict `StmtT.ctxRel` stays as a corollary for a callee's body. Its R-only helpers in SrcKeep had no other users and are gone.)*

**The closure-capture clause in the invariant (2026-11-23).**
- `Inv.heldCaps : HeldCapsInp m Γ F s` is the clause (claude-expert's, CapClause.lean; its definition sits in Invariant.lean ahead of `Inv`).
- With it, Preservation's `frozenIn` and `catchR` are proved by `Step.held_not_killVars`.
- What is left:
  - **AGORA-963 step 3, preservation of the clause:** every `Inv` a step builds is marked `WIP scaffold (AGORA-963 step 3, …): HeldCapsInp across this step`. `grep -rn "AGORA-963 step 3" formal/` lists them: 33 sites in Preservation, EnvHand, Closure and CallInv. The positional constructions go through `Inv.mk₀ hcaps …`, and `Inv.ofLeaf` takes the clause first.
  - **Proved already:** the sites where the store's slots, the borrowed parameters and the spine carry over (`HeldCapsInp.of_st / respine / of_rootb / mono`): the sweeps, `Inv.weaker`, `Inv.clean`, `Inv.respine`, the `…In` lemmas, A3's `Nid` and spawn, and the empty store.
  - *(Proved since: the 5 call-side places.*
    - *At the closure call, an outer held root is at most a read capture (the clause). Then the opened call lends it (`H`): it is no moved argument (`capPos_any`), and no root of `mutNames`, since `NamesFree` makes every argument reach a changed root by its bound. Otherwise it is none of the call's names.*
    - *After the call it is none of the new statement's killable names, and a frame binding of the same type (`postdt`).*
    - *The hand-over lemmas take `RootbAnch` plus `NoHeld` at the receiver and the arguments, and `rootb_namesH` spares held views by `NamesFree`.)*
- **What is left is exactly AGORA-963 step 3's 30 sites.**
- *(Proved since, B3's call side: `CallA.anch` is `RootbAnchRS Γ F args`. An anchor is in `F`, through a region, or held of a root that is no argument and holds no views.*
  - *`NamesFree` asks that the closures' by-name change ends no held view. That is the call-site twin of 963's clause, in the spare form `HeldSpared` reads.*
  - *`namesFree_lift` carries it into the lifted frame from `S.OK` as it stands, with no new field (`liftE_rootb_held_mem`, `Φsat`, `N_mut`).*
  - *`post_rootb` uses it at `mutNames`' roots, and at a moved or changed argument the held root is no argument.*
  - *The outer anchors after the call is placed come from the `letcall`'s own `Inv` (`killVars_callIn`, `postdt`).)*
- *(Proved since: `StmtT.catchR`'s anchor premise is now `RootbAnchS Δ F [x]`. It is used only at the frame's end, where `catchR x m0 skip`'s one killable name is `x`. At the recursive call's setup it follows from the outer anchors, because `x` is a killable name of `letrec x f k`.)*
- *(Proved since: EnvHand.lean's two "carry the anchors to the package call's new statement". The new killable names are the old ones, or the fresh `m.nv` / `m.nv + 1`, which Γ does not bind.)*

**The call side (B3): what `CallA.anch` is used for.** Four uses (2026-11-23), and all but one are met by the relaxed clause:
1. **`CallA.post_rootb` (Call.lean).** The call's context change leaves every borrowed parameter's entry as it was. At a moved or changed argument, a held root is impossible: an argument is a killable name of the `letcall` / `callc`, and the clause keeps held roots out of those. At the roots of `mutNames Γ args` (what an argument closure may change by name), the clause says nothing. **This is the one use that needs AGORA-963's fact**, in its typing form: no held root is a root of `mutNames Γ args`.
2. **CallInv.lean:257.** The new `Inv`'s anchors for an outer borrowed parameter after the call is placed. The renamed body's killable names are `≥ base` or `inout` arguments (`Step.killVars_sub`'s call case), and an outer held root is none of them. So the relaxed clause carries over (transport: `of_ty` / `extend`).
3. **CallInv.lean:540 (`recCase`).** It only enlarges `F` (`.mono`).
4. **CallMem.lean:568/573.** An argument's copy at entry (`rhs_pres`) asks `NoHeld` at the argument, a killable name, so the relaxed clause suffices.

So `CallA.anch` can become the relaxed R-form with the held clause over `s.killVars`, plus a premise for (1). That premise is the call-site twin of 963's store-level clause: `w ∉ roots (mutNames Γ args)` for each held root `w`, the same condition `CallThruOK` asks at a route-U call. **The two must be proved to agree.** A package's captures are its entry's name dependencies (`MInv.held`, `NamesIn`), so the store-level clause gives the typing-level one on the strict context. Weakening (`StmtT.sub`) can only add name dependencies, so the premise is asked of the context at the call, before weakening, as `CallT`'s other premises are.

The premise of the call (`CallThruOK`) narrows too (finding above): other
arguments reach `w` only by name. A `.self` path (a borrow `&w` passed
beside `vv`) would let the callee view inside `w`'s elements through a
parameter whose dependencies are not on the region.

Then `CallThruOK` (the `CallT` premise) holds the following, each stated
on the caller. Each root `w` below is a root that a regioned argument's
memory reaches.
- nothing frozen (`argMemF = []`);
- each regioned argument's memory a `.view`/`.self` of a live owned `Vec`,
  no argument and not in `F`;
- `w`'s elements hold no views (`(argE Γ w).ty = .vec t` with
  `t.holdsView = false`), so no `editBV` kill (`hv`) ends a loan of `w`;
- no two regioned arguments on one root;
- every other argument reaches `w` only by name, and the regioned argument
  only through its `held` (σ);
- `w ∉ roots (mutNames Γ args)`;
- `DtorSafe (callPost …) .dropIn false w`.

`CallInv` derives the two `Inv` clauses at the call from these:
- `w` is no variable of the renamed body (`w < base`, and `w` is no
  `inout` argument, since it is no argument);
- the body's `Vec`-typed borrows are its own, so at entry they are the
  lifted parameters. A regioned parameter reaches `w` only in its `held`,
  and every other parameter only by name.

### 3d groundwork: frozen roots split from region-reached ones

A call setting now tells apart what it freezes from what its regions stand
for:
- `RSetup.A := compAll S.Rf ++ S.N` is what a lift adds;
- `RSetup.B := compAll S.Rd ++ S.N` is everything the arguments hold, used
  as the bound where a region's memory comes back through the substitution
  (`mem_subD_A`, `mem_subE_vdeps_A`, `B_out`, `B_root`).

For a call, `Rf := argMemF Γ fn.params args`: only what arguments to
parameters with no region hold in memory. A regioned parameter's argument
memory comes back through its region. So a change through a region no
longer meets the over-approximation in what the lift adds.

The bounds the lift lemmas need for the inner call's argument deps, result
and `inout` arguments are now stated after the substitution
(`argDeps_lift`, `heldOfArgs_lift`, `outHeld_lift`:
`… ⊆ (rds ρ … ++ S.A).flatMap S.subD`, with `flatMap_liftS`, `app_liftS`,
`mem_subD_comp`). `callRes_lift` and `callPostAux_lift` compare substituted
entries directly.

A lent parameter's lift keeps only its argument's names when the parameter
has a region (`RSetup.peReg`). `pe_held` admits a memory dependency of such
a parameter's argument. At call entry, a moved or changed parameter's tree
holds what its region stands for (`σmap_mem`, `slot_ownArg`), and its
package freedom is proved through its argument's (`own_param_free`, now via
`cleanDeps_back` and `MInv.pkgFree`, no longer via a share the lift added).

### 3d groundwork: a precise call result and a precise `RSetup.A`

A call's result held `allKinds (callR …)`: every kind of every root the
arguments hold. The lift of an inner call needed `⟨r, .self⟩` for a root a
region reaches, which σ (precise since `recvRes`) no longer gives, and the
call's exit needed what the lift adds (`S.A`) to be among it. Both are now
precise. `heldOfArgs` is `compAll (argMem Γ args) ++ argNames Γ args`:
each memory dependency of an argument composed with every kind
(`compAll`). `RSetup.A` is `compAll S.Rd ++ S.N`, where `Rd` is what the
arguments hold in memory (`Rd_sub`: on `R`, no name; `σ_Rd`: σ is among
it; callS sets `Rd := argMem Γ args`). `compAll` is closed under composing
with a memory way (`compAll_comp`, `comp_assoc`), so every lift lemma keeps
its shape. This is the precise `A` the 3d split of frozen and
region-reached roots needs.

**Correction to the route above.** A call does not reach every `callR` root
through a region. An argument of a type that holds no views may still carry
memory dependencies the callee does not track (`ValOK.pair` passes `P ++ H`
down to the parts). So 3d splits the roots instead of dropping them: those
of arguments to regioned parameters (σ) and the frozen rest (`Rd` of those
arguments only). The CallT premise then refuses a change through a region
that reaches a frozen root.

### 3d groundwork: a lent parameter's lift holds the callee's memory

A lent parameter used to be lifted to its argument's entry (`S.pe`), and
with that came the argument's own memory dependencies. A lift lemma bounds
those only through `S.A`'s `allKinds R`, which is the over-approximation
3d removes. Now the `.rootb` lift keeps the argument's path, but its held
is the callee's own memory dependencies, renamed (its region, by its
handle). If it has none, the argument's held is kept; otherwise the
argument's names are kept (`liftE`). Substituted, the region gives back
exactly the argument's memory (`comp a .self = a`, σ precise since the
precise `recvRes`). So where the call places the callee, a lent parameter
is its argument's entry, dependency for dependency (`canon_inp_eq`). This
needs `typedDeps` to list memory first, then names, and the lent
parameter's exit (`WrapCond`, `exitsP`, `callPost`) is then unchanged.

- `liftE_rootb_dep` / `liftE_rootb_ρ` give what a lifted lent parameter
  depends on: the argument's, or its own region by its handle.
- `subE_liftE_fix` asks a lent parameter's held to be on no region
  (`hEb`).
- `canon_param` holds in every mode, and `canon_lend` (unused) is gone.
- `canon_rbq` takes the context's `AbsOK`.

No rule changes: `typedDeps` only reorders, and the lift is proof
machinery.

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

## B4, the turn-on (in progress, branch `wip/t937-b4`)

**Done on the branch:**
- **The call rule.** `CallThruOK` (Typing.lean) is the second branch of `CallT`'s `ThruFn` premise: the call passes views of real memory `w` that the callee changes only inside its elements.
- **No exit kill.** Weakening ends a caller binding such as `s2`, a view inside `w`'s elements, before the call (`EntryWeaker.live`). A dead binding is never read again, so A2 accepts what nurlc does, and `callPost` is unchanged.
- **The frame.** `zN` leaves out `thruW`, the roots the callee changes inside.
- **The anchors.**
  - `StmtT.rbind` takes `AnchoredS Γ E F (p :: s.killVars)`.
  - `WrapCond .inp` takes `AnchoredS … V`.
  - `StmtT.keepKV` keeps such a root bound.
  - `CallH.held_anch` shows that the lifted lent parameter's view of `w` is a `HeldAnch`.
- **The rename.** `CallH.thruReady`: the call sets the body up ready for a change through its regions (`ThruReady`).

**What is left: the closure-capture clause must be frame-relative.**

`HeldCapsInp` asks for `CapsInpAt m w` over the whole store, for the held anchors of borrowed parameters outside the running scopes, at roots outside `F`. A running `rbind`'s own parameter is in the spine, so it is skipped. `Inv.rbindIn` then needs the clause for it.

The clause cannot be stated at the outer level as it stands:
- There, `F` lacks the frozen part `z'` the typing chose. The runtime `frozen z` (`zOf`) contains the changed root `w` too.
- So no condition on `F` tells `w` from a frozen root `w'`.
- A live caller closure that captures `w'` inout is legal and unreachable from the callee. It makes the store-wide `CapsInpAt m w'` false.

The clause must therefore speak of what the frame can reach:
- bindings at or above the frame's base;
- the call's `inout` arguments;
- closed under names held: what an argument's closures capture by name, transitively. A lent closure that reads a closure `x` which changes `w` would otherwise let the callee change `w` through `x`.

Stated this way, the clause holds for frozen roots as well: a frozen root is no root of `mutNames`, and the callee names none of the caller's bindings. So the clause needs neither the spine exclusion nor the `∉ F` condition.

**Preservation:**
- A step inside the frame binds only fresh variables, at or above `m.nv`, which is at or above the base.
- It writes only reached slots, from values it read there (`EvalR.capsInp`, restricted to the reach).
- A nested frame's base is at or above the outer one's.
- `rbindSkip` removes the parameter.

**Refined, after `CapsOK` and `MInv.noPkg` (github#2268):**
- **No transitive capture problem.** A binding captured by name holds nothing (`CapsOK`: `Ev.held = []`), and its type holds no views. By `noPkg`, every package in its slot captures nothing by name, so it cannot carry an inout capture of `w` into the frame.
- **The call can establish the store clause.** At a route-U call, `CapsInpAt m w` over the whole store follows from three things:
  - `noPkg` for bindings whose type has no closure, dead ones included;
  - `MInv.held` with `NamesIn` for live closures;
  - `CallThruOK`'s "closure-typed bindings are live and change `w` by no name".

  Blocks need nothing.
- **Left: the spine.** A running `rbind`'s parameter `p` is in the spine at every level above it. There, `F` does not show whether `p`'s held anchor is a changed root `w` or a frozen root `w'`. The typing's frozen part `z'` lives only in the derivation, and the runtime `frozen z` (`zOf`) contains both roots.

**Direction for the spine: make the runtime frozen list informative.**
- `Step.letcall` builds `frozen z` with `z` = `zOf` minus, when `fn.body.hasThru`, every slot whose tree holds a node that an argument's value views (`ViewAddr`, `DataAt`).
- `frozen z` is ghost: no step reads `z`. So no behaviour changes, and for every call typed today nothing is removed (`callR = []`, so no argument holds views).
- `z' ⊆ z` still holds for the typing. `zN` drops `thruW`, and the correspondence lemma shows that `thruW` is the set of removed slots.
- The spine clause then reads, at an `rbind` under `frozen z`: "a held anchor at a root outside `F ++ z` has `CapsInpAt`". A frozen `w'` is in `z`, so the clause is vacuous for it. A changed `w` is not in `z`, so the clause applies, and the call establishes it as above.
- `Inv.rbindIn` moves to the typing's `F ++ z'`. A root in `z` but not in `z'` is a root of `mutNames`, which by `NamesFree` no argument but a closure reaches, so it is no held anchor.

**Correction: the informative runtime list does not work.** The runtime cannot match the typing:
- `thruW` is the roots an argument *may* view (`callR`). An argument whose value holds no views at run time, such as an empty `Vec` of slices, removes nothing from the runtime `z`.
- `w` then stays in `z` while the typing has freed it (`zN` drops `thruW`).
- Inside the frame, under `F ++ zN`, the clause still asks `CapsInpAt m w`, and the outer level gives nothing for it.

**What remains: a frame-relative store clause.** For a borrowed parameter `p` of the frame based at `b`, with held anchor `w`: every slot at or above `b` holds `ValCapsInp · w`, and so do the slots of the call's `inout` arguments and every block. This is true for frozen roots too, because a caller closure that captures `w'` is below `b`. What the frame reads elsewhere is harmless:
- A captured name holds nothing (`CapsOK`), and by `noPkg` its packages capture nothing by name.
- A view lands in a root whose type holds no views. So that type has no closures (`hasFn → holdsView`), and by `noPkg` its packages capture nothing by name.
- A borrow of a closure part holds its names, so an inout capture of `w` would make `w` a root of `mutNames`, which `CallThruOK` excludes.

The proof work is `EvalR.capsInp` restated for that clause. A read below `b`, outside the `inout` arguments, needs the typing facts above, carried as `MInv`-level facts. Then comes the preservation of the new `Inv` field over every step, as for `heldCaps` in B2.

**Two scaffolds discharged (8eac5d2e1):**
- `CallThruOK` takes no closure argument. A call through a package, whose receiver is a closure, therefore stays on the regions-only branch. `CallT.clean` and the package call's `.resolve_right` then follow by contradiction.
- Route U for closure arguments is later work. Until then A2 types fewer such calls than nurlc accepts, which is no hole.

**The two left share one cause.**
- `Inv.rbindIn` needs the spine clause (above).
- Rename's lifted `CallThruOK` needs, in the placed context, "every closure-typed binding is live". The outer frames' bindings are there too, and nothing is known of them.

The liveness clause exists only to let the call establish the store-wide `CapsInpAt`. With the frame-relative clause:
- the clause is not needed: a dead caller closure lies below the frame's base and is never read by it;
- so it can go from `CallThruOK`;
- the lift then needs only what the renaming keeps.

So the next piece of work is the frame-relative clause, and the clause's removal from `CallThruOK`.

**The frame-relative clause, as lemmas (plan).** `EvalR.capsInp` reads three kinds of place:
- slots of the right-hand side's variables;
- nodes found through a borrow or a view (`SlotsCaps.vecOf` / `.dataAt`), which can lie in any slot's tree;
- blocks, which are already free (`MInv.rdCapsInp`).

So the clause is "every slot is safe except a set `D`": `CapsExcept m w D := (∀ x ∉ D, ∀ o V, m.st x = some ⟨o, some V⟩ → ValCapsInp V w) ∧ blocks`.
- At a route-U call, `D` is the caller's dead closure-typed slots.
- Every other slot is safe at entry:
  - `noPkg` covers types without closures;
  - `NamesIn` covers live closures, with `CallThruOK`'s "no mutating name on `w`";
  - `w`'s own tree has no closures, since its type holds no views.

The steps inside the frame keep it:
- **Writes** go to slots at or above the base, or to `inout` arguments. Both are live, so neither is in `D`.
- **Reads** never touch `D`:
  - the statement's variables are callee variables, `inout` arguments, or captured names, and captured names are live (`CapsOK`);
  - nodes reached through a borrow or view lie in a root the reaching entry depends on (`Landed` / `RootNode`);
  - a live entry's roots are bound root-mode entries (`CtxWF.live`). Dead closure roots are needed here: a live view of a closure's environment would have to be ended when the closure died. That is the one fact still to check.

Lemmas:
1. `EvalR.capsExcept`: `EvalR.capsInp` with `SlotsCaps` replaced by `CapsExcept` and a premise that the evaluation reads outside `D` (`EvalR.ReadsOut m r D`).
2. `RhsT.readsOut`: a typed right-hand side, under `MInv`, reads outside the dead slots.
3. `Step.capsExcept`, the twin of `Step.slotsCaps`.
4. `Inv.heldCaps` restated with `∃ D`, all members dead closure-typed slots below the frame. The spine exclusion and `∉ F` go.
5. Remove `CallThruOK`'s "closure-typed bindings live", then discharge the two scaffolds.

**Rejected: "NamesIn for dead entries too".** The idea:
- `MInv.held` would cover dead entries as well.
- `StmtT.rbind` would ask that no entry holds a mutating name on its held anchors.
- `Inv.rbindIn` would then derive `CapsInpAt` directly.

It fails because `Entry.clean` drops a dead entry's dependencies on purpose (`held := memDeps …` or `[]`), and the package call builds its `MInv` over `cleanC Γ`. Making it work would mean changing `clean`, about 170 `EntryWeaker` constructions and 87 uses of `MInv.held`. `CapsExcept`, above, is the route.

**What the lift needs, and the two candidate invariants.**

Rename's lifted `CallThruOK` fails only on "every closure-typed binding is live", because outer frames may hold dead closures. Those closures cannot capture the callee's own `w`, which is fresh at the callee's entry. Showing that takes a store fact, from one of two candidates.

- **(i) `CapsExcept`, above.** Its read lemma must be typing-aware:
  - A dead binding killed in place keeps its slot, and a live view may still depend on it, since `CtxWF.live` does not ask the root to be live.
  - So a read can land in a dead struct's `Vec`. Its elements are safe when their type has no closures (`WFv.no_pkg`). Otherwise they are a closure whose captures the dead owner's names once listed.
- **(ii) No forward captures.** A package in a slot below a frame's base captures none of that frame's variables:
  - A package is made inside the frame, from the frame's variables.
  - It leaves the frame only through an `inout` argument or the result, after the frame's variables die.
  - The exit checks have to be shown to refuse the `inout` case.

(ii) is closer to what the lift needs, and it is local to frames. (i) also covers the top-level call's dead closures. Next session: settle which one, by trying (ii)'s step lemma on `assign` to an `inout` argument first.

**(ii) checked on `assign` to an `inout` argument: it does not hold as stated.**
- A2 does not refuse a callee that assigns its `inout` parameter a closure capturing a callee local `w`. The assign rule asks only `x ∉ roots E.vdeps` and the modes.
- At the body's end, `exitScope w` kills the entry that names `w`. The caller's slot keeps the package, though: it is below the base and captures `w`.
- So (ii) has to exempt the call's `inout` arguments while the frame runs.
- It also needs the running frames' bases, which `Inv` does not carry. The spine gives the `rbind` parameters `base + j`, but not `base`.

With both, (ii) is a new `Inv` field with a preservation proof over every step, as large as (i).

Neither candidate is cheap. Choose by which consumers each serves:
- (i) serves the top-level call's dead closures and the lift. It needs a typing-aware read lemma.
- (ii) serves the lift only, and still needs the dead-closure clause at the top level.

So **(i) `CapsExcept` is the choice**, and (ii) is dropped.

**Refined: `CapsLive` (supersedes `CapsExcept`'s fixed `D`).** The set left out is simply the dead bindings:

    CapsLive m Γ w := ∀ v E o V, Γ v = some E → E.live → m.st v = some ⟨o, some V⟩ →
      ValCapsInp V w ∧ (every node a view or handle inside V points at is ValCapsInp · w)

plus blocks, which are free. The reasoning:
- **Weakening keeps it.** Weakening can only end bindings, and it does not touch the store.
- **The call can establish it from typing.** `MInv.held` (`NamesIn`) bounds a live value's package captures by its names, and what a live view reaches is named by its holder. So `CapsLive m Γ w` follows from "no LIVE entry holds a mutating name on `w`".
  - That clause replaces `CallThruOK`'s "closure-typed bindings live".
  - Unlike the old clause, it lifts: the outer frames' live entries depend only on bindings below the base.
- **The consumer** (`CapInout`) calls a package in slot `c` of a `callc`, and its typing makes `c` live (`callT_recv_live`). So `Step.held_not_killVars` takes the statement's typing.

What preservation needs is one typed read lemma: `RhsT` reads only live bindings' slots and the nodes their views and handles point at. Then come the `Preservation` sites, as for B2's `heldCaps`. This is the remaining work.

**Proved (A2/CapsLive.lean):** `MInv.liveCaps`. Where no live binding holds a mutating name on `w` (`NoMutLive`), no live slot holds a package capturing `w` but read-only. It follows from `NamesIn` (`MInv.held`) and `PkgsOK`, whose `inout` captures have a bound.
- What a borrowed `Vec` reaches is named too (`HrefAt` carries `NamesIn` of the node).
- A slice's elements hold no views (`Ty.ok`), so no closure with names either.

**Next:**
1. `Inv.liveCaps` (the field): `∀ w` held anchor root outside `F`, every live slot and every node its handles reach is `ValCapsInp · w`. It replaces `HeldCapsInp`. Weakening keeps it, since it only ends bindings.
2. `RhsT.liveCaps`: a typed right-hand side evaluated under it yields a `ValCapsInp` value, and leaves the store under it. It reads only live bindings and what they reach.
3. Its `Preservation` sites; `Step.held_not_killVars` from the typing (the called `c` is live); then the two scaffolds.

*Probe (2026-11-24): `RhsT.vars_live`, "every variable a typed rhs reads is live".* A generic tactic closes every `RhsT` case but nine: `at`, `sat`, `remove`, `expr`, `atomic`, `chanSend`, `lockRestore`, `pack` (captures, live by `CapsOK`) and `pair` (an intermediate context). The index expressions read integers, which need no clause. So the value lemma should go case by case, as `EvalR.capsInp` does, and take liveness from each `RhsT` premise only where a value that may hold packages is read.

*Progress (2026-11-24 late):* `LiveCaps` is defined. `RhsT.liveCapsVal` proves the value is `ValCapsInp` for every case that reads a live slot or a block. Eighteen cases are left:
- `at`, `sat`, `view`, `borrow`: the targets;
- `pop`, `remove`: children;
- `glob`, `rwRead`, `rwTry*`, `chanRecv`: leaves and payloads;
- `pair`, `inl`, `inr`, `pack`, and `arcNew` / `lockNew` / `cellNew`: recursive.

The recursive ones need the statement strengthened to "the value is `ValCapsInp`, and `LiveCaps m1 Γ1 w` holds after". A component's evaluation changes the store (a move empties its slot), and the next component reads in `Γ1`, as `EvalR.capsInp` does with `SlotsCaps`.

*Plan for the joint lemma `RhsT.liveCaps`:* the value is `ValCapsInp`, and `LiveCaps m1 Γ1 w` holds.
- **The store side.** `EvalR` changes only the read variable's slot: emptied (`moveOwn`, `takel`/`taker`), its node shrunk (`pop`, `remove`), or a fresh empty node (`take`). Each new tree's subtrees are the old one's, so both the values and the slot-located targets stay `ValCapsInp`.
- **The block side.** Block changes (`chanSend`/`Recv`, `lock*`) leave the slots alone, and nodes in blocks are clean by `MInv`. So `LiveCaps` speaks of slot-located targets only.
- **The context side.** It needs `RhsT`'s output to only end bindings, a `LiveLe Γ Γ1` for `RhsT`. Here `kill` is `LiveLe.kill`, and `setE … { live := false }` ends one.

*Correction (integration, 2026-11-24): `LiveCaps`'s target clauses must cover nested handles and views.*
- `lendOf` of a struct yields `pair (href c1) (href c2)`, and a later `fst` lifts the inner handle into a binding of its own. So the clause speaks of every `Sub (.href c) V` and `Sub (.view d o l) V`, not only the top.
- At the call this needs nested inversion lemmas:
  - `ValOK` for borrows: its `pair` / `pkg` / `dtor` constructors carry the handle's `HrefAt`, whose names are among `H` or `envDeps cs H`.
  - `ViewsOK` with `ViewIn` for owners, with "a slice inside a well-formed type holds no views".
- `LiveCaps.set`'s premise becomes "every nested target of the new value is clean". For a shrunk node it follows from the old node's clause.

Integration state (branch wip/t937-b4-int, 8158047b7):
- `HeldCapsInp` concludes `LiveCaps`.
- Ctx, Sweep, SweepD, CapsStore and CapClause are done. CapClause uses `Stmt.headCallc`, `CapInoutH` and `Step.killVars_subH`, and `held_not_killVars` takes the called slot live.
- Preservation has 50 errors, at the `heldCaps_step` callers and the set/remove/frozenIn/catchIn sites.

*Open sub-problem (nested targets at the call).*
- **Handles:** fine. `ValOK.href_sub`: a nested `href` carries `HrefAt` with names among `H` (`envDeps cs H ⊆ H`), and owned values hold no handle (`WFv`).
- **Views:** the target's elements must hold no closure with names, so the view's element type must hold no views. For a top-level view the binding's `Ty.ok` gives it. For a view nested in a package's environment, `ValOK.pkg` does not carry `te.ok`.
- **Candidates:**
  - an `MInv`-level fact "every view in memory has an element type that holds no views", made where views are made, from typed bindings;
  - `te.ok` from `PkgsOK` or `MemCodes`.

Next: check whether either already exists.

*Integration progress (2026-11-25):*
- **CapsLive.lean** also has `RhsT.liveCapsSet`, the combined `x := r`, and `LiveCaps.of_change` / `of_changeR`, the clause across slot changes. `of_changeR` asks two things:
  - a live changed value is clean, with no handle;
  - each node in a changed slot is clean, or is what an old node at the same handle became, clean if that one was.

  An edit's owner may be dead, so its whole tree need not be clean.
- **Preservation:** `letv`, `letd` and `assign` are done (42 errors left).
- **Next:** `Repl.nodesBack`, the node correspondence across a `Repl`, from `Repl.capsInp`. Then the edit, push, insert and `takeB` sites through `of_changeR`; then `unpair`, `reap`, `free`, the scope exits, the frames, and `frozenIn` / `catchIn` (`hlive`).

**Integration, 2026-11-25 (wip/t937-b4-int).** The whole tree builds on `LiveCaps`. Proved:
- the store and value lemmas (`CapsLive.lean`: `liveCapsSet`, `repl` / `editNode(H)`, `unpair`, `hand`, `panic_st`, `of_shrink`);
- every leaf step in Preservation;
- the call frame (`CallH.liveCaps`), the closure frames and the hand-overs;
- the catch frame, which now carries its end's clause (`StmtT.catchR`'s new premise).

Two scaffolds are left: `Inv.rbindIn` (the spine) and Rename's lifted `CallThruOK`.

**Finding: the frame exclusion (`d.root ∉ F`) cannot simply go.** The current branch drops it, so that `frozen` and `catchR` keep the clause from their inner step. With it gone, `Inv.rbindIn` must give the clause at a frozen anchor of the callee's borrowed parameter, and that is false. A counterexample:

- the caller holds a live closure `cl` that captures `r` inout;
- it calls `f(vv)` where `vv` views `r`, and `r` is frozen for the call.

The typing allows both live together: creating `cl` kills no viewer of `r`; the conflict is settled when `cl` runs. In `f`, `cl` is still live in the frame's context, so `LiveCaps r` fails. The frame exclusion is what makes this case vacuous.

**With the exclusion kept (wip/t937-b4-capskeep)**, `frozenIn` must carry the clause for the roots it freezes (`z' \ F`) through the inner step. Leaf steps do keep it: a frozen root is captured inout by no package (`CapsOK`), and `liveCapsVal` takes `w ∈ F`. Two places break it:

- **`catchP`:** the frame's end restores the start's store and context `Δ`. If the body killed a binding that captured `w` before the catch started, `Δ` revives it.
- **The catch frame's start:** it knows the clause only at its own frame, outside its `F`, which holds every older binding.

**What would close it:**
- either a frame-relative clause, over what the frame can reach (above), so a caller's unreachable `cl` does not count;
- or two catch-frame facts:
  - the body kills no binding older than the frame (every older binding is frozen there, and depends on frozen roots only), so `Δ`'s live bindings are live now;
  - its slots are the frame start's (`Frz`, `hsteq`).

  Then `catchP` keeps the clause for every root, and `frozenIn` takes it from a `CapsKeep` conjunct of `preserve`, as on wip/t937-b4-capskeep. This is the smaller step: one new `StmtT.catchR` fact ("no older binding dies"), kept by `catchIn` through a lemma that a step kills only bindings depending on an unfrozen root.

**Decision (owner, 2026-11-25): the frame-relative clause.** Plan:

*The clause.* For a borrowed parameter `p` with held anchor `w`: every live binding `v ≥ p` (the frame's later parameters, its body, the frames it opens) holds a value that meets `LiveGood m w`, and so does every live `inout` argument of `p`'s frame. A caller binding below the frame is not asked about, so the counterexample above (the caller's live `cl`) is out of scope. The clause needs neither the frame exclusion (`∉ F`) nor the spine exclusion: a running `rbind`'s parameter is asked about too, so `Inv.rbindIn` is the identity on it.

*Why `≥ p` suffices.*
- **The frame's earlier parameters** (`base ≤ v < p`): at a route-U call they hold no package (`CallThruOK` takes no closure argument). At an ordinary call, an argument that a package could make dirty for `w` holds a mutating name on `w` (`MInv.held`, `NamesIn`). Then `w` is a root of `mutNames`, and `NamesFree` forbids an argument viewing `w` with another bound. So no parameter is both.
- **The receiver of a call through a package** (`Stmt.headCallc`, what `CapInoutH` reads) is a body binding, so `≥ p`; or it is an `inout` argument, which is in the clause.

*Obligations.*
1. Define it (`FrameCaps m Γ p A w`, where `A` is the frame's `inout` arguments). The frame of `p` must be readable from the `Inv`: give `CallStmt`'s `frozen` frame the `inout` arguments, or carry `A` in the running `rbind`.
2. **The call** establishes it for each new parameter:
   - its slots are the arguments' values or what they lend (`BindParams.src`);
   - at a changed root `w`, `CallThruOK`'s `NoMutLive` with `MInv.liveCapsAll` gives it for the `inout` arguments;
   - at a frozen root, the `NamesFree` argument above.
3. **Each step** keeps it:
   - a fresh binding (`≥ m.nv ≥ p`) is given a value read from bindings the frame reaches, or a lent part of one: `liveCapsSet` restricted to the reach;
   - a read below `p` that is not an `inout` argument reaches a frozen view or a captured name, and by `noPkg` neither holds a package that captures by name.
4. **`catchP`**: the frame's end restores the start's slots and `Δ`, inside the catch frame. A binding of `Δ` at or above `p` was created inside `p`'s frame, under the clause, so it met it then. The catch frame carries its end's clause, as it does now (proved in `recCase`).
5. **The wrappers** (`frozen`, `catchR`) keep it from their inner step. It does not depend on `F`.

`CallH.liveCaps`, `LiveCaps.hand`, `editNode`, `unpair` and the rest of `CapsLive.lean` carry over once restricted to `v ≥ p ∨ v ∈ A`; their proofs read one binding at a time.

*Refinement: the frame is `F`.* `callIn`'s runtime `frozen z` is every caller variable but the `inout` arguments (`(List.range base).filter (∉ inoutArgs)`). So "the bindings the frame reaches" is "the bindings outside `F`". The clause becomes `LiveCaps` restricted to `v ∉ F`:

`FCaps m Γ F w := ∀ v E o V, Γ v = some E → E.live → v ∉ F → m.st v = some ⟨o, some V⟩ → LiveGood m w V`

- **No root exclusion.** The counterexample's `cl` is a caller binding, so it is in `F` inside the frame.
- **The spine:** a running `rbind`'s parameter is asked about too, at the `F` its frame runs under: `F ++ frozenAbove s p`, the runtime lists of the `frozen` wrappers on the spine above it.
- **`Inv.rbindIn`** moves to the typing's `F ++ z'`. The runtime list `z` contains `z'` and the changed roots, whose slots hold no package (data `Vec`s, `noPkg`). So the clause over `v ∉ F ++ z` gives it over `v ∉ F ++ z'`.
- **`frozenIn` and `catchIn`** keep it as follows:
  - a binding in the frame the wrapper adds is frozen through the inner step (`Frz`: its slot is unchanged), and is not revived;
  - outside that frame, the inner clause gives it.
- **The call** establishes it for its parameters' anchors over the parameters and the `inout` arguments: the arguments are clean by `NamesFree` at a frozen root, and by `CallThruOK`'s `NoMutLive` at a changed root.
- **`catchP`:** the catch frame's `F` is every older binding, so the restored `Δ` is asked about only at the frame's own bindings.

**Second look at the refinement (2026-11-25): the domain must be the anchor owner's frame, not the current `F`.**

A clause over `v ∉ F` with the *current* `F` shrinks as the frames nest. Inside an inner call `g`, an outer parameter `q`'s clause loses `q`'s own frame's bindings, which are frozen in `g`. After `g` they are asked for again, and a `catchP` inside `g` may have revived one, restoring a snapshot that no clause covered. This is the same wall as before.

The domain must be fixed per anchor owner `p`: `{v ∉ z_p}`, where `z_p` is the runtime frozen list of `p`'s own frame. That set is every binding from `p`'s frame's base up, and its `inout` arguments.
- It is the same at every depth, so a catch frame's snapshot taken deep inside is covered, and the catch frame's carried clause, proved in `recCase` from the `Inv` at hand, covers it.
- It excludes the counterexample's `cl`, which is in `z_p`.

What `Inv` lacks is `z_p` for a parameter outside the current spine. Options, in order of preference:
1. **Recover `z_p` from the context.** A borrowed parameter's entry is `callPe`: `path = derive a .self` on its argument `a`. Check whether `Inv` can keep, per running frame, a ghost map from each `rbind` parameter to its frame's list. The candidate is a new `Inv` field, `frames : ∀ p rootb, ∃ z, …`, set by the call and kept by every step: frozen lists never change.
2. **Thread the stack.** `Inv` at an inner level takes the enclosing frames' lists, as the wrappers peel them (`Inv.frozenIn` pushes `z`): `Inv m Γ F Z s`, where `Z : Var → List Var` gives each parameter's frame list. Every `Inv` construction site changes (large, mechanical).
3. Carry the frame list in the `rbind` statement: `rbind p z s`. This is a syntax change across A2/A3 (largest).

Whichever is chosen, the obligations above stand, with `v ∉ F` read as `v ∉ z_p`. Next session: start with option 1's feasibility.

**Option 1 checked (2026-11-25): an existential frame list is not enough.** An `Inv` field `∃ Z ⊆ F ++ s.frozenAt p, FCaps m Γ (∉ Z) d.root` is kept by the leaf steps, and `catchP` can restore the creation-time `Z`.

But `catchIn` must show the outer `Z` covers the post-state. A binding older than the catch frame lies in the catch's `F` and may be revived there. It was clean at the frame's start only for the `Z` chosen then. Nothing ties that choice to the `Z` chosen now.

So the list must be **canonical**: the runtime frozen lists of the frames above `p`, concatenated. That is option 2. `Inv` takes the map `Z : Var → List Var` of the outer frames' parameters, `Inv m Γ F Z s`:
- `preserve` keeps `Z` for the old parameters;
- `Inv.frozenIn` and `Inv.rbindIn` extend it;
- a catch frame's carried clause is stated at the `Z` of its start, which is the `Z` then, because `Z` is threaded.

This is a signature change at every `Inv` use: mechanical, large, multi-session. It is the next step.

**Option 2, the crux (2026-11-25).** Threading `Z` is mechanical, and it need not touch every `Inv` use: the clause can move out of `Inv` into a predicate `HeldZ m Γ Z s` that `preserve` takes and returns beside it. The hard part is the catch frame.

At `catchP` the post-state is the snapshot `m0` with the typing's end context `Δ`. The clause there is needed at the threaded `Z`: `FCaps (m0.set x) Δ (Z p) d.root`. That is the clause at the frame's start, at the same `Z`, which the start's step (`recCase`) knew.

It must be recorded where both sides meet:
- **`StmtT.catchR`** has `Δ` but no `Z`. `Z` belongs to no typing.
- **`HeldZ`** has `Z` but not `Δ`. Recording `∃ Γc, clause m0 Γc Z` leaves `Γc` unrelated to `Δ`.

Ways out, to weigh next session:
- **(a)** `catchR` carries the start's context in its syntax, `catchR x m0 Γ0 s`. It is a runtime-only form, so only its uses change. The typing then asks `Δ = setE Γ0 x _`, and `HeldZ` records `clause m0 Γ0 Z`.
- **(b)** `HeldZ`'s record is the liveness of `Δ` against the snapshot (`LiveBack Γc Δ`). That needs the "body kills no older binding" fact again.
- **(c)** Restrict A2: no `recover` frame inside a route-U frame. This is the coverage cut the owner did not choose.

(a) looks smallest and sound. The rest of the plan (`HeldZ`, the frame's domain `∉ z_p`, the call's `NamesFree` / `NoMutLive` argument) stands.

**(a) fails, and a memory-only clause makes it unnecessary (2026-11-25).** The `letrec` step knows no context, so a ghost `Γ0` in `catchR`'s syntax would be arbitrary.

But inside a frame the clause can range over **every slot of the frame's domain**, live or dead:

`FrameCaps m D w := ∀ v o V, v ∉ D → m.st v = some ⟨o, some V⟩ → LiveGood m w V`

Live-only was needed only for the caller's dead closures that a through call killed, and those lie outside the domain (`D = z_p`, below the frame).
- **At the call**, the domain is the fresh parameters, built from live arguments, and the `inout` arguments, which are live. Both are clean (`CallThruOK`'s `NoMutLive` with `liveCapsAll` at a changed root; `NamesFree` at a frozen one).
- **In the frame**, no code names `w` (it is a caller variable, and no `inout` argument aliases a viewed root, `CallA`). So no package capturing it inout is made. Values come from the domain, or from reads outside it, which are frozen views or captured names: package-free (`noPkg`), and blocks hold no names (`blkCapsInp`). Killing a binding makes nothing dirty.
- **`catchP`:** the clause is about memory only, so the catch frame's record needs no context. Keep `HeldZ`'s catch part as: for each running `catchR x m0 _`, for every borrowed parameter `p < m0.nv` of the current context, `FrameCaps (m0.set x) (Z p) d.root`. It is set at the frame's start from the clause then, and kept because old parameters' entries do not change (`KeepOut`, rootb entries) and `Z` is threaded. At `catchP` the post-state's store is the snapshot.

**Pieces:**
- `HeldZ m Γ Z s`:
  - the clause for each borrowed parameter outside the spine, at `Z p`;
  - the spine's parameters at `F ++ frozenAbove`;
  - the catch part;
  - "the running statement's variables avoid `Z p`", which gives the receivers of calls through a package (`CapInoutH`) inside the domain.
- It is threaded beside `Inv` through `preserve` and the `…Case` results.
- `CapsLive`'s lemmas get memory-only twins (simpler: no liveness).

**`HeldZ`, settled (2026-11-25).** `Z p` is set when `p` is made, by the call (`Z p := z`, the new frame's runtime list), and then never changes. So the clause covers every borrowed parameter, the spine's too, and `Inv.rbindIn` needs nothing.

`HeldZ m Γ Z s` is the conjunction of:
1. **The clause**, for every rootb `p` and held anchor `d` of `p`: `FrameCaps m (Z p) d.root`.
2. **The reach**: for a rootb `p ∉ s.spine`, every `v ∈ s.killVars` satisfies `v ∉ Z p`. `killVars` leaves out the frozen lists, and inside `p`'s `rbind` the statement is the callee's body. This gives `CapInoutH`'s receiver, and `frameCapsSet`'s `hD` (`r.vars ⊆ killVars`), inside the domain.
3. **The catch frames** on the spine, `catchR x m0 _`: for every rootb `p < m0.nv` and held anchor `d`, `FrameCaps (m0.set x) (Z p) d.root`.

`preserve` gets: `∀ Z, HeldZ m Γ Z s → ∃ Z', HeldZ m' Γ' Z' s' ∧ ∀ p E, Γ p = some E → E.mode = .rootb → Z' p = Z p`.

Proved (wip/t937-b4-z, 9961c3798): `FrameCaps` (`set`, `remove`, `mono`, `reads`), `frameCapsSt`, `readsCapsVal` / `readsCapsTgt` / `readsSt_back`, and `frameCapsSet`.

**Frame-clause library, proved (wip/t937-b4-z, f97d17c5d; `FrameClause.lean`, `CapsLive.lean`):**
- `HeldZ`, with `CapInoutH.not_heldZ` and `Step.held_not_killVarsZ`;
- `HeldZ.leaf`;
- the memory-only change lemmas (`FrameCaps.of_changeR` / `repl` / `editNode` / `of_shrink` / `unpair`);
- `frameCapsSet`;
- `MInv.goodOf`: the clause one binding at a time;
- `NamesFree.noMut`;
- `BindParams.frameCaps`.

**Finding:** the call needs no `NoMutLive` from `CallThruOK`. `NamesFree` alone keeps every argument free of a mutating name on a root another argument depends on with no bound (`NamesFree.noMut`). With `MInv.goodOf` this makes every argument clean for the new parameters' anchors, frozen and changed roots alike. `BindParams.frameCaps` then gives the clause on the new frame at `z`, and on old frames at `Z q`, since the arguments are outside `Z q` (`reach`). So `CallThruOK`'s "closure-typed bindings live" may not be needed by the clause at all. Check this when dropping the Rename scaffold.

**Integration, next:**
1. Remove `Inv.heldCaps`, which is false as it stands (`HeldCapsInp`), with `Inv.mk₀` / `ofLeaf`'s clause argument.
2. `preserve` takes `HeldZ m Γ Z s` and returns `∃ Z', HeldZ m' Γ' Z' s'`, with `Z'` agreeing on old borrowed parameters. So do the `…Case` statements.
3. The leaves via `HeldZ.leaf`, with `hc` from the FrameCaps lemmas. Their `hD` comes from `reach` (`r.vars ⊆ killVars`).
4. The wrappers: `frozenIn` / `catchIn` / `rbindIn` keep `Z`; the anchor proofs use `held_not_killVarsZ`.
5. `CallInv`: `Z' := Z[params ↦ z]`; `caps` via `BindParams.frameCaps`; `reach` for the callee body, whose variables are `≥ base` or `inout` arguments, outside `z`.
6. `recCase` opens a catch frame: the `frames` entry from `caps` at that moment.
7. `catchP`: the post store's slots are the snapshot's, so `caps` comes from `frames`.
8. Soundness's initial state: an empty store, so every part holds.

**Integration progress (wip/t937-b4-z), and a fix to `HeldZ.reach` (2026-11-25).** `Inv.heldCaps` is gone.

`preserve` and the `…Case` results now take `HeldZ m Γ Z s` and return `∃ Z', HeldZ m' Γ' Z' s' ∧ ZKeep Γ Z Z'`. Threaded so far:
- `pres_reap`, `sub`, `seq`, `letv`, `letd`, `withLock`, `assign`, `ite`, `while`, `push`;
- `editB` / `editBV`, `withElem`, `takeB` / `takeBV`, `insert`, `free`, the scope exits.

**The fix.** `reach` must speak of a running `rbind`'s parameter too: entering its body (`rbind p k ⟶ k`), the body's names must avoid `Z p`. State it at `s.below p`, the part of `s` under `p`'s `rbind` on the spine, or `s` itself when `p` is off the spine:

`reach : ∀ p E, Γ p = some E → E.mode = .rootb → ∀ v ∈ (s.below p).killVars, v ∉ Z p`

- At the call, `below p` is the callee's body. Its variables are `≥ base`, or `inout` arguments, all outside `z`.
- A leaf has an empty spine, so `below p = s`.
- A wrapper keeps `below` for parameters under it, and it is itself for the rest.
