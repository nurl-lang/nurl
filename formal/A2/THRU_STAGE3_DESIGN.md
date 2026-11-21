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
- **3b.** The ghost store: `RegionSnap`, building on `Region.lean`'s
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
