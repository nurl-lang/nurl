### Fixed

- **A String or Vec owner given what a call may lend out of itself or
  another argument holds the right value on every run** (Agora #419;
  probes string_owner_given_a_call_*, vec_owner_given_a_call_*). Take `=
  o ( pick o other k )`, where `pick` lends either argument. On the run
  that handed back `other`'s value, `o` kept its old ownership flag over
  it, so `o` and `other` both dropped it (heap-use-after-free). The
  hand-over now keeps the old value only when the result is that very
  value, compared by handle key at run time. Otherwise the old value is
  dropped by its flag, and `o` holds the other argument's value as a lend.
  `= o ( id o )` is unchanged.
