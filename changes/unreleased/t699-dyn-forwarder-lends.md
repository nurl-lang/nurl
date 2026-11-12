### Fixed

- **A function that hands back a `dyn` method's result lends what the
  method's impls lend** (Agora #699). `@ viaobj %Src o ( Vec S ) v → S
  { ^ ( first o v ) }`, with an impl of `first` returning
  `( vec_at [S] v 0 )`, lent nothing, so a caller that cleared its `Vec`
  and then read the result read freed memory. The same call made directly
  was refused already. The forwarder now lends `v`: the result bound
  first, two impls of which one is fresh, and a forwarder of a forwarder
  are refused the same way.
