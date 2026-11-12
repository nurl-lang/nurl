### Fixed

- **A helper's change through a local holding its parameter ends the caller's views** (Agora #770, #496, #530). Each of these left the caller's view of the parameter's payload or element pointing into freed or moved memory:
  - a helper that put its parameter into a local struct, a Vec or a Box and replaced or grew the payload through it (`: H x @ H { h 1 } ( rc_set . x a … )`, `( vec_push xs h )`, `( box_new h )`), or handed such a local to a replacer;
  - a closure that grew an element of a captured parameter, or cleared a local of its body read out of one;
  - a closure parameter handed an element of the parameter, called with a closure that grows it;
  - a `??` payload of a parameter's element grown in place;
  - a closure rebinding its own parameter and replacing its payload.

  The helper's summary now records each of these, and the caller is refused. A helper that only reads what it wrapped or pushed stays accepted. `NURL_SUMMARY=<fn>` now prints a function's drops, reallocs and ireallocs.

### Known issues

- A helper that wraps an `Rc` parameter into a local struct and then grows ANOTHER field of that struct is taken to change the parameter's payload (the summaries are per local, not per field).
