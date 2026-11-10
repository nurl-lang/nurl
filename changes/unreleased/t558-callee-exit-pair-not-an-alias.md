### Fixed

- **A callee that points its `inout` holder at another argument at its
  exit is no longer refused for it** (Agora #558). `( f w s )`, where `f`
  points `w` at the `inout` String `s`, grows `s`, and points `w` at it
  again before it returns, was refused at the caller: "'s' reaches 'f'
  through argument 2 … and through argument 1, which points into it".
  The walk applied what `f` leaves `w` viewing at its exit (its `vpass`
  rows) before the exclusive-call check, which then took that for an
  alias the arguments had going in. Then the growth of `s` ended the
  view `f` itself made. A call's own `vpass` rows now come after its
  checks (`callx`, `clox`, `arcx`). For the outermost call of a
  statement they also come after its pending call rows. A call nested in
  another call's arguments keeps its rows ahead of the enclosing call's
  checks, so `( k ( f w s ) w s )` stays refused. A holder that already views `s` when the call is entered
  is still refused.
