### Fixed

- **A binding that may be a lend of a local no longer takes the local's
  value when it moves on** (Agora #457; probes
  string_maybe_lend_of_a_local_*). With `: String x ( maybe o k )`,
  where `maybe` hands back `o` on one run and a fresh String on another,
  handing `x` to a `sink`, pushing it (also inside a literal), capturing
  it in a returned closure, or handing it to a keeper such as `rc_new`
  leaked `o` on the run that handed back the fresh value. Now `x` is its
  own value where the call says so and a copy where it lent, and `o`
  always drops its own.
