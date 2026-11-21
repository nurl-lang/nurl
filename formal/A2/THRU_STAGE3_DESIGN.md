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
     *Done, structurally:* `RSetup.ghost` exists, and `AbsOK`'s fourth clause
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

## Open questions for review

1. Does lifting a lent parameter's region keep `liftE`'s `.rootb` case's
   other duties (the caller's `pe`, `rootbLive`)? Or should a lent parameter
   holding views become a `.bor` binding of its argument in the lift?
2. Is the entry kill better stated on the combined context at `callMem` time
   (`CallH.minv`), or as a `CallPre` context the call steps through?
3. Is a depth-aware `.drop` worth adding before 3d, so that `sw` and `vv`
   stay live after the call as in nurlc? Or is that a precision follow-up?
