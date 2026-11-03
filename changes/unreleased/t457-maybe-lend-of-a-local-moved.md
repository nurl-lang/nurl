### Fixed

- **A binding that may be a lend of a local no longer takes the local's
  value when it moves on** (Agora #457; probes
  string_maybe_lend_of_a_local_*). With `: String x ( maybe o k )`,
  where `maybe` hands back `o` on one run and a fresh String on another,
  handing `x` to a `sink`, pushing it, returning it, storing it in a
  literal or a field, returning it through a join, or capturing it in a
  returned closure leaked `o` (or the copy of `x`) on one of the runs.
  Now `x` is its own value where the call says so and a copy where it
  lent, and `o` always drops its own.
