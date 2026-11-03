### Fixed

- **A `??` written as another `??`'s arm without braces keeps what its arms
  view** (Agora #452; probe qq_value_arm_that_is_an_unbraced_inner_join).
  In `= a ?? o { T m → @ W { `lit` } F → ?? o2 { T k → @ W { `l2` } F → b }
  }`, with `b` viewing a block local, the outer join took the inner join to
  view nothing, so `a` was kept past the local and read freed memory. The
  braced form was already refused, and so is this one now.
