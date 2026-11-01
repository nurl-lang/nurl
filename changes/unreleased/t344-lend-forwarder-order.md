### Fixed

- **An owner given a value a forwarder lends drops its old value whatever
  order the functions are defined in** (Agora #344). `= o ( first vs )`,
  with `first` handing back `vec_get`'s lend, kept `o`'s old value back
  and leaked it when `first` was defined above its caller. Its lend
  summary was final only at module end, so the assignment could not tell
  the lend came from `vs` and not from `o`. Defined below, the call's
  ownership bit decided and nothing leaked. A lend comes out of an
  argument, so when every argument is an owner other than `o`, the old
  value now goes by its flag in both orders.
