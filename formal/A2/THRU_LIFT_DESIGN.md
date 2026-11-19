# A2-thru-lift — a through-changing callee called with an argument holding views (AGORA-932)

## Status

**Not typed yet.** `CallT` asks `ThruFn P f → callR Γ args = []`. A call
into a function that changes elements through a borrow, or that calls one
that does, passes no argument holding views.
`A2/HeldViewThruWitness.lean` (AGORA-933) shows that this refuses both of
AGORA-933's shapes. nurlc refuses them too (github#2100), and ends the
caller's views after `( f vv )`. So the gap is one of precision: nurlc
accepts nothing here that A2 refuses.

`A2/ThruLiftKinds.lean` proves the facts below on Lean's standard axioms
only.

## Why the lift does not carry over

`Rename` types a callee's body where the call places it. Its edit cases
prove an **equality**: the lifted context after the body's change is the
change, lifted, of the lifted context. With `callR Γ args = []`, the lift
adds only names to a borrow's path (`memDeps S.A = []`), so both sides
kill the same renamed roots. With an argument holding views, three things
break.

1. **The lift is coarse.** `liftE` adds the whole `S.A`, everything every
   argument holds, to every lifted borrow that is not fresh and to every
   lifted owner. A change that reaches a caller root `r` held by argument
   `j` then also ends the lifted bindings that came from other arguments
   or from the callee's own locals. The body still reads those, so the
   lifted body does not type at the caller. Names are immune to this,
   since `Eff.kills e _ (.name _ _) = false` below `.replace`. That is why
   `S.N` never needed more.
2. **The kinds do not compose exactly.** A per-parameter lift composes an
   argument's kind `a` on `r` with the callee's kinds on the parameter
   (`comp a k`).
   - Through the root's own handle (`a = .self`) the caller kills exactly
     what the callee does (`kills_comp_self`).
   - Through a view or an element hop it kills more:
     `comp_view_overkills`, `comp_inner_overkills`, and
     `comp_inner_push_overkills`, which is AGORA-933's shape. A push
     reallocates the parameter in the callee, which keeps a borrow of an
     element's inside live, but in the caller it is a drop of `r`, which
     ends it.
   - Killing every kind on the parameter covers whatever the caller kills
     (`replace_covers`).
3. **A move erases provenance.** A `sink` or `inout` parameter holds
   nothing the body sees (`paramE`: `held = []`). After a move out of the
   parameter, the new owner holds what the argument held at run time, but
   has no dependency on the parameter. A lift keyed by "the entry's deps on
   parameter `p`" would add nothing to it, which is unsound. The coarse
   `S.A` covers it only because every lifted owner gets all of it.

What does carry over is ending the frame's views of the changed roots at
the call. The callee cannot reach the frame, and a later kill of any
effect on `r` ends nothing more there (`kill_after_replace`). The same
pattern already holds for names (`RSetup.OK.N_mut`'s last clause).

## What typing it would take

- **Symbolic memory provenance for parameters**, the analogue of `sym` for
  names. `paramE` gives a parameter whose type holds views a symbolic
  dependency on itself, which moves, copies and borrows carry. The lift
  maps each symbolic dependency on `p` to what argument `p` holds. That
  replaces `S.A` in `liftE` and `heldA`.
- **At the caller, a change through a parameter kills every kind on it**
  (`replace_covers`), or only through a hop that is not `.self`
  (`kills_comp_self`).
- **The frame's views of the changed roots end at the call**
  (`kill_after_replace`), and `CallT`'s premise names the changed
  argument's roots `Rj`:
  - they are allowed and not frozen;
  - no other argument depends on them in memory;
  - no dependency on them goes through a share.

This changes `sigCtx` and every rule that reads a parameter's `held`, not
only `Rename`. It is a calculus change of the size of AGORA-441 (ownership
signatures checked at definition), and belongs with it.
