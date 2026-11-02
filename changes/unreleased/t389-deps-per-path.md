### Fixed

- **A holder kept on one path outlives its source no more** (Agora #389;
  probes holder_kept_*). `( k a t )` gave `a` a view of `t`, then `? > n
  5 { = a @ W { `lit` } } {}` gave it a new value on one path. The walk
  kept one dependency table per function, so that `=` cleared `a`'s
  dependency on `t` for the other path too, and `a` read after `t` ended
  read freed memory. The same held in a `??` arm, a nested `?`, and a
  loop left by `break` before the body's `=`. Dependencies are now joined
  where paths meet, as borrows have been since #311: either path's
  dependency holds past the join.
